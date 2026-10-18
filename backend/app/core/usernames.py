"""
Finding an account by a username someone typed.

Usernames are case-sensitive (sign-in compares them exactly), so "Ravi" and
"ravi" can be two accounts. Lookups that forgive case — a parent's username
typed at sign-up or in the admin's editor — must not assume one match.
"""

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


async def find_by_username(db: AsyncSession, school_id: int, username: str, role=None) -> list[User]:
    """Live accounts in the school matching `username`.

    An exact match is returned alone. Otherwise every case-insensitive match is
    returned, so the caller can tell "none", "this one" and "ambiguous" apart.
    """
    username = username.strip()
    query = select(User).where(User.school_id == school_id, User.deleted_at.is_(None))
    if role is not None:
        query = query.where(User.role == role)
    exact = (await db.execute(query.where(User.username == username))).scalars().first()
    if exact:
        return [exact]
    return list((await db.execute(
        query.where(func.lower(User.username) == username.lower()).order_by(User.id)
    )).scalars().all())
