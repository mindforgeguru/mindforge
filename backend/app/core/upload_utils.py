"""
Utilities for validating and sanitising user-uploaded images.

• Magic-byte check: only JPEG, PNG, and WebP are accepted.
• 5 MB size cap enforced before any processing.
• EXIF metadata stripped via Pillow (re-encodes as clean JPEG or PNG).
"""

import io
import zipfile

from fastapi import HTTPException, UploadFile, status
from PIL import Image

_MAX_BYTES = 5 * 1024 * 1024  # 5 MB

# Decompression-bomb guard: cap how many pixels Pillow will decode. A small
# (< 5 MB) file can still expand to an enormous bitmap and exhaust memory in
# img.load(); above this limit Pillow raises Image.DecompressionBombError,
# which validate_and_strip_exif's except-block turns into a clean 400. 40 MP
# (~ a 7300×5500 photo) is far more than any avatar needs.
Image.MAX_IMAGE_PIXELS = 40_000_000


def reject_if_oversize(file: UploadFile, max_bytes: int = _MAX_BYTES) -> None:
    """Reject an upload by its *declared* size before buffering it.

    UploadFile.size comes from the multipart part's Content-Length; when the
    client sends it (browsers and the Flutter client do) this lets us 413 a
    huge file without reading the whole body into memory first. It's a
    best-effort gate — size can be None or understated — so the post-read
    length check in validate_and_strip_exif remains the source of truth."""
    if file.size is not None and file.size > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large. Maximum allowed size is "
                   f"{max_bytes // (1024 * 1024)} MB.",
        )

# (offset, magic_bytes, label, pil_format, output_ext)
_SIGNATURES = [
    (0, b"\xff\xd8\xff",        "JPEG",  "JPEG", "jpg"),
    (0, b"\x89PNG\r\n\x1a\n",  "PNG",   "PNG",  "png"),
    (0, b"RIFF",               "WebP",  "WEBP", "webp"),  # bytes[8:12] == b"WEBP" checked below
]


def validate_and_strip_exif(raw: bytes, original_filename: str) -> tuple[bytes, str]:
    """
    Validate raw image bytes and return (clean_bytes, extension).

    Raises HTTP 400 if the file is too large, not a supported image type,
    or cannot be decoded by Pillow.
    """
    if len(raw) > _MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Image too large. Maximum allowed size is 5 MB.",
        )

    # Magic-byte check
    detected = None
    for offset, magic, label, pil_fmt, ext in _SIGNATURES:
        if raw[offset:offset + len(magic)] == magic:
            if label == "WebP" and raw[8:12] != b"WEBP":
                continue
            detected = (label, pil_fmt, ext)
            break

    if detected is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported file type. Only JPEG, PNG, and WebP images are accepted.",
        )

    label, pil_fmt, ext = detected

    # Decode with Pillow (catches truncated / malformed files)
    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File could not be read as a valid image.",
        )

    # Convert palette/transparency modes so JPEG re-encode works
    if pil_fmt == "JPEG" and img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    # Re-encode without metadata — this is the EXIF strip
    buf = io.BytesIO()
    save_kwargs: dict = {"format": pil_fmt}
    if pil_fmt == "JPEG":
        save_kwargs["quality"] = 92
        save_kwargs["optimize"] = True
    img.save(buf, **save_kwargs)

    return buf.getvalue(), ext


# ─── Document validation ──────────────────────────────────────────────────────
#
# Images above are validated by magic bytes. Documents were not: the PDF path in
# presentations.py trusted `content_type` or the filename extension, and the
# knowledge-base path in database_router.py checked neither. Both are claims the
# *client* makes, so a caller that lies passes either one.
#
# This decides from the bytes. It deliberately does not re-encode — unlike an
# avatar, a chapter PDF has to reach the AI pipeline byte-identical.

# (label, offset, signature, canonical extension)
_DOC_SIGNATURES = [
    ("PDF",  0, b"%PDF-",              "pdf"),
    # .pptx/.docx/.xlsx are ZIP/OOXML containers. Matching the ZIP local-file
    # header proves it is a container, not that it is a *deck* — the caller is
    # expected to parse it afterwards, which presentations.py already does.
    ("ZIP",  0, b"PK\x03\x04",         "pptx"),
    ("PNG",  0, b"\x89PNG\r\n\x1a\n",  "png"),
    ("JPEG", 0, b"\xff\xd8\xff",       "jpg"),
    ("WebP", 0, b"RIFF",               "webp"),
]

_EXT_LABELS = {
    "pdf": "PDF", "pptx": "PowerPoint (.pptx)",
    "png": "PNG", "jpg": "JPEG", "webp": "WebP",
}


