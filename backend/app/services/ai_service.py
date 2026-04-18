"""
AI Pipeline Service for MIND FORGE.

Pipeline:
1. Try Gemini first (native PDF/image reading via Files API)
2. Fall back to Groq (text extracted from files via PyMuPDF/Pillow + pytesseract)
3. If both fail, return stub questions
"""

import asyncio
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
                max_output_tokens=16384,
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
                page_text = page.get_text().strip()
                pix = page.get_pixmap(dpi=150)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
                ocr_text = pytesseract.image_to_string(img).strip()
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


# ─── Paper metadata scanning ─────────────────────────────────────────────────

def _build_scan_prompt() -> str:
    return """You are an expert at reading Indian ICSE school exam papers and textbook chapters.

Examine the document and extract the following metadata.
Respond ONLY with a valid JSON object — no markdown, no explanation.

{
  "grade": <integer 8, 9, or 10, or null if not determinable>,
  "subject": "<one of: Math, Physics, Chemistry, Biology, History & Civics, Geography, English 1, English 2, Computer Applications, Economics, Environmental Science, Artificial Intelligence — or null>",
  "chapter": "<chapter or topic name — or null>",
  "title": "<descriptive title for this document — or null>",
  "summary": "<1-2 sentence summary of what this document covers>"
}

JSON:"""


async def scan_document_metadata(
    file_bytes: bytes,
    ext: str,
) -> Dict[str, Any]:
    """
    Use AI to extract grade/subject/chapter/title from an uploaded document.
    Falls back to empty metadata if AI is unavailable.
    """
    loop = asyncio.get_event_loop()

    if settings.GEMINI_API_KEY:
        try:
            uploaded = await loop.run_in_executor(
                None, lambda: _upload_file_to_gemini(file_bytes, ext)
            )
            prompt = _build_scan_prompt()
            model = _get_gemini_model()
            response = await loop.run_in_executor(
                None, lambda: model.generate_content([uploaded, prompt])
            )
            await loop.run_in_executor(
                None, lambda: genai.delete_file(uploaded.name)
            )
            raw = response.text.strip()
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
            return json.loads(raw)
        except Exception as e:
            logger.warning(f"Gemini scan failed: {e}")

    if settings.GROQ_API_KEY:
        try:
            source_text = await loop.run_in_executor(
                None, lambda: _extract_text_from_file(file_bytes, ext)
            )
            prompt = _build_scan_prompt()
            full_prompt = f"SOURCE TEXT:\n---\n{source_text[:8000]}\n---\n\n{prompt}"
            client = _get_groq_client()
            response = await loop.run_in_executor(
                None,
                lambda: client.chat.completions.create(
                    model=settings.GROQ_MODEL,
                    messages=[{"role": "user", "content": full_prompt}],
                    temperature=0.2,
                    max_tokens=512,
                )
            )
            raw = response.choices[0].message.content.strip()
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
            return json.loads(raw)
        except Exception as e:
            logger.warning(f"Groq scan failed: {e}")

    return {"grade": None, "subject": None, "chapter": None, "title": None, "summary": None}


# ─── Syllabus scanning ────────────────────────────────────────────────────────

def _build_syllabus_prompt(grade: int, subject: str) -> str:
    return f"""You are reading an ICSE school syllabus document for Grade {grade}, subject: {subject}.

Extract the complete list of chapter/unit names for this subject from the document.
Return ONLY a valid JSON array of strings — each string is one chapter or unit name.
Keep names concise (as they appear in the syllabus). No descriptions, just names.

Example output:
["Chapter 1: The Cell", "Chapter 2: Tissues", "Chapter 3: Nutrition in Plants"]

If you cannot find chapter names for this subject, return an empty array: []

JSON array:"""


