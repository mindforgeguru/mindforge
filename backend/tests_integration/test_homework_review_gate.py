"""The ordering rules on homework review, and what they tell the teacher.

Review depends on attendance, and attendance depends on somebody being enrolled.
A grade with no students can never satisfy the attendance rule, so it has to be
told that rather than being sent to mark attendance that inserts nothing.

Attendance also depends on there being a class. On a holiday or a day the
grade has no lessons, nobody takes attendance — so review must not demand it,
or the pending review can never clear and new homework 409s all day.
"""

import asyncio
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import asyncpg

from .conftest import DB_DSN, PREFIX, _make_student, auth

# The schools are in India; "today" for every daily gate is the IST date.
SCHOOL_TZ = ZoneInfo("Asia/Kolkata")


def _school_today():
    return datetime.now(SCHOOL_TZ).date()


def _make_slot(api, token, grade, *, is_holiday):
    r = api.post(
        "/api/teacher/timetable",
        headers=auth(token),
        json={
            "grade": grade,
            "slot_date": _school_today().isoformat(),
            "period_number": 1,
            "subject": "Physics",
            "is_holiday": is_holiday,
        },
    )
    assert r.status_code == 200, f"slot create failed: {r.text}"


async def _insert_yesterdays_homework(school_id, teacher_id, grade, title):
    """Homework assigned on the previous school day — the row the review gate
    looks at. Inserted directly because the API stamps created_at with now()."""
    created = datetime.combine(
        _school_today() - timedelta(days=1), time(12, 0), tzinfo=SCHOOL_TZ
    )
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(
            """
            INSERT INTO homework (teacher_id, grade, subject, title,
                                  homework_type, school_id, created_at)
            VALUES ($1, $2, 'Physics', $3, 'written', $4, $5)
            RETURNING id
            """,
            teacher_id, grade, title, school_id, created,
        )
    finally:
        await conn.close()


def _make_homework(api, token, grade, title):
    r = api.post(
        "/api/teacher/homework",
        headers=auth(token),
        json={
            "grade": grade,
            "subject": "Physics",
            "title": title,
            "homework_type": "written",
        },
    )
    assert r.status_code in (200, 201), f"homework create failed: {r.text}"
    return r.json()["id"]


def test_empty_grade_reports_enrolment_not_attendance(api, two_schools):
    """Grade 11 of a fresh school has nobody in it.

    Marking attendance there is a no-op (an empty roster inserts no rows), so
    an "attendance first" error would strand the teacher on an error they have
    no way to clear.
    """
    token = two_schools["a"]["teacher_token"]
    hw_id = _make_homework(api, token, 11, f"{PREFIX} empty-grade hw")

    r = api.put(
        f"/api/teacher/homework/{hw_id}/completions",
        headers=auth(token),
        json={"records": []},
    )

    assert r.status_code == 400, r.text
    detail = r.json()["detail"]
    assert "enrolled" in detail, f"expected an enrolment message, got: {detail}"
    assert "Mark attendance" not in detail, (
        f"empty grade still told to mark attendance: {detail}"
    )


def test_populated_grade_still_requires_attendance_first(api, two_schools, students):
    """Rule 1 must survive the reordering: grade 8 has a student, a lesson
    today and no attendance recorded, so it still gets the attendance error."""
    token = two_schools["a"]["teacher_token"]
    _make_slot(api, token, 8, is_holiday=False)
    hw_id = _make_homework(api, token, 8, f"{PREFIX} attendance-gate hw")

    r = api.put(
        f"/api/teacher/homework/{hw_id}/completions",
        headers=auth(token),
        json={"records": [{"student_id": students["a"], "completed": True}]},
    )

    assert r.status_code == 400, r.text
    assert "Mark attendance" in r.json()["detail"], r.text


def test_other_schools_teacher_cannot_review(api, two_schools):
    """The enrolment check runs before any tenant check could be skipped —
    school B must still get 404, not a leaked enrolment count for school A."""
    hw_id = _make_homework(
        api, two_schools["a"]["teacher_token"], 11, f"{PREFIX} cross-tenant hw"
    )

    r = api.put(
        f"/api/teacher/homework/{hw_id}/completions",
        headers=auth(two_schools["b"]["teacher_token"]),
        json={"records": []},
    )

    assert r.status_code == 404, r.text


def _assert_review_unblocked(api, school, grade):
    """The holiday deadlock: yesterday's HW is unreviewed, so new HW 409s; the
    review must be recordable without attendance, and then new HW goes through."""
    token = school["teacher_token"]
    student_id = asyncio.run(
        _make_student(school["id"], f"{PREFIX}_student_g{grade}", grade=grade)
    )
    hw_id = asyncio.run(_insert_yesterdays_homework(
        school["id"], school["teacher_id"], grade, f"{PREFIX} g{grade} yesterday"
    ))

    blocked = api.post(
        "/api/teacher/homework",
        headers=auth(token),
        json={"grade": grade, "subject": "Physics",
              "title": f"{PREFIX} g{grade} blocked", "homework_type": "written"},
    )
    assert blocked.status_code == 409, blocked.text
    assert blocked.json()["detail"]["code"] == "homework_review_pending"

    r = api.put(
        f"/api/teacher/homework/{hw_id}/completions",
        headers=auth(token),
        json={"records": [{"student_id": student_id, "completed": True}]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["students"][0]["completed"] is True

    got = api.get(f"/api/teacher/homework/{hw_id}/completions", headers=auth(token))
    assert got.status_code == 200, got.text
    assert got.json()["attendance_required"] is False, got.text
    assert got.json()["attendance_date"] == _school_today().isoformat(), got.text

    _make_homework(api, token, grade, f"{PREFIX} g{grade} after review")


def test_no_class_day_does_not_deadlock_review(api, two_schools):
    """No timetable for grade 9 today (the observed 2026-10-09 case): there is
    no attendance to take, so review proceeds without it."""
    _assert_review_unblocked(api, two_schools["a"], 9)


def test_holiday_does_not_deadlock_review(api, two_schools):
    """Grade 10's timetable today is entirely holiday."""
    _make_slot(api, two_schools["a"]["teacher_token"], 10, is_holiday=True)
    _assert_review_unblocked(api, two_schools["a"], 10)


def test_class_day_reports_attendance_required(api, two_schools, students):
    """The flag the teacher screen uses to disable Submit stays on for a
    normal lesson day."""
    token = two_schools["a"]["teacher_token"]
    _make_slot(api, token, 8, is_holiday=False)
    hw_id = _make_homework(api, token, 8, f"{PREFIX} required-flag hw")

    got = api.get(f"/api/teacher/homework/{hw_id}/completions", headers=auth(token))
    assert got.status_code == 200, got.text
    assert got.json()["attendance_required"] is True, got.text
