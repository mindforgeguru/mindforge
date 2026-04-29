"""
Student router — all endpoints require student role.
"""

from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import case, func, select
from sqlalchemy.orm import aliased

from app.core.database import get_db
from app.core.redis_client import redis_manager
from app.core.security import get_current_student
from app.core.upload_utils import validate_and_strip_exif
from app.models.attendance import Attendance
from app.models.grade import Grade
from app.models.test import Test, TestSubmission, TestType
from app.models.timetable import TimetableConfig, TimetableSlot
from app.models.user import StudentProfile, User
from app.schemas.attendance import AttendanceResponse, AttendanceSummary
from app.schemas.grade import GradeResponse, GradeStats
from app.schemas.test import (
    TestAnswersSave,
    TestAttemptResponse,
    TestResponse,
    TestSubmissionCreate,
    TestSubmissionResponse,
)
from app.schemas.timetable import TimetableSlotWithTeacherResponse
from app.schemas.homework import (
    HomeworkResponse,
    BroadcastResponse,
    StudentHomeworkCompletion,
)
from app.schemas.fees import StudentFeeSummary
from app.models.homework import Homework, HomeworkCompletion, Broadcast
from app.models.fees import FeeStructure, FeePayment, PaymentInfo
from app.schemas.fees import FeePaymentResponse, PaymentInfoResponse
from app.services import storage_service
from app.core.cache import (
    get_student_profile_cached,
    get_timetable_config_cached,
    get_current_academic_year_cached,
)

router = APIRouter()

# Maps the short code stored in StudentProfile.additional_subjects
# → the full subject name stored in Test.subject (from the teacher dropdown).
_OPTIONAL_SUBJECT_MAP = {
    "ai": "Artificial Intelligence",
    "economics": "Economics",
    "computer": "Computer Applications",
}


def _apply_subject_filter(query, profile):
    """Exclude tests whose subject is an optional subject the student hasn't opted for."""
    student_codes = set(profile.additional_subjects or [])
    excluded_names = {
        full_name
        for code, full_name in _OPTIONAL_SUBJECT_MAP.items()
        if code not in student_codes
    }
    if excluded_names:
        query = query.where(Test.subject.notin_(excluded_names))
    return query


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


