"""Academic-year labels ("2026-27")."""

from typing import Optional


def make_year_label(year: int) -> str:
    """Generate label like '2025-26' from a start year."""
    return f"{year}-{str(year + 1)[-2:]}"


def next_year_label(previous_label: Optional[str], now_year: int, used: set[str]) -> str:
    """Label for the year that follows `previous_label`.

    Naming the new year after the calendar year reused the label whenever a
    year was closed inside the year it started in — two "2026-27"s (#30). The
    label is also the key fee structures are stored under, so the new year
    silently inherited the old one's fees. Follow on from the closing year
    (2026-27 → 2027-28), never go behind the calendar year, and skip any label
    the school has already used.
    """
    start = now_year
    if previous_label:
        try:
            start = max(start, int(previous_label.split("-")[0]) + 1)
        except ValueError:
            pass
    while make_year_label(start) in used:
        start += 1
    return make_year_label(start)
