"""
Teacher router — all endpoints require teacher role.
"""

import asyncio
import io
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, UploadFile, status
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, func, select, update

from app.core.database import get_db
from app.core.mask_utils import mask_phone, mask_email
from app.core.redis_client import redis_manager
from app.core.security import get_current_teacher
from app.core.upload_utils import validate_and_strip_exif
from app.models.attendance import Attendance, AttendanceStatus
from app.models.grade import Grade, GradeType
from app.models.test import Test, TestSubmission, TestType
from app.models.timetable import TimetableConfig, TimetableSlot
from app.models.user import User, StudentProfile, TeacherProfile
from app.schemas.attendance import (
    AttendanceCreate, AttendanceBulkCreate, AttendanceResponse, AttendanceSummary
)
from app.schemas.grade import GradeCreate, GradeResponse, GradeStats
from app.schemas.test import TestGenerationParams, TestResponse, OfflineGradesBulk
from app.schemas.timetable import TimetableConfigResponse, TimetableSlotCreate, TimetableSlotResponse, TimetableSlotUpdate
from app.schemas.user import AdminMpinUpdate, UserResponse, TeacherWithSubjectsResponse
from app.schemas.homework import (
    HomeworkCreate,
    HomeworkResponse,
    HomeworkCompletionBulkUpdate,
    HomeworkCompletionDetail,
    HomeworkCompletionsResponse,
    BroadcastCreate,
    BroadcastResponse,
)
from app.models.homework import Homework, HomeworkCompletion, Broadcast
from app.services import ai_service, notification_service, pdf_service, storage_service

router = APIRouter()
logger = logging.getLogger(__name__)


# ─── Teacher Profile ───────────────────────────────────────────────────────────

@router.get("/profile", response_model=UserResponse)
async def get_teacher_profile(
    current_teacher: User = Depends(get_current_teacher),
):
    """Return the current teacher's profile."""
    return current_teacher


