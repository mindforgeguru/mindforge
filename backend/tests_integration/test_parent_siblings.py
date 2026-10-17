"""
A parent with two children in the school can see each of them.

Registration lets a second student link to an existing parent, but every parent
endpoint looked up "the child" expecting exactly one. With two, the dashboard,
attendance, fees and grades were all 500s (found 2026-10-17). Now
`GET /parent/children` lists them and every child endpoint takes `child_id`;
without it the first child is used, so a one-child family (and an older app)
sees no change.
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


@pytest.fixture(scope="module")
def family(two_schools):
    # New accounts, so they join no other test's homework roster (rosters count
    # students who were there when the homework was set).
    school = two_schools["a"]
    sid = school["id"]
    younger = asyncio.run(_make_student(sid, f"{PREFIX}_sib_younger", grade=8, new=True))
    older = asyncio.run(_make_student(sid, f"{PREFIX}_sib_older", grade=10, new=True))
    stranger = asyncio.run(_make_student(sid, f"{PREFIX}_sib_stranger", grade=9, new=True))
    parent = asyncio.run(_sql(
        """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
           VALUES ($1, 'x', 'parent', $2, true, true) RETURNING id""", f"{PREFIX}_sib_parent", sid))

    async def link_and_seed():
        await _sql("UPDATE student_profiles SET parent_user_id = $1 WHERE user_id = ANY($2::int[])",
                   parent, [younger, older])
        for child, chapter, marks in ((younger, "Younger's chapter", 7), (older, "Older's chapter", 9)):
            await _sql(
                """INSERT INTO grades (student_id, teacher_id, subject, chapter, marks_obtained,
                                       max_marks, grade_type, school_id)
                   VALUES ($1, $2, 'maths', $3, $4, 10, 'manual', $5)""",
                child, school["teacher_id"], chapter, marks, sid)
        for grade in (8, 10):
            await _sql(
                """INSERT INTO homework (teacher_id, grade, subject, title, homework_type, school_id)
                   VALUES ($1, $2, 'maths', $3, 'written', $4)""",
                school["teacher_id"], grade, f"{PREFIX} grade {grade} homework", sid)

    asyncio.run(link_and_seed())
    return {"parent": auth(_mint_access_token(parent)),
            "younger": younger, "older": older, "stranger": stranger}


def test_the_parent_can_list_both_children(api, family):
    r = api.get("/api/parent/children", headers=family["parent"])
    assert r.status_code == 200, r.text
    kids = {c["student_id"]: c["grade"] for c in r.json()}
    assert kids == {family["younger"]: 8, family["older"]: 10}
    assert all(c["username"] for c in r.json())


@pytest.mark.parametrize("path", [
    "/api/parent/dashboard-summary", "/api/parent/child/attendance",
    "/api/parent/child/attendance/summary", "/api/parent/fees", "/api/parent/child/grades",
    "/api/parent/child/tests", "/api/parent/child/homework",
    "/api/parent/child/homework/completions", "/api/parent/broadcasts",
])
def test_no_parent_screen_fails_with_two_children(api, family, path):
    assert api.get(path, headers=family["parent"]).status_code == 200


@pytest.mark.parametrize("who,other", [("younger", "older"), ("older", "younger")])
def test_each_childs_marks_are_their_own(api, family, who, other):
    r = api.get("/api/parent/child/grades", headers=family["parent"],
                params={"child_id": family[who]})
    assert r.status_code == 200, r.text
    assert {g["student_id"] for g in r.json()} == {family[who]}


def test_homework_and_dashboard_follow_the_chosen_child(api, family):
    r = api.get("/api/parent/child/homework", headers=family["parent"],
                params={"child_id": family["older"]})
    titles = {h["title"] for h in r.json()}
    assert f"{PREFIX} grade 10 homework" in titles
    assert f"{PREFIX} grade 8 homework" not in titles

    r = api.get("/api/parent/dashboard-summary", headers=family["parent"],
                params={"child_id": family["older"]})
    assert r.status_code == 200, r.text
    assert "grade 10 homework" in r.text and "grade 8 homework" not in r.text


def test_another_familys_child_is_not_reachable(api, family):
    for path in ("/api/parent/child/grades", "/api/parent/dashboard-summary", "/api/parent/fees"):
        r = api.get(path, headers=family["parent"], params={"child_id": family["stranger"]})
        assert r.status_code == 404, f"{path}: {r.status_code}"
