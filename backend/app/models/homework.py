"""
Homework and Broadcast SQLAlchemy models.
"""

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, Enum, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class HomeworkType(str, enum.Enum):
    online_test = "online_test"
    written = "written"


class Homework(Base):
    """
    Homework assigned by a teacher to a grade.
    - If homework_type == 'online_test', test_id links to an existing Test.
    - If homework_type == 'written', description holds the assignment text.
    """
    __tablename__ = "homework"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    teacher_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    grade: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    subject: Mapped[str] = mapped_column(String(100), nullable=False)
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)
    homework_type: Mapped[HomeworkType] = mapped_column(
        Enum(HomeworkType, name="homework_type"), nullable=False, default=HomeworkType.written
    )
    # Link to Test for online_test type
    test_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("tests.id", ondelete="SET NULL"), nullable=True
    )
    due_date: Mapped[Optional[datetime]] = mapped_column(Date, nullable=True)
    # True for a "no homework today" marker — a grade-wide signal that the
    # teacher deliberately assigned nothing. It satisfies the daily "assign
    # homework" workflow step but is never shown to students/parents and
    # never needs a completion review.
    is_no_homework: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    teacher = relationship("User", foreign_keys=[teacher_id])
    test = relationship("Test", foreign_keys=[test_id])

    def __repr__(self) -> str:
        return f"<Homework id={self.id} grade={self.grade} subject={self.subject}>"


class HomeworkCompletion(Base):
    """
    Per-student record of whether a piece of homework was completed.
    One row per (homework_id, student_id). Created the first time the teacher
    marks the student's status; subsequent saves overwrite the same row.
    """
    __tablename__ = "homework_completions"
    __table_args__ = (
        UniqueConstraint("homework_id", "student_id", name="uq_homework_student"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    homework_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("homework.id", ondelete="CASCADE"), nullable=False, index=True
    )
    student_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # True = completed, False = not completed. Absence of a row means the
    # teacher hasn't recorded a status for this student yet.
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    marked_by: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    marked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    homework = relationship("Homework", foreign_keys=[homework_id])
    student = relationship("User", foreign_keys=[student_id])

    def __repr__(self) -> str:
        return (
            f"<HomeworkCompletion hw={self.homework_id} student={self.student_id} "
            f"completed={self.completed}>"
        )


class Broadcast(Base):
    """
    Message broadcast sent by a teacher to all users or a specific grade.
    """
    __tablename__ = "broadcasts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    sender_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    message: Mapped[str] = mapped_column(String(2000), nullable=False)
    # 'all' = everyone, 'grade' = specific grade only
    target_type: Mapped[str] = mapped_column(String(20), nullable=False, default="all")
    # grade number if target_type == 'grade'
    target_grade: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    sender = relationship("User", foreign_keys=[sender_id])

    def __repr__(self) -> str:
        return f"<Broadcast id={self.id} title={self.title} target={self.target_type}>"
