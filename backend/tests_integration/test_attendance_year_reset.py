"""
Attendance stats start fresh each academic year.

Tests, homework and broadcasts already drop away at a year close (they filter
on `since(... year_started_at)`), but the attendance summary and the class
leaderboard counted every row ever written. After a close, last year's
attendance still set this year's percentage and ranking (found 2026-10-18) —
the opposite of the "new student sees nothing from last year" promise the rest
of the app keeps. Both now count only rows created since the year began. The
raw record list is deliberately left whole: it is a history browser, and the
Previous-Years rows stay in the database by design.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth
from .test_realtime_delivery import _mint_access_token


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


async def _mark(student_id, teacher_id, grade, sid, day, status, created_at):
    from datetime import date as _date, datetime as _dt, timezone as _tz
    conn = await asyncpg.connect(DB_DSN)
    try:
        await conn.execute(
            """INSERT INTO attendance (student_id, teacher_id, grade, period, date,
                                       status, school_id, created_at)
               VALUES ($1, $2, $3, 1, $4, $5, $6, $7)""",
            student_id, teacher_id, grade, _date.fromisoformat(day), status, sid,
            _dt.fromisoformat(created_at.replace("Z", "+00:00")).astimezone(_tz.utc))
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def student_across_years(two_schools):
    school = two_schools["a"]
    sid = school["id"]
    grade = 9
    me = asyncio.run(_make_student(sid, f"{PREFIX}_ay_me", grade=grade, new=True))
    # The current year started 30 days ago (conftest backdates it). Put two
    # "present" rows this year and three "absent" rows well before the start.
    asyncio.run(_mark(me, school["teacher_id"], grade, sid, "2026-10-10", "present", "2026-10-10T04:00:00Z"))
    asyncio.run(_mark(me, school["teacher_id"], grade, sid, "2026-10-11", "present", "2026-10-11T04:00:00Z"))
    for day in ("2026-01-10", "2026-01-11", "2026-01-12"):
        asyncio.run(_mark(me, school["teacher_id"], grade, sid, day, "absent", f"{day}T04:00:00Z"))
    return {"token": auth(_mint_access_token(me)), "id": me}


def test_the_summary_counts_only_this_year(api, student_across_years):
    r = api.get("/api/student/attendance/summary", headers=student_across_years["token"])
    assert r.status_code == 200, r.text
    body = r.json()
    # Only the two present rows from this year — not the three absent ones from
    # before the year began.
    assert body["total_classes"] == 2, body
    assert body["present_count"] == 2, body
    assert body["attendance_percentage"] == 100.0, body


def test_the_leaderboard_counts_only_this_year(api, student_across_years):
    r = api.get("/api/student/attendance/class-leaderboard", headers=student_across_years["token"])
    assert r.status_code == 200, r.text
    me = next((row for row in r.json() if row["student_id"] == student_across_years["id"]), None)
    assert me is not None, r.json()
    assert me["attendance_percentage"] == 100.0, me


def test_the_record_list_still_shows_history(api, student_across_years):
    # The browsable list is intentionally not year-scoped.
    r = api.get("/api/student/attendance", headers=student_across_years["token"],
                params={"limit": 200})
    assert r.status_code == 200, r.text
    assert len(r.json()) == 5, r.json()
