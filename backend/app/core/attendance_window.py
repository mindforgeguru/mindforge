"""
Attendance date window.

Attendance is a record of a day that has actually happened. Left unbounded, a
teacher can POST attendance for *any* date — a future day that hasn't occurred,
or a day months in the past, silently rewriting history. `mark_attendance`
overwrites an existing record for the same (student, date, period), so an
unbounded date is a write onto arbitrary history, not just an insert.

This is the single source of truth for which dates a teacher may mark. Future
dates are never valid. Past dates are accepted only inside a correction window,
so ordinary "I forgot to mark Tuesday" fixes work while fabricating old records
does not. The window is a product decision, kept here as a named constant.
"""

from datetime import date, timedelta
from typing import Optional

# How many days back a teacher may still mark or correct attendance. Product
# decision (2026-08-24): a two-week correction window.
ATTENDANCE_BACKDATE_LIMIT_DAYS = 14


def attendance_date_reason(d: date, today: date) -> Optional[str]:
    """Why `d` is not an acceptable attendance date, or None if it's fine.

    Pure and reference-date-injected so it can be tested without freezing the
    clock. `today` is the caller's notion of the current date.
    """
    if d > today:
        return "Attendance cannot be marked for a future date."
    if d < today - timedelta(days=ATTENDANCE_BACKDATE_LIMIT_DAYS):
        return (
            "Attendance can only be marked or corrected within the last "
            f"{ATTENDANCE_BACKDATE_LIMIT_DAYS} days."
        )
    return None
