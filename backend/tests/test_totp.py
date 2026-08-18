"""
TOTP core, checked against RFC 6238's own test vectors.

Implemented from the RFC rather than pulled from PyPI. That is a deliberate
trade: TOTP is HMAC-SHA1 over a time counter plus the RFC 4226 truncation, about
forty lines of stdlib, and Wave 1 was spent shrinking the dependency surface of
an app holding minors' data. It is not "rolling your own crypto" in the
dangerous sense — the construction is fully specified and comes with official
vectors, which is exactly what makes it safe to implement and what this file
checks.

Vectors are RFC 6238 Appendix B, the SHA1 rows: seed "12345678901234567890",
8 digits, 30-second step. Any implementation that reproduces all six is doing
the counter, the HMAC and the dynamic truncation correctly.
"""

import pytest

from app.core.totp import (
    generate_secret,
    provisioning_uri,
    totp_at,
    verify_totp,
)

# ASCII seed from the RFC, as raw bytes.
RFC_SEED = b"12345678901234567890"

# (unix time, expected 8-digit TOTP)
RFC_VECTORS = [
    (59, "94287082"),
    (1111111109, "07081804"),
    (1111111111, "14050471"),
    (1234567890, "89005924"),
    (2000000000, "69279037"),
    (20000000000, "65353130"),
]


class TestRFC6238Vectors:
    @pytest.mark.parametrize("when,expected", RFC_VECTORS)
    def test_matches_the_published_vector(self, when, expected):
        assert totp_at(RFC_SEED, when, digits=8) == expected


class TestCodeShape:
    def test_default_is_six_digits(self):
        code = totp_at(RFC_SEED, 59)
        assert len(code) == 6 and code.isdigit()

    def test_leading_zeros_are_preserved(self):
        # 07081804 starts with a zero. Formatting the code as an int would drop
        # it and lock the user out roughly one time in ten.
        assert totp_at(RFC_SEED, 1111111109, digits=8).startswith("0")


class TestVerification:
    def test_accepts_the_current_code(self):
        now = 1234567890
        assert verify_totp(RFC_SEED, totp_at(RFC_SEED, now), now=now) is True

    def test_rejects_a_wrong_code(self):
        assert verify_totp(RFC_SEED, "000000", now=1234567890) is False

    def test_accepts_the_previous_step(self):
        # Clocks drift and people type slowly. One step either side is the
        # standard allowance; without it, a code entered at second 29 fails.
        now = 1234567890
        earlier = totp_at(RFC_SEED, now - 30)
        assert verify_totp(RFC_SEED, earlier, now=now) is True

    def test_accepts_the_next_step(self):
        now = 1234567890
        later = totp_at(RFC_SEED, now + 30)
        assert verify_totp(RFC_SEED, later, now=now) is True

    def test_rejects_a_code_two_steps_old(self):
        # The window must not be generous. Two steps is 60+ seconds of replay.
        now = 1234567890
        stale = totp_at(RFC_SEED, now - 90)
        assert verify_totp(RFC_SEED, stale, now=now) is False

    @pytest.mark.parametrize("junk", ["", "abcdef", "12345", "1234567", "  1234", None])
    def test_malformed_input_is_rejected_not_raised(self, junk):
        # This is reached straight from a request body. It must return False,
        # never raise, or a malformed code becomes a 500 instead of a 401.
        assert verify_totp(RFC_SEED, junk, now=1234567890) is False


class TestSecrets:
    def test_generated_secret_is_base32_and_long_enough(self):
        s = generate_secret()
        # 160 bits is the RFC 4226 recommendation; base32 of 20 bytes is 32
        # characters.
        assert len(s) >= 32
        assert set(s) <= set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")

    def test_secrets_differ(self):
        assert len({generate_secret() for _ in range(20)}) == 20


class TestProvisioningURI:
    def test_uri_is_the_shape_authenticator_apps_expect(self):
        uri = provisioning_uri("demo_admin", "JBSWY3DPEHPK3PXP")
        assert uri.startswith("otpauth://totp/")
        assert "secret=JBSWY3DPEHPK3PXP" in uri
        assert "issuer=MIND%20FORGE" in uri or "issuer=MIND+FORGE" in uri

    def test_username_is_url_encoded(self):
        # Usernames are not guaranteed URI-safe, and an unescaped one silently
        # produces a QR code that scans into the wrong account.
        uri = provisioning_uri("a b/c", "JBSWY3DPEHPK3PXP")
        assert " " not in uri.split("?")[0]
        assert "a b/c" not in uri
