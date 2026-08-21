"""
Account-state login gate: an unapproved, deactivated, or deleted account cannot
authenticate, and the response for each is the right one.

This is the policy behind three login rejections. It used to live inline in the
login handler with no coverage (the reason the register row was stale); it is
now a pure function, tested here, and the exact same object the router calls.
"""

from types import SimpleNamespace

import pytest

from app.core.account_state import (
    login_block_reason,
    login_block_response,
    self_delete_block_reason,
    self_delete_block_response,
)


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


class TestSelfDeletePolicy:
    """Which roles may delete their own account. App-store policy needs a
    self-delete path, but not for every role — and the platform owner in
    particular must not be able to remove the only account that administers the
    platform."""

    def test_parent_and_teacher_may_self_delete(self):
        assert self_delete_block_reason("parent") is None
        assert self_delete_block_reason("teacher") is None

    def test_admin_is_blocked(self):
        assert self_delete_block_reason("admin") == "admin"

    def test_student_is_blocked(self):
        assert self_delete_block_reason("student") == "student"

    def test_owner_is_blocked(self):
        # The gap this fixed: before, an owner fell through delete_my_account
        # and soft-deleted itself, orphaning the platform.
        assert self_delete_block_reason("owner") == "owner"

    def test_accepts_an_enum_role_not_just_a_string(self):
        from app.models.user import UserRole
        assert self_delete_block_reason(UserRole.owner) == "owner"
        assert self_delete_block_reason(UserRole.parent) is None

    def test_responses_are_403_with_role_specific_text(self):
        assert self_delete_block_response("admin").status_code == 403
        assert "admin tools" in self_delete_block_response("admin").detail.lower()
        assert "parent" in self_delete_block_response("student").detail.lower()
        assert "owner" in self_delete_block_response("owner").detail.lower()
