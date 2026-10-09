"""
JWTs are signed and verified with PyJWT, not python-jose.

python-jose has had two incomplete fixes for the same algorithm-confusion bug
(CVE-2024-33663, then GHSA-3qf3-8w2g-rqmx / CVE-2026-85394) and no patched
release, and it is the only thing that pulled `ecdsa` (PYSEC-2026-1325) in.

The migration risk is the error path: the two libraries raise different
exception types, and every `except` around a decode must still catch them, or a
bad token turns into a 500 instead of a 401. These pin that, plus the iat
behaviour PyJWT validates and python-jose did not.
"""

import pathlib
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import timedelta
from unittest.mock import MagicMock

import jwt
import pytest
from fastapi import HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials

from app.core.security import (
    _get_current_user,
    create_access_token,
    create_refresh_token,
    decode_access_token,
)

BACKEND = pathlib.Path(__file__).resolve().parent.parent


# ── The library itself ────────────────────────────────────────────────────────


def test_decode_errors_are_pyjwt_errors():
    with pytest.raises(jwt.PyJWTError):
        decode_access_token("not.a.real.token")


def test_expired_token_raises_pyjwt_expiry():
    expired = create_access_token({"sub": "1"}, expires_delta=timedelta(hours=-1))
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_access_token(expired)


def test_fresh_token_with_subsecond_iat_verifies_immediately():
    # iat is a float on purpose (session revocation compares sub-second times).
    # PyJWT rejects an iat in the future; a token must verify the instant it is
    # minted, for both token types.
    assert decode_access_token(create_access_token({"sub": "5"}))["sub"] == "5"
    assert decode_access_token(create_refresh_token({"sub": "5"}))["type"] == "refresh"


def test_only_the_configured_algorithm_is_accepted():
    # alg=none and a different HMAC must both be refused: decode pins the list.
    payload = {"sub": "1", "type": "access"}
    unsigned = jwt.encode(payload, key=None, algorithm="none")
    with pytest.raises(jwt.PyJWTError):
        decode_access_token(unsigned)
    from app.core.config import settings
    other = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS512")
    with pytest.raises(jwt.PyJWTError):
        decode_access_token(other)


# ── Callers still answer 401 on a bad token ───────────────────────────────────


def _creds(token):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


@pytest.mark.asyncio
@pytest.mark.parametrize("token", [
    "garbage",
    "not.a.real.token",
    create_access_token({"sub": "1"}, expires_delta=timedelta(hours=-1)),
])
async def test_auth_dependency_rejects_bad_tokens_with_401(token):
    with pytest.raises(HTTPException) as exc:
        await _get_current_user(_creds(token), MagicMock())
    assert exc.value.status_code == 401


@pytest.mark.asyncio
@pytest.mark.parametrize("token", [
    "garbage",
    create_access_token({"sub": "1"}, expires_delta=timedelta(hours=-1)),
])
async def test_refresh_rejects_bad_tokens_with_401(token):
    from app.routers.auth import refresh_access_token
    from app.schemas.user import RefreshRequest

    with pytest.raises(HTTPException) as exc:
        await refresh_access_token(
            Response(), RefreshRequest(refresh_token=token), MagicMock()
        )
    assert exc.value.status_code == 401


# ── python-jose is gone ───────────────────────────────────────────────────────


def test_no_app_code_imports_python_jose():
    offenders = []
    for path in [BACKEND / "main.py", *(BACKEND / "app").rglob("*.py")]:
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if re.match(r"\s*(from|import)\s+jose\b", line):
                offenders.append(f"{path.relative_to(BACKEND)}:{n}")
    assert not offenders, offenders


def test_requirements_drop_python_jose_and_ecdsa():
    reqs = (BACKEND / "requirements.txt").read_text().lower()
    pins = {
        re.split(r"[\[=<>~ ]", line.strip(), maxsplit=1)[0]
        for line in reqs.splitlines()
        if line.strip() and not line.strip().startswith("#")
    }
    assert "python-jose" not in pins
    assert "ecdsa" not in pins
    assert "pyjwt" in pins
