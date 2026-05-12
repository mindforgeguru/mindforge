"""
Feedback router — any authenticated user can submit a problem report.
Admin endpoints for listing / resolving live in app.routers.admin.
"""
from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.redis_client import redis_manager
from app.core.security import get_current_user
from app.models.feedback import FeedbackReport
from app.models.user import User
from app.schemas.feedback import FeedbackCreate

router = APIRouter()


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def submit_feedback(
    payload: FeedbackCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Rate-limit per user so a stuck button can't spam the table.
    if await redis_manager.rate_limit(
        f"feedback:{current_user.id}", max_attempts=10, window_seconds=60
    ):
        # Silently accept and drop — keeps the UI honest, stops the flood.
        return

    db.add(FeedbackReport(
        user_id=current_user.id,
        username=current_user.username,
        role=current_user.role.value,
        app_version=payload.app_version,
        route=payload.route,
        message=payload.message.strip(),
    ))
    await db.commit()
