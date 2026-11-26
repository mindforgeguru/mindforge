"""
PDF Generation Service using ReportLab.
Generates printable offline test papers with MIND FORGE branding.
"""

import io
import logging
from app.core.school_time import school_today
from pathlib import Path
from typing import Any, Dict, List, Optional
from xml.sax.saxutils import escape as _xml_escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm, mm
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (
    HRFlowable, Image, Paragraph as _RLParagraph, SimpleDocTemplate, Spacer, Table, TableStyle
)


# ── Fonts ─────────────────────────────────────────────────────────────────────
# ReportLab's built-in Helvetica has no ₹, so "Price ₹500" printed as
# "Price I500" — and rupee amounts are in half the maths word problems a school
# sets. DejaVu Sans has it; the image installs fonts-dejavu-core. Where it is
# missing (a bare dev machine) the built-ins are used, as before. DejaVu's
# oblique face is not in -core, so italic styles use the regular face.
_FONT, _BOLD, _ITALIC = "Helvetica", "Helvetica-Bold", "Helvetica-Oblique"
_DEJAVU_DIR = "/usr/share/fonts/truetype/dejavu"
try:
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    pdfmetrics.registerFont(TTFont("DejaVuSans", f"{_DEJAVU_DIR}/DejaVuSans.ttf"))
    pdfmetrics.registerFont(TTFont("DejaVuSans-Bold", f"{_DEJAVU_DIR}/DejaVuSans-Bold.ttf"))
    _FONT, _BOLD, _ITALIC = "DejaVuSans", "DejaVuSans-Bold", "DejaVuSans"
except Exception:  # noqa: BLE001 — fonts are a nicety; never fail the import
    logging.getLogger(__name__).info("DejaVu Sans not found; PDFs use Helvetica")

logger = logging.getLogger(__name__)


# ── Indic scripts (K-17) ──────────────────────────────────────────────────────
# Usernames and school names may be Hindi (Devanagari) or Gujarati, and DejaVu
# has neither script, so names printed as black boxes. Noto Sans Devanagari /
# Gujarati (OFL, vendored in app/assets/fonts) carry the glyphs, and ReportLab
# >= 4.4 shapes them through HarfBuzz (uharfbuzz) so conjuncts and matras
# (क्ष, र्म, ि) come out right — a plain glyph map draws them broken.
#
# Neither Noto face has Latin letters, so text is split into runs: Indic runs
# (plus the digits, spaces and punctuation between them) use Noto; everything
# else keeps DejaVu and its current look. Shaping is switched on only for a
# Paragraph that actually holds an Indic run, so Latin-only output is unchanged.
_FONT_DIR = Path(__file__).resolve().parent.parent / "assets" / "fonts"
# script -> (first codepoint, last codepoint, regular face, bold face)
_INDIC = {
    "deva": (0x0900, 0x097F, "NotoSansDevanagari", "NotoSansDevanagari-Bold"),
    "gujr": (0x0A80, 0x0AFF, "NotoSansGujarati", "NotoSansGujarati-Bold"),
}
_INDIC_OK = False
try:
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    for _lo, _hi, _reg, _bold in _INDIC.values():
        pdfmetrics.registerFont(TTFont(_reg, str(_FONT_DIR / f"{_reg}-Regular.ttf")))
        pdfmetrics.registerFont(TTFont(_bold, str(_FONT_DIR / f"{_bold}.ttf")))
    # Shaping needs uharfbuzz; without it Noto would still draw broken
    # conjuncts, so treat the scripts as unsupported rather than half-working.
    _INDIC_OK = bool(pdfmetrics.getFont("NotoSansDevanagari").shapable)
    if not _INDIC_OK:
        logger.warning("uharfbuzz unavailable; Hindi/Gujarati text in PDFs will not be shaped")
except Exception:  # noqa: BLE001 — fonts are a nicety; never fail the import
    logger.warning("Noto Indic fonts not registered; Hindi/Gujarati text in PDFs will show as boxes")


