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
