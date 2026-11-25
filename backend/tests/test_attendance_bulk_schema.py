"""Bulk attendance: each student once."""

import datetime as dt

import pytest
from pydantic import ValidationError

from app.core.school_time import school_today
from app.schemas.attendance import AttendanceBulkCreate


def _rec(sid, status="present"):
    d = school_today()
    return {"student_id": sid, "grade": 8, "period": 1, "date": d, "status": status}


def test_a_student_listed_twice_is_refused():
    with pytest.raises(ValidationError, match="listed twice"):
        AttendanceBulkCreate(grade=8, period=1, date=school_today(),
                             records=[_rec(1), _rec(1, "absent")])


def test_distinct_students_are_fine():
    bulk = AttendanceBulkCreate(grade=8, period=1, date=school_today(),
                                records=[_rec(1), _rec(2, "absent")])
    assert [r.student_id for r in bulk.records] == [1, 2]
