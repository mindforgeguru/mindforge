"""Figures for the admin attendance and marks reports (#28).

Kept free of the database and of reportlab so they can be unit-tested; the
router gathers rows, these turn them into the tables the PDFs print.
"""

from collections import defaultdict
from typing import Dict, Iterable, List, Optional, Tuple

# Below this share of periods attended a student is flagged on the report.
LOW_ATTENDANCE_PERCENT = 75.0


def _percent(part: float, whole: float) -> Optional[float]:
    return round(100.0 * part / whole, 1) if whole > 0 else None


def attendance_rows(
    students: Iterable[Tuple[int, str]],
    marks: Iterable[Tuple[int, str]],
) -> List[dict]:
    """One row per student: periods present/absent and % present.

    `students` is (id, name) for everyone in the grade, so a student with no
    attendance yet still appears; `marks` is (student_id, "present"|"absent").
    """
    present: Dict[int, int] = defaultdict(int)
    absent: Dict[int, int] = defaultdict(int)
    for student_id, status in marks:
        if status == "present":
            present[student_id] += 1
        elif status == "absent":
            absent[student_id] += 1
    rows = []
    for student_id, name in students:
        p, a = present[student_id], absent[student_id]
        pct = _percent(p, p + a)
        rows.append({
            "student": name,
            "present": p,
            "absent": a,
            "percent": pct,
            "low": pct is not None and pct < LOW_ATTENDANCE_PERCENT,
        })
    return sorted(rows, key=lambda r: r["student"].lower())


def marks_rows(
    students: Iterable[Tuple[int, str]],
    grades: Iterable[Tuple[int, str, float, float]],
) -> Tuple[Dict[str, List[dict]], List[dict]]:
    """Per-subject tables and an overall table.

    `grades` is (student_id, subject, marks_obtained, max_marks). Percentages
    are totals over totals, so a 50-mark test weighs more than a 10-mark quiz.
    Subjects only list students who sat something in them; the overall table
    lists every student, with no percentage for those with no marks.
    """
    names = dict(students)
    got: Dict[Tuple[str, int], float] = defaultdict(float)
    out_of: Dict[Tuple[str, int], float] = defaultdict(float)
    count: Dict[Tuple[str, int], int] = defaultdict(int)
    for student_id, subject, obtained, maximum in grades:
        if student_id not in names:
            continue
        key = (subject, student_id)
        got[key] += obtained
        out_of[key] += maximum
        count[key] += 1

    by_subject: Dict[str, List[dict]] = defaultdict(list)
    total_got: Dict[int, float] = defaultdict(float)
    total_out: Dict[int, float] = defaultdict(float)
    for (subject, student_id), n in count.items():
        g, o = got[(subject, student_id)], out_of[(subject, student_id)]
        by_subject[subject].append({
            "student": names[student_id],
            "tests": n,
            "obtained": round(g, 2),
            "max": round(o, 2),
            "percent": _percent(g, o),
        })
        total_got[student_id] += g
        total_out[student_id] += o

    for rows in by_subject.values():
        rows.sort(key=lambda r: r["student"].lower())
    overall = sorted(
        ({
            "student": name,
            "obtained": round(total_got[sid], 2),
            "max": round(total_out[sid], 2),
            "percent": _percent(total_got[sid], total_out[sid]),
        } for sid, name in names.items()),
        key=lambda r: r["student"].lower(),
    )
    return dict(sorted(by_subject.items())), overall
