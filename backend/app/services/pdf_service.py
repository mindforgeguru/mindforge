"""
PDF Generation Service using ReportLab.
Generates printable offline test papers with MIND FORGE branding.
"""

import io
import logging
from datetime import date
from typing import Any, Dict, List

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm, mm
from reportlab.platypus import (
    HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
)

logger = logging.getLogger(__name__)

# ─── Brand colors ─────────────────────────────────────────────────────────────
BRAND_PURPLE = colors.HexColor("#4A1F8B")
BRAND_BLUE = colors.HexColor("#1565C0")
BRAND_GOLD = colors.HexColor("#F9A825")
LIGHT_GRAY = colors.HexColor("#F5F5F5")


def _get_styles() -> dict:
    base = getSampleStyleSheet()
    styles = {
        "brand_title": ParagraphStyle(
            "brand_title",
            parent=base["Title"],
            fontSize=24,
            fontName="Helvetica-Bold",
            textColor=BRAND_PURPLE,
            spaceAfter=2,
            alignment=1,  # center
        ),
        "tagline": ParagraphStyle(
            "tagline",
            parent=base["Normal"],
            fontSize=10,
            fontName="Helvetica-Oblique",
            textColor=BRAND_GOLD,
            spaceAfter=6,
            alignment=1,
        ),
        "test_title": ParagraphStyle(
            "test_title",
            parent=base["Heading1"],
            fontSize=16,
            fontName="Helvetica-Bold",
            textColor=BRAND_BLUE,
            spaceAfter=4,
            alignment=1,
        ),
        "section_header": ParagraphStyle(
            "section_header",
            parent=base["Heading2"],
            fontSize=12,
            fontName="Helvetica-Bold",
            textColor=BRAND_PURPLE,
            spaceBefore=10,
            spaceAfter=4,
        ),
        "question": ParagraphStyle(
            "question",
            parent=base["Normal"],
            fontSize=11,
            fontName="Helvetica-Bold",
            spaceBefore=8,
            spaceAfter=2,
            leftIndent=0,
        ),
        "option": ParagraphStyle(
            "option",
            parent=base["Normal"],
            fontSize=10,
            fontName="Helvetica",
            leftIndent=20,
            spaceAfter=1,
        ),
        "answer_line": ParagraphStyle(
            "answer_line",
            parent=base["Normal"],
            fontSize=10,
            fontName="Helvetica",
            textColor=colors.gray,
            leftIndent=0,
            spaceBefore=4,
            spaceAfter=8,
        ),
        "meta": ParagraphStyle(
            "meta",
            parent=base["Normal"],
            fontSize=10,
            fontName="Helvetica",
            alignment=1,
        ),
        "instructions": ParagraphStyle(
            "instructions",
            parent=base["Normal"],
            fontSize=9,
            fontName="Helvetica-Oblique",
            textColor=colors.gray,
            leftIndent=10,
            spaceAfter=2,
        ),
    }
    return styles


def _group_questions_by_type(questions: List[Dict[str, Any]]) -> Dict[str, List]:
    """Group questions by their type for sectioned layout."""
    groups: Dict[str, List] = {
        "mcq": [],
        "true_false": [],
        "fill_blank": [],
        "vsa": [],
        "short_answer": [],
        "long_answer": [],
        "numerical": [],
    }
    for q in questions:
        q_type = q.get("type", "vsa").lower()
        if q_type in groups:
            groups[q_type].append(q)
        else:
            groups["vsa"].append(q)
    return groups


SECTION_LABELS = {
    "mcq": "Section A — Multiple Choice Questions",
    "true_false": "Section B — True / False",
    "fill_blank": "Section C — Fill in the Blanks",
    "vsa": "Section D — Very Short Answer",
    "short_answer": "Section E — Short Answer Questions",
    "long_answer": "Section F — Long Answer Questions",
    "numerical": "Section G — Numerical Problems",
}

ANSWER_LINES = {
    "vsa": 2,
    "short_answer": 4,
    "long_answer": 8,
    "numerical": 3,
}


