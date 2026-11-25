"""Refuse a grade the caller's school doesn't teach (#5), before any work."""

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.grades_offered import grade_not_offered_message
from app.models.school import School


async def require_grade_offered(db: AsyncSession, school_id: int, grade: int) -> None:
    row = (await db.execute(
        select(School.name, School.grades_offered).where(School.id == school_id)
    )).one_or_none()
    if row is None:
        return  # no school (e.g. platform owner): nothing to check against
    message = grade_not_offered_message(grade, row.grades_offered, row.name)
    if message:
        raise HTTPException(status_code=422, detail=message)
