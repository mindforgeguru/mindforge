"""Pydantic schemas for the auto-presentation feature."""

from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator


# ── Responses ────────────────────────────────────────────────────────────────


class PresentationSlideOut(BaseModel):
    """A single slide in the deck."""
    id: int
    slide_index: int
    title: str
    body_md: str
    speaker_notes: str
    last_edited_by_username: Optional[str] = None
    last_edited_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class PresentationProgressOut(BaseModel):
    """One teacher's pace through a presentation."""
    teacher_id: int
    teacher_username: str
    current_slide_index: int
    periods_used: int
    updated_at: datetime

    model_config = {"from_attributes": True}


class PresentationPeriodLogOut(BaseModel):
    """One period record."""
    id: int
    teacher_id: int
    teacher_username: str
    period_date: date
    period_number: Optional[int] = None
    slides_covered_from: int
    slides_covered_to: int
    notes: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PresentationListItem(BaseModel):
    """Row in the school-wide list. One row per (teacher_progress) so the
    same chapter taught by three teachers shows three cards."""
    presentation_id: int
    grade: int
    subject: str
    chapter_name: str
    status: str
    total_slides: int
    recommended_periods: int
    default_slides_per_period: int
    created_by_teacher_id: int
    created_by_username: str
    created_at: datetime

    # Per-teacher progress fields (for the teacher who owns this card row).
    teacher_id: int
    teacher_username: str
    current_slide_index: int
    periods_used: int

    @property
    def progress_pct(self) -> float:
        if self.total_slides <= 0:
            return 0.0
        return round(100.0 * self.current_slide_index / self.total_slides, 1)


class PresentationDetail(BaseModel):
    """Full presentation: meta + slides + every teacher's progress + logs."""
    id: int
    grade: int
    subject: str
    chapter_name: str
    status: str
    failure_reason: Optional[str] = None
    total_slides: int
    recommended_periods: int
    default_slides_per_period: int
    created_by_teacher_id: int
    created_by_username: str
    created_at: datetime
    last_edited_by_username: Optional[str] = None
    last_edited_at: Optional[datetime] = None

    slides: List[PresentationSlideOut]
    all_progress: List[PresentationProgressOut]
    period_logs: List[PresentationPeriodLogOut]

    # Convenience fields for the calling teacher
    my_current_slide_index: int = 0
    my_periods_used: int = 0
    my_slides_left: int = 0
    my_periods_left: int = 0
    my_slides_per_period_suggested: int = 0


class PresentationCreateResponse(BaseModel):
    presentation_id: int
    status: str


# ── Inputs ───────────────────────────────────────────────────────────────────


class PresentationSlidePatch(BaseModel):
    title: Optional[str] = Field(None, max_length=300)
    body_md: Optional[str] = None
    speaker_notes: Optional[str] = None

    @field_validator("title")
    @classmethod
    def trim_title(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("Slide title cannot be empty.")
        return v


class PresentationPeriodLogCreate(BaseModel):
    period_date: date
    period_number: Optional[int] = Field(None, ge=1, le=12)
    slides_covered_to: int = Field(..., ge=0)
    notes: Optional[str] = Field(None, max_length=1000)
