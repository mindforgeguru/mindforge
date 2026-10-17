"""
Cutting the number of periods removes the periods that no longer exist.

Both of the teacher's screens draw only `periods_per_day` periods, but the
attendance step expects every period scheduled today. After an admin cut the day
from 8 periods to 6, a period-8 slot already scheduled was invisible — it could
not be deleted, or have attendance taken — yet still expected, so the day could
not be finished. Found 2026-10-17. Slots beyond the new count are now removed
from today on; past days keep theirs as history.
"""

import asyncio
from datetime import timedelta

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login, register


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _today():
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.now(ZoneInfo("Asia/Kolkata")).date()


@pytest.fixture(scope="module")
def shrunk(api, owner_token):
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest Periods {RUN_ID}", "slug": f"{PREFIX}-periods"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin_name = f"{PREFIX}_admin_periods"
    api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
             json={"username": admin_name, "mpin": TEST_MPIN})
    admin = auth(login(api, admin_name, school_id=sid))
    api.post("/api/admin/academic-years/init", headers=admin)
    assert api.put("/api/admin/timetable/config", headers=admin,
                   json={"periods_per_day": 8}).status_code == 200

    teacher_name = f"{PREFIX}_periods_t"
    assert register(api, username=teacher_name, mpin=TEST_MPIN, role="teacher", school_id=sid,
                    phone=f"83{RUN_ID[:5].translate(str.maketrans('abcdef', '123456'))}11").status_code == 201
    for u in api.get("/api/admin/users/pending", headers=admin).json():
        api.post(f"/api/admin/users/{u['id']}/approve", headers=admin)
    teacher = auth(login(api, teacher_name, school_id=sid))
    asyncio.run(_make_student(sid, f"{PREFIX}_periods_s"))

    today, tomorrow, yesterday = _today(), _today() + timedelta(days=1), _today() - timedelta(days=1)
    for day, period in ((today, 2), (today, 8), (tomorrow, 7)):
        r = api.post("/api/teacher/timetable", headers=teacher,
                     json={"grade": 8, "slot_date": day.isoformat(), "period_number": period,
                           "subject": "maths"})
        assert r.status_code == 200, r.text
    asyncio.run(_sql("INSERT INTO timetable_slots (grade, slot_date, period_number, subject, "
                     "is_holiday, school_id) VALUES (8, $1, 8, 'maths', false, $2)", yesterday, sid))

    assert api.put("/api/admin/timetable/config", headers=admin,
                   json={"periods_per_day": 6}).status_code == 200
    return {"sid": sid, "teacher": teacher, "today": today, "tomorrow": tomorrow, "yesterday": yesterday}


def _slot_count(sid, day, period):
    return asyncio.run(_sql("SELECT count(*) FROM timetable_slots WHERE school_id = $1 "
                            "AND slot_date = $2 AND period_number = $3", sid, day, period))


def test_periods_past_the_new_count_are_gone_from_today_on(shrunk):
    assert _slot_count(shrunk["sid"], shrunk["today"], 8) == 0
    assert _slot_count(shrunk["sid"], shrunk["tomorrow"], 7) == 0


def test_the_periods_that_remain_and_past_days_are_kept(shrunk):
    assert _slot_count(shrunk["sid"], shrunk["today"], 2) == 1
    assert _slot_count(shrunk["sid"], shrunk["yesterday"], 8) == 1


def test_attendance_no_longer_expects_the_removed_period(api, shrunk):
    r = api.get("/api/teacher/today-workflow", headers=shrunk["teacher"])
    assert r.status_code == 200, r.text
    assert r.json()["grades"][0]["expected_periods"] == [2]
