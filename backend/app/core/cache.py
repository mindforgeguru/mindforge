"""
Cached helpers for frequently-read, rarely-changed DB rows.
All functions check Redis first; on miss they query Postgres and fill the cache.
"""

import json
from dataclasses import dataclass
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis_client import redis_manager

# ─── TTLs ─────────────────────────────────────────────────────────────────────
_TTL_PROFILE = 300        # 5 min — profile rarely changes mid-session
_TTL_TIMETABLE_CFG = 3600 # 1 hour — admin sets this once
_TTL_ACADEMIC_YEAR = 3600 # 1 hour — changes at most once a year
# Deliberately short: this gates access for every request of every user in a
# school, so a suspension must bite quickly. The owner endpoint invalidates
# explicitly on change, making this only the backstop for a missed invalidation
# (or one that raced a concurrent request).
_TTL_SCHOOL_ACTIVE = 60   # 1 min


# ─── School active flag ───────────────────────────────────────────────────────

_SCHOOL_ACTIVE_KEY = "cache:school_active:{school_id}"


async def is_school_active_cached(school_id: int, db: AsyncSession) -> bool:
    """True when the school exists and is not suspended.

    Called on every authenticated request, so it is Redis-backed. A missing
    school counts as inactive: a token naming a school that no longer exists
    should not grant access.
    """
    from app.models.school import School

    key = _SCHOOL_ACTIVE_KEY.format(school_id=school_id)
    raw = await redis_manager.get_cache(key)
    if raw is not None:
        return raw == "1"

    result = await db.execute(select(School.is_active).where(School.id == school_id))
    active = bool(result.scalar_one_or_none())
    await redis_manager.set_cache(
        key, "1" if active else "0", expire_seconds=_TTL_SCHOOL_ACTIVE
    )
    return active


async def invalidate_school_active(school_id: int):
    await redis_manager.delete_cache(
        _SCHOOL_ACTIVE_KEY.format(school_id=school_id)
    )


# ─── Student profile ──────────────────────────────────────────────────────────

@dataclass
class CachedStudentProfile:
    user_id: int
    grade: int
    additional_subjects: Optional[list]
    parent_user_id: Optional[int]
    # Carried so callers can enforce tenancy without a second query — the
    # cross-school IDOR guards in student.py compare this against the record's
    # school_id. Entries cached before this field existed lack it, hence the
    # versioned key below.
    school_id: Optional[int]


# Bumped to v2 when school_id joined the payload. A v1 entry deserialised into
# the new shape would carry school_id=None and silently fail every tenancy
# comparison, 404-ing legitimate students until the 5-minute TTL aged it out.
# The version suffix sidesteps that: v1 keys are simply never read again.
_STUDENT_PROFILE_KEY = "cache:student_profile:v2:{user_id}"


async def get_student_profile_cached(
    user_id: int, db: AsyncSession
) -> Optional[CachedStudentProfile]:
    from app.models.user import StudentProfile

    key = _STUDENT_PROFILE_KEY.format(user_id=user_id)
    raw = await redis_manager.get_cache(key)
    if raw:
        d = json.loads(raw)
        return CachedStudentProfile(
            user_id=d["user_id"],
            grade=d["grade"],
            additional_subjects=d.get("additional_subjects"),
            parent_user_id=d.get("parent_user_id"),
            school_id=d.get("school_id"),
        )

    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()
    if profile:
        await redis_manager.set_cache(
            key,
            json.dumps({
                "user_id": profile.user_id,
                "grade": profile.grade,
                "additional_subjects": profile.additional_subjects,
                "parent_user_id": profile.parent_user_id,
                "school_id": profile.school_id,
            }),
            expire_seconds=_TTL_PROFILE,
        )
    return CachedStudentProfile(
        user_id=profile.user_id,
        grade=profile.grade,
        additional_subjects=profile.additional_subjects,
        parent_user_id=profile.parent_user_id,
        school_id=profile.school_id,
    ) if profile else None


async def invalidate_student_profile(user_id: int):
    await redis_manager.delete_cache(
        _STUDENT_PROFILE_KEY.format(user_id=user_id)
    )


# ─── Timetable config ─────────────────────────────────────────────────────────

@dataclass
class CachedTimetableConfig:
    id: int
    periods_per_day: int
    enable_weekends: bool
    period_times: Optional[list]
    created_by_admin_id: Optional[int]


async def get_timetable_config_cached(
    db: AsyncSession, school_id: int
) -> Optional[CachedTimetableConfig]:
    """Returns a CachedTimetableConfig (or None) for one school, Redis-cached."""
    from app.models.timetable import TimetableConfig

    key = f"cache:timetable_config:{school_id}"
    raw = await redis_manager.get_cache(key)
    if raw:
        d = json.loads(raw)
        return CachedTimetableConfig(
            id=d["id"],
            periods_per_day=d["periods_per_day"],
            enable_weekends=d["enable_weekends"],
            period_times=d.get("period_times"),
            created_by_admin_id=d.get("created_by_admin_id"),
        )

    result = await db.execute(
        select(TimetableConfig).where(TimetableConfig.school_id == school_id)
    )
    cfg = result.scalar_one_or_none()
    if cfg:
        await redis_manager.set_cache(
            key,
            json.dumps({
                "id": cfg.id,
                "periods_per_day": cfg.periods_per_day,
                "enable_weekends": cfg.enable_weekends,
                "period_times": cfg.period_times,
                "created_by_admin_id": cfg.created_by_admin_id,
            }),
            expire_seconds=_TTL_TIMETABLE_CFG,
        )
        return CachedTimetableConfig(
            id=cfg.id,
            periods_per_day=cfg.periods_per_day,
            enable_weekends=cfg.enable_weekends,
            period_times=cfg.period_times,
            created_by_admin_id=cfg.created_by_admin_id,
        )
    return None


async def invalidate_timetable_config(school_id: int):
    await redis_manager.delete_cache(f"cache:timetable_config:{school_id}")


# ─── Current academic year ────────────────────────────────────────────────────

async def get_current_academic_year_cached(
    db: AsyncSession, school_id: int
) -> Optional[str]:
    """Returns one school's current academic year label (e.g. '2025-26')."""
    from app.models.academic_year import AcademicYear
    from datetime import date as _date

    key = f"cache:academic_year_current:{school_id}"
    raw = await redis_manager.get_cache(key)
    if raw:
        return raw  # stored as plain string, not JSON

    result = await db.execute(
        select(AcademicYear).where(
            AcademicYear.is_current == True,
            AcademicYear.school_id == school_id,
        )
    )
    ay = result.scalar_one_or_none()
    if ay:
        await redis_manager.set_cache(key, ay.year_label, expire_seconds=_TTL_ACADEMIC_YEAR)
        return ay.year_label

    # Fallback: derive from current date
    today = _date.today()
    year_start = today.year if today.month >= 6 else today.year - 1
    return f"{year_start}-{str(year_start + 1)[2:]}"


async def invalidate_academic_year(school_id: int):
    await redis_manager.delete_cache(f"cache:academic_year_current:{school_id}")
