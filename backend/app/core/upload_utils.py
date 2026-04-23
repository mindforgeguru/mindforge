"""
Utilities for validating and sanitising user-uploaded images.

• Magic-byte check: only JPEG, PNG, and WebP are accepted.
• 5 MB size cap enforced before any processing.
• EXIF metadata stripped via Pillow (re-encodes as clean JPEG or PNG).
"""

import io

from fastapi import HTTPException, status
from PIL import Image

_MAX_BYTES = 5 * 1024 * 1024  # 5 MB

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