async def scan_syllabus(
    file_bytes: bytes,
    ext: str,
    grade: int,
    subject: str,
) -> List[str]:
    """
    Use AI to extract the chapter list from a syllabus PDF for a given grade+subject.
    Returns a list of chapter name strings.
    """
    loop = asyncio.get_event_loop()
    prompt = _build_syllabus_prompt(grade, subject)

    if settings.GEMINI_API_KEY:
        try:
            uploaded = await loop.run_in_executor(
                None, lambda: _upload_file_to_gemini(file_bytes, ext)
            )
            model = _get_gemini_model()
            response = await loop.run_in_executor(
                None, lambda: model.generate_content([uploaded, prompt])
            )
            await loop.run_in_executor(None, lambda: genai.delete_file(uploaded.name))
            raw = response.text.strip()
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
            result = json.loads(raw)
            if isinstance(result, list):
                return [str(c) for c in result if c]
        except Exception as e:
            logger.warning(f"Gemini syllabus scan failed: {e}")

    if settings.GROQ_API_KEY:
        try:
            source_text = await loop.run_in_executor(
                None, lambda: _extract_text_from_file(file_bytes, ext)
            )
            full_prompt = f"SOURCE TEXT:\n---\n{source_text[:8000]}\n---\n\n{prompt}"
            client = _get_groq_client()
            response = await loop.run_in_executor(
                None,
                lambda: client.chat.completions.create(
                    model=settings.GROQ_MODEL,
                    messages=[{"role": "user", "content": full_prompt}],
                    temperature=0.1,
                    max_tokens=1024,
                )
            )
            raw = response.choices[0].message.content.strip()
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
            result = json.loads(raw)
            if isinstance(result, list):
                return [str(c) for c in result if c]
        except Exception as e:
            logger.warning(f"Groq syllabus scan failed: {e}")

    return []


# ─── Prompt building ──────────────────────────────────────────────────────────

