"""
XP & Level service.

Centralises every XP award so call sites in routers stay one-liners. Holds
the XP-band table for tests, the level-recompute logic, and the level_up
WebSocket publish.

Idempotency: a partial unique index on (student_id, reason, reference_id)
where reference_id IS NOT NULL prevents double-awards. The service catches
IntegrityError on insert and reports a no-op so callers don't have to think
about it.
"""

import logging
from typing import List, Optional

from sqlalchemy import desc, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis_client import redis_manager
from app.models.user import StudentProfile, User
from app.models.xp import LevelConfig, StudentXP, XPReason, XPTransaction
from app.schemas.xp import (
    LevelInfo,
    StudentXPDetails,
    XPTransactionResponse,
)

logger = logging.getLogger(__name__)

# ── XP amounts by event ───────────────────────────────────────────────────────
ATTENDANCE_XP = 5
HOMEWORK_ON_TIME_XP = 20
HOMEWORK_LATE_XP = 10
STREAK_BONUS_XP = 50  # reserved for Phase 1.5; not awarded yet


def xp_for_test_score(percentage: float) -> tuple[int, XPReason]:
    """Return (amount, reason) for a graded test percentage.

    Bands match the spec: 50–69 → 30, 70–89 → 50, 90–99 → 80, 100 → 120.
    Anything below 50 awards 0 XP and is caller's responsibility to skip.
    """
    if percentage >= 100:
        return 120, XPReason.TEST_PERFECT
    if percentage >= 90:
        return 80, XPReason.TEST_SCORE
    if percentage >= 70:
        return 50, XPReason.TEST_SCORE
    if percentage >= 50:
        return 30, XPReason.TEST_SCORE
    return 0, XPReason.TEST_SCORE


# ── Internal helpers ──────────────────────────────────────────────────────────


async def _get_or_create_student_xp(db: AsyncSession, student_id: int) -> StudentXP:
    row = (await db.execute(
        select(StudentXP).where(StudentXP.student_id == student_id)
    )).scalar_one_or_none()
    if row is not None:
        return row
    row = StudentXP(student_id=student_id, total_xp=0, current_level=1)
    db.add(row)
    # Flush so subsequent UPDATEs in the same transaction see the row.
    await db.flush()
    return row


async def _level_for_xp(db: AsyncSession, total_xp: int) -> LevelConfig:
    """Highest LevelConfig whose xp_required <= total_xp.

    Returns the level-1 row when total_xp == 0 (assumed seeded with
    xp_required=0). Caller must not call this on an empty LevelConfig table.
    """
    row = (await db.execute(
        select(LevelConfig)
        .where(LevelConfig.xp_required <= total_xp)
        .order_by(desc(LevelConfig.level))
        .limit(1)
    )).scalar_one_or_none()
    if row is None:
        # Level config not seeded — fall back to level 1 / xp 0 so we don't
        # crash. Migration 021 must have run for the system to function.
        logger.error(
            "LevelConfig table is empty — XP service degraded. "
            "Run migration 021_add_xp_system."
        )
        return LevelConfig(level=1, xp_required=0, title="Novice")
    return row


async def _next_level(db: AsyncSession, current_level: int) -> Optional[LevelConfig]:
    return (await db.execute(
        select(LevelConfig)
        .where(LevelConfig.level == current_level + 1)
        .limit(1)
    )).scalar_one_or_none()


async def _publish_level_up(
    student_id: int,
    new_level: int,
    new_title: str,
    total_xp: int,
) -> None:
    """Push a level_up event to the student's WebSocket connection."""
    try:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": student_id,
            "payload": {
                "event": "level_up",
                "level": new_level,
                "title": new_title,
                "total_xp": total_xp,
            },
        })
    except Exception as exc:
        logger.warning("level_up publish failed for student %s: %s", student_id, exc)


# ── Public API ────────────────────────────────────────────────────────────────


