"""
Username enumeration via login timing.

`login()` short-circuits: `if not user or not verify_mpin(...)`. When the
username does not exist, Python never evaluates the right-hand side, so bcrypt
never runs and the request returns in a few milliseconds. When it does exist,
bcrypt at work factor 12 costs a couple of hundred.

Measured against the local stack on 2026-08-19: 238.7 ms for a real username
with a wrong PIN, 3.9 ms for one that does not exist — a 61x gap, with every
sample a clean 401. Identical response bodies do not help when the latency
answers the question.

That matters more here than on a typical app. Usernames are school-issued and
predictable (`river_kid`, `demo_admin`, `nitin_dad`), so confirming which exist
turns a guessing game into a target list — of accounts belonging to children.

`verify_mpin_constant_time` does the same bcrypt work either way.
"""

import time

import pytest

from app.core.security import hash_mpin, verify_mpin_constant_time


class _User:
    """Stand-in for the ORM row — only mpin_hash is read."""
    def __init__(self, mpin_hash: str):
        self.mpin_hash = mpin_hash


@pytest.fixture(scope="module")
def real_user():
    return _User(hash_mpin("847362"))


class TestCorrectness:
    def test_correct_mpin_passes(self, real_user):
        assert verify_mpin_constant_time("847362", real_user) is True

    def test_wrong_mpin_fails(self, real_user):
        assert verify_mpin_constant_time("000000", real_user) is False

    def test_absent_user_fails(self):
        # The security property: no user must never authenticate, however the
        # timing is equalised.
        assert verify_mpin_constant_time("847362", None) is False

    def test_absent_user_fails_even_for_an_empty_mpin(self):
        assert verify_mpin_constant_time("", None) is False


class TestTiming:
    def test_absent_user_costs_about_the_same_as_a_present_one(self, real_user):
        # The bug being fixed was a ~60x gap. bcrypt dominates both paths once
        # the dummy verification is in place, so they land within a small factor
        # of each other. The threshold is deliberately loose — this asserts the
        # work is *being done*, and must not turn into a flaky benchmark on a
        # noisy CI runner.
        def median_ms(fn, n=5):
            xs = []
            for _ in range(n):
                t0 = time.perf_counter()
                fn()
                xs.append((time.perf_counter() - t0) * 1000)
            xs.sort()
            return xs[len(xs) // 2]

        present = median_ms(lambda: verify_mpin_constant_time("000000", real_user))
        absent = median_ms(lambda: verify_mpin_constant_time("000000", None))

        assert absent > 1.0, (
            f"absent-user path took {absent:.2f} ms — too fast to have hashed "
            "anything, so the timing oracle is still open"
        )
        ratio = max(present, absent) / max(min(present, absent), 0.001)
        assert ratio < 3, (
            f"timing still distinguishable: present {present:.1f} ms vs "
            f"absent {absent:.1f} ms ({ratio:.1f}x)"
        )
