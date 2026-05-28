"""
Auto-presentation service.

Takes a chapter PDF, asks Gemini for an outline sized to fit in N one-hour
periods, then asks Gemini to flesh each outline item into a slide
(title + markdown body + speaker notes). Stores the result in the
chapter_presentations + presentation_slides tables.

Each "period" the school runs is 60 minutes — Gemini is told this so it
can pick a sensible recommended_periods + default_slides_per_period.
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.redis_client import redis_manager
from app.models.presentation import (
    ChapterPresentation,
    PresentationSlide,
    PresentationStatus,
    PresentationTeacherProgress,
)
from app.services import ai_service

logger = logging.getLogger(__name__)


PERIOD_MINUTES = 60  # School period length. Used in every prompt.
_MIN_PERIODS = 1
_MAX_PERIODS = 12
_MIN_SLIDES_PER_PERIOD = 6
_MAX_SLIDES_PER_PERIOD = 18


# ── Prompts ──────────────────────────────────────────────────────────────────


def _build_outline_prompt(grade: int, subject: str, chapter: str) -> str:
    return f"""You are an experienced ICSE school teacher planning a lesson series.

You are reading a chapter PDF for Grade {grade}, subject: {subject}, chapter: {chapter!r}.

Your task: design a slide-by-slide outline for teaching this chapter in
a classroom. The school's period length is exactly {PERIOD_MINUTES} minutes.
Plan for active teaching (~40 minutes of slides) plus discussion / Q&A /
quick exercises (~20 minutes) per period.

Pick a number of periods between {_MIN_PERIODS} and {_MAX_PERIODS} based on
the chapter's depth, and a slides-per-period count between
{_MIN_SLIDES_PER_PERIOD} and {_MAX_SLIDES_PER_PERIOD}.

Respond ONLY with a valid JSON object — no markdown fences, no explanation:

{{
  "recommended_periods": <integer {_MIN_PERIODS}-{_MAX_PERIODS}>,
  "slides_per_period": <integer {_MIN_SLIDES_PER_PERIOD}-{_MAX_SLIDES_PER_PERIOD}>,
  "outline": [
    {{
      "title": "<short slide title>",
      "key_points": ["<bullet 1>", "<bullet 2>", ...]
    }},
    ...
  ]
}}

The total number of outline items MUST equal recommended_periods * slides_per_period.
Every key_points array must have 2–5 short bullets that capture the slide's substance.

JSON:"""


def _build_slide_fill_prompt(grade: int, subject: str, chapter: str,
                             outline_chunk: list) -> str:
    """Ask Gemini to expand outline items into full slide content."""
    chunk_json = json.dumps(outline_chunk, ensure_ascii=False)
    return f"""You are writing slide content for Grade {grade} {subject}, chapter: {chapter!r}.

Given the slide outline items below, expand each into a single slide.
Keep language clear, age-appropriate for an ICSE Grade {grade} student.

Respond ONLY with a valid JSON array — no markdown fences:

[
  {{
    "title": "<slide title, max 80 chars>",
    "body_md": "<2-6 short bullet points in markdown, each starting with '- '. May include short examples or 1 numbered list. No images, no headings.>",
    "speaker_notes": "<1-3 sentences the teacher can say while presenting this slide>"
  }},
  ...
]

The output array length MUST equal the input outline length, in the same order.

INPUT OUTLINE:
{chunk_json}