def validate_document(
    raw: bytes,
    original_filename: str,
    allowed_exts: set[str],
) -> str:
    """Identify an upload from its bytes and confirm the caller allows that type.

    Returns the canonical extension ("pdf", "pptx", "png", "jpg", "webp").

    Raises 422 when the body is empty, and 415 when the content is
    unidentifiable or is a type the endpoint does not accept.

    `original_filename` is accepted for symmetry with validate_and_strip_exif
    and for logging, but is deliberately **not** used to decide the type and
    never appears in an error message — it is attacker-controlled.
    """
    if not raw:
        # Literal 422 rather than status.HTTP_422_* — starlette 1.x deprecated
        # the ENTITY spelling, and the routers here already use the literal.
        raise HTTPException(status_code=422, detail="Uploaded file is empty.")

    wanted = ", ".join(
        sorted(_EXT_LABELS.get(e, e.upper()) for e in allowed_exts)
    )

    detected = None
    for label, offset, sig, ext in _DOC_SIGNATURES:
        if raw[offset:offset + len(sig)] == sig:
            # WebP writes "RIFF" then a 4-byte size then "WEBP"; without the
            # second check any RIFF container (.wav, .avi) would pass as an
            # image.
            if ext == "webp" and raw[8:12] != b"WEBP":
                continue
            detected = ext
            break

    if detected is None or detected not in allowed_exts:
        # The message names what was expected, never what was received: echoing
        # the sniffed type back is a free oracle, and echoing the filename would
        # reflect attacker-controlled text into whatever renders the error.
        raise HTTPException(
            status_code=415,
            detail=f"That file isn't a valid {wanted}. Check the file and try again.",
        )

    return detected


# ─── Zip / OOXML decompression-bomb guard ─────────────────────────────────────
#
# A .pptx is a ZIP archive. The size cap in presentations.py bounds the *file*,
# not what it expands to: DEFLATE reaches ~1000:1 on repetitive data, so a 50 MB
# upload that passes every byte check can still unpack to tens of gigabytes. The
# _MAX_SLIDES cap in pptx_service runs only after python-pptx has opened and
# buffered the archive, which is exactly the step a bomb blows up. This must run
# before that.
#
# The check is cheap: a ZIP records each entry's uncompressed size in its
# central directory, so summing them and looking at the compression ratio reads
# metadata only — nothing is decompressed. That is also why it is trustworthy
# for exactly one thing (spotting a bomb) and not another: the sizes are the
# archive's own claims, so this proves an upload *isn't* absurd, never that a
# small one is safe.

# A genuine teaching deck is mostly already-compressed media (JPEG/PNG barely
# shrink) plus small XML, so its overall ratio sits in single digits. A bomb is
# runs of zeros or repeated bytes and inflates by three orders of magnitude, so
# ratio is the discriminating signal and the absolute cap is the backstop for a
# bomb spread thinly across many low-ratio entries.
_MAX_UNCOMPRESSED_BYTES = 300 * 1024 * 1024  # 300 MB unpacked, summed
_MAX_COMPRESSION_RATIO = 120                  # per entry, above a size floor
_RATIO_FLOOR_BYTES = 1 * 1024 * 1024          # ignore ratio on tiny entries


def reject_if_zip_bomb(
    raw: bytes,
    *,
    max_uncompressed: int = _MAX_UNCOMPRESSED_BYTES,
    max_ratio: int = _MAX_COMPRESSION_RATIO,
) -> None:
    """Reject a ZIP/OOXML upload that would expand to an unreasonable size.

    Reads the archive's central directory only — no entry is decompressed.
    Raises 413 when the declared unpacked total exceeds ``max_uncompressed`` or
    any entry above a 1 MB floor claims a compression ratio over ``max_ratio``.
    Raises 415 when the bytes are not a readable ZIP at all, so a mislabelled or
    truncated upload fails here with a clean status rather than deeper in the
    parser.

    The ratio floor matters: a few hundred bytes of XML that compress 500:1 is
    normal and harmless, so the ratio rule only applies once an entry is large
    enough for that ratio to represent real unpacked bytes.
    """
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as zf:
            infos = zf.infolist()
    except zipfile.BadZipFile as exc:
        raise HTTPException(
            status_code=415,
            detail="That file isn't a readable PowerPoint (.pptx). "
                   "Check the file and try again.",
        ) from exc

    total_uncompressed = 0
    for info in infos:
        total_uncompressed += info.file_size
        if total_uncompressed > max_uncompressed:
            # Message names a size, never the ratio or the offending entry: the
            # entry name is attacker-controlled and the ratio is a free oracle
            # for tuning a bomb that just squeaks under the limit.
            raise HTTPException(
                status_code=413,
                detail="That PowerPoint file unpacks to far more than expected "
                       "and was rejected.",
            )
        if info.file_size >= _RATIO_FLOOR_BYTES and info.compress_size > 0:
            if info.file_size // info.compress_size > max_ratio:
                raise HTTPException(
                    status_code=413,
                    detail="That PowerPoint file unpacks to far more than "
                           "expected and was rejected.",
                )