async def generate_offline_test_pdf(
    questions: List[Dict[str, Any]],
    test_title: str,
    grade: int = 0,
    subject: str = "",
    total_marks: float = 0,
    time_limit_minutes: int = 0,
) -> bytes:
    """
    Generate a branded, printable test paper PDF using ReportLab.

    Returns raw PDF bytes that can be stored in MinIO.
    """
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=2 * cm,
        leftMargin=2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    styles = _get_styles()
    story = []

    # ── Header ────────────────────────────────────────────────────────────────
    story.append(Paragraph("MIND FORGE", styles["brand_title"]))
    story.append(Paragraph("AI Assisted Learning", styles["tagline"]))
    story.append(HRFlowable(width="100%", thickness=2, color=BRAND_PURPLE, spaceAfter=6))

    # ── Test meta ─────────────────────────────────────────────────────────────
    story.append(Paragraph(test_title.upper(), styles["test_title"]))
    meta_items = []
    if grade:
        meta_items.append(f"Grade: {grade}")
    if subject:
        meta_items.append(f"Subject: {subject}")
    if total_marks:
        meta_items.append(f"Total Marks: {int(total_marks)}")
    if time_limit_minutes:
        meta_items.append(f"Time Allowed: {time_limit_minutes} minutes")
    meta_items.append(f"Date: {date.today().strftime('%d %B %Y')}")

    if meta_items:
        story.append(Paragraph("  |  ".join(meta_items), styles["meta"]))

    story.append(Spacer(1, 4 * mm))
    story.append(HRFlowable(width="100%", thickness=1, color=LIGHT_GRAY, spaceAfter=4))

    # ── Student info box ──────────────────────────────────────────────────────
    info_data = [
        ["Name: _______________________________", "Roll No: ___________"],
        ["Class / Division: ___________________", ""],
    ]
    info_table = Table(info_data, colWidths=[10 * cm, 7 * cm])
    info_table.setStyle(TableStyle([
        ("FONT", (0, 0), (-1, -1), "Helvetica", 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 4 * mm))

    # ── General Instructions ──────────────────────────────────────────────────
    story.append(Paragraph("General Instructions:", styles["section_header"]))
    instructions = [
        "1. Read all questions carefully before answering.",
        "2. Attempt all questions. Marks are indicated against each question.",
        "3. Neatness and clarity of expression will be considered.",
        "4. Use of calculator is not permitted unless specified.",
        "5. Write your Name and Roll Number on the top of the answer sheet.",
    ]
    for inst in instructions:
        story.append(Paragraph(inst, styles["instructions"]))

    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_GOLD, spaceBefore=8, spaceAfter=8))

    # ── Questions by section ──────────────────────────────────────────────────
    grouped = _group_questions_by_type(questions)
    q_counter = 1

    for q_type, section_label in SECTION_LABELS.items():
        section_qs = grouped.get(q_type, [])
        if not section_qs:
            continue

        # Compute marks for this section
        section_marks = sum(q.get("marks", 1) for q in section_qs)
        label_with_marks = f"{section_label}  [{section_marks} marks]"
        story.append(Paragraph(label_with_marks, styles["section_header"]))

        for q in section_qs:
            q_text = f"Q{q_counter}. {q.get('question', '')}  [{q.get('marks', 1)} mark{'s' if q.get('marks', 1) > 1 else ''}]"
            story.append(Paragraph(q_text, styles["question"]))

            if q_type == "mcq" and q.get("options"):
                opts = q["options"]
                for key in ("A", "B", "C", "D"):
                    if key in opts:
                        story.append(Paragraph(f"({key}) {opts[key]}", styles["option"]))
                story.append(Paragraph("Answer: ( __ )", styles["answer_line"]))

            elif q_type == "true_false":
                story.append(Paragraph("Circle your answer:    True    /    False", styles["answer_line"]))

            elif q_type == "fill_blank":
                story.append(Paragraph("Answer: ___________________________________________", styles["answer_line"]))

            else:
                num_lines = ANSWER_LINES.get(q_type, 2)
                for _ in range(num_lines):
                    story.append(Paragraph(
                        "____________________________________________________________________",
                        styles["answer_line"]
                    ))

            q_counter += 1

        story.append(Spacer(1, 3 * mm))

    # ── Footer ────────────────────────────────────────────────────────────────
    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceBefore=10, spaceAfter=4))
    story.append(Paragraph(
        "— End of Question Paper — MIND FORGE | AI Assisted Learning",
        ParagraphStyle(
            "footer",
            parent=getSampleStyleSheet()["Normal"],
            fontSize=8,
            textColor=colors.gray,
            alignment=1,
        )
    ))

    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


