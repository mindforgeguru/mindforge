"""
Auto-presentation SQLAlchemy models.

Four tables (see migration 024 for the SQL):

  - chapter_presentations: one row per chapter PDF uploaded; owns the deck
  - presentation_slides: shared, editable slide content
  - presentation_teacher_progress: per-teacher pace against a shared deck
  - presentation_period_logs: append-only "I taught slides X..Y on date" log

Per-teacher progress lets two teachers teach the same chapter to different
classes at different paces while sharing the slide content.
"""

import enum
from datetime import date, datetime
from typing import Optional

from sqlalchemy import (
    Date, DateTime, Enum, ForeignKey, Integer, String, Text, UniqueConstraint, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class PresentationStatus(str, enum.Enum):
    PROCESSING = "PROCESSING"
    READY = "READY"
    FAILED = "FAILED"


class ChapterPresentation(Base):
    """One row per chapter PDF uploaded by a teacher. Owns the shared deck."""
    __tablename__ = "chapter_presentations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    created_by_teacher_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    grade: Mapped[int] = mapped_column(Integer, nullable=False)
    subject: Mapped[str] = mapped_column(String(100), nullable=False)
    chapter_name: Mapped[str] = mapped_column(String(300), nullable=False)
    source_pdf_key: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    total_slides: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    recommended_periods: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    default_slides_per_period: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[PresentationStatus] = mapped_column(
        Enum(PresentationStatus, name="presentation_status"),
        nullable=False, default=PresentationStatus.PROCESSING,
    )
    failure_reason: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    last_edited_by: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    last_edited_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    creator = relationship("User", foreign_keys=[created_by_teacher_id])
    last_editor = relationship("User", foreign_keys=[last_edited_by])
    slides = relationship(
        "PresentationSlide",
        back_populates="presentation",
        cascade="all, delete-orphan",
        order_by="PresentationSlide.slide_index",
    )

    def __repr__(self) -> str:
        return (
            f"<ChapterPresentation id={self.id} grade={self.grade} "
            f"subject={self.subject} chapter={self.chapter_name!r}>"
        )


class PresentationSlide(Base):
    """One slide in a deck. Any teacher can edit title/body/notes."""
    __tablename__ = "presentation_slides"
    __table_args__ = (
        UniqueConstraint("presentation_id", "slide_index",
                         name="uq_slide_per_presentation"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    presentation_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapter_presentations.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    slide_index: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    body_md: Mapped[str] = mapped_column(Text, nullable=False, default="")
    speaker_notes: Mapped[str] = mapped_column(Text, nullable=False, default="")
    last_edited_by: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    last_edited_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    presentation = relationship("ChapterPresentation", back_populates="slides")
    last_editor = relationship("User", foreign_keys=[last_edited_by])

    def __repr__(self) -> str:
        return (
            f"<PresentationSlide id={self.id} "
            f"presentation_id={self.presentation_id} "
            f"index={self.slide_index} title={self.title!r}>"
        )


class PresentationTeacherProgress(Base):
    """One row per (presentation, teacher). Tracks that teacher's pace."""
    __tablename__ = "presentation_teacher_progress"
    __table_args__ = (
        UniqueConstraint("presentation_id", "teacher_id",
                         name="uq_progress_per_teacher_presentation"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    presentation_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapter_presentations.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    teacher_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    current_slide_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    periods_used: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(),
        onupdate=func.now(), nullable=False,
    )

    presentation = relationship("ChapterPresentation", foreign_keys=[presentation_id])
    teacher = relationship("User", foreign_keys=[teacher_id])

    def __repr__(self) -> str:
        return (
            f"<PresentationTeacherProgress presentation_id={self.presentation_id} "
            f"teacher_id={self.teacher_id} slide={self.current_slide_index}>"
        )


class PresentationPeriodLog(Base):
    """Append-only "I taught slides X..Y in period N on date D" entry."""
    __tablename__ = "presentation_period_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    presentation_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapter_presentations.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    teacher_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    period_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    period_number: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    slides_covered_from: Mapped[int] = mapped_column(Integer, nullable=False)
    slides_covered_to: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    presentation = relationship("ChapterPresentation", foreign_keys=[presentation_id])
    teacher = relationship("User", foreign_keys=[teacher_id])

    def __repr__(self) -> str:
        return (
            f"<PresentationPeriodLog presentation_id={self.presentation_id} "
            f"teacher_id={self.teacher_id} date={self.period_date} "
            f"slides={self.slides_covered_from}-{self.slides_covered_to}>"
        )