def _build_prompt(
    params: Any,
    chapter_text: str = "",
    old_paper_text: str = "",
    syllabus_chapters: List[str] = [],
) -> str:
    question_spec_lines = []
    if params.mcq_count > 0:
        question_spec_lines.append(
            f"- {params.mcq_count} Multiple Choice Questions (MCQ) — 1 mark each. "
            "Provide 4 options (A, B, C, D) and the correct answer letter."
        )
    if params.true_false_count > 0:
        question_spec_lines.append(
            f"- {params.true_false_count} True/False statements — 1 mark each. "
            "Answer must be 'True' or 'False'."
        )
    if params.fill_blank_count > 0:
        question_spec_lines.append(
            f"- {params.fill_blank_count} Fill-in-the-Blank questions — 1 mark each. "
            "Provide the exact word(s) as the answer."
        )
    if params.match_following_count > 0:
        question_spec_lines.append(
            f"- 1 Match-the-Following set with EXACTLY {params.match_following_count} pairs — "
            f"{params.match_following_count} marks total (1 per correct pair). "
            f"Set column_a to a list of {params.match_following_count} terms. "
            f"Set column_b to a SHUFFLED list of {params.match_following_count} definitions. "
            "Set answer to 'A-<n>, B-<n>, ...' where each letter maps to the correct column_b index (1-based)."
        )
    if params.vsa_count > 0:
        question_spec_lines.append(
            f"- {params.vsa_count} One-Word / Very Short Answer (VSA) questions — 1 mark each. "
            "Answer should be 1-3 words or a single sentence."
        )
    if params.short_answer_count > 0:
        gen_sa = params.short_answer_count + 1
        question_spec_lines.append(
            f"- {gen_sa} Short Answer questions — 2 marks each. "
            "Answer should be 3-5 sentences. "
            f"(Teacher will print 'Attempt any {params.short_answer_count} of {gen_sa}' — generate all {gen_sa}.)"
        )
    if params.long_answer_count > 0:
        gen_la = params.long_answer_count + 1
        question_spec_lines.append(
            f"- {gen_la} Long Answer questions — 3 marks each. "
            "Answer should be a detailed paragraph. "
            f"(Teacher will print 'Attempt any {params.long_answer_count} of {gen_la}' — generate all {gen_la}.)"
        )
    if params.diagram_count > 0:
        question_spec_lines.append(
            f"- {params.diagram_count} Diagram-Based questions — 5 marks each. "
            "Each question must require the student to draw, label, or interpret a diagram."
        )
    if params.include_numericals:
        question_spec_lines.append(
            "- 2 Numerical/Calculation-based problems — 2 marks each. "
            "Provide the numerical answer with units."
        )

    question_spec = "\n".join(question_spec_lines)

    # ── Build source context sections ─────────────────────────────────────────
    source_sections = ""
    has_sources = chapter_text.strip() or old_paper_text.strip()

    if chapter_text.strip():
        source_sections += (
            f"\n\n━━━ CHAPTER PDF ━━━\n"
            f"The following text is from the chapter '{params.chapter}' ({params.subject}, Grade {params.grade}).\n\n"
            f"From this PDF you will use TWO things:\n"
            f"  [BACK EXERCISES] — sections at the END of the chapter labelled:\n"
            f"      'Exercises', 'Questions', 'Review Questions', 'Practice Questions',\n"
            f"      'Self Assessment', 'Think and Answer', 'Fill in the Blanks',\n"
            f"      'Give Reasons', 'Short Answer Questions', 'Long Answer Questions',\n"
            f"      or any numbered/lettered question list near the end of the chapter.\n"
            f"      → 20% of questions must be EXACT copies from here (category [2]).\n"
            f"      → 20% of questions must be AI-written in the same style (category [4]).\n\n"
            f"  [CHAPTER THEORY] — definitions, laws, concepts, worked examples.\n"
            f"      → Used for category [5] fully AI-generated questions.\n"
            f"---\n{chapter_text[:25000]}\n---"
        )

    if old_paper_text.strip():
        source_sections += (
            f"\n\n━━━ OLD TEST PAPERS ━━━\n"
            f"The following text is from old test papers for {params.subject} Grade {params.grade}.\n"
            f"⚠️  These papers contain questions from MULTIPLE chapters.\n"
            f"    ONLY use questions that are SPECIFICALLY about '{params.chapter}'.\n"
            f"    IGNORE all questions about other chapters.\n\n"
            f"From these papers you will use TWO things:\n"
            f"  → 20% of questions must be EXACT copies of old-paper questions about '{params.chapter}' (category [1]).\n"
            f"  → 20% of questions must be AI-written in the same style as those old-paper questions (category [3]).\n"
            f"---\n{old_paper_text[:15000]}\n---"
        )

    if syllabus_chapters:
        syllabus_list = ", ".join(syllabus_chapters)
        source_sections += (
            f"\n\n━━━ SYLLABUS REFERENCE (scope only — do not generate from this) ━━━\n"
            f"All chapters in {params.subject} Grade {params.grade}: {syllabus_list}\n"
            f"The test is for: '{params.chapter}' only."
        )

    # ── Topic instruction ──────────────────────────────────────────────────────
    if has_sources:
        topic_instruction = (
            f"Generate ALL questions STRICTLY about '{params.chapter}' in {params.subject} "
            f"(Grade {params.grade}, ICSE board) using the source material above.\n"
            f"Every single question must be within the scope of '{params.chapter}' — "
            f"no other chapter, no general knowledge."
        )
    else:
        topic_instruction = (
            f"Generate questions STRICTLY about '{params.chapter}' in {params.subject} "
            f"for Grade {params.grade} ICSE board.\n"
            f"Every question must be within the scope of '{params.chapter}' only."
        )

    match_note = ""
    if params.match_following_count > 0:
        match_note = """
For match_following items use this exact JSON structure:
{
  "type": "match_following",
  "question": "Match the following",
  "column_a": ["term1", "term2", ...],
  "column_b": ["shuffled_def1", "shuffled_def2", ...],
  "options": null,
  "answer": "A-2, B-4, C-1, D-3",
  "marks": <number of pairs>
}
"""

    return f"""You are an expert ICSE board question-paper setter for Grades 8, 9, and 10.
{source_sections}

━━━ TEST PARAMETERS ━━━
Subject : {params.subject}
Chapter : {params.chapter}
Grade   : {params.grade}
Board   : ICSE

{topic_instruction}

━━━ GENERATE EXACTLY THE FOLLOWING ━━━
{question_spec}
{match_note}
━━━ QUESTION SOURCING — MANDATORY DISTRIBUTION ━━━
You MUST distribute the questions across exactly these 5 source categories.
For each question, internally track which category it belongs to.

  [1] EXACT from old test papers        — {params.src_pct_p}% of total questions
      Copy questions word-for-word from the old test papers above.
      Only use questions that are specifically about '{params.chapter}'.

  [2] EXACT from back exercises          — {params.src_pct_e}% of total questions
      Copy questions word-for-word from the end-of-chapter exercise sections
      in the chapter PDF (sections labelled Exercises / Review Questions /
      Self Assessment / Think and Answer / Practice Questions / Q.1, Q.2 etc.
      at the END of the chapter).

  [3] AI-generated similar to old tests — {params.src_pct_np}% of total questions
      Create NEW questions that follow the same style, difficulty, and phrasing
      as the old test paper questions for '{params.chapter}'.
      Do NOT copy — write fresh questions inspired by the old paper style.

  [4] AI-generated similar to back exercises — {params.src_pct_ne}% of total questions
      Create NEW questions that follow the same style and format as the
      back-exercise questions from the chapter PDF.
      Do NOT copy — write fresh questions inspired by the exercise style.

  [5] Fully AI-generated                 — {params.src_pct_ai}% of total questions
      Create completely original questions about '{params.chapter}' based on
      the chapter theory, definitions, laws, and concepts.

Round to the nearest whole number per category. If rounding leaves a remainder,
distribute it across whichever categories have non-zero percentages.

━━━ CRITICAL RULES ━━━
1. ALL questions must be about '{params.chapter}' ONLY — not any other chapter or topic.
2. Follow the {params.src_pct_p}/{params.src_pct_e}/{params.src_pct_np}/{params.src_pct_ne}/{params.src_pct_ai} sourcing distribution above — this is mandatory.
3. Categories [1] and [2] must use exact or near-exact wording from the source.
4. Categories [3] and [4] must be freshly written, not copied.
5. NEVER invent facts that are not supported by the source material.
6. Do NOT include URLs, websites, or external references.
7. Do NOT duplicate questions across any category.

Respond ONLY with a valid JSON array. No markdown fences, no explanation.

Each element:
{{
  "id": <integer starting from 1>,
  "type": "<mcq | true_false | fill_blank | match_following | vsa | short_answer | long_answer | diagram | numerical>",
  "question": "<question text>",
  "options": <for MCQ: {{"A": "...", "B": "...", "C": "...", "D": "..."}} | for others: null>,
  "answer": "<correct answer>",
  "marks": <integer>,
  "source_category": <1|2|3|4|5>
}}

source_category must be one of:
1 = exact copy from old test paper
2 = exact copy from back exercise
3 = AI-generated in style of old test paper
4 = AI-generated in style of back exercise
5 = fully AI-generated

JSON array:"""


