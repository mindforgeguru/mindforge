"""K-17: Hindi (Devanagari) and Gujarati names in report PDFs.

DejaVu Sans has neither script, so names such as आरव_शर्मा printed as black
boxes. pdf_service registers Noto Sans Devanagari/Gujarati, switches font per
script run, and has ReportLab shape the runs through HarfBuzz so conjuncts and
matras are correct. Latin text keeps its font and plain table cells stay raw.

Like test_pdf_injection.py these need the real reportlab + uharfbuzz, so they
skip in the stubbed unit env; run them in the mindforge_backend container.
"""

import asyncio

import pytest

try:
    import uharfbuzz  # noqa: F401 — in requirements.txt, so CI and the image have it
    from app.services import pdf_service as P
except Exception:  # pragma: no cover - env-dependent
    pytest.skip(
        "reportlab/uharfbuzz unavailable (stubbed in the unit env); run in the backend container",
        allow_module_level=True,
    )

NAMES = ["आरव_शर्मा", "આરવ", "Ab & Cd", "<b>bold", "Ab_आरव"]
SCHOOL = {"name": "श्री विद्या मंदिर", "logo": None}


def test_indic_support_is_active():
    # Fonts registered and uharfbuzz importable — otherwise names regress to boxes.
    assert P._INDIC_OK


# ── run splitting / escaping ─────────────────────────────────────────────────

def test_latin_text_is_only_escaped():
    assert P._safe("Ab & Cd") == "Ab &amp; Cd"
    assert P._safe("<b>bold") == "&lt;b&gt;bold"


def test_indic_runs_get_noto_faces():
    assert P._safe("आरव_शर्मा") == '<font face="NotoSansDevanagari">आरव_शर्मा</font>'
    assert P._safe("આરવ") == '<font face="NotoSansGujarati">આરવ</font>'
    # Latin keeps DejaVu; user markup next to an Indic run is still escaped.
    assert P._safe("<b>आरव & Co") == (
        '&lt;b&gt;<font face="NotoSansDevanagari">आरव </font>&amp; Co')


def test_plain_cells_stay_raw_and_indic_cells_become_paragraphs():
    assert P._cell("Ab & Cd") == "Ab & Cd"
    assert P._cell("<b>bold") == "<b>bold"
    cell = P._cell("आरव_शर्मा")
    assert isinstance(cell, P._RLParagraph)
    assert cell.style.shaping


# ── shaping ──────────────────────────────────────────────────────────────────

def _drawn(text, style_font=None):
    """Lay the paragraph out and return it with the (fontName, text) runs the
    canvas will draw — after shaping, the text holds glyphs, not code points."""
    from reportlab.lib.styles import ParagraphStyle
    style = ParagraphStyle("t", fontName=style_font or P._FONT, fontSize=10)
    para = P.Paragraph(P._safe(text), style)
    para.wrap(400, 400)
    runs = [(f.fontName, f.text) for line in para.blPara.lines for f in line.words]
    return para, runs


@pytest.mark.parametrize("text, face", [
    ("क्षत्रिय", "NotoSansDevanagari"),     # conjunct + pre-base matra
    ("आरव_शर्मा", "NotoSansDevanagari"),    # reph (र्म) + underscore inside the run
    ("ક્ષિતિજ", "NotoSansGujarati"),
])
def test_indic_runs_are_shaped(text, face):
    _, runs = _drawn(text)
    assert [f for f, _t in runs] == [face]
    # HarfBuzz reordered/ligated the glyphs; a plain cmap lookup would draw
    # the input code points one by one (broken conjuncts, matra on the wrong side).
    assert runs[0][1] != text


def test_mixed_script_word_keeps_each_font():
    """ReportLab shapes a word with its first fragment's font; the per-font
    split must keep the Devanagari part in Noto (else: boxes)."""
    _, runs = _drawn("Ab_आरव")
    assert runs == [(P._FONT, "Ab_"), ("NotoSansDevanagari", "आरव")]


def test_bold_style_uses_bold_noto():
    _, runs = _drawn("आरव", style_font=P._BOLD)
    assert [f for f, _t in runs] == ["NotoSansDevanagari-Bold"]


def test_helvetica_style_still_shapes():
    # The report footer is Helvetica-based; ReportLab only shapes when the
    # style's base font is a shapable TTF, so the wrapper swaps it to DejaVu.
    para, runs = _drawn("विद्या", style_font="Helvetica")
    assert para.style.shaping
    assert P.pdfmetrics.getFont(para.style.fontName).shapable
    assert runs[0][1] != "विद्या"


def test_latin_only_paragraph_is_not_shaped():
    from reportlab.lib.styles import ParagraphStyle
    style = ParagraphStyle("t", fontName=P._FONT, fontSize=10)
    assert P.Paragraph("Ab &amp; Cd", style).style is style


# ── the real reports ─────────────────────────────────────────────────────────

def _pdf_text(pdf: bytes) -> str:
    import fitz  # pymupdf, a backend dependency
    with fitz.open(stream=pdf, filetype="pdf") as doc:
        return "".join(page.get_text() for page in doc)


def _check_report(pdf: bytes):
    assert pdf[:5] == b"%PDF-"
    # Both Noto faces are embedded (subset names end in the PostScript name).
    assert b"NotoSansDevanagari" in pdf
    assert b"NotoSansGujarati" in pdf
    text = _pdf_text(pdf)
    # Latin names print literally — not escaped, not parsed as markup.
    assert "Ab & Cd" in text and "<b>bold" in text
    assert "&amp;" not in text and "&lt;" not in text


def test_attendance_report_renders_indic_names():
    rows = [{"student": n, "present": 9, "absent": 1, "percent": 90.0, "low": False}
            for n in NAMES]
    _check_report(asyncio.run(P.generate_attendance_report(rows, 8, "Nov 2026", school=SCHOOL)))


def test_pending_fees_report_renders_indic_names():
    rows = [{"username": n, "grade": 8, "total_fee": 1000.0, "total_paid": 400.0,
             "balance_due": 600.0} for n in NAMES]
    _check_report(asyncio.run(P.generate_pending_fees_report(rows, "2026-27", school=SCHOOL)))
