"""
Pydantic schemas for Homework and Broadcast.
"""

from datetime import date, datetime
from typing import Optional

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