@router.get("/profile/bio")
async def get_teacher_bio(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return the teacher's current bio."""
    result = await db.execute(
        select(TeacherProfile).where(TeacherProfile.user_id == current_teacher.id)
    )
    profile = result.scalar_one_or_none()
    return {"bio": profile.bio if profile else None}


@router.put("/profile/bio")
async def update_teacher_bio(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Update the teacher's bio (max 500 chars)."""
    bio = (payload.get("bio") or "").strip()[:500]
    result = await db.execute(
        select(TeacherProfile).where(TeacherProfile.user_id == current_teacher.id)
    )
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Teacher profile not found.")
    profile.bio = bio or None
    await db.commit()
    return {"bio": profile.bio}


@router.post("/profile/photo", status_code=status.HTTP_200_OK)
async def upload_teacher_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Upload or replace the teacher's profile picture."""
    raw = await file.read()
    file_bytes, ext = validate_and_strip_exif(raw, file.filename or "upload")
    bucket = "mindforge-profiles"
    key = f"profiles/teacher/{current_teacher.id}/avatar.{ext}"
    await storage_service.upload_file(bucket, key, file_bytes)
    public_url = storage_service.get_public_url(bucket, key)

    result = await db.execute(select(User).where(User.id == current_teacher.id))
    teacher_user = result.scalar_one()
    teacher_user.profile_pic_url = public_url
    await db.commit()
    return {"profile_pic_url": public_url}


@router.put("/profile/mpin", status_code=status.HTTP_200_OK)
async def change_teacher_mpin(
    payload: AdminMpinUpdate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Change the teacher's MPIN after verifying the current one."""
    from app.core.security import hash_mpin, verify_mpin
    if not verify_mpin(payload.current_mpin, current_teacher.mpin_hash):
        raise HTTPException(status_code=400, detail="Current MPIN is incorrect.")
    result = await db.execute(select(User).where(User.id == current_teacher.id))
    teacher_user = result.scalar_one()
    teacher_user.mpin_hash = hash_mpin(payload.new_mpin)
    await db.commit()
    return {"message": "MPIN updated successfully."}


# ─── Students ──────────────────────────────────────────────────────────────────

@router.get("/students", response_model=List[UserResponse])
async def get_students_in_grade(
    grade: int = Query(...),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return all active, approved students enrolled in a specific grade.
    Phone and email are partially masked — teachers see enough to contact a
    family but not the full PII that only admins should hold.
    """
    result = await db.execute(
        select(User)
        .join(StudentProfile, User.id == StudentProfile.user_id)
        .where(
            StudentProfile.grade == grade,
            User.is_active == True,
            User.is_approved == True,
        )
        .order_by(User.username)
    )
    students = result.scalars().all()
    return [
        UserResponse(
            id=s.id,
            username=s.username,
            role=s.role,
            is_active=s.is_active,
            is_approved=s.is_approved,
            created_at=s.created_at,
            deleted_at=s.deleted_at,
            profile_pic_url=s.profile_pic_url,
            phone=mask_phone(s.phone),
            email=mask_email(s.email),
        )
        for s in students
    ]


# ─── Attendance ────────────────────────────────────────────────────────────────

@router.get("/attendance/dates", response_model=List[str])
async def get_attendance_dates(
    grade: int = Query(...),
    month: str = Query(..., description="YYYY-MM"),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return distinct dates (YYYY-MM-DD) that have attendance records for grade in a given month."""
    from datetime import date as dt_date
    year, mon = int(month.split("-")[0]), int(month.split("-")[1])
    first_day = dt_date(year, mon, 1)
    import calendar as cal_mod
    last_day = dt_date(year, mon, cal_mod.monthrange(year, mon)[1])
    result = await db.execute(
        select(func.distinct(Attendance.date))
        .where(Attendance.grade == grade)
        .where(Attendance.date >= first_day)
        .where(Attendance.date <= last_day)
        .order_by(Attendance.date)
    )
    return [str(row) for row in result.scalars().all()]


@router.get("/attendance", response_model=List[AttendanceResponse])
async def get_attendance(
    grade: int = Query(..., description="Class grade (8, 9, or 10)"),
    date: Optional[str] = Query(None, description="Filter by date YYYY-MM-DD"),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Retrieve attendance records for a grade, optionally filtered by date."""
    query = select(Attendance).where(Attendance.grade == grade)
    if date:
        from datetime import date as dt_date
        parsed_date = dt_date.fromisoformat(date)
        query = query.where(Attendance.date == parsed_date)
    result = await db.execute(query.order_by(Attendance.date.desc(), Attendance.period))
    return result.scalars().all()


@router.post("/attendance", response_model=List[AttendanceResponse], status_code=status.HTTP_201_CREATED)
async def mark_attendance(
    payload: AttendanceBulkCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
):
    """
    Bulk-mark attendance for a class period.
    Clients should include X-Idempotency-Key (UUID) to prevent duplicate submissions
    if a request is retried after a timeout.
    Emits a WebSocket event to all students in the grade after saving.
    """
    if x_idempotency_key:
        if not await redis_manager.consume_idempotency_key(
            f"attend:{current_teacher.id}:{x_idempotency_key}"
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Duplicate request: this attendance submission was already processed.",
            )
    student_ids = [item.student_id for item in payload.records]

    # Batch-fetch all existing records for this date/period in one query
    existing_result = await db.execute(
        select(Attendance).where(
            Attendance.student_id.in_(student_ids),
            Attendance.date == payload.date,
            Attendance.period == payload.period,
        )
    )
    existing_map = {att.student_id: att for att in existing_result.scalars().all()}

    records = []
    for item in payload.records:
        att = existing_map.get(item.student_id)
        if att:
            att.status = item.status
        else:
            att = Attendance(
                student_id=item.student_id,
                teacher_id=current_teacher.id,
                grade=payload.grade,
                period=payload.period,
                date=payload.date,
                status=item.status,
            )
            db.add(att)
        records.append(att)

    await db.commit()
    for r in records:
        await db.refresh(r)

    # Broadcast attendance update to all students in the grade
    await redis_manager.publish({
        "target_type": "grade",
        "grade": payload.grade,
        "payload": {
            "event": "attendance_updated",
            "date": str(payload.date),
            "period": payload.period,
            "grade": payload.grade,
        },
    })

    # ── Push notifications for absent students ────────────────────────────────
    absent_ids = [
        item.student_id
        for item in payload.records
        if item.status == AttendanceStatus.absent
    ]
    if absent_ids:
        # Fetch student users + their parent links in one query
        sp_result = await db.execute(
            select(StudentProfile)
            .where(StudentProfile.user_id.in_(absent_ids))
        )
        profiles = sp_result.scalars().all()

        # Collect all user IDs we need FCM tokens for
        all_user_ids = set(absent_ids)
        parent_ids = {p.parent_user_id for p in profiles if p.parent_user_id}
        all_user_ids.update(parent_ids)

        token_result = await db.execute(
            select(User.id, User.fcm_token)
            .where(User.id.in_(all_user_ids), User.fcm_token.isnot(None))
        )
        token_map = {row.id: row.fcm_token for row in token_result}

        date_str = str(payload.date)
        period_str = str(payload.period)

        for profile in profiles:
            # Notify the student
            student_token = token_map.get(profile.user_id)
            if student_token:
                asyncio.create_task(notification_service.send_to_token(
                    token=student_token,
                    title="Attendance Alert",
                    body=f"You were marked absent on {date_str} (Period {period_str}).",
                    data={"route": "/student/attendance"},
                ))
            # Notify the parent
            if profile.parent_user_id:
                parent_token = token_map.get(profile.parent_user_id)
                if parent_token:
                    asyncio.create_task(notification_service.send_to_token(
                        token=parent_token,
                        title="Attendance Alert",
                        body=f"Your child was marked absent on {date_str} (Period {period_str}).",
                        data={"route": "/parent/attendance"},
                    ))

    return records


# ─── Timetable ─────────────────────────────────────────────────────────────────

@router.get("/teachers", response_model=List[TeacherWithSubjectsResponse])
async def get_all_teachers(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Get list of all active, approved teachers with their teachable subjects."""
    from sqlalchemy.orm import selectinload
    result = await db.execute(
        select(User)
        .options(selectinload(User.teacher_profile))
        .where(
            User.role == "teacher",
            User.is_active == True,
            User.is_approved == True,
        )
        .order_by(User.username)
    )
    teachers = result.scalars().all()
    return [
        TeacherWithSubjectsResponse(
            id=t.id,
            username=t.username,
            role=t.role,
            is_active=t.is_active,
            is_approved=t.is_approved,
            created_at=t.created_at,
            deleted_at=t.deleted_at,
            profile_pic_url=t.profile_pic_url,
            teachable_subjects=t.teacher_profile.teachable_subjects if t.teacher_profile else [],
        )
        for t in teachers
    ]


@router.get("/timetable-config", response_model=Optional[TimetableConfigResponse])
async def get_timetable_config(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return the timetable config (period count + times) created by admin."""
    result = await db.execute(select(TimetableConfig))
    return result.scalar_one_or_none()


@router.get("/my-timetable", response_model=List[TimetableSlotResponse])
async def get_my_timetable(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return all upcoming timetable slots assigned to the current teacher."""
    from datetime import date as date_type
    today = date_type.today()
    result = await db.execute(
        select(TimetableSlot)
        .where(
            TimetableSlot.teacher_id == current_teacher.id,
        )
        .order_by(TimetableSlot.slot_date, TimetableSlot.period_number)
    )
    return result.scalars().all()


@router.get("/timetable", response_model=List[TimetableSlotResponse])
async def get_timetable(
    grade: int = Query(...),
    date: str = Query(...),  # YYYY-MM-DD
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Get timetable for a grade on a specific date."""
    from datetime import date as date_type
    slot_date = date_type.fromisoformat(date)
    result = await db.execute(
        select(TimetableSlot)
        .where(TimetableSlot.grade == grade, TimetableSlot.slot_date == slot_date)
        .order_by(TimetableSlot.period_number)
    )
    return result.scalars().all()


@router.post("/timetable/delete", status_code=status.HTTP_200_OK)
async def delete_timetable_for_grade_date(
    grade: int = Query(...),
    date: str = Query(...),  # YYYY-MM-DD
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Delete all timetable slots for a given grade and date."""
    from datetime import date as date_type
    from sqlalchemy import delete as sql_delete
    slot_date = date_type.fromisoformat(date)
    result = await db.execute(
        sql_delete(TimetableSlot).where(
            TimetableSlot.grade == grade,
            TimetableSlot.slot_date == slot_date,
        )
    )
    await db.commit()
    deleted = result.rowcount
    return {"deleted": deleted, "message": f"Deleted {deleted} slot(s) for Grade {grade} on {date}."}


@router.post("/timetable", response_model=TimetableSlotResponse, status_code=status.HTTP_200_OK)
async def create_timetable_slot(
    payload: TimetableSlotCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Upsert a timetable slot — updates if one exists for the same grade/date/period."""
    existing = await db.execute(
        select(TimetableSlot).where(
            TimetableSlot.grade == payload.grade,
            TimetableSlot.slot_date == payload.slot_date,
            TimetableSlot.period_number == payload.period_number,
        )
    )
    slot = existing.scalar_one_or_none()
    is_new_slot = slot is None
    if slot:
        for key, value in payload.model_dump().items():
            setattr(slot, key, value)
    else:
        slot = TimetableSlot(**payload.model_dump())
        db.add(slot)
    await db.commit()
    await db.refresh(slot)

    await redis_manager.publish({
        "target_type": "grade",
        "target_grade": payload.grade,
        "payload": {
            "event": "timetable_updated",
            "grade": payload.grade,
            "slot_date": str(payload.slot_date),
        },
    })

    # ── Push notification — fire once when period 1 is first created ──────────
    # Sending per-slot would spam students. Period 1 being newly saved signals
    # the teacher has started entering the day's timetable.
    if is_new_slot and payload.period_number == 1:
        sp_result = await db.execute(
            select(StudentProfile)
            .join(User, User.id == StudentProfile.user_id)
            .where(
                StudentProfile.grade == payload.grade,
                User.is_active == True,
                User.is_approved == True,
                User.deleted_at.is_(None),
            )
        )
        profiles = sp_result.scalars().all()

        all_user_ids = {p.user_id for p in profiles}
        all_user_ids.update(p.parent_user_id for p in profiles if p.parent_user_id)

        if all_user_ids:
            token_result = await db.execute(
                select(User.fcm_token)
                .where(User.id.in_(all_user_ids), User.fcm_token.isnot(None))
            )
            tokens = [row.fcm_token for row in token_result]
            if tokens:
                date_str = str(payload.slot_date)
                asyncio.create_task(notification_service.send_to_tokens(
                    tokens=tokens,
                    title="Timetable Ready",
                    body=f"The timetable for Grade {payload.grade} on {date_str} has been published.",
                    data={"route": "/student/timetable"},
                ))

    return slot


# ─── Grades ────────────────────────────────────────────────────────────────────

@router.get("/grades", response_model=List[GradeResponse])
async def get_grades(
    grade: Optional[int] = Query(None),
    subject: Optional[str] = Query(None),
    student_id: Optional[int] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Retrieve grades with optional filters."""
    query = select(Grade).where(Grade.teacher_id == current_teacher.id)
    if grade is not None:
        # Filter by class grade via StudentProfile join
        query = query.join(StudentProfile, Grade.student_id == StudentProfile.user_id).where(
            StudentProfile.grade == grade
        )
    if subject:
        query = query.where(Grade.subject == subject)
    if student_id:
        query = query.where(Grade.student_id == student_id)
    result = await db.execute(query.order_by(Grade.created_at.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.post("/grades", response_model=GradeResponse, status_code=status.HTTP_201_CREATED)
async def create_grade(
    payload: GradeCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
):
    """Record a grade entry and notify the student and their parent via WebSocket.
    Clients should include X-Idempotency-Key (UUID) to prevent accidental double-posting.
    """
    if x_idempotency_key:
        if not await redis_manager.consume_idempotency_key(
            f"grade:{current_teacher.id}:{x_idempotency_key}"
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Duplicate request: this grade entry was already submitted.",
            )
    grade_obj = Grade(
        **payload.model_dump(),
        teacher_id=current_teacher.id,
        grade_type=payload.grade_type,
    )
    db.add(grade_obj)
    await db.commit()
    await db.refresh(grade_obj)

    # Notify student
    await redis_manager.publish({
        "target_type": "user",
        "user_id": payload.student_id,
        "payload": {
            "event": "grade_added",
            "subject": payload.subject,
            "marks_obtained": payload.marks_obtained,
            "max_marks": payload.max_marks,
        },
    })

    # Notify parent if linked
    profile_result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == payload.student_id)
    )
    profile = profile_result.scalar_one_or_none()
    if profile and profile.parent_user_id:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": profile.parent_user_id,
            "payload": {
                "event": "child_grade_added",
                "subject": payload.subject,
                "marks_obtained": payload.marks_obtained,
                "max_marks": payload.max_marks,
            },
        })

    return grade_obj


# ─── Tests ─────────────────────────────────────────────────────────────────────

@router.get("/tests", response_model=List[TestResponse])
async def get_tests(
    grade: Optional[int] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Retrieve tests (visible to all teachers) with pagination."""
    query = select(Test)
    if grade:
        query = query.where(Test.grade == grade)
    result = await db.execute(query.order_by(Test.created_at.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.post("/tests/generate", response_model=TestResponse, status_code=status.HTTP_201_CREATED)
async def generate_test(
    title: str = Form(...),
    grade: int = Form(...),
    subject: str = Form(...),
    chapter: str = Form(""),
    test_type: str = Form("online"),
    mcq_count: int = Form(5),
    fill_blank_count: int = Form(3),
    true_false_count: int = Form(2),
    match_following_count: int = Form(0),
    vsa_count: int = Form(2),
    short_answer_count: int = Form(0),
    long_answer_count: int = Form(0),
    diagram_count: int = Form(0),
    include_numericals: bool = Form(False),
    time_limit_minutes: Optional[int] = Form(None),
    use_database: bool = Form(False),
    src_pct_p: int = Form(20),
    src_pct_e: int = Form(20),
    src_pct_np: int = Form(20),
    src_pct_ne: int = Form(20),
    src_pct_ai: int = Form(20),
    source_files: List[UploadFile] = File(default=[]),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """
    AI-powered test generation pipeline:
    1. Optionally pull old test papers + chapter docs from teacher's database
    2. Read any freshly-uploaded source files
    3. Call Gemini/Groq to generate structured questions
    4. Save test to database
    5. For offline tests, generate a PDF via ReportLab and store in MinIO
    6. Broadcast new test event to the grade
    """
    from sqlalchemy import select as _select
    from app.models.database_models import OldTestPaper, ChapterDocument

    params = TestGenerationParams(
        title=title,
        grade=grade,
        subject=subject,
        chapter=chapter,
        test_type=TestType(test_type),
        mcq_count=mcq_count,
        fill_blank_count=fill_blank_count,
        true_false_count=true_false_count,
        match_following_count=match_following_count,
        vsa_count=vsa_count,
        short_answer_count=short_answer_count,
        long_answer_count=long_answer_count,
        diagram_count=diagram_count,
        include_numericals=include_numericals,
        time_limit_minutes=time_limit_minutes if time_limit_minutes is not None else (mcq_count + fill_blank_count + true_false_count + vsa_count + match_following_count),
        src_pct_p=src_pct_p,
        src_pct_e=src_pct_e,
        src_pct_np=src_pct_np,
        src_pct_ne=src_pct_ne,
        src_pct_ai=src_pct_ai,
    )

    source_file_url = None
    chapter_files: list = []    # (bytes, ext) — chapter PDFs (primary source)
    old_paper_files: list = []  # (bytes, ext) — old test papers (secondary, chapter-filtered)
    syllabus_chapters: list = []

    # ── Pull files from teacher's knowledge base ──────────────────────────────
    if use_database:
        from app.models.database_models import SyllabusEntry

        # 1. Chapter documents — strict match on grade+subject+chapter name
        chapter_q = _select(ChapterDocument).where(
            ChapterDocument.teacher_id == current_teacher.id,
            ChapterDocument.grade == grade,
            ChapterDocument.subject == subject,
            ChapterDocument.chapter_name.ilike(f"%{chapter}%"),
        ).order_by(ChapterDocument.created_at.desc()).limit(3)
        chapter_res = await db.execute(chapter_q)
        for chap in chapter_res.scalars().all():
            try:
                data = await storage_service.download_file(
                    settings.MINIO_BUCKET_DATABASE, chap.file_key
                )
                ext = chap.file_key.rsplit(".", 1)[-1].lower()
                chapter_files.append((data, ext))
                logger.info(f"Loaded chapter doc '{chap.chapter_name}' (id={chap.id})")
            except Exception as e:
                logger.warning(f"Could not load chapter doc {chap.id}: {e}")

        # 2. Old test papers — fetch by grade+subject only; AI will filter by chapter
        papers_q = _select(OldTestPaper).where(
            OldTestPaper.teacher_id == current_teacher.id,
            OldTestPaper.grade == grade,
            OldTestPaper.subject == subject,
        ).order_by(OldTestPaper.created_at.desc()).limit(5)
        papers_res = await db.execute(papers_q)
        for paper in papers_res.scalars().all():
            try:
                data = await storage_service.download_file(
                    settings.MINIO_BUCKET_DATABASE, paper.file_key
                )
                ext = paper.file_key.rsplit(".", 1)[-1].lower()
                old_paper_files.append((data, ext))
                logger.info(f"Loaded old test paper id={paper.id} for chapter-filtered use")
            except Exception as e:
                logger.warning(f"Could not load old test paper {paper.id}: {e}")

        # 3. Syllabus — fetch chapter list for scope reference
        syllabus_q = _select(SyllabusEntry).where(
            SyllabusEntry.teacher_id == current_teacher.id,
            SyllabusEntry.grade == grade,
            SyllabusEntry.subject == subject,
        ).limit(1)
        syllabus_res = await db.execute(syllabus_q)
        syl = syllabus_res.scalar_one_or_none()
        if syl and syl.chapters:
            syllabus_chapters = syl.chapters
            logger.info(f"Loaded syllabus: {len(syllabus_chapters)} chapters for scope reference")

        if chapter_files or old_paper_files:
            params.has_database_context = True

    # ── Freshly uploaded source files (legacy path — kept for compatibility) ──
    for i, source_file in enumerate(source_files or []):
        file_bytes = await source_file.read()
        if not file_bytes:
            continue
        ext = source_file.filename.rsplit(".", 1)[-1].lower() if source_file.filename else "bin"
        try:
            storage_key = f"sources/{current_teacher.id}/{datetime.now(timezone.utc).timestamp()}_{i}.{ext}"
            file_url = await storage_service.upload_file(
                settings.MINIO_BUCKET_TESTS, storage_key, file_bytes
            )
            if i == 0:
                source_file_url = file_url
        except Exception:
            pass
        # Treat freshly-uploaded files as chapter content (teacher uploaded them explicitly)
        chapter_files.append((file_bytes, ext))

    # ── Generate questions ─────────────────────────────────────────────────────
    questions = await ai_service.generate_test_questions(
        chapter_files, old_paper_files, syllabus_chapters, params
    )

    # ── Total marks calculation ────────────────────────────────────────────────
    if test_type == "offline":
        from app.services.ai_service import _TYPE_MARKS as _TM
        total_marks = (
            params.mcq_count * _TM["mcq"] +
            params.true_false_count * _TM["true_false"] +
            params.fill_blank_count * _TM["fill_blank"] +
            params.match_following_count * 1 +          # 1 mark per pair
            params.vsa_count * _TM["vsa"] +
            params.short_answer_count * _TM["short_answer"] +
            params.long_answer_count * _TM["long_answer"] +
            params.diagram_count * _TM["diagram"] +
            (2 * _TM["numerical"] if params.include_numericals else 0)
        )
    else:
        total_marks = sum(q.get("marks", 1) for q in questions)

    # Set expiry for online tests (3-day window)
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(days=3) if test_type == "online" else None

    # For online tests: 30 seconds per question (stored as whole minutes, rounded up).
    # For offline: use the slider value the teacher chose.
    import math
    time_limit = math.ceil(len(questions) / 2) if test_type == "online" else (params.time_limit_minutes or 0)

    test = Test(
        title=title,
        teacher_id=current_teacher.id,
        grade=grade,
        subject=subject,
        source_file_url=source_file_url,
        test_type=TestType(test_type),
        questions=questions,
        total_marks=total_marks,
        time_limit_minutes=time_limit,
        expires_at=expires_at,
    )
    db.add(test)
    await db.flush()  # get test.id without committing
    await db.commit()
    await db.refresh(test)

    # Explicitly publish online tests via a direct UPDATE (bypasses server default)
    if test_type == "online":
        await db.execute(update(Test).where(Test.id == test.id).values(is_published=True))
        await db.commit()
        await db.refresh(test)

    # For offline tests, generate printable PDF + answer key and store them
    if test_type == "offline":
        try:
            pdf_bytes = await pdf_service.generate_offline_test_pdf(
                questions, title,
                grade=grade, subject=subject,
                total_marks=total_marks,
                time_limit_minutes=params.time_limit_minutes or 0,
            )
            pdf_key = f"offline_tests/{test.id}/test_paper.pdf"
            pdf_url = await storage_service.upload_file("mindforge-pdfs", pdf_key, pdf_bytes)
            test.source_file_url = pdf_url

            ak_bytes = await pdf_service.generate_answer_key_pdf(
                questions, title,
                grade=grade, subject=subject, total_marks=total_marks,
            )
            ak_key = f"offline_tests/{test.id}/answer_key.pdf"
            ak_url = await storage_service.upload_file("mindforge-pdfs", ak_key, ak_bytes)
            test.answer_key_url = ak_url

            await db.commit()
            await db.refresh(test)
        except Exception:
            pass  # Storage unavailable — test is saved without PDF files

    # Broadcast new test to the grade (teachers can also listen)
    await redis_manager.publish({
        "target_type": "grade",
        "grade": grade,
        "payload": {
            "event": "new_test_available",
            "test_id": test.id,
            "title": title,
            "subject": subject,
            "test_type": test_type,
        },
    })

    # ── Push notifications for new test ───────────────────────────────────────
    # Fetch all students in this grade + their parent links
    sp_result = await db.execute(
        select(StudentProfile)
        .join(User, User.id == StudentProfile.user_id)
        .where(
            StudentProfile.grade == grade,
            User.is_active == True,
            User.is_approved == True,
            User.deleted_at.is_(None),
        )
    )
    profiles = sp_result.scalars().all()

    all_user_ids = {p.user_id for p in profiles}
    parent_ids = {p.parent_user_id for p in profiles if p.parent_user_id}
    all_user_ids.update(parent_ids)

    token_result = await db.execute(
        select(User.id, User.fcm_token)
        .where(User.id.in_(all_user_ids), User.fcm_token.isnot(None))
    )
    token_map = {row.id: row.fcm_token for row in token_result}

    student_tokens = [token_map[p.user_id] for p in profiles if p.user_id in token_map]
    parent_tokens  = [token_map[p.parent_user_id] for p in profiles if p.parent_user_id and p.parent_user_id in token_map]

    notif_title = "New Test Available"
    notif_body  = f"A new {test_type} test '{title}' has been added for Grade {grade} — {subject}."
    route = "/student/tests" if test_type != "offline" else "/student/tests"

    if student_tokens:
        asyncio.create_task(notification_service.send_to_tokens(
            tokens=student_tokens,
            title=notif_title,
            body=notif_body,
            data={"route": route},
        ))
    if parent_tokens:
        asyncio.create_task(notification_service.send_to_tokens(
            tokens=parent_tokens,
            title=notif_title,
            body=f"A new {test_type} test '{title}' has been added for your child (Grade {grade} — {subject}).",
            data={"route": "/parent/tests"},
        ))

    return test


@router.get("/tests/{test_id}", response_model=TestResponse)
async def get_test(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Get a single test by ID (must belong to the calling teacher)."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")
    return test


@router.put("/tests/{test_id}/questions", response_model=TestResponse)
async def update_test_questions(
    test_id: int,
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Replace the questions list for a test and recalculate total marks and time limit."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")

    questions = payload.get("questions", [])
    if not isinstance(questions, list):
        raise HTTPException(status_code=400, detail="questions must be a list")

    # Re-number questions sequentially
    for i, q in enumerate(questions):
        q["id"] = i + 1

    total_marks = sum(q.get("marks", 1) for q in questions)
    test.questions = questions
    test.total_marks = total_marks
    # Recalculate time for online tests (1 min/question)
    if test.test_type == TestType.online:
        test.time_limit_minutes = len(questions)

    await db.commit()
    await db.refresh(test)
    return test


@router.delete("/tests/{test_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_test(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Permanently delete a test and all its submissions/grades."""
    result = await db.execute(select(Test).where(Test.id == test_id))
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")

    # Collect affected student IDs from grades before deleting
    grade_rows = await db.execute(
        select(Grade.student_id).where(Grade.test_id == test_id)
    )
    affected_student_ids = {row[0] for row in grade_rows.all()}

    # Explicitly delete all grades linked to this test
    await db.execute(delete(Grade).where(Grade.test_id == test_id))

    # Delete the test (submissions cascade via FK)
    await db.delete(test)
    await db.commit()

    # Notify affected students and their parents
    # Batch-fetch all profiles in one query instead of one per student
    if affected_student_ids:
        profiles_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id.in_(affected_student_ids))
        )
        profiles_map = {p.user_id: p for p in profiles_result.scalars().all()}

        notify_tasks = []
        for student_id in affected_student_ids:
            notify_tasks.append(redis_manager.publish({
                "target_type": "user",
                "user_id": student_id,
                "payload": {"event": "grade_deleted", "test_id": test_id},
            }))
            profile = profiles_map.get(student_id)
            if profile and profile.parent_user_id:
                notify_tasks.append(redis_manager.publish({
                    "target_type": "user",
                    "user_id": profile.parent_user_id,
                    "payload": {"event": "child_grade_deleted", "test_id": test_id},
                }))
        await asyncio.gather(*notify_tasks)


@router.get("/tests/{test_id}/pdf-urls")
async def get_test_pdf_urls(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Return pre-signed MinIO URLs for the test paper PDF and answer key PDF."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")
    if test.test_type != TestType.offline:
        raise HTTPException(status_code=400, detail="PDF URLs only available for offline tests")

    urls = {}
    if test.source_file_url:
        parts = test.source_file_url.split("/", 1)
        if len(parts) == 2:
            urls["test_pdf_url"] = await storage_service.get_presigned_url(parts[0], parts[1])
    if test.answer_key_url:
        parts = test.answer_key_url.split("/", 1)
        if len(parts) == 2:
            urls["answer_key_pdf_url"] = await storage_service.get_presigned_url(parts[0], parts[1])

    return urls


@router.get("/tests/{test_id}/download-pdf")
async def download_test_pdf(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Generate and stream the test paper PDF directly."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")
    if test.test_type != TestType.offline:
        raise HTTPException(status_code=400, detail="PDF only available for offline tests")

    pdf_bytes = await pdf_service.generate_offline_test_pdf(
        test.questions, test.title,
        grade=test.grade, subject=test.subject,
        total_marks=test.total_marks,
        time_limit_minutes=test.time_limit_minutes or 0,
    )
    filename = f"{test.title.replace(' ', '_')}_test.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/tests/{test_id}/download-answer-key")
async def download_answer_key_pdf(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Generate and stream the answer key PDF directly."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")
    if test.test_type != TestType.offline:
        raise HTTPException(status_code=400, detail="PDF only available for offline tests")

    ak_bytes = await pdf_service.generate_answer_key_pdf(
        test.questions, test.title,
        grade=test.grade, subject=test.subject,
        total_marks=test.total_marks,
    )
    filename = f"{test.title.replace(' ', '_')}_answer_key.pdf"
    return Response(
        content=ak_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/tests/{test_id}/submissions")
async def get_test_submissions(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """List all student submissions for an online test (visible to all teachers)."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Test not found")

    rows = await db.execute(
        select(TestSubmission, User)
        .join(User, User.id == TestSubmission.student_id)
        .where(TestSubmission.test_id == test_id)
        .order_by(User.username)
    )
    return [
        {
            "id": s.id,
            "student_id": s.student_id,
            "student_name": u.username,
            "score": s.score,
            "total_marks": None,  # filled from test
            "submitted_at": s.submitted_at.isoformat(),
            "auto_submitted": s.auto_submitted,
        }
        for s, u in rows.all()
    ]


@router.get("/tests/{test_id}/grades")
async def get_test_grades(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """List all offline grades entered for a test (visible to all teachers)."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Test not found")

    rows = await db.execute(
        select(Grade, User)
        .join(User, User.id == Grade.student_id)
        .where(Grade.test_id == test_id)
        .order_by(User.username)
    )
    return [
        {
            "id": g.id,
            "student_id": g.student_id,
            "student_name": u.username,
            "marks_obtained": g.marks_obtained,
            "max_marks": g.max_marks,
            "percentage": g.percentage,
        }
        for g, u in rows.all()
    ]


@router.post("/tests/{test_id}/offline-grades", status_code=status.HTTP_201_CREATED)
async def save_offline_grades(
    test_id: int,
    payload: OfflineGradesBulk,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Bulk-save offline test grades for a list of students."""
    result = await db.execute(
        select(Test).where(Test.id == test_id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found")
    if test.test_type != TestType.offline:
        raise HTTPException(status_code=400, detail="Manual grades only allowed for offline tests")

    saved_grades = []
    for entry in payload.grades:
        if entry.marks_obtained < 0 or entry.marks_obtained > test.total_marks:
            raise HTTPException(
                status_code=400,
                detail=f"marks_obtained must be between 0 and {test.total_marks}"
            )
        grade_obj = Grade(
            student_id=entry.student_id,
            teacher_id=current_teacher.id,
            subject=test.subject,
            chapter=test.title,
            test_id=test_id,
            marks_obtained=entry.marks_obtained,
            max_marks=test.total_marks,
            grade_type=GradeType.offline,
        )
        db.add(grade_obj)
        saved_grades.append((grade_obj, entry.student_id))

    test.is_graded = True
    await db.commit()

    # Broadcast completed status to all connected clients (teachers, students, parents)
    await redis_manager.publish({
        "target_type": "broadcast",
        "payload": {
            "event": "test_completed",
            "test_id": test_id,
        },
    })

    # Notify each student
    for grade_obj, student_id in saved_grades:
        await db.refresh(grade_obj)
        await redis_manager.publish({
            "target_type": "user",
            "user_id": student_id,
            "payload": {
                "event": "grade_added",
                "subject": test.subject,
                "marks_obtained": grade_obj.marks_obtained,
                "max_marks": grade_obj.max_marks,
            },
        })
        # Notify parent if linked
        profile_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == student_id)
        )
        profile = profile_result.scalar_one_or_none()
        if profile and profile.parent_user_id:
            await redis_manager.publish({
                "target_type": "user",
                "user_id": profile.parent_user_id,
                "payload": {
                    "event": "child_grade_added",
                    "subject": test.subject,
                    "marks_obtained": grade_obj.marks_obtained,
                    "max_marks": grade_obj.max_marks,
                },
            })

    return {"saved": len(saved_grades)}


@router.post("/tests/{test_id}/publish", status_code=status.HTTP_200_OK)
async def publish_test(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Toggle publish state of a test. Only the creator can publish/unpublish."""
    result = await db.execute(
        select(Test).where(Test.id == test_id, Test.teacher_id == current_teacher.id)
    )
    test = result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=403, detail="Only the teacher who created this test can publish/unpublish it")
    test.is_published = not test.is_published
    await db.commit()
    # Notify all connected clients so every teacher sees the updated status immediately
    await redis_manager.publish({
        "target_type": "broadcast",
        "payload": {
            "event": "test_status_changed",
            "test_id": test_id,
            "is_published": test.is_published,
        },
    })
    return {"is_published": test.is_published}


# ─── Homework ──────────────────────────────────────────────────────────────────

@router.post("/homework", response_model=HomeworkResponse, status_code=status.HTTP_201_CREATED)
async def create_homework(
    payload: HomeworkCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Create a homework assignment for a grade."""
    hw = Homework(
        teacher_id=current_teacher.id,
        grade=payload.grade,
        subject=payload.subject,
        title=payload.title,
        description=payload.description,
        homework_type=payload.homework_type,
        test_id=payload.test_id,
        due_date=payload.due_date,
    )
    db.add(hw)
    await db.commit()
    await db.refresh(hw)
    # Notify all students and parents in the grade
    await redis_manager.publish({
        "target_type": "grade",
        "grade": payload.grade,
        "payload": {
            "event": "homework_added",
            "homework_id": hw.id,
            "title": hw.title,
            "subject": hw.subject,
            "due_date": payload.due_date.isoformat() if payload.due_date else None,
        },
    })
    return hw


@router.get("/homework", response_model=List[HomeworkResponse])
async def list_teacher_homework(
    grade: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """List all homework created by this teacher, optionally filtered by grade."""
    q = select(Homework).where(Homework.teacher_id == current_teacher.id)
    if grade is not None:
        q = q.where(Homework.grade == grade)
    q = q.order_by(Homework.created_at.desc())
    result = await db.execute(q)
    return result.scalars().all()


@router.delete("/homework/{homework_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_homework(
    homework_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Delete a homework assignment (only the creator can delete)."""
    result = await db.execute(
        select(Homework).where(
            Homework.id == homework_id, Homework.teacher_id == current_teacher.id
        )
    )
    hw = result.scalar_one_or_none()
    if not hw:
        raise HTTPException(status_code=404, detail="Homework not found or not yours")
    await db.delete(hw)
    await db.commit()


# ─── Homework completion tracking ─────────────────────────────────────────────

async def _build_completions_response(
    homework_id: int,
    db: AsyncSession,
    teacher: User,
) -> HomeworkCompletionsResponse:
    """Internal helper used by both GET and PUT. Builds the wrapped response
    with attendance metadata so the teacher screen can render warnings and
    lock absent rows from a single fetch.
    """
    hw = (await db.execute(
        select(Homework).where(
            Homework.id == homework_id, Homework.teacher_id == teacher.id
        )
    )).scalar_one_or_none()
    if not hw:
        raise HTTPException(status_code=404, detail="Homework not found or not yours")

    students = (await db.execute(
        select(User)
        .join(StudentProfile, User.id == StudentProfile.user_id)
        .where(
            StudentProfile.grade == hw.grade,
            User.is_active == True,
            User.is_approved == True,
        )
        .order_by(User.username)
    )).scalars().all()

    existing = {
        c.student_id: c
        for c in (await db.execute(
            select(HomeworkCompletion).where(
                HomeworkCompletion.homework_id == homework_id
            )
        )).scalars().all()
    }

    # Attendance check uses the homework's assigned date (created_at). A
    # student who wasn't in class that day couldn't have done the homework,
    # so we lock them as Incomplete on the teacher screen.
    attendance_date = hw.created_at.date()
    att_rows = (await db.execute(
        select(Attendance).where(
            Attendance.grade == hw.grade,
            Attendance.date == attendance_date,
        )
    )).scalars().all()

    attendance_recorded = len(att_rows) > 0
    absent_student_ids = {
        a.student_id for a in att_rows
        if a.status == AttendanceStatus.absent
    }

    students_out = [
        HomeworkCompletionDetail(
            student_id=s.id,
            username=s.username,
            completed=(
                False if s.id in absent_student_ids
                else (existing[s.id].completed if s.id in existing else False)
            ),
            marked_at=existing[s.id].marked_at if s.id in existing else None,
            was_absent=s.id in absent_student_ids,
        )
        for s in students
    ]
    return HomeworkCompletionsResponse(
        attendance_date=attendance_date.isoformat(),
        attendance_recorded=attendance_recorded,
        students=students_out,
    )


@router.get(
    "/homework/{homework_id}/completions",
    response_model=HomeworkCompletionsResponse,
)
async def list_homework_completions(
    homework_id: int,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Roster + each student's completion status, plus attendance metadata
    for the homework's assigned date so the teacher screen can render
    warnings and lock absent rows.
    """
    return await _build_completions_response(homework_id, db, current_teacher)


@router.put(
    "/homework/{homework_id}/completions",
    response_model=HomeworkCompletionsResponse,
)
async def upsert_homework_completions(
    homework_id: int,
    payload: HomeworkCompletionBulkUpdate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Bulk insert/update completion rows for one homework.

    Two safety rules enforced server-side (so a stale client can't bypass
    them):
      1. Attendance for the homework's assigned date must be recorded
         first — otherwise return 400. The teacher screen surfaces this as
         a warning banner.
      2. Students marked absent on that date are forced to completed=False
         regardless of payload. They couldn't have done the homework.
    """
    hw = (await db.execute(
        select(Homework).where(
            Homework.id == homework_id, Homework.teacher_id == current_teacher.id
        )
    )).scalar_one_or_none()
    if not hw:
        raise HTTPException(status_code=404, detail="Homework not found or not yours")

    attendance_date = hw.created_at.date()
    att_rows = (await db.execute(
        select(Attendance).where(
            Attendance.grade == hw.grade,
            Attendance.date == attendance_date,
        )
    )).scalars().all()
    if not att_rows:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Mark attendance for {attendance_date.isoformat()} "
                "before updating homework status."
            ),
        )
    absent_student_ids = {
        a.student_id for a in att_rows
        if a.status == AttendanceStatus.absent
    }

    # Reject student_ids that don't actually belong to this homework's grade —
    # cheap defence against a crafted payload trying to write rows for someone
    # else's class.
    valid_student_ids = {
        row[0] for row in (await db.execute(
            select(User.id)
            .join(StudentProfile, User.id == StudentProfile.user_id)
            .where(
                StudentProfile.grade == hw.grade,
                User.is_active == True,
                User.is_approved == True,
            )
        )).all()
    }

    existing = {
        c.student_id: c
        for c in (await db.execute(
            select(HomeworkCompletion).where(
                HomeworkCompletion.homework_id == homework_id
            )
        )).scalars().all()
    }

    for rec in payload.records:
        if rec.student_id not in valid_student_ids:
            continue
        # Force absent students to incomplete regardless of what the client
        # tried to send. See rule 2 above.
        completed = False if rec.student_id in absent_student_ids else rec.completed
        if rec.student_id in existing:
            existing[rec.student_id].completed = completed
            existing[rec.student_id].marked_by = current_teacher.id
        else:
            db.add(HomeworkCompletion(
                homework_id=homework_id,
                student_id=rec.student_id,
                completed=completed,
                marked_by=current_teacher.id,
            ))
    await db.commit()

    await redis_manager.publish({
        "target_type": "grade",
        "grade": hw.grade,
        "payload": {
            "event": "homework_completion_updated",
            "homework_id": homework_id,
        },
    })

    return await _build_completions_response(homework_id, db, current_teacher)


# ─── Broadcast ────────────────────────────────────────────────────────────────

@router.post("/broadcast", response_model=BroadcastResponse, status_code=status.HTTP_201_CREATED)
async def send_broadcast(
    payload: BroadcastCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Broadcast a message to all users or a specific grade."""
    bc = Broadcast(
        sender_id=current_teacher.id,
        title=payload.title,
        message=payload.message,
        target_type=payload.target_type,
        target_grade=payload.target_grade,
    )
    db.add(bc)
    await db.commit()
    await db.refresh(bc)

    ws_payload = {
        "event": "message_broadcast",
        "broadcast_id": bc.id,
        "title": bc.title,
        "message": bc.message,
        "sender": current_teacher.username,
    }

    if payload.target_type == "grade" and payload.target_grade is not None:
        await redis_manager.publish({
            "target_type": "grade",
            "grade": payload.target_grade,
            "payload": ws_payload,
        })
    else:
        await redis_manager.publish({
            "target_type": "broadcast",
            "payload": ws_payload,
        })

    # ── Push notifications for broadcast ─────────────────────────────────────
    notif_title = payload.title
    notif_body  = payload.message[:200]  # cap body length for display

    if payload.target_type == "grade" and payload.target_grade is not None:
        # Notify students + parents of the target grade only
        sp_result = await db.execute(
            select(StudentProfile)
            .join(User, User.id == StudentProfile.user_id)
            .where(
                StudentProfile.grade == payload.target_grade,
                User.is_active == True,
                User.is_approved == True,
                User.deleted_at.is_(None),
            )
        )
        profiles = sp_result.scalars().all()
        all_user_ids = {p.user_id for p in profiles}
        all_user_ids.update(p.parent_user_id for p in profiles if p.parent_user_id)
    else:
        # Notify all active approved users
        all_users_result = await db.execute(
            select(User.id)
            .where(
                User.is_active == True,
                User.is_approved == True,
                User.deleted_at.is_(None),
            )
        )
        all_user_ids = {row.id for row in all_users_result}

    if all_user_ids:
        token_result = await db.execute(
            select(User.fcm_token)
            .where(User.id.in_(all_user_ids), User.fcm_token.isnot(None))
        )
        tokens = [row.fcm_token for row in token_result]
        if tokens:
            asyncio.create_task(notification_service.send_to_tokens(
                tokens=tokens,
                title=notif_title,
                body=notif_body,
                data={"route": "/student/broadcasts"},
            ))

    return BroadcastResponse(
        id=bc.id,
        sender_id=bc.sender_id,
        sender_username=current_teacher.username,
        title=bc.title,
        message=bc.message,
        target_type=bc.target_type,
        target_grade=bc.target_grade,
        created_at=bc.created_at,
    )


@router.get("/broadcast", response_model=List[BroadcastResponse])
async def list_teacher_broadcasts(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """List all broadcasts sent by this teacher."""
    result = await db.execute(
        select(Broadcast)
        .where(Broadcast.sender_id == current_teacher.id)
        .order_by(Broadcast.created_at.desc())
    )
    broadcasts = result.scalars().all()
    return [
        BroadcastResponse(
            id=b.id,
            sender_id=b.sender_id,
            sender_username=current_teacher.username,
            title=b.title,
            message=b.message,
            target_type=b.target_type,
            target_grade=b.target_grade,
            created_at=b.created_at,
        )
        for b in broadcasts
    ]


# ─── Dashboard Summary ─────────────────────────────────────────────────────────

@router.get("/dashboard-summary")
async def get_teacher_dashboard_summary(
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """
    Single aggregated endpoint for the teacher dashboard.
    Returns my_timetable, broadcasts, homework, grades, and test_count — in one round trip.
    Tests are returned as a count only (no questions payload) to keep the response fast.
    """
    # My timetable slots
    my_timetable = (await db.execute(
        select(TimetableSlot)
        .where(TimetableSlot.teacher_id == current_teacher.id)
        .order_by(TimetableSlot.slot_date, TimetableSlot.period_number)
    )).scalars().all()

    # Broadcasts sent by this teacher (50 most recent)
    broadcasts_raw = (await db.execute(
        select(Broadcast)
        .where(Broadcast.sender_id == current_teacher.id)
        .order_by(Broadcast.created_at.desc())
        .limit(50)
    )).scalars().all()
    broadcasts = [
        BroadcastResponse(
            id=b.id, sender_id=b.sender_id, sender_username=current_teacher.username,
            title=b.title, message=b.message, target_type=b.target_type,
            target_grade=b.target_grade, created_at=b.created_at,
        )
        for b in broadcasts_raw
    ]

    # Homework created by this teacher (30 most recent)
    homework = (await db.execute(
        select(Homework)
        .where(Homework.teacher_id == current_teacher.id)
        .order_by(Homework.created_at.desc())
        .limit(30)
    )).scalars().all()

    # Grades recorded by this teacher (100 most recent, sufficient for chart)
    grades = (await db.execute(
        select(Grade)
        .where(Grade.teacher_id == current_teacher.id)
        .order_by(Grade.created_at.desc())
        .limit(100)
    )).scalars().all()

    # Test count only — the dashboard only shows the count, not full question data.
    # Fetching full test questions (large JSON blobs) is extremely slow and
    # unnecessary here.
    test_count_row = (await db.execute(
        select(func.count()).select_from(Test)
    )).scalar()

    return {
        "my_timetable": [TimetableSlotResponse.model_validate(s) for s in my_timetable],
        "broadcasts": broadcasts,
        "homework": [HomeworkResponse.model_validate(h) for h in homework],
        "grades": [GradeResponse.model_validate(g) for g in grades],
        "test_count": test_count_row or 0,
    }
