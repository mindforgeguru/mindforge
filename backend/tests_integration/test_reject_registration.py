"""
Rejecting a student's sign-up does not leave their parent's account behind.

Registering a student creates their parent's account too (pending). Rejecting
the student deleted only the student, so the childless parent account kept the
parent username: the family's next attempt with a different parent MPIN was
told "Parent username or MPIN is incorrect" (found 2026-10-18). The parent goes
with the student now — unless it is already approved or has another child.
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


def _sign_up(api, sid, kid, parent, parent_mpin, phone):
    return register(api, username=kid, mpin=TEST_MPIN, role="student", school_id=sid,
                    phone=phone, grade=9, parent_username=parent, parent_mpin=parent_mpin)


def test_the_family_can_sign_up_again_after_a_rejection(api, two_schools):
    school = two_schools["a"]
    admin = auth(school["admin_token"])
    kid, parent = f"{PREFIX}_rj_kid", f"{PREFIX}_rj_parent"
    r = _sign_up(api, school["id"], kid, parent, "739154", f"77{NUM_ID}001")
    assert r.status_code == 201, r.text
    assert api.delete(f"/api/admin/users/{r.json()['id']}/pending", headers=admin).status_code == 204
    assert asyncio.run(_sql("SELECT count(*) FROM users WHERE username = $1", parent)) == 0

    r = _sign_up(api, school["id"], kid, parent, "604817", f"77{NUM_ID}001")
    assert r.status_code == 201, r.text


def test_a_parent_with_another_child_stays(api, two_schools):
    school = two_schools["a"]
    admin = auth(school["admin_token"])
    parent = f"{PREFIX}_rj_parent2"
    r = _sign_up(api, school["id"], f"{PREFIX}_rj_first", parent, "739154", f"77{NUM_ID}002")
    assert r.status_code == 201, r.text
    r2 = _sign_up(api, school["id"], f"{PREFIX}_rj_second", parent, "739154", f"77{NUM_ID}003")
    assert r2.status_code == 201, r2.text
    assert api.delete(f"/api/admin/users/{r2.json()['id']}/pending", headers=admin).status_code == 204
    assert asyncio.run(_sql("SELECT count(*) FROM users WHERE username = $1", parent)) == 1


def test_delete_all_pending_keeps_an_approved_students_parent(api, owner_token):
    # Approving a student leaves their parent pending. "Delete all pending"
    # promised approved users were not affected, then deleted those parents
    # and unlinked the children (the link is ON DELETE SET NULL).
    from .conftest import RUN_ID, login

    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest Reject All {RUN_ID}", "slug": f"{PREFIX}-rejectall"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin_name = f"{PREFIX}_admin_rejall"
    api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
             json={"username": admin_name, "mpin": TEST_MPIN})
    admin = auth(login(api, admin_name, school_id=sid))
    api.post("/api/admin/academic-years/init", headers=admin)

    parent = f"{PREFIX}_rj_parent3"
    r = _sign_up(api, sid, f"{PREFIX}_rj_third", parent, "739154", f"77{NUM_ID}004")
    assert r.status_code == 201, r.text
    student = r.json()["id"]
    assert api.post(f"/api/admin/users/{student}/approve", headers=admin).status_code in (200, 204)
    stray = _sign_up(api, sid, f"{PREFIX}_rj_stray", f"{PREFIX}_rj_stray_parent", "739154",
                     f"77{NUM_ID}005")
    assert stray.status_code == 201, stray.text

    r = api.delete("/api/admin/users/pending", headers=admin)
    assert r.status_code == 200, r.text
    assert asyncio.run(_sql("SELECT count(*) FROM users WHERE username = $1", parent)) == 1
    linked = asyncio.run(_sql("SELECT parent_user_id FROM student_profiles WHERE user_id = $1", student))
    assert linked is not None
    # The stray sign-up and its parent are gone.
    assert asyncio.run(_sql("SELECT count(*) FROM users WHERE username LIKE $1", f"{PREFIX}_rj_stray%")) == 0
