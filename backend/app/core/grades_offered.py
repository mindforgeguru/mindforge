"""Which grades a school teaches (#5).

The platform supports grades 8–10 (`app.core.subjects.GRADES`); each school
offers a subset. Dropping a grade that still has students would strand them,
so that's refused.
"""

from typing import Dict, Iterable, List

from app.core.subjects import GRADES


class GradesOfferedError(ValueError):
    pass


def checked_grades_offered(
    requested: Iterable[int], students_by_grade: Dict[int, int],
) -> List[int]:
    """The requested grades, sorted and de-duplicated, or GradesOfferedError."""
    grades = sorted(set(requested))
    if not grades:
        raise GradesOfferedError("Choose at least one grade.")
    unknown = [g for g in grades if g not in GRADES]
    if unknown:
        raise GradesOfferedError(
            f"Grade {unknown[0]} isn't supported; choose from "
            f"{', '.join(str(g) for g in GRADES)}."
        )
    stranded = [
        g for g, count in sorted(students_by_grade.items())
        if count > 0 and g not in grades
    ]
    if stranded:
        g = stranded[0]
        n = students_by_grade[g]
        raise GradesOfferedError(
            f"Grade {g} still has {n} student{'s' if n != 1 else ''}; "
            f"it can't be removed while they're enrolled."
        )
    return grades


def grade_not_offered_message(grade: int, offered: Iterable[int],
                              school_name: str) -> "str | None":
    """Why `grade` can't be used at this school, or None if it can.

    Registration already refused grades a school doesn't teach (#5); homework,
    broadcasts, tests and presentations did not, so a teacher could assign
    work to a grade with no students and it reached nobody.
    """
    if grade in set(offered or []):
        return None
    return f"{school_name} doesn't have a Grade {grade}."