async def award_xp(
    db: AsyncSession,
    student_id: int,
    reason: XPReason,
    amount: int,
    reference_id: Optional[str] = None,
    description: Optional[str] = None,
) -> Optional[XPTransaction]:
    """Award XP to a student and recompute their level.

    Idempotent on (student_id, reason, reference_id) when reference_id is
    not None — re-awards return None instead of creating a duplicate row.
    Publishes a `level_up` WebSocket event when the recompute crosses a
    level threshold.

    Caller is responsible for committing the surrounding transaction —
    this function does its own commit so the row + level recompute are
    atomic with respect to other concurrent awards.
    """
    if amount == 0:
        return None

    # Pre-check idempotency to avoid the cost of an integrity violation +
    # rollback on the common path. The unique partial index in migration 021
    # is still the source of truth under concurrent writes.
    if reference_id is not None:
        existing = (await db.execute(
            select(XPTransaction.id).where(
                XPTransaction.student_id == student_id,
                XPTransaction.reason == reason,
                XPTransaction.reference_id == reference_id,
            ).limit(1)
        )).scalar_one_or_none()
        if existing is not None:
            return None

    txn = XPTransaction(
        student_id=student_id,
        amount=amount,
        reason=reason,
        reference_id=reference_id,
        description=description,
    )
    db.add(txn)

    xp_row = await _get_or_create_student_xp(db, student_id)
    old_level = xp_row.current_level
    xp_row.total_xp = max(0, xp_row.total_xp + amount)

    new_level_cfg = await _level_for_xp(db, xp_row.total_xp)
    xp_row.current_level = new_level_cfg.level

    try:
        await db.commit()
    except IntegrityError:
        # Concurrent insert beat us to the unique index — the other writer
        # already credited the points, so this is a no-op.
        await db.rollback()
        return None

    await db.refresh(txn)

    if new_level_cfg.level > old_level:
        await _publish_level_up(
            student_id=student_id,
            new_level=new_level_cfg.level,
            new_title=new_level_cfg.title,
            total_xp=xp_row.total_xp,
        )

    return txn


async def get_student_xp(
    db: AsyncSession,
    student_id: int,
    *,
    transactions_limit: int = 10,
) -> StudentXPDetails:
    """Build the full XP snapshot used by the dashboard."""
    xp_row = await _get_or_create_student_xp(db, student_id)
    # New rows from _get_or_create need a commit so subsequent calls see them.
    await db.commit()

    current_cfg = await _level_for_xp(db, xp_row.total_xp)
    next_cfg = await _next_level(db, current_cfg.level)

    xp_into_level = xp_row.total_xp - current_cfg.xp_required
    if next_cfg is not None:
        xp_for_next = next_cfg.xp_required - current_cfg.xp_required
    else:
        xp_for_next = None

    txn_rows = (await db.execute(
        select(XPTransaction)
        .where(XPTransaction.student_id == student_id)
        .order_by(desc(XPTransaction.created_at))
        .limit(transactions_limit)
    )).scalars().all()

    return StudentXPDetails(
        student_id=student_id,
        total_xp=xp_row.total_xp,
        current_level=current_cfg.level,
        current_level_title=current_cfg.title,
        xp_into_level=xp_into_level,
        xp_for_next_level=xp_for_next,
        next_level_xp_required=next_cfg.xp_required if next_cfg else None,
        next_level=next_cfg.level if next_cfg else None,
        next_level_title=next_cfg.title if next_cfg else None,
        selected_theme=xp_row.selected_theme,
        recent_transactions=[
            XPTransactionResponse.model_validate(t) for t in txn_rows
        ],
    )


# ── Theme unlocks ─────────────────────────────────────────────────────────────

# The default theme is implicitly unlocked at level 1 and not stored in
# level_configs.unlocks (so seed migrations stay minimal). The service
# synthesises this row when building the picker.
_DEFAULT_THEME_ID = "mind_forge"
_DEFAULT_THEME_UNLOCK_LEVEL = 1


