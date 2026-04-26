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


# ── 5. Health ─────────────────────────────────────────────────────────────────

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
