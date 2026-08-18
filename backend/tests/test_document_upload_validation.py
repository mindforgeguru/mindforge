"""
Content-based validation for document uploads.

Images have been validated by magic bytes since `upload_utils.py` was written.
Documents were not: the PDF path in `presentations.py` accepted anything whose
`content_type` header or filename looked right, and the knowledge-base path in
`database_router.py` checked neither. Both are header/filename claims made by
the client, so neither survives a caller that simply lies.

These tests pin the behaviour of `validate_document`, which decides from the
bytes.
"""

import pytest
from fastapi import HTTPException

from app.core.upload_utils import validate_document


# Minimal but genuine headers. A real PDF starts "%PDF-" and a real OOXML deck
# is a ZIP, so its first four bytes are the local-file-header signature.
PDF_BYTES = b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<< >>\nendobj\n"
ZIP_BYTES = b"PK\x03\x04" + b"\x00" * 26
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 24


class TestAcceptsGenuineFiles:
    def test_accepts_pdf(self):
        assert validate_document(PDF_BYTES, "chapter.pdf", {"pdf"}) == "pdf"

    def test_accepts_zip_container_when_pptx_allowed(self):
        assert validate_document(ZIP_BYTES, "deck.pptx", {"pptx"}) == "pptx"

    def test_accepts_image_when_images_allowed(self):
        # The knowledge base takes scanned answer sheets as images as well as
        # PDFs, so the same validator has to cover both.
        assert validate_document(PNG_BYTES, "scan.png", {"pdf", "png", "jpg"}) == "png"
        assert validate_document(JPEG_BYTES, "scan.jpg", {"pdf", "png", "jpg"}) == "jpg"

    def test_extension_does_not_have_to_match_content(self):
        # Content decides. A PDF named .txt is still a PDF, and the caller asked
        # for PDFs, so this is fine — the filename is not evidence either way.
        assert validate_document(PDF_BYTES, "chapter.txt", {"pdf"}) == "pdf"


class TestRejectsSpoofedFiles:
    def test_rejects_executable_renamed_to_pdf(self):
        # The case the old header check could not catch: correct extension,
        # correct content_type, wrong bytes.
        payload = b"\x7fELF\x02\x01\x01" + b"\x00" * 32
        with pytest.raises(HTTPException) as exc:
            validate_document(payload, "invoice.pdf", {"pdf"})
        assert exc.value.status_code == 415

    def test_rejects_script_renamed_to_pdf(self):
        payload = b"#!/bin/sh\nrm -rf /\n"
        with pytest.raises(HTTPException) as exc:
            validate_document(payload, "notes.pdf", {"pdf"})
        assert exc.value.status_code == 415

    def test_rejects_type_that_is_real_but_not_allowed(self):
        # A genuine PNG offered where only PDFs are accepted.
        with pytest.raises(HTTPException) as exc:
            validate_document(PNG_BYTES, "x.pdf", {"pdf"})
        assert exc.value.status_code == 415

    def test_rejects_empty_body(self):
        with pytest.raises(HTTPException) as exc:
            validate_document(b"", "empty.pdf", {"pdf"})
        assert exc.value.status_code == 422

    def test_rejects_body_too_short_to_identify(self):
        with pytest.raises(HTTPException) as exc:
            validate_document(b"%P", "truncated.pdf", {"pdf"})
        assert exc.value.status_code == 415


class TestErrorsAreActionable:
    def test_message_names_what_was_expected(self):
        with pytest.raises(HTTPException) as exc:
            validate_document(b"\x7fELF\x02" + b"\x00" * 32, "x.pdf", {"pdf"})
        # The uploader needs to know what to do differently, so the allowed
        # types belong in the message. No stack detail, no echo of the bytes.
        assert "PDF" in exc.value.detail
        assert "ELF" not in exc.value.detail

    def test_message_does_not_leak_the_filename_back(self):
        # Filenames are attacker-controlled; echoing one into a response body
        # invites reflection games in whatever renders the error.
        nasty = "<script>alert(1)</script>.pdf"
        with pytest.raises(HTTPException) as exc:
            validate_document(b"garbage-not-a-pdf-at-all", nasty, {"pdf"})
        assert "<script>" not in exc.value.detail
