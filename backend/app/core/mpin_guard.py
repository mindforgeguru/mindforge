"""
One rule for every MPIN check: a wrong MPIN is a failed login.

The login counted wrong MPINs towards a lockout (5 per address, 50 per account,
15 minutes). Nothing else that checks an MPIN did — registering a student under
an existing parent (unauthenticated, answering 201 or 401), the MPIN-change
screens and turning off two-factor — so each was a way to guess an MPIN with
the lockout never noticing.
"""

from fastapi import HTTPException, Request

from app.core.redis_client import redis_manager
from app.core.security import verify_mpin_async

LOCKED_DETAIL = (
    "Account temporarily locked due to too many failed attempts. Try again in 15 minutes."
)


def client_ip(request: Request) -> str:
    """Best-effort real client IP: the rightmost X-Forwarded-For entry, which
    the closest trusted hop appends; the leftmost is client-controlled."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        parts = [p.strip() for p in forwarded.split(",") if p.strip()]
        if parts:
            return parts[-1]
    return request.client.host if request.client else "unknown"


async def mpin_matches(user, mpin: str, request: Request, *, locked_status: int = 429,
                       locked_detail: str = LOCKED_DETAIL) -> bool:
    """True if `mpin` is the user's. Refuses outright while the account is locked
    for this caller; a wrong MPIN counts towards the lock.

    `locked_status` / `locked_detail` let an unauthenticated caller get the same
    answer as a wrong MPIN, so the lock itself does not confirm anything.
    """
    ip = client_ip(request)
    if await redis_manager.is_user_locked_out(user.id, ip):
        raise HTTPException(status_code=locked_status, detail=locked_detail)
    if await verify_mpin_async(mpin, user.mpin_hash):
        return True
    await redis_manager.record_failed_login(user.id, ip)
    return False
