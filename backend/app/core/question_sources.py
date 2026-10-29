"""Which source categories a generated question can honestly claim (#15).

The generator asks for a mix of five categories: [1] exact from old papers,
[2] exact from back exercises, [3]/[4] AI-written in their style, [5] fully
AI-generated. A category is only possible when its source was supplied; a
chapter-only upload used to come back tagged [P] "past test paper" anyway.
"""

from typing import Any, Optional, Tuple

OLD_PAPER_CATEGORIES = (1, 3)
EXERCISE_CATEGORIES = (2, 4)
AI_CATEGORY = 5


def effective_source_mix(
    p: int, e: int, np_: int, ne: int, ai: int,
    *, has_old_papers: bool, has_chapter: bool,
) -> Tuple[int, int, int, int, int]:
    """The requested percentages with each missing source's share moved to [5]."""
    if not has_old_papers:
        ai, p, np_ = ai + p + np_, 0, 0
    if not has_chapter:
        ai, e, ne = ai + e + ne, 0, 0
    return p, e, np_, ne, ai


def honest_source_category(
    raw: Any, *, has_old_papers: bool, has_chapter: bool,
) -> Optional[int]:
    """The model's claimed category, downgraded to [5] when its source wasn't given."""
    try:
        cat = int(raw)
    except (TypeError, ValueError):
        return None
    if cat not in (1, 2, 3, 4, 5):
        return None
    if cat in OLD_PAPER_CATEGORIES and not has_old_papers:
        return AI_CATEGORY
    if cat in EXERCISE_CATEGORIES and not has_chapter:
        return AI_CATEGORY
    return cat
