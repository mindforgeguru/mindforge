"""
Authentication router:
- POST /auth/register  — create a pending user (awaits admin approval)
- POST /auth/login     — validate credentials, return JWT
- POST /auth/refresh   — exchange refresh token for new access token
- GET  /auth/me        — return current user info
"""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response, status
from jose import JWTError, jwt as _jose_jwt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.config import settings
from app.core.security import (
    hash_mpin, verify_mpin, create_access_token, create_refresh_token,
    decode_access_token, get_current_user
)
from app.models.academic_year import AcademicYear
from app.models.user import User, StudentProfile, TeacherProfile
from app.schemas.user import (
    UserRegisterRequest, UserLoginRequest, TokenResponse,
    RefreshRequest, RefreshResponse, UserResponse, StudentProfileCreate
)
from app.core.redis_client import redis_manager
from app.services import storage_service

router = APIRouter()

# ── Cookie helpers ────────────────────────────────────────────────────────────

_COOKIE_NAME = "session"
_COOKIE_MAX_AGE = settings.JWT_EXPIRE_MINUTES * 60


def _set_session_cookie(response: Response, access_token: str) -> None:
    """Set a Secure HttpOnly SameSite=Strict cookie for web browser clients."""
    response.set_cookie(
        key=_COOKIE_NAME,
        value=access_token,
        max_age=_COOKIE_MAX_AGE,
        path="/api",
        httponly=True,
        secure=True,
        samesite="strict",
    )


def _clear_session_cookie(response: Response) -> None:
    """Expire the session cookie (used on logout)."""
    response.delete_cookie(key=_COOKIE_NAME, path="/api", httponly=True, secure=True, samesite="strict")