async def generate_answer_key_pdf(
    questions: List[Dict[str, Any]],
    test_title: str,
    grade: int = 0,
    subject: str = "",
    total_marks: float = 0,
) -> bytes:
    """
    Generate a teacher-only answer key PDF with correct answers highlighted.
    Returns raw PDF bytes.
    """
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=2 * cm,
        leftMargin=2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    styles = _get_styles()
    base = getSampleStyleSheet()

    answer_style = ParagraphStyle(
        "answer",
        parent=base["Normal"],
        fontSize=10,
        fontName="Helvetica-Bold",
        textColor=colors.HexColor("#2E7D32"),
        leftIndent=20,
        spaceAfter=6,
    )
    explanation_style = ParagraphStyle(
        "explanation",
        parent=base["Normal"],
        fontSize=9,
        fontName="Helvetica-Oblique",
        textColor=colors.HexColor("#1565C0"),
        leftIndent=20,
        spaceAfter=8,
    )
    confidential_style = ParagraphStyle(
        "confidential",
        parent=base["Normal"],
        fontSize=11,
        fontName="Helvetica-Bold",
        textColor=colors.red,
        alignment=1,
        spaceAfter=6,
    )

    story = []

    # ── Header ────────────────────────────────────────────────────────────────
    story.append(Paragraph("MIND FORGE — ANSWER KEY", styles["brand_title"]))
    story.append(Paragraph("STRICTLY CONFIDENTIAL — FOR TEACHER USE ONLY", confidential_style))
    story.append(HRFlowable(width="100%", thickness=2, color=colors.red, spaceAfter=8))

    # ── Test meta ─────────────────────────────────────────────────────────────
    story.append(Paragraph(test_title.upper(), styles["test_title"]))
    meta_items = []
    if grade:
        meta_items.append(f"Grade: {grade}")
    if subject:
        meta_items.append(f"Subject: {subject}")
    if total_marks:
        meta_items.append(f"Total Marks: {int(total_marks)}")
    if meta_items:
        story.append(Paragraph("  |  ".join(meta_items), styles["meta"]))

    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_GOLD, spaceBefore=6, spaceAfter=8))

    # ── Questions with answers ─────────────────────────────────────────────────
    grouped = _group_questions_by_type(questions)
    q_counter = 1

    for q_type, section_label in SECTION_LABELS.items():
        section_qs = grouped.get(q_type, [])
        if not section_qs:
            continue

        story.append(Paragraph(section_label, styles["section_header"]))

        for q in section_qs:
            q_text = f"Q{q_counter}. {q.get('question', '')}  [{q.get('marks', 1)} mark{'s' if q.get('marks', 1) > 1 else ''}]"
            story.append(Paragraph(q_text, styles["question"]))

            # Show options for MCQ
            if q_type == "mcq" and q.get("options"):
                opts = q["options"]
                for key in ("A", "B", "C", "D"):
                    if key in opts:
                        story.append(Paragraph(f"({key}) {opts[key]}", styles["option"]))

            # Correct answer (highlighted)
            answer = q.get("answer", "")
            story.append(Paragraph(f"✓ Answer: {answer}", answer_style))

            # Explanation if available
            if q.get("explanation"):
                story.append(Paragraph(f"Explanation: {q['explanation']}", explanation_style))

            q_counter += 1

        story.append(Spacer(1, 3 * mm))

    # ── Footer ────────────────────────────────────────────────────────────────
    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceBefore=10, spaceAfter=4))
    story.append(Paragraph(
        "— Answer Key — MIND FORGE | AI Assisted Learning — CONFIDENTIAL",
        ParagraphStyle(
            "footer",
            parent=base["Normal"],
            fontSize=8,
            textColor=colors.gray,
            alignment=1,
        )
    ))

    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes
