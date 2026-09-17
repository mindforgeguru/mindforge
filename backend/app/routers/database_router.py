"""
Teacher knowledge-base endpoints.

Three databases:
  /teacher/database/old-tests   — past test papers (AI-classified)
  /teacher/database/chapters    — chapter PDFs (by grade/subject/chapter)
  /teacher/database/syllabus    — syllabus entries (chapter list per grade+subject)
"""

import logging
import uuid
from typing import List, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Form, HTTPException, UploadFile, File
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_teacher
from app.core.upload_utils import reject_if_oversize, validate_document
from app.models.user import User
from app.models.database_models import OldTestPaper, ChapterDocument, SyllabusEntry
from app.services import ai_service, storage_service
from app.services.realtime_service import publish_to_users
from app.core.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

BUCKET = settings.MINIO_BUCKET_DATABASE

# Per-file size cap for knowledge-base uploads (PDFs/images). Without this an
# authenticated teacher could stream an arbitrarily large body — `file.read()`
# buffers the whole thing into memory → OOM/DoS. nginx caps the request at 50M
# but that protection vanishes if the backend is ever reached directly.
_MAX_DOC_BYTES = 25 * 1024 * 1024  # 25 MB
# Cap the batch size on the multi-file old-tests endpoint so the per-file cap
# can't be multiplied into a huge aggregate upload.
_MAX_FILES_PER_UPLOAD = 20
# Knowledge-base uploads are chapter PDFs and scanned answer sheets. The type is
# decided from the file's bytes, not from its name — see validate_document.
_ALLOWED_DOC_EXTS = {"pdf", "png", "jpg", "webp"}


