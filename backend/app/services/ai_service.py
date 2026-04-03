"""
AI Pipeline Service for MIND FORGE.

Pipeline:
1. Try Gemini first (native PDF/image reading via Files API)
2. Fall back to Groq (text extracted from files via PyMuPDF/Pillow + pytesseract)
3. If both fail, return stub questions
"""

import asyncio
import base64
import json
import logging
import os
import re
import tempfile
from typing import Any, Dict, List, Optional, Tuple

import google.generativeai as genai
from groq import Groq

from app.core.config import settings

logger = logging.getLogger(__name__)

_gemini_model = None
_groq_client = None

# MIME types Gemini Files API accepts
_MIME_MAP = {
    "pdf": "application/pdf",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "gif": "image/gif",
    "webp": "image/webp",
    "bmp": "image/bmp",
    "tiff": "image/tiff",
    "tif": "image/tiff",
}


def _get_gemini_model():
    global _gemini_model
    if _gemini_model is None:
        genai.configure(api_key=settings.GEMINI_API_KEY)
        _gemini_model = genai.GenerativeModel(
            model_name=settings.GEMINI_MODEL,
            generation_config=genai.GenerationConfig(
                temperature=0.4,
                max_output_tokens=8192,
            ),
        )
    return _gemini_model


def _get_groq_client():
    global _groq_client
    if _groq_client is None:
        _groq_client = Groq(api_key=settings.GROQ_API_KEY)
    return _groq_client


# ─── Text extraction from files (for Groq) ───────────────────────────────────

def _extract_text_from_file(file_bytes: bytes, ext: str) -> str:
    """Extract plain text from PDF or image for use with Groq."""
    try:
        if ext.lower() == "pdf":
            import fitz  # PyMuPDF
            import pytesseract
            from PIL import Image
            import io

            doc = fitz.open(stream=file_bytes, filetype="pdf")
            all_parts = []

            for page in doc:
                # Native text for this page
                page_text = page.get_text().strip()

                # Always OCR the page render to capture diagrams/images
                pix = page.get_pixmap(dpi=150)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
                ocr_text = pytesseract.image_to_string(img).strip()

                # Prefer OCR if it gives more content, else use native text
                best = ocr_text if len(ocr_text) > len(page_text) else page_text
                if best:
                    all_parts.append(best)

            doc.close()
            text = "\n".join(all_parts)
            logger.info(f"PDF extraction (hybrid): {len(text)} chars from {len(all_parts)} pages")
            return text[:40000]

        elif ext.lower() in ("jpg", "jpeg", "png", "bmp", "tiff", "tif", "webp"):
            import pytesseract
            from PIL import Image
            import io
            img = Image.open(io.BytesIO(file_bytes))
            text = pytesseract.image_to_string(img)
            logger.info(f"Image OCR extracted {len(text)} chars")
            return text[:40000]
    except Exception as e:
        logger.warning(f"Text extraction failed for .{ext}: {e}")
    return ""


# ─── Prompt building ──────────────────────────────────────────────────────────

