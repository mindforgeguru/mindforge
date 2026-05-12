"""Pydantic schemas for feedback reports."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class FeedbackCreate(BaseModel):
    message: str = Field(..., min_length=3, max_length=4000)
    app_version: Optional[str] = Field(None, max_length=40)
    route: Optional[str] = Field(None, max_length=200)


class FeedbackResponse(BaseModel):
    id: int
    user_id: Optional[int]
    username: Optional[str]
    role: Optional[str]
    app_version: Optional[str]
    route: Optional[str]
    message: str
    resolved: bool
    created_at: datetime
    resolved_at: Optional[datetime]

    model_config = {"from_attributes": True}
