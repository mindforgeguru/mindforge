"""
Attendance date window — the teacher-side business-logic guard.

Left unbounded, `mark_attendance` lets a teacher POST attendance for any date:
a future day that never happened, or a day months back (and because the endpoint
overwrites the existing record for that day, that's rewriting history, not just a
stray insert). These tests pin the two bounds — future rejected, backdating
capped at the 14-day correction window — at both the pure-helper level and
through the actual request schema, so a regression at either layer fails.

Falsified: widen the window to `timedelta(days=0)` (reject the far-past line) or
drop the `> today` check and the corresponding test flips.
"""

from datetime import date, datetime, timedelta, timezone

import pytest

from app.core.attendance_window import (
    ATTENDANCE_BACKDATE_LIMIT_DAYS as WINDOW,
    attendance_date_reason,
)
from app.core import school_time
from app.core.school_time import school_today
from app.schemas.attendance import AttendanceBulkCreate

TODAY = date(2026, 8, 24)


# --- the pure helper -------------------------------------------------------

def test_today_is_allowed():
    assert attendance_date_reason(TODAY, TODAY) is None


def test_yesterday_and_recent_days_are_allowed():
    # Ordinary corrections: "I forgot to mark Tuesday" must keep working.
    for back in range(0, WINDOW + 1):
        d = TODAY - timedelta(days=back)
        assert attendance_date_reason(d, TODAY) is None, f"{back} days back rejected"


def test_a_future_date_is_rejected():
    reason = attendance_date_reason(TODAY + timedelta(days=1), TODAY)
    assert reason is not None
    assert "future" in reason.lower()


def test_the_edge_of_the_window_is_allowed_but_one_past_it_is_not():
    # Exactly WINDOW days back: still a correction. One more: history-rewriting.
    assert attendance_date_reason(TODAY - timedelta(days=WINDOW), TODAY) is None
    over = attendance_date_reason(TODAY - timedelta(days=WINDOW + 1), TODAY)
    assert over is not None
    assert str(WINDOW) in over


def test_far_backdating_is_rejected():
    reason = attendance_date_reason(TODAY - timedelta(days=180), TODAY)
    assert reason is not None


# --- through the request schema (the real enforcement point) ---------------

def _bulk(d: date) -> AttendanceBulkCreate:
    return AttendanceBulkCreate(grade=8, period=1, date=d, records=[])


def test_schema_accepts_today():
    # Uses the real clock: the school's today must always parse.
    assert _bulk(school_today()).date == school_today()


def test_schema_rejects_a_future_date():
    with pytest.raises(ValueError):
        _bulk(school_today() + timedelta(days=1))


def test_schema_rejects_far_backdating():
    with pytest.raises(ValueError):
        _bulk(school_today() - timedelta(days=WINDOW + 5))


def test_schema_accepts_the_school_day_before_utc_catches_up(monkeypatch):
    # 01:30 IST on the 9th is still the 8th in UTC. A teacher marking the
    # morning's attendance must not be told the 9th is "a future date".
    monkeypatch.setattr(
        school_time, "_utc_now",
        lambda: datetime(2026, 10, 8, 20, 0, tzinfo=timezone.utc),
    )
    assert _bulk(date(2026, 10, 9)).date == date(2026, 10, 9)


def test_the_window_is_the_agreed_two_weeks():
    # A guard against someone quietly loosening the product decision.
    assert WINDOW == 14
