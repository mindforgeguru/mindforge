"""
Pydantic schemas for Grade.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, model_validator

from app.models.grade import GradeType
from app.schemas.bounds import Marks, PositiveMarks, Required


class GradeCreate(BaseModel):
    student_id: int
    subject: Required(100)
    chapter: Required(200)
    marks_obtained: Marks
    max_marks: PositiveMarks
    grade_type: GradeType = GradeType.manual
    test_id: Optional[int] = None

    @model_validator(mode="after")
    def _obtained_within_max(self):
        if self.marks_obtained > self.max_marks:
            raise ValueError("Marks obtained cannot be more than the maximum marks.")
        return self


class GradeUpdate(BaseModel):
    marks_obtained: Optional[Marks] = None
    max_marks: Optional[PositiveMarks] = None
    chapter: Optional[Required(200)] = None


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
    # Class high/low for the test this grade came from (online tests only, where
    # a cohort exists). Null for offline/manual grades that aren't tied to a
    # test — the client hides the Class High/Low row rather than showing the
    # student's own score as if it were the class's (#19).
    class_high: Optional[float] = None
    class_low: Optional[float] = None

    model_config = {"from_attributes": True}


class GradeStats(BaseModel):
    """Class-level statistics for a subject."""
    subject: str
    class_high: float
    class_low: float
    class_average: float
