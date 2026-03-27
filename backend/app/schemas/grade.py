"""
Pydantic schemas for Grade.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from app.models.grade import GradeType


class GradeCreate(BaseModel):
    student_id: int
    subject: str
    chapter: str
    marks_obtained: float
    max_marks: float
    grade_type: GradeType = GradeType.manual
    test_id: Optional[int] = None

    @field_validator("marks_obtained", "max_marks")
    @classmethod
    def validate_marks(cls, v: float) -> float:
        if v < 0:
            raise ValueError("Marks cannot be negative.")
        return v


class GradeUpdate(BaseModel):
    marks_obtained: Optional[float] = None
    max_marks: Optional[float] = None
    chapter: Optional[str] = None


class GradeResponse(BaseModel):
    id: int
    student_id: int
    teacher_id: Optional[int] = None
    subject: str
    chapter: str
    test_id: Optional[int] = None
    marks_obtained: float
    max_marks: float
    percentage: float
    grade_type: GradeType
    created_at: datetime

    model_config = {"from_attributes": True}


class GradeStats(BaseModel):
    """Class-level statistics for a subject."""
    subject: str
    class_high: float
    class_low: float
    class_average: float
