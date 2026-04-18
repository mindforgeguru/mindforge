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

from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, File
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.database_models import OldTestPaper, ChapterDocument, SyllabusEntry
from app.services import ai_service, storage_service
from app.core.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

BUCKET = settings.MINIO_BUCKET_DATABASE


# ─── helpers ─────────────────────────────────────────────────────────────────

def _ext(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else "bin"


# ═══════════════════════════════════════════════════════════════════════════════
# OLD TEST PAPERS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/old-tests/upload")
async def upload_old_test_paper(
    files: List[UploadFile] = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Upload one or more old test paper files.
    AI scans each file to extract grade/subject/chapter metadata.
    """
    results = []
    for file in files:
        data = await file.read()
        ext = _ext(file.filename or "doc.pdf")

        # AI scan
        try:
            meta = await ai_service.scan_document_metadata(data, ext)
        except Exception as e:
            logger.warning(f"AI scan failed for {file.filename}: {e}")
            meta = {}

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
            grade=meta.get("grade"),
            subject=meta.get("subject"),
            chapter=meta.get("chapter"),
            title=meta.get("title") or file.filename,
            ai_summary=meta.get("summary"),
        )
        db.add(record)
        await db.flush()
        results.append(_paper_dict(record))

    await db.commit()
    return results


@router.get("/old-tests")
async def list_old_test_papers(
    grade: Optional[int] = None,
    subject: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
):
    """Upload a chapter PDF/image for a specific grade, subject, and chapter."""
    data = await file.read()
    ext = _ext(file.filename or "chapter.pdf")

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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
):
    """
    Upload a syllabus PDF. AI scans it to extract the chapter list for
    the given grade+subject, then stores both the file and extracted chapters.
    """
    data = await file.read()
    ext = _ext(file.filename or "syllabus.pdf")

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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
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