# Enforced marks per question type
_TYPE_MARKS: Dict[str, int] = {
    "mcq": 1,
    "true_false": 1,
    "fill_blank": 1,
    "vsa": 1,
    "short_answer": 2,
    "long_answer": 3,
    "diagram": 5,
    "numerical": 2,
    # match_following marks = number of pairs (set from AI response)
}


# ─── Response parsing ─────────────────────────────────────────────────────────

def _parse_questions(raw: str, params: Any = None) -> List[Dict[str, Any]]:
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
        q_type = q.get("type", "vsa")

        # Handle match_following specially
        if q_type == "match_following":
            col_a = q.get("column_a") or []
            col_b = q.get("column_b") or []
            marks = len(col_a) if col_a else q.get("marks", 4)
            validated.append({
                "id": len(validated) + 1,
                "type": "match_following",
                "question": q_text,
                "column_a": [str(x) for x in col_a],
                "column_b": [str(x) for x in col_b],
                "options": None,
                "answer": a_text,
                "marks": marks,
                "source_category": q.get("source_category"),
            })
            continue

        raw_options = q.get("options")
        options = None
        if isinstance(raw_options, dict) and raw_options:
            options = {str(k): str(v) for k, v in raw_options.items()}

        validated.append({
            "id": len(validated) + 1,
            "type": q_type,
            "question": q_text,
            "options": options,
            "answer": a_text,
            "marks": _TYPE_MARKS.get(q_type, q.get("marks", 1)),
            "source_category": q.get("source_category"),
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
        logger.info(f"Uploaded file to Gemini: {uploaded.name}, size={len(file_bytes)} bytes")
        return uploaded
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


async def _generate_with_gemini(
    chapter_files: List[Tuple[bytes, str]],
    old_paper_files: List[Tuple[bytes, str]],
    syllabus_chapters: List[str],
    params: Any,
) -> List[Dict[str, Any]]:
    loop = asyncio.get_event_loop()
    all_uploaded: List[Any] = []
    try:
        # Upload chapter files
        chapter_uploaded = []
        for file_bytes, ext in chapter_files:
            if not file_bytes:
                continue
            uf = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _upload_file_to_gemini(fb, e)
            )
            chapter_uploaded.append(uf)
            all_uploaded.append(uf)

        # Upload old paper files
        old_paper_uploaded = []
        for file_bytes, ext in old_paper_files:
            if not file_bytes:
                continue
            uf = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _upload_file_to_gemini(fb, e)
            )
            old_paper_uploaded.append(uf)
            all_uploaded.append(uf)

        # Build interleaved content parts so Gemini understands source roles
        content_parts: List[Any] = []

        if chapter_uploaded:
            content_parts.append(
                f"━━━ CHAPTER PDF ━━━\n"
                f"Document(s) for chapter '{params.chapter}' ({params.subject}, Grade {params.grade} ICSE).\n"
                f"Read the ENTIRE document. You need TWO things from it:\n"
                f"  [BACK EXERCISES] Sections near the END labelled 'Exercises', 'Questions',\n"
                f"    'Review Questions', 'Self Assessment', 'Think and Answer', 'Practice Questions',\n"
                f"    or any numbered Q.1, Q.2... list. 20% of test questions must be exact copies\n"
                f"    from here; another 20% must be AI-written in the same style.\n"
                f"  [THEORY] Definitions, laws, concepts from the main chapter body —\n"
                f"    used for the fully AI-generated 20%."
            )
            content_parts.extend(chapter_uploaded)

        if old_paper_uploaded:
            content_parts.append(
                f"━━━ OLD TEST PAPERS ━━━\n"
                f"Old/past test papers for {params.subject} Grade {params.grade}.\n"
                f"⚠️  These contain questions from MULTIPLE chapters.\n"
                f"    ONLY use questions specifically about '{params.chapter}' — ignore all others.\n"
                f"20% of test questions must be exact copies of old-paper questions about '{params.chapter}';\n"
                f"another 20% must be AI-written in the same style as those old-paper questions."
            )
            content_parts.extend(old_paper_uploaded)

        if syllabus_chapters:
            content_parts.append(
                f"━━━ SYLLABUS SCOPE (reference only) ━━━\n"
                f"All chapters in {params.subject} Grade {params.grade}: "
                f"{', '.join(syllabus_chapters)}\n"
                f"The test is for: '{params.chapter}' ONLY."
            )

        # Append the generation prompt
        prompt = _build_prompt(params, syllabus_chapters=syllabus_chapters)
        content_parts.append(prompt)

        model = _get_gemini_model()
        response = await loop.run_in_executor(
            None, lambda: model.generate_content(content_parts)
        )
        questions = _parse_questions(response.text, params)
        logger.info(
            f"Gemini generated {len(questions)} questions "
            f"(chapter files: {len(chapter_uploaded)}, old papers: {len(old_paper_uploaded)})"
        )
        return questions
    finally:
        for uf in all_uploaded:
            try:
                await loop.run_in_executor(None, lambda f=uf: genai.delete_file(f.name))
            except Exception:
                pass


