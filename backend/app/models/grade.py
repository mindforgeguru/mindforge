"""
Grade SQLAlchemy model.
"""

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Enum, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class GradeType(str, enum.Enum):
    online = "online"    # auto-graded from online test submission
    offline = "offline"  # graded from offline/printed test
    manual = "manual"    # manually entered by teacher


class Grade(Base):
    __tablename__ = "grades"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    student_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    teacher_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    subject: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    chapter: Mapped[str] = mapped_column(String(200), nullable=False)
    # Optional link to an online test
    test_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("tests.id", ondelete="CASCADE"), nullable=True
    )
    marks_obtained: Mapped[float] = mapped_column(Float, nullable=False)
    max_marks: Mapped[float] = mapped_column(Float, nullable=False)
    grade_type: Mapped[GradeType] = mapped_column(
        Enum(GradeType, name='grade_type'), nullable=False, default=GradeType.manual
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    student = relationship("User", foreign_keys=[student_id])
    teacher = relationship("User", foreign_keys=[teacher_id])
    test = relationship("Test", foreign_keys=[test_id])

    @property
    def percentage(self) -> float:
        if self.max_marks == 0:
            return 0.0
        return round((self.marks_obtained / self.max_marks) * 100, 2)

    def __repr__(self) -> str:
        return (
            f"<Grade student_id={self.student_id} subject={self.subject} "
            f"{self.marks_obtained}/{self.max_marks}>"
        )
