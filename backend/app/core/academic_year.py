"""
The current academic year's start, for keeping last year out of this one.

Close Year removes every student, teacher and parent and clears the timetable,
but homework, announcements and tests carry no year. Without a cut-off a new
year's students saw last year's homework, notices and open tests, and the
homework review gate asked a new teacher to record completion of last year's
last homework by this year's class. Rows stay in the database for Previous
Years; queries that serve the current year filter on `since(...)`.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import select, true
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.academic_year import AcademicYear


async def year_started_at(db: AsyncSession, school_id: Optional[int]) -> Optional[datetime]:
    """When the school's current year began, or None (no year yet: no cut-off)."""
    if school_id is None:
        return None
    return (await db.execute(
        select(AcademicYear.started_at).where(
            AcademicYear.school_id == school_id,
            AcademicYear.is_current == True,  # noqa: E712
        )
    )).scalar_one_or_none()


def since(column, started: Optional[datetime]):
    """`column >= started`, or no condition when there is no current year."""
    return column >= started if started is not None else true()
