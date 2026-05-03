"""
XP & Level system HTTP endpoints.

  GET  /api/xp/me                 — current student's XP snapshot
  GET  /api/xp/leaderboard        — class/grade/school ranking
  GET  /api/xp/student/{id}       — admin/teacher view of any student
  POST /api/xp/admin/adjust       — admin manual award/deduction
  GET  /api/xp/levels             — full level table (titles + thresholds)
"""

from typing import List, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import (
    get_current_admin,
    get_current_student,
    get_current_user,
)
from app.models.user import User, UserRole
from app.models.xp import XPReason
from app.schemas.xp import (
    LeaderboardEntry,
    LeaderboardResponse,
    LevelInfo,
    StudentXPDetails,
    ThemeInfo,
    ThemeListResponse,
    ThemeSelectRequest,
    XPAdjustmentRequest,
    XPTransactionResponse,
)
from app.services import xp_service

router = APIRouter()


@router.get("/me", response_model=StudentXPDetails)
async def get_my_xp(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Current student's XP, level, progress, and last 10 transactions."""
    return await xp_service.get_student_xp(db, current_student.id)


@router.get("/leaderboard", response_model=LeaderboardResponse)
async def get_leaderboard(
    scope: Literal["class", "grade", "school"] = Query("grade"),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Leaderboard scoped to class/grade/school.

    `class` and `grade` are equivalent right now (no class/section model);
    both filter to the viewer's own grade. School scope is global.
    """
    rows = await xp_service.get_leaderboard(
        db, scope=scope, viewer=current_user, limit=limit
    )
    return LeaderboardResponse(
        scope=scope,
        entries=[LeaderboardEntry(**r) for r in rows],
    )


@router.get("/student/{student_id}", response_model=StudentXPDetails)
async def get_student_xp_admin(
    student_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Admin/teacher view of any student's XP. Students may only call this
    for their own id (use /me — kept here for symmetry)."""
    if current_user.role not in (UserRole.admin, UserRole.teacher):
        if current_user.id != student_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view your own XP.",
            )

    target = (await db.execute(
        select(User).where(User.id == student_id, User.role == UserRole.student)
    )).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=404, detail="Student not found.")

    return await xp_service.get_student_xp(db, student_id)


@router.post(
    "/admin/adjust",
    response_model=XPTransactionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def adjust_xp(
    payload: XPAdjustmentRequest,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Admin manual XP award or deduction. Reason text is mandatory and
    stored in the transaction's description column."""
    target = (await db.execute(
        select(User).where(
            User.id == payload.student_id, User.role == UserRole.student
        )
    )).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=404, detail="Student not found.")

    txn = await xp_service.award_xp(
        db,
        student_id=payload.student_id,
        reason=XPReason.MANUAL_ADJUSTMENT,
        amount=payload.amount,
        # MANUAL_ADJUSTMENT uses no reference_id so multiple manual entries
        # can stack — there's no "duplicate" to guard against.
        reference_id=None,
        description=f"[{current_admin.username}] {payload.reason}",
    )
    if txn is None:
        # Only happens if amount was 0, which the schema validator already
        # rejects — guard against drift.
        raise HTTPException(status_code=400, detail="No-op adjustment.")
    return txn


@router.get("/levels", response_model=List[LevelInfo])
async def get_levels(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Full level table — useful for the client to render the level ladder."""
    return await xp_service.list_levels(db)


# ─── Cosmetic theme unlocks ───────────────────────────────────────────────────


@router.get("/themes", response_model=ThemeListResponse)
async def list_themes(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Catalogue of cosmetic themes with the current student's lock state.

    The default theme is always unlocked. Other themes unlock at the level
    declared in `level_configs.unlocks`. Frontend resolves theme_id → palette.
    """
    raw = await xp_service.list_themes(db, current_student.id)
    return ThemeListResponse(
        selected_theme=raw["selected_theme"],
        themes=[ThemeInfo(**t) for t in raw["themes"]],
    )


@router.post("/themes/select", response_model=ThemeListResponse)
async def select_theme(
    payload: ThemeSelectRequest,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Pick an unlocked theme. Pass `theme_id=null` to revert to default."""
    try:
        await xp_service.select_theme(db, current_student.id, payload.theme_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # Return the refreshed catalogue so the client has the new `selected`
    # flags without a second round-trip.
    raw = await xp_service.list_themes(db, current_student.id)
    return ThemeListResponse(
        selected_theme=raw["selected_theme"],
        themes=[ThemeInfo(**t) for t in raw["themes"]],
    )
