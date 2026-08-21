"""
JWT lifetime and expiry.

Two failure modes matter: an access token that never expires (a leaked token is
then valid forever), and a token whose expiry the server doesn't actually
enforce. These pin the exp claim on both token types, the type/jti markers, and
that an expired token is rejected on decode.

Times come from the stubbed settings in conftest (access 30 min, refresh 30
days); the assertions use those values, so they track the config rather than a
hardcoded copy of it.
"""

from datetime import datetime, timedelta, timezone

import pytest
from jose import jwt
from jose.exceptions import ExpiredSignatureError

from app.core.config import settings
from app.core.security import create_access_token, create_refresh_token

SECRET = settings.JWT_SECRET
ALG = settings.JWT_ALGORITHM


def _claims(token):
    # verify_exp off so we can inspect the exp value itself without it tripping.
    return jwt.decode(token, SECRET, algorithms=[ALG], options={"verify_exp": False})


def _seconds_from_now(exp_ts):
    return exp_ts - datetime.now(timezone.utc).timestamp()


class TestAccessToken:
    def test_carries_subject_type_and_unique_jti(self):
        c = _claims(create_access_token({"sub": "42"}))
        assert c["sub"] == "42"
        assert c["type"] == "access"
        assert c["jti"]

    def test_expires_at_the_configured_minutes(self):
        c = _claims(create_access_token({"sub": "42"}))
        expected = settings.JWT_EXPIRE_MINUTES * 60
        assert abs(_seconds_from_now(c["exp"]) - expected) < 30  # ~30 min, small slack

    def test_two_tokens_have_different_jtis(self):
        a = _claims(create_access_token({"sub": "42"}))
        b = _claims(create_access_token({"sub": "42"}))
        assert a["jti"] != b["jti"]

    def test_explicit_expiry_override_is_honoured(self):
        c = _claims(create_access_token({"sub": "42"}, expires_delta=timedelta(seconds=5)))
        assert _seconds_from_now(c["exp"]) < 10


class TestRefreshToken:
    def test_is_long_lived_and_typed(self):
        c = _claims(create_refresh_token({"sub": "42"}))
        assert c["type"] == "refresh"
        assert c["jti"]
        expected = settings.JWT_REFRESH_EXPIRE_DAYS * 86400
        assert abs(_seconds_from_now(c["exp"]) - expected) < 3600  # ~30 days, 1h slack

    def test_refresh_outlives_access(self):
        acc = _claims(create_access_token({"sub": "42"}))
        ref = _claims(create_refresh_token({"sub": "42"}))
        assert ref["exp"] > acc["exp"]


class TestExpiryIsEnforced:
    def test_an_expired_token_is_rejected_on_decode(self):
        # Mint a token that expired an hour ago and confirm a real verifying
        # decode refuses it — proving exp is honoured, not merely present.
        expired = create_access_token({"sub": "42"}, expires_delta=timedelta(hours=-1))
        with pytest.raises(ExpiredSignatureError):
            jwt.decode(expired, SECRET, algorithms=[ALG])

    def test_a_live_token_verifies(self):
        live = create_access_token({"sub": "42"})
        assert jwt.decode(live, SECRET, algorithms=[ALG])["sub"] == "42"
