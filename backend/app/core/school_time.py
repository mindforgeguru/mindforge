"""
School-local calendar day.

The server clock is UTC but every school is in India (IST, UTC+5:30). Daily
rules — the attendance window, the homework review gate, the teacher's daily
workflow — are about the school's calendar day, and between 00:00 and 05:30
IST the UTC date is still yesterday. Anything that asks "what is today?" for a
school must ask here, so the attendance a teacher marks for "today" and the
gate that checks for it agree on the date.

There is no per-school timezone column; when one is added, this is the single
place to thread it through.
"""

from datetime import date, datetime, timezone
from typing import Optional
from zoneinfo import ZoneInfo

SCHOOL_TZ = ZoneInfo("Asia/Kolkata")


def _utc_now() -> datetime:
    # Indirection so tests can pin the clock.
    return datetime.now(timezone.utc)


def school_today(now: Optional[datetime] = None) -> date:
    """The school's current calendar date."""
    return (now or _utc_now()).astimezone(SCHOOL_TZ).date()


def school_day_start(day: date) -> datetime:
    """Midnight at the start of `day` in school time, as an aware datetime —
    the boundary for "created today" / "created before today" comparisons."""
    return datetime.combine(day, datetime.min.time(), tzinfo=SCHOOL_TZ)


def parse_iso_date(value: str, field: str = "date") -> date:
    """A YYYY-MM-DD query parameter as a date; a malformed one is the client's
    error (422), where an unguarded fromisoformat() made it a 500."""
    from fastapi import HTTPException

    try:
        return date.fromisoformat(value)
    except ValueError:
        raise HTTPException(status_code=422, detail=f"{field} must be YYYY-MM-DD.")
