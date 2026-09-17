"""Canonical grades and subjects.

Mirrors `AppConstants.grades` / `AppConstants.subjects` in the Flutter app
(`tests/test_subjects.py` fails if they drift). These strings matter beyond
display: test generation selects old papers with an exact grade + subject match
on the values the app sends, so anything stored off-list is never used.
"""

from typing import Any, Optional

GRADES = (8, 9, 10)

SUBJECTS = (
    "Mathematics",
    "Physics",
    "Chemistry",
    "Biology",
    "History & Civics",
    "Geography",
    "English 1",
    "English 2",
    "Computer Applications",
    "Economics",
    "Environmental Science",
    "Artificial Intelligence",
)

_BY_KEY = {s.lower(): s for s in SUBJECTS}
_ALIASES = {
    "math": "Mathematics",
    "maths": "Mathematics",
    "history and civics": "History & Civics",
}


def normalize_subject(value: Any) -> Optional[str]:
    """The canonical subject for an AI-supplied value, or None if unrecognised."""
    if not isinstance(value, str):
        return None
    key = " ".join(value.split()).lower()
    return _BY_KEY.get(key) or _ALIASES.get(key)


def normalize_grade(value: Any) -> Optional[int]:
    """A supported grade from an AI-supplied value (8, "8", 8.0), else None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, float):
        if not value.is_integer():
            return None
        value = int(value)
    if isinstance(value, str):
        value = value.strip()
        if not value.isdigit():
            return None
        value = int(value)
    return value if isinstance(value, int) and value in GRADES else None
