"""
Security utilities:
- MPIN hashing (bcrypt via passlib)
- JWT creation and verification
- Role-based FastAPI dependency functions
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
import bcrypt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.config import settings
from app.core.database import get_db

bearer_scheme = HTTPBearer()


# ─── MPIN hashing ─────────────────────────────────────────────────────────────

def hash_mpin(mpin: str) -> str:
    """Hash a 6-digit MPIN using bcrypt."""
    return bcrypt.hashpw(mpin.encode(), bcrypt.gensalt()).decode()


def verify_mpin(plain_mpin: str, hashed_mpin: str) -> bool:
    """Verify a plain MPIN against its bcrypt hash."""
    return bcrypt.checkpw(plain_mpin.encode(), hashed_mpin.encode())


# ─── JWT ──────────────────────────────────────────────────────────────────────

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a signed JWT access token."""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta if expires_delta else timedelta(minutes=settings.JWT_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict:
    """Decode and validate a JWT token. Raises JWTError on failure."""
    return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])


# ─── Current user dependency ──────────────────────────────────────────────────

async def _get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
):
    """Base dependency: validates JWT and returns the active, approved User ORM object."""
    from app.models.user import User  # imported here to avoid circular imports

    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_access_token(credentials.credentials)
        user_id_raw = payload.get("sub")
        if user_id_raw is None:
            raise credentials_exception
        try:
            user_id: int = int(user_id_raw)
        except (ValueError, TypeError):
            raise credentials_exception
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception
    if not user.is_approved:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is pending admin approval.",
        )
    return user


def _require_role(role: str):
    """Factory that returns a FastAPI dependency enforcing a specific role."""
    async def role_dependency(current_user=Depends(_get_current_user)):
        if current_user.role != role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access restricted to {role} accounts.",
            )
        return current_user
    return role_dependency


# ─── Public role-based dependencies ───────────────────────────────────────────

get_current_user = _get_current_user
get_current_teacher = _require_role("teacher")
get_current_student = _require_role("student")
get_current_parent = _require_role("parent")
get_current_admin = _require_role("admin")
