"""An MPIN change or reset has to end the sessions that existed before it.

Recovery here is admin-mediated: a student whose MPIN leaks asks the admin for
a new one. If the tokens minted with the old MPIN keep working, the reset locks
out nobody — the attacker's refresh token rotates on for its full 30 days.

Each test makes its own student so revoking that student's sessions can't
disturb the shared session fixtures other modules read from.
"""

import asyncio

import asyncpg
import bcrypt
import websockets

from .conftest import BASE_URL, DB_DSN, PREFIX, TEST_MPIN, auth

NEW_MPIN = "592814"


async def _insert_student(school_id: int, username: str) -> int:
    conn = await asyncpg.connect(DB_DSN)
    try:
        mpin_hash = bcrypt.hashpw(TEST_MPIN.encode(), bcrypt.gensalt()).decode()
        uid = await conn.fetchval(
            """
            INSERT INTO users (username, mpin_hash, role, school_id,
                               is_active, is_approved)
            VALUES ($1, $2, 'student', $3, true, true)
            RETURNING id
            """,
            username,
            mpin_hash,
            school_id,
        )
        await conn.execute(
            "INSERT INTO student_profiles (user_id, grade, school_id) VALUES ($1, 8, $2)",
            uid,
            school_id,
        )
        return uid
    finally:
        await conn.close()


def _student(two_schools, tag, name):
    sid = two_schools[tag]["id"]
    username = f"{PREFIX}_rev_{name}"
    uid = asyncio.run(_insert_student(sid, username))
    return {"id": uid, "username": username, "school_id": sid}


def _session(api, student, mpin=TEST_MPIN):
    r = api.post(
        "/api/auth/login",
        json={"username": student["username"], "mpin": mpin, "school_id": student["school_id"]},
    )
    assert r.status_code == 200, f"login failed: {r.text}"
    body = r.json()
    return body["access_token"], body["refresh_token"]


def _access_ok(api, token):
    return api.get("/api/student/profile", headers=auth(token)).status_code == 200


def _refresh_status(api, refresh_token):
    return api.post("/api/auth/refresh", json={"refresh_token": refresh_token}).status_code


def _admin_reset(api, two_schools, student, tag="a"):
    return api.put(
        f"/api/admin/users/{student['id']}",
        headers=auth(two_schools[tag]["admin_token"]),
        json={"new_mpin": NEW_MPIN},
    )


# ── Admin reset ──────────────────────────────────────────────────────────────


def test_admin_reset_revokes_existing_access_token(api, two_schools):
    student = _student(two_schools, "a", "reset_access")
    access, _ = _session(api, student)
    assert _access_ok(api, access), "precondition: fresh token should work"

    assert _admin_reset(api, two_schools, student).status_code == 200

    assert not _access_ok(api, access), "access token minted before the reset still works"


def test_admin_reset_revokes_existing_refresh_token(api, two_schools):
    student = _student(two_schools, "a", "reset_refresh")
    _, refresh = _session(api, student)

    assert _admin_reset(api, two_schools, student).status_code == 200

    assert _refresh_status(api, refresh) == 401, (
        "refresh token minted before the reset can still mint new sessions"
    )


def test_login_with_new_mpin_works_after_reset(api, two_schools):
    """The revocation must not also lock out the rightful owner."""
    student = _student(two_schools, "a", "reset_relogin")
    _session(api, student)
    assert _admin_reset(api, two_schools, student).status_code == 200

    access, refresh = _session(api, student, mpin=NEW_MPIN)
    assert _access_ok(api, access)
    assert _refresh_status(api, refresh) == 200


def test_editing_without_mpin_leaves_sessions_alone(api, two_schools):
    """Only an MPIN reset revokes. A phone-number edit logging the student out
    everywhere would be a bug of its own."""
    student = _student(two_schools, "a", "edit_no_mpin")
    access, _ = _session(api, student)

    r = api.put(
        f"/api/admin/users/{student['id']}",
        headers=auth(two_schools["a"]["admin_token"]),
        json={"email": "someone@example.com"},
    )
    assert r.status_code == 200, r.text

    assert _access_ok(api, access)


def test_admin_cannot_reset_another_schools_student(api, two_schools):
    student = _student(two_schools, "a", "cross_tenant")
    access, _ = _session(api, student)

    r = _admin_reset(api, two_schools, student, tag="b")

    assert r.status_code == 404, r.text
    assert _access_ok(api, access), "cross-tenant attempt must not revoke anything"
    _session(api, student)  # old MPIN still valid


def test_admin_cannot_reset_to_a_weak_mpin(api, two_schools):
    student = _student(two_schools, "a", "weak_mpin")
    r = api.put(
        f"/api/admin/users/{student['id']}",
        headers=auth(two_schools["a"]["admin_token"]),
        json={"new_mpin": "123456"},
    )
    assert r.status_code == 422, r.text


# ── Self-service change ──────────────────────────────────────────────────────


def test_self_change_revokes_other_sessions(api, two_schools):
    """Changing your MPIN because you think it leaked must kick the intruder."""
    student = _student(two_schools, "a", "self_change")
    mine, _ = _session(api, student)
    theirs_access, theirs_refresh = _session(api, student)

    r = api.put(
        "/api/student/profile/mpin",
        headers=auth(mine),
        json={"current_mpin": TEST_MPIN, "new_mpin": NEW_MPIN},
    )
    assert r.status_code == 200, r.text

    assert not _access_ok(api, theirs_access), "other session's access token survived"
    assert _refresh_status(api, theirs_refresh) == 401, "other session's refresh token survived"


def test_self_change_hands_back_a_working_session(api, two_schools):
    """The caller's own tokens are revoked with the rest, so the response has to
    carry replacements or the user is logged out by changing their MPIN."""
    student = _student(two_schools, "a", "self_keep")
    mine, _ = _session(api, student)

    r = api.put(
        "/api/student/profile/mpin",
        headers=auth(mine),
        json={"current_mpin": TEST_MPIN, "new_mpin": NEW_MPIN},
    )
    assert r.status_code == 200, r.text
    body = r.json()

    assert _access_ok(api, body["access_token"])
    assert _refresh_status(api, body["refresh_token"]) == 200


# ── Realtime ─────────────────────────────────────────────────────────────────


def _ws_accepts(user_id, token) -> bool:
    """True when the handshake completes and the socket answers a ping."""
    url = BASE_URL.replace("http://", "ws://").replace("https://", "wss://")

    async def attempt():
        try:
            async with websockets.connect(
                f"{url}/ws/{user_id}?token={token}", open_timeout=10
            ) as ws:
                await ws.send("ping")
                return await asyncio.wait_for(ws.recv(), 5) == "pong"
        except (websockets.exceptions.InvalidStatus, websockets.exceptions.ConnectionClosed):
            return False

    return asyncio.run(attempt())


def test_revoked_token_cannot_open_a_realtime_socket(api, two_schools):
    """The socket authenticates separately from the HTTP dependency, so it
    needs the same check — or a revoked session keeps receiving live events."""
    student = _student(two_schools, "a", "ws")
    access, _ = _session(api, student)
    assert _ws_accepts(student["id"], access), "precondition: fresh token should connect"

    assert _admin_reset(api, two_schools, student).status_code == 200

    assert not _ws_accepts(student["id"], access), "revoked token still opens a socket"
