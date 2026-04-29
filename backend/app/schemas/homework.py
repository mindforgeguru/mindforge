"""
Pydantic schemas for Homework and Broadcast.
"""

from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel

from app.models.homework import HomeworkType


class HomeworkCreate(BaseModel):
    grade: int
    subject: str
    title: str
    description: Optional[str] = None
    homework_type: HomeworkType = HomeworkType.written
    test_id: Optional[int] = None
    due_date: Optional[date] = None


class HomeworkResponse(BaseModel):
    id: int
    teacher_id: int
    grade: int
    subject: str
    title: str
    description: Optional[str] = None
    homework_type: HomeworkType
    test_id: Optional[int] = None
    due_date: Optional[date] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class HomeworkCompletionRecord(BaseModel):
    """One student's completion status, used in bulk upsert payload."""
    student_id: int
    completed: bool


class HomeworkCompletionBulkUpdate(BaseModel):
    records: List[HomeworkCompletionRecord]


class HomeworkCompletionDetail(BaseModel):
    """Teacher-facing row: the student's identity plus their status."""
    student_id: int
    username: str
    completed: bool
    marked_at: Optional[datetime] = None


class StudentHomeworkCompletion(BaseModel):
    """Student/parent-facing: which homework was completed.

    Absence of an entry means the teacher hasn't recorded a status yet —
    treat as 'pending' on the client.
    """
    homework_id: int
    completed: bool
    marked_at: Optional[datetime] = None


class BroadcastCreate(BaseModel):
    title: str
    message: str
    target_type: str = "all"   # "all" or "grade"
    target_grade: Optional[int] = None


class BroadcastResponse(BaseModel):
    id: int
    sender_id: int
    sender_username: str
    title: str
    message: str
    target_type: str
    target_grade: Optional[int] = None
    created_at: datetime

    model_config = {"from_attributes": True}
