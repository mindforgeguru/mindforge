"""
XP & Level system SQLAlchemy models.

Three tables:
  - student_xp: one row per student, denormalised total + current level
  - xp_transactions: append-only audit log of every XP award/deduction
  - level_configs: lookup table mapping level number to cumulative XP and title

Idempotency on transactions is enforced by a partial unique index on
(student_id, reason, reference_id) where reference_id IS NOT NULL — this
guarantees a single test/homework cannot award XP twice even across regrades
or retried requests.
"""

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    DateTime, Enum, ForeignKey, Integer, JSON, String, UniqueConstraint, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class XPReason(str, enum.Enum):
    ATTENDANCE = "ATTENDANCE"
    HOMEWORK_ON_TIME = "HOMEWORK_ON_TIME"
    HOMEWORK_LATE = "HOMEWORK_LATE"
    TEST_SCORE = "TEST_SCORE"
    TEST_PERFECT = "TEST_PERFECT"
    STREAK_BONUS = "STREAK_BONUS"
    MANUAL_ADJUSTMENT = "MANUAL_ADJUSTMENT"


class StudentXP(Base):
    """One row per student. Denormalised total + computed current level."""
    __tablename__ = "student_xp"
    __table_args__ = (
        UniqueConstraint("student_id", name="uq_student_xp_student"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    student_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    total_xp: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    current_level: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    # Cosmetic theme picked by the student. NULL = use the default theme.
    # Validated by the service against the unlocks defined on LevelConfig.
    selected_theme: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    student = relationship("User", foreign_keys=[student_id])

    def __repr__(self) -> str:
        return (
            f"<StudentXP student_id={self.student_id} "
            f"xp={self.total_xp} level={self.current_level}>"
        )


class XPTransaction(Base):
    """Append-only audit log of every XP award."""
    __tablename__ = "xp_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    student_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[XPReason] = mapped_column(
        Enum(XPReason, name="xp_reason"), nullable=False, index=True
    )
    # reference_id ties the award to a domain object (test_id, homework_id,
    # attendance period, etc). Combined with reason it gives the (student,
    # event) idempotency key — see partial unique index in migration 021.
    reference_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(String(300), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    student = relationship("User", foreign_keys=[student_id])

    def __repr__(self) -> str:
        return (
            f"<XPTransaction student_id={self.student_id} "
            f"amount={self.amount} reason={self.reason}>"
        )


class LevelConfig(Base):
    """Maps level number → cumulative XP required + display title.

    Seeded once via migration 021 with levels 1..50. The `unlocks` JSON
    column is reserved for future cosmetic unlocks (Phase 3) and is
    optional/null on every seeded row.
    """
    __tablename__ = "level_configs"

    level: Mapped[int] = mapped_column(Integer, primary_key=True)
    xp_required: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    unlocks: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

    def __repr__(self) -> str:
        return (
            f"<LevelConfig level={self.level} xp_required={self.xp_required} "
            f"title={self.title}>"
        )
