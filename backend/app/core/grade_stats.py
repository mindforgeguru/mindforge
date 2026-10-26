"""Class high/low for online-test grades (#19).

The student and parent Grades screens showed "Class High / Class Low" computed
from the viewer's *own* grades, so a student who scored 90% saw "Class High 90%"
even when a classmate scored 100%. The real figures come from every grade tied
to the same test. This module holds the pure reduction; the routers supply the
rows from the DB (scoped to the school by the tenant filter).
"""

from typing import Dict, Iterable, Tuple


def class_extremes(
    rows: Iterable[Tuple[int, float]],
) -> Dict[int, Tuple[float, float]]:
    """Fold (test_id, percentage) rows into {test_id: (high, low)}.

    Rows with a null test_id are ignored (offline/manual grades have no test
    cohort). A test with a single grade yields high == low == that score.
    """
    out: Dict[int, Tuple[float, float]] = {}
    for test_id, pct in rows:
        if test_id is None:
            continue
        pct = float(pct)
        if test_id not in out:
            out[test_id] = (pct, pct)
        else:
            hi, lo = out[test_id]
            out[test_id] = (pct if pct > hi else hi, pct if pct < lo else lo)
    return out


def percentage(marks_obtained: float, max_marks: float) -> float:
    """Same rounding as Grade.percentage, for building rows to reduce."""
    if not max_marks:
        return 0.0
    return round((float(marks_obtained) / float(max_marks)) * 100, 2)
