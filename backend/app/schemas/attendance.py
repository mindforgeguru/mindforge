"""
Pydantic schemas for Attendance.
"""

from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

from app.core.attendance_window import attendance_date_reason
from app.core.school_time import school_today
from app.models.attendance import AttendanceStatus
from app.schemas.bounds import Period, SchoolGrade


class AttendanceCreate(BaseModel):
    student_id: int
    grade: int
    period: int
    date: date
    status: AttendanceStatus = AttendanceStatus.present


class AttendanceBulkCreate(BaseModel):
    """Used by teachers to mark attendance for a whole class in one request."""
    grade: SchoolGrade
    period: Period
    date: date
    records: List[AttendanceCreate]

    @field_validator("date")
    @classmethod
    def _within_correction_window(cls, v: date) -> date:
        # Reject future dates and anything older than the backdate window, so a
        # teacher cannot mark attendance for a day that hasn't happened or
        # silently rewrite an old record. See core/attendance_window.py.
        # "Today" is the school's date, not the UTC server's.
        reason = attendance_date_reason(v, school_today())
        if reason:
            raise ValueError(reason)
        return v

    @field_validator("records")
    @classmethod
    def _each_student_once(cls, records: List[AttendanceCreate]) -> List[AttendanceCreate]:
        # A student listed twice hit the unique constraint and came back as
        # "That already exists — it may have just been saved", which reads as
        # a double tap. Say what's actually wrong.
        seen = set()
        for r in records:
            if r.student_id in seen:
                raise ValueError("A student is listed twice. Mark each student once.")
            seen.add(r.student_id)
        return records


class AttendanceUpdate(BaseModel):
    status: AttendanceStatus


class AttendanceResponse(BaseModel):
    id: int
    student_id: int
    teacher_id: Optional[int] = None
    grade: int
    period: int
    date: date
    status: AttendanceStatus
    created_at: datetime

    model_config = {"from_attributes": True}


class AttendanceSummary(BaseModel):
    """Aggregated attendance stats for a student."""
    student_id: int
    total_classes: int
    present_count: int
    absent_count: int
    attendance_percentage: float
