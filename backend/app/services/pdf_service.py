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
NAVY = colors.HexColor("#1D3557")
ORANGE = colors.HexColor("#E87722")

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


# ─── Source category tags (teacher reference only) ────────────────────────────
_SOURCE_TAGS = {
    1: ('<font color="#1565C0" size="8"><b>[P]</b></font>',  "P  = Exact copy from past test paper"),
    2: ('<font color="#2E7D32" size="8"><b>[E]</b></font>',  "E  = Exact copy from back exercise"),
    3: ('<font color="#1565C0" size="8"><b>[~P]</b></font>', "~P = AI-generated, style of past paper"),
    4: ('<font color="#2E7D32" size="8"><b>[~E]</b></font>', "~E = AI-generated, style of back exercise"),
    5: ('<font color="#6A1B9A" size="8"><b>[AI]</b></font>', "AI = Fully AI-generated"),
}

def _source_tag(q: Dict[str, Any]) -> str:
    """Return a small colored HTML tag for the question's source category, or empty string."""
    cat = q.get("source_category")
    if cat is None:
        return ""
    tag, _ = _SOURCE_TAGS.get(int(cat), ("", ""))
    return f"  {tag}" if tag else ""


def _group_questions_by_type(questions: List[Dict[str, Any]]) -> Dict[str, List]:
    """Group questions by their type for sectioned layout."""
    groups: Dict[str, List] = {
        "mcq": [],
        "true_false": [],
        "fill_blank": [],
        "match_following": [],
        "vsa": [],
        "short_answer": [],
        "long_answer": [],
        "diagram": [],
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
    "match_following": "Section D — Match the Following",
    "vsa": "Section E — One Word / Very Short Answer",
    "short_answer": "Section F — Short Answer Questions",
    "long_answer": "Section G — Long Answer Questions",
    "diagram": "Section H — Diagram Based Questions",
    "numerical": "Section I — Numerical Problems",
}

# For short/long answer sections, stores n+1 context to show choice instruction.
# Key = q_type, value = (questions_to_attempt, total_questions)
# This is populated dynamically per test generation in the PDF function.

