"""
The admin's user list filters.

The role filter was passed to the database as free text. Any value that is not
a role made Postgres reject the query, and the admin got "Internal server
error" where a validation message belonged. The same parameter on the
per-year user list had the same hole.
"""

import pytest

from .conftest import PREFIX, auth


def _usernames(api, admin, **params):
    r = api.get("/api/admin/users", headers=admin, params=params)
    assert r.status_code == 200, r.text
    return {u["username"] for u in r.json()}


def test_role_filter_keeps_only_that_role(api, two_schools, students):
    admin = auth(two_schools["a"]["admin_token"])
    teachers = _usernames(api, admin, role="teacher")
    assert two_schools["a"]["teacher_username"] in teachers
    assert f"{PREFIX}_student_a" not in teachers

    pupils = _usernames(api, admin, role="student")
    assert f"{PREFIX}_student_a" in pupils
    assert two_schools["a"]["teacher_username"] not in pupils


def test_grade_filter_narrows_students(api, two_schools, students):
    admin = auth(two_schools["a"]["admin_token"])
    assert f"{PREFIX}_student_a" in _usernames(api, admin, role="student", grade=8)
    assert f"{PREFIX}_student_a" not in _usernames(api, admin, role="student", grade=10)


def test_filters_never_reach_another_school(api, two_schools, students):
    admin = auth(two_schools["a"]["admin_token"])
    for params in ({}, {"role": "student"}, {"role": "teacher"}, {"grade": 8}):
        names = _usernames(api, admin, **params)
        assert f"{PREFIX}_student_b" not in names
        assert two_schools["b"]["teacher_username"] not in names


@pytest.mark.parametrize("path", ["/api/admin/users", "/api/admin/academic-years/1/users"])
def test_an_unknown_role_is_a_validation_error(api, two_schools, path):
    r = api.get(
        path, headers=auth(two_schools["a"]["admin_token"]), params={"role": "nonsense"}
    )
    assert r.status_code == 422, f"{r.status_code} {r.text[:200]}"
