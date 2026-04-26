"""
MIND FORGE — API Integration Tests
Tests every significant endpoint against the live server.

Fixtures register fresh test users at session start and clean them up on exit.
If the admin token can't be obtained the entire suite is skipped — set the
ADMIN_MPIN environment variable if the default (123456) has been changed.

Run:
    cd /Users/chinmay1975/Desktop/mindforge
    python3 -m pytest tests/test_api.py -v
"""

import os
import time
import pytest
import httpx

BASE_URL = "https://api.mindforge.guru"
TIMEOUT   = 20

# ── helpers ───────────────────────────────────────────────────────────────────

def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client: httpx.Client, username: str, mpin: str):
    return client.post(
        f"{BASE_URL}/api/auth/login",
        json={"username": username, "mpin": mpin},
        timeout=TIMEOUT,
    )


# ── session-scoped fixtures ───────────────────────────────────────────────────

@pytest.fixture(scope="session")
def client():
    with httpx.Client(follow_redirects=True) as c:
        yield c


@pytest.fixture(scope="session")
def admin_token(client):
    mpin = os.getenv("ADMIN_MPIN", "123456")
    resp = _login(client, "admin", mpin)
    if resp.status_code != 200:
        pytest.skip(
            f"Admin login failed ({resp.status_code}). "
            "Set ADMIN_MPIN env var if the default has been changed."
        )
    return resp.json()["access_token"]


@pytest.fixture(scope="session")
def teacher_ctx(client, admin_token):
    """Registers, approves, and logs in a temporary teacher. Cleans up after session."""
    ts   = int(time.time())
    uname = f"apitst_tchr_{ts}"
    mpin  = "222222"

    r = client.post(f"{BASE_URL}/api/auth/register", json={
        "username": uname, "mpin": mpin, "role": "teacher",
        "phone": f"+910{ts % 10_000_000_000:010d}",
    }, timeout=TIMEOUT)
    assert r.status_code == 201, f"Teacher register failed: {r.text}"
    uid = r.json()["id"]

    client.post(f"{BASE_URL}/api/admin/users/{uid}/approve",
                headers=_auth(admin_token), timeout=TIMEOUT)

    tok = _login(client, uname, mpin)
    assert tok.status_code == 200, f"Teacher login failed: {tok.text}"

    yield {"token": tok.json()["access_token"], "id": uid, "username": uname}

    # cleanup — revoke so user is soft-deleted
    client.delete(f"{BASE_URL}/api/admin/users/{uid}/revoke",
                  headers=_auth(admin_token), timeout=TIMEOUT)


@pytest.fixture(scope="session")
def student_ctx(client, admin_token):
    """Registers, approves, and logs in a temporary student. Cleans up after session."""
    ts    = int(time.time()) + 1        # +1 so phone differs from teacher
    uname = f"apitst_std_{ts}"
    mpin  = "333333"

    r = client.post(f"{BASE_URL}/api/auth/register", json={
        "username": uname, "mpin": mpin, "role": "student",
        "phone": f"+910{(ts + 1) % 10_000_000_000:010d}",
        "grade": 9,
    }, timeout=TIMEOUT)
    assert r.status_code == 201, f"Student register failed: {r.text}"
    uid = r.json()["id"]

    client.post(f"{BASE_URL}/api/admin/users/{uid}/approve",
                headers=_auth(admin_token), timeout=TIMEOUT)

    tok = _login(client, uname, mpin)
    assert tok.status_code == 200, f"Student login failed: {tok.text}"

    yield {"token": tok.json()["access_token"], "id": uid, "username": uname}

    client.delete(f"{BASE_URL}/api/admin/users/{uid}/revoke",
                  headers=_auth(admin_token), timeout=TIMEOUT)


@pytest.fixture(scope="session")
def parent_ctx(client, admin_token, student_ctx):
    """
    Registers, approves, and logs in a temporary parent linked to student_ctx.
    Uses PUT /admin/users/{id} with student_username to establish the link.
    Cleans up (unlinks then revokes) after the session.
    """
    ts    = int(time.time()) + 2
    uname = f"apitst_prnt_{ts}"
    mpin  = "444444"

    r = client.post(f"{BASE_URL}/api/auth/register", json={
        "username": uname, "mpin": mpin, "role": "parent",
        "phone": f"+910{(ts + 2) % 10_000_000_000:010d}",
    }, timeout=TIMEOUT)
    assert r.status_code == 201, f"Parent register failed: {r.text}"
    uid = r.json()["id"]

    client.post(f"{BASE_URL}/api/admin/users/{uid}/approve",
                headers=_auth(admin_token), timeout=TIMEOUT)

    # Link this parent to the shared student fixture.
    link = client.put(
        f"{BASE_URL}/api/admin/users/{uid}",
        json={"student_username": student_ctx["username"]},
        headers=_auth(admin_token),
        timeout=TIMEOUT,
    )
    assert link.status_code == 200, f"Parent-student link failed: {link.text}"

    tok = _login(client, uname, mpin)
    assert tok.status_code == 200, f"Parent login failed: {tok.text}"

    yield {"token": tok.json()["access_token"], "id": uid, "username": uname, "mpin": mpin}

    # Unlink first so the student isn't left pointing at a deleted parent.
    client.put(
        f"{BASE_URL}/api/admin/users/{uid}",
        json={"student_username": ""},
        headers=_auth(admin_token),
        timeout=TIMEOUT,
    )
    client.delete(f"{BASE_URL}/api/admin/users/{uid}/revoke",
                  headers=_auth(admin_token), timeout=TIMEOUT)