def _enforce_size(file: UploadFile, data: bytes) -> None:
    """Reject an upload whose buffered body exceeds the per-file cap."""
    if len(data) > _MAX_DOC_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File too large (max {_MAX_DOC_BYTES // (1024 * 1024)} MB).",
        )


# ─── helpers ─────────────────────────────────────────────────────────────────
#
# `_ext(filename)` used to live here and derived the extension from the upload's
# name. Every call site now uses validate_document, which derives it from the
# bytes instead, so trusting the name is no longer possible by accident.


# ═══════════════════════════════════════════════════════════════════════════════
# OLD TEST PAPERS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/old-tests/upload")
async def upload_old_test_paper(
    background_tasks: BackgroundTasks,
    files: List[UploadFile] = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    """
    Upload one or more old test paper files.

    Stores them and returns straight away; AI classification (grade, subject,
    chapter) runs in the background and fills the rows in. Scanning inside the
    request took up to 40s per file against an app that gives up at 120s, so a
    batch of more than a few papers timed out. The app already shows
    "AI classification pending..." until a paper's metadata arrives.
    """
    if len(files) > _MAX_FILES_PER_UPLOAD:
        raise HTTPException(
            status_code=413,
            detail=f"Too many files (max {_MAX_FILES_PER_UPLOAD} per upload).",
        )

    records = []
    to_classify = []
    for file in files:
        reject_if_oversize(file, _MAX_DOC_BYTES)
        data = await file.read()
        _enforce_size(file, data)
        # Identify from the bytes. This used to take the extension straight
        # off the filename and hand it to the AI scanner, so the caller
        # chose how their upload was parsed.
        ext = validate_document(data, file.filename or "", _ALLOWED_DOC_EXTS)

        # Store in MinIO
        key = f"old-tests/{current_user.id}/{uuid.uuid4()}.{ext}"
        try:
            await storage_service.upload_file(BUCKET, key, data)
        except Exception as e:
            logger.error(f"MinIO upload failed: {e}")
            raise HTTPException(status_code=500, detail="File storage failed.")

        record = OldTestPaper(
            teacher_id=current_user.id,
            file_key=key,
            original_filename=file.filename or "unknown",
            title=file.filename,
            school_id=current_user.school_id,
        )
        db.add(record)
        await db.flush()
        records.append(record)
        to_classify.append((record.id, key, ext))

    await db.commit()
    background_tasks.add_task(
        classify_old_test_papers, teacher_id=current_user.id, items=to_classify,
    )
    return [_paper_dict(r) for r in records]


async def classify_old_test_papers(
    teacher_id: int,
    items: List[tuple],
    session_factory=None,
) -> None:
    """Scan each uploaded paper and fill in its metadata.

    `items` is `(paper_id, file_key, ext)`. One paper at a time, each in its own
    session: a scan or a write failing for one paper leaves it unclassified and
    moves on. A paper deleted before its turn is skipped. The teacher is told
    after each one so their list fills in as papers finish.
    """
    if session_factory is None:
        from app.core.database import AsyncSessionLocal
        session_factory = AsyncSessionLocal

    for paper_id, key, ext in items:
        try:
            data = await storage_service.download_file(BUCKET, key)
            meta = await ai_service.scan_document_metadata(data, ext) or {}
        except Exception as e:
            logger.warning("Old test paper %s: AI scan failed: %s", paper_id, e)
            continue
        async with session_factory() as db:
            try:
                record = await db.get(OldTestPaper, paper_id)
                if record is None:
                    continue
                record.grade = meta.get("grade")
                record.subject = meta.get("subject")
                record.chapter = meta.get("chapter")
                record.title = meta.get("title") or record.title
                record.ai_summary = meta.get("summary")
                await db.commit()
            except Exception as e:
                await db.rollback()
                logger.warning("Old test paper %s: saving metadata failed: %s", paper_id, e)
                continue
        try:
            await publish_to_users([teacher_id], {
                "event": "old_test_papers_classified", "paper_id": paper_id,
            })
        except Exception as e:
            logger.warning("Old test paper %s: realtime notify failed: %s", paper_id, e)


@router.get("/old-tests")
async def list_old_test_papers(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    q = select(OldTestPaper).where(OldTestPaper.teacher_id == current_user.id)
    if grade is not None:
        q = q.where(OldTestPaper.grade == grade)
    if subject:
        q = q.where(OldTestPaper.subject == subject)
    q = q.order_by(OldTestPaper.created_at.desc())
    result = await db.execute(q)
    return [_paper_dict(r) for r in result.scalars().all()]


@router.delete("/old-tests/{paper_id}", status_code=204)
async def delete_old_test_paper(
    paper_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    result = await db.execute(
        select(OldTestPaper).where(
            OldTestPaper.id == paper_id,
            OldTestPaper.teacher_id == current_user.id,
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Not found.")
    try:
        await storage_service.delete_file(BUCKET, record.file_key)
    except Exception:
        pass
    await db.delete(record)
    await db.commit()


def _paper_dict(r: OldTestPaper) -> dict:
    return {
        "id": r.id,
        "original_filename": r.original_filename,
        "grade": r.grade,
        "subject": r.subject,
        "chapter": r.chapter,
        "title": r.title,
        "ai_summary": r.ai_summary,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# CHAPTER DOCUMENTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/chapters/upload")
async def upload_chapter_document(
    file: UploadFile = File(...),
    grade: int = Form(...),
    subject: str = Form(...),
    chapter_name: str = Form(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    """Upload a chapter PDF/image for a specific grade, subject, and chapter."""
    reject_if_oversize(file, _MAX_DOC_BYTES)
    data = await file.read()
    _enforce_size(file, data)
    # Identify from the bytes. This used to take the extension straight
    # off the filename and hand it to the AI scanner, so the caller
    # chose how their upload was parsed.
    ext = validate_document(data, file.filename or "", _ALLOWED_DOC_EXTS)

    key = f"chapters/{current_user.id}/{uuid.uuid4()}.{ext}"
    try:
        await storage_service.upload_file(BUCKET, key, data)
    except Exception as e:
        logger.error(f"MinIO upload failed: {e}")
        raise HTTPException(status_code=500, detail="File storage failed.")

    record = ChapterDocument(
        teacher_id=current_user.id,
        file_key=key,
        original_filename=file.filename or "unknown",
        grade=grade,
        subject=subject,
        chapter_name=chapter_name,
        school_id=current_user.school_id,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)
    return _chapter_dict(record)


@router.get("/chapters/names")
async def list_chapter_names(
    grade: int,
    subject: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    """
    Return a deduplicated, sorted list of chapter names for a grade+subject.
    Combines chapters from uploaded ChapterDocuments and SyllabusEntry.
    Each item includes whether a PDF has been uploaded for it.
    """
    # Chapters with uploaded PDFs
    q = select(ChapterDocument.chapter_name).where(
        ChapterDocument.teacher_id == current_user.id,
        ChapterDocument.grade == grade,
        ChapterDocument.subject == subject,
    ).distinct()
    result = await db.execute(q)
    pdf_chapters = {row[0] for row in result.all()}

    # Chapters from syllabus (scope reference)
    syl_q = select(SyllabusEntry).where(
        SyllabusEntry.teacher_id == current_user.id,
        SyllabusEntry.grade == grade,
        SyllabusEntry.subject == subject,
    ).limit(1)
    syl_res = await db.execute(syl_q)
    syl = syl_res.scalar_one_or_none()
    syllabus_chapters = set(syl.chapters or []) if syl else set()

    # Merge and annotate
    all_names = pdf_chapters | syllabus_chapters
    return sorted([
        {"name": name, "has_pdf": name in pdf_chapters}
        for name in all_names
    ], key=lambda x: x["name"])


@router.get("/chapters")
async def list_chapter_documents(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    q = select(ChapterDocument).where(ChapterDocument.teacher_id == current_user.id)
    if grade is not None:
        q = q.where(ChapterDocument.grade == grade)
    if subject:
        q = q.where(ChapterDocument.subject == subject)
    q = q.order_by(ChapterDocument.created_at.desc())
    result = await db.execute(q)
    return [_chapter_dict(r) for r in result.scalars().all()]


@router.delete("/chapters/{chapter_id}", status_code=204)
async def delete_chapter_document(
    chapter_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    result = await db.execute(
        select(ChapterDocument).where(
            ChapterDocument.id == chapter_id,
            ChapterDocument.teacher_id == current_user.id,
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Not found.")
    try:
        await storage_service.delete_file(BUCKET, record.file_key)
    except Exception:
        pass
    await db.delete(record)
    await db.commit()


def _chapter_dict(r: ChapterDocument) -> dict:
    return {
        "id": r.id,
        "original_filename": r.original_filename,
        "grade": r.grade,
        "subject": r.subject,
        "chapter_name": r.chapter_name,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# SYLLABUS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/syllabus/upload")
async def upload_syllabus(
    file: UploadFile = File(...),
    grade: int = Form(...),
    subject: str = Form(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    """
    Upload a syllabus PDF. AI scans it to extract the chapter list for
    the given grade+subject, then stores both the file and extracted chapters.
    """
    reject_if_oversize(file, _MAX_DOC_BYTES)
    data = await file.read()
    _enforce_size(file, data)
    # Identify from the bytes. This used to take the extension straight
    # off the filename and hand it to the AI scanner, so the caller
    # chose how their upload was parsed.
    ext = validate_document(data, file.filename or "", _ALLOWED_DOC_EXTS)

    # Store file in MinIO
    key = f"syllabus/{current_user.id}/{uuid.uuid4()}.{ext}"
    try:
        await storage_service.upload_file(BUCKET, key, data)
    except Exception as e:
        logger.error(f"MinIO upload failed: {e}")
        raise HTTPException(status_code=500, detail="File storage failed.")

    # AI extracts chapter list
    try:
        chapter_list = await ai_service.scan_syllabus(data, ext, grade, subject)
    except Exception as e:
        logger.warning(f"Syllabus AI scan failed: {e}")
        chapter_list = []

    # Upsert: delete old entry for same grade+subject, then insert new
    existing = await db.execute(
        select(SyllabusEntry).where(
            SyllabusEntry.teacher_id == current_user.id,
            SyllabusEntry.grade == grade,
            SyllabusEntry.subject == subject,
        )
    )
    old = existing.scalar_one_or_none()
    if old:
        # Delete old MinIO file if present
        if old.file_key:
            try:
                await storage_service.delete_file(BUCKET, old.file_key)
            except Exception:
                pass
        await db.delete(old)

    record = SyllabusEntry(
        teacher_id=current_user.id,
        grade=grade,
        subject=subject,
        chapters=chapter_list,
        file_key=key,
        original_filename=file.filename or "syllabus",
        school_id=current_user.school_id,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)
    return _syllabus_dict(record)


@router.get("/syllabus")
async def list_syllabus(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    q = select(SyllabusEntry).where(SyllabusEntry.teacher_id == current_user.id)
    if grade is not None:
        q = q.where(SyllabusEntry.grade == grade)
    if subject:
        q = q.where(SyllabusEntry.subject == subject)
    q = q.order_by(SyllabusEntry.grade, SyllabusEntry.subject)
    result = await db.execute(q)
    return [_syllabus_dict(r) for r in result.scalars().all()]


@router.delete("/syllabus/{syllabus_id}", status_code=204)
async def delete_syllabus(
    syllabus_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_teacher),
):
    result = await db.execute(
        select(SyllabusEntry).where(
            SyllabusEntry.id == syllabus_id,
            SyllabusEntry.teacher_id == current_user.id,
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Not found.")
    await db.delete(record)
    await db.commit()


def _syllabus_dict(r: SyllabusEntry) -> dict:
    return {
        "id": r.id,
        "grade": r.grade,
        "subject": r.subject,
        "chapters": r.chapters or [],
        "original_filename": r.original_filename,
        "updated_at": r.updated_at.isoformat() if r.updated_at else None,
    }
