"""
Owner (platform super-admin) router.

Only ``UserRole.owner`` accounts reach these endpoints. The owner sits above all
tenants: they create/suspend schools and provision each school's admin(s). They
never touch student/teacher data — that's the school admins' job.
"""

import re
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_owner, hash_mpin
from app.models.school import School
from app.models.user import User, UserRole
from app.schemas.school import (
    SchoolAdminCreate,
    SchoolCreate,
    SchoolOwnerResponse,
    SchoolUpdate,
)
from app.schemas.user import UserResponse

router = APIRouter()


def _slugify(name: str) -> str:
    """Derive a URL-safe slug from a school name."""
    s = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return s or "school"


async def _counts_for(db: AsyncSession, school_id: int) -> dict:
    """Per-role active user counts for a school."""
    rows = (await db.execute(
        select(User.role, func.count(User.id))
        .where(User.school_id == school_id, User.deleted_at.is_(None))
        .group_by(User.role)
    )).all()
    by_role = {role: n for role, n in rows}
    return {
        "admin_count": by_role.get(UserRole.admin, 0),
        "teacher_count": by_role.get(UserRole.teacher, 0),
        "student_count": by_role.get(UserRole.student, 0),
        "parent_count": by_role.get(UserRole.parent, 0),
    }


def _to_response(school: School, counts: dict) -> SchoolOwnerResponse:
    return SchoolOwnerResponse(
        id=school.id,
        name=school.name,
        slug=school.slug,
        logo_url=school.logo_url,
        address=school.address,
        contact_email=school.contact_email,
        contact_phone=school.contact_phone,
        is_active=school.is_active,
        subscription_status=school.subscription_status,
        subscription_plan=school.subscription_plan,
        created_at=school.created_at,
        **counts,
    )


@router.get("/schools", response_model=List[SchoolOwnerResponse])
async def list_schools(
    db: AsyncSession = Depends(get_db),
    current_owner: User = Depends(get_current_owner),
):
    """Every school on the platform, with per-role user counts, newest first."""
    schools = (await db.execute(
        select(School).order_by(School.created_at.desc())
    )).scalars().all()
    out: List[SchoolOwnerResponse] = []
    for s in schools:
        out.append(_to_response(s, await _counts_for(db, s.id)))
    return out


@router.post("/schools", response_model=SchoolOwnerResponse,
             status_code=status.HTTP_201_CREATED)
async def create_school(
    payload: SchoolCreate,
    db: AsyncSession = Depends(get_db),
    current_owner: User = Depends(get_current_owner),
):
    """Onboard a new school. Slug is derived from the name when not supplied and
    must be unique across the platform."""
    slug = payload.slug or _slugify(payload.name)
    existing = await db.execute(select(School).where(School.slug == slug))
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A school with slug '{slug}' already exists. Choose a different slug.",
        )

    school = School(
        name=payload.name,
        slug=slug,
        logo_url=payload.logo_url,
        address=payload.address,
        contact_email=payload.contact_email,
        contact_phone=payload.contact_phone,
        subscription_plan=payload.subscription_plan,
        is_active=True,
        subscription_status="active",
    )
    db.add(school)
    await db.commit()
    await db.refresh(school)
    return _to_response(school, await _counts_for(db, school.id))


async def _get_school_or_404(db: AsyncSession, school_id: int) -> School:
    school = (await db.execute(
        select(School).where(School.id == school_id)
    )).scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found.")
    return school


@router.patch("/schools/{school_id}", response_model=SchoolOwnerResponse)
async def update_school(
    school_id: int,
    payload: SchoolUpdate,
    db: AsyncSession = Depends(get_db),
    current_owner: User = Depends(get_current_owner),
):
    """Edit a school's details, suspend/reactivate it, or change its plan.
    A suspended school (is_active=False) drops out of the public picker and its
    users can no longer log in — no data is deleted."""
    school = await _get_school_or_404(db, school_id)
    data = payload.model_dump(exclude_none=True)
    for field, value in data.items():
        setattr(school, field, value)
    await db.commit()
    await db.refresh(school)
    # Drop the cached is_active flag so a suspension (or reactivation) takes
    # effect on the next request rather than after the cache TTL.
    if "is_active" in data:
        from app.core.cache import invalidate_school_active
        await invalidate_school_active(school.id)
    return _to_response(school, await _counts_for(db, school.id))


@router.post("/schools/{school_id}/admins", response_model=UserResponse,
             status_code=status.HTTP_201_CREATED)
async def create_school_admin(
    school_id: int,
    payload: SchoolAdminCreate,
    db: AsyncSession = Depends(get_db),
    current_owner: User = Depends(get_current_owner),
):
    """Provision an admin for a school. The admin is created already approved so
    they can log in immediately and start onboarding their staff/students.
    Usernames are unique per school."""
    school = await _get_school_or_404(db, school_id)

    conflict = await db.execute(
        select(User).where(
            User.username == payload.username,
            User.school_id == school.id,
            User.deleted_at.is_(None),
        )
    )
    if conflict.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this username already exists in this school.",
        )

    admin = User(
        username=payload.username,
        mpin_hash=hash_mpin(payload.mpin),
        role=UserRole.admin,
        school_id=school.id,
        is_active=True,
        is_approved=True,
    )
    db.add(admin)
    await db.commit()
    await db.refresh(admin)
    return admin
