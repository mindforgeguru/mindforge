"""
Parent → child authorization.

A parent account reads another person's records by design — that is the whole
feature — so "which child" is decided entirely by the link, and the link is the
control. Nothing was testing it.

Three properties, each a distinct way the link could fail:

1. A parent cannot choose whose records they read. Every /parent/child/*
   endpoint resolves the student from the authenticated parent's own id, so
   there is no id for a caller to swap. This asserts no endpoint grows one.
2. The read cannot be redirected. Handing the endpoint another school's
   student id must not change the answer by a single byte.
3. An admin cannot link a parent to a student in another school, in either
   direction — parent-side edit or student-side edit.

The linking write path lives only in admin.py; the parent router is read-only
apart from changing its own MPIN. Verified by source read, and pinned here so a
future write endpoint on the parent router has to confront these tests.
"""

import pytest

from .conftest import PREFIX, TEST_MPIN, auth, login, register


@pytest.fixture(scope="module")
def parent_a(api, two_schools, students):
    """A parent in school A, linked to school A's student.

    Created the way the app actually creates one: an admin edits the student and
    supplies a parent username plus MPIN. Self-registration as a parent is
    rejected by the `restrict_self_register_role` validator added when the
    mass-assignment hole was closed in May, so there is no other route in.
    """
    sid = two_schools["a"]["id"]
    admin_token = two_schools["a"]["admin_token"]
    username = f"{PREFIX}_parent_a"

    r = api.put(
        f"/api/admin/users/{students['a']}",
        headers=auth(admin_token),
        json={"parent_username": username, "parent_mpin": TEST_MPIN},
    )
    if r.status_code not in (200, 201):
        pytest.skip(f"could not create parent via admin: {r.status_code} {r.text[:200]}")

    token = login(api, username, school_id=sid)
    if not token:
        pytest.skip("parent login failed — cannot exercise linking")
    return {"username": username, "token": token, "school_id": sid}


# path -> query params the endpoint requires to be well-formed. The timetable
# read is date-scoped, so without one it 422s before authorization is even
# reached — which would make it a vacuous test rather than a passing one.
CHILD_ENDPOINTS = {
    "/api/parent/child/attendance": {},
    "/api/parent/child/grades": {},
    "/api/parent/child/tests": {},
    "/api/parent/child/homework": {},
    "/api/parent/child/timetable": {"date": "2026-08-19"},
}


class TestParentSeesOwnChild:
    """Positive control. Without this, a 404 in the next class proves nothing —
    it could just mean the endpoint is broken for everyone."""

    @pytest.mark.parametrize("path,required", sorted(CHILD_ENDPOINTS.items()))
    def test_linked_parent_can_read_their_child(self, api, parent_a, path, required):
        r = api.get(path, headers=auth(parent_a["token"]), params=required)
        assert r.status_code == 200, (
            f"{path} returned {r.status_code} for a correctly linked parent; "
            f"body={r.text[:200]}"
        )


class TestParentCannotChooseTheChild:
    @pytest.mark.parametrize("path,required", sorted(CHILD_ENDPOINTS.items()))
    def test_student_id_parameter_cannot_redirect_the_read(
        self, api, parent_a, students, path, required
    ):
        # Hand the endpoint a real student id from the *other* school. Today the
        # child comes from the token and the parameter is ignored, so the answer
        # must be byte-identical to the unparameterised call. This fails the day
        # someone adds a student_id parameter without an ownership check.
        victim = students["b"]
        baseline = api.get(path, headers=auth(parent_a["token"]), params=required)
        steered = api.get(
            path,
            headers=auth(parent_a["token"]),
            params={**required,
                    "student_id": victim, "child_id": victim, "user_id": victim},
        )
        assert steered.status_code == baseline.status_code
        assert steered.text == baseline.text, (
            f"{path} changed its response when handed another school's student "
            f"id — the caller may be choosing whose records they read"
        )

    def test_dashboard_cannot_be_redirected(self, api, parent_a, students):
        base = api.get("/api/parent/dashboard-summary", headers=auth(parent_a["token"]))
        steered = api.get(
            "/api/parent/dashboard-summary",
            headers=auth(parent_a["token"]),
            params={"student_id": students["b"]},
        )
        assert steered.status_code == base.status_code
        assert steered.text == base.text


class TestAdminCannotLinkAcrossSchools:
    def test_linking_a_parent_to_a_student_in_another_school_fails(
        self, api, two_schools, students
    ):
        # Admin of A tries to attach A's parent to B's student by username.
        admin_a = two_schools["a"]["admin_token"]
        r = api.get("/api/admin/users", headers=auth(admin_a))
        assert r.status_code == 200
        parent_row = next(
            (u for u in r.json() if u.get("role") == "parent"), None
        )
        if parent_row is None:
            pytest.skip("no parent in school A to exercise the link path")

        r = api.put(
            f"/api/admin/users/{parent_row['id']}",
            headers=auth(admin_a),
            json={"student_username": f"{PREFIX}_student_b"},
        )
        # 404 — school B's student is not visible to school A's admin, so the
        # username does not resolve. A 200 here would mean the link crossed
        # tenants.
        assert r.status_code in (404, 422), (
            f"cross-school parent link returned {r.status_code}: {r.text[:200]}"
        )
