"""
End-to-end WebSocket delivery, against the real backend + Redis.

`tests/test_realtime_fanout.py` covers the audience arithmetic in isolation.
This covers the part that was actually broken: whether an event published by a
router ever reaches a connected socket.

The bug this guards against shipped silently. Class-wide events were addressed
as `{"target_type": "grade", "grade": N}` and resolved through an index in the
WebSocket manager that nothing ever populated — `register_grade()` had no
callers and `/ws/{user_id}` connects without a grade — so the fan-out resolved
to the empty set every time and Redis dutifully delivered it to nobody. Every
unit test still passed, because the units were all individually correct.

The same change scoped delivery to one school. `broadcast_all` previously hit
every socket on the instance, so a school-wide broadcast leaked to other
tenants; `test_broadcast_does_not_leak_to_another_school` is the regression
guard for that.

Note that the leak test asserts an *absence*, so on its own it would also pass
if delivery were broken outright — which is the exact failure mode this file
exists to catch. It is only meaningful next to the positive tests above it:
those prove events are delivered, this one proves they are delivered *narrowly*.
Keep them together.

Verified by falsification: reverting `send_broadcast` to the old
`target_type: "grade"` publish makes the two broadcast tests fail and leaves
the homework test passing (a separate call site), which is the expected shape.
"""

import asyncio
import json
import os

import asyncpg
import pytest
import websockets
from jose import jwt

from .conftest import BASE_URL, DB_DSN, PREFIX, TEST_MPIN, auth, login

WS_BASE = BASE_URL.replace("http://", "ws://").replace("https://", "wss://")

# The backend validates the WS token against its own JWT_SECRET, so the test
# has to sign with the same one the container was started with.
JWT_SECRET = os.environ.get("MF_TEST_JWT_SECRET") or ""
if not JWT_SECRET:
    for line in open(
        os.path.join(os.path.dirname(__file__), "..", "..", ".env.local"),
        encoding="utf-8",
    ):
        if line.startswith("JWT_SECRET="):
            JWT_SECRET = line.split("=", 1)[1].strip().strip("'\"")
            break

# How long to wait for an event that should arrive. Generous: it crosses the
# app, Redis pub/sub, the subscriber task and back out over the socket.
RECV_TIMEOUT = 8.0
# How long to wait before concluding an event should NOT arrive. Shorter, but
# still well past the round trip measured above.
SILENCE_TIMEOUT = 4.0


def _mint_access_token(user_id: int) -> str:
    """Sign an access token the way app.core.security does.

    The students these fixtures create are inserted straight into the database
    with a placeholder MPIN hash and cannot log in, so there is no password
    flow to borrow a token from.
    """
    from datetime import datetime, timedelta, timezone
    import uuid

    return jwt.encode(
        {
            "sub": str(user_id),
            "exp": datetime.now(timezone.utc) + timedelta(minutes=30),
            "type": "access",
            "jti": str(uuid.uuid4()),
        },
        JWT_SECRET,
        algorithm="HS256",
    )


def _connect(user_id: int, token: str):
    """Return the `connect()` awaitable-and-context-manager.

    Not awaited here on purpose: `websockets.connect(...)` is itself the async
    context manager, and awaiting it first hands back a protocol object that
    is not one.
    """
    return websockets.connect(
        f"{WS_BASE}/ws/{user_id}?token={token}", open_timeout=10
    )


async def _collect(ws, timeout: float) -> list[dict]:
    """Drain events until `timeout` elapses with nothing new arriving."""
    events = []
    try:
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
            if raw == "pong":
                continue
            try:
                events.append(json.loads(raw))
            except json.JSONDecodeError:
                pass
    except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
        pass
    return events


def _events_of(events: list[dict], name: str) -> list[dict]:
    return [e for e in events if e.get("event") == name]


@pytest.fixture(scope="module")
def teacher_user_ids(two_schools):
    """user_id for each school's teacher — needed to address the socket."""
    async def _fetch():
        conn = await asyncpg.connect(DB_DSN)
        try:
            out = {}
            for tag in ("a", "b"):
                out[tag] = await conn.fetchval(
                    "SELECT id FROM users WHERE username = $1 AND school_id = $2",
                    f"{PREFIX}_teacher_{tag}",
                    two_schools[tag]["id"],
                )
            return out
        finally:
            await conn.close()

    ids = asyncio.run(_fetch())
    for tag, uid in ids.items():
        assert uid is not None, f"could not resolve teacher {tag} user id"
    return ids


def test_grade_broadcast_reaches_the_grades_students(
    api, two_schools, students, teacher_user_ids
):
    """A grade-targeted broadcast must arrive on a student's socket.

    Before the fix this delivered to nobody at all.
    """
    student_id = students["a"]

    async def scenario():
        async with _connect(student_id, _mint_access_token(student_id)) as ws:
            await asyncio.sleep(0.5)  # let the manager register the connection
            r = api.post(
                "/api/teacher/broadcast",
                headers=auth(two_schools["a"]["teacher_token"]),
                json={
                    "title": f"{PREFIX} grade note",
                    "message": "grade-targeted",
                    "target_type": "grade",
                    "target_grade": 8,
                },
            )
            assert r.status_code == 201, r.text
            return await _collect(ws, RECV_TIMEOUT)

    received = _events_of(asyncio.run(scenario()), "message_broadcast")
    assert received, "student received no message_broadcast for their own grade"
    assert received[0]["title"] == f"{PREFIX} grade note"


