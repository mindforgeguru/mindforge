"""
The teacher's daily workflow: timetable → attendance → homework review →
homework, one road per grade.

Nothing was testing it, and the first step had a dead end. The road only drew
grades that had a timetable today or in the last fourteen days, so a school
with none — a new school, or one back from a long break — returned no grades
at all, flagged as a holiday. The teacher was shown "Holiday! No classes
today" on a working day and never offered the step that would have fixed it:
create today's timetable.

Each test class builds its own school. The workflow is grade-wide and
school-wide, so sharing the session's schools would make every assertion
depend on what the other modules happened to leave behind.
"""

import asyncio
from datetime import date

import asyncpg
import pytest

from .conftest import DB_DSN, NUM_ID, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login, register


def _school_today() -> str:
    """The school's date as the backend sees it."""
    async def _q():
        conn = await asyncpg.connect(DB_DSN)
        try:
            return await conn.fetchval(
                "SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date"
            )
        finally:
            await conn.close()

    d = asyncio.run(_q())
    assert isinstance(d, date)
    return d.isoformat()


def _new_school(api, owner_token, tag, phone_suffix):
    r = api.post(
        "/api/owner/schools",
        headers=auth(owner_token),
        json={"name": f"ITest WF {tag} {RUN_ID}", "slug": f"{PREFIX}-wf-{tag}"},
    )
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin = f"{PREFIX}_wf_admin_{tag}"
    r = api.post(
        f"/api/owner/schools/{sid}/admins",
        headers=auth(owner_token),
        json={"username": admin, "mpin": TEST_MPIN},
    )
    assert r.status_code == 201, r.text
    admin_token = login(api, admin, school_id=sid)
    assert admin_token

    teacher = f"{PREFIX}_wf_teacher_{tag}"
    r = register(
        api, username=teacher, mpin=TEST_MPIN, role="teacher", school_id=sid,
        phone=f"95{NUM_ID}{phone_suffix}",
    )
    assert r.status_code == 201, r.text
    r = api.post(f"/api/admin/users/{r.json()['id']}/approve", headers=auth(admin_token))
    assert r.status_code in (200, 204), r.text
    teacher_token = login(api, teacher, school_id=sid)
    assert teacher_token
    return {"id": sid, "admin": auth(admin_token), "teacher": auth(teacher_token)}


def _workflow(api, school):
    r = api.get("/api/teacher/today-workflow", headers=school["teacher"])
    assert r.status_code == 200, r.text
    body = r.json()
    return body, {g["grade"]: g for g in body["grades"]}


def _slot(api, school, grade, period, **extra):
    r = api.post(
        "/api/teacher/timetable",
        headers=school["teacher"],
        json={"grade": grade, "slot_date": _school_today(), "period_number": period, **extra},
    )
    assert r.status_code == 200, r.text


class TestASchoolWithNoTimetableYet:
    @pytest.fixture(scope="class")
    def school(self, api, owner_token):
        s = _new_school(api, owner_token, "new", "101")
        s["students"] = {
            8: asyncio.run(_make_student(s["id"], f"{PREFIX}_wf_new_8", grade=8)),
            9: asyncio.run(_make_student(s["id"], f"{PREFIX}_wf_new_9", grade=9)),
        }
        return s

    def test_it_is_not_called_a_holiday(self, api, school):
        body, _ = _workflow(api, school)
        assert body["is_holiday_for_teacher"] is False

    def test_each_grade_with_students_is_offered_the_timetable_step(self, api, school):
        _, grades = _workflow(api, school)
        assert sorted(grades) == [8, 9]
        for g in grades.values():
            assert g["timetable_created"] is False
            assert g["next_step"] == "create_timetable"
            assert g["is_holiday"] is False

    def test_a_removed_student_does_not_keep_a_grade_on_the_road(self, api, school):
        r = api.delete(
            f"/api/admin/users/{school['students'][9]}/revoke", headers=school["admin"]
        )
        assert r.status_code == 204, r.text
        _, grades = _workflow(api, school)
        assert sorted(grades) == [8]


class TestOneGradeTimetabledAnotherNot:
    """A grade with students but no timetable used to vanish from the road as
    soon as any other grade had one, so nothing prompted anyone to set it up
    (found 2026-10-12, fixed 2026-10-18)."""

    def test_the_untimetabled_grade_is_still_offered_the_step(self, api, owner_token):
        school = _new_school(api, owner_token, "half", "103")
        asyncio.run(_make_student(school["id"], f"{PREFIX}_wf_half_8", grade=8))
        asyncio.run(_make_student(school["id"], f"{PREFIX}_wf_half_9", grade=9))
        _slot(api, school, 8, 1, subject="maths")
        _, grades = _workflow(api, school)
        assert sorted(grades) == [8, 9]
        assert grades[8]["timetable_created"] is True
        assert grades[9]["timetable_created"] is False
        assert grades[9]["next_step"] == "create_timetable"


class TestASchoolWithNobodyInIt:
    def test_no_grades_and_still_not_a_holiday(self, api, owner_token):
        school = _new_school(api, owner_token, "empty", "102")
        body, grades = _workflow(api, school)
        assert grades == {}
        assert body["is_holiday_for_teacher"] is False


class TestAWorkingDay:
    """The road from timetable to homework, pinned as it behaves today."""

    @pytest.fixture(scope="class")
    def school(self, api, owner_token):
        s = _new_school(api, owner_token, "day", "103")
        s["student"] = asyncio.run(_make_student(s["id"], f"{PREFIX}_wf_day_8", grade=8))
        return s

    def _mark(self, api, school, period):
        today = _school_today()
        r = api.post(
            "/api/teacher/attendance",
            headers=school["teacher"],
            json={
                "grade": 8, "period": period, "date": today,
                "records": [{
                    "student_id": school["student"], "grade": 8, "period": period,
                    "date": today, "status": "present",
                }],
            },
        )
        assert r.status_code == 201, r.text

    def test_the_car_moves_one_step_at_a_time(self, api, school):
        _slot(api, school, 8, 1, subject="Mathematics")
        _slot(api, school, 8, 2, subject="Science")
        body, grades = _workflow(api, school)
        g = grades[8]
        assert (g["timetable_created"], g["next_step"]) == (True, "take_attendance")
        assert g["expected_periods"] == [1, 2]
        assert g["can_assign_new_homework"] is False
        assert body["is_holiday_for_teacher"] is False

        self._mark(api, school, 1)
        g = _workflow(api, school)[1][8]
        assert (g["attendance_progress"], g["next_step"]) == ("1/2", "take_attendance")

        self._mark(api, school, 2)
        g = _workflow(api, school)[1][8]
        assert g["attendance_taken"] is True
        # No earlier homework to review, so the car goes straight on.
        assert g["review_applicable"] is False
        assert (g["can_assign_new_homework"], g["next_step"]) == (True, "assign_homework")

        r = api.post(
            "/api/teacher/homework",
            headers=school["teacher"],
            json={"grade": 8, "subject": "Mathematics", "title": f"{PREFIX} wf hw"},
        )
        assert r.status_code == 201, r.text
        g = _workflow(api, school)[1][8]
        assert (g["tomorrow_hw_assigned"], g["next_step"]) == (True, "done")


class TestADeclaredHoliday:
    @pytest.fixture(scope="class")
    def school(self, api, owner_token):
        s = _new_school(api, owner_token, "hol", "104")
        for grade in (8, 9):
            asyncio.run(_make_student(s["id"], f"{PREFIX}_wf_hol_{grade}", grade=grade))
        return s

    def test_one_grade_on_holiday_is_not_a_school_holiday(self, api, school):
        _slot(api, school, 8, 1, subject="Mathematics")
        _slot(api, school, 9, 1, is_holiday=True, comment="Sports day")
        body, grades = _workflow(api, school)
        assert grades[9]["is_holiday"] is True
        assert grades[9]["attendance_applicable"] is False
        assert grades[9]["next_step"] == "assign_homework"
        assert grades[8]["is_holiday"] is False
        assert body["is_holiday_for_teacher"] is False

    def test_every_timetabled_grade_on_holiday_is(self, api, school):
        today = _school_today()
        r = api.post(
            "/api/teacher/timetable/delete",
            headers=school["teacher"],
            params={"grade": 8, "date": today},
        )
        assert r.status_code == 200, r.text
        _slot(api, school, 8, 1, is_holiday=True, comment="Sports day")
        body, grades = _workflow(api, school)
        assert all(g["is_holiday"] for g in grades.values())
        assert body["is_holiday_for_teacher"] is True