@router.get("/attendance/class-leaderboard")
async def get_class_attendance_leaderboard(
    limit: int = Query(7, ge=1, le=20),
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Return top students in the same grade ranked by overall attendance %."""
    from app.models.attendance import AttendanceStatus

    # Get current student's grade
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        return []

    # Get all student user_ids in the same grade
    classmates_result = await db.execute(
        select(StudentProfile.user_id).where(StudentProfile.grade == profile.grade)
    )
    classmate_ids = [row[0] for row in classmates_result.all()]
    if not classmate_ids:
        return []

    # Aggregate attendance per student
    agg = await db.execute(
        select(
            Attendance.student_id,
            func.count(Attendance.id).label("total"),
            func.sum(
                case((Attendance.status == AttendanceStatus.present, 1), else_=0)
            ).label("present"),
        )
        .where(Attendance.student_id.in_(classmate_ids))
        .group_by(Attendance.student_id)
    )
    rows = agg.all()

    # Build percentage map
    pct_map: dict[int, float] = {}
    for row in rows:
        total_r = row.total or 0
        present_r = row.present or 0
        pct_map[row.student_id] = round((present_r / total_r * 100) if total_r > 0 else 0.0, 1)

    # Sort by percentage descending, take top N
    sorted_ids = sorted(pct_map.keys(), key=lambda sid: pct_map[sid], reverse=True)[:limit]

    # Fetch usernames + profile pic
    users_result = await db.execute(
        select(User.id, User.username, User.profile_pic_url)
        .where(User.id.in_(sorted_ids))
    )
    user_map = {row[0]: {"username": row[1], "profile_pic_url": row[2]} for row in users_result.all()}

    leaderboard = []
    for rank, sid in enumerate(sorted_ids, start=1):
        if sid not in user_map:
            continue
        leaderboard.append({
            "rank": rank,
            "student_id": sid,
            "username": user_map[sid]["username"],
            "profile_pic_url": user_map[sid]["profile_pic_url"],
            "attendance_percentage": pct_map[sid],
            "is_me": sid == current_student.id,
        })

    return leaderboard


# ─── Faculty ──────────────────────────────────────────────────────────────────

@router.get("/faculty")
async def get_faculty(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Return all approved teachers with their photo, subjects, and bio."""
    from app.models.user import UserRole, TeacherProfile
    result = await db.execute(
        select(User, TeacherProfile)
        .outerjoin(TeacherProfile, TeacherProfile.user_id == User.id)
        .where(User.role == UserRole.teacher)
        .where(User.deleted_at == None)
        .order_by(User.username)
    )
    rows = result.all()
    return [
        {
            "id": user.id,
            "username": user.username,
            "profile_pic_url": user.profile_pic_url,
            "subjects": profile.teachable_subjects if profile else [],
            "bio": profile.bio if profile else None,
        }
        for user, profile in rows
    ]


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


def _grade_submission(test: Test, answers: dict) -> float:
    """Auto-grade the answers against the test's question key.

    Pure function — does not touch the DB. Used both at /submit time and when
    an in-progress attempt is finalized lazily after its deadline passes.
    """
    score = 0.0
    questions = test.questions or []
    for question in questions:
        q_id = str(question.get("id"))
        correct_answer = str(question.get("answer", "")).strip().lower()
        student_answer = str((answers or {}).get(q_id, "")).strip().lower()
        q_type = question.get("type", "").lower()
        marks = question.get("marks", 1)

        if q_type in ("mcq", "true_false", "fill_blank"):
            if student_answer and student_answer == correct_answer:
                score += marks
        elif q_type in ("vsa", "numerical"):
            if student_answer and correct_answer:
                stop_words = {"the", "a", "an", "is", "are", "was", "were",
                              "of", "in", "on", "at", "to", "for", "it", "its"}
                correct_words = set(correct_answer.split()) - stop_words
                student_words = set(student_answer.split()) - stop_words
                if correct_words:
                    overlap = len(correct_words & student_words) / len(correct_words)
                    if overlap >= 0.5:
                        score += marks
    return score


async def _finalize_submission(
    submission: TestSubmission,
    test: Test,
    db: AsyncSession,
    *,
    auto_submitted: bool,
    finalized_at: Optional[datetime] = None,
) -> None:
    """Score, persist, and broadcast the finalization of a TestSubmission.

    Idempotent: if the submission is already finalized this is a no-op. Used
    by /submit (manual finalization) and by the lazy expiry sweep.
    """
    if submission.is_finalized:
        return

    from app.models.grade import Grade, GradeType

    score = _grade_submission(test, submission.answers or {})
    submission.score = score
    submission.auto_submitted = auto_submitted
    submission.is_finalized = True
    submission.submitted_at = finalized_at or datetime.now(timezone.utc)

    db.add(
        Grade(
            student_id=submission.student_id,
            teacher_id=test.teacher_id,
            subject=test.subject,
            chapter=f"Test: {test.title}",
            test_id=test.id,
            marks_obtained=score,
            max_marks=test.total_marks,
            grade_type=GradeType.online,
        )
    )
    await db.commit()
    await db.refresh(submission)

    # Mark the test fully graded once every student in the grade has finalized.
    student_count_result = await db.execute(
        select(func.count()).select_from(StudentProfile).where(StudentProfile.grade == test.grade)
    )
    student_count = student_count_result.scalar_one()
    finalized_count_result = await db.execute(
        select(func.count())
        .select_from(TestSubmission)
        .where(
            TestSubmission.test_id == test.id,
            TestSubmission.is_finalized == True,  # noqa: E712
        )
    )
    finalized_count = finalized_count_result.scalar_one()
    if student_count > 0 and finalized_count >= student_count:
        test.is_graded = True
        await db.commit()
        await redis_manager.publish({
            "target_type": "broadcast",
            "payload": {"event": "test_completed", "test_id": test.id},
        })

    await redis_manager.publish({
        "target_type": "user",
        "user_id": test.teacher_id,
        "payload": {
            "event": "test_submitted",
            "test_id": test.id,
            "student_id": submission.student_id,
            "score": score,
            "total_marks": test.total_marks,
        },
    })
    await redis_manager.publish({
        "target_type": "user",
        "user_id": submission.student_id,
        "payload": {
            "event": "grade_added",
            "subject": test.subject,
            "marks_obtained": score,
            "max_marks": test.total_marks,
        },
    })

    profile_result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == submission.student_id)
    )
    student_profile = profile_result.scalar_one_or_none()
    if student_profile and student_profile.parent_user_id:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": student_profile.parent_user_id,
            "payload": {
                "event": "child_grade_added",
                "subject": test.subject,
                "marks_obtained": score,
                "max_marks": test.total_marks,
            },
        })


