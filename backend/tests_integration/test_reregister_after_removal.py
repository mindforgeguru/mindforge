"""
A removed account must not hold on to its username or phone number.

Closing the academic year removes every student, teacher and parent in the
school and tells them to register again. Removal is a soft delete, so the old
rows stay — and until migration 038 they stayed inside the unique indexes on
(school_id, username) and (school_id, phone). Every conflict check in the
application looks only at live accounts, so it found nothing, issued the
INSERT, and Postgres refused it: a 500 for anyone who came back under their
own name or their own number, which is nearly everyone.

The same applied to any soft delete — an admin revoking an account, or a
teacher or parent deleting their own.

These tests run against their own school. Closing a year removes every
non-admin in it, which would pull the rug from under the shared fixtures.
"""

import pytest

from .conftest import NUM_ID, PREFIX, RUN_ID, TEST_MPIN, auth, login, register

PARENT_MPIN = "739154"

TEACHER = f"{PREFIX}_back_teacher"
STUDENT = f"{PREFIX}_back_student"
PARENT = f"{PREFIX}_back_parent"
TEACHER_PHONE = f"97{NUM_ID}001"
STUDENT_PHONE = f"97{NUM_ID}002"


def _register_teacher(api, sid, username=TEACHER, phone=TEACHER_PHONE):
    return register(
        api, username=username, mpin=TEST_MPIN, role="teacher",
        school_id=sid, phone=phone, teachable_subjects=["maths"],
    )


def _register_student(api, sid, username=STUDENT, phone=STUDENT_PHONE):
    return register(
        api, username=username, mpin=TEST_MPIN, role="student",
        school_id=sid, phone=phone, grade=8,
        parent_username=PARENT, parent_mpin=PARENT_MPIN,
    )


def _approve_all(api, admin_token):
    pending = api.get("/api/admin/users/pending", headers=auth(admin_token)).json()
    for u in pending:
        r = api.post(f"/api/admin/users/{u['id']}/approve", headers=auth(admin_token))
        assert r.status_code in (200, 204), r.text
    return pending


@pytest.fixture(scope="module")
def closed_school(api, owner_token):
    """A school whose year was closed with a teacher, a student and a parent in it."""
    r = api.post(
        "/api/owner/schools",
        headers=auth(owner_token),
        json={"name": f"ITest Reuse {RUN_ID}", "slug": f"{PREFIX}-reuse"},
    )
    assert r.status_code == 201, r.text
    sid = r.json()["id"]

    admin_username = f"{PREFIX}_admin_reuse"
    r = api.post(
        f"/api/owner/schools/{sid}/admins",
        headers=auth(owner_token),
        json={"username": admin_username, "mpin": TEST_MPIN},
    )
    assert r.status_code == 201, r.text
    admin_token = login(api, admin_username, school_id=sid)
    assert admin_token

    r = api.post("/api/admin/academic-years/init", headers=auth(admin_token))
    assert r.status_code == 201, r.text

    assert _register_teacher(api, sid).status_code == 201
    assert _register_student(api, sid).status_code == 201
    assert len(_approve_all(api, admin_token)) == 3
    assert login(api, TEACHER, school_id=sid), "teacher could not log in before the close"

    r = api.post("/api/admin/academic-years/new", headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return {"id": sid, "admin_token": admin_token}


class TestTheYearCloseRemovesEveryone:
    """Positive control: without it, a successful re-registration could just
    mean the close never removed anyone."""

    def test_removed_accounts_cannot_log_in(self, api, closed_school):
        sid = closed_school["id"]
        assert login(api, TEACHER, school_id=sid) is None
        assert login(api, STUDENT, school_id=sid) is None
        assert login(api, PARENT, mpin=PARENT_MPIN, school_id=sid) is None


class TestReturningUsersCanRegisterAgain:
    def test_teacher_returns_with_the_same_username_and_phone(self, api, closed_school):
        r = _register_teacher(api, closed_school["id"])
        assert r.status_code == 201, f"{r.status_code} {r.text[:200]}"

    def test_student_returns_with_the_same_username_phone_and_parent(
        self, api, closed_school
    ):
        r = _register_student(api, closed_school["id"])
        assert r.status_code == 201, f"{r.status_code} {r.text[:200]}"

    def test_the_returning_accounts_log_in_once_approved(self, api, closed_school):
        sid = closed_school["id"]
        approved = _approve_all(api, closed_school["admin_token"])
        assert sorted(u["username"] for u in approved) == sorted(
            [TEACHER, STUDENT, PARENT]
        )
        # Two rows now share each username — one removed, one live. Login must
        # pick the live one rather than trip over the pair.
        assert login(api, TEACHER, school_id=sid)
        assert login(api, STUDENT, school_id=sid)
        assert login(api, PARENT, mpin=PARENT_MPIN, school_id=sid)


class TestLiveAccountsStillOwnTheirDetails:
    """Loosening the index must not let two live accounts share a name or number."""

    def test_a_live_username_is_still_refused(self, api, closed_school):
        r = _register_teacher(
            api, closed_school["id"], phone=f"97{NUM_ID}003"
        )
        assert r.status_code == 409, f"{r.status_code} {r.text[:200]}"

    def test_a_live_phone_is_still_refused(self, api, closed_school):
        r = _register_teacher(
            api, closed_school["id"], username=f"{PREFIX}_back_other"
        )
        assert r.status_code == 409, f"{r.status_code} {r.text[:200]}"


class TestAnAccountRevokedByTheAdmin:
    def test_its_username_and_phone_can_be_registered_again(self, api, closed_school):
        sid = closed_school["id"]
        admin = auth(closed_school["admin_token"])
        users = api.get("/api/admin/users", headers=admin).json()
        teacher_id = next(u["id"] for u in users if u["username"] == TEACHER)

        r = api.delete(f"/api/admin/users/{teacher_id}/revoke", headers=admin)
        assert r.status_code == 204, r.text
        assert login(api, TEACHER, school_id=sid) is None

        r = _register_teacher(api, sid)
        assert r.status_code == 201, f"{r.status_code} {r.text[:200]}"
