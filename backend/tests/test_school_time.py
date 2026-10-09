"""
School-local "today".

The schools run on IST (UTC+5:30) while the server clock is UTC, so between
00:00 and 05:30 IST `datetime.now(timezone.utc).date()` is still yesterday.
Every daily gate (attendance window, homework review, workflow) must agree on
the school's calendar day, or a teacher marking attendance at 07:00 IST sees a
different "today" from the gate checking it.

Falsified: make `school_today` return `now.astimezone(timezone.utc).date()` and
the early-morning case flips.
"""

from datetime import datetime, timezone

from app.core.school_time import school_day_start, school_today


def test_early_morning_ist_is_already_the_next_day():
    # 20:00 UTC on the 8th is 01:30 IST on the 9th.
    now = datetime(2026, 10, 8, 20, 0, tzinfo=timezone.utc)
    assert school_today(now).isoformat() == "2026-10-09"


def test_late_evening_ist_is_still_the_same_day():
    # 18:00 UTC on the 9th is 23:30 IST on the 9th.
    now = datetime(2026, 10, 9, 18, 0, tzinfo=timezone.utc)
    assert school_today(now).isoformat() == "2026-10-09"


def test_school_day_starts_at_ist_midnight():
    start = school_day_start(school_today(datetime(2026, 10, 9, 6, 0, tzinfo=timezone.utc)))
    assert start.astimezone(timezone.utc) == datetime(
        2026, 10, 8, 18, 30, tzinfo=timezone.utc
    )
