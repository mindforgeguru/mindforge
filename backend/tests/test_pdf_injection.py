"""K-17: content shown in generated PDFs must be inert.

reportlab's Paragraph parses intra-paragraph markup (<b>, <font>, <img ...>),
so AI/teacher-supplied question text, options, titles and match columns are an
injection surface: an <img src="http://169.254.169.254/..."> would attempt a
fetch (SSRF), and an unbalanced tag or </para> would raise and break PDF
generation (DoS). `_safe` escapes &, < and > so every such string reaches
reportlab as literal text. These tests lock that in.
"""

import pytest

# The unit-test env stubs reportlab (a fake module without `colors`), so
# importing pdf_service fails there. These are integration checks that need the
# real reportlab (present in the backend container) — skip the whole module when
# it isn't, rather than erroring at collection.
try:
    from app.services.pdf_service import _safe
except Exception:  # pragma: no cover - env-dependent
    pytest.skip(
        "reportlab unavailable (stubbed in the unit env); run in the backend container",
        allow_module_level=True,
    )


# ── the escape itself ────────────────────────────────────────────────────────

@pytest.mark.parametrize("payload", [
    '<img src="http://169.254.169.254/latest/meta-data">',
    "<script>alert(1)</script>",
    '<font color="red">x</font>',
    "</para><img src=x onerror=1>",
    "<unichar code='99'/>",
])
def test_markup_is_neutralised(payload):
    out = _safe(payload)
    # No live angle brackets survive, so reportlab sees text, not tags.
    assert "<" not in out and ">" not in out
    assert "&lt;" in out and "&gt;" in out


def test_ampersand_and_none_are_handled():
    assert _safe("a & b") == "a &amp; b"
    assert _safe(None) == ""          # missing field, not the string "None"
    assert _safe(123) == "123"


# ── the full generators survive a payload and emit a valid PDF ───────────────

@pytest.mark.asyncio
async def test_generators_do_not_crash_on_injection():
    reportlab = pytest.importorskip("reportlab")  # noqa: F841
    from app.services import pdf_service as P

    questions = [
        {"type": "mcq",
         "question": '<img src="http://169.254.169.254/x">Q? <script>alert(1)</script>',
         "options": {"A": '<font color="red">x</font>', "B": "& < >", "C": "c", "D": "d"},
         "answer": "A", "marks": 1,
         "explanation": '</para><img src=x onerror=1>'},
        {"type": "match_following", "question": "Match <b>these</b>",
         "column_a": ['<img src=x>', "two"], "column_b": ["<script>", "2"],
         "answer": "A-1", "marks": 2},
    ]
    paper = await P.generate_offline_test_pdf(
        questions, '<img src="x">Exam & "Title"', grade=8,
        subject="<script>Sci</script>", total_marks=3, time_limit_minutes=30,
    )
    key = await P.generate_answer_key_pdf(
        questions, '<img src="x">Exam', grade=8, subject="Sci", total_marks=3,
    )
    # Valid PDFs, not a reportlab traceback — the escaped payload was inert.
    assert paper[:5] == b"%PDF-" and len(paper) > 1000
    assert key[:5] == b"%PDF-" and len(key) > 1000
