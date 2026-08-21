"""
Weak-MPIN policy: reject guessable PINs when they are *set*, stay lenient at
login so a legacy user with a weak PIN can still get in and change it.

That asymmetry is the whole design, and it is easy to break by wiring the wrong
validator onto a field — a set-site that accepts weak PINs silently weakens
everyone who signs up after, and a login that rejects them locks out the exact
users the policy is trying to help. These tests pin both the guessability rule
and which boundary each schema field is wired to.
"""

import pytest

from app.models.user import UserRole
from app.schemas.user import (
    AdminMpinUpdate,
    UserLoginRequest,
    UserRegisterRequest,
    _is_weak_mpin,
    _validate_mpin_format,
    _validate_strong_mpin,
)

WEAK = [
    "000000", "111111", "999999",          # all one digit
    "123456", "234567", "345678",          # ascending run
    "654321", "987654",                    # descending run
    "123123", "456456",                    # first half repeated
    "121212", "343434",                    # two-digit pattern
    "159753", "147258", "789456", "456789",  # keypad-shape PINs
]

# Verified strong against the rule below — no run, no repeat, not a keypad shape.
STRONG = ["918273", "194837", "240815", "738261", "506192", "802461"]


class TestGuessabilityRule:
    @pytest.mark.parametrize("pin", WEAK)
    def test_weak_pins_are_flagged(self, pin):
        assert _is_weak_mpin(pin) is True

    @pytest.mark.parametrize("pin", STRONG)
    def test_strong_pins_pass(self, pin):
        assert _is_weak_mpin(pin) is False

    def test_near_miss_patterns_are_not_over_flagged(self):
        # These look patterned but aren't caught by any rule, and must NOT be
        # rejected — over-blocking pushes users toward the few "allowed" PINs.
        for pin in ("112233", "100000", "986532"):
            assert _is_weak_mpin(pin) is False


class TestValidators:
    def test_strong_validator_rejects_weak_with_a_helpful_message(self):
        with pytest.raises(ValueError) as e:
            _validate_strong_mpin("123456")
        assert "guess" in str(e.value).lower()

    def test_strong_validator_returns_strong_unchanged(self):
        assert _validate_strong_mpin("918273") == "918273"

    def test_format_validator_accepts_weak(self):
        # The login path. A weak but well-formed PIN must pass shape validation.
        assert _validate_mpin_format("123456") == "123456"

    def test_format_validator_still_enforces_six_digits(self):
        for bad in ("12345", "1234567", "12ab56", ""):
            with pytest.raises(ValueError):
                _validate_mpin_format(bad)


class TestSchemaWiring:
    """The security-critical part: each field bound to the right boundary."""

    def test_login_accepts_a_weak_mpin(self):
        # Legacy users must not be locked out by the strength rule.
        assert UserLoginRequest(username="u", mpin="123456").mpin == "123456"

    def test_registration_rejects_a_weak_mpin(self):
        with pytest.raises(ValueError) as e:
            UserRegisterRequest(username="user1", mpin="123456", role=UserRole.student)
        assert "guess" in str(e.value).lower()

    def test_registration_accepts_a_strong_mpin(self):
        req = UserRegisterRequest(username="user1", mpin="918273", role=UserRole.student)
        assert req.mpin == "918273"

    def test_change_mpin_rejects_a_weak_new_pin(self):
        with pytest.raises(ValueError):
            AdminMpinUpdate(current_mpin="918273", new_mpin="123456")

    def test_change_mpin_allows_a_weak_current_pin(self):
        # Proving you know your existing (possibly weak) PIN must not be blocked,
        # or a legacy weak-PIN user can never reach the change flow.
        upd = AdminMpinUpdate(current_mpin="123456", new_mpin="918273")
        assert upd.current_mpin == "123456"