def _install_per_font_shaping() -> None:
    """ReportLab shapes a whole word with its *first* fragment's font, so a
    word mixing scripts with no space ("aarav_शर्मा") got DejaVu glyph ids for
    its Devanagari and printed boxes. Split such a word into same-font pieces,
    shape each with ReportLab's own function, and join them back. Words in a
    single font (all text before K-17) take the original path untouched."""
    from reportlab.platypus import paragraph as _rl_para
    from reportlab.pdfbase.ttfonts import ShapedFragWord, makeShapedFragWord

    original = _rl_para.shapeFragWord
    if getattr(original, "_mindforge_per_font", False):
        return

    def shape(w, *args, **kwargs):
        if isinstance(w, ShapedFragWord):
            return w
        items = w[1:]
        if (len({getattr(f, "fontName", None) for f, _ in items}) <= 1
                or any(hasattr(f, "cbDefn") for f, _ in items)):
            return original(w, *args, **kwargs)
        pieces, cur = [], []
        for item in items:
            if cur and cur[-1][0].fontName != item[0].fontName:
                pieces.append(cur)
                cur = []
            cur.append(item)
        pieces.append(cur)
        out = []
        for piece in pieces:
            width = sum(pdfmetrics.stringWidth(s, f.fontName, f.fontSize) for f, s in piece)
            out.append(original(w.__class__([width] + piece), *args, **kwargs))
        return makeShapedFragWord(w)([sum(p[0] for p in out)] + [it for p in out for it in p[1:]])

    shape._mindforge_per_font = True
    _rl_para.shapeFragWord = shape


if _INDIC_OK:
    _install_per_font_shaping()

# Characters both DejaVu and the Noto faces draw: they stay inside an Indic
# run instead of breaking it (a run boundary mid-word splits HarfBuzz's view
# of the cluster). Danda (। ॥) is in the Devanagari block but used by both.
_NEUTRAL = set("0123456789 _-.,:;!?'\"()[]{}/\\|+*=%#~^") | {"\u0964", "\u0965"}


def _script_of(ch: str) -> Optional[str]:
    if ch in _NEUTRAL:
        return None                       # joins whichever run it sits in
    cp = ord(ch)
    for name, (lo, hi, _r, _b) in _INDIC.items():
        if lo <= cp <= hi:
            return name
    return "latn"


def _has_indic(text: str) -> bool:
    return _INDIC_OK and any(_script_of(c) in _INDIC for c in text)


def _script_runs(text: str) -> List[tuple]:
    """Split text into (script, chunk) runs; neutral characters join the run
    they follow (or, at the start, the run they precede)."""
    runs: List[list] = []
    for ch in text:
        sc = _script_of(ch)
        if sc is None or (runs and runs[-1][0] == sc):
            if runs:
                runs[-1][1] += ch
            else:
                runs.append([None, ch])
            continue
        if runs and runs[-1][0] is None:  # leading neutrals: adopt this script
            runs[-1][0] = sc
            runs[-1][1] += ch
        else:
            runs.append([sc, ch])
    return [(sc or "latn", chunk) for sc, chunk in runs]


def _safe(value: Any) -> str:
    """Escape user/AI-supplied text before it goes into a ReportLab Paragraph.

    Paragraph parses an intra-paragraph XML/HTML markup (``<b>``, ``<font>``,
    ``<img>`` …). Question text, options, titles and names originate from
    AI generation or teacher/student input, so a stray ``<`` / ``&`` would
    break PDF rendering and a tag such as ``<img src=...>`` could be injected.
    Escaping neutralises that while leaving the intentional literal markup
    elsewhere in this module untouched.

    After escaping, Hindi/Gujarati runs are wrapped in a ``<font face>`` tag of
    our own (never user text, which is already inert) so they draw in Noto.
    """
    text = "" if value is None else str(value)
    if not _has_indic(text):
        return _xml_escape(text)
    out = []
    for sc, chunk in _script_runs(text):
        if sc in _INDIC:
            out.append(f'<font face="{_INDIC[sc][2]}">{_xml_escape(chunk)}</font>')
        else:
            out.append(_xml_escape(chunk))
    return "".join(out)