ANSWER_LINES = {
    "vsa": 2,
    "short_answer": 5,
    "long_answer": 10,
    "diagram": 14,
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

    # ── Source legend (teacher reference — only shown when any question has a tag) ──
    has_source_tags = any(q.get("source_category") is not None for q in questions)
    if has_source_tags:
        story.append(Spacer(1, 3 * mm))
        legend_style = ParagraphStyle(
            "legend",
            parent=getSampleStyleSheet()["Normal"],
            fontSize=7,
            fontName="Helvetica",
            textColor=colors.HexColor("#888888"),
            leftIndent=0,
            spaceAfter=1,
        )
        story.append(Paragraph(
            '<font color="#888888" size="7"><b>Source legend (teacher reference):</b>  '
            + "  |  ".join(desc for _, (_, desc) in _SOURCE_TAGS.items())
            + "</font>",
            legend_style,
        ))

    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_GOLD, spaceBefore=8, spaceAfter=8))

    # ── Questions by section ──────────────────────────────────────────────────
    grouped = _group_questions_by_type(questions)
    q_counter = 1

    for q_type, section_label in SECTION_LABELS.items():
        section_qs = grouped.get(q_type, [])
        if not section_qs:
            continue

        section_marks = sum(q.get("marks", 1) for q in section_qs)

        # Short / long answer choice instruction (n+1 questions generated)
        choice_note = ""
        if q_type == "short_answer" and len(section_qs) > 1:
            attempt = len(section_qs) - 1
            choice_note = f"  (Attempt any {attempt} of {len(section_qs)})"
        elif q_type == "long_answer" and len(section_qs) > 1:
            attempt = len(section_qs) - 1
            choice_note = f"  (Attempt any {attempt} of {len(section_qs)})"

        label_with_marks = f"{section_label}{choice_note}  [{section_marks} marks]"
        story.append(Paragraph(label_with_marks, styles["section_header"]))

        for q in section_qs:
            marks = q.get("marks", 1)
            marks_label = f"{marks} mark{'s' if marks > 1 else ''}"
            q_text = f"Q{q_counter}. {q.get('question', '')}  [{marks_label}]{_source_tag(q)}"
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

            elif q_type == "match_following":
                col_a = q.get("column_a") or []
                col_b = q.get("column_b") or []
                n = max(len(col_a), len(col_b))
                # Build two-column table
                table_data = [
                    [Paragraph("<b>Column A</b>", styles["option"]),
                     Paragraph("<b>Column B</b>", styles["option"]),
                     Paragraph("<b>Answer</b>", styles["option"])],
                ]
                letters = [chr(65 + i) for i in range(n)]
                for i in range(n):
                    a_val = f"({letters[i]})  {col_a[i]}" if i < len(col_a) else ""
                    b_val = f"({i+1})  {col_b[i]}" if i < len(col_b) else ""
                    table_data.append([
                        Paragraph(a_val, styles["option"]),
                        Paragraph(b_val, styles["option"]),
                        Paragraph(f"{letters[i]} — ___", styles["answer_line"]),
                    ])
                match_table = Table(table_data, colWidths=[6.5 * cm, 6.5 * cm, 4 * cm])
                match_table.setStyle(TableStyle([
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F0F4FF")),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ]))
                story.append(match_table)
                story.append(Spacer(1, 2 * mm))

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
            marks = q.get("marks", 1)
            q_text = f"Q{q_counter}. {q.get('question', '')}  [{marks} mark{'s' if marks > 1 else ''}]"
            story.append(Paragraph(q_text, styles["question"]))

            # Show options for MCQ
            if q_type == "mcq" and q.get("options"):
                opts = q["options"]
                for key in ("A", "B", "C", "D"):
                    if key in opts:
                        story.append(Paragraph(f"({key}) {opts[key]}", styles["option"]))

            # Match the following — show columns and correct answer
            if q_type == "match_following":
                col_a = q.get("column_a") or []
                col_b = q.get("column_b") or []
                n = max(len(col_a), len(col_b))
                letters = [chr(65 + i) for i in range(n)]
                table_data = [
                    [Paragraph("<b>Column A</b>", styles["option"]),
                     Paragraph("<b>Column B</b>", styles["option"])],
                ]
                for i in range(n):
                    a_val = f"({letters[i]})  {col_a[i]}" if i < len(col_a) else ""
                    b_val = f"({i+1})  {col_b[i]}" if i < len(col_b) else ""
                    table_data.append([
                        Paragraph(a_val, styles["option"]),
                        Paragraph(b_val, styles["option"]),
                    ])
                match_table = Table(table_data, colWidths=[8 * cm, 8 * cm])
                match_table.setStyle(TableStyle([
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F0F4FF")),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ]))
                story.append(match_table)
                story.append(Spacer(1, 2 * mm))

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

# ─── Shared report header ─────────────────────────────────────────────────────

def _report_header(story: list, styles: dict, title: str, subtitle: str) -> None:
    story.append(Paragraph("MIND FORGE", styles["brand_title"]))
    story.append(Paragraph("AI Assisted Learning", styles["tagline"]))
    story.append(HRFlowable(width="100%", thickness=2, color=BRAND_PURPLE, spaceAfter=6))
    story.append(Paragraph(title, styles["test_title"]))
    story.append(Paragraph(subtitle, styles["meta"]))
    story.append(Spacer(1, 4 * mm))


# ─── Report: Pending Fees (grade-wise) ────────────────────────────────────────

async def generate_pending_fees_report(summaries: List[Dict[str, Any]], academic_year: str) -> bytes:
    from collections import defaultdict
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    _report_header(story, styles,
                   title=f"PENDING FEES REPORT — {academic_year}",
                   subtitle=f"Generated on {date.today().strftime('%d %B %Y')}")

    by_grade: Dict[int, list] = defaultdict(list)
    for s in summaries:
        if s["balance_due"] > 0:
            by_grade[s["grade"]].append(s)

    if not by_grade:
        story.append(Paragraph("No pending fees found for this academic year.", styles["meta"]))
    else:
        grand_total = 0.0
        for grade in sorted(by_grade.keys()):
            students = by_grade[grade]
            story.append(Paragraph(f"Grade {grade}", styles["section_header"]))
            rows = [["Student", "Total Fee (Rs.)", "Paid (Rs.)", "Balance Due (Rs.)"]]
            grade_total = 0.0
            for s in students:
                rows.append([s["username"], f"{s['total_fee']:,.2f}",
                              f"{s['total_paid']:,.2f}", f"{s['balance_due']:,.2f}"])
                grade_total += s["balance_due"]
            grand_total += grade_total
            rows.append(["Grade Total", "", "", f"{grade_total:,.2f}"])
            t = Table(rows, colWidths=[7*cm, 3.5*cm, 3.5*cm, 3.5*cm])
            t.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#F5F7FA")]),
                ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#FFF3E0")),
                ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]))
            story.append(t)
            story.append(Spacer(1, 6*mm))

        story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceAfter=4))
        story.append(Paragraph(
            f"Grand Total Pending: Rs.{grand_total:,.2f}",
            ParagraphStyle("grand", parent=getSampleStyleSheet()["Normal"],
                           fontSize=12, fontName="Helvetica-Bold",
                           textColor=BRAND_PURPLE, alignment=2, spaceAfter=4)))

    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceBefore=10, spaceAfter=4))
    story.append(Paragraph("MIND FORGE | AI Assisted Learning — Confidential",
                            ParagraphStyle("footer", parent=getSampleStyleSheet()["Normal"],
                                           fontSize=8, textColor=colors.gray, alignment=1)))
    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


