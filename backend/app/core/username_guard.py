"""Is a username already taken in a school, counting look-alikes? (J-03/K-21)

Registration refused a name that differs from an existing one only by case or
a cross-script look-alike (Cyrillic а vs Latin a). Renames and accounts created
by an admin or the owner only checked an exact match, so an admin could become
"AARAV8" or "аarav8" next to a real student. Every place that sets a username
uses this.
"""

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.username_identity import confusable_skeleton
from app.models.user import User


async def username_taken(db: AsyncSession, school_id: int, username: str,
                         exclude_user_id: Optional[int] = None) -> bool:
    query = select(User.id, User.username).where(
        User.school_id == school_id, User.deleted_at.is_(None))
    target = confusable_skeleton(username)
    for uid, name in (await db.execute(query)).all():
        if uid != exclude_user_id and confusable_skeleton(name) == target:
            return True
    return False
