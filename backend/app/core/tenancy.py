"""
Multi-tenancy helpers.

Central place for the school-scoping rules so routers don't hand-roll (and
occasionally forget) the ``school_id`` filter that keeps one school's data
invisible to another.
"""

from typing import Optional

from fastapi import HTTPException, status

from app.models.user import User


def require_school_id(user: User) -> int:
    """Return the caller's school id, or 403 if they have none.

    Every role except the platform ``owner`` belongs to a school. A tenant
    endpoint reached by an ownerless account (only the owner) is a
    programming/authorization error, so we fail closed rather than run an
    unscoped query.
    """
    if user.school_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is not associated with a school.",
        )
    return user.school_id


async def assert_school_active(user: User, db) -> None:
    """403 if the caller's school has been suspended.

    Login and the public school picker already exclude suspended schools, but
    both are one-time gates: a session established while the school was active
    keeps working, and rotating refresh tokens renew it indefinitely. Suspension
    is a billing control, so it has to be re-checked per request rather than
    trusted from the ``school_id`` baked into the JWT at login.

    The platform owner has no school and is never gated — otherwise suspending
    a school could lock the owner out of the console they need to unsuspend it.
    """
    from app.core.cache import is_school_active_cached

    if user.school_id is None:
        return
    if not await is_school_active_cached(user.school_id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This school's access has been suspended. "
                   "Please contact your administrator.",
        )


def same_school_or_404(row_school_id: Optional[int], user_school_id: int) -> None:
    """Guard a fetched row: 404 if it belongs to a different school.

    Used after loading a single record by id so a caller can't read (or mutate)
    another school's object by guessing its id. 404 — not 403 — so existence
    across the tenant boundary isn't revealed.
    """
    if row_school_id != user_school_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not found.",
        )
