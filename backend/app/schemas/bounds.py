"""
Bounded field types shared by the request schemas.

Each limit mirrors a database constraint — a VARCHAR length, a NUMERIC
precision, a CHECK — so out-of-range input is refused as a 422 naming the
field, instead of reaching Postgres and coming back as a 500. Floats refuse
NaN and Infinity, which JSON parsing lets through.
"""

from typing import Annotated

from pydantic import AfterValidator, Field, StringConstraints

GRADES = (8, 9, 10)


def _school_grade(v: int) -> int:
    if v not in GRADES:
        raise ValueError("Grade must be 8, 9, or 10.")
    return v


SchoolGrade = Annotated[int, AfterValidator(_school_grade)]

# A period in the day; the admin's timetable settings allow up to 12.
Period = Annotated[int, Field(ge=1, le=12)]

# NUMERIC(10, 2): below 10^8.
Money = Annotated[float, Field(ge=0, lt=100_000_000, allow_inf_nan=False)]
PositiveMoney = Annotated[float, Field(gt=0, lt=100_000_000, allow_inf_nan=False)]

# NUMERIC(6, 2): below 10^4.
Marks = Annotated[float, Field(ge=0, lt=10_000, allow_inf_nan=False)]
PositiveMarks = Annotated[float, Field(gt=0, lt=10_000, allow_inf_nan=False)]


def Text(max_length: int):
    """Free text up to `max_length`, may be empty."""
    return Annotated[str, StringConstraints(max_length=max_length)]


def Required(max_length: int):
    """Text that must say something: trimmed, then 1..`max_length`."""
    return Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=max_length)]


# A test attempt's answers: question id -> the student's answer. The app only
# sends text. 200 answers of up to 5,000 characters (a long-answer essay) caps a
# save at about 1 MB; it was unbounded, and the app autosaves every 20 seconds.
Answers = Annotated[
    dict[
        Annotated[str, StringConstraints(max_length=20)],
        Annotated[str, StringConstraints(max_length=5000)],
    ],
    Field(max_length=200),
]
