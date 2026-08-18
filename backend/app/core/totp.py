"""
TOTP (RFC 6238) over HOTP (RFC 4226), using only the standard library.

Implemented rather than depended on. TOTP is HMAC-SHA1 over a time counter plus
the RFC 4226 dynamic truncation — a fully specified construction that ships with
official test vectors, which `tests/test_totp.py` checks all six of. Against
that, adding a PyPI package to an app holding minors' data, right after Wave 1
was spent shrinking exactly that surface, is the worse trade.

SHA1 is correct here and not a weakness: HMAC-SHA1 is unbroken, and it is what
every authenticator app implements. Choosing SHA256 would be marginally stronger
in theory and unscannable by Google Authenticator in practice.
"""

import base64
import hashlib
import hmac
import secrets
import struct
import time
import urllib.parse
from typing import Optional

# 30 seconds is the RFC default and what every authenticator app assumes.
STEP_SECONDS = 30

# How many steps either side of "now" are accepted. One step covers clock drift
# and a person typing slowly; two would mean a code stays replayable for over a
# minute.
ALLOWED_DRIFT_STEPS = 1

ISSUER = "MIND FORGE"


def generate_secret() -> str:
    """A fresh base32 secret, 160 bits as RFC 4226 recommends."""
    return base64.b32encode(secrets.token_bytes(20)).decode()


def _decode_secret(secret) -> Optional[bytes]:
    """Accept either raw bytes or a base32 string; None if it is neither."""
    if isinstance(secret, bytes):
        return secret
    if not isinstance(secret, str):
        return None
    try:
        # Authenticator apps strip padding, so restore it before decoding.
        padded = secret + "=" * (-len(secret) % 8)
        return base64.b32decode(padded, casefold=True)
    except Exception:
        return None


def totp_at(secret, when: Optional[int] = None, digits: int = 6) -> str:
    """The TOTP code for `secret` at unix time `when` (default: now)."""
    key = _decode_secret(secret)
    if key is None:
        raise ValueError("secret must be bytes or a base32 string")

    counter = int((when if when is not None else time.time()) // STEP_SECONDS)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()

    # RFC 4226 dynamic truncation: the low nibble of the last byte picks the
    # 4-byte window, and the top bit is masked off to keep it positive.
    offset = digest[-1] & 0x0F
    code = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFF_FFFF

    # zfill matters: a code of 81804 is "081804", and formatting it as an int
    # would lock the user out roughly one attempt in ten.
    return str(code % (10 ** digits)).zfill(digits)


def verify_totp(secret, code, now: Optional[int] = None, digits: int = 6) -> bool:
    """True if `code` is valid for `secret` now, within the drift window.

    Returns False for anything malformed rather than raising — this is reached
    straight from a request body, and a junk code must be a 401, not a 500.
    """
    if not isinstance(code, str):
        return False
    code = code.strip()
    if len(code) != digits or not code.isdigit():
        return False
    if _decode_secret(secret) is None:
        return False

    now = int(now if now is not None else time.time())
    for drift in range(-ALLOWED_DRIFT_STEPS, ALLOWED_DRIFT_STEPS + 1):
        candidate = totp_at(secret, now + drift * STEP_SECONDS, digits)
        # compare_digest so a wrong code cannot be narrowed down by timing.
        if hmac.compare_digest(candidate, code):
            return True
    return False


def provisioning_uri(username: str, secret: str) -> str:
    """otpauth:// URI for the QR code an authenticator app scans.

    Both the label and the issuer are percent-encoded: usernames are not
    guaranteed URI-safe, and an unescaped one produces a QR that scans into the
    wrong account rather than failing visibly.
    """
    label = urllib.parse.quote(f"{ISSUER}:{username}", safe="")
    query = urllib.parse.urlencode({
        "secret": secret,
        "issuer": ISSUER,
        "algorithm": "SHA1",
        "digits": 6,
        "period": STEP_SECONDS,
    })
    return f"otpauth://totp/{label}?{query}"
