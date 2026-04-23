"""
AuditLog model — immutable record of every admin action.
Rows are never updated or deleted; new rows are always appended.
"""

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    # The admin who performed the action
    admin_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=False, index=True
    )

    # Short action name, e.g. "approve_user", "revoke_user", "edit_user"
    action: Mapped[str] = mapped_column(String(80), nullable=False, index=True)

    # What kind of object was acted on: "user", "fee_payment", "fee_structure", etc.
    target_type: Mapped[str] = mapped_column(String(50), nullable=False)

    # Primary key of the affected row (nullable for bulk actions)
    target_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Arbitrary JSON payload — before/after values, payload diff, notes, etc.
    details: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<AuditLog id={self.id} admin={self.admin_id} "
            f"action={self.action} target={self.target_type}:{self.target_id}>"
        )
