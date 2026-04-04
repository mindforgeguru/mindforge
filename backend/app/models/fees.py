"""
Fee-related SQLAlchemy models.
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class FeeStructure(Base):
    """Defines fee amounts per academic year and grade."""
    __tablename__ = "fee_structures"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    academic_year: Mapped[str] = mapped_column(String(20), nullable=False)  # e.g. "2024-25"
    grade: Mapped[int] = mapped_column(Integer, nullable=False)
    base_amount: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    economics_fee: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    computer_fee: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    ai_fee: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    @property
    def total_amount(self) -> float:
        return self.base_amount + self.economics_fee + self.computer_fee + self.ai_fee

    def __repr__(self) -> str:
        return f"<FeeStructure year={self.academic_year} grade={self.grade} total={self.total_amount}>"


class FeePayment(Base):
    """Records individual fee payment transactions for a student."""
    __tablename__ = "fee_payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    student_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    paid_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_by_admin_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    student = relationship("User", foreign_keys=[student_id])
    updated_by = relationship("User", foreign_keys=[updated_by_admin_id])

    def __repr__(self) -> str:
        return f"<FeePayment student_id={self.student_id} amount={self.amount}>"


class PaymentInfo(Base):
    """Tuition center payment details shown to parents for fee payment."""
    __tablename__ = "payment_info"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    slot: Mapped[int] = mapped_column(Integer, nullable=False, default=1, unique=True)
    label: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    bank_name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    branch: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    account_holder: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    account_number: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    ifsc: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    upi_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    qr_code_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return f"<PaymentInfo bank={self.bank_name} upi={self.upi_id}>"