# ─── Groq generation ──────────────────────────────────────────────────────────

async def _generate_with_groq(
    chapter_files: List[Tuple[bytes, str]],
    old_paper_files: List[Tuple[bytes, str]],
    syllabus_chapters: List[str],
    params: Any,
) -> List[Dict[str, Any]]:
    loop = asyncio.get_event_loop()

    # Extract text from chapter files
    chapter_text = ""
    for file_bytes, ext in chapter_files:
        if file_bytes:
            text = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _extract_text_from_file(fb, e)
            )
            chapter_text += text + "\n"

    # Extract text from old paper files
    old_paper_text = ""
    for file_bytes, ext in old_paper_files:
        if file_bytes:
            text = await loop.run_in_executor(
                None, lambda fb=file_bytes, e=ext: _extract_text_from_file(fb, e)
            )
            old_paper_text += text + "\n"

    prompt = _build_prompt(
        params,
        chapter_text=chapter_text,
        old_paper_text=old_paper_text,
        syllabus_chapters=syllabus_chapters,
    )
    client = _get_groq_client()

    response = await loop.run_in_executor(
        None,
        lambda: client.chat.completions.create(
            model=settings.GROQ_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.4,
            max_tokens=16384,
        )
    )
    raw = response.choices[0].message.content
    questions = _parse_questions(raw, params)
    logger.info(f"Groq generated {len(questions)} questions")
    return questions


