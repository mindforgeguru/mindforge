"""
A rupee sign in a question prints as ₹, not as a box.

The PDFs used ReportLab's built-in Helvetica, which has no ₹ — and rupee
amounts are in half the maths word problems a school sets. "Price ₹500" came
out as "Price I500" (found 2026-10-18). The service now uses DejaVu Sans when
it is installed (the image installs fonts-dejavu-core).
"""

import asyncio
import os

import pytest

DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
fitz = pytest.importorskip("fitz")

pytestmark = pytest.mark.skipif(not os.path.exists(DEJAVU), reason="DejaVu Sans not installed")

QUESTIONS = [{"id": 1, "type": "short_answer", "marks": 2, "answer": "₹450",
              "question": "A shirt costs ₹500 and is sold at 10% off. What is the price?"}]


def _text(pdf_bytes):
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    return "".join(page.get_text() for page in doc)


@pytest.mark.parametrize("which", ["generate_offline_test_pdf", "generate_answer_key_pdf"])
def test_the_rupee_sign_survives(which):
    from app.services import pdf_service

    pdf = asyncio.run(getattr(pdf_service, which)(QUESTIONS, "Percentages", grade=8, subject="maths"))
    text = _text(pdf)
    assert "₹500" in text, text[:400]
