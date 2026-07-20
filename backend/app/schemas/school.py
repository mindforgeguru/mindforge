"""Pydantic schemas for schools."""

import re
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from app.schemas.user import _validate_strong_mpin


class SchoolPublic(BaseModel):
    """Minimal, non-sensitive school info exposed on the unauthenticated
    login/registration picker. Deliberately excludes contact/subscription
    fields — only what's needed to identify and brand a school."""
    id: int
    name: str
    slug: str
    logo_url: Optional[str] = None

    model_config = {"from_attributes": True}


# ── Owner console ─────────────────────────────────────────────────────────────

class SchoolOwnerResponse(BaseModel):
    """Full school record for the owner console, with per-role user counts."""
    id: int
    name: str
    slug: str
    logo_url: Optional[str] = None
    address: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    is_active: bool
    subscription_status: str
    subscription_plan: Optional[str] = None
    created_at: datetime
    admin_count: int = 0
    teacher_count: int = 0
    student_count: int = 0
    parent_count: int = 0

    model_config = {"from_attributes": True}


class SchoolCreate(BaseModel):
    name: str
    slug: Optional[str] = None  # auto-derived from name when omitted
    logo_url: Optional[str] = None
    address: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    subscription_plan: Optional[str] = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2 or len(v) > 200:
            raise ValueError("School name must be 2–200 characters.")
        return v

    @field_validator("slug")
    @classmethod
    def validate_slug(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.strip().lower()
        if v and not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", v):
            raise ValueError("Slug may contain lowercase letters, numbers and hyphens only.")
        return v or None


class SchoolUpdate(BaseModel):
    name: Optional[str] = None
    logo_url: Optional[str] = None
    address: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    is_active: Optional[bool] = None
    subscription_status: Optional[str] = None
    subscription_plan: Optional[str] = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.strip()
        if len(v) < 2 or len(v) > 200:
            raise ValueError("School name must be 2–200 characters.")
        return v


class SchoolAdminCreate(BaseModel):
    """Provision a school's first (or additional) admin account."""
    username: str
    mpin: str

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 3 or len(v) > 100:
            raise ValueError("Username must be 3–100 characters.")
        return v

    @field_validator("mpin")
    @classmethod
    def validate_mpin(cls, v: str) -> str:
        return _validate_strong_mpin(v)