JSON:"""


# ── Helpers ──────────────────────────────────────────────────────────────────


def _strip_json_fences(raw: str) -> str:
    raw = raw.strip()
    raw = re.sub(r"^```(?:json)?\s*", "", raw)
    raw = re.sub(r"\s*```$", "", raw)
    return raw


def _clamp(value: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, value))


async def _gemini_call(file_bytes: Optional[bytes], ext: Optional[str],
                       prompt: str) -> str:
    """Run a single Gemini call. Uploads the file once if provided."""
    loop = asyncio.get_running_loop()
    client = ai_service._get_gemini_client()
    uploaded = None
    try:
        contents: list = []
        if file_bytes and ext:
            uploaded = await loop.run_in_executor(
                None, lambda: ai_service._upload_file_to_gemini(file_bytes, ext)
            )
            contents.append(uploaded)
        contents.append(prompt)
        response = await loop.run_in_executor(
            None,
            lambda: client.models.generate_content(
                model=settings.GEMINI_MODEL,
                contents=contents,
                config=ai_service._GEMINI_GENERATION_CONFIG,
            ),
        )
        return response.text
    finally:
        if uploaded is not None:
            try:
                await loop.run_in_executor(
                    None, lambda: client.files.delete(name=uploaded.name)
                )
            except Exception as exc:
                logger.warning("Gemini file cleanup failed: %s", exc)


# ── Public API ───────────────────────────────────────────────────────────────


async def analyze_chapter(
    file_bytes: bytes,
    ext: str,
    grade: int,
    subject: str,
    chapter: str,
) -> dict:
    """Ask Gemini for a slide outline sized for {grade}/{subject}/{chapter}.

    Returns {recommended_periods, slides_per_period, outline:[{title, key_points}]}.
    Clamps the AI's choices to safe ranges. Raises on parse failure so the
    caller can mark the presentation FAILED.
    """
    prompt = _build_outline_prompt(grade, subject, chapter)
    raw = await _gemini_call(file_bytes, ext, prompt)
    parsed = json.loads(_strip_json_fences(raw))

    periods = _clamp(int(parsed.get("recommended_periods", 3)),
                     _MIN_PERIODS, _MAX_PERIODS)
    per_period = _clamp(int(parsed.get("slides_per_period", 10)),
                        _MIN_SLIDES_PER_PERIOD, _MAX_SLIDES_PER_PERIOD)
    outline = parsed.get("outline") or []
    if not isinstance(outline, list) or not outline:
        raise ValueError("Gemini returned an empty outline.")

    # Trim or pad the outline to the slot count the AI committed to.
    target = periods * per_period
    if len(outline) > target:
        outline = outline[:target]
    # If short, just accept the shorter deck — adjust per_period downward
    if len(outline) < target:
        per_period = max(_MIN_SLIDES_PER_PERIOD, len(outline) // periods)
        outline = outline[: periods * per_period]

    return {
        "recommended_periods": periods,
        "slides_per_period": per_period,
        "outline": outline,
    }


async def generate_slides(grade: int, subject: str, chapter: str,
                          outline: list) -> list[dict]:
    """Flesh each outline item into a full slide.

    Splits into chunks of ~8 items per Gemini call to keep responses bounded
    and runs them sequentially (parallel would race on the same Gemini key
    quota). Returns a flat list of {title, body_md, speaker_notes}.
    """
    CHUNK = 8
    slides: list[dict] = []
    for start in range(0, len(outline), CHUNK):
        chunk = outline[start:start + CHUNK]
        prompt = _build_slide_fill_prompt(grade, subject, chapter, chunk)
        raw = await _gemini_call(None, None, prompt)
        parsed = json.loads(_strip_json_fences(raw))
        if not isinstance(parsed, list):
            raise ValueError("Gemini slide-fill returned non-array.")
        for item, source in zip(parsed, chunk):
            slides.append({
                "title": str(item.get("title") or source.get("title") or "Untitled slide")[:300],
                "body_md": str(item.get("body_md") or ""),
                "speaker_notes": str(item.get("speaker_notes") or ""),
            })
    return slides


async def run_generation(db: AsyncSession, presentation_id: int) -> None:
    """Background job that takes a PROCESSING row to READY (or FAILED).

    Reads the source PDF off the row's source_pdf_key via storage_service,
    runs the two Gemini passes, persists the slides, then publishes a
    WebSocket event for the uploader.
    """
    from app.services import storage_service  # local import to avoid cycles

    row = (await db.execute(
        select(ChapterPresentation).where(ChapterPresentation.id == presentation_id)
    )).scalar_one_or_none()
    if row is None:
        logger.error("run_generation: presentation %s not found", presentation_id)
        return
    if row.status != PresentationStatus.PROCESSING:
        logger.info("run_generation: presentation %s status=%s, skipping",
                    presentation_id, row.status)
        return

    try:
        # Pull the PDF back from object storage.
        if not row.source_pdf_key:
            raise ValueError("Presentation row has no source_pdf_key.")
        bucket, key = row.source_pdf_key.split("/", 1)
        file_bytes = await storage_service.download_file(bucket, key)
        ext = key.rsplit(".", 1)[-1].lower() if "." in key else "pdf"

        plan = await analyze_chapter(
            file_bytes, ext, row.grade, row.subject, row.chapter_name
        )
        slides_payload = await generate_slides(
            row.grade, row.subject, row.chapter_name, plan["outline"]
        )

        # Persist slides + finalize row metadata.
        for i, s in enumerate(slides_payload):
            db.add(PresentationSlide(
                presentation_id=row.id,
                slide_index=i,
                title=s["title"],
                body_md=s["body_md"],
                speaker_notes=s["speaker_notes"],
            ))
        row.total_slides = len(slides_payload)
        row.recommended_periods = plan["recommended_periods"]
        row.default_slides_per_period = plan["slides_per_period"]
        row.status = PresentationStatus.READY
        row.failure_reason = None
        await db.commit()

        try:
            await redis_manager.publish({
                "target_type": "user",
                "user_id": row.created_by_teacher_id,
                "payload": {
                    "event": "presentation_ready",
                    "presentation_id": row.id,
                    "total_slides": row.total_slides,
                    "recommended_periods": row.recommended_periods,
                },
            })
        except Exception as exc:
            logger.warning("presentation_ready publish failed: %s", exc)

    except Exception as exc:
        logger.exception("Presentation generation failed for id=%s", presentation_id)
        row.status = PresentationStatus.FAILED
        row.failure_reason = str(exc)[:500]
        try:
            await db.commit()
        except Exception:
            await db.rollback()


# ── Progress + period log ────────────────────────────────────────────────────


async def get_or_create_progress(
    db: AsyncSession, presentation_id: int, teacher_id: int,
) -> PresentationTeacherProgress:
    """Return the teacher's progress row for a presentation, creating it
    on first contact. Used both when a teacher adopts a deck and when they
    open it for the first time."""
    row = (await db.execute(
        select(PresentationTeacherProgress).where(
            PresentationTeacherProgress.presentation_id == presentation_id,
            PresentationTeacherProgress.teacher_id == teacher_id,
        )
    )).scalar_one_or_none()
    if row is not None:
        return row
    row = PresentationTeacherProgress(
        presentation_id=presentation_id,
        teacher_id=teacher_id,
        current_slide_index=0,
        periods_used=0,
    )
    db.add(row)
    await db.flush()
    return row


def estimate_remaining(
    progress: PresentationTeacherProgress,
    total_slides: int,
    recommended_periods: int,
) -> dict:
    """Return a remaining-periods + slides-per-period estimate for the UI."""
    slides_left = max(0, total_slides - progress.current_slide_index)
    periods_left = max(0, recommended_periods - progress.periods_used)
    if periods_left == 0 and slides_left > 0:
        # Already overrun the budget — suggest 1 more period.
        periods_left = 1
    slides_per_period = (
        max(1, -(-slides_left // periods_left))  # ceil division
        if periods_left > 0 else 0
    )
    return {
        "slides_left": slides_left,
        "periods_left": periods_left,
        "slides_per_period_suggested": slides_per_period,
    }
