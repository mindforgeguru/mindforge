"""
Auto-presentation HTTP endpoints.

  POST   /api/presentations/upload                 — teacher uploads chapter PDF
  GET    /api/presentations/                       — school-wide list (one card per teacher_progress)
  GET    /api/presentations/{id}                   — full deck + progress + logs
  POST   /api/presentations/{id}/adopt             — current teacher joins this deck
  PATCH  /api/presentations/{id}/slides/{slide_id} — any teacher edits a slide
  POST   /api/presentations/{id}/period-log        — log a period taught
  DELETE /api/presentations/{id}                   — uploader (or admin) deletes

All endpoints require teacher or admin role. Visibility is school-wide so any
teacher can read any presentation; only the period-log writer's own progress
row is mutated by their period log.
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal, get_db
from app.core.security import get_current_user
from app.models.database_models import ChapterDocument
from app.models.presentation import (
    ChapterPresentation,
    PresentationPeriodLog,
    PresentationSlide,
    PresentationStatus,
    PresentationTeacherProgress,
)
from app.models.user import User, UserRole
from app.schemas.presentation import (
    AvailableChapter,
    FromChapterRequest,
    LibraryPresentation,
    PresentationCreateResponse,
    PresentationDetail,
    PresentationListItem,
    PresentationPeriodLogCreate,
    PresentationPeriodLogOut,
    PresentationProgressOut,
    PresentationSlideOut,
    PresentationSlidePatch,
)
from app.services import presentation_service, storage_service

logger = logging.getLogger(__name__)

router = APIRouter()


_VALID_GRADES = (8, 9, 10)
_MAX_PDF_BYTES = 25 * 1024 * 1024  # 25 MB — chapter PDFs are usually < 5 MB


def _require_teacher_or_admin(user: User) -> None:
    if user.role not in (UserRole.teacher, UserRole.admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only teachers and admins can use auto-presentations.",
        )


async def _run_generation_job(presentation_id: int) -> None:
    """Background task wrapper that opens its own DB session."""
    async with AsyncSessionLocal() as db:
        try:
            await presentation_service.run_generation(db, presentation_id)
        except Exception:
            logger.exception("Background generation crashed for id=%s",
                             presentation_id)


# ── POST /upload ─────────────────────────────────────────────────────────────


@router.post("/upload", response_model=PresentationCreateResponse,
             status_code=status.HTTP_202_ACCEPTED)
async def upload_chapter(
    background_tasks: BackgroundTasks,
    grade: int = Form(...),
    subject: str = Form(...),
    chapter_name: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PresentationCreateResponse:
    """Upload a chapter PDF. Returns immediately with status=PROCESSING.
    Gemini analysis + slide generation runs in the background; the client
    can poll GET /{id} or listen for the `presentation_ready` WebSocket
    event."""
    _require_teacher_or_admin(current_user)

    if grade not in _VALID_GRADES:
        raise HTTPException(status_code=422, detail="Grade must be 8, 9, or 10.")
    subject = subject.strip()
    chapter_name = chapter_name.strip()
    if not subject:
        raise HTTPException(status_code=422, detail="Subject is required.")
    if not chapter_name:
        raise HTTPException(status_code=422, detail="Chapter name is required.")

    if file.content_type not in ("application/pdf", "application/octet-stream"):
        # Some browsers send octet-stream; allow but verify extension.
        if not (file.filename or "").lower().endswith(".pdf"):
            raise HTTPException(status_code=415, detail="Only PDF uploads are supported.")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=422, detail="Uploaded file is empty.")
    if len(data) > _MAX_PDF_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"PDF too large (max {_MAX_PDF_BYTES // (1024 * 1024)} MB).",
        )

    # Store the PDF in object storage. Key includes a uuid so re-uploads of
    # the same chapter never collide.
    pdf_key = f"presentations/{current_user.id}/{uuid.uuid4().hex}.pdf"
    bucket = settings.MINIO_BUCKET_PDFS
    try:
        await storage_service.upload_file(bucket, pdf_key, data, "application/pdf")
    except Exception as exc:
        logger.exception("Storage upload failed for presentation source PDF.")
        raise HTTPException(status_code=502, detail="Storage upload failed.") from exc

    row = ChapterPresentation(
        created_by_teacher_id=current_user.id,
        grade=grade,
        subject=subject,
        chapter_name=chapter_name,
        source_pdf_key=f"{bucket}/{pdf_key}",
        status=PresentationStatus.PROCESSING,
    )
    db.add(row)
    await db.commit()
    # Note: no PresentationTeacherProgress row is created here. The uploader
    # has to explicitly hit POST /{id}/adopt (the "Adopt for my class"
    # button) to put the deck on their dashboard. Uploading just adds it
    # to the school-wide library.

    background_tasks.add_task(_run_generation_job, row.id)

    return PresentationCreateResponse(
        presentation_id=row.id, status=row.status.value
    )


# ── GET /available-chapters ──────────────────────────────────────────────────


@router.get("/available-chapters", response_model=List[AvailableChapter])
async def list_available_chapters(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[AvailableChapter]:
    """List every chapter PDF in the school-wide database, plus a flag for
    whether an auto-presentation has already been generated for it. The
    intended UX is to pick a row and click "Generate" (or "Open existing")
    rather than re-uploading the same chapter PDF.

    Note: /teacher/database/chapters filters by current teacher; this view
    is intentionally school-wide so any teacher can pick any chapter doc.
    """
    _require_teacher_or_admin(current_user)

    q = select(ChapterDocument)
    if grade is not None:
        q = q.where(ChapterDocument.grade == grade)
    if subject:
        q = q.where(ChapterDocument.subject == subject)
    q = q.order_by(
        ChapterDocument.subject, ChapterDocument.grade,
        ChapterDocument.created_at.desc(),
    )
    chapters = (await db.execute(q)).scalars().all()

    if not chapters:
        return []

    chapter_ids = [c.id for c in chapters]
    teacher_ids = {c.teacher_id for c in chapters}

    # One-shot lookup of any existing presentations for these chapter docs.
    existing_rows = (await db.execute(
        select(ChapterPresentation).where(
            ChapterPresentation.source_chapter_document_id.in_(chapter_ids)
        )
    )).scalars().all()
    existing_map: dict[int, ChapterPresentation] = {}
    for p in existing_rows:
        cid = p.source_chapter_document_id
        if cid is None:
            continue
        # If there are somehow multiple presentations for the same chapter
        # doc, prefer the READY one, else the most recent. (Shouldn't happen
        # in steady state because find-or-create dedupes, but be defensive.)
        prev = existing_map.get(cid)
        if prev is None:
            existing_map[cid] = p
        elif (prev.status != PresentationStatus.READY
              and p.status == PresentationStatus.READY):
            existing_map[cid] = p

    username_rows = (await db.execute(
        select(User.id, User.username).where(User.id.in_(teacher_ids))
    )).all()
    username_map = {uid: uname for uid, uname in username_rows}

    return [
        AvailableChapter(
            chapter_document_id=c.id,
            teacher_id=c.teacher_id,
            teacher_username=username_map.get(c.teacher_id, "?"),
            grade=c.grade,
            subject=c.subject,
            chapter_name=c.chapter_name,
            original_filename=c.original_filename,
            created_at=c.created_at,
            existing_presentation_id=existing_map[c.id].id
                if c.id in existing_map else None,
            existing_presentation_status=existing_map[c.id].status.value
                if c.id in existing_map else None,
        )
        for c in chapters
    ]


# ── POST /from-chapter ───────────────────────────────────────────────────────


@router.post("/from-chapter", response_model=PresentationCreateResponse,
             status_code=status.HTTP_201_CREATED)
async def create_from_chapter(
    payload: FromChapterRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PresentationCreateResponse:
    """Find-or-create a presentation for an existing chapter document.

    If a presentation already exists for the chapter doc, just adopt it
    (create the caller's teacher_progress row) and return its id. If not,
    create a new ChapterPresentation pointing at the chapter doc's
    file_key and kick off Gemini generation in the background. Either
    way, the caller ends up with a teacher_progress row pointing at the
    deck.
    """
    _require_teacher_or_admin(current_user)

    chapter = (await db.execute(
        select(ChapterDocument).where(
            ChapterDocument.id == payload.chapter_document_id
        )
    )).scalar_one_or_none()
    if chapter is None:
        raise HTTPException(status_code=404, detail="Chapter document not found.")

    # Find-or-create the shared presentation row.
    existing = (await db.execute(
        select(ChapterPresentation).where(
            ChapterPresentation.source_chapter_document_id == chapter.id
        ).order_by(ChapterPresentation.id.desc())
    )).scalars().first()

    if existing is not None:
        # Idempotent — return the deck someone already generated for this
        # chapter doc. No auto-adopt: caller still has to POST /adopt to
        # put it on their dashboard.
        return PresentationCreateResponse(
            presentation_id=existing.id, status=existing.status.value
        )

    # Create fresh. Reuse the chapter doc's file_key directly — no copy.
    row = ChapterPresentation(
        created_by_teacher_id=current_user.id,
        grade=chapter.grade,
        subject=chapter.subject,
        chapter_name=(payload.chapter_name_override or chapter.chapter_name).strip(),
        source_pdf_key=f"{settings.MINIO_BUCKET_DATABASE}/{chapter.file_key}",
        source_chapter_document_id=chapter.id,
        status=PresentationStatus.PROCESSING,
    )
    db.add(row)
    await db.commit()
    # Same as /upload — no auto-progress row. Caller must explicitly adopt.

    background_tasks.add_task(_run_generation_job, row.id)
    return PresentationCreateResponse(
        presentation_id=row.id, status=row.status.value
    )


# ── GET /library ─────────────────────────────────────────────────────────────


@router.get("/library", response_model=List[LibraryPresentation])
async def list_library(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    include_processing: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[LibraryPresentation]:
    """School-wide presentation library — one row per presentation (NOT per
    teacher-progress). Used by the "Presentations" tab in the teacher
    Database screen so any teacher can browse + adopt a deck someone else
    already generated.

    By default only includes READY decks; pass include_processing=true to
    also surface ones still being generated.
    """
    _require_teacher_or_admin(current_user)

    q = select(ChapterPresentation)
    if not include_processing:
        q = q.where(ChapterPresentation.status == PresentationStatus.READY)
    if grade is not None:
        q = q.where(ChapterPresentation.grade == grade)
    if subject:
        q = q.where(ChapterPresentation.subject == subject)
    q = q.order_by(
        ChapterPresentation.subject,
        ChapterPresentation.grade,
        ChapterPresentation.created_at.desc(),
    )
    presentations = (await db.execute(q)).scalars().all()
    if not presentations:
        return []

    pres_ids = [p.id for p in presentations]
    creator_ids = {p.created_by_teacher_id for p in presentations}

    # Bulk fetch progress rows for all of these presentations in one round
    # trip — used to count adopters, count who's completed, and look up
    # the caller's own progress.
    full_progress_rows = (await db.execute(
        select(PresentationTeacherProgress)
        .where(PresentationTeacherProgress.presentation_id.in_(pres_ids))
    )).scalars().all()
    adopters_by_pres: dict[int, set[int]] = {}
    completed_by_pres: dict[int, set[int]] = {}
    last_completion_by_pres: dict[int, datetime] = {}
    my_progress_by_pres: dict[int, PresentationTeacherProgress] = {}
    # Need quick lookup of presentation meta to decide "completed"
    pres_by_id = {p.id: p for p in presentations}
    for pr in full_progress_rows:
        adopters_by_pres.setdefault(pr.presentation_id, set()).add(pr.teacher_id)
        pres = pres_by_id.get(pr.presentation_id)
        if pres is not None:
            slides_done = (
                pres.total_slides > 0
                and pr.current_slide_index >= pres.total_slides
            )
            periods_done = (
                pres.recommended_periods > 0
                and pr.periods_used >= pres.recommended_periods
            )
            if slides_done or periods_done:
                completed_by_pres.setdefault(pr.presentation_id, set()).add(
                    pr.teacher_id
                )
                # Track the most recent completion timestamp for sorting.
                prev = last_completion_by_pres.get(pr.presentation_id)
                if prev is None or pr.updated_at > prev:
                    last_completion_by_pres[pr.presentation_id] = pr.updated_at
        if pr.teacher_id == current_user.id:
            my_progress_by_pres[pr.presentation_id] = pr

    username_rows = (await db.execute(
        select(User.id, User.username).where(User.id.in_(creator_ids))
    )).all()
    username_map = {uid: uname for uid, uname in username_rows}

    def _lifecycle(p: ChapterPresentation) -> str:
        """Per-caller state — describes the current teacher's relationship
        to this deck, not the school-wide aggregate. This is what drives the
        Pending / On going / Completed grouping in the library tab."""
        if current_user.id in completed_by_pres.get(p.id, set()):
            return "COMPLETED"
        if current_user.id in adopters_by_pres.get(p.id, set()):
            return "ONGOING"
        return "PENDING"

    return [
        LibraryPresentation(
            presentation_id=p.id,
            grade=p.grade,
            subject=p.subject,
            chapter_name=p.chapter_name,
            status=p.status.value,
            total_slides=p.total_slides,
            recommended_periods=p.recommended_periods,
            default_slides_per_period=p.default_slides_per_period,
            created_by_username=username_map.get(p.created_by_teacher_id, "?"),
            created_at=p.created_at,
            adopter_count=len(adopters_by_pres.get(p.id, set())),
            completed_count=len(completed_by_pres.get(p.id, set())),
            already_adopted_by_me=(
                current_user.id in adopters_by_pres.get(p.id, set())
            ),
            my_is_completed=(
                current_user.id in completed_by_pres.get(p.id, set())
            ),
            last_completion_at=last_completion_by_pres.get(p.id),
            lifecycle_state=_lifecycle(p),
        )
        for p in presentations
    ]


# ── GET / (list) ─────────────────────────────────────────────────────────────


@router.get("/", response_model=List[PresentationListItem])
async def list_presentations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[PresentationListItem]:
    """School-wide dashboard list — IN-PROGRESS decks only. One card per
    (teacher_progress) row so the same chapter taught by three teachers
    shows three cards.

    A deck disappears from the dashboard once the teacher has finished it
    (slides_covered >= total_slides OR periods_used >= recommended_periods),
    but it stays in the library tab as "completed". Only READY presentations
    are shown — PROCESSING and FAILED rows live exclusively in the library.
    """
    from sqlalchemy import or_

    _require_teacher_or_admin(current_user)

    rows = (await db.execute(
        select(ChapterPresentation, PresentationTeacherProgress)
        .join(
            PresentationTeacherProgress,
            PresentationTeacherProgress.presentation_id == ChapterPresentation.id,
        )
        .where(
            ChapterPresentation.status == PresentationStatus.READY,
            # NOT completed by slide-count
            or_(
                ChapterPresentation.total_slides == 0,
                PresentationTeacherProgress.current_slide_index
                    < ChapterPresentation.total_slides,
            ),
            # AND NOT completed by period-count
            or_(
                ChapterPresentation.recommended_periods == 0,
                PresentationTeacherProgress.periods_used
                    < ChapterPresentation.recommended_periods,
            ),
        )
        .order_by(PresentationTeacherProgress.updated_at.desc())
    )).all()

    # Bulk-fetch usernames for both creator + per-row teacher to avoid N+1.
    user_ids: set[int] = set()
    for pres, prog in rows:
        user_ids.add(pres.created_by_teacher_id)
        user_ids.add(prog.teacher_id)
    user_map: dict[int, str] = {}
    if user_ids:
        usernames = (await db.execute(
            select(User.id, User.username).where(User.id.in_(user_ids))
        )).all()
        user_map = {uid: uname for uid, uname in usernames}

    items: List[PresentationListItem] = []
    for pres, prog in rows:
        items.append(PresentationListItem(
            presentation_id=pres.id,
            grade=pres.grade,
            subject=pres.subject,
            chapter_name=pres.chapter_name,
            status=pres.status.value,
            total_slides=pres.total_slides,
            recommended_periods=pres.recommended_periods,
            default_slides_per_period=pres.default_slides_per_period,
            created_by_teacher_id=pres.created_by_teacher_id,
            created_by_username=user_map.get(pres.created_by_teacher_id, "?"),
            created_at=pres.created_at,
            teacher_id=prog.teacher_id,
            teacher_username=user_map.get(prog.teacher_id, "?"),
            current_slide_index=prog.current_slide_index,
            periods_used=prog.periods_used,
        ))
    return items


# ── GET /{id} ────────────────────────────────────────────────────────────────


@router.get("/{presentation_id}", response_model=PresentationDetail)
async def get_presentation(
    presentation_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PresentationDetail:
    _require_teacher_or_admin(current_user)

    pres = (await db.execute(
        select(ChapterPresentation).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if pres is None:
        raise HTTPException(status_code=404, detail="Presentation not found.")

    slides = (await db.execute(
        select(PresentationSlide)
        .where(PresentationSlide.presentation_id == presentation_id)
        .order_by(PresentationSlide.slide_index)
    )).scalars().all()

    progress_rows = (await db.execute(
        select(PresentationTeacherProgress)
        .where(PresentationTeacherProgress.presentation_id == presentation_id)
    )).scalars().all()

    period_logs = (await db.execute(
        select(PresentationPeriodLog)
        .where(PresentationPeriodLog.presentation_id == presentation_id)
        .order_by(PresentationPeriodLog.period_date.desc(),
                  PresentationPeriodLog.created_at.desc())
    )).scalars().all()

    # Bulk-fetch usernames for everyone involved.
    user_ids: set[int] = {pres.created_by_teacher_id}
    if pres.last_edited_by:
        user_ids.add(pres.last_edited_by)
    for s in slides:
        if s.last_edited_by:
            user_ids.add(s.last_edited_by)
    for p in progress_rows:
        user_ids.add(p.teacher_id)
    for log in period_logs:
        user_ids.add(log.teacher_id)
    user_map: dict[int, str] = {}
    if user_ids:
        rows = (await db.execute(
            select(User.id, User.username).where(User.id.in_(user_ids))
        )).all()
        user_map = {uid: uname for uid, uname in rows}

    # Look up — but do NOT create — the caller's progress row. Adoption is
    # explicit via POST /{id}/adopt or via the "Adopt for my class" button
    # in the library tab. Viewing the deck no longer puts it on the
    # caller's dashboard.
    me_progress = next(
        (p for p in progress_rows if p.teacher_id == current_user.id),
        None,
    )
    my_adopted = me_progress is not None

    if me_progress is not None:
        remaining = presentation_service.estimate_remaining(
            me_progress, pres.total_slides, pres.recommended_periods
        )
    else:
        remaining = {
            "slides_left": pres.total_slides,
            "periods_left": pres.recommended_periods,
            "slides_per_period_suggested": pres.default_slides_per_period,
        }

    return PresentationDetail(
        id=pres.id,
        grade=pres.grade,
        subject=pres.subject,
        chapter_name=pres.chapter_name,
        status=pres.status.value,
        failure_reason=pres.failure_reason,
        total_slides=pres.total_slides,
        recommended_periods=pres.recommended_periods,
        default_slides_per_period=pres.default_slides_per_period,
        created_by_teacher_id=pres.created_by_teacher_id,
        created_by_username=user_map.get(pres.created_by_teacher_id, "?"),
        created_at=pres.created_at,
        last_edited_by_username=(
            user_map.get(pres.last_edited_by) if pres.last_edited_by else None
        ),
        last_edited_at=pres.last_edited_at,
        slides=[
            PresentationSlideOut(
                id=s.id, slide_index=s.slide_index, title=s.title,
                body_md=s.body_md, speaker_notes=s.speaker_notes,
                last_edited_by_username=(
                    user_map.get(s.last_edited_by) if s.last_edited_by else None
                ),
                last_edited_at=s.last_edited_at,
            )
            for s in slides
        ],
        all_progress=[
            PresentationProgressOut(
                teacher_id=p.teacher_id,
                teacher_username=user_map.get(p.teacher_id, "?"),
                current_slide_index=p.current_slide_index,
                periods_used=p.periods_used,
                updated_at=p.updated_at,
            )
            for p in progress_rows
        ],
        period_logs=[
            PresentationPeriodLogOut(
                id=log.id, teacher_id=log.teacher_id,
                teacher_username=user_map.get(log.teacher_id, "?"),
                period_date=log.period_date,
                period_number=log.period_number,
                slides_covered_from=log.slides_covered_from,
                slides_covered_to=log.slides_covered_to,
                notes=log.notes, created_at=log.created_at,
            )
            for log in period_logs
        ],
        my_adopted=my_adopted,
        my_current_slide_index=(
            me_progress.current_slide_index if me_progress else 0
        ),
        my_periods_used=(me_progress.periods_used if me_progress else 0),
        my_slides_left=remaining["slides_left"],
        my_periods_left=remaining["periods_left"],
        my_slides_per_period_suggested=remaining["slides_per_period_suggested"],
    )


# ── POST /{id}/adopt ─────────────────────────────────────────────────────────


@router.post("/{presentation_id}/adopt",
             status_code=status.HTTP_201_CREATED)
async def adopt_presentation(
    presentation_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> dict:
    """Create the current teacher's progress row for this presentation.
    Idempotent: re-calls just return the existing row's id."""
    _require_teacher_or_admin(current_user)

    pres = (await db.execute(
        select(ChapterPresentation.id).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if pres is None:
        raise HTTPException(status_code=404, detail="Presentation not found.")

    progress = await presentation_service.get_or_create_progress(
        db, presentation_id, current_user.id
    )
    await db.commit()
    return {
        "progress_id": progress.id,
        "presentation_id": presentation_id,
        "teacher_id": current_user.id,
        "current_slide_index": progress.current_slide_index,
    }


# ── PATCH /{id}/slides/{slide_id} ────────────────────────────────────────────


@router.patch("/{presentation_id}/slides/{slide_id}",
              response_model=PresentationSlideOut)
async def patch_slide(
    presentation_id: int,
    slide_id: int,
    payload: PresentationSlidePatch,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PresentationSlideOut:
    """Any teacher may edit any slide. Last-write-wins."""
    _require_teacher_or_admin(current_user)

    slide = (await db.execute(
        select(PresentationSlide).where(
            PresentationSlide.id == slide_id,
            PresentationSlide.presentation_id == presentation_id,
        )
    )).scalar_one_or_none()
    if slide is None:
        raise HTTPException(status_code=404, detail="Slide not found.")

    touched = False
    if payload.title is not None:
        slide.title = payload.title
        touched = True
    if payload.body_md is not None:
        slide.body_md = payload.body_md
        touched = True
    if payload.speaker_notes is not None:
        slide.speaker_notes = payload.speaker_notes
        touched = True

    if not touched:
        raise HTTPException(status_code=422, detail="No editable fields supplied.")

    now = datetime.now(timezone.utc)
    slide.last_edited_by = current_user.id
    slide.last_edited_at = now

    # Mirror onto the parent so the list view shows recent activity.
    pres = (await db.execute(
        select(ChapterPresentation).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if pres is not None:
        pres.last_edited_by = current_user.id
        pres.last_edited_at = now

    await db.commit()
    await db.refresh(slide)

    return PresentationSlideOut(
        id=slide.id, slide_index=slide.slide_index, title=slide.title,
        body_md=slide.body_md, speaker_notes=slide.speaker_notes,
        last_edited_by_username=current_user.username,
        last_edited_at=slide.last_edited_at,
    )


# ── POST /{id}/period-log ────────────────────────────────────────────────────


@router.post("/{presentation_id}/period-log",
             response_model=PresentationPeriodLogOut,
             status_code=status.HTTP_201_CREATED)
async def create_period_log(
    presentation_id: int,
    payload: PresentationPeriodLogCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PresentationPeriodLogOut:
    """Log a period taught. Updates the current teacher's progress row to
    point at `slides_covered_to` (clamped to total_slides) and bumps
    periods_used."""
    _require_teacher_or_admin(current_user)

    pres = (await db.execute(
        select(ChapterPresentation).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if pres is None:
        raise HTTPException(status_code=404, detail="Presentation not found.")
    if pres.status != PresentationStatus.READY:
        raise HTTPException(
            status_code=409,
            detail="Presentation is not ready yet — wait for generation to finish.",
        )

    # Period logs require an explicit adoption — the dashboard progress
    # bar only exists after the teacher hits POST /adopt. We don't auto-
    # create here because that would put the deck on the teacher's
    # dashboard via a side-channel.
    progress = (await db.execute(
        select(PresentationTeacherProgress).where(
            PresentationTeacherProgress.presentation_id == presentation_id,
            PresentationTeacherProgress.teacher_id == current_user.id,
        )
    )).scalar_one_or_none()
    if progress is None:
        raise HTTPException(
            status_code=409,
            detail=(
                "Adopt this presentation first (\"Adopt for my class\") "
                "before logging a period."
            ),
        )
    if payload.slides_covered_to < progress.current_slide_index:
        raise HTTPException(
            status_code=422,
            detail=(
                f"slides_covered_to ({payload.slides_covered_to}) cannot be less "
                f"than your current position ({progress.current_slide_index})."
            ),
        )
    to_idx = min(payload.slides_covered_to, pres.total_slides)

    log = PresentationPeriodLog(
        presentation_id=presentation_id,
        teacher_id=current_user.id,
        period_date=payload.period_date,
        period_number=payload.period_number,
        slides_covered_from=progress.current_slide_index,
        slides_covered_to=to_idx,
        notes=payload.notes,
    )
    db.add(log)

    progress.current_slide_index = to_idx
    progress.periods_used += 1

    await db.commit()
    await db.refresh(log)

    return PresentationPeriodLogOut(
        id=log.id,
        teacher_id=log.teacher_id,
        teacher_username=current_user.username,
        period_date=log.period_date,
        period_number=log.period_number,
        slides_covered_from=log.slides_covered_from,
        slides_covered_to=log.slides_covered_to,
        notes=log.notes,
        created_at=log.created_at,
    )


# ── DELETE /{id} ─────────────────────────────────────────────────────────────


@router.delete("/{presentation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_presentation(
    presentation_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Only the uploader or an admin can delete."""
    _require_teacher_or_admin(current_user)

    pres = (await db.execute(
        select(ChapterPresentation).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if pres is None:
        raise HTTPException(status_code=404, detail="Presentation not found.")
    if (current_user.role != UserRole.admin
            and pres.created_by_teacher_id != current_user.id):
        raise HTTPException(
            status_code=403,
            detail="Only the uploader or an admin can delete this presentation.",
        )

    await db.delete(pres)
    await db.commit()
