"""
Pydantic schemas for User and StudentProfile.
"""

import re
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

from app.models.user import UserRole

VALID_SUBJECTS = {"economics", "computer", "ai"}


# ── MPIN strength ─────────────────────────────────────────────────────────────

def _is_weak_mpin(v: str) -> bool:
    """True if the MPIN is trivially guessable. Login still accepts any
    6-digit MPIN — we only reject weak MPINs at the SET boundary so legacy
    users with weak MPINs can still log in and change them."""
    if len(set(v)) == 1:                       # 000000, 111111, ... 999999
        return True
    digits = [int(c) for c in v]
    diffs = {b - a for a, b in zip(digits, digits[1:])}
    if diffs == {1} or diffs == {-1}:          # 123456, 234567, 654321, ...
        return True
    if v[:3] == v[3:]:                         # 123123, 456456, ...
        return True
    if v[:2] == v[2:4] == v[4:]:               # 121212, 343434, ...
        return True
    # Common typing-pattern PINs that don't fit a math rule above.
    if v in {"159753", "147258", "258369", "369258",
             "753951", "951357", "789456", "456789"}:
        return True
    return False


_WEAK_MPIN_MSG = (
    "MPIN is too easy to guess. Avoid all-same-digit (e.g. 000000), "
    "simple sequences (e.g. 123456), and repeated patterns (e.g. 121212)."
)


def _validate_mpin_format(v: str) -> str:
    """Shape only: 6 digits. Used at verification sites (login, current MPIN)."""
    if not re.fullmatch(r"\d{6}", v):
        raise ValueError("MPIN must be exactly 6 digits.")
    return v


def _validate_strong_mpin(v: str) -> str:
    """Shape + weak-MPIN rejection. Used at SET sites (register, change, reset)."""
    _validate_mpin_format(v)
    if _is_weak_mpin(v):
        raise ValueError(_WEAK_MPIN_MSG)
    return v


# ── Auth / Registration ───────────────────────────────────────────────────────

class UserRegisterRequest(BaseModel):
    username: str
    mpin: str
    role: UserRole
    phone: Optional[str] = None                  # required for student/teacher; optional for parent
    email: Optional[str] = None                  # optional for all
    parent_username: Optional[str] = None        # student only
    # Required when role=student. Used to (a) auto-create the parent account if
    # parent_username doesn't exist yet, or (b) prove the student is authorized
    # to link to an existing parent. Never falls back to the student's own MPIN.
    parent_mpin: Optional[str] = None            # student only
    grade: Optional[int] = None                  # student only (8, 9, or 10)
    additional_subjects: Optional[List[str]] = None  # student only
    teachable_subjects: Optional[List[str]] = None   # teacher only

    @field_validator("role")
    @classmethod
    def restrict_self_register_role(cls, v: UserRole) -> UserRole:
        # Admin accounts are created via the seed script; parent accounts are
        # auto-created from a student's `parent_username` in the register
        # endpoint. Only student and teacher may self-register.
        if v not in (UserRole.student, UserRole.teacher):
            raise ValueError("Self-registration is only allowed for student or teacher accounts.")
        return v

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
        return _validate_strong_mpin(v)

    @field_validator("parent_mpin")
    @classmethod
    def validate_parent_mpin(cls, v: Optional[str]) -> Optional[str]:
        if v is None or v == "":
            return None
        return _validate_strong_mpin(v)

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

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        if len(v) > 150:
            raise ValueError("Username too long.")
        if "\x00" in v:
            raise ValueError("Invalid characters in username.")
        return v

    @field_validator("mpin")
    @classmethod
    def validate_mpin(cls, v: str) -> str:
        # Shape only — legacy users with weak MPINs must still be able to log in
        # so they can change them.
        return _validate_mpin_format(v)


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
    refresh_token: str
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

    @field_validator("current_mpin")
    @classmethod
    def validate_current_mpin(cls, v: str) -> str:
        # Shape only — the user is *proving* their existing MPIN; we don't
        # block weak values here or legacy weak-MPIN users couldn't change.
        return _validate_mpin_format(v)

    @field_validator("new_mpin")
    @classmethod
    def validate_new_mpin(cls, v: str) -> str:
        return _validate_strong_mpin(v)


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
    parent_mpin: Optional[str] = None       # students only — used when creating a new parent inline
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
        if v is None:
            return v
        return _validate_strong_mpin(v)

    @field_validator("parent_mpin")
    @classmethod
    def validate_parent_mpin(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        return _validate_strong_mpin(v)


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
