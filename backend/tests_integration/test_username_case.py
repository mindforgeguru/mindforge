"""
Two accounts whose usernames differ only in case do not break parent linking.

Usernames are case-sensitive — sign-in, registration and the admin's rename all
compare them exactly, so "Ravi" and "ravi" can both exist. But finding a parent
by username (registration and the admin's student editor) ignored case and
expected one match. With two it raised, and the admin's edit — and anyone's
sign-up naming that parent — was a 500 (found 2026-10-18). An exact match now
wins; a case-insensitive one is used only when it is the only one.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, NUM_ID, PREFIX, TEST_MPIN, _make_student, auth, register


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def look_alikes(two_schools):
    sid = two_schools["a"]["id"]
    ids = {}
    for name, role in ((f"{PREFIX}_Case_Parent", "parent"), (f"{PREFIX}_case_parent", "parent"),
                       (f"{PREFIX}_Case_Teacher", "teacher"), (f"{PREFIX}_case_teacher", "teacher")):
        ids[name] = asyncio.run(_sql(
            """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
               VALUES ($1, 'x', $2, $3, true, true) RETURNING id""", name, role, sid))
    student = asyncio.run(_make_student(sid, f"{PREFIX}_case_kid", new=True))
    return {"ids": ids, "student": student, "admin": auth(two_schools["a"]["admin_token"]), "sid": sid}


def _link(api, look_alikes, parent_username, **extra):
    return api.put(f"/api/admin/users/{look_alikes['student']}", headers=look_alikes["admin"],
                   json={"parent_username": parent_username, **extra})


def test_the_exact_username_is_the_parent_linked(api, look_alikes):
    name = f"{PREFIX}_case_parent"
    r = _link(api, look_alikes, name)
    assert r.status_code == 200, r.text
    assert r.json()["parent_user_id"] == look_alikes["ids"][name]


def test_an_ambiguous_parent_username_is_refused_not_a_crash(api, look_alikes):
    r = _link(api, look_alikes, f"{PREFIX}_CASE_PARENT")
    assert r.status_code == 409, r.text


def test_a_username_used_by_two_teachers_is_refused_not_a_crash(api, look_alikes):
    r = _link(api, look_alikes, f"{PREFIX}_CASE_TEACHER", parent_mpin="739154")
    assert r.status_code == 409, r.text


def test_signing_up_with_an_ambiguous_parent_username_is_not_a_crash(api, look_alikes):
    r = register(api, username=f"{PREFIX}_case_signup", mpin=TEST_MPIN, role="student",
                 school_id=look_alikes["sid"], phone=f"76{NUM_ID}001", grade=9,
                 parent_username=f"{PREFIX}_CASE_PARENT", parent_mpin="739154")
    assert r.status_code in (401, 409), r.text
