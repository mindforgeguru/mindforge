"""
Pydantic schemas for Test and TestSubmission.
"""

from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel

from app.models.test import TestType


class TestGenerationParams(BaseModel):
    """Parameters for AI test generation."""
    title: str
    grade: int
    subject: str
    chapter: str
    test_type: TestType = TestType.online
    # Question type counts
    mcq_count: int = 5
    fill_blank_count: int = 3
    true_false_count: int = 2
    vsa_count: int = 2           # Very Short Answer (1 mark)
    # Offline-only question types
    short_answer_count: int = 0  # 2 marks each
    long_answer_count: int = 0   # 3 marks each
    diagram_count: int = 0       # 5 marks each
    include_numericals: bool = False
    time_limit_minutes: Optional[int] = None


class TestCreate(BaseModel):
    title: str
    grade: int
    subject: str
    source_file_url: Optional[str] = None
    test_type: TestType = TestType.online
    questions: Optional[List[Dict[str, Any]]] = None
    total_marks: float = 0.0
    time_limit_minutes: Optional[int] = None
    is_published: bool = False


class TestUpdate(BaseModel):
    is_published: Optional[bool] = None
    title: Optional[str] = None


class TestResponse(BaseModel):
    id: int
    title: str
    teacher_id: int
    grade: int
    subject: str
    source_file_url: Optional[str] = None
    answer_key_url: Optional[str] = None
    test_type: TestType
    questions: Optional[List[Dict[str, Any]]] = None
    total_marks: float
    time_limit_minutes: Optional[int] = None
    is_published: bool
    is_graded: bool = False
    created_at: datetime
    expires_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class OfflineGradeEntry(BaseModel):
    student_id: int
    marks_obtained: float


class OfflineGradesBulk(BaseModel):
    grades: List[OfflineGradeEntry]


class TestSubmissionCreate(BaseModel):
    """Sent by student when submitting their answers."""
    answers: Dict[str, Any]  # {question_id: answer_given}
    auto_submitted: bool = False


class TestSubmissionResponse(BaseModel):
    id: int
    test_id: int
    student_id: int
    answers: Optional[Dict[str, Any]] = None
    score: Optional[float] = None
    submitted_at: datetime
    auto_submitted: bool

    model_config = {"from_attributes": True}
