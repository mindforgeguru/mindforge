"""
User and StudentProfile SQLAlchemy models.
Implements soft-delete via deleted_at column.
"""

import enum
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import (
    Boolean, DateTime, Enum, ForeignKey, Integer, JSON, String, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class UserRole(str, enum.Enum):
    teacher = "teacher"
    student = "student"
    parent = "parent"
    admin = "admin"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    mpin_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole, name='user_role'), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_approved: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    profile_pic_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    academic_year_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("academic_years.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    # Soft delete: set to timestamp when user is revoked/deleted
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    student_profile: Mapped[Optional["StudentProfile"]] = relationship(
        "StudentProfile", back_populates="user", foreign_keys="StudentProfile.user_id", uselist=False
    )
    teacher_profile: Mapped[Optional["TeacherProfile"]] = relationship(
        "TeacherProfile", back_populates="user", foreign_keys="TeacherProfile.user_id", uselist=False
    )

    def soft_delete(self):
        self.deleted_at = datetime.now(timezone.utc)
        self.is_active = False

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

    def __repr__(self) -> str:
        return f"<User id={self.id} username={self.username} role={self.role}>"


class StudentProfile(Base):
    __tablename__ = "student_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    grade: Mapped[int] = mapped_column(Integer, nullable=False)  # 8, 9, or 10
    profile_pic_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    # additional_subjects chosen at registration: e.g. ["economics", "computer", "ai"]
    additional_subjects: Mapped[Optional[list]] = mapped_column(JSON, nullable=True, default=list)
    # parent_user_id links this student to their parent account
    parent_user_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    # Relationships
    user: Mapped["User"] = relationship(
        "User", back_populates="student_profile", foreign_keys=[user_id]
    )
    parent: Mapped[Optional["User"]] = relationship(
        "User", foreign_keys=[parent_user_id]
    )

    def __repr__(self) -> str:
        return f"<StudentProfile user_id={self.user_id} grade={self.grade}>"


class TeacherProfile(Base):
    __tablename__ = "teacher_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    # subjects the teacher is qualified to teach — e.g. ["Mathematics", "Physics"]
    teachable_subjects: Mapped[Optional[list]] = mapped_column(JSON, nullable=True, default=list)

    user: Mapped["User"] = relationship(
        "User", back_populates="teacher_profile", foreign_keys=[user_id]
    )

    def __repr__(self) -> str:
        return f"<TeacherProfile user_id={self.user_id}>"
