"""
Teacher router — all endpoints require teacher role.
"""

import io
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, func, select, update

from app.core.database import get_db
from app.core.redis_client import redis_manager
from app.core.security import get_current_teacher
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
from app.schemas.homework import HomeworkCreate, HomeworkResponse, BroadcastCreate, BroadcastResponse
from app.models.homework import Homework, Broadcast
from app.services import ai_service, pdf_service, storage_service

router = APIRouter()


# ─── Teacher Profile ───────────────────────────────────────────────────────────

@router.get("/profile", response_model=UserResponse)
async def get_teacher_profile(
    current_teacher: User = Depends(get_current_teacher),
):
    """Return the current teacher's profile."""
    return current_teacher


@router.post("/profile/photo", status_code=status.HTTP_200_OK)
async def upload_teacher_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Upload or replace the teacher's profile picture."""
    file_bytes = await file.read()
    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "jpg"
    bucket = "mindforge-profiles"
    key = f"profiles/teacher/{current_teacher.id}/avatar.{ext}"
    await storage_service.upload_file(bucket, key, file_bytes)
    presigned_url = await storage_service.get_presigned_url(bucket, key, expires_seconds=604800)

    result = await db.execute(select(User).where(User.id == current_teacher.id))
    teacher_user = result.scalar_one()
    # Store the key path for later URL regeneration
    teacher_user.profile_pic_url = f"{bucket}/{key}"
    await db.commit()
    return {"profile_pic_url": presigned_url}


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
    """Return all active, approved students enrolled in a specific grade."""
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
    return result.scalars().all()


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
):
    """
    Bulk-mark attendance for a class period.
    Emits a WebSocket event to all students in the grade after saving.
    """
    records = []
    for item in payload.records:
        # Upsert: update if exists for same student/date/period
        existing = await db.execute(
            select(Attendance).where(
                Attendance.student_id == item.student_id,
                Attendance.date == payload.date,
                Attendance.period == payload.period,
            )
        )
        att = existing.scalar_one_or_none()
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

    return slot


# ─── Grades ────────────────────────────────────────────────────────────────────

@router.get("/grades", response_model=List[GradeResponse])
async def get_grades(
    grade: Optional[int] = Query(None),
    subject: Optional[str] = Query(None),
    student_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Retrieve grades with optional filters."""
    query = select(Grade).where(Grade.teacher_id == current_teacher.id)
    if subject:
        query = query.where(Grade.subject == subject)
    if student_id:
        query = query.where(Grade.student_id == student_id)
    result = await db.execute(query.order_by(Grade.created_at.desc()))
    return result.scalars().all()


@router.post("/grades", response_model=GradeResponse, status_code=status.HTTP_201_CREATED)
async def create_grade(
    payload: GradeCreate,
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Record a grade entry and notify the student and their parent via WebSocket."""
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
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """Retrieve all tests (visible to all teachers)."""
    query = select(Test)
    if grade:
        query = query.where(Test.grade == grade)
    result = await db.execute(query.order_by(Test.created_at.desc()))
    return result.scalars().all()


@router.post("/tests/generate", response_model=TestResponse, status_code=status.HTTP_201_CREATED)
async def generate_test(
    title: str = Form(...),
    grade: int = Form(...),
    subject: str = Form(...),
    chapter: str = Form(...),
    test_type: str = Form("online"),
    mcq_count: int = Form(5),
    fill_blank_count: int = Form(3),
    true_false_count: int = Form(2),
    vsa_count: int = Form(2),
    short_answer_count: int = Form(0),
    long_answer_count: int = Form(0),
    include_numericals: bool = Form(False),
    time_limit_minutes: Optional[int] = Form(None),
    source_files: List[UploadFile] = File(default=[]),
    db: AsyncSession = Depends(get_db),
    current_teacher: User = Depends(get_current_teacher),
):
    """
    AI-powered test generation pipeline:
    1. Extract text from uploaded PDF or image via OCR
    2. Call Groq LLM to generate structured questions
    3. Save test to database
    4. For offline tests, generate a PDF via ReportLab and store in MinIO
    5. Broadcast new test event to the grade
    """
    params = TestGenerationParams(
        title=title,
        grade=grade,
        subject=subject,
        chapter=chapter,
        test_type=TestType(test_type),
        mcq_count=mcq_count,
        fill_blank_count=fill_blank_count,
        true_false_count=true_false_count,
        vsa_count=vsa_count,
        short_answer_count=short_answer_count,
        long_answer_count=long_answer_count,
        include_numericals=include_numericals,
        time_limit_minutes=time_limit_minutes if time_limit_minutes is not None else (mcq_count + fill_blank_count + true_false_count + vsa_count),
    )

    source_file_url = None
    file_list = []  # (bytes, ext) tuples passed directly to Gemini

    for i, source_file in enumerate(source_files or []):
        file_bytes = await source_file.read()
        if not file_bytes:
            continue
        bucket = "mindforge-tests"

        ext = source_file.filename.rsplit(".", 1)[-1].lower() if source_file.filename else "bin"

        # Try to upload source file to storage (non-fatal if unavailable)
        try:
            storage_key = f"sources/{current_teacher.id}/{datetime.now(timezone.utc).timestamp()}_{i}.{ext}"
            file_url = await storage_service.upload_file(bucket, storage_key, file_bytes)
            if i == 0:
                source_file_url = file_url
        except Exception:
            pass  # Storage unavailable — proceed without persisting source file

        # Collect for Gemini native file reading (no OCR needed)
        file_list.append((file_bytes, ext))

    # Generate questions — Gemini reads the files natively
    questions = await ai_service.generate_test_questions(file_list, params)

    # Calculate total marks
    total_marks = sum(q.get("marks", 1) for q in questions)

    # Set expiry for online tests (3-day window)
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(days=3) if test_type == "online" else None

    # For online tests: 1 minute per question, auto-publish immediately
    time_limit = len(questions) if test_type == "online" else (params.time_limit_minutes if params.time_limit_minutes is not None else len(questions))

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
    for student_id in affected_student_ids:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": student_id,
            "payload": {"event": "grade_deleted", "test_id": test_id},
        })
        profile_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == student_id)
        )
        profile = profile_result.scalar_one_or_none()
        if profile and profile.parent_user_id:
            await redis_manager.publish({
                "target_type": "user",
                "user_id": profile.parent_user_id,
                "payload": {"event": "child_grade_deleted", "test_id": test_id},
            })


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
            "event": "homework_assigned",
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
