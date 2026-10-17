"""
Correcting a mark takes back the XP the mark gave.

Marking a student present awards attendance XP, and marking homework done
awards homework XP — but correcting either afterwards left the XP in place
(found 2026-10-17: present → absent, still +5). A student kept points for a
period they missed. Corrections now remove the award, and marking again gives it
once more, never twice.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _xp(student_id):
    return asyncio.run(_sql(
        "SELECT coalesce((SELECT total_xp FROM student_xp WHERE student_id = $1), 0)", student_id))


def _today():
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.now(ZoneInfo("Asia/Kolkata")).date().isoformat()


@pytest.fixture(scope="module")
def teacher(two_schools):
    return auth(two_schools["a"]["teacher_token"]), two_schools["a"]["id"]


def test_correcting_attendance_to_absent_takes_the_xp_back(api, teacher):
    headers, sid = teacher
    student = asyncio.run(_make_student(sid, f"{PREFIX}_xpc_att", grade=9, new=True))

    def mark(status):
        r = api.post("/api/teacher/attendance", headers=headers, json={
            "grade": 9, "period": 7, "date": _today(),
            "records": [{"student_id": student, "grade": 9, "period": 7,
                         "date": _today(), "status": status}],
        })
        assert r.status_code == 201, r.text

    mark("present")
    earned = _xp(student)
    assert earned > 0
    mark("absent")
    assert _xp(student) == 0
    mark("present")
    mark("present")
    assert _xp(student) == earned


def test_correcting_homework_to_not_done_takes_the_xp_back(api, teacher):
    headers, sid = teacher
    student = asyncio.run(_make_student(sid, f"{PREFIX}_xpc_hw", grade=9, new=True))
    hw = api.post("/api/teacher/homework", headers=headers,
                  json={"grade": 9, "subject": "maths", "title": f"{PREFIX} xp correction"})
    assert hw.status_code == 201, hw.text
    path = f"/api/teacher/homework/{hw.json()['id']}/completions"

    def mark(done):
        r = api.put(path, headers=headers,
                    json={"records": [{"student_id": student, "completed": done}]})
        assert r.status_code == 200, r.text

    mark(True)
    earned = _xp(student)
    assert earned > 0
    mark(False)
    assert _xp(student) == 0
    mark(True)
    assert _xp(student) == earned