def test_grade_broadcast_also_reaches_staff(api, two_schools, teacher_user_ids):
    """Teachers share the school-wide announcement list, so a grade-targeted
    broadcast has to reach them too regardless of grade (`include_staff`)."""
    teacher_id = teacher_user_ids["a"]

    async def scenario():
        async with _connect(teacher_id, _mint_access_token(teacher_id)) as ws:
            await asyncio.sleep(0.5)
            r = api.post(
                "/api/teacher/broadcast",
                headers=auth(two_schools["a"]["teacher_token"]),
                json={
                    "title": f"{PREFIX} staff note",
                    "message": "staff should see this",
                    "target_type": "grade",
                    "target_grade": 8,
                },
            )
            assert r.status_code == 201, r.text
            return await _collect(ws, RECV_TIMEOUT)

    received = _events_of(asyncio.run(scenario()), "message_broadcast")
    assert received, "teacher received no message_broadcast"
    assert received[0]["title"] == f"{PREFIX} staff note"


def test_new_homework_reaches_students_and_staff(
    api, two_schools, students, teacher_user_ids
):
    """`homework_added` was one of the seven grade-targeted events being
    dropped. Both the grade's students and the school's staff must get it."""
    student_id = students["a"]
    teacher_id = teacher_user_ids["a"]

    async def scenario():
        async with _connect(student_id, _mint_access_token(student_id)) as s_ws:
            async with _connect(teacher_id, _mint_access_token(teacher_id)) as t_ws:
                await asyncio.sleep(0.5)
                r = api.post(
                    "/api/teacher/homework",
                    headers=auth(two_schools["a"]["teacher_token"]),
                    json={
                        "grade": 8,
                        "subject": "Physics",
                        "title": f"{PREFIX} realtime hw",
                        "homework_type": "written",
                    },
                )
                assert r.status_code in (200, 201), r.text
                return await asyncio.gather(
                    _collect(s_ws, RECV_TIMEOUT), _collect(t_ws, RECV_TIMEOUT)
                )

    student_events, teacher_events = asyncio.run(scenario())
    assert _events_of(student_events, "homework_added"), \
        "student received no homework_added"
    assert _events_of(teacher_events, "homework_added"), \
        "teacher received no homework_added"


def test_broadcast_does_not_leak_to_another_school(
    api, two_schools, teacher_user_ids
):
    """A school-wide broadcast must not reach a different school's users.

    This is the tenancy half of the fix: the old path called `broadcast_all`,
    which fanned out to every socket on the instance.
    """
    outsider_id = teacher_user_ids["b"]

    async def scenario():
        async with _connect(outsider_id, _mint_access_token(outsider_id)) as ws:
            await asyncio.sleep(0.5)
            r = api.post(
                "/api/teacher/broadcast",
                headers=auth(two_schools["a"]["teacher_token"]),
                json={
                    "title": f"{PREFIX} school A only",
                    "message": "must not cross schools",
                    "target_type": "all",
                },
            )
            assert r.status_code == 201, r.text
            return await _collect(ws, SILENCE_TIMEOUT)

    leaked = _events_of(asyncio.run(scenario()), "message_broadcast")
    assert not leaked, (
        f"school B user received school A's broadcast: {leaked}"
    )


def test_timetable_config_reaches_own_school(
    api, two_schools, students
):
    """An admin's timetable-config change must reach that school's users.

    `timetable_config_updated` used to be published with `target_type:
    "broadcast"`, so it both leaked to other schools (below) and — once the
    grade index was found to be dead — this positive case has to be pinned too,
    so a future "fix" can't scope it down to nobody.
    """
    student_id = students["a"]

    async def scenario():
        async with _connect(student_id, _mint_access_token(student_id)) as ws:
            await asyncio.sleep(0.5)
            r = api.put(
                "/api/admin/timetable/config",
                headers=auth(two_schools["a"]["admin_token"]),
                json={"periods_per_day": 8},
            )
            assert r.status_code in (200, 201), r.text
            return await _collect(ws, RECV_TIMEOUT)

    got = _events_of(asyncio.run(scenario()), "timetable_config_updated")
    assert got, "student received no timetable_config_updated for own school"


def test_timetable_config_does_not_leak_to_another_school(
    api, two_schools, teacher_user_ids
):
    """The tenancy half: school A's timetable-config change must not reach a
    school B user. Regression guard for the `broadcast_all` leak at
    admin.py:update_timetable_config."""
    outsider_id = teacher_user_ids["b"]

    async def scenario():
        async with _connect(outsider_id, _mint_access_token(outsider_id)) as ws:
            await asyncio.sleep(0.5)
            r = api.put(
                "/api/admin/timetable/config",
                headers=auth(two_schools["a"]["admin_token"]),
                json={"periods_per_day": 9},
            )
            assert r.status_code in (200, 201), r.text
            return await _collect(ws, SILENCE_TIMEOUT)

    leaked = _events_of(asyncio.run(scenario()), "timetable_config_updated")
    assert not leaked, (
        f"school B user received school A's timetable_config_updated: {leaked}"
    )