# ─── Main entry point ─────────────────────────────────────────────────────────

async def generate_test_questions(
    chapter_files: List[Tuple[bytes, str]],
    old_paper_files: List[Tuple[bytes, str]],
    syllabus_chapters: List[str],
    params: Any,
) -> List[Dict[str, Any]]:
    """
    Generate test questions. Tries Gemini first, falls back to Groq, then stubs.

    Args:
        chapter_files:    (bytes, ext) tuples of the chapter PDF(s) — primary source.
        old_paper_files:  (bytes, ext) tuples of old test papers — secondary source,
                          AI is instructed to only use questions matching the chapter.
        syllabus_chapters: list of all chapter names for the subject/grade (scope reference).
        params:           TestGenerationParams.
    """
    if settings.GEMINI_API_KEY:
        try:
            return await _generate_with_gemini(chapter_files, old_paper_files, syllabus_chapters, params)
        except Exception as e:
            logger.warning(f"Gemini failed: {e}. Trying Groq...")

    if settings.GROQ_API_KEY:
        try:
            return await _generate_with_groq(chapter_files, old_paper_files, syllabus_chapters, params)
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
    if params.match_following_count > 0:
        col_a = [f"Term {i+1}" for i in range(params.match_following_count)]
        col_b = [f"Definition {i+1}" for i in range(params.match_following_count)]
        answer = ", ".join([f"{chr(65+i)}-{i+1}" for i in range(params.match_following_count)])
        questions.append({"id": q_id, "type": "match_following", "question": f"[STUB] Match the following terms from {chapter}", "column_a": col_a, "column_b": col_b, "options": None, "answer": answer, "marks": params.match_following_count})
        q_id += 1
    for _ in range(params.vsa_count):
        questions.append({"id": q_id, "type": "vsa", "question": f"[STUB VSA] Define one important concept from {chapter}.", "options": None, "answer": "Sample answer.", "marks": 1})
        q_id += 1
    for _ in range(params.short_answer_count + (1 if params.short_answer_count > 0 else 0)):
        questions.append({"id": q_id, "type": "short_answer", "question": f"[STUB SA] Explain in brief the importance of {chapter} in {subject}.", "options": None, "answer": "Sample short answer.", "marks": 2})
        q_id += 1
    for _ in range(params.long_answer_count + (1 if params.long_answer_count > 0 else 0)):
        questions.append({"id": q_id, "type": "long_answer", "question": f"[STUB LA] Describe in detail the concepts covered in {chapter}.", "options": None, "answer": "Sample detailed answer.", "marks": 3})
        q_id += 1
    for _ in range(params.diagram_count):
        questions.append({"id": q_id, "type": "diagram", "question": f"[STUB DIAGRAM] Draw and label a diagram to illustrate a key concept from {chapter} in {subject}.", "options": None, "answer": "Refer to textbook diagram.", "marks": 5})
        q_id += 1
    return questions
