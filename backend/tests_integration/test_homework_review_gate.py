"""The ordering rules on homework review, and what they tell the teacher.

Review depends on attendance, and attendance depends on somebody being enrolled.
A grade with no students can never satisfy the attendance rule, so it has to be
told that rather than being sent to mark attendance that inserts nothing.
"""

from .conftest import PREFIX, auth


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
    """Rule 1 must survive the reordering: grade 8 has a student and no
    attendance recorded today, so it still gets the attendance error."""
    token = two_schools["a"]["teacher_token"]
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
