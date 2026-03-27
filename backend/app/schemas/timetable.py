"""
Pydantic schemas for Timetable.
"""

from datetime import date, time
from typing import Any, Optional

from pydantic import BaseModel


class PeriodTime(BaseModel):
    period: int
    start: str   # "HH:MM"
    end: str     # "HH:MM"


class TimetableConfigCreate(BaseModel):
    periods_per_day: int
    enable_weekends: bool = False
    period_times: Optional[list[Any]] = None


class TimetableConfigResponse(BaseModel):
    id: int
    periods_per_day: int
    enable_weekends: bool
    period_times: Optional[list[Any]] = None
    created_by_admin_id: Optional[int] = None

    model_config = {"from_attributes": True}


class TimetableSlotCreate(BaseModel):
    grade: int
    slot_date: date          # specific calendar date
    period_number: int
    subject: str
    teacher_id: Optional[int] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_holiday: bool = False
    comment: Optional[str] = None


class TimetableSlotUpdate(BaseModel):
    subject: Optional[str] = None
    teacher_id: Optional[int] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_holiday: Optional[bool] = None
    comment: Optional[str] = None


class TimetableSlotResponse(BaseModel):
    id: int
    grade: int
    slot_date: date
    period_number: int
    subject: str
    teacher_id: Optional[int] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_holiday: bool
    comment: Optional[str] = None

    model_config = {"from_attributes": True}


class TimetableSlotWithTeacherResponse(BaseModel):
    """Enriched slot response that includes the teacher's username and period
    times resolved from the admin timetable config."""
    id: int
    grade: int
    slot_date: str           # "YYYY-MM-DD" string
    period_number: int
    subject: str
    teacher_id: Optional[int] = None
    teacher_username: Optional[str] = None
    start_time: Optional[str] = None   # "HH:MM" string
    end_time: Optional[str] = None
    is_holiday: bool
    comment: Optional[str] = None
