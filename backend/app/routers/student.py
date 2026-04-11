"""
Student router — all endpoints require student role.
"""

from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select
from sqlalchemy.orm import aliased

from app.core.database import get_db
from app.core.redis_client import redis_manager
from app.core.security import get_current_student
from app.models.attendance import Attendance
from app.models.grade import Grade
from app.models.test import Test, TestSubmission, TestType
from app.models.timetable import TimetableConfig, TimetableSlot
from app.models.user import StudentProfile, User
from app.schemas.attendance import AttendanceResponse, AttendanceSummary
from app.schemas.grade import GradeResponse, GradeStats
from app.schemas.test import TestResponse, TestSubmissionCreate, TestSubmissionResponse
from app.schemas.timetable import TimetableSlotWithTeacherResponse
from app.schemas.homework import HomeworkResponse, BroadcastResponse
from app.schemas.fees import StudentFeeSummary
from app.models.homework import Homework, Broadcast
from app.models.fees import FeeStructure, FeePayment, PaymentInfo
from app.schemas.fees import FeePaymentResponse, PaymentInfoResponse
from app.services import storage_service
from app.core.cache import (
    get_student_profile_cached,
    get_timetable_config_cached,
    get_current_academic_year_cached,
)

router = APIRouter()


# ─── Profile ───────────────────────────────────────────────────────────────────