async def _sweep_expired_attempts_for_student(
    student_id: int, db: AsyncSession
) -> None:
    """Finalize any unfinalized attempts for this student whose deadline passed.

    Cheap lazy sweep run from any student-facing endpoint that should reflect
    a "you walked away from the app" auto-submission. Computes the score from
    whatever answers were saved (zero if none), marks auto_submitted=True,
    and stamps submitted_at with the actual deadline.
    """
    now = datetime.now(timezone.utc)
    rows = await db.execute(
        select(TestSubmission).where(
            TestSubmission.student_id == student_id,
            TestSubmission.is_finalized == False,  # noqa: E712
            TestSubmission.attempt_expires_at != None,  # noqa: E711
            TestSubmission.attempt_expires_at <= now,
        )
    )
    expired = list(rows.scalars().all())
    if not expired:
        return

    test_ids = {s.test_id for s in expired}
    test_rows = await db.execute(select(Test).where(Test.id.in_(test_ids)))
    tests_by_id = {t.id: t for t in test_rows.scalars().all()}
    for sub in expired:
        test = tests_by_id.get(sub.test_id)
        if test is None:
            continue
        await _finalize_submission(
            sub,
            test,
            db,
            auto_submitted=True,
            finalized_at=sub.attempt_expires_at,
        )


def _attempt_response(
    submission: TestSubmission, test: Test, *, now: datetime
) -> TestAttemptResponse:
    deadline = submission.attempt_expires_at or test.expires_at or now
    remaining = max(0, int((deadline - now).total_seconds()))
    return TestAttemptResponse(
        submission_id=submission.id,
        test_id=test.id,
        title=test.title,
        subject=test.subject,
        total_marks=test.total_marks,
        time_limit_minutes=test.time_limit_minutes,
        questions=test.questions or [],
        saved_answers=submission.answers or {},
        started_at=submission.started_at or now,
        attempt_expires_at=deadline,
        remaining_seconds=remaining,
        is_finalized=submission.is_finalized,
        score=submission.score,
        auto_submitted=submission.auto_submitted,
    )


