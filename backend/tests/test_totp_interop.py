"""
TOTP interoperability — the "am I just marking my own homework?" test.

tests/test_totp.py already proves the app's TOTP matches RFC 6238's own
published vectors, so the algorithm is correct against an external authority.
What it does not do is check the app against a *different implementation*, which
is what a real authenticator app is.

This file adds that. It carries a second, independently-written RFC 6238/4226
routine (classic byte-shift truncation, not the app's struct.unpack form),
anchors that routine to the RFC's published vector so it is itself trustworthy,
then shows the two implementations agree — both on the raw secret and, crucially,
on the secret parsed out of the actual `otpauth://` QR URI. A real authenticator
app is one more RFC-6238 implementation reading that same URI, so this closes the
interop question down to a literal phone scan (checklist item 06), which is a
formality rather than an open correctness risk.
"""

import base64
import hashlib
import hmac
import struct
from urllib.parse import parse_qs, unquote, urlparse

from app.core.totp import (
    STEP_SECONDS,
    generate_secret,
    provisioning_uri,
    totp_at,
    verify_totp,
)


def independent_totp(secret_b32: str, when: int, digits: int = 6, step: int = 30) -> str:
    """A second, from-scratch TOTP. Deliberately not sharing code with the app:
    if both were wrong the same way they would have to share this exact bug, and
    the RFC-vector anchor below rules that out."""
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8), casefold=True)
    counter = when // step
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    off = mac[-1] & 0x0F
    bincode = (
        (mac[off] & 0x7F) << 24
        | (mac[off + 1] & 0xFF) << 16
        | (mac[off + 2] & 0xFF) << 8
        | (mac[off + 3] & 0xFF)
    )
    return str(bincode % (10 ** digits)).zfill(digits)


# RFC 6238 Appendix B, SHA1, T=59 → 8-digit 94287082. Anchoring the independent
# routine to the same external ground truth the app is checked against.
RFC_SECRET_B32 = base64.b32encode(b"12345678901234567890").decode()

FIXED_NOW = 1_700_000_000  # deterministic instant, mid-step


class TestIndependentRoutineIsTrustworthy:
    def test_matches_the_rfc_vector(self):
        assert independent_totp(RFC_SECRET_B32, 59, digits=8) == "94287082"


class TestTwoImplementationsAgree:
    def test_same_code_for_the_same_secret_and_time(self):
        secret = generate_secret()
        assert totp_at(secret, FIXED_NOW) == independent_totp(secret, FIXED_NOW)

    def test_app_accepts_a_code_made_by_the_independent_impl(self):
        secret = generate_secret()
        code = independent_totp(secret, FIXED_NOW)
        assert verify_totp(secret, code, now=FIXED_NOW) is True

    def test_they_agree_across_several_time_windows(self):
        secret = generate_secret()
        for t in (0, 59, FIXED_NOW, FIXED_NOW + STEP_SECONDS, 2_000_000_000):
            assert totp_at(secret, t) == independent_totp(secret, t)


class TestScanTheQrEndToEnd:
    """Simulates the real flow: parse the otpauth URI a phone would scan, have an
    independent generator produce a code from it, and confirm the server accepts
    that code."""

    def _params(self, secret):
        uri = provisioning_uri("alice.smith", secret)
        parsed = urlparse(uri)
        assert parsed.scheme == "otpauth"
        assert parsed.netloc == "totp"
        return parsed, {k: v[0] for k, v in parse_qs(parsed.query).items()}

    def test_uri_is_a_spec_compliant_sha1_6_digit_30s_code(self):
        _, q = self._params(generate_secret())
        assert q["algorithm"] == "SHA1"
        assert q["digits"] == "6"
        assert q["period"] == str(STEP_SECONDS)
        assert q["issuer"] == "MIND FORGE"

    def test_label_is_percent_encoded_issuer_and_user(self):
        parsed, _ = self._params(generate_secret())
        # otpauth://totp/<label> — label is issuer:user, percent-encoded.
        assert unquote(parsed.path.lstrip("/")) == "MIND FORGE:alice.smith"

    def test_secret_from_the_qr_produces_a_code_the_server_accepts(self):
        secret = generate_secret()
        _, q = self._params(secret)
        # An authenticator app reads exactly this secret out of the QR.
        scanned_secret = q["secret"]
        assert scanned_secret == secret
        code = independent_totp(scanned_secret, FIXED_NOW)
        assert verify_totp(secret, code, now=FIXED_NOW) is True
