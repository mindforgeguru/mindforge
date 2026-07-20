"""
School (tenant) model — the top-level container for a customer school.

Every non-owner user belongs to exactly one school, and all tenant data is
scoped by ``school_id``. The platform owner (``UserRole.owner``) has
``school_id = NULL`` and is the only role that can create/manage schools.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class School(Base):
    __tablename__ = "schools"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    # URL/login-friendly identifier, unique across the platform (e.g. "hansel-gretel").
    # Used by the public school picker and any future per-school URLs.
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    logo_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    address: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    contact_email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    contact_phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # Soft on/off switch — a suspended school's users can't log in and it drops
    # out of the public picker, without deleting any data.
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Billing/subscription state for selling access. Free-form for now; a proper
    # billing model can replace these later.
    subscription_status: Mapped[str] = mapped_column(
        String(30), default="active", nullable=False
    )
    subscription_plan: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return f"<School id={self.id} name={self.name!r} slug={self.slug}>"
