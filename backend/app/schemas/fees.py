"""
Pydantic schemas for Fee structures and payments.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from app.schemas.bounds import Money, PositiveMoney, Required, SchoolGrade, Text


class FeeStructureCreate(BaseModel):
    academic_year: Required(20)
    grade: SchoolGrade
    base_amount: Money = 0.0
    economics_fee: Money = 0.0
    computer_fee: Money = 0.0
    ai_fee: Money = 0.0


class FeeStructureUpdate(BaseModel):
    base_amount: Optional[Money] = None
    economics_fee: Optional[Money] = None
    computer_fee: Optional[Money] = None
    ai_fee: Optional[Money] = None


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
    amount: PositiveMoney
    notes: Optional[Text(1000)] = None
    paid_at: Optional[datetime] = None  # defaults to now() if not provided


class FeePaymentUpdate(BaseModel):
    amount: PositiveMoney
    notes: Optional[Text(1000)] = None


class FeePaymentResponse(BaseModel):
    id: int
    student_id: int
    amount: float
    paid_at: datetime
    updated_by_admin_id: Optional[int] = None
    notes: Optional[str] = None

    model_config = {"from_attributes": True}


class PaymentInfoCreate(BaseModel):
    label: Optional[Text(100)] = None
    bank_name: Optional[Text(200)] = None
    branch: Optional[Text(200)] = None
    account_holder: Optional[Text(200)] = None
    account_number: Optional[Text(50)] = None
    ifsc: Optional[Text(20)] = None
    upi_id: Optional[Text(100)] = None
    qr_code_url: Optional[Text(500)] = None


class PaymentInfoResponse(BaseModel):
    id: int
    slot: int = 1
    label: Optional[str] = None
    bank_name: Optional[str] = None
    branch: Optional[str] = None
    account_holder: Optional[str] = None
    account_number: Optional[str] = None
    ifsc: Optional[str] = None
    upi_id: Optional[str] = None
    qr_code_url: Optional[str] = None
    updated_at: datetime

    model_config = {"from_attributes": True}

    @field_validator("qr_code_url")
    @classmethod
    def _as_media_url(cls, v: Optional[str]) -> Optional[str]:
        # Uploads before 2026-10-16 stored "bucket/key", which the fee screens
        # turned into a MinIO presigned URL on MinIO's own host — not one a
        # phone can reach. Every response gives the media-proxy URL instead.
        if v and not v.startswith("http") and "/" in v:
            from app.services import storage_service
            bucket, key = v.split("/", 1)
            return storage_service.get_public_url(bucket, key)
        return v


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
