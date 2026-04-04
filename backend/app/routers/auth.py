"""
Authentication router:
- POST /auth/register  — create a pending user (awaits admin approval)
- POST /auth/login     — validate credentials, return JWT
- GET  /auth/me        — return current user info
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import (
    hash_mpin, verify_mpin, create_access_token, get_current_user
)
from app.models.academic_year import AcademicYear
from app.models.user import User, StudentProfile, TeacherProfile
from app.schemas.user import (
    UserRegisterRequest, UserLoginRequest, TokenResponse,
    UserResponse, StudentProfileCreate
)
from app.services import storage_service

router = APIRouter()


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register_user(
    payload: UserRegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Register a new user. Account is created in pending state (is_approved=False).
    Admin must approve before the user can log in.
    """
    # Check username uniqueness
    existing = await db.execute(
        select(User).where(User.username == payload.username, User.deleted_at.is_(None))
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username already taken.",
        )

    # Resolve current academic year (if any)
    year_result = await db.execute(
        select(AcademicYear).where(AcademicYear.is_current == True)
    )
    current_year = year_result.scalar_one_or_none()

    user = User(
        username=payload.username,
        mpin_hash=hash_mpin(payload.mpin),
        role=payload.role,
        is_active=True,
        is_approved=False,  # Pending admin approval
        academic_year_id=current_year.id if current_year else None,
    )
    db.add(user)
    await db.flush()  # Get the generated user.id

    # If registering as teacher, create a TeacherProfile with teachable subjects
    if payload.role == "teacher":
        teacher_profile = TeacherProfile(
            user_id=user.id,
            teachable_subjects=payload.teachable_subjects or [],
        )
        db.add(teacher_profile)

    # If registering as student, create a StudentProfile with grade and subjects
    if payload.role == "student":
        parent_user_id = None
        if payload.parent_username:
            from sqlalchemy import func as sa_func
            parent_result = await db.execute(
                select(User).where(
                    sa_func.lower(User.username) == payload.parent_username.strip().lower(),
                    User.role == "parent",
                    User.deleted_at.is_(None),
                )
            )
            parent = parent_result.scalar_one_or_none()
            if parent:
                parent_user_id = parent.id
            else:
                # Parent account doesn't exist — auto-create it with the same
                # MPIN so the parent can log in after admin approval.
                new_parent = User(
                    username=payload.parent_username.strip(),
                    mpin_hash=hash_mpin(payload.mpin),
                    role="parent",
                    is_active=True,
                    is_approved=False,
                    academic_year_id=current_year.id if current_year else None,
                )
                db.add(new_parent)
                await db.flush()
                parent_user_id = new_parent.id

        grade = payload.grade if payload.grade in (8, 9, 10) else 8
        subjects = payload.additional_subjects or []

        profile = StudentProfile(
            user_id=user.id,
            grade=grade,
            parent_user_id=parent_user_id,
            additional_subjects=subjects,
        )
        db.add(profile)

    await db.commit()
    await db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
async def login(
    payload: UserLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Authenticate user with username + 6-digit MPIN.
    Returns a JWT token on success.
    """
    result = await db.execute(
        select(User).where(User.username == payload.username, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()

    if not user or not verify_mpin(payload.mpin, user.mpin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or MPIN.",
        )

    if not user.is_approved:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account is pending admin approval. Please wait.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been deactivated.",
        )

    token = create_access_token(data={"sub": str(user.id), "role": user.role})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        role=user.role,
        user_id=user.id,
        username=user.username,
    )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """Return the currently authenticated user's profile."""
    pic = current_user.profile_pic_url
    # Legacy: if stored value is "bucket/key" path (old format), convert to public URL
    if pic and not pic.startswith("http"):
        parts = pic.split("/", 1)
        if len(parts) == 2:
            try:
                pic = storage_service.get_public_url(parts[0], parts[1])
            except Exception:
                pic = None

    return UserResponse(
        id=current_user.id,
        username=current_user.username,
        role=current_user.role,
        is_active=current_user.is_active,
        is_approved=current_user.is_approved,
        created_at=current_user.created_at,
        deleted_at=current_user.deleted_at,
        profile_pic_url=pic,
    )
