from app.core.report_math import attendance_rows, marks_rows

STUDENTS = [(2, "meera8"), (1, "aarav8"), (3, "kabir8")]


def test_attendance_percent_and_low_flag():
    rows = attendance_rows(STUDENTS, [
        (1, "present"), (1, "present"), (1, "present"), (1, "absent"),
        (2, "present"), (2, "absent"), (2, "absent"),
    ])
    assert [r["student"] for r in rows] == ["aarav8", "kabir8", "meera8"]
    aarav, kabir, meera = rows
    assert (aarav["present"], aarav["absent"], aarav["percent"], aarav["low"]) == (3, 1, 75.0, False)
    assert (meera["percent"], meera["low"]) == (33.3, True)
    # No attendance yet: listed, but no percentage and not flagged.
    assert (kabir["present"], kabir["percent"], kabir["low"]) == (0, None, False)


def test_marks_weight_by_max_marks():
    by_subject, overall = marks_rows(STUDENTS, [
        (1, "Physics", 45, 50),
        (1, "Physics", 1, 10),
        (2, "Physics", 8, 10),
        (1, "Mathematics", 20, 40),
    ])
    assert list(by_subject) == ["Mathematics", "Physics"]
    physics = {r["student"]: r for r in by_subject["Physics"]}
    # 46/60, not the average of 90% and 10%.
    assert physics["aarav8"]["percent"] == 76.7
    assert physics["aarav8"]["tests"] == 2
    assert physics["meera8"]["percent"] == 80.0
    assert "kabir8" not in physics
    totals = {r["student"]: r for r in overall}
    assert totals["aarav8"]["percent"] == 66.0  # 66/100
    assert totals["kabir8"]["percent"] is None


def test_marks_of_students_outside_the_grade_are_ignored():
    by_subject, _ = marks_rows(STUDENTS, [(99, "Physics", 5, 10)])
    assert by_subject == {}