def Paragraph(text: str, style, *args, **kwargs):  # noqa: N802 — drop-in for ReportLab's
    """ReportLab Paragraph that shapes Indic runs tagged by `_safe`.

    A ``<font face>`` tag resets bold, so on a bold style the Noto faces are
    swapped for their bold cuts. Shaping is turned on only when such a run is
    present; Latin-only paragraphs are built exactly as before.
    """
    if _INDIC_OK and '<font face="Noto' in text:
        bold = "bold" in (style.fontName or "").lower()
        if bold:
            for _lo, _hi, reg, bold_face in _INDIC.values():
                text = text.replace(f'<font face="{reg}">', f'<font face="{bold_face}">')
        # ReportLab only shapes when the style's own font is a shapable TTF;
        # a Helvetica-based style (the footer) would leave matras misplaced.
        overrides = {"shaping": 1}
        if not getattr(pdfmetrics.getFont(style.fontName), "shapable", False):
            overrides["fontName"] = _BOLD if bold else _FONT
        style = ParagraphStyle(f"{style.name}-shaped", parent=style, **overrides)
    return _RLParagraph(text, style, *args, **kwargs)


def _cell(value: Any, size: float = 9):
    """A Table cell for user text. Plain strings are drawn as-is (not parsed as
    markup), so a Latin name stays a raw, unescaped string — escaping it
    printed "Ab & Cd" as "Ab &amp; Cd". Table cells can't switch fonts or
    shape, so a name with Hindi/Gujarati becomes a Paragraph over `_safe`
    text, which still prints "&" and "<b>" literally. Its Latin runs use
    Helvetica, the font ReportLab draws the other (plain) body cells in."""
    text = "" if value is None else str(value)
    if not _has_indic(text):
        return text
    return Paragraph(f'<font face="Helvetica">{_safe(text)}</font>', ParagraphStyle(
        "cell", fontName=_FONT, fontSize=size, leading=size * 1.3))


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
            fontName=_BOLD,
            textColor=BRAND_PURPLE,
            spaceAfter=2,
            alignment=1,  # center
        ),
        "tagline": ParagraphStyle(
            "tagline",
            parent=base["Normal"],
            fontSize=10,
            fontName=_ITALIC,
            textColor=BRAND_GOLD,
            spaceAfter=6,
            alignment=1,
        ),
        "test_title": ParagraphStyle(
            "test_title",
            parent=base["Heading1"],
            fontSize=16,
            fontName=_BOLD,
            textColor=BRAND_BLUE,
            spaceAfter=4,
            alignment=1,
        ),
        "section_header": ParagraphStyle(
            "section_header",
            parent=base["Heading2"],
            fontSize=12,
            fontName=_BOLD,
            textColor=BRAND_PURPLE,
            spaceBefore=10,
            spaceAfter=4,
        ),
        "question": ParagraphStyle(
            "question",
            parent=base["Normal"],
            fontSize=11,
            fontName=_BOLD,
            spaceBefore=8,
            spaceAfter=2,
            leftIndent=0,
        ),
        "option": ParagraphStyle(
            "option",
            parent=base["Normal"],
            fontSize=10,
            fontName=_FONT,
            leftIndent=20,
            spaceAfter=1,
        ),
        "answer_line": ParagraphStyle(
            "answer_line",
            parent=base["Normal"],
            fontSize=10,
            fontName=_FONT,
            textColor=colors.gray,
            leftIndent=0,
            spaceBefore=4,
            spaceAfter=8,
        ),
        "meta": ParagraphStyle(
            "meta",
            parent=base["Normal"],
            fontSize=10,
            fontName=_FONT,
            alignment=1,
        ),
        "instructions": ParagraphStyle(
            "instructions",
            parent=base["Normal"],
            fontSize=9,
            fontName=_ITALIC,
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
    story.append(Paragraph(_safe(test_title.upper()), styles["test_title"]))
    meta_items = []
    if grade:
        meta_items.append(f"Grade: {grade}")
    if subject:
        meta_items.append(f"Subject: {_safe(subject)}")
    if total_marks:
        meta_items.append(f"Total Marks: {int(total_marks)}")
    if time_limit_minutes:
        meta_items.append(f"Time Allowed: {time_limit_minutes} minutes")
    meta_items.append(f"Date: {school_today().strftime('%d %B %Y')}")

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
        ("FONT", (0, 0), (-1, -1), _FONT, 10),
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
            fontName=_FONT,
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
            q_text = f"Q{q_counter}. {_safe(q.get('question', ''))}  [{marks_label}]{_source_tag(q)}"
            story.append(Paragraph(q_text, styles["question"]))

            if q_type == "mcq" and q.get("options"):
                opts = q["options"]
                for key in ("A", "B", "C", "D"):
                    if key in opts:
                        story.append(Paragraph(f"({key}) {_safe(opts[key])}", styles["option"]))
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
                    a_val = f"({letters[i]})  {_safe(col_a[i])}" if i < len(col_a) else ""
                    b_val = f"({i+1})  {_safe(col_b[i])}" if i < len(col_b) else ""
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
        fontName=_BOLD,
        textColor=colors.HexColor("#2E7D32"),
        leftIndent=20,
        spaceAfter=6,
    )
    explanation_style = ParagraphStyle(
        "explanation",
        parent=base["Normal"],
        fontSize=9,
        fontName=_ITALIC,
        textColor=colors.HexColor("#1565C0"),
        leftIndent=20,
        spaceAfter=8,
    )
    confidential_style = ParagraphStyle(
        "confidential",
        parent=base["Normal"],
        fontSize=11,
        fontName=_BOLD,
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
    story.append(Paragraph(_safe(test_title.upper()), styles["test_title"]))
    meta_items = []
    if grade:
        meta_items.append(f"Grade: {grade}")
    if subject:
        meta_items.append(f"Subject: {_safe(subject)}")
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
            q_text = f"Q{q_counter}. {_safe(q.get('question', ''))}  [{marks} mark{'s' if marks > 1 else ''}]"
            story.append(Paragraph(q_text, styles["question"]))

            # Show options for MCQ
            if q_type == "mcq" and q.get("options"):
                opts = q["options"]
                for key in ("A", "B", "C", "D"):
                    if key in opts:
                        story.append(Paragraph(f"({key}) {_safe(opts[key])}", styles["option"]))

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
                    a_val = f"({letters[i]})  {_safe(col_a[i])}" if i < len(col_a) else ""
                    b_val = f"({i+1})  {_safe(col_b[i])}" if i < len(col_b) else ""
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
            story.append(Paragraph(f"✓ Answer: {_safe(answer)}", answer_style))

            # Explanation if available
            if q.get("explanation"):
                story.append(Paragraph(f"Explanation: {_safe(q['explanation'])}", explanation_style))

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
# Reports go to parents, boards and auditors as the school's own documents, so
# they carry the school's name and logo (#28). `school` is {"name", "logo"}
# with the logo as image bytes or None; without it they fall back to MindForge.

def _logo_flowable(logo: Optional[bytes]):
    if not logo:
        return None
    try:
        # Uploaded logos are often full-size photos; embedding one as-is made
        # every report ~5 MB. 400 px is plenty for an 18 mm header.
        from PIL import Image as PILImage
        with PILImage.open(io.BytesIO(logo)) as img:
            img = img.convert("RGBA") if img.mode in ("P", "LA") else img
            img.thumbnail((400, 400))
            small = io.BytesIO()
            if img.mode == "RGBA":
                img.save(small, format="PNG", optimize=True)
            else:
                img.convert("RGB").save(small, format="JPEG", quality=85)
        reader = ImageReader(io.BytesIO(small.getvalue()))
        w, h = reader.getSize()
        height = 18 * mm
        return Image(io.BytesIO(small.getvalue()), width=height * w / h, height=height)
    except Exception:  # noqa: BLE001 — an unreadable logo must not sink the report
        logger.warning("School logo could not be drawn on a report; skipped.")
        return None


def _report_header(story: list, styles: dict, title: str, subtitle: str,
                   school: Optional[Dict[str, Any]] = None) -> None:
    if school and school.get("name"):
        logo = _logo_flowable(school.get("logo"))
        if logo is not None:
            story.append(logo)
            story.append(Spacer(1, 2 * mm))
        story.append(Paragraph(_safe(school["name"]), styles["brand_title"]))
    else:
        story.append(Paragraph("MIND FORGE", styles["brand_title"]))
        story.append(Paragraph("AI Assisted Learning", styles["tagline"]))
    story.append(HRFlowable(width="100%", thickness=2, color=BRAND_PURPLE, spaceAfter=6))
    story.append(Paragraph(_safe(title), styles["test_title"]))
    story.append(Paragraph(_safe(subtitle), styles["meta"]))
    story.append(Spacer(1, 4 * mm))


def _report_footer(story: list, school: Optional[Dict[str, Any]] = None) -> None:
    text = (f"{_safe(school['name'])} — Confidential · Generated with MindForge"
            if school and school.get("name")
            else "MIND FORGE | AI Assisted Learning — Confidential")
    story.append(HRFlowable(width="100%", thickness=1, color=BRAND_PURPLE, spaceBefore=10, spaceAfter=4))
    story.append(Paragraph(text, ParagraphStyle("footer", parent=getSampleStyleSheet()["Normal"],
                                                fontSize=8, textColor=colors.gray, alignment=1)))


# ─── Report: Pending Fees (grade-wise) ────────────────────────────────────────

async def generate_pending_fees_report(summaries: List[Dict[str, Any]], academic_year: str,
                                       school: Optional[Dict[str, Any]] = None) -> bytes:
    from collections import defaultdict
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    _report_header(story, styles,
                   title=f"PENDING FEES REPORT — {academic_year}",
                   subtitle=f"Generated on {school_today().strftime('%d %B %Y')}",
                   school=school)

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
                rows.append([_cell(s["username"]), f"{s['total_fee']:,.2f}",
                              f"{s['total_paid']:,.2f}", f"{s['balance_due']:,.2f}"])
                grade_total += s["balance_due"]
            grand_total += grade_total
            rows.append(["Grade Total", "", "", f"{grade_total:,.2f}"])
            t = Table(rows, colWidths=[7*cm, 3.5*cm, 3.5*cm, 3.5*cm])
            t.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), _BOLD),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#F5F7FA")]),
                ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#FFF3E0")),
                ("FONTNAME", (0, -1), (-1, -1), _BOLD),
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
                           fontSize=12, fontName=_BOLD,
                           textColor=BRAND_PURPLE, alignment=2, spaceAfter=4)))

    _report_footer(story, school)
    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