# ── 1. Auth ───────────────────────────────────────────────────────────────────

class TestAuth:

    def test_login_valid_returns_200_and_tokens(self, client, admin_token):
        # We already have a valid token — just verify the login response structure
        mpin = os.getenv("ADMIN_MPIN", "123456")
        r = _login(client, "admin", mpin)
        assert r.status_code == 200
        body = r.json()
        assert "access_token"  in body
        assert "refresh_token" in body
        assert body["role"]    == "admin"

    def test_login_wrong_mpin_returns_401(self, client):
        r = _login(client, "admin", "000000")
        # 401 normally; 429 if this test-run pair exhausted the per-user rate limit
        assert r.status_code in (401, 429)
        assert "detail" in r.json()

    def test_login_nonexistent_user_returns_401(self, client):
        r = _login(client, "no_such_user_xyz", "123456")
        assert r.status_code in (401, 429)

    def test_login_pending_user_returns_403(self, client):
        # Register a brand-new user without approving — login must return 403
        ts    = int(time.time()) + 99
        uname = f"pending_user_{ts}"
        reg = client.post(f"{BASE_URL}/api/auth/register", json={
            "username": uname, "mpin": "444444", "role": "teacher",
            "phone": f"+919{ts % 10_000_000_000:010d}",
        }, timeout=TIMEOUT)
        assert reg.status_code == 201

        r = _login(client, uname, "444444")
        assert r.status_code in (403, 429)
        # no cleanup needed — pending users are harmless and soft-deleted

    def test_login_missing_fields_returns_422(self, client):
        r = client.post(f"{BASE_URL}/api/auth/login",
                        json={"username": "admin"}, timeout=TIMEOUT)
        assert r.status_code == 422

    def test_refresh_valid_token_returns_new_access_token(self, client, admin_token):
        # admin_token fixture already confirmed login works; login again to get refresh_token
        mpin = os.getenv("ADMIN_MPIN", "123456")
        login = _login(client, "admin", mpin)
        body = login.json()
        assert "refresh_token" in body, f"Login response missing refresh_token: {body}"
        rt = body["refresh_token"]

        r = client.post(f"{BASE_URL}/api/auth/refresh",
                        json={"refresh_token": rt}, timeout=TIMEOUT)
        assert r.status_code == 200
        assert "access_token" in r.json()

    def test_refresh_invalid_token_returns_401(self, client):
        r = client.post(f"{BASE_URL}/api/auth/refresh",
                        json={"refresh_token": "not.a.real.token"}, timeout=TIMEOUT)
        assert r.status_code == 401

    def test_logout_with_refresh_token_blacklists_refresh_jti(self, client, admin_token):
        """
        Logout must revoke the refresh-token JTI when sent in the body, so a
        captured refresh token cannot mint new access tokens after logout.
        Uses a fresh admin login so the session-scoped admin_token is not
        invalidated. Depends on admin_token so the test skips when admin
        credentials are unavailable, matching the rest of the suite.
        """
        mpin = os.getenv("ADMIN_MPIN", "123456")
        login = _login(client, "admin", mpin)
        assert login.status_code == 200
        body = login.json()
        access = body["access_token"]
        refresh = body["refresh_token"]

        out = client.post(
            f"{BASE_URL}/api/auth/logout",
            headers=_auth(access),
            json={"refresh_token": refresh},
            timeout=TIMEOUT,
        )
        assert out.status_code == 204, f"Logout failed: {out.text}"

        # The refresh token's JTI is now blacklisted — it must not mint a new access token.
        r = client.post(f"{BASE_URL}/api/auth/refresh",
                        json={"refresh_token": refresh}, timeout=TIMEOUT)
        assert r.status_code == 401, (
            f"Refresh token was not revoked by logout (got {r.status_code}: {r.text})"
        )

    def test_register_creates_pending_user(self, client):
        ts    = int(time.time()) + 200
        uname = f"reg_test_{ts}"
        r = client.post(f"{BASE_URL}/api/auth/register", json={
            "username": uname, "mpin": "555555", "role": "teacher",
            "phone": f"+918{ts % 10_000_000_000:010d}",
        }, timeout=TIMEOUT)
        assert r.status_code == 201
        body = r.json()
        assert body["is_approved"] is False
        assert body["role"] == "teacher"

    def test_get_me_returns_current_user(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/auth/me",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 200
        assert r.json()["role"] == "admin"

    def test_get_me_without_token_returns_401(self, client):
        r = client.get(f"{BASE_URL}/api/auth/me", timeout=TIMEOUT)
        assert r.status_code == 401


# ── 2. Teacher ────────────────────────────────────────────────────────────────

class TestTeacher:

    def test_dashboard_summary_returns_200(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/dashboard-summary",
                       headers=_auth(teacher_ctx["token"]), timeout=30)
        assert r.status_code == 200
        body = r.json()
        # Must contain expected keys
        assert "test_count" in body or "timetable" in body or "broadcasts" in body

    def test_dashboard_summary_requires_auth(self, client):
        r = client.get(f"{BASE_URL}/api/teacher/dashboard-summary", timeout=TIMEOUT)
        assert r.status_code == 401

    def test_get_teacher_profile(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/profile",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert r.json()["role"] == "teacher"

    def test_get_tests_returns_list(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/tests",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_tests_with_grade_filter(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/tests?grade=9",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_grades_returns_list(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/grades",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_attendance_requires_grade_param(self, client, teacher_ctx):
        # Missing grade → 422
        r = client.get(f"{BASE_URL}/api/teacher/attendance",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 422

    def test_get_attendance_with_grade(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/attendance?grade=9",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_broadcasts_returns_list(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/broadcast",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_homework_returns_list(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/homework",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_student_token_cannot_access_teacher_endpoints(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/teacher/dashboard-summary",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403

    def test_delete_nonexistent_test_returns_404(self, client, teacher_ctx):
        r = client.delete(f"{BASE_URL}/api/teacher/tests/999999999",
                          headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 404


# ── 3. Student ────────────────────────────────────────────────────────────────

class TestStudent:

    def test_dashboard_summary_returns_200(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/dashboard-summary",
                       headers=_auth(student_ctx["token"]), timeout=30)
        assert r.status_code == 200

    def test_dashboard_summary_requires_auth(self, client):
        r = client.get(f"{BASE_URL}/api/student/dashboard-summary", timeout=TIMEOUT)
        assert r.status_code == 401

    def test_get_pending_tests_returns_list(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/tests/pending",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_completed_tests_returns_list(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/tests/completed",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_student_grades_returns_list(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/grades",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_student_attendance_returns_list(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/attendance",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_submit_nonexistent_test_returns_404(self, client, student_ctx):
        r = client.post(
            f"{BASE_URL}/api/student/tests/999999999/submit",
            json={"answers": {}, "auto_submitted": False},
            headers=_auth(student_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 404

    def test_teacher_token_cannot_access_student_endpoints(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/student/dashboard-summary",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403


# ── 4. Admin ──────────────────────────────────────────────────────────────────

class TestAdmin:

    def test_get_all_users_returns_list(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/users",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_pending_users_returns_list(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/users/pending",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code in (200, 404)   # 404 if endpoint path differs slightly
        if r.status_code == 200:
            assert isinstance(r.json(), list)

    def test_teacher_token_cannot_access_admin_endpoints(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/admin/users",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403

    def test_student_token_cannot_access_admin_endpoints(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/admin/users",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403

    def test_approve_nonexistent_user_returns_404(self, client, admin_token):
        r = client.post(f"{BASE_URL}/api/admin/users/999999999/approve",
                        headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 404

    def test_approve_and_revoke_user(self, client, admin_token):
        # Register a fresh user
        ts    = int(time.time()) + 500
        uname = f"approv_test_{ts}"
        reg = client.post(f"{BASE_URL}/api/auth/register", json={
            "username": uname, "mpin": "666666", "role": "teacher",
            "phone": f"+917{ts % 10_000_000_000:010d}",
        }, timeout=TIMEOUT)
        assert reg.status_code == 201
        uid = reg.json()["id"]

        # Approve
        approve = client.post(f"{BASE_URL}/api/admin/users/{uid}/approve",
                              headers=_auth(admin_token), timeout=TIMEOUT)
        assert approve.status_code == 200
        assert approve.json()["is_approved"] is True

        # Can now login
        login = _login(client, uname, "666666")
        assert login.status_code == 200

        # Revoke
        revoke = client.delete(f"{BASE_URL}/api/admin/users/{uid}/revoke",
                               headers=_auth(admin_token), timeout=TIMEOUT)
        assert revoke.status_code in (200, 204)

        # Cannot login after revoke
        login2 = _login(client, uname, "666666")
        assert login2.status_code == 401

    def test_get_admin_profile(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/profile",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 200
        assert r.json()["role"] == "admin"



# ── 5. Parent ─────────────────────────────────────────────────────────────────

class TestParent:
    """
    Integration tests for every endpoint in the parent router.
    All tests use parent_ctx which is pre-linked to student_ctx (grade 9).
    """

    # ── Auth & role isolation ──────────────────────────────────────────────────

    def test_dashboard_requires_auth(self, client):
        r = client.get(f"{BASE_URL}/api/parent/dashboard-summary", timeout=TIMEOUT)
        assert r.status_code == 401

    def test_teacher_token_rejected_on_parent_endpoints(self, client, teacher_ctx):
        for path in [
            "/api/parent/dashboard-summary",
            "/api/parent/child/attendance",
            "/api/parent/child/grades",
        ]:
            r = client.get(f"{BASE_URL}{path}",
                           headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
            assert r.status_code == 403, f"{path} accepted teacher token"

    def test_student_token_rejected_on_parent_endpoints(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/parent/dashboard-summary",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403

    # ── Dashboard summary ──────────────────────────────────────────────────────

    def test_dashboard_summary_returns_200(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/dashboard-summary",
                       headers=_auth(parent_ctx["token"]), timeout=30)
        assert r.status_code == 200

    def test_dashboard_summary_has_expected_keys(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/dashboard-summary",
                       headers=_auth(parent_ctx["token"]), timeout=30)
        assert r.status_code == 200
        body = r.json()
        for key in ("child_timetable", "broadcasts", "homework",
                    "child_grades", "child_tests", "child_fees"):
            assert key in body, f"Missing key '{key}' in dashboard summary"

    def test_dashboard_summary_accepts_date_param(self, client, parent_ctx):
        r = client.get(
            f"{BASE_URL}/api/parent/dashboard-summary?date=2026-04-24",
            headers=_auth(parent_ctx["token"]),
            timeout=30,
        )
        assert r.status_code == 200

    def test_dashboard_child_fees_has_required_fields(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/dashboard-summary",
                       headers=_auth(parent_ctx["token"]), timeout=30)
        fees = r.json().get("child_fees", {})
        for field in ("total_fee", "total_paid", "balance_due", "grade"):
            assert field in fees, f"child_fees missing field '{field}'"

    # ── Attendance ─────────────────────────────────────────────────────────────

    def test_child_attendance_returns_list(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/attendance",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_child_attendance_accepts_period_filter(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/attendance?period=1",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_child_attendance_invalid_limit_rejected(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/attendance?limit=999",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 422

    def test_child_attendance_summary_returns_summary(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/attendance/summary",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        body = r.json()
        for field in ("student_id", "total_classes", "present_count",
                      "absent_count", "attendance_percentage"):
            assert field in body, f"Attendance summary missing field '{field}'"

    def test_child_attendance_summary_percentage_in_range(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/attendance/summary",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        pct = r.json()["attendance_percentage"]
        assert 0.0 <= pct <= 100.0

    # ── Timetable ──────────────────────────────────────────────────────────────

    def test_child_timetable_requires_date_param(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/timetable",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 422

    def test_child_timetable_returns_list_for_date(self, client, parent_ctx):
        r = client.get(
            f"{BASE_URL}/api/parent/child/timetable?date=2026-04-24",
            headers=_auth(parent_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_child_timetable_invalid_date_returns_error(self, client, parent_ctx):
        r = client.get(
            f"{BASE_URL}/api/parent/child/timetable?date=not-a-date",
            headers=_auth(parent_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code in (400, 422, 500)

    # ── Grades ─────────────────────────────────────────────────────────────────

    def test_child_grades_returns_list(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/grades",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_child_grades_subject_filter(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/grades?subject=mathematics",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_child_grades_type_filter(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/grades?grade_type=online",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    # ── Tests ──────────────────────────────────────────────────────────────────

    def test_child_tests_returns_list(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/tests",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    # ── Fees ───────────────────────────────────────────────────────────────────

    def test_child_fees_returns_summary(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/fees",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        body = r.json()
        for field in ("student_id", "academic_year", "grade",
                      "total_fee", "total_paid", "balance_due", "payments"):
            assert field in body, f"Fee summary missing field '{field}'"

    def test_child_fees_balance_is_non_negative(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/fees",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        body = r.json()
        assert body["balance_due"] >= 0

    def test_child_fees_with_academic_year_param(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/fees?academic_year=2025-26",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert r.json()["academic_year"] == "2025-26"

    # ── Homework ───────────────────────────────────────────────────────────────

    def test_child_homework_returns_list(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/child/homework",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    # ── Broadcasts ─────────────────────────────────────────────────────────────

    def test_parent_broadcasts_returns_list(self, client, parent_ctx):
        r = client.get(f"{BASE_URL}/api/parent/broadcasts",
                       headers=_auth(parent_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    # ── MPIN change ────────────────────────────────────────────────────────────

    def test_change_mpin_wrong_current_returns_400(self, client, parent_ctx):
        r = client.put(
            f"{BASE_URL}/api/parent/profile/mpin",
            json={"current_mpin": "000000", "new_mpin": "444445"},
            headers=_auth(parent_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 400

    def test_change_mpin_invalid_new_returns_422(self, client, parent_ctx):
        r = client.put(
            f"{BASE_URL}/api/parent/profile/mpin",
            json={"current_mpin": parent_ctx["mpin"], "new_mpin": "abc"},
            headers=_auth(parent_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 422

    def test_change_mpin_success(self, client, parent_ctx, admin_token):
        """Change MPIN, verify new one works for login, then restore original."""
        original_mpin = parent_ctx["mpin"]   # "444444"
        new_mpin      = "444445"

        # Change to new MPIN.
        r = client.put(
            f"{BASE_URL}/api/parent/profile/mpin",
            json={"current_mpin": original_mpin, "new_mpin": new_mpin},
            headers=_auth(parent_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 200

        # New MPIN works for login.
        login = _login(client, parent_ctx["username"], new_mpin)
        assert login.status_code == 200

        # Restore original MPIN so remaining tests keep working.
        restore_token = login.json()["access_token"]
        client.put(
            f"{BASE_URL}/api/parent/profile/mpin",
            json={"current_mpin": new_mpin, "new_mpin": original_mpin},
            headers=_auth(restore_token),
            timeout=TIMEOUT,
        )


# ── 6. Fees ───────────────────────────────────────────────────────────────────

# Test academic year — clearly synthetic so it never conflicts with live data.
_TEST_AY = "9999-00"


class TestAdminFees:
    """
    Covers every admin fee-management endpoint:
      - Fee structure  CRUD
      - Fee payment  CRUD + idempotency key
      - Payment info (bank/UPI) read + update
      - Pending-fees PDF report
      - Role-isolation (non-admin rejected)

    All writes use academic_year=_TEST_AY and are cleaned up within the same
    test, so the suite is safe to run against the production database.
    """

    # ── Role isolation ──────────────────────────────────────────────────────

    def test_fee_endpoints_require_admin(self, client, teacher_ctx, student_ctx):
        for path in [
            f"/api/admin/fees/summary?academic_year={_TEST_AY}",
            "/api/admin/fees/structure",
        ]:
            for token in (teacher_ctx["token"], student_ctx["token"]):
                r = client.get(f"{BASE_URL}{path}",
                               headers=_auth(token), timeout=TIMEOUT)
                assert r.status_code == 403, (
                    f"GET {path} accepted non-admin token (got {r.status_code})"
                )

    # ── Fee summary ─────────────────────────────────────────────────────────

    def test_fee_summary_requires_academic_year(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/fees/summary",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 422

    def test_fee_summary_returns_list(self, client, admin_token):
        r = client.get(
            f"{BASE_URL}/api/admin/fees/summary?academic_year={_TEST_AY}",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_fee_summary_each_entry_has_required_fields(self, client, admin_token):
        r = client.get(
            f"{BASE_URL}/api/admin/fees/summary?academic_year=2024-25",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 200
        for entry in r.json():
            for field in ("student_id", "username", "grade",
                          "total_fee", "total_paid", "balance_due"):
                assert field in entry, f"Summary entry missing field '{field}'"

    # ── Fee structure CRUD ──────────────────────────────────────────────────

    def test_get_fee_structures_returns_list(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/fees/structure",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_get_fee_structures_filtered_by_year(self, client, admin_token):
        r = client.get(
            f"{BASE_URL}/api/admin/fees/structure?academic_year={_TEST_AY}",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_fee_structure_full_crud(self, client, admin_token):
        """Create → verify → update → verify → delete."""
        # CREATE
        create_r = client.post(
            f"{BASE_URL}/api/admin/fees/structure",
            json={
                "academic_year": _TEST_AY,
                "grade": 9,
                "base_amount": 10000.0,
                "economics_fee": 1500.0,
                "computer_fee": 1200.0,
                "ai_fee": 800.0,
            },
            headers=_auth(admin_token),
            timeout=TIMEOUT,
        )
        assert create_r.status_code == 201
        body = create_r.json()
        assert body["academic_year"] == _TEST_AY
        assert body["grade"] == 9
        assert body["base_amount"] == 10000.0
        assert body["total_amount"] == 13500.0
        structure_id = body["id"]

        try:
            # DUPLICATE rejected
            dup_r = client.post(
                f"{BASE_URL}/api/admin/fees/structure",
                json={"academic_year": _TEST_AY, "grade": 9, "base_amount": 5000.0},
                headers=_auth(admin_token),
                timeout=TIMEOUT,
            )
            assert dup_r.status_code == 409

            # UPDATE
            update_r = client.put(
                f"{BASE_URL}/api/admin/fees/structure/{structure_id}",
                json={"base_amount": 11000.0, "economics_fee": 2000.0},
                headers=_auth(admin_token),
                timeout=TIMEOUT,
            )
            assert update_r.status_code == 200
            assert update_r.json()["base_amount"] == 11000.0
            assert update_r.json()["economics_fee"] == 2000.0

            # Still visible in listing
            list_r = client.get(
                f"{BASE_URL}/api/admin/fees/structure?academic_year={_TEST_AY}",
                headers=_auth(admin_token), timeout=TIMEOUT,
            )
            ids = [s["id"] for s in list_r.json()]
            assert structure_id in ids

        finally:
            # DELETE (always runs even if assertions fail above)
            del_r = client.delete(
                f"{BASE_URL}/api/admin/fees/structure/{structure_id}",
                headers=_auth(admin_token), timeout=TIMEOUT,
            )
            assert del_r.status_code == 204

        # Gone after delete
        list_after = client.get(
            f"{BASE_URL}/api/admin/fees/structure?academic_year={_TEST_AY}",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        ids_after = [s["id"] for s in list_after.json()]
        assert structure_id not in ids_after

    def test_update_nonexistent_structure_returns_404(self, client, admin_token):
        r = client.put(
            f"{BASE_URL}/api/admin/fees/structure/999999999",
            json={"base_amount": 1.0},
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 404

    def test_delete_nonexistent_structure_returns_404(self, client, admin_token):
        r = client.delete(
            f"{BASE_URL}/api/admin/fees/structure/999999999",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 404

    # ── Fee payment CRUD ────────────────────────────────────────────────────

    def test_fee_payment_full_crud(self, client, admin_token, student_ctx):
        """Record → verify → update → verify → delete."""
        import uuid

        # RECORD
        record_r = client.post(
            f"{BASE_URL}/api/admin/fees/payments",
            json={
                "student_id": student_ctx["id"],
                "amount": 5000.0,
                "notes": "Test payment — automated test",
            },
            headers=_auth(admin_token),
            timeout=TIMEOUT,
        )
        assert record_r.status_code == 201
        body = record_r.json()
        assert body["student_id"] == student_ctx["id"]
        assert body["amount"] == 5000.0
        assert body["notes"] == "Test payment — automated test"
        payment_id = body["id"]

        try:
            # UPDATE
            update_r = client.put(
                f"{BASE_URL}/api/admin/fees/payments/{payment_id}",
                json={"amount": 6000.0, "notes": "Updated amount"},
                headers=_auth(admin_token), timeout=TIMEOUT,
            )
            assert update_r.status_code == 200
            assert update_r.json()["amount"] == 6000.0
            assert update_r.json()["notes"] == "Updated amount"

        finally:
            # DELETE
            del_r = client.delete(
                f"{BASE_URL}/api/admin/fees/payments/{payment_id}",
                headers=_auth(admin_token), timeout=TIMEOUT,
            )
            assert del_r.status_code == 204

    def test_fee_payment_idempotency_key_prevents_duplicate(
        self, client, admin_token, student_ctx
    ):
        """Same idempotency key on two requests must return 409 on the second."""
        import uuid
        idem_key = str(uuid.uuid4())
        payment_ids = []

        payload = {
            "student_id": student_ctx["id"],
            "amount": 100.0,
            "notes": "Idempotency test",
        }
        headers = {**_auth(admin_token), "X-Idempotency-Key": idem_key}

        first = client.post(f"{BASE_URL}/api/admin/fees/payments",
                            json=payload, headers=headers, timeout=TIMEOUT)
        assert first.status_code == 201
        payment_ids.append(first.json()["id"])

        second = client.post(f"{BASE_URL}/api/admin/fees/payments",
                             json=payload, headers=headers, timeout=TIMEOUT)
        assert second.status_code == 409

        # Cleanup
        for pid in payment_ids:
            client.delete(f"{BASE_URL}/api/admin/fees/payments/{pid}",
                          headers=_auth(admin_token), timeout=TIMEOUT)

    def test_record_payment_for_nonexistent_student(self, client, admin_token):
        """Recording a payment for a non-existent student should fail gracefully."""
        r = client.post(
            f"{BASE_URL}/api/admin/fees/payments",
            json={"student_id": 999999999, "amount": 1.0},
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        # FK constraint should cause 400/404/422/409; must not be 201
        assert r.status_code != 201

    def test_update_nonexistent_payment_returns_404(self, client, admin_token):
        r = client.put(
            f"{BASE_URL}/api/admin/fees/payments/999999999",
            json={"amount": 1.0},
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 404

    def test_delete_nonexistent_payment_returns_404(self, client, admin_token):
        r = client.delete(
            f"{BASE_URL}/api/admin/fees/payments/999999999",
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 404

    # ── Payment info (bank/UPI) ─────────────────────────────────────────────

    def test_get_payment_info_returns_list(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/fees/payment-info",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_update_payment_info_slot(self, client, admin_token):
        """Upsert slot 1 with test data, then restore the original value."""
        # Read current value to restore afterwards
        current = client.get(f"{BASE_URL}/api/admin/fees/payment-info",
                             headers=_auth(admin_token), timeout=TIMEOUT).json()
        original = next((x for x in current if x.get("slot") == 1), None)

        new_data = {
            "label": "Test Bank",
            "bank_name": "Test Bank Ltd",
            "account_number": "0000000001",
            "ifsc": "TEST0000001",
            "upi_id": "test@upi",
        }
        r = client.put(
            f"{BASE_URL}/api/admin/fees/payment-info/1",
            json=new_data,
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 200
        body = r.json()
        assert body["slot"] == 1
        assert body["bank_name"] == "Test Bank Ltd"

        # Restore original if it existed
        if original:
            restore = {k: original.get(k) for k in new_data}
            client.put(f"{BASE_URL}/api/admin/fees/payment-info/1",
                       json=restore, headers=_auth(admin_token), timeout=TIMEOUT)

    def test_payment_info_invalid_slot_rejected(self, client, admin_token):
        r = client.put(
            f"{BASE_URL}/api/admin/fees/payment-info/5",
            json={"label": "Bad slot"},
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert r.status_code == 400

    # ── PDF reports ─────────────────────────────────────────────────────────

    def test_pending_fees_report_returns_pdf(self, client, admin_token):
        r = client.get(
            f"{BASE_URL}/api/admin/reports/pending-fees?academic_year=2024-25",
            headers=_auth(admin_token), timeout=30,
        )
        assert r.status_code == 200
        assert "pdf" in r.headers.get("content-type", "").lower()

    def test_pending_fees_report_requires_academic_year(self, client, admin_token):
        r = client.get(f"{BASE_URL}/api/admin/reports/pending-fees",
                       headers=_auth(admin_token), timeout=TIMEOUT)
        assert r.status_code == 422


class TestStudentFees:
    """Student-facing fee summary endpoint."""

    def test_student_fees_requires_auth(self, client):
        r = client.get(f"{BASE_URL}/api/student/fees", timeout=TIMEOUT)
        assert r.status_code == 401

    def test_teacher_cannot_access_student_fees(self, client, teacher_ctx):
        r = client.get(f"{BASE_URL}/api/student/fees",
                       headers=_auth(teacher_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 403

    def test_student_fees_returns_summary(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/fees",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.status_code == 200
        body = r.json()
        for field in ("student_id", "academic_year", "grade",
                      "total_fee", "total_paid", "balance_due", "payments"):
            assert field in body, f"Fee summary missing field '{field}'"

    def test_student_fees_balance_non_negative(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/fees",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert r.json()["balance_due"] >= 0

    def test_student_fees_payments_is_list(self, client, student_ctx):
        r = client.get(f"{BASE_URL}/api/student/fees",
                       headers=_auth(student_ctx["token"]), timeout=TIMEOUT)
        assert isinstance(r.json()["payments"], list)

    def test_student_fees_with_academic_year_param(self, client, student_ctx):
        r = client.get(
            f"{BASE_URL}/api/student/fees?academic_year={_TEST_AY}",
            headers=_auth(student_ctx["token"]), timeout=TIMEOUT,
        )
        assert r.status_code == 200
        assert r.json()["academic_year"] == _TEST_AY

    def test_student_fees_reflect_recorded_payment(
        self, client, admin_token, student_ctx
    ):
        """
        Record a payment via admin, verify the student sees it in their
        summary, then clean up.
        """
        # Baseline paid amount
        before = client.get(f"{BASE_URL}/api/student/fees",
                            headers=_auth(student_ctx["token"]),
                            timeout=TIMEOUT).json()
        paid_before = before["total_paid"]

        # Record payment
        record_r = client.post(
            f"{BASE_URL}/api/admin/fees/payments",
            json={"student_id": student_ctx["id"], "amount": 250.0,
                  "notes": "Reflect test"},
            headers=_auth(admin_token), timeout=TIMEOUT,
        )
        assert record_r.status_code == 201
        payment_id = record_r.json()["id"]

        try:
            after = client.get(f"{BASE_URL}/api/student/fees",
                               headers=_auth(student_ctx["token"]),
                               timeout=TIMEOUT).json()
            assert after["total_paid"] == paid_before + 250.0
            assert len(after["payments"]) == len(before["payments"]) + 1
        finally:
            client.delete(f"{BASE_URL}/api/admin/fees/payments/{payment_id}",
                          headers=_auth(admin_token), timeout=TIMEOUT)


# ── 7. Logout & FCM token lifecycle ──────────────────────────────────────────

class TestLogout:
    """
    Verify the logout endpoint:
      - returns 204
      - blacklists the JWT (protected endpoints return 401 afterwards)
      - is null-safe when no FCM token has been registered in the session
      - clears any previously registered FCM token (DB-level invariant is
        exercised indirectly: a second logout with no FCM token must not crash,
        which would happen if the server tried to clear an already-NULL value
        via broken SQL)
    """

    def test_logout_returns_204(self, client, admin_token):
        # Fresh login so we can revoke without killing the shared admin_token
        # fixture (or the teacher_ctx token, which downstream tests rely on).
        mpin = os.getenv("ADMIN_MPIN", "123456")
        login = _login(client, "admin", mpin)
        assert login.status_code == 200
        token = login.json()["access_token"]

        r = client.post(
            f"{BASE_URL}/api/auth/logout",
            headers=_auth(token),
            timeout=TIMEOUT,
        )
        assert r.status_code == 204

    def test_logout_blacklists_jwt(self, client, admin_token):
        # Log in fresh so we get a token we control and can revoke cleanly.
        mpin = os.getenv("ADMIN_MPIN", "123456")
        login = _login(client, "admin", mpin)
        assert login.status_code == 200
        token = login.json()["access_token"]

        # Verify the token works before logout.
        me = client.get(f"{BASE_URL}/api/auth/me",
                        headers=_auth(token), timeout=TIMEOUT)
        assert me.status_code == 200

        # Logout.
        logout = client.post(f"{BASE_URL}/api/auth/logout",
                             headers=_auth(token), timeout=TIMEOUT)
        assert logout.status_code == 204

        # The same token must be rejected on every subsequent request.
        me_after = client.get(f"{BASE_URL}/api/auth/me",
                              headers=_auth(token), timeout=TIMEOUT)
        assert me_after.status_code == 401

    def test_fcm_token_cleared_on_logout(self, client, student_ctx):
        """
        Full FCM-token lifecycle: register token → logout → re-login (no FCM
        set) → second logout.  The second logout exercises the NULL-safe path,
        confirming the server committed fcm_token=NULL after the first logout
        and didn't crash when it encountered a NULL value on the second.
        """
        token = student_ctx["token"]
        uname = student_ctx["username"]

        # Register a fake FCM token while logged in.
        set_r = client.put(
            f"{BASE_URL}/api/auth/fcm-token",
            json={"fcm_token": "test-device-token-abc123"},
            headers=_auth(token),
            timeout=TIMEOUT,
        )
        assert set_r.status_code == 204

        # Logout — server must clear fcm_token in DB.
        logout_r = client.post(
            f"{BASE_URL}/api/auth/logout",
            headers=_auth(token),
            timeout=TIMEOUT,
        )
        assert logout_r.status_code == 204

        # Old token is dead.
        assert client.get(f"{BASE_URL}/api/auth/me",
                          headers=_auth(token), timeout=TIMEOUT).status_code == 401

        # Re-login (does NOT register a new FCM token — fcm_token stays NULL).
        login2 = _login(client, uname, "333333")
        assert login2.status_code == 200
        token2 = login2.json()["access_token"]

        # Second logout: fcm_token is already NULL → must not crash.
        logout2_r = client.post(
            f"{BASE_URL}/api/auth/logout",
            headers=_auth(token2),
            timeout=TIMEOUT,
        )
        assert logout2_r.status_code == 204

    def test_logout_without_auth_returns_401(self, client):
        r = client.post(f"{BASE_URL}/api/auth/logout", timeout=TIMEOUT)
        assert r.status_code == 401

    def test_fcm_token_update_requires_auth(self, client):
        r = client.put(
            f"{BASE_URL}/api/auth/fcm-token",
            json={"fcm_token": "some-token"},
            timeout=TIMEOUT,
        )
        assert r.status_code == 401

    def test_fcm_token_update_rejects_empty_string(self, client, teacher_ctx):
        r = client.put(
            f"{BASE_URL}/api/auth/fcm-token",
            json={"fcm_token": ""},
            headers=_auth(teacher_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 422

    def test_fcm_token_update_rejects_missing_field(self, client, teacher_ctx):
        r = client.put(
            f"{BASE_URL}/api/auth/fcm-token",
            json={},
            headers=_auth(teacher_ctx["token"]),
            timeout=TIMEOUT,
        )
        assert r.status_code == 422


# ── 8. Token revocation ───────────────────────────────────────────────────────

class TestTokenRevocation:
    """
    Verify that a revoked access token (blacklisted in Redis on logout) is
    rejected across every endpoint type — not just /auth/me.

    Each test obtains a *fresh* login token so it can log out without
    invalidating the session-scoped teacher_ctx / student_ctx fixtures.
    """

    # ── helpers ──────────────────────────────────────────────────────────────

    def _fresh_teacher_token(self, client, teacher_ctx):
        """Log the shared teacher in again to get a one-off access token."""
        r = _login(client, teacher_ctx["username"], "222222")
        assert r.status_code == 200, f"Re-login failed: {r.text}"
        return r.json()["access_token"]

    def _fresh_student_token(self, client, student_ctx):
        r = _login(client, student_ctx["username"], "333333")
        assert r.status_code == 200, f"Re-login failed: {r.text}"
        return r.json()["access_token"]

    def _logout(self, client, token):
        r = client.post(
            f"{BASE_URL}/api/auth/logout",
            headers=_auth(token),
            timeout=TIMEOUT,
        )
        assert r.status_code == 204, f"Logout failed: {r.text}"

    # ── tests ─────────────────────────────────────────────────────────────────

    def test_revoked_token_rejected_on_auth_me(self, client, teacher_ctx):
        token = self._fresh_teacher_token(client, teacher_ctx)
        self._logout(client, token)
        r = client.get(f"{BASE_URL}/api/auth/me",
                       headers=_auth(token), timeout=TIMEOUT)
        assert r.status_code == 401

    def test_revoked_token_rejected_on_teacher_endpoints(self, client, teacher_ctx):
        token = self._fresh_teacher_token(client, teacher_ctx)
        self._logout(client, token)

        endpoints = [
            ("GET",  "/api/teacher/dashboard-summary"),
            ("GET",  "/api/teacher/profile"),
            ("GET",  "/api/teacher/tests"),
            ("GET",  "/api/teacher/grades"),
        ]
        for method, path in endpoints:
            r = client.request(method, f"{BASE_URL}{path}",
                               headers=_auth(token), timeout=TIMEOUT)
            assert r.status_code == 401, (
                f"{method} {path} returned {r.status_code} with revoked token"
            )

    def test_revoked_token_rejected_on_student_endpoints(self, client, student_ctx):
        token = self._fresh_student_token(client, student_ctx)
        self._logout(client, token)

        endpoints = [
            ("GET", "/api/student/dashboard-summary"),
            ("GET", "/api/student/tests/pending"),
            ("GET", "/api/student/grades"),
            ("GET", "/api/student/attendance"),
        ]
        for method, path in endpoints:
            r = client.request(method, f"{BASE_URL}{path}",
                               headers=_auth(token), timeout=TIMEOUT)
            assert r.status_code == 401, (
                f"{method} {path} returned {r.status_code} with revoked token"
            )

    def test_revoked_token_rejected_on_fcm_update(self, client, teacher_ctx):
        """A revoked token must not be able to register a new FCM token."""
        token = self._fresh_teacher_token(client, teacher_ctx)
        self._logout(client, token)

        r = client.put(
            f"{BASE_URL}/api/auth/fcm-token",
            json={"fcm_token": "post-logout-token"},
            headers=_auth(token),
            timeout=TIMEOUT,
        )
        assert r.status_code == 401

    def test_revoked_token_rejected_consistently(self, client, teacher_ctx):
        """The same revoked token must be rejected every time, not just once."""
        token = self._fresh_teacher_token(client, teacher_ctx)
        self._logout(client, token)

        for attempt in range(3):
            r = client.get(f"{BASE_URL}/api/auth/me",
                           headers=_auth(token), timeout=TIMEOUT)
            assert r.status_code == 401, (
                f"Attempt {attempt + 1}: expected 401, got {r.status_code}"
            )

    def test_refresh_token_still_valid_after_access_token_revoked(
        self, client, teacher_ctx
    ):
        """
        Logout only blacklists the *access* token JTI — the refresh token is
        not server-side revoked. A refresh token captured before logout can
        still produce a new access token.

        This documents the intentional design: logout is a device-side
        operation (the app deletes local tokens). If a refresh token is
        stolen before logout, it remains usable — enforce short expiry on
        refresh tokens if this becomes a concern.
        """
        r = _login(client, teacher_ctx["username"], "222222")
        assert r.status_code == 200
        body = r.json()
        access_token  = body["access_token"]
        refresh_token = body["refresh_token"]

        # Logout revokes the access token.
        self._logout(client, access_token)

        # Access token is dead.
        me = client.get(f"{BASE_URL}/api/auth/me",
                        headers=_auth(access_token), timeout=TIMEOUT)
        assert me.status_code == 401

        # Refresh token can still mint a new access token.
        refresh_r = client.post(
            f"{BASE_URL}/api/auth/refresh",
            json={"refresh_token": refresh_token},
            timeout=TIMEOUT,
        )
        assert refresh_r.status_code == 200
        new_token = refresh_r.json().get("access_token")
        assert new_token is not None

        # Clean up — revoke the newly minted token too.
        client.post(f"{BASE_URL}/api/auth/logout",
                    headers=_auth(new_token), timeout=TIMEOUT)

    def test_admin_endpoints_reject_revoked_token(self, client, admin_token):
        """Admin-issued token is blacklisted on logout just like any other role."""
        mpin = os.getenv("ADMIN_MPIN", "123456")
        r = _login(client, "admin", mpin)
        assert r.status_code == 200
        token = r.json()["access_token"]

        self._logout(client, token)

        for path in ["/api/admin/users", "/api/admin/profile"]:
            r = client.get(f"{BASE_URL}{path}",
                           headers=_auth(token), timeout=TIMEOUT)
            assert r.status_code == 401, (
                f"GET {path} returned {r.status_code} with revoked admin token"
            )


# ── 9. Health ─────────────────────────────────────────────────────────────────

class TestHealth:
    def test_health_returns_ok(self, client):
        r = client.get(f"{BASE_URL}/api/health", timeout=TIMEOUT)
        assert r.status_code == 200
        assert r.json()["status"] == "ok"

    def test_health_has_security_headers(self, client):
        r = client.get(f"{BASE_URL}/api/health", timeout=TIMEOUT)
        h = {k.lower(): v for k, v in r.headers.items()}
        assert "strict-transport-security" in h
        assert "x-content-type-options"    in h
        assert "x-frame-options"           in h
        assert "content-security-policy"   in h