async def list_themes(db: AsyncSession, student_id: int) -> dict:
    """Return every catalogued theme + the student's lock status.

    Sources of truth:
      - level_configs.unlocks JSON for unlock tiers
      - student_xp.selected_theme + .total_xp for "unlocked" / "selected"
    """
    xp_row = await _get_or_create_student_xp(db, student_id)
    await db.commit()

    student_level = (await _level_for_xp(db, xp_row.total_xp)).level

    # Walk every level_config row and pull out themes from `unlocks`.
    # Themes unlocked at lower levels appear first (sorted by unlock_level).
    rows = (await db.execute(
        select(LevelConfig).order_by(LevelConfig.level)
    )).scalars().all()

    themes: list[dict] = [{
        "theme_id": _DEFAULT_THEME_ID,
        "unlock_level": _DEFAULT_THEME_UNLOCK_LEVEL,
        "unlocked": True,
        "selected": (xp_row.selected_theme is None
                     or xp_row.selected_theme == _DEFAULT_THEME_ID),
    }]

    for row in rows:
        unlocks = row.unlocks or {}
        theme_id = unlocks.get("theme") if isinstance(unlocks, dict) else None
        if not theme_id:
            continue
        themes.append({
            "theme_id": theme_id,
            "unlock_level": row.level,
            "unlocked": student_level >= row.level,
            "selected": xp_row.selected_theme == theme_id,
        })

    return {
        "selected_theme": xp_row.selected_theme,
        "themes": themes,
    }


async def select_theme(
    db: AsyncSession,
    student_id: int,
    theme_id: Optional[str],
) -> StudentXP:
    """Persist the student's chosen theme.

    Passing `theme_id=None` (or the default theme id) clears the selection,
    falling back to the default. Any other value must be in the student's
    unlocked set — otherwise raise ValueError so the router returns 400.
    """
    xp_row = await _get_or_create_student_xp(db, student_id)

    # Treat default theme as a clear (NULL) so the column stays canonical.
    if not theme_id or theme_id == _DEFAULT_THEME_ID:
        xp_row.selected_theme = None
        await db.commit()
        await db.refresh(xp_row)
        return xp_row

    # Resolve unlocked set from the catalog at the student's current level.
    catalog = await list_themes(db, student_id)
    unlocked_ids = {t["theme_id"] for t in catalog["themes"] if t["unlocked"]}
    if theme_id not in unlocked_ids:
        raise ValueError(f"Theme '{theme_id}' is not unlocked.")

    xp_row.selected_theme = theme_id
    await db.commit()
    await db.refresh(xp_row)
    return xp_row


async def get_leaderboard(
    db: AsyncSession,
    *,
    scope: str,
    viewer: User,
    limit: int = 20,
) -> List[dict]:
    """Return ranked leaderboard rows for the requested scope.

    `class` and `grade` both filter to viewer's grade (no class/section model
    exists yet). `school` returns the global ranking.
    """
    q = (
        select(
            User.id,
            User.username,
            User.profile_pic_url,
            StudentProfile.grade,
            StudentXP.total_xp,
            StudentXP.current_level,
        )
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .join(StudentXP, StudentXP.student_id == User.id)
        .where(
            User.role == "student",
            User.is_active == True,  # noqa: E712
            User.deleted_at.is_(None),
        )
    )

    if scope in ("class", "grade"):
        # Resolve viewer's grade: students see their own grade; teachers/parents/
        # admins fall through to school-wide if they have no grade context.
        viewer_grade: Optional[int] = None
        if viewer.role.value == "student":
            sp = (await db.execute(
                select(StudentProfile.grade).where(StudentProfile.user_id == viewer.id)
            )).scalar_one_or_none()
            viewer_grade = sp
        if viewer_grade is not None:
            q = q.where(StudentProfile.grade == viewer_grade)

    q = q.order_by(desc(StudentXP.total_xp), User.id).limit(limit)

    rows = (await db.execute(q)).all()
    return [
        {
            "rank": idx + 1,
            "student_id": r.id,
            "username": r.username,
            "profile_pic_url": r.profile_pic_url,
            "grade": r.grade,
            "total_xp": r.total_xp,
            "current_level": r.current_level,
        }
        for idx, r in enumerate(rows)
    ]


async def list_levels(db: AsyncSession) -> List[LevelInfo]:
    rows = (await db.execute(
        select(LevelConfig).order_by(LevelConfig.level)
    )).scalars().all()
    return [LevelInfo.model_validate(r) for r in rows]