# ─── Report: Student Ledger ────────────────────────────────────────────────────

async def generate_student_ledger_report(student: Dict[str, Any], academic_year: str,
                                         school: Optional[Dict[str, Any]] = None) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    _report_header(story, styles,
                   title=f"STUDENT FEE LEDGER — {academic_year}",
                   subtitle=f"Student: {student['username']}  |  Grade: {student['grade']}  |  Generated: {school_today().strftime('%d %B %Y')}",
                   school=school)

    # ── Fee Breakdown ─────────────────────────────────────────────────────────
    fee_breakdown = student.get("fee_breakdown", [])
    if fee_breakdown:
        story.append(Paragraph("Fee Breakdown", styles["section_header"]))
        bd_rows = [["Description", "Amount (Rs.)"]]
        for item in fee_breakdown:
            bd_rows.append([_cell(item["label"], 10), f"{item['amount']:,.2f}"])
        bd_rows.append(["Total Fee", f"{student['total_fee']:,.2f}"])
        bd_table = Table(bd_rows, colWidths=[12*cm, 5.5*cm])
        bd_table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), _BOLD),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("ALIGN", (1, 0), (1, -1), "RIGHT"),
            ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#F5F7FA")]),
            ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#EDE7F6")),
            ("FONTNAME", (0, -1), (-1, -1), _BOLD),
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
        ("FONTNAME", (0, 0), (-1, 0), _BOLD),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("BACKGROUND", (2, 1), (2, 1),
         colors.HexColor("#FFEBEE") if student["balance_due"] > 0 else colors.HexColor("#E8F5E9")),
        ("FONTNAME", (0, 1), (-1, 1), _BOLD),
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
            pay_rows.append([str(i), paid_at, f"{float(p['amount']):,.2f}", _cell(p.get("notes") or "—")])
        pt = Table(pay_rows, colWidths=[1*cm, 4*cm, 4*cm, 8.5*cm])
        pt.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), _BOLD),
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
                                                        fontSize=13, fontName=_BOLD,
                                                        textColor=status_color, alignment=1, spaceAfter=4)))
    _report_footer(story, school)
    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


