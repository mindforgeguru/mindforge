"""
Real-time fan-out helpers.

Historically events aimed at a class were published as
`{"target_type": "grade", "grade": N}` and the Redis subscriber asked the
WebSocket manager to resolve that grade to a set of connected users. That
resolution never worked: nothing ever called `ws_manager.register_grade()`
and the `/ws/{user_id}` endpoint connects without a grade, so the grade
index was permanently empty and *every* grade-targeted event was dropped on
the floor (new homework, new tests, grade-targeted broadcasts, …).

Rather than maintain a per-connection grade index (which a parent with
children in two grades, or a teacher who teaches five, can't express, and
which has no school scoping), recipients are now resolved from the database
at publish time and the event is addressed to an explicit list of user IDs.
"""

import logging
from typing import Iterable, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis_client import redis_manager
from app.models.user import StudentProfile, User, UserRole

logger = logging.getLogger(__name__)

# Roles that should receive class-wide events alongside the students and
# parents they concern. Teachers and admins share the school-wide homework /
# test / broadcast lists, so their screens need the same refresh signal.
_STAFF_ROLES = (UserRole.teacher, UserRole.admin)


def audience_from_profile_rows(rows: Iterable[tuple[int, int | None]]) -> set[int]:
    """Fold `(student_user_id, parent_user_id)` rows into a recipient set.

    Students always count; parents only when the link exists. Split out from
    the query so it can be exercised without a database.
    """
    user_ids: set[int] = set()
    for student_user_id, parent_user_id in rows:
        user_ids.add(student_user_id)
        if parent_user_id:
            user_ids.add(parent_user_id)
    return user_ids


async def grade_audience(
    db: AsyncSession,
    *,
    school_id: int,
    grade: int,
    include_staff: bool = False,
) -> list[int]:
    """User IDs that should receive an event about `grade` in `school_id`.

    Always includes the grade's active students and their linked parents.
    With `include_staff`, also every active teacher/admin in the school.
    """
    profiles = (await db.execute(
        select(StudentProfile.user_id, StudentProfile.parent_user_id)
        .join(User, User.id == StudentProfile.user_id)
        .where(
            StudentProfile.grade == grade,
            StudentProfile.school_id == school_id,
            User.is_active == True,        # noqa: E712
            User.is_approved == True,      # noqa: E712
            User.deleted_at.is_(None),
        )
    )).all()

    user_ids = audience_from_profile_rows(profiles)

    if include_staff:
        user_ids.update(await school_staff_ids(db, school_id=school_id))

    return list(user_ids)


async def school_staff_ids(db: AsyncSession, *, school_id: int) -> list[int]:
    """Active teacher + admin user IDs for a school."""
    return [
        row.id for row in (await db.execute(
            select(User.id).where(
                User.school_id == school_id,
                User.role.in_(_STAFF_ROLES),
                User.is_active == True,      # noqa: E712
                User.is_approved == True,    # noqa: E712
                User.deleted_at.is_(None),
            )
        ))
    ]


async def publish_to_users(user_ids: Iterable[int], payload: dict) -> None:
    """Send `payload` to an explicit set of users. No-op when empty."""
    ids = sorted({int(u) for u in user_ids if u is not None})
    if not ids:
        return
    await redis_manager.publish({
        "target_type": "users",
        "user_ids": ids,
        "payload": payload,
    })


async def publish_to_grade(
    db: AsyncSession,
    *,
    school_id: int,
    grade: int,
    payload: dict,
    include_staff: bool = False,
    extra_user_ids: Sequence[int] = (),
) -> None:
    """Resolve `grade` to real users and fan the event out to them.

    `extra_user_ids` lets a caller add recipients who aren't in the grade
    (e.g. the teacher who triggered the action) without a second publish.
    """
    audience = await grade_audience(
        db, school_id=school_id, grade=grade, include_staff=include_staff
    )
    audience.extend(extra_user_ids)
    await publish_to_users(audience, payload)


async def publish_to_school(
    db: AsyncSession, *, school_id: int, payload: dict
) -> None:
    """Fan an event out to every active user in one school.

    Replaces `target_type: "broadcast"` for anything school-scoped —
    `broadcast_all` hits every connected socket on the instance, including
    users from other schools.
    """
    user_ids = [
        row.id for row in (await db.execute(
            select(User.id).where(
                User.school_id == school_id,
                User.is_active == True,      # noqa: E712
                User.is_approved == True,    # noqa: E712
                User.deleted_at.is_(None),
            )
        ))
    ]
    await publish_to_users(user_ids, payload)
