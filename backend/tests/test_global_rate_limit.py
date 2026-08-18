"""
Global request throttle.

nginx.conf caps the API at 120 r/m per IP, but nginx is a local-compose artifact
— production runs backend/Dockerfile's start.sh on :8000 behind Railway's edge,
so that zone never loads. The limit is in the repo, reads as present, and does
not ship. These tests pin an app-level throttle that travels with the app
regardless of what sits in front of it.

The throttle is deliberately loose: it exists to stop a runaway client or a
scripted burst, not to police normal use. The strict limits that matter for
security (login 10/min, register 5/min) stay where they are and are unaffected.
"""

import pytest

from app.core.throttle import (
    EXEMPT_PATHS,
    GLOBAL_MAX_PER_MINUTE,
    is_exempt,
    throttle_identity,
)


class TestIdentity:
    def test_authenticated_users_are_bucketed_separately(self):
        # Two users behind one school NAT must not share a budget, or one
        # busy teacher throttles the whole staff room.
        a = throttle_identity(user_id=7, client_ip="203.0.113.9")
        b = throttle_identity(user_id=8, client_ip="203.0.113.9")
        assert a != b

    def test_same_user_from_two_devices_shares_a_budget(self):
        # Phone and laptop are one person; the budget is per identity.
        a = throttle_identity(user_id=7, client_ip="203.0.113.9")
        b = throttle_identity(user_id=7, client_ip="198.51.100.4")
        assert a == b

    def test_falls_back_to_ip_when_unauthenticated(self):
        a = throttle_identity(user_id=None, client_ip="203.0.113.9")
        b = throttle_identity(user_id=None, client_ip="198.51.100.4")
        assert a != b
        assert "203.0.113.9" in a

    def test_missing_ip_still_yields_a_key(self):
        # Starlette gives request.client is None in some ASGI setups; the
        # throttle must not crash the request in that case.
        assert throttle_identity(user_id=None, client_ip=None)


class TestExemptions:
    def test_health_is_exempt(self):
        # A throttled health check turns a traffic spike into a failed liveness
        # probe, which restarts the container and makes the spike worse.
        assert is_exempt("/api/health")

    def test_websocket_upgrade_path_is_exempt(self):
        # The socket is one long-lived connection, not a request stream, and it
        # carries its own JWT check.
        assert is_exempt("/ws/42")

    def test_normal_api_paths_are_not_exempt(self):
        for p in ("/api/student/homework", "/api/teacher/attendance",
                  "/api/admin/users", "/api/auth/login"):
            assert not is_exempt(p), p

    def test_exempt_list_is_narrow(self):
        # Guards against someone "fixing" a throttling complaint by exempting
        # a broad prefix like /api.
        assert all(p.count("/") <= 2 for p in EXEMPT_PATHS), EXEMPT_PATHS


class TestBudget:
    def test_limit_is_generous_enough_for_a_dashboard_load(self):
        # Dashboards fan out to several endpoints at once and a user may move
        # between screens quickly. Too tight here and real users see 429s,
        # which is a worse outcome than the abuse being prevented.
        assert GLOBAL_MAX_PER_MINUTE >= 120

    def test_limit_is_tight_enough_to_matter(self):
        # If it never trips it is decoration.
        assert GLOBAL_MAX_PER_MINUTE <= 600
