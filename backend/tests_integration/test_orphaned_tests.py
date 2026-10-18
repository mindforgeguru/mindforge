"""
A test whose teacher has left can be looked after by the teachers who remain.

Every operation on a test — details, questions, publish, PDFs, offline marks,
delete — was for its creator only, and the admin has no test screens. When a
teacher was removed mid-year their open tests could not be unpublished, their
offline tests could not be marked, and their submissions could not be seen by
anyone. Found 2026-10-18. A colleague may now act on a test whose creator is no
longer an active account; an active teacher's tests stay theirs alone.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, auth


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _make_teacher(school_id, name, removed):
    return asyncio.run(_sql(
        """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved, deleted_at)
           VALUES ($1, 'x', 'teacher', $2, $3, true, CASE WHEN $3 THEN NULL ELSE now() END)
           RETURNING id""", name, school_id, not removed))


def _test(school_id, teacher_id, kind="offline"):
    return asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, school_id)
           VALUES ($1, $2, 8, 'maths', $3, '[]'::json, 10, 10, true, $4) RETURNING id""",
        f"{PREFIX} orphan {kind} {teacher_id}", teacher_id, kind, school_id))


@pytest.fixture(scope="module")
def tests(two_schools):
    sid = two_schools["a"]["id"]
    gone = _make_teacher(sid, f"{PREFIX}_orph_gone", removed=True)
    here = _make_teacher(sid, f"{PREFIX}_orph_here", removed=False)
    return {"orphan": _test(sid, gone), "colleague": _test(sid, here),
            "headers": auth(two_schools["a"]["teacher_token"])}


def test_a_colleague_can_see_and_unpublish_an_orphaned_test(api, tests):
    h = tests["headers"]
    assert api.get(f"/api/teacher/tests/{tests['orphan']}", headers=h).status_code == 200
    r = api.post(f"/api/teacher/tests/{tests['orphan']}/publish", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["is_published"] is False


def test_an_active_teachers_test_stays_theirs(api, tests):
    h = tests["headers"]
    assert api.get(f"/api/teacher/tests/{tests['colleague']}", headers=h).status_code == 404
    assert api.post(f"/api/teacher/tests/{tests['colleague']}/publish", headers=h).status_code in (403, 404)
