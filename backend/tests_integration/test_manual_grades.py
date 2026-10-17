"""
A manual mark can only be tied to this school's own offline test.

`POST /teacher/grades` took any `test_id`: a nonexistent one was a 500 (the
foreign key refused it), another school's test was accepted — with that test's
XP for the student — and the client could label the mark "online", the type the
system gives a grade it worked out itself. Found 2026-10-18.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _test(school, test_type, grade=8):
    return asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, school_id)
           VALUES ($1, $2, $3, 'maths', $4, '[]'::json, 10, 10, true, $5) RETURNING id""",
        f"{PREFIX} manual {test_type} {grade}", school["teacher_id"], grade, test_type, school["id"]))


@pytest.fixture(scope="module")
def setup(two_schools):
    a, b = two_schools["a"], two_schools["b"]
    student = asyncio.run(_make_student(a["id"], f"{PREFIX}_manual_g", new=True))
    return {"headers": auth(a["teacher_token"]), "student": student,
            "own_offline": _test(a, "offline"), "own_online": _test(a, "online"),
            "own_other_grade": _test(a, "offline", grade=9), "foreign": _test(b, "offline")}


def _post(api, s, **extra):
    return api.post("/api/teacher/grades", headers=s["headers"], json={
        "student_id": s["student"], "subject": "maths", "chapter": "c",
        "marks_obtained": 10, "max_marks": 10, **extra})


@pytest.mark.parametrize("which", ["foreign", "own_online", "own_other_grade"])
def test_a_test_that_is_not_this_classes_offline_test_is_refused(api, setup, which):
    r = _post(api, setup, test_id=setup[which])
    assert r.status_code in (404, 409), f"{which}: {r.status_code} {r.text[:200]}"


def test_a_test_that_does_not_exist_is_404_not_500(api, setup):
    assert _post(api, setup, test_id=99_999_999).status_code == 404


def test_own_offline_test_is_fine_and_the_type_is_the_servers(api, setup):
    r = _post(api, setup, test_id=setup["own_offline"], grade_type="online")
    assert r.status_code == 201, r.text
    assert r.json()["grade_type"] == "offline"
    r = _post(api, setup, grade_type="online")
    assert r.status_code == 201, r.text
    assert r.json()["grade_type"] == "manual"


@pytest.mark.parametrize("which", ["foreign", "own_other_grade", "missing"])
def test_homework_can_only_link_this_classes_test(api, setup, which):
    # Homework took any test_id too: nonexistent was a 500, another school's
    # test was stored on the homework.
    test_id = 99_999_999 if which == "missing" else setup[which]
    r = api.post("/api/teacher/homework", headers=setup["headers"], json={
        "grade": 8, "subject": "maths", "title": f"{PREFIX} linked {which}",
        "homework_type": "online_test", "test_id": test_id})
    assert r.status_code == 404, f"{which}: {r.status_code} {r.text[:200]}"


def test_homework_linking_its_own_test_is_fine(api, setup):
    r = api.post("/api/teacher/homework", headers=setup["headers"], json={
        "grade": 8, "subject": "maths", "title": f"{PREFIX} linked own",
        "homework_type": "online_test", "test_id": setup["own_online"]})
    assert r.status_code == 201, r.text
