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


def test_late_night_mark_falls_in_the_school_day_window():
    # The marks report bounds a day range by school_day_start(start) and
    # school_day_start(end + 1 day). A mark entered at 00:30 IST on 1 Dec
    # (19:00 UTC on 30 Nov) belongs to December's window, not November's;
    # date(created_at) in the UTC session had put it in November.
    from datetime import date, timedelta

    entered = datetime(2026, 11, 30, 19, 0, tzinfo=timezone.utc)

    def in_window(start, end):
        return school_day_start(start) <= entered < school_day_start(end + timedelta(days=1))

    assert in_window(date(2026, 12, 1), date(2026, 12, 31))
    assert not in_window(date(2026, 11, 1), date(2026, 11, 30))
