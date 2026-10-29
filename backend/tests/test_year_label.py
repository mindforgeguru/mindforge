"""Close Year must not reuse the closing year's label (#30)."""

from app.core.year_label import next_year_label


def test_follows_on_from_the_closing_year_within_the_same_calendar_year():
    assert next_year_label("2026-27", 2026, {"2026-27"}) == "2027-28"


def test_never_goes_behind_the_calendar_year():
    # A year closed late (2025-26 still current in 2027) starts at the calendar year.
    assert next_year_label("2025-26", 2027, {"2025-26"}) == "2027-28"


def test_skips_labels_the_school_already_used():
    assert next_year_label("2026-27", 2026, {"2026-27", "2027-28"}) == "2028-29"


def test_no_previous_year_uses_the_calendar_year():
    assert next_year_label(None, 2026, set()) == "2026-27"


def test_unparseable_previous_label_falls_back_to_the_calendar_year():
    assert next_year_label("Term A", 2026, {"Term A"}) == "2026-27"


def test_century_rollover_label():
    assert next_year_label("2098-99", 2026, set()) == "2099-00"
