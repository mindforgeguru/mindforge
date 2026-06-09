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

    # Convenience fields for the calling teacher. `my_adopted` distinguishes
    # "I've adopted this deck for my class" from "I'm browsing/uploading but
    # haven't added it to my dashboard yet". The progress numbers below are
    # only meaningful when my_adopted is true.
    my_adopted: bool = False
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


class PresentationPeriodLogPatch(BaseModel):
    """Edit an existing period log. All fields optional — only the ones sent
    are changed. Editing never schedules an auto-quiz."""
    period_date: Optional[date] = None
    period_number: Optional[int] = Field(None, ge=1, le=12)
    slides_covered_to: Optional[int] = Field(None, ge=0)
    notes: Optional[str] = Field(None, max_length=1000)


# ── Pick-from-database flow ──────────────────────────────────────────────────


class AvailableChapter(BaseModel):
    """One row in the school-wide chapter database, with a hint about
    whether an auto-presentation already exists for it."""
    chapter_document_id: int
    teacher_id: int
    teacher_username: str
    grade: int
    subject: str
    chapter_name: str
    original_filename: str
    created_at: datetime
    existing_presentation_id: Optional[int] = None
    existing_presentation_status: Optional[str] = None


class FromChapterRequest(BaseModel):
    chapter_document_id: int
    # Frontend may want to override the display name (e.g. typo fix) without
    # editing the original chapter doc. NULL → inherit from the chapter doc.
    chapter_name_override: Optional[str] = Field(None, max_length=300)


# ── Library (school-wide presentation browser) ───────────────────────────────


class LibraryPresentation(BaseModel):
    """One row in the school-wide presentations library. Distinct from
    PresentationListItem which is keyed per (teacher, presentation) — the
    library shows one row per *presentation* with adopter aggregates."""
    presentation_id: int
    grade: int
    subject: str
    chapter_name: str
    status: str
    total_slides: int
    recommended_periods: int
    default_slides_per_period: int
    created_by_username: str
    created_at: datetime
    adopter_count: int
    completed_count: int  # how many teachers have finished it
    already_adopted_by_me: bool
    # Status of the caller's progress through this deck. mutually exclusive
    # with adopted/not-adopted:
    #   already_adopted_by_me=false → "Adopt for my class" button
    #   already_adopted_by_me=true, my_is_completed=false → "On your dashboard"
    #   already_adopted_by_me=true, my_is_completed=true → "Completed" pill
    my_is_completed: bool = False
    # Most recent updated_at across the completed-progress rows (NULL when
    # the deck has not been completed by any teacher). Used by the library
    # tab to sort the Completed group by date-of-completion desc.
    last_completion_at: Optional[datetime] = None
    # School-wide lifecycle bucket. Mutually exclusive; computed from
    # adopter_count + completed_count + status:
    #   PROCESSING / FAILED status → "PENDING"
    #   READY + no adopters         → "PENDING"
    #   READY + adopters > completed → "ONGOING"
    #   READY + adopters == completed > 0 → "COMPLETED"
    lifecycle_state: str = "PENDING"
