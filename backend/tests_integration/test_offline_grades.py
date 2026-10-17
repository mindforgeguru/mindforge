"""
Saving a test's offline marks again corrects them; it does not add to them.

Each save inserted a new grade row per student, so a teacher who entered a mark,
noticed a mistake and saved again left the student with two grades for one test
— both shown to the student and the parent, both counted in averages. Found
2026-10-17: 12 then 15 gave the student [15, 12]. The save also accepted any
student in the school, not just the test's grade.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth


async def _sql(query, *args, rows=False):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await (conn.fetch if rows else conn.fetchval)(query, *args)
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def offline_test(two_schools):
    school = two_schools["a"]
    test_id = asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions,
                              total_marks, time_limit_minutes, is_published, school_id)
           VALUES ($1, $2, 8, 'maths', 'offline', '[]'::json, 20, 0, true, $3) RETURNING id""",
        f"{PREFIX} offline", school["teacher_id"], school["id"]))
    return test_id, auth(school["teacher_token"]), school["id"]


def _save(api, offline_test, *pairs):
    test_id, headers, _ = offline_test
    return api.post(f"/api/teacher/tests/{test_id}/offline-grades", headers=headers,
                    json={"grades": [{"student_id": s, "marks_obtained": m} for s, m in pairs]})


def test_saving_again_replaces_the_mark(api, offline_test):
    test_id, _, sid = offline_test
    pupil = asyncio.run(_make_student(sid, f"{PREFIX}_off_a"))
    other = asyncio.run(_make_student(sid, f"{PREFIX}_off_b"))
    assert _save(api, offline_test, (pupil, 12), (other, 18)).status_code == 201
    assert _save(api, offline_test, (pupil, 15)).status_code == 201

    marks = asyncio.run(_sql("SELECT student_id, marks_obtained FROM grades WHERE test_id = $1",
                             test_id, rows=True))
    by_student = {}
    for r in marks:
        by_student.setdefault(r["student_id"], []).append(float(r["marks_obtained"]))
    assert by_student[pupil] == [15.0]
    # A student left out of the second save keeps their mark.
    assert by_student[other] == [18.0]


def test_a_student_from_another_grade_is_refused(api, offline_test):
    _, _, sid = offline_test
    tenth = asyncio.run(_make_student(sid, f"{PREFIX}_off_g10", grade=10))
    assert _save(api, offline_test, (tenth, 10)).status_code == 404