def _get_client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


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

    # Phone is required for student and teacher
    if payload.role in ("student", "teacher") and not payload.phone:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Phone number is required for student and teacher accounts.",
        )

    # A linked parent account is mandatory for every student. Without a parent
    # in place, no one can ever delete the student's account (students can't
    # self-delete; only the parent or an admin can). The frontend enforces this
    # but we double-gate here for any direct API caller.
    if payload.role == "student" and not (
        payload.parent_username and payload.parent_username.strip()
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A parent username is required to register a student account.",
        )

    # Check phone uniqueness (if provided)
    if payload.phone:
        phone_conflict = await db.execute(
            select(User).where(User.phone == payload.phone, User.deleted_at.is_(None))
        )
        if phone_conflict.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this phone number already exists.",
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
        phone=payload.phone or None,
        email=payload.email or None,
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
    request: Request,
    response: Response,
    payload: UserLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Authenticate user with username + 6-digit MPIN.
    Returns a JWT token on success.
    """
    ip = _get_client_ip(request)
    rate_key = f"rate_limit:login:{ip}:{payload.username}"
    if await redis_manager.rate_limit(rate_key, max_attempts=10, window_seconds=60):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Please wait 60 seconds and try again.",
            headers={"Retry-After": "60"},
        )

    result = await db.execute(
        select(User).where(User.username == payload.username, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()

    # Check per-user lockout before touching the DB password check
    if user and await redis_manager.is_user_locked_out(user.id):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account temporarily locked due to too many failed attempts. Try again in 15 minutes.",
            headers={"Retry-After": "900"},
        )

    if not user or not verify_mpin(payload.mpin, user.mpin_hash):
        # Record the failure against the user (if the username exists)
        if user:
            await redis_manager.record_failed_login(user.id)
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

    # Successful login — clear any prior failure counter
    await redis_manager.clear_failed_logins(user.id)

    token_data = {"sub": str(user.id), "role": user.role}
    access_token = create_access_token(data=token_data)
    refresh_token = create_refresh_token(data=token_data)

    # Set a Secure HttpOnly cookie for web browser clients.
    # Mobile clients use the Bearer token from the JSON body and ignore this.
    _set_session_cookie(response, access_token)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        role=user.role,
        user_id=user.id,
        username=user.username,
    )


@router.post("/refresh", response_model=RefreshResponse)
async def refresh_access_token(
    response: Response,
    payload: RefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    """Exchange a valid refresh token for a new access token + rotated refresh token.
    The used refresh token's JTI is immediately blacklisted so it cannot be reused.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired refresh token.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        data = decode_access_token(payload.refresh_token)
        if data.get("type") != "refresh":
            raise credentials_exception
        user_id_raw = data.get("sub")
        if user_id_raw is None:
            raise credentials_exception
        user_id = int(user_id_raw)
        jti = data.get("jti")
        exp = data.get("exp")
    except (JWTError, ValueError):
        raise credentials_exception

    # Reject already-used (blacklisted) tokens
    if jti and await redis_manager.is_jti_revoked(jti):
        raise credentials_exception

    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None or not user.is_approved or not user.is_active:
        raise credentials_exception

    # Blacklist the consumed JTI (TTL = remaining lifetime of the old token)
    if jti and exp:
        remaining = max(int(exp - datetime.now(timezone.utc).timestamp()), 1)
        await redis_manager.revoke_jti(jti, remaining)

    token_data = {"sub": str(user.id), "role": user.role}
    new_access_token = create_access_token(data=token_data)
    new_refresh_token = create_refresh_token(data=token_data)
    _set_session_cookie(response, new_access_token)
    return RefreshResponse(access_token=new_access_token, refresh_token=new_refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    request: Request,
    response: Response,
    body: Optional[dict] = Body(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Invalidate the session completely:
    - Access token JTI is blacklisted in Redis (checked on every request).
    - Refresh token JTI is also blacklisted when the client sends it in the
      request body as {"refresh_token": "<token>"}. This prevents a captured
      refresh token from minting new access tokens after logout.
    - FCM token is cleared so no further push notifications are sent.
    """
    # Revoke the access token.
    access_token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if access_token:
        try:
            at_payload = decode_access_token(access_token)
            jti = at_payload.get("jti")
            exp = at_payload.get("exp")
            if jti and exp:
                remaining = max(int(exp - datetime.now(timezone.utc).timestamp()), 1)
                await redis_manager.revoke_access_jti(jti, remaining)
        except Exception:
            pass  # already invalid/expired — nothing to do

    # Revoke the refresh token if the client provided it.
    if isinstance(body, dict):
        refresh_token = body.get("refresh_token")
        if refresh_token and isinstance(refresh_token, str):
            try:
                rt_payload = decode_access_token(refresh_token)
                if rt_payload.get("type") == "refresh":
                    rt_jti = rt_payload.get("jti")
                    rt_exp = rt_payload.get("exp")
                    if rt_jti and rt_exp:
                        remaining = max(int(rt_exp - datetime.now(timezone.utc).timestamp()), 1)
                        await redis_manager.revoke_jti(rt_jti, remaining)
            except Exception:
                pass  # invalid/expired refresh token — nothing to do

    current_user.fcm_token = None
    await db.commit()

    _clear_session_cookie(response)



@router.put("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def update_fcm_token(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Store or update the FCM device token for the authenticated user."""
    token = payload.get("fcm_token")
    if not token or not isinstance(token, str):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="fcm_token is required.",
        )
    current_user.fcm_token = token.strip()
    await db.commit()


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """Return the currently authenticated user's profile."""
    from urllib.parse import urlparse
    pic = current_user.profile_pic_url

    if pic:
        if not pic.startswith("http"):
            # Legacy format: "bucket/key" path stored directly
            parts = pic.split("/", 1)
            if len(parts) == 2:
                try:
                    pic = storage_service.get_public_url(parts[0], parts[1])
                except Exception:
                    pic = None
        else:
            # Check for internal MinIO hostname (minio:9000, minio.railway.internal, etc.)
            parsed = urlparse(pic)
            is_internal = (
                "minio" in parsed.hostname
                and not parsed.hostname.startswith("api.")
            ) if parsed.hostname else False
            if is_internal:
                # Extract bucket and key from the URL path and rebuild as proxy URL
                try:
                    path = parsed.path.lstrip("/")  # e.g. "mindforge-profiles/profiles/7/avatar.jpg"
                    bucket, key = path.split("/", 1)
                    pic = storage_service.get_public_url(bucket, key)
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


@router.delete("/account", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_account(
    request: Request,
    response: Response,
    body: Optional[dict] = Body(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Self-service account deletion — required by Play Store / App Store.

    Deletion policy (set 2026-05-14):
      • Admins cannot self-delete — use the admin user-management endpoints.
      • Students cannot self-delete — their account is created and managed by
        a parent (and the school). Only the linked parent or an admin can
        delete a student account.
      • When a parent self-deletes, the deletion cascades to the parent's one
        linked student account (parent + child are removed together). If the
        parent has more than one linked active student, the request is
        rejected — the school must intervene to pick which child to keep.

    Soft-delete sets `deleted_at` + `is_active=False` so historical rows
    referencing the user (attendance, grades, fees, audit trail) stay intact.
    Revokes the current access + refresh tokens and clears the FCM token.
    """
    from app.models.user import UserRole

    if current_user.role == UserRole.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin accounts cannot be self-deleted. Use the admin tools.",
        )

    if current_user.role == UserRole.student:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Students cannot delete their own account. Ask your parent "
                "to delete the account (your parent's deletion also removes "
                "the linked student account), or contact the school admin."
            ),
        )

    # ── Parent role: find linked active student(s) and cascade ────────────────
    cascade_student: Optional[User] = None
    if current_user.role == UserRole.parent:
        linked_result = await db.execute(
            select(User)
            .join(StudentProfile, StudentProfile.user_id == User.id)
            .where(
                StudentProfile.parent_user_id == current_user.id,
                User.deleted_at.is_(None),
            )
        )
        linked_students = linked_result.scalars().all()
        if len(linked_students) > 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "This parent account is linked to more than one student. "
                    "Self-deletion would remove multiple accounts at once. "
                    "Please contact the school admin to delete one specific "
                    "student before deleting the parent account."
                ),
            )
        if len(linked_students) == 1:
            cascade_student = linked_students[0]

    # Revoke the access token JTI so the same bearer can't be reused.
    access_token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if access_token:
        try:
            at_payload = decode_access_token(access_token)
            jti = at_payload.get("jti")
            exp = at_payload.get("exp")
            if jti and exp:
                remaining = max(int(exp - datetime.now(timezone.utc).timestamp()), 1)
                await redis_manager.revoke_access_jti(jti, remaining)
        except Exception:
            pass

    # Revoke the refresh token if the client sent it.
    if isinstance(body, dict):
        refresh_token = body.get("refresh_token")
        if refresh_token and isinstance(refresh_token, str):
            try:
                rt_payload = decode_access_token(refresh_token)
                if rt_payload.get("type") == "refresh":
                    rt_jti = rt_payload.get("jti")
                    rt_exp = rt_payload.get("exp")
                    if rt_jti and rt_exp:
                        remaining = max(
                            int(rt_exp - datetime.now(timezone.utc).timestamp()), 1
                        )
                        await redis_manager.revoke_jti(rt_jti, remaining)
            except Exception:
                pass

    current_user.fcm_token = None
    current_user.soft_delete()

    from app.models.audit_log import AuditLog

    # Audit-log the self-deletion. Admin id is the same user (acting on self).
    db.add(AuditLog(
        admin_id=current_user.id,
        action="self_delete",
        target_type="user",
        target_id=current_user.id,
        details={"username": current_user.username, "role": current_user.role.value},
    ))

    # Cascade soft-delete to the parent's single linked student (if any).
    # We don't know the student's session JTIs so we can't blacklist them in
    # Redis — the student's tokens will keep working until natural expiry.
    # The student row is `is_active=False + deleted_at` set, so any further
    # request that hits the User lookup (login, /auth/me, every protected
    # endpoint that filters on deleted_at IS NULL) will fail authentication.
    if cascade_student is not None:
        cascade_student.fcm_token = None
        cascade_student.soft_delete()
        db.add(AuditLog(
            admin_id=current_user.id,
            action="self_delete_cascade_child",
            target_type="user",
            target_id=cascade_student.id,
            details={
                "username": cascade_student.username,
                "role": cascade_student.role.value,
                "triggered_by_parent_id": current_user.id,
                "triggered_by_parent_username": current_user.username,
            },
        ))

    await db.commit()
    _clear_session_cookie(response)
