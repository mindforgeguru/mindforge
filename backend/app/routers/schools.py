"""
Public school directory.

Unauthenticated — it powers the school picker on the login and registration
screens (a user must pick their school before we can resolve their per-school
username). Only *active* schools are listed, and only non-sensitive fields
(id, name, slug, logo) are returned. The trade-off — the list of customer
schools is publicly visible — is normal for B2B SaaS and intentional.
"""

from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.school import School
from app.schemas.school import SchoolPublic

router = APIRouter()


@router.get("", response_model=List[SchoolPublic])
@router.get("/", response_model=List[SchoolPublic])
async def list_schools(db: AsyncSession = Depends(get_db)):
    """List active schools for the login/registration picker, ordered by name."""
    result = await db.execute(
        select(School).where(School.is_active.is_(True)).order_by(School.name)
    )
    return result.scalars().all()