@router.get("/profile")
async def get_my_profile(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Return the student's grade and linked parent username."""
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    parent_username = None
    if profile.parent_user_id:
        pu = await db.execute(select(User).where(User.id == profile.parent_user_id))
        parent_user = pu.scalar_one_or_none()
        if parent_user:
            parent_username = parent_user.username

    return {
        "grade": profile.grade,
        "parent_username": parent_username,
    }


# ─── Attendance ────────────────────────────────────────────────────────────────

@router.get("/attendance", response_model=List[AttendanceResponse])
async def get_my_attendance(
    period: Optional[int] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get the current student's own attendance records."""
    query = select(Attendance).where(Attendance.student_id == current_student.id)
    if period:
        query = query.where(Attendance.period == period)
    result = await db.execute(query.order_by(Attendance.date.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.get("/attendance/summary", response_model=AttendanceSummary)
async def get_my_attendance_summary(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get aggregated attendance statistics for the current student."""
    from app.models.attendance import AttendanceStatus

    result = await db.execute(
        select(
            func.count(Attendance.id).label("total"),
            func.sum(
                func.cast(Attendance.status == AttendanceStatus.present, type_=func.count(Attendance.id).type)
            ).label("present"),
        ).where(Attendance.student_id == current_student.id)
    )
    row = result.one()
    total = row.total or 0
    present = row.present or 0
    absent = total - present
    percentage = round((present / total * 100) if total > 0 else 0.0, 2)

    return AttendanceSummary(
        student_id=current_student.id,
        total_classes=total,
        present_count=present,
        absent_count=absent,
        attendance_percentage=percentage,
    )


# ─── Timetable ─────────────────────────────────────────────────────────────────

@router.get("/timetable", response_model=List[TimetableSlotWithTeacherResponse])
async def get_my_timetable(
    date: str = Query(...),  # YYYY-MM-DD
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get the timetable for the student's grade on a specific date."""
    from datetime import date as date_type
    slot_date = date_type.fromisoformat(date)

    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    config = await get_timetable_config_cached(db)
    period_time_map: dict[int, tuple[str, str]] = {}
    if config and config.period_times:
        for pt in config.period_times:
            period_time_map[pt["period"]] = (pt["start"], pt["end"])

    TeacherUser = aliased(User, name="teacher")
    rows = (await db.execute(
        select(TimetableSlot, TeacherUser.username)
        .outerjoin(TeacherUser, TimetableSlot.teacher_id == TeacherUser.id)
        .where(
            TimetableSlot.grade == profile.grade,
            TimetableSlot.slot_date == slot_date,
        )
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

@router.get("/grades", response_model=List[GradeResponse])
async def get_my_grades(
    subject: Optional[str] = Query(None),
    grade_type: Optional[str] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get the current student's grades, optionally filtered by subject and/or grade_type."""
    from app.models.grade import GradeType as GT
    query = select(Grade).where(Grade.student_id == current_student.id)
    if subject:
        query = query.where(Grade.subject == subject)
    if grade_type:
        query = query.where(Grade.grade_type == GT(grade_type))
    result = await db.execute(query.order_by(Grade.created_at.desc()).offset(skip).limit(limit))
    return result.scalars().all()


# ─── Tests ─────────────────────────────────────────────────────────────────────

@router.get("/tests/pending", response_model=List[TestResponse])
async def get_pending_tests(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Get all online tests available to the student that:
    - Are published
    - Have not expired
    - Have not been submitted by this student yet
    """
    # Get student's grade
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    now = datetime.now(timezone.utc)

    # Get IDs of already submitted tests
    submitted_result = await db.execute(
        select(TestSubmission.test_id).where(TestSubmission.student_id == current_student.id)
    )
    submitted_ids = {row[0] for row in submitted_result.all()}

    # Fetch pending tests
    query = (
        select(Test)
        .where(
            Test.grade == profile.grade,
            Test.is_published == True,
            Test.test_type == "online",
            Test.expires_at > now,
        )
    )
    if submitted_ids:
        query = query.where(Test.id.notin_(submitted_ids))

    result = await db.execute(query.order_by(Test.created_at.desc()))
    return result.scalars().all()


@router.get("/tests/offline", response_model=List[TestResponse])
async def get_offline_tests(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get all offline tests for the student's grade (view-only)."""
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    result = await db.execute(
        select(Test)
        .where(Test.grade == profile.grade, Test.test_type == TestType.offline,
               Test.is_published == True)
        .order_by(Test.created_at.desc())
    )
    return result.scalars().all()


@router.get("/tests/completed", response_model=List[TestResponse])
async def get_completed_tests(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get online tests the student has already submitted."""
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    submitted_result = await db.execute(
        select(TestSubmission.test_id).where(TestSubmission.student_id == current_student.id)
    )
    submitted_ids = [row[0] for row in submitted_result.all()]
    if not submitted_ids:
        return []

    result = await db.execute(
        select(Test)
        .where(Test.id.in_(submitted_ids), Test.test_type == TestType.online)
        .order_by(Test.created_at.desc())
    )
    return result.scalars().all()


@router.post("/tests/{test_id}/submit", response_model=TestSubmissionResponse, status_code=status.HTTP_201_CREATED)
async def submit_test(
    test_id: int,
    payload: TestSubmissionCreate,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Submit answers for an online test.
    Auto-grades MCQ, true/false, fill-in-blank questions.
    Saves a Grade record for the student.
    """
    # Validate test
    test_result = await db.execute(select(Test).where(Test.id == test_id))
    test = test_result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found.")

    now = datetime.now(timezone.utc)
    if test.expires_at and test.expires_at < now:
        raise HTTPException(status_code=410, detail="Test submission window has expired.")

    # Check for duplicate submission
    existing_sub = await db.execute(
        select(TestSubmission).where(
            TestSubmission.test_id == test_id,
            TestSubmission.student_id == current_student.id,
        )
    )
    if existing_sub.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="You have already submitted this test.")

    # Auto-grade: exact match for MCQ/T-F/fill-blank; keyword match for VSA/numerical
    score = 0.0
    questions = test.questions or []
    for question in questions:
        q_id = str(question.get("id"))
        correct_answer = str(question.get("answer", "")).strip().lower()
        student_answer = str(payload.answers.get(q_id, "")).strip().lower()
        q_type = question.get("type", "").lower()
        marks = question.get("marks", 1)

        if q_type in ("mcq", "true_false", "fill_blank"):
            if student_answer == correct_answer:
                score += marks
        elif q_type in ("vsa", "numerical"):
            # Keyword overlap: award full marks if ≥50% of answer keywords appear
            if student_answer and correct_answer:
                stop_words = {"the", "a", "an", "is", "are", "was", "were",
                              "of", "in", "on", "at", "to", "for", "it", "its"}
                correct_words = set(correct_answer.split()) - stop_words
                student_words = set(student_answer.split()) - stop_words
                if correct_words:
                    overlap = len(correct_words & student_words) / len(correct_words)
                    if overlap >= 0.5:
                        score += marks

    # Save submission
    submission = TestSubmission(
        test_id=test_id,
        student_id=current_student.id,
        answers=payload.answers,
        score=score,
        auto_submitted=payload.auto_submitted,
    )
    db.add(submission)

    # Record as a Grade entry
    from app.models.grade import Grade, GradeType
    grade_record = Grade(
        student_id=current_student.id,
        teacher_id=test.teacher_id,
        subject=test.subject,
        chapter=f"Test: {test.title}",
        test_id=test.id,
        marks_obtained=score,
        max_marks=test.total_marks,
        grade_type=GradeType.online,
    )
    db.add(grade_record)

    await db.commit()
    await db.refresh(submission)

    # Check if all students in this grade have now submitted — if so, mark test completed
    student_count_result = await db.execute(
        select(func.count()).select_from(StudentProfile).where(StudentProfile.grade == test.grade)
    )
    student_count = student_count_result.scalar_one()
    submission_count_result = await db.execute(
        select(func.count()).select_from(TestSubmission).where(TestSubmission.test_id == test_id)
    )
    submission_count = submission_count_result.scalar_one()
    if student_count > 0 and submission_count >= student_count:
        test.is_graded = True
        await db.commit()
        await redis_manager.publish({
            "target_type": "broadcast",
            "payload": {
                "event": "test_completed",
                "test_id": test_id,
            },
        })

    # Notify teacher of submission
    await redis_manager.publish({
        "target_type": "user",
        "user_id": test.teacher_id,
        "payload": {
            "event": "test_submitted",
            "test_id": test_id,
            "student_id": current_student.id,
            "score": score,
            "total_marks": test.total_marks,
        },
    })

    # Notify student of their own grade
    await redis_manager.publish({
        "target_type": "user",
        "user_id": current_student.id,
        "payload": {
            "event": "grade_added",
            "subject": test.subject,
            "marks_obtained": score,
            "max_marks": test.total_marks,
        },
    })

    # Notify linked parent
    profile_result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_student.id)
    )
    profile = profile_result.scalar_one_or_none()
    if profile and profile.parent_user_id:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": profile.parent_user_id,
            "payload": {
                "event": "child_grade_added",
                "subject": test.subject,
                "marks_obtained": score,
                "max_marks": test.total_marks,
            },
        })

    return submission


@router.get("/tests/{test_id}/review")
async def get_test_review(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Return all questions (with correct answers) and the student's submitted
    answers for a completed online test — for read-only review.
    """
    test_result = await db.execute(select(Test).where(Test.id == test_id))
    test = test_result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found.")

    sub_result = await db.execute(
        select(TestSubmission).where(
            TestSubmission.test_id == test_id,
            TestSubmission.student_id == current_student.id,
        )
    )
    submission = sub_result.scalar_one_or_none()
    if not submission:
        raise HTTPException(status_code=404, detail="No submission found for this test.")

    return {
        "test_id": test.id,
        "title": test.title,
        "subject": test.subject,
        "total_marks": test.total_marks,
        "score": submission.score,
        "questions": test.questions or [],
        "student_answers": submission.answers or {},
    }


@router.post("/profile/picture", status_code=status.HTTP_200_OK)
async def upload_profile_picture(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Upload or replace the student's profile picture."""
    file_bytes = await file.read()
    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "jpg"
    bucket = "mindforge-profiles"
    key = f"profiles/{current_student.id}/avatar.{ext}"
    await storage_service.upload_file(bucket, key, file_bytes)
    public_url = storage_service.get_public_url(bucket, key)

    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    profile.profile_pic_url = public_url

    user_result = await db.execute(select(User).where(User.id == current_student.id))
    student_user = user_result.scalar_one()
    student_user.profile_pic_url = public_url

    await db.commit()
    return {"profile_pic_url": public_url}


@router.put("/profile/mpin", status_code=status.HTTP_200_OK)
async def change_student_mpin(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Change the student's MPIN after verifying the current one."""
    from app.core.security import hash_mpin, verify_mpin
    import re

    current_mpin = payload.get("current_mpin", "")
    new_mpin = payload.get("new_mpin", "")

    if not verify_mpin(current_mpin, current_student.mpin_hash):
        raise HTTPException(status_code=400, detail="Current MPIN is incorrect.")

    if not re.fullmatch(r"\d{6}", new_mpin):
        raise HTTPException(status_code=422, detail="New MPIN must be exactly 6 digits.")

    result = await db.execute(select(User).where(User.id == current_student.id))
    student_user = result.scalar_one()
    student_user.mpin_hash = hash_mpin(new_mpin)
    await db.commit()
    return {"message": "MPIN updated successfully."}


# ─── Homework ──────────────────────────────────────────────────────────────────

@router.get("/homework", response_model=List[HomeworkResponse])
async def get_student_homework(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """List all homework assigned to the student's grade."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_student.id)
    )
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found")

    hw_result = await db.execute(
        select(Homework)
        .where(Homework.grade == profile.grade)
        .order_by(Homework.created_at.desc())
    )
    return hw_result.scalars().all()


# ─── Broadcasts ────────────────────────────────────────────────────────────────

@router.get("/broadcasts", response_model=List[BroadcastResponse])
async def get_student_broadcasts(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """List broadcast messages visible to this student (all + grade-specific)."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_student.id)
    )
    profile = result.scalar_one_or_none()
    grade = profile.grade if profile else None

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


# ─── Fees ──────────────────────────────────────────────────────────────────────

@router.get("/fees", response_model=StudentFeeSummary)
async def get_my_fees(
    academic_year: Optional[str] = Query(None, description="e.g. '2024-25'"),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get the current student's own fee summary."""
    import asyncio

    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    if not academic_year:
        academic_year = await get_current_academic_year_cached(db)

    structure_result = await db.execute(
        select(FeeStructure).where(
            FeeStructure.grade == profile.grade,
            FeeStructure.academic_year == academic_year,
        )
    )
    structure = structure_result.scalar_one_or_none()

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

    payments_result = await db.execute(
        select(FeePayment)
        .where(FeePayment.student_id == current_student.id)
        .order_by(FeePayment.paid_at.desc())
    )
    payments = payments_result.scalars().all()
    total_paid = sum(p.amount for p in payments)

    pi_result = await db.execute(select(PaymentInfo).order_by(PaymentInfo.slot))
    payment_options_raw = pi_result.scalars().all()

    # Resolve presigned QR URLs in parallel instead of sequentially
    async def _resolve_qr(pi):
        resp = PaymentInfoResponse.model_validate(pi)
        if pi.qr_code_url and not pi.qr_code_url.startswith("http"):
            parts = pi.qr_code_url.split("/", 1)
            if len(parts) == 2:
                try:
                    resp.qr_code_url = await storage_service.get_presigned_url(
                        parts[0], parts[1], expires_seconds=604800
                    )
                except Exception:
                    resp.qr_code_url = None
        return resp

    payment_options = list(await asyncio.gather(*[_resolve_qr(pi) for pi in payment_options_raw]))

    return StudentFeeSummary(
        student_id=current_student.id,
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
        payment_options=payment_options,
    )


# ─── Dashboard Summary ─────────────────────────────────────────────────────────

@router.get("/dashboard-summary")
async def get_student_dashboard_summary(
    date: Optional[str] = Query(None, description="YYYY-MM-DD, defaults to today"),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Single aggregated endpoint for the student dashboard.
    Returns timetable, broadcasts, homework, attendance summary,
    pending tests, offline tests, grades, and fees — in one round trip.
    """
    import asyncio
    from datetime import date as date_type, datetime, timezone
    from sqlalchemy import or_
    from app.models.attendance import AttendanceStatus

    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    today = date_type.fromisoformat(date) if date else date_type.today()

    # Timetable for today
    config = await get_timetable_config_cached(db)
    period_time_map: dict[int, tuple[str, str]] = {}
    if config and config.period_times:
        for pt in config.period_times:
            period_time_map[pt["period"]] = (pt["start"], pt["end"])

    TeacherAlias = aliased(User, name="teacher_alias")
    timetable_rows = (await db.execute(
        select(TimetableSlot, TeacherAlias.username)
        .outerjoin(TeacherAlias, TimetableSlot.teacher_id == TeacherAlias.id)
        .where(TimetableSlot.grade == profile.grade, TimetableSlot.slot_date == today)
        .order_by(TimetableSlot.period_number)
    )).all()
    timetable = [
        TimetableSlotWithTeacherResponse(
            id=s.id, grade=s.grade, slot_date=str(s.slot_date),
            period_number=s.period_number, subject=s.subject,
            teacher_id=s.teacher_id, teacher_username=tu,
            start_time=str(s.start_time)[:5] if s.start_time else (period_time_map.get(s.period_number, (None, None))[0]),
            end_time=str(s.end_time)[:5] if s.end_time else (period_time_map.get(s.period_number, (None, None))[1]),
            is_holiday=s.is_holiday, comment=s.comment,
        )
        for s, tu in timetable_rows
    ]

    # Broadcasts
    bc_rows = (await db.execute(
        select(Broadcast, User)
        .join(User, Broadcast.sender_id == User.id)
        .where(or_(
            Broadcast.target_type == "all",
            (Broadcast.target_type == "grade") & (Broadcast.target_grade == profile.grade),
        ))
        .order_by(Broadcast.created_at.desc())
    )).all()
    broadcasts = [
        BroadcastResponse(
            id=b.id, sender_id=b.sender_id, sender_username=u.username,
            title=b.title, message=b.message, target_type=b.target_type,
            target_grade=b.target_grade, created_at=b.created_at,
        )
        for b, u in bc_rows
    ]

    # Homework
    homework = (await db.execute(
        select(Homework).where(Homework.grade == profile.grade).order_by(Homework.created_at.desc())
    )).scalars().all()

    # Attendance summary
    att_row = (await db.execute(
        select(
            func.count(Attendance.id).label("total"),
            func.sum(
                func.cast(Attendance.status == AttendanceStatus.present,
                          type_=func.count(Attendance.id).type)
            ).label("present"),
        ).where(Attendance.student_id == current_student.id)
    )).one()
    att_total = att_row.total or 0
    att_present = att_row.present or 0
    attendance = AttendanceSummary(
        student_id=current_student.id,
        total_classes=att_total,
        present_count=att_present,
        absent_count=att_total - att_present,
        attendance_percentage=round((att_present / att_total * 100) if att_total > 0 else 0.0, 2),
    )

    # Tests
    now = datetime.now(timezone.utc)
    submitted_ids = {
        row[0] for row in (await db.execute(
            select(TestSubmission.test_id).where(TestSubmission.student_id == current_student.id)
        )).all()
    }
    pending_q = select(Test).where(
        Test.grade == profile.grade, Test.is_published == True,
        Test.test_type == "online", Test.expires_at > now,
    )
    if submitted_ids:
        pending_q = pending_q.where(Test.id.notin_(submitted_ids))
    pending_tests = (await db.execute(pending_q.order_by(Test.created_at.desc()))).scalars().all()
    offline_tests = (await db.execute(
        select(Test).where(
            Test.grade == profile.grade, Test.test_type == TestType.offline, Test.is_published == True
        ).order_by(Test.created_at.desc())
    )).scalars().all()

    # Grades
    grades = (await db.execute(
        select(Grade).where(Grade.student_id == current_student.id).order_by(Grade.created_at.desc())
    )).scalars().all()

    # Fees (skip presigned QR URL resolution — dashboard only needs amounts)
    academic_year = await get_current_academic_year_cached(db)
    structure = (await db.execute(
        select(FeeStructure).where(
            FeeStructure.grade == profile.grade, FeeStructure.academic_year == academic_year,
        )
    )).scalar_one_or_none()
    if structure:
        base_amount = structure.base_amount
        economics_fee = computer_fee = ai_fee = 0.0
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
    payments = (await db.execute(
        select(FeePayment).where(FeePayment.student_id == current_student.id).order_by(FeePayment.paid_at.desc())
    )).scalars().all()
    total_paid = sum(p.amount for p in payments)
    fees = StudentFeeSummary(
        student_id=current_student.id, academic_year=academic_year, grade=profile.grade,
        total_fee=total_fee, total_paid=total_paid, balance_due=max(0.0, total_fee - total_paid),
        base_amount=base_amount, economics_fee=economics_fee,
        computer_fee=computer_fee, ai_fee=ai_fee,
        payments=[FeePaymentResponse.model_validate(p) for p in payments],
        payment_options=[],  # Not needed on dashboard; use /fees for full detail
    )

    return {
        "timetable": timetable,
        "broadcasts": broadcasts,
        "homework": [HomeworkResponse.model_validate(h) for h in homework],
        "attendance": attendance,
        "pending_tests": [TestResponse.model_validate(t) for t in pending_tests],
        "offline_tests": [TestResponse.model_validate(t) for t in offline_tests],
        "grades": [GradeResponse.model_validate(g) for g in grades],
        "fees": fees,
    }
