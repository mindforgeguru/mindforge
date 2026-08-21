"""
Decompression-bomb guard for .pptx uploads.

A PowerPoint file is a ZIP archive. The upload endpoint caps the *file* at
50 MB and checks its first four bytes, but nothing bounded what the archive
expands to — DEFLATE reaches ~1000:1 on runs of zeros, so a small, valid-looking
deck can unpack to tens of gigabytes and exhaust memory the instant python-pptx
opens it. The _MAX_SLIDES cap in pptx_service runs only *after* that open, so it
never gets a turn.

These tests build real archives (nothing is monkeypatched or mocked) and pin
`reject_if_zip_bomb`: it fires on a bomb, stays out of the way of a genuine
deck, and reads the central directory only — it must not decompress anything.
"""

import io
import zipfile

import pytest
from fastapi import HTTPException

from app.core.upload_utils import reject_if_zip_bomb


def _zip_with(entries: dict[str, bytes], compression=zipfile.ZIP_DEFLATED) -> bytes:
    """Build a real ZIP from {name: uncompressed_bytes}."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression) as zf:
        for name, body in entries.items():
            zf.writestr(name, body)
    return buf.getvalue()


class TestRejectsBombs:
    def test_high_ratio_single_entry_is_rejected(self):
        # 100 MB of zeros compresses to ~100 KB — a ~1000:1 ratio, and the
        # signature of a bomb. It sits under the 300 MB absolute cap, so this
        # exercises the *ratio* rule specifically, not the total.
        bomb = _zip_with({"ppt/slides/slide1.xml": b"\x00" * (100 * 1024 * 1024)})
        assert len(bomb) < 1024 * 1024  # the whole upload is under a megabyte
        with pytest.raises(HTTPException) as exc:
            reject_if_zip_bomb(bomb)
        assert exc.value.status_code == 413

    def test_total_uncompressed_over_cap_is_rejected(self):
        # The backstop for a bomb spread across many low-ratio entries so no
        # single ratio looks alarming — the *sum* is what catches it. Built from
        # incompressible bytes (ratio ~1) so the ratio rule stays silent and the
        # total rule is the one on trial; the cap is lowered so the test stays
        # cheap rather than allocating 300 MB.
        import os
        entries = {f"ppt/media/img{i}.bin": os.urandom(2 * 1024 * 1024) for i in range(4)}
        deck = _zip_with(entries, compression=zipfile.ZIP_STORED)  # 8 MB unpacked
        with pytest.raises(HTTPException) as exc:
            reject_if_zip_bomb(deck, max_uncompressed=5 * 1024 * 1024, max_ratio=10_000)
        assert exc.value.status_code == 413

    def test_error_message_names_no_entry_and_no_ratio(self):
        # The entry name is attacker-controlled and the ratio is a tuning
        # oracle; neither may appear in the response.
        bomb = _zip_with({"../../etc/passwd": b"\x00" * (100 * 1024 * 1024)})
        with pytest.raises(HTTPException) as exc:
            reject_if_zip_bomb(bomb)
        detail = exc.value.detail.lower()
        assert "passwd" not in detail
        assert "ratio" not in detail
        assert "1000" not in detail and "1024" not in detail


class TestAllowsGenuineDecks:
    def test_ordinary_deck_passes(self):
        # A real deck is small XML plus already-compressed media, so its overall
        # ratio is low and its total modest. Simulate that: a few MB of
        # incompressible bytes (media) and some small text (XML).
        import os
        media = os.urandom(3 * 1024 * 1024)  # ~incompressible, like an embedded JPEG
        deck = _zip_with({
            "ppt/media/image1.jpg": media,
            "ppt/slides/slide1.xml": b"<p:sld>hello</p:sld>",
            "ppt/presentation.xml": b"<p:presentation/>",
        })
        reject_if_zip_bomb(deck)  # must not raise

    def test_small_highly_compressible_xml_is_not_a_bomb(self):
        # A slide with a lot of repeated whitespace compresses hard, but it is
        # far under the 1 MB ratio floor, so the ratio rule must ignore it —
        # otherwise every tidy XML file trips the guard.
        deck = _zip_with({"ppt/slides/slide1.xml": b" " * 4000})
        reject_if_zip_bomb(deck)  # must not raise


class TestRejectsNonZip:
    def test_non_zip_bytes_get_a_clean_415(self):
        # Reached only after the endpoint's PK-magic check, but the guard is
        # public and must not raise a raw BadZipFile at a future caller.
        with pytest.raises(HTTPException) as exc:
            reject_if_zip_bomb(b"%PDF-1.7 not a zip at all")
        assert exc.value.status_code == 415
