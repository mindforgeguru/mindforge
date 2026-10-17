"""
A missed test is a zero only for a student who could have taken it.

When an online test expires, a sweep gives a score-0 submission (and a grade)
to every student in the grade who never opened it. "Every student" was every
student profile in the grade — so on 2026-10-17, after a year close, a student
who registered this year got a 0 in their marks for last year's test, and the
removed student from last year got one too. Removed students also kept the test
from ever counting as fully graded, and stayed on the attendance leaderboard.

Now the zero goes to live, approved students whose account existed while the
test was open.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login
from .test_realtime_delivery import _mint_access_token

QUESTIONS = [{"id": 1, "type": "mcq", "marks": 1, "answer": "A", "question": "Pick A",
              "options": {"A": "Right", "B": "Wrong", "C": "Wrong", "D": "Wrong"}}]


async def _sql(query, *args, fetch="val"):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await (conn.fetchval if fetch == "val" else conn.fetch)(query, *args)
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def rollover(api, owner_token):
    """A school of its own: a test that expired yesterday; a student who was
    there, one removed since, and one who joined after it closed."""
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest Missed {RUN_ID}", "slug": f"{PREFIX}-missed"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin = f"{PREFIX}_admin_missed"
    assert api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
                    json={"username": admin, "mpin": TEST_MPIN}).status_code == 201
    admin_id = asyncio.run(_sql("SELECT id FROM users WHERE username = $1", admin))

    there = asyncio.run(_make_student(sid, f"{PREFIX}_m_there"))
    removed = asyncio.run(_make_student(sid, f"{PREFIX}_m_removed"))
    joined = asyncio.run(_make_student(sid, f"{PREFIX}_m_joined", new=True))

    async def setup():
        await _sql("UPDATE users SET created_at = now() - interval '10 days' WHERE id = ANY($1::int[])",
                   [there, removed])
        await _sql("UPDATE users SET deleted_at = now(), is_active = false, is_approved = false "
                   "WHERE id = $1", removed)
        await _sql("""INSERT INTO attendance (student_id, grade, period, date, status, school_id)
                      VALUES ($1, 8, 1, current_date - 3, 'present', $3),
                             ($2, 8, 1, current_date - 3, 'present', $3)""", there, removed, sid)
        return await _sql(
            """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                                  time_limit_minutes, is_published, expires_at, school_id, created_at)
               VALUES ($1, $2, 8, 'maths', 'online', $3::json, 1, 10, true,
                       now() - interval '1 day', $4, now() - interval '5 days') RETURNING id""",
            f"{PREFIX} missed", admin_id, json.dumps(QUESTIONS), sid)

    test_id = asyncio.run(setup())
    # Any student's test list runs the sweep for their grade.
    r = api.get("/api/student/tests/completed", headers=auth(_mint_access_token(joined)))
    assert r.status_code == 200, r.text
    return {"test": test_id, "there": there, "removed": removed, "joined": joined}


def _zeroed(rollover):
    rows = asyncio.run(_sql("SELECT student_id FROM grades WHERE test_id = $1",
                            rollover["test"], fetch="rows"))
    return {r["student_id"] for r in rows}


def test_the_student_who_was_there_gets_the_zero(rollover):
    assert rollover["there"] in _zeroed(rollover)


def test_a_student_who_joined_after_it_closed_does_not(api, rollover):
    assert rollover["joined"] not in _zeroed(rollover)
    r = api.get("/api/student/grades", headers=auth(_mint_access_token(rollover["joined"])))
    assert all(g["test_id"] != rollover["test"] for g in r.json())


def test_a_removed_student_does_not(rollover):
    assert rollover["removed"] not in _zeroed(rollover)


def test_the_test_counts_as_fully_graded(rollover):
    assert asyncio.run(_sql("SELECT is_graded FROM tests WHERE id = $1", rollover["test"]))


def test_a_removed_student_is_off_the_attendance_leaderboard(api, rollover):
    r = api.get("/api/student/attendance/class-leaderboard",
                headers=auth(_mint_access_token(rollover["there"])))
    assert r.status_code == 200, r.text
    ids = {row["student_id"] for row in r.json()}
    assert rollover["there"] in ids
    assert rollover["removed"] not in ids