# ─── Report: Student Ledger ────────────────────────────────────────────────────

async def generate_student_ledger_report(student: Dict[str, Any], academic_year: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    _report_header(story, styles,
                   title=f"STUDENT FEE LEDGER — {academic_year}",
                   subtitle=f"Student: {student['username']}  |  Grade: {student['grade']}  |  Generated: {date.today().strftime('%d %B %Y')}")

    # ── Fee Breakdown ─────────────────────────────────────────────────────────
    fee_breakdown = student.get("fee_breakdown", [])
    if fee_breakdown:
        story.append(Paragraph("Fee Breakdown", styles["section_header"]))
        bd_rows = [["Description", "Amount (Rs.)"]]
        for item in fee_breakdown:
            bd_rows.append([item["label"], f"{item['amount']:,.2f}"])
        bd_rows.append(["Total Fee", f"{student['total_fee']:,.2f}"])
        bd_table = Table(bd_rows, colWidths=[12*cm, 5.5*cm])
        bd_table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("ALIGN", (1, 0), (1, -1), "RIGHT"),
            ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#F5F7FA")]),
            ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#EDE7F6")),
            ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]))
        story.append(bd_table)
        story.append(Spacer(1, 6*mm))

    # ── Summary ───────────────────────────────────────────────────────────────
    summary_data = [
        ["Total Fee", "Total Paid", "Balance Due"],
        [f"Rs.{student['total_fee']:,.2f}", f"Rs.{student['total_paid']:,.2f}", f"Rs.{student['balance_due']:,.2f}"],
    ]
    st = Table(summary_data, colWidths=[5.5*cm, 5.5*cm, 5.5*cm])
    st.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("BACKGROUND", (2, 1), (2, 1),
         colors.HexColor("#FFEBEE") if student["balance_due"] > 0 else colors.HexColor("#E8F5E9")),
        ("FONTNAME", (0, 1), (-1, 1), "Helvetica-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(st)
    story.append(Spacer(1, 6*mm))

    story.append(Paragraph("Payment History", styles["section_header"]))
    payments = student.get("payments", [])
    if not payments:
        story.append(Paragraph("No payments recorded.", styles["meta"]))
    else:
        pay_rows = [["#", "Date", "Amount (Rs.)", "Notes"]]
        for i, p in enumerate(payments, 1):
            paid_at = p.get("paid_at", "")
            if paid_at:
                try:
                    from datetime import datetime as _dt
                    paid_at = _dt.fromisoformat(paid_at).strftime("%d %b %Y")
                except Exception:
                    pass
            pay_rows.append([str(i), paid_at, f"{float(p['amount']):,.2f}", p.get("notes") or "—"])
        pt = Table(pay_rows, colWidths=[1*cm, 4*cm, 4*cm, 8.5*cm])
        pt.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("ALIGN", (2, 0), (2, -1), "RIGHT"),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F7FA")]),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))
        story.append(pt)

    story.append(Spacer(1, 6*mm))
    status_text = "FULLY PAID" if student["balance_due"] <= 0 else f"BALANCE DUE: Rs.{student['balance_due']:,.2f}"
    status_color = colors.HexColor("#2E7D32") if student["balance_due"] <= 0 else colors.HexColor("#B71C1C")
    story.append(Paragraph(status_text, ParagraphStyle("status", parent=getSampleStyleSheet()["Normal"],
                                                        fontSize=13, fontName="Helvetica-Bold",
                                                        textColor=status_color, alignment=1, spaceAfter=4)))
    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceBefore=10, spaceAfter=4))
    story.append(Paragraph("MIND FORGE | AI Assisted Learning — Confidential",
                            ParagraphStyle("footer", parent=getSampleStyleSheet()["Normal"],
                                           fontSize=8, textColor=colors.gray, alignment=1)))
    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes
