"""
Detection for attacks the rate limiters do not stop.

Login is limited to 10/min per (IP, username). That stops someone grinding one
account, and does nothing about the opposite shape: one password tried once
against many accounts. Spraying 200 usernames from a single IP is 200 requests
that each sit at 1/10 of their own budget. The global 300/min per-IP throttle
added in Wave 2 caps the volume but cannot tell spraying from a busy classroom.

Nothing was watching for it either. Failed logins go to the `mindforge.security`
logger at WARNING, and Sentry's logging integration turns WARNING into a
breadcrumb, not an event — so a spray is invisible unless something unrelated
errors in the same request.

These pin the decision logic. The Redis bookkeeping is exercised against the
live stack instead; this file stays free of I/O so it can run in CI.
"""

import pytest

from app.core.security_events import (
    SPRAY_DISTINCT_USERNAMES,
    SPRAY_WINDOW_SECONDS,
    is_spray,
    spray_summary,
)


class TestThreshold:
    def test_a_single_failure_is_not_an_attack(self):
        # Everyone mistypes. One failure must never page anyone.
        assert is_spray(1) is False

    def test_a_few_failures_are_not_an_attack(self):
        # A shared family device, or a parent guessing between two accounts.
        assert is_spray(3) is False

    def test_crossing_the_threshold_is_an_attack(self):
        assert is_spray(SPRAY_DISTINCT_USERNAMES) is True

    def test_well_past_the_threshold_is_an_attack(self):
        assert is_spray(SPRAY_DISTINCT_USERNAMES + 500) is True

    def test_just_below_the_threshold_is_not(self):
        assert is_spray(SPRAY_DISTINCT_USERNAMES - 1) is False


class TestThresholdIsSanelyChosen:
    def test_high_enough_to_survive_a_shared_device(self):
        # A school reception desk or a family tablet legitimately fails a few
        # different logins in a row. Too low and the alert is noise, which is
        # worse than no alert — it trains people to ignore it.
        assert SPRAY_DISTINCT_USERNAMES >= 5

    def test_low_enough_to_catch_a_real_spray(self):
        # An attacker walking a class list is trying tens of accounts.
        assert SPRAY_DISTINCT_USERNAMES <= 20

    def test_window_is_long_enough_to_span_a_slow_spray(self):
        # Spraying is deliberately slow to stay under per-account limits, so a
        # 60-second window would miss it entirely.
        assert SPRAY_WINDOW_SECONDS >= 300


class TestSummaryIsSafeToLog:
    def test_summary_reports_the_count_and_the_ip(self):
        s = spray_summary("203.0.113.9", 12)
        assert "203.0.113.9" in s
        assert "12" in s

    def test_summary_never_carries_usernames_or_credentials(self):
        # The alert goes to Sentry. It needs to say "this IP is spraying", not
        # ship a list of the children's accounts that were targeted.
        s = spray_summary("203.0.113.9", 12)
        lowered = s.lower()
        for leak in ("mpin", "password", "token", "nitin", "username="):
            assert leak not in lowered, f"summary leaked {leak!r}: {s}"