# ─── Reports: attendance and marks (#28) ──────────────────────────────────────

def _report_table(rows: list, col_widths: list, highlight_rows=()) -> Table:
    # User text arrives via _cell: a raw string (drawn as-is, never escaped)
    # or, for a Hindi/Gujarati name, a shaped Paragraph.
    t = Table(rows, colWidths=col_widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), BRAND_BLUE),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), _BOLD),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F7FA")]),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    for r in highlight_rows:
        style.append(("BACKGROUND", (0, r), (-1, r), colors.HexColor("#FFEBEE")))
    t.setStyle(TableStyle(style))
    return t


def _pct(value: Optional[float]) -> str:
    return "—" if value is None else f"{value:.1f}%"


def _build(story: list) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


async def generate_attendance_report(rows: List[Dict[str, Any]], grade: int, period: str,
                                     school: Optional[Dict[str, Any]] = None,
                                     low_percent: float = 75.0) -> bytes:
    """Per-student attendance for one grade; rows from report_math.attendance_rows."""
    styles = _get_styles()
    story: list = []
    _report_header(story, styles,
                   title=f"ATTENDANCE REPORT — GRADE {grade}",
                   subtitle=f"{period}  |  Generated on {school_today().strftime('%d %B %Y')}",
                   school=school)
    if not rows:
        story.append(Paragraph("No students in this grade.", styles["meta"]))
    else:
        table = [["Student", "Periods present", "Periods absent", "Attendance"]]
        low = []
        for i, r in enumerate(rows, 1):
            table.append([_cell(r["student"]), str(r["present"]), str(r["absent"]), _pct(r["percent"])])
            if r["low"]:
                low.append(i)
        story.append(_report_table(table, [7*cm, 3.5*cm, 3.5*cm, 3.5*cm], low))
        story.append(Spacer(1, 4*mm))
        story.append(Paragraph(
            f"{len(low)} of {len(rows)} student(s) below {low_percent:.0f}% attendance (shaded).",
            styles["meta"]))
    _report_footer(story, school)
    return _build(story)


