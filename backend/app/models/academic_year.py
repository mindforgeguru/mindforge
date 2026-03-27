"""
AcademicYear model — tracks school years and rollover history.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AcademicYear(Base):
    __tablename__ = "academic_years"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    year_label: Mapped[str] = mapped_column(String(20), nullable=False)  # e.g. "2025-26"
    is_current: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    started_by_admin_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL", use_alter=True, name="fk_academic_years_started_by_admin"), nullable=True
    )

    def __repr__(self) -> str:
        return f"<AcademicYear {self.year_label} current={self.is_current}>"
