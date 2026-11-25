import pytest

from app.core.grades_offered import GradesOfferedError, checked_grades_offered


def test_sorted_and_deduplicated():
    assert checked_grades_offered([9, 8, 9], {}) == [8, 9]


def test_empty_is_refused():
    with pytest.raises(GradesOfferedError, match="at least one"):
        checked_grades_offered([], {})


def test_unsupported_grade_is_refused():
    with pytest.raises(GradesOfferedError, match="Grade 11"):
        checked_grades_offered([8, 11], {})


def test_grade_with_students_cannot_be_dropped():
    with pytest.raises(GradesOfferedError, match="Grade 10 still has 3 students"):
        checked_grades_offered([8, 9], {8: 40, 10: 3})


def test_grade_without_students_can_be_dropped():
    assert checked_grades_offered([8, 9], {8: 40, 10: 0}) == [8, 9]


# ── grade_not_offered_message: homework, broadcasts, tests, presentations ────

from app.core.grades_offered import grade_not_offered_message


def test_offered_grade_is_allowed():
    assert grade_not_offered_message(8, [8, 9], "Sunrise") is None


def test_grade_the_school_does_not_teach_is_refused_by_name():
    assert grade_not_offered_message(10, [8, 9], "Sunrise") == \
        "Sunrise doesn't have a Grade 10."


def test_missing_grades_list_refuses():
    assert grade_not_offered_message(8, None, "Sunrise") == \
        "Sunrise doesn't have a Grade 8."
