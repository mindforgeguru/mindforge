"""
TimetableConfig and TimetableSlot SQLAlchemy models.
"""

from datetime import date, datetime, time
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, JSON, String, Time, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class TimetableConfig(Base):
    """Global timetable configuration set by admin."""
    __tablename__ = "timetable_configs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    periods_per_day: Mapped[int] = mapped_column(Integer, nullable=False, default=6)
    enable_weekends: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    period_times: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
    created_by_admin_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    admin = relationship("User", foreign_keys=[created_by_admin_id])


class TimetableSlot(Base):
    """Individual timetable slots per grade/date/period."""
    __tablename__ = "timetable_slots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    grade: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    slot_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    period_number: Mapped[int] = mapped_column(Integer, nullable=False)
    subject: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    teacher_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    start_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    end_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    is_holiday: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    comment: Mapped[Optional[str]] = mapped_column(String(300), nullable=True)

    teacher = relationship("User", foreign_keys=[teacher_id])

    def __repr__(self) -> str:
        return (
            f"<TimetableSlot grade={self.grade} date={self.slot_date} "
            f"period={self.period_number} subject={self.subject}>"
        )
