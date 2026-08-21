"""
Account-state login gate: an unapproved, deactivated, or deleted account cannot
authenticate, and the response for each is the right one.

This is the policy behind three login rejections. It used to live inline in the
login handler with no coverage (the reason the register row was stale); it is
now a pure function, tested here, and the exact same object the router calls.
"""

from types import SimpleNamespace

import pytest

from app.core.account_state import login_block_reason, login_block_response


def _user(*, approved=True, active=True, deleted=False):
    return SimpleNamespace(
        is_approved=approved,
        is_active=active,
        deleted_at="2026-08-22T00:00:00Z" if deleted else None,
    )


class TestReason:
    def test_a_good_account_is_not_blocked(self):
        assert login_block_reason(_user()) is None

    def test_unapproved_is_blocked(self):
        assert login_block_reason(_user(approved=False)) == "unapproved"

    def test_deactivated_is_blocked(self):
        assert login_block_reason(_user(active=False)) == "deactivated"

    def test_deleted_is_blocked(self):
        assert login_block_reason(_user(deleted=True)) == "deleted"

    def test_deleted_takes_precedence_over_other_flags(self):
        # A deactivated-then-deleted account must be answered as deleted (an
        # opaque "invalid"), never as "deactivated" — which would confirm it
        # existed. Precedence is the security-relevant part.
        assert login_block_reason(_user(approved=False, active=False, deleted=True)) == "deleted"


class TestResponse:
    def test_unapproved_is_403_and_says_pending(self):
        exc = login_block_response("unapproved")
        assert exc.status_code == 403
        assert "pending" in exc.detail.lower()

    def test_deactivated_is_403_and_says_deactivated(self):
        exc = login_block_response("deactivated")
        assert exc.status_code == 403
        assert "deactivated" in exc.detail.lower()

    def test_deleted_is_a_generic_401_with_no_enumeration_tell(self):
        # Must look identical to a wrong-username response: same 401, same
        # "Invalid username or MPIN." — never a "deleted"/"revoked" hint.
        exc = login_block_response("deleted")
        assert exc.status_code == 401
        assert exc.detail == "Invalid username or MPIN."
        assert "delet" not in exc.detail.lower()
