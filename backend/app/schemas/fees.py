"""
Pydantic schemas for Fee structures and payments.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class FeeStructureCreate(BaseModel):
    academic_year: str
    grade: int
    base_amount: float = 0.0
    economics_fee: float = 0.0
    computer_fee: float = 0.0
    ai_fee: float = 0.0


class FeeStructureUpdate(BaseModel):
    base_amount: Optional[float] = None
    economics_fee: Optional[float] = None
    computer_fee: Optional[float] = None
    ai_fee: Optional[float] = None


class FeeStructureResponse(BaseModel):
    id: int
    academic_year: str
    grade: int
    base_amount: float
    economics_fee: float
    computer_fee: float
    ai_fee: float
    total_amount: float

    model_config = {"from_attributes": True}


class FeePaymentCreate(BaseModel):
    student_id: int
    amount: float
    notes: Optional[str] = None


class FeePaymentUpdate(BaseModel):
    amount: float
    notes: Optional[str] = None


class FeePaymentResponse(BaseModel):
    id: int
    student_id: int
    amount: float
    paid_at: datetime
    updated_by_admin_id: Optional[int] = None
    notes: Optional[str] = None

    model_config = {"from_attributes": True}


class PaymentInfoCreate(BaseModel):
    label: Optional[str] = None
    bank_name: Optional[str] = None
    account_holder: Optional[str] = None
    account_number: Optional[str] = None
    ifsc: Optional[str] = None
    upi_id: Optional[str] = None
    qr_code_url: Optional[str] = None


class PaymentInfoResponse(BaseModel):
    id: int
    slot: int = 1
    label: Optional[str] = None
    bank_name: Optional[str] = None
    account_holder: Optional[str] = None
    account_number: Optional[str] = None
    ifsc: Optional[str] = None
    upi_id: Optional[str] = None
    qr_code_url: Optional[str] = None
    updated_at: datetime

    model_config = {"from_attributes": True}


class StudentFeeSummary(BaseModel):
    """Aggregated fee info for a specific student shown to parents."""
    student_id: int
    academic_year: str
    grade: int
    total_fee: float
    total_paid: float
    balance_due: float
    # Fee breakdown
    base_amount: float = 0.0
    economics_fee: float = 0.0
    computer_fee: float = 0.0
    ai_fee: float = 0.0
    payments: list[FeePaymentResponse]
    payment_options: list[PaymentInfoResponse] = []
