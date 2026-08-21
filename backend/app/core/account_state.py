"""
One choke-point for "may this account authenticate at all?"

The login query already excludes soft-deleted rows, so on the login path `user`
is a live account by the time these run. Pulling the decision out here does two
things: it makes the policy unit-testable without a database, and it re-asserts
the deleted check defensively — any future path that loads a user some other way
still cannot wave a revoked, unapproved, or deactivated account through.

The decision is pure (returns a reason or None); the side effects — logging the
rejection with the caller's IP, and raising the response — stay in the router,
so this can be tested as data.
"""

from fastapi import HTTPException, status

# reason -> (HTTP status, user-facing detail)
#
# Approval and deactivation are told apart on purpose — the user needs to know
# which, and both require a valid login to reach, so it is not an oracle. A
# soft-deleted account is answered like an unknown username instead: a distinct
# "deleted" message would confirm the account once existed.
_BLOCKS = {
    "unapproved":  (status.HTTP_403_FORBIDDEN, "Your account is pending admin approval. Please wait."),
    "deactivated": (status.HTTP_403_FORBIDDEN, "Your account has been deactivated."),
    "deleted":     (status.HTTP_401_UNAUTHORIZED, "Invalid username or MPIN."),
}


def login_block_reason(user) -> str | None:
    """Return why this loaded user may not log in, or None if they may.

    Order matters: a soft-deleted row is rejected before its approval/active
    flags are even consulted, so a deactivated-then-deleted account can't slip
    through on a stale flag combination.
    """
    if getattr(user, "deleted_at", None) is not None:
        return "deleted"
    if not user.is_approved:
        return "unapproved"
    if not user.is_active:
        return "deactivated"
    return None


def login_block_response(reason: str) -> HTTPException:
    """Map a block reason to the HTTP response the login endpoint should raise."""
    code, detail = _BLOCKS[reason]
    return HTTPException(status_code=code, detail=detail)


# ── Self-service account deletion: which roles may NOT delete themselves ───────
#
# App-store policy requires a self-delete path, but not for every role:
#   • admin  — managed via the admin tools, not self-service.
#   • student — created and managed by a parent + the school; the parent (or an
#     admin) removes it, so a student self-deleting would orphan that control.
#   • owner  — the platform-wide super-admin, provisioned out of band. A self-
#     delete would remove the only account that can administer the platform,
#     with no in-app way back. Added here after the fact: the owner role landed
#     after this policy was first written, and delete_my_account let it fall
#     through and soft-delete itself.
# parent and teacher are adults managing their own account and may self-delete
# (a parent's deletion cascades to their one linked student — handled in the
# router).
_SELF_DELETE_BLOCKS = {
    "admin": "Admin accounts cannot be self-deleted. Use the admin tools.",
    "student": (
        "Students cannot delete their own account. Ask your parent "
        "to delete the account (your parent's deletion also removes "
        "the linked student account), or contact the school admin."
    ),
    "owner": "The platform owner account cannot be self-deleted.",
}


def self_delete_block_reason(role) -> str | None:
    """Return the role key if this role may not self-delete, else None.

    Accepts a UserRole enum or a plain string, so it is trivial to test and
    indifferent to how the caller holds the role.
    """
    key = role.value if hasattr(role, "value") else str(role)
    return key if key in _SELF_DELETE_BLOCKS else None


def self_delete_block_response(reason: str) -> HTTPException:
    """Map a self-delete block reason to a 403 with the role-specific message."""
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=_SELF_DELETE_BLOCKS[reason])
