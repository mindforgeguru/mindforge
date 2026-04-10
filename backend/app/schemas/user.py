"""
Pydantic schemas for User and StudentProfile.
"""

import re
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

from app.models.user import UserRole

VALID_SUBJECTS = {"economics", "computer", "ai"}


# ── Auth / Registration ───────────────────────────────────────────────────────

class UserRegisterRequest(BaseModel):
    username: str
    mpin: str
    role: UserRole
    phone: Optional[str] = None                  # required for student/teacher; optional for parent
    email: Optional[str] = None                  # optional for all
    parent_username: Optional[str] = None        # student only
    grade: Optional[int] = None                  # student only (8, 9, or 10)
    additional_subjects: Optional[List[str]] = None  # student only
    teachable_subjects: Optional[List[str]] = None   # teacher only

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if v and not re.fullmatch(r"[\d\s\+\-\(\)]{7,20}", v):
                raise ValueError("Invalid phone number format.")
            return v or None
        return v

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if v and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", v):
                raise ValueError("Invalid email address.")
            return v or None
        return v

    @field_validator("mpin")
    @classmethod
    def validate_mpin(cls, v: str) -> str:
        if not re.fullmatch(r"\d{6}", v):
            raise ValueError("MPIN must be exactly 6 digits.")
        return v

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 3 or len(v) > 100:
            raise ValueError("Username must be 3–100 characters.")
        return v

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v not in (8, 9, 10):
            raise ValueError("Grade must be 8, 9, or 10.")
        return v

    @field_validator("additional_subjects")
    @classmethod
    def validate_subjects(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        if v is not None:
            invalid = set(v) - VALID_SUBJECTS
            if invalid:
                raise ValueError(f"Invalid subjects: {invalid}. Allowed: {VALID_SUBJECTS}")
        return v

    @field_validator("teachable_subjects")
    @classmethod
    def validate_teachable_subjects(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        return v


class UserLoginRequest(BaseModel):
    username: str
    mpin: str

    @field_validator("mpin")
    @classmethod
    def validate_mpin(cls, v: str) -> str:
        if not re.fullmatch(r"\d{6}", v):
            raise ValueError("MPIN must be exactly 6 digits.")
        return v


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: UserRole
    user_id: int
    username: str


class RefreshRequest(BaseModel):
    refresh_token: str


class RefreshResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


# ── User CRUD ─────────────────────────────────────────────────────────────────

class UserResponse(BaseModel):
    id: int
    username: str
    role: UserRole
    is_active: bool
    is_approved: bool
    created_at: datetime
    deleted_at: Optional[datetime] = None
    profile_pic_url: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None

    model_config = {"from_attributes": True}


class AdminMpinUpdate(BaseModel):
    current_mpin: str
    new_mpin: str

    @field_validator("current_mpin", "new_mpin")
    @classmethod
    def validate_mpin(cls, v: str) -> str:
        if not re.fullmatch(r"\d{6}", v):
            raise ValueError("MPIN must be exactly 6 digits.")
        return v


class UserWithProfileResponse(UserResponse):
    """Extended response that includes student profile fields (grade, parent_user_id).
    Used only for the admin user-list endpoint where profiles are joined."""
    grade: Optional[int] = None
    parent_user_id: Optional[int] = None
    parent_username: Optional[str] = None
    student_username: Optional[str] = None  # parents only — username of linked student
    teachable_subjects: Optional[List[str]] = None  # teachers only
    additional_subjects: Optional[List[str]] = None  # students only


class TeacherWithSubjectsResponse(UserResponse):
    """Extended response that includes teachable_subjects from TeacherProfile."""
    teachable_subjects: Optional[List[str]] = None


class UserUpdate(BaseModel):
    is_active: Optional[bool] = None


class AdminUserEdit(BaseModel):
    """Fields admin can change on any user."""
    username: Optional[str] = None
    role: Optional[UserRole] = None    # change role
    grade: Optional[int] = None        # students only
    new_mpin: Optional[str] = None     # reset MPIN
    phone: Optional[str] = None        # any user
    email: Optional[str] = None        # any user
    parent_username: Optional[str] = None   # students only — link to parent account
    student_username: Optional[str] = None  # parents only — link to student account
    teachable_subjects: Optional[List[str]] = None  # teachers only
    additional_subjects: Optional[List[str]] = None  # students only

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if len(v) < 3 or len(v) > 100:
                raise ValueError("Username must be 3–100 characters.")
        return v

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v not in (8, 9, 10):
            raise ValueError("Grade must be 8, 9, or 10.")
        return v

    @field_validator("new_mpin")
    @classmethod
    def validate_mpin(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not re.fullmatch(r"\d{6}", v):
            raise ValueError("MPIN must be exactly 6 digits.")
        return v


# ── StudentProfile ────────────────────────────────────────────────────────────

class StudentProfileCreate(BaseModel):
    user_id: int
    grade: int
    parent_user_id: Optional[int] = None

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: int) -> int:
        if v not in (8, 9, 10):
            raise ValueError("Grade must be 8, 9, or 10.")
        return v


class StudentProfileUpdate(BaseModel):
    grade: Optional[int] = None
    profile_pic_url: Optional[str] = None
    parent_user_id: Optional[int] = None

    @field_validator("grade")
    @classmethod
    def validate_grade(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v not in (8, 9, 10):
            raise ValueError("Grade must be 8, 9, or 10.")
        return v


class StudentProfileResponse(BaseModel):
    id: int
    user_id: int
    grade: int
    profile_pic_url: Optional[str] = None
    parent_user_id: Optional[int] = None
    additional_subjects: Optional[List[str]] = None

    model_config = {"from_attributes": True}