@router.get("/tests/pending", response_model=List[TestResponse])
async def get_pending_tests(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Get all online tests available to the student that:
    - Are published
    - Have not expired
    - Have not been finalized by this student yet (in-progress attempts still
      appear so the student can resume them)
    """
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    # Auto-grade anything whose deadline passed while the app was closed.
    await _sweep_expired_attempts_for_student(current_student.id, db)

    now = datetime.now(timezone.utc)

    finalized_result = await db.execute(
        select(TestSubmission.test_id).where(
            TestSubmission.student_id == current_student.id,
            TestSubmission.is_finalized == True,  # noqa: E712
        )
    )
    finalized_ids = {row[0] for row in finalized_result.all()}

    query = (
        select(Test)
        .where(
            Test.grade == profile.grade,
            Test.is_published == True,
            Test.test_type == "online",
            Test.expires_at > now,
        )
    )
    if finalized_ids:
        query = query.where(Test.id.notin_(finalized_ids))
    query = _apply_subject_filter(query, profile)

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

    query = (
        select(Test)
        .where(Test.grade == profile.grade, Test.test_type == TestType.offline,
               Test.is_published == True)
    )
    query = _apply_subject_filter(query, profile)
    result = await db.execute(query.order_by(Test.created_at.desc()))
    return result.scalars().all()


@router.get("/tests/completed", response_model=List[TestResponse])
async def get_completed_tests(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Get online tests the student has already finalized."""
    profile = await get_student_profile_cached(current_student.id, db)
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found.")

    await _sweep_expired_attempts_for_student(current_student.id, db)

    finalized_result = await db.execute(
        select(TestSubmission.test_id).where(
            TestSubmission.student_id == current_student.id,
            TestSubmission.is_finalized == True,  # noqa: E712
        )
    )
    finalized_ids = [row[0] for row in finalized_result.all()]
    if not finalized_ids:
        return []

    result = await db.execute(
        select(Test)
        .where(Test.id.in_(finalized_ids), Test.test_type == TestType.online)
        .order_by(Test.created_at.desc())
    )
    return result.scalars().all()


@router.post("/tests/{test_id}/start", response_model=TestAttemptResponse)
async def start_test_attempt(
    test_id: int,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Start (or resume) the student's attempt at an online test.

    A student may only ever have one attempt per test. The first call creates
    a TestSubmission row and stamps an attempt_expires_at (start_time +
    time_limit, capped by the test's expires_at). Subsequent calls return
    the same row with whatever answers have been autosaved and the time left.

    If the deadline has already passed, the attempt is finalized in place
    (graded with whatever was saved) and the response carries is_finalized=True
    so the client can show the result dialog.
    """
    test_result = await db.execute(select(Test).where(Test.id == test_id))
    test = test_result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found.")
    if test.test_type != TestType.online:
        raise HTTPException(status_code=400, detail="Only online tests can be attempted.")
    if not test.is_published:
        raise HTTPException(status_code=400, detail="Test is not published.")

    now = datetime.now(timezone.utc)
    if test.expires_at and test.expires_at < now:
        raise HTTPException(status_code=410, detail="Test submission window has expired.")

    sub_result = await db.execute(
        select(TestSubmission).where(
            TestSubmission.test_id == test_id,
            TestSubmission.student_id == current_student.id,
        )
    )
    submission = sub_result.scalar_one_or_none()

    if submission is None:
        # First attempt — lock the student in.
        time_limit = test.time_limit_minutes
        if time_limit and time_limit > 0:
            attempt_deadline = now + timedelta(minutes=time_limit)
            if test.expires_at and attempt_deadline > test.expires_at:
                attempt_deadline = test.expires_at
        else:
            attempt_deadline = test.expires_at or (now + timedelta(days=3))

        submission = TestSubmission(
            test_id=test_id,
            student_id=current_student.id,
            answers={},
            score=None,
            started_at=now,
            attempt_expires_at=attempt_deadline,
            is_finalized=False,
            auto_submitted=False,
        )
        db.add(submission)
        await db.commit()
        await db.refresh(submission)
        return _attempt_response(submission, test, now=now)

    # Existing attempt — finalize it lazily if the deadline already passed.
    if (
        not submission.is_finalized
        and submission.attempt_expires_at
        and submission.attempt_expires_at <= now
    ):
        await _finalize_submission(
            submission,
            test,
            db,
            auto_submitted=True,
            finalized_at=submission.attempt_expires_at,
        )

    return _attempt_response(submission, test, now=now)


@router.post("/tests/{test_id}/save", status_code=status.HTTP_200_OK)
async def save_test_answers(
    test_id: int,
    payload: TestAnswersSave,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Autosave answers for an in-progress attempt.

    Treated as a checkpoint — the latest call replaces the saved answer map.
    If the attempt's deadline has passed this finalizes the submission and
    returns 410 so the client can show the result dialog.
    """
    sub_result = await db.execute(
        select(TestSubmission).where(
            TestSubmission.test_id == test_id,
            TestSubmission.student_id == current_student.id,
        )
    )
    submission = sub_result.scalar_one_or_none()
    if submission is None:
        raise HTTPException(status_code=404, detail="No in-progress attempt found.")
    if submission.is_finalized:
        raise HTTPException(status_code=409, detail="Test already submitted.")

    now = datetime.now(timezone.utc)
    if submission.attempt_expires_at and submission.attempt_expires_at <= now:
        test_result = await db.execute(select(Test).where(Test.id == test_id))
        test = test_result.scalar_one_or_none()
        if test is not None:
            await _finalize_submission(
                submission,
                test,
                db,
                auto_submitted=True,
                finalized_at=submission.attempt_expires_at,
            )
        raise HTTPException(status_code=410, detail="Time is up — attempt finalized.")

    submission.answers = payload.answers
    await db.commit()
    return {"saved": True, "remaining_seconds": max(
        0,
        int((submission.attempt_expires_at - now).total_seconds())
        if submission.attempt_expires_at else 0,
    )}


@router.post("/tests/{test_id}/submit", response_model=TestSubmissionResponse, status_code=status.HTTP_201_CREATED)
async def submit_test(
    test_id: int,
    payload: TestSubmissionCreate,
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """
    Finalize the student's attempt at an online test.

    Auto-grades against the question key. If a /start row already exists for
    this student it is finalized in place; otherwise (legacy clients that
    skipped /start) a new finalized submission is created. Submitting after
    the attempt's deadline is treated as auto-submitted.
    """
    test_result = await db.execute(select(Test).where(Test.id == test_id))
    test = test_result.scalar_one_or_none()
    if not test:
        raise HTTPException(status_code=404, detail="Test not found.")

    now = datetime.now(timezone.utc)
    if test.expires_at and test.expires_at < now:
        raise HTTPException(status_code=410, detail="Test submission window has expired.")

    sub_result = await db.execute(
        select(TestSubmission).where(
            TestSubmission.test_id == test_id,
            TestSubmission.student_id == current_student.id,
        )
    )
    submission = sub_result.scalar_one_or_none()

    if submission is None:
        # Legacy / no-start path: create a one-shot finalized row.
        submission = TestSubmission(
            test_id=test_id,
            student_id=current_student.id,
            answers=payload.answers,
            score=None,
            started_at=now,
            attempt_expires_at=now,
            is_finalized=False,
            auto_submitted=payload.auto_submitted,
        )
        db.add(submission)
        await db.commit()
        await db.refresh(submission)
    elif submission.is_finalized:
        raise HTTPException(status_code=409, detail="You have already submitted this test.")
    else:
        submission.answers = payload.answers

    deadline_passed = bool(
        submission.attempt_expires_at and submission.attempt_expires_at <= now
    )
    auto_submitted = payload.auto_submitted or deadline_passed

    finalized_at = (
        submission.attempt_expires_at
        if deadline_passed and submission.attempt_expires_at
        else now
    )
    await _finalize_submission(
        submission,
        test,
        db,
        auto_submitted=auto_submitted,
        finalized_at=finalized_at,
    )

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
    # Don't leak the answer key while the attempt is still in progress.
    if not submission.is_finalized:
        raise HTTPException(status_code=409, detail="Attempt is still in progress.")

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
    raw = await file.read()
    file_bytes, ext = validate_and_strip_exif(raw, file.filename or "upload")
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


@router.get(
    "/homework/completions",
    response_model=List[StudentHomeworkCompletion],
)
async def get_student_homework_completions(
    db: AsyncSession = Depends(get_db),
    current_student: User = Depends(get_current_student),
):
    """Return only this student's own completion rows. Homework without a
    row is treated as 'pending' on the client (no entry returned).
    """
    rows = (await db.execute(
        select(HomeworkCompletion).where(
            HomeworkCompletion.student_id == current_student.id
        )
    )).scalars().all()
    return [
        StudentHomeworkCompletion(
            homework_id=r.homework_id,
            completed=r.completed,
            marked_at=r.marked_at,
        )
        for r in rows
    ]


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
    await _sweep_expired_attempts_for_student(current_student.id, db)
    now = datetime.now(timezone.utc)
    submitted_ids = {
        row[0] for row in (await db.execute(
            select(TestSubmission.test_id).where(
                TestSubmission.student_id == current_student.id,
                TestSubmission.is_finalized == True,  # noqa: E712
            )
        )).all()
    }
    pending_q = select(Test).where(
        Test.grade == profile.grade, Test.is_published == True,
        Test.test_type == "online", Test.expires_at > now,
    )
    if submitted_ids:
        pending_q = pending_q.where(Test.id.notin_(submitted_ids))
    pending_q = _apply_subject_filter(pending_q, profile)
    pending_tests = (await db.execute(pending_q.order_by(Test.created_at.desc()))).scalars().all()
    offline_q = select(Test).where(
        Test.grade == profile.grade, Test.test_type == TestType.offline, Test.is_published == True
    )
    offline_q = _apply_subject_filter(offline_q, profile)
    offline_tests = (await db.execute(offline_q.order_by(Test.created_at.desc()))).scalars().all()

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
