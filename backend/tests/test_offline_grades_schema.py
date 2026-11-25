"""Offline marks entry: one mark per student, finite numbers only."""

import math

import pytest
from pydantic import ValidationError

from app.schemas.test import OfflineGradesBulk


def test_a_student_listed_twice_is_refused():
    with pytest.raises(ValidationError, match="listed twice"):
        OfflineGradesBulk(grades=[{"student_id": 1, "marks_obtained": 2},
                                  {"student_id": 1, "marks_obtained": 5}])


@pytest.mark.parametrize("bad", [math.nan, math.inf, -1])
def test_non_finite_or_negative_marks_are_refused(bad):
    with pytest.raises(ValidationError):
        OfflineGradesBulk(grades=[{"student_id": 1, "marks_obtained": bad}])


def test_distinct_students_with_decimals_are_fine():
    bulk = OfflineGradesBulk(grades=[{"student_id": 1, "marks_obtained": 4.5},
                                     {"student_id": 2, "marks_obtained": 0}])
    assert [g.marks_obtained for g in bulk.grades] == [4.5, 0]
