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
