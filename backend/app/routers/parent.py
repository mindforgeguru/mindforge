"""
Parent router — all endpoints require parent role.
Parents can view their linked child's attendance, timetable, grades, and fees.
"""

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select

from app.core.database import get_db
from app.core.security import get_current_parent
from app.models.attendance import Attendance, AttendanceStatus
from app.models.fees import FeePayment, FeeStructure, PaymentInfo
from app.models.grade import Grade
from app.models.test import Test, TestType
from app.models.timetable import TimetableConfig, TimetableSlot
from app.models.user import StudentProfile, User
from sqlalchemy.orm import aliased
from app.schemas.attendance import AttendanceResponse, AttendanceSummary
from app.schemas.fees import FeePaymentResponse, FeeStructureResponse, PaymentInfoResponse, StudentFeeSummary
from app.schemas.grade import GradeResponse
from app.schemas.test import TestResponse
from app.schemas.timetable import TimetableSlotWithTeacherResponse
from app.schemas.homework import HomeworkResponse, BroadcastResponse
from app.models.homework import Homework, Broadcast

router = APIRouter()


# ─── Profile / MPIN ───────────────────────────────────────────────────────────

@router.put("/profile/mpin", status_code=status.HTTP_200_OK)
async def change_parent_mpin(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Change the parent's MPIN after verifying the current one."""
    from app.core.security import hash_mpin, verify_mpin
    import re

    current_mpin = payload.get("current_mpin", "")
    new_mpin = payload.get("new_mpin", "")

    if not verify_mpin(current_mpin, current_parent.mpin_hash):
        raise HTTPException(status_code=400, detail="Current MPIN is incorrect.")

    if not re.fullmatch(r"\d{6}", new_mpin):
        raise HTTPException(status_code=422, detail="New MPIN must be exactly 6 digits.")

    result = await db.execute(select(User).where(User.id == current_parent.id))
    parent_user = result.scalar_one()
    parent_user.mpin_hash = hash_mpin(new_mpin)
    await db.commit()
    return {"message": "MPIN updated successfully."}


async def _get_child_profile(parent: User, db: AsyncSession) -> StudentProfile:
    """Helper to retrieve the parent's linked child's StudentProfile."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.parent_user_id == parent.id)
    )
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No child account is linked to this parent account.",
        )
    return profile


# ─── Attendance ────────────────────────────────────────────────────────────────

@router.get("/child/attendance", response_model=List[AttendanceResponse])
async def get_child_attendance(
    period: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get child's attendance records."""
    profile = await _get_child_profile(current_parent, db)
    query = select(Attendance).where(Attendance.student_id == profile.user_id)
    if period:
        query = query.where(Attendance.period == period)
    result = await db.execute(query.order_by(Attendance.date.desc()))
    return result.scalars().all()


@router.get("/child/attendance/summary", response_model=AttendanceSummary)
async def get_child_attendance_summary(
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get aggregated attendance stats for the child."""
    profile = await _get_child_profile(current_parent, db)
    result = await db.execute(
        select(func.count(Attendance.id)).where(Attendance.student_id == profile.user_id)
    )
    total = result.scalar() or 0
    present_result = await db.execute(
        select(func.count(Attendance.id)).where(
            Attendance.student_id == profile.user_id,
            Attendance.status == AttendanceStatus.present,
        )
    )
    present = present_result.scalar() or 0
    absent = total - present
    percentage = round((present / total * 100) if total > 0 else 0.0, 2)

    return AttendanceSummary(
        student_id=profile.user_id,
        total_classes=total,
        present_count=present,
        absent_count=absent,
        attendance_percentage=percentage,
    )


# ─── Timetable ─────────────────────────────────────────────────────────────────

@router.get("/child/timetable", response_model=List[TimetableSlotWithTeacherResponse])
async def get_child_timetable(
    date: str = Query(...),  # YYYY-MM-DD
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get the timetable for the child's grade on a specific date."""
    from datetime import date as date_type
    slot_date = date_type.fromisoformat(date)
    profile = await _get_child_profile(current_parent, db)

    config_result = await db.execute(select(TimetableConfig))
    config = config_result.scalar_one_or_none()
    period_time_map: dict[int, tuple[str, str]] = {}
    if config and config.period_times:
        for pt in config.period_times:
            period_time_map[pt["period"]] = (pt["start"], pt["end"])

    TeacherUser = aliased(User, name="teacher")
    rows = (await db.execute(
        select(TimetableSlot, TeacherUser.username)
        .outerjoin(TeacherUser, TimetableSlot.teacher_id == TeacherUser.id)
        .where(TimetableSlot.grade == profile.grade, TimetableSlot.slot_date == slot_date)
        .order_by(TimetableSlot.period_number)
    )).all()

    enriched = []
    for slot, teacher_username in rows:
        cfg_times = period_time_map.get(slot.period_number)
        enriched.append(TimetableSlotWithTeacherResponse(
            id=slot.id,
            grade=slot.grade,
            slot_date=str(slot.slot_date),
            period_number=slot.period_number,
            subject=slot.subject,
            teacher_id=slot.teacher_id,
            teacher_username=teacher_username,
            start_time=str(slot.start_time)[:5] if slot.start_time else (cfg_times[0] if cfg_times else None),
            end_time=str(slot.end_time)[:5] if slot.end_time else (cfg_times[1] if cfg_times else None),
            is_holiday=slot.is_holiday,
            comment=slot.comment,
        ))
    return enriched


# ─── Grades ────────────────────────────────────────────────────────────────────

@router.get("/child/grades", response_model=List[GradeResponse])
async def get_child_grades(
    subject: Optional[str] = Query(None),
    grade_type: Optional[str] = Query(None),  # "online" | "offline"
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get the child's grades."""
    profile = await _get_child_profile(current_parent, db)
    query = select(Grade).where(Grade.student_id == profile.user_id)
    if subject:
        query = query.where(Grade.subject == subject)
    if grade_type:
        query = query.where(Grade.grade_type == grade_type)
    result = await db.execute(query.order_by(Grade.created_at.desc()))
    return result.scalars().all()


# ─── Tests ─────────────────────────────────────────────────────────────────────

@router.get("/child/tests", response_model=List[TestResponse])
async def get_child_tests(
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get all tests (online + offline) for the child's grade."""
    profile = await _get_child_profile(current_parent, db)
    result = await db.execute(
        select(Test)
        .where(Test.grade == profile.grade, Test.is_published == True)
        .order_by(Test.created_at.desc())
    )
    return result.scalars().all()


# ─── Fees ──────────────────────────────────────────────────────────────────────

@router.get("/fees", response_model=StudentFeeSummary)
async def get_child_fees(
    academic_year: Optional[str] = Query(None, description="e.g. '2024-25'"),
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """Get the child's fee summary including total, paid, and balance due."""
    profile = await _get_child_profile(current_parent, db)

    # Determine academic year (default to current)
    from datetime import date
    if not academic_year:
        today = date.today()
        year_start = today.year if today.month >= 6 else today.year - 1
        academic_year = f"{year_start}-{str(year_start + 1)[2:]}"

    # Fetch fee structure for this grade/year
    structure_result = await db.execute(
        select(FeeStructure).where(
            FeeStructure.grade == profile.grade,
            FeeStructure.academic_year == academic_year,
        )
    )
    structure = structure_result.scalar_one_or_none()

    # Calculate fee based on student's actual additional subjects only
    if structure:
        base_amount = structure.base_amount
        economics_fee = 0.0
        computer_fee = 0.0
        ai_fee = 0.0
        for subj in (profile.additional_subjects or []):
            if subj == "economics":
                economics_fee = structure.economics_fee
            elif subj == "computer":
                computer_fee = structure.computer_fee
            elif subj == "ai":
                ai_fee = structure.ai_fee
        total_fee = base_amount + economics_fee + computer_fee + ai_fee
    else:
        base_amount = economics_fee = computer_fee = ai_fee = total_fee = 0.0

    # Fetch all payments
    payments_result = await db.execute(
        select(FeePayment)
        .where(FeePayment.student_id == profile.user_id)
        .order_by(FeePayment.paid_at.desc())
    )
    payments = payments_result.scalars().all()
    total_paid = sum(p.amount for p in payments)

    # Fetch payment info (bank/UPI details) and resolve QR code presigned URL
    pi_result = await db.execute(select(PaymentInfo).order_by(PaymentInfo.id.desc()))
    payment_info = pi_result.scalars().first()

    payment_info_response = None
    if payment_info:
        payment_info_response = PaymentInfoResponse.model_validate(payment_info)
        if payment_info.qr_code_url and not payment_info.qr_code_url.startswith("http"):
            from app.services import storage_service
            parts = payment_info.qr_code_url.split("/", 1)
            if len(parts) == 2:
                try:
                    payment_info_response.qr_code_url = await storage_service.get_presigned_url(
                        parts[0], parts[1], expires_seconds=604800
                    )
                except Exception:
                    payment_info_response.qr_code_url = None

    return StudentFeeSummary(
        student_id=profile.user_id,
        academic_year=academic_year,
        grade=profile.grade,
        total_fee=total_fee,
        total_paid=total_paid,
        balance_due=max(0.0, total_fee - total_paid),
        base_amount=base_amount,
        economics_fee=economics_fee,
        computer_fee=computer_fee,
        ai_fee=ai_fee,
        payments=[FeePaymentResponse.model_validate(p) for p in payments],
        payment_info=payment_info_response,
    )


# ─── Homework ──────────────────────────────────────────────────────────────────

@router.get("/child/homework", response_model=List[HomeworkResponse])
async def get_child_homework(
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """List all homework assigned to the linked child's grade."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.parent_user_id == current_parent.id)
    )
    child_profile = result.scalar_one_or_none()
    if not child_profile:
        raise HTTPException(status_code=404, detail="No linked child found")

    hw_result = await db.execute(
        select(Homework)
        .where(Homework.grade == child_profile.grade)
        .order_by(Homework.created_at.desc())
    )
    return hw_result.scalars().all()


# ─── Broadcasts ────────────────────────────────────────────────────────────────

@router.get("/broadcasts", response_model=List[BroadcastResponse])
async def get_parent_broadcasts(
    db: AsyncSession = Depends(get_db),
    current_parent: User = Depends(get_current_parent),
):
    """List broadcast messages visible to this parent (all + child's grade)."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.parent_user_id == current_parent.id)
    )
    child_profile = result.scalar_one_or_none()
    grade = child_profile.grade if child_profile else None

    from sqlalchemy import or_
    q = select(Broadcast, User).join(User, Broadcast.sender_id == User.id)
    if grade is not None:
        q = q.where(
            or_(
                Broadcast.target_type == "all",
                (Broadcast.target_type == "grade") & (Broadcast.target_grade == grade),
            )
        )
    else:
        q = q.where(Broadcast.target_type == "all")
    q = q.order_by(Broadcast.created_at.desc())

    rows = (await db.execute(q)).all()
    return [
        BroadcastResponse(
            id=b.id,
            sender_id=b.sender_id,
            sender_username=u.username,
            title=b.title,
            message=b.message,
            target_type=b.target_type,
            target_grade=b.target_grade,
            created_at=b.created_at,
        )
        for b, u in rows
    ]