async def generate_marks_report(by_subject: Dict[str, List[Dict[str, Any]]],
                                overall: List[Dict[str, Any]], grade: int, period: str,
                                school: Optional[Dict[str, Any]] = None) -> bytes:
    """Marks per subject and overall for one grade; from report_math.marks_rows."""
    styles = _get_styles()
    story: list = []
    _report_header(story, styles,
                   title=f"MARKS REPORT — GRADE {grade}",
                   subtitle=f"{period}  |  Generated on {school_today().strftime('%d %B %Y')}",
                   school=school)
    if not by_subject:
        story.append(Paragraph("No marks recorded for this grade in this period.", styles["meta"]))
    else:
        story.append(Paragraph("Overall", styles["section_header"]))
        table = [["Student", "Marks", "Out of", "Percentage"]]
        for r in overall:
            table.append([_cell(r["student"]), f"{r['obtained']:g}", f"{r['max']:g}", _pct(r["percent"])])
        story.append(_report_table(table, [7*cm, 3.5*cm, 3.5*cm, 3.5*cm]))
        for subject, rows in by_subject.items():
            story.append(Spacer(1, 6*mm))
            story.append(Paragraph(_safe(subject), styles["section_header"]))
            table = [["Student", "Tests", "Marks", "Out of", "Percentage"]]
            for r in rows:
                table.append([_cell(r["student"]), str(r["tests"]), f"{r['obtained']:g}",
                              f"{r['max']:g}", _pct(r["percent"])])
            story.append(_report_table(table, [6*cm, 2*cm, 3*cm, 3*cm, 3.5*cm]))
    _report_footer(story, school)
    return _build(story)