def _build_prompt(params: Any, source_text: str = "") -> str:
    question_spec_lines = []
    if params.mcq_count > 0:
        question_spec_lines.append(f"- {params.mcq_count} Multiple Choice Questions (MCQ) — 1 mark each. Provide 4 options (A, B, C, D) and the correct answer letter.")
    if params.true_false_count > 0:
        question_spec_lines.append(f"- {params.true_false_count} True/False statements — 1 mark each. Answer must be 'True' or 'False'.")
    if params.fill_blank_count > 0:
        question_spec_lines.append(f"- {params.fill_blank_count} Fill-in-the-Blank questions — 1 mark each. Provide the exact word(s) as the answer.")
    if params.vsa_count > 0:
        question_spec_lines.append(f"- {params.vsa_count} Very Short Answer (VSA) questions — 1 mark each. Answer should be 1-2 sentences.")
    if params.short_answer_count > 0:
        question_spec_lines.append(f"- {params.short_answer_count} Short Answer questions — 2 marks each. Answer should be 3-5 sentences.")
    if params.long_answer_count > 0:
        question_spec_lines.append(f"- {params.long_answer_count} Long Answer questions — 3 marks each. Answer should be a detailed paragraph.")
    if params.include_numericals:
        question_spec_lines.append("- 2 Numerical/Calculation-based problems — 2 marks each. Provide the numerical answer with units.")

    question_spec = "\n".join(question_spec_lines)

    if source_text.strip():
        source_section = f"\nSOURCE MATERIAL (use ONLY this content for questions):\n---\n{source_text[:30000]}\n---\n"
        topic_note = f"Generate ALL questions EXCLUSIVELY from the source material above. Subject: {params.subject} — {params.chapter} (Grade {params.grade}, ICSE)."
    else:
        source_section = ""
        topic_note = f"Generate questions strictly about: {params.chapter} in {params.subject} for Grade {params.grade} ICSE board."

    return f"""You are an expert ICSE board question-paper setter for grades 8, 9, and 10.
{source_section}
Test details:
- Subject: {params.subject}
- Chapter/Topic: {params.chapter}
- Grade: {params.grade}
- Board: ICSE

{topic_note}

Generate EXACTLY the following questions:
{question_spec}

RULES:
- NEVER include websites, URLs, or internet references.
- Questions must test academic knowledge appropriate for Grade {params.grade} ICSE.

Respond ONLY with a valid JSON array. No markdown, no explanation.

Each object must have:
{{
  "id": <integer starting from 1>,
  "type": "<mcq | true_false | fill_blank | vsa | short_answer | long_answer | numerical>",
  "question": "<question text>",
  "options": <for MCQ: {{"A": "...", "B": "...", "C": "...", "D": "..."}} | for all others: null>,
  "answer": "<correct answer>",
  "marks": <integer>
}}

JSON array:"""


# Enforced marks per question type — must match what the prompt tells the AI
_TYPE_MARKS: Dict[str, int] = {
    "mcq": 1,
    "true_false": 1,
    "fill_blank": 1,
    "vsa": 1,
    "short_answer": 2,
    "long_answer": 3,
    "numerical": 2,
}


# ─── Response parsing ─────────────────────────────────────────────────────────

def _parse_questions(raw: str) -> List[Dict[str, Any]]:
    raw = raw.strip()
    raw = re.sub(r"^```(?:json)?\s*", "", raw)
    raw = re.sub(r"\s*```$", "", raw)
    json_match = re.search(r'\[.*\]', raw, re.DOTALL)
    if json_match:
        raw = json_match.group(0)

    questions = json.loads(raw)
    if not isinstance(questions, list):
        raise ValueError("Response is not a JSON array.")

    _url_pattern = re.compile(
        r"(https?://|www\.|\.com|\.org|\.net|\.in|visit\s|website|webpage|refer\s+to\s+the\s+link)",
        re.IGNORECASE,
    )

    validated = []
    for q in questions:
        q_text = str(q.get("question", "")).strip()
        a_text = str(q.get("answer", "")).strip()
        if not q_text:
            continue
        if _url_pattern.search(q_text) or _url_pattern.search(a_text):
            continue
        raw_options = q.get("options")
        options = None
        if isinstance(raw_options, dict) and raw_options:
            options = {str(k): str(v) for k, v in raw_options.items()}
        q_type = q.get("type", "mcq")
        validated.append({
            "id": len(validated) + 1,
            "type": q_type,
            "question": q_text,
            "options": options,
            "answer": a_text,
            "marks": _TYPE_MARKS.get(q_type, 1),
        })
    return validated


# ─── Gemini generation ────────────────────────────────────────────────────────

def _upload_file_to_gemini(file_bytes: bytes, ext: str):
    mime_type = _MIME_MAP.get(ext.lower(), "application/octet-stream")
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=f".{ext.lower()}", delete=False) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name
        uploaded = genai.upload_file(tmp_path, mime_type=mime_type)
        logger.info(f"Uploaded file to Gemini Files API: {uploaded.name}, mime={mime_type}, size={len(file_bytes)} bytes")
        return uploaded
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


async def _generate_with_gemini(file_list: List[Tuple[bytes, str]], params: Any) -> List[Dict[str, Any]]:
    loop = asyncio.get_event_loop()
    uploaded_files = []
    try:
        for file_bytes, ext in file_list:
            if not file_bytes:
                continue
            uploaded = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _upload_file_to_gemini(fb, e)
            )
            uploaded_files.append(uploaded)

        prompt = _build_prompt(params)
        content_parts = uploaded_files + [prompt] if uploaded_files else [prompt]

        model = _get_gemini_model()
        response = await loop.run_in_executor(
            None, lambda: model.generate_content(content_parts)
        )
        questions = _parse_questions(response.text)
        logger.info(f"Gemini generated {len(questions)} questions from {len(uploaded_files)} file(s)")
        return questions
    finally:
        for uf in uploaded_files:
            try:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(None, lambda f=uf: genai.delete_file(f.name))
            except Exception:
                pass


# ─── Groq generation ──────────────────────────────────────────────────────────

async def _generate_with_groq(file_list: List[Tuple[bytes, str]], params: Any) -> List[Dict[str, Any]]:
    loop = asyncio.get_event_loop()

    # Extract text from files
    source_text = ""
    for file_bytes, ext in file_list:
        if file_bytes:
            text = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _extract_text_from_file(fb, e)
            )
            source_text += text + "\n"

    prompt = _build_prompt(params, source_text=source_text)
    client = _get_groq_client()

    response = await loop.run_in_executor(
        None,
        lambda: client.chat.completions.create(
            model=settings.GROQ_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.4,
            max_tokens=8192,
        )
    )
    raw = response.choices[0].message.content
    questions = _parse_questions(raw)
    logger.info(f"Groq generated {len(questions)} questions")
    return questions


# ─── Main entry point ─────────────────────────────────────────────────────────

async def generate_test_questions(
    file_list: List[Tuple[bytes, str]],
    params: Any,
    source_text: str = "",
) -> List[Dict[str, Any]]:
    """
    Generate test questions. Tries Gemini first, falls back to Groq, then stubs.
    """
    # Try Gemini
    if settings.GEMINI_API_KEY:
        try:
            return await _generate_with_gemini(file_list, params)
        except Exception as e:
            logger.warning(f"Gemini failed: {e}. Trying Groq...")

    # Try Groq
    if settings.GROQ_API_KEY:
        try:
            return await _generate_with_groq(file_list, params)
        except Exception as e:
            logger.error(f"Groq failed: {e}. Returning stub questions.")

    logger.warning("No AI provider available. Returning stub questions.")
    return _generate_stub_questions(params)


def _generate_stub_questions(params: Any) -> List[Dict[str, Any]]:
    """Fallback stub questions when all AI providers are unavailable."""
    questions = []
    q_id = 1
    subject = params.subject
    chapter = params.chapter

    for _ in range(params.mcq_count):
        questions.append({"id": q_id, "type": "mcq", "question": f"[STUB MCQ] Which of the following best describes a concept from {chapter} in {subject}?", "options": {"A": "Option A", "B": "Option B", "C": "Option C", "D": "Option D"}, "answer": "A", "marks": 1})
        q_id += 1
    for _ in range(params.true_false_count):
        questions.append({"id": q_id, "type": "true_false", "question": f"[STUB T/F] State whether the following statement about {chapter} is True or False.", "options": None, "answer": "True", "marks": 1})
        q_id += 1
    for _ in range(params.fill_blank_count):
        questions.append({"id": q_id, "type": "fill_blank", "question": f"[STUB FILL] ________ is a key term in {chapter} of {subject}.", "options": None, "answer": "Term", "marks": 1})
        q_id += 1
    for _ in range(params.vsa_count):
        questions.append({"id": q_id, "type": "vsa", "question": f"[STUB VSA] Define one important concept from {chapter}.", "options": None, "answer": "Sample answer.", "marks": 1})
        q_id += 1
    for _ in range(params.short_answer_count):
        questions.append({"id": q_id, "type": "short_answer", "question": f"[STUB SA] Explain in brief the importance of {chapter} in {subject}.", "options": None, "answer": "Sample short answer.", "marks": 2})
        q_id += 1
    for _ in range(params.long_answer_count):
        questions.append({"id": q_id, "type": "long_answer", "question": f"[STUB LA] Describe in detail the concepts covered in {chapter}.", "options": None, "answer": "Sample detailed answer.", "marks": 5})
        q_id += 1
    return questions
