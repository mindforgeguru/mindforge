"""
Cached helpers for frequently-read, rarely-changed DB rows.
All functions check Redis first; on miss they query Postgres and fill the cache.
"""

import json
from dataclasses import dataclass
from datetime import date, time
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis_client import redis_manager

# ─── TTLs ─────────────────────────────────────────────────────────────────────
_TTL_PROFILE = 300        # 5 min — profile rarely changes mid-session
_TTL_TIMETABLE_CFG = 3600 # 1 hour — admin sets this once
_TTL_ACADEMIC_YEAR = 3600 # 1 hour — changes at most once a year


# ─── Student profile ──────────────────────────────────────────────────────────

@dataclass
class CachedStudentProfile:
    user_id: int
    grade: int
    additional_subjects: Optional[list]
    parent_user_id: Optional[int]


async def get_student_profile_cached(
    user_id: int, db: AsyncSession
) -> Optional[CachedStudentProfile]:
    from app.models.user import StudentProfile

    key = f"cache:student_profile:{user_id}"
    raw = await redis_manager.get_cache(key)
    if raw:
        d = json.loads(raw)
        return CachedStudentProfile(
            user_id=d["user_id"],
            grade=d["grade"],
            additional_subjects=d.get("additional_subjects"),
            parent_user_id=d.get("parent_user_id"),
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
            }),
            expire_seconds=_TTL_PROFILE,
        )
    return CachedStudentProfile(
        user_id=profile.user_id,
        grade=profile.grade,
        additional_subjects=profile.additional_subjects,
        parent_user_id=profile.parent_user_id,
    ) if profile else None


async def invalidate_student_profile(user_id: int):
    await redis_manager.delete_cache(f"cache:student_profile:{user_id}")


# ─── Timetable config ─────────────────────────────────────────────────────────

async def get_timetable_config_cached(db: AsyncSession):
    """Returns the TimetableConfig ORM object (or None) with Redis caching."""
    from app.models.timetable import TimetableConfig

    key = "cache:timetable_config"
    raw = await redis_manager.get_cache(key)
    if raw:
        d = json.loads(raw)
        # Reconstruct a lightweight object with the fields routers actually use
        cfg = TimetableConfig.__new__(TimetableConfig)
        cfg.id = d["id"]
        cfg.periods_per_day = d["periods_per_day"]
        cfg.enable_weekends = d["enable_weekends"]
        cfg.period_times = d.get("period_times")
        cfg.created_by_admin_id = d.get("created_by_admin_id")
        return cfg

    result = await db.execute(select(TimetableConfig))
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
    return cfg


async def invalidate_timetable_config():
    await redis_manager.delete_cache("cache:timetable_config")


# ─── Current academic year ────────────────────────────────────────────────────

async def get_current_academic_year_cached(db: AsyncSession) -> Optional[str]:
    """Returns the current academic year label string (e.g. '2025-26')."""
    from app.models.academic_year import AcademicYear
    from datetime import date as _date

    key = "cache:academic_year_current"
    raw = await redis_manager.get_cache(key)
    if raw:
        return raw  # stored as plain string, not JSON

    result = await db.execute(
        select(AcademicYear).where(AcademicYear.is_current == True)
    )
    ay = result.scalar_one_or_none()
    if ay:
        await redis_manager.set_cache(key, ay.year_label, expire_seconds=_TTL_ACADEMIC_YEAR)
        return ay.year_label

    # Fallback: derive from current date
    today = _date.today()
    year_start = today.year if today.month >= 6 else today.year - 1
    return f"{year_start}-{str(year_start + 1)[2:]}"


async def invalidate_academic_year():
    await redis_manager.delete_cache("cache:academic_year_current")
