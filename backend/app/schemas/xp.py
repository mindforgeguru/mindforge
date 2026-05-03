"""
Pydantic schemas for the XP & Level system.
"""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

from app.models.xp import XPReason


class XPTransactionResponse(BaseModel):
    id: int
    student_id: int
    amount: int
    reason: XPReason
    reference_id: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class LevelInfo(BaseModel):
    level: int
    xp_required: int
    title: str

    model_config = {"from_attributes": True}


class StudentXPDetails(BaseModel):
    """Full XP snapshot used by the student dashboard."""
    student_id: int
    total_xp: int
    current_level: int
    current_level_title: str
    # XP earned within the current level (total_xp - current.xp_required)
    xp_into_level: int
    # XP needed to reach the next level (next.xp_required - current.xp_required).
    # None when the student has hit the level cap.
    xp_for_next_level: Optional[int]
    # Cumulative XP threshold for the next level. None if at cap.
    next_level_xp_required: Optional[int]
    next_level: Optional[int]
    next_level_title: Optional[str]
    # Cosmetic theme id the student has selected. Null → default theme.
    selected_theme: Optional[str] = None
    recent_transactions: List[XPTransactionResponse]


class ThemeInfo(BaseModel):
    """One row in the theme picker. Frontend resolves theme_id → palette."""
    theme_id: str
    unlock_level: int
    unlocked: bool
    selected: bool


class ThemeListResponse(BaseModel):
    selected_theme: Optional[str] = None
    themes: List[ThemeInfo]


class ThemeSelectRequest(BaseModel):
    # Empty/null clears the selection (= use default theme). Non-empty must
    # match an unlocked theme — validated server-side.
    theme_id: Optional[str] = None


class LeaderboardEntry(BaseModel):
    """Public-safe leaderboard row — no transaction details."""
    student_id: int
    username: str
    profile_pic_url: Optional[str] = None
    grade: int
    total_xp: int
    current_level: int
    rank: int


class LeaderboardResponse(BaseModel):
    scope: str  # "class" | "grade" | "school"
    entries: List[LeaderboardEntry]


class XPAdjustmentRequest(BaseModel):
    """Admin-only manual award/deduction."""
    student_id: int
    amount: int  # may be negative
    reason: str  # mandatory free-text reason — stored in description

    @field_validator("amount")
    @classmethod
    def validate_amount(cls, v: int) -> int:
        if v == 0:
            raise ValueError("Amount must be non-zero.")
        return v

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Reason is required.")
        if len(v) > 300:
            raise ValueError("Reason must be ≤ 300 characters.")
        return v
