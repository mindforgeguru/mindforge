"""
What the bearer dependency must refuse even though the signature is valid.

Two holes found by driving the live local stack on 2026-10-10, both in
`_get_current_user`, the one dependency every authenticated request passes:

  * A refresh token was accepted as an access token. It is signed with the same
    key and carries the same `sub`, so nothing rejected it — which turned the
    60-minute access lifetime into 30 days. Worse, logout and rotation revoke a
    refresh token in a *different* Redis namespace from the one this dependency
    checks, so a refresh token that `/auth/refresh` already refused still worked
    as a bearer.
  * A deactivated account kept working on any token it already held. Login and
    `/auth/refresh` both check `is_active`; the per-request dependency did not.

The WebSocket authenticates on its own (`main._ws_account_allows`); its
deactivation check is pinned in test_websocket_auth.py, which carries the stubs
`main` needs to import.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.core.security import (
    _get_current_user,
    create_access_token,
    create_refresh_token,
)
from app.models.user import UserRole


class _FakeUser:
    """Enough of the User ORM object for these paths."""

    def __init__(self, user_id=1, school_id=2, role=UserRole.teacher):
        self.id = user_id
        self.username = "tester"
        self.school_id = school_id
        self.role = role
        self.is_approved = True
        self.is_active = True
        self.deleted_at = None
        self.tokens_valid_after = None


def _db_returning(user):
    result = MagicMock()
    result.scalar_one_or_none = MagicMock(return_value=user)
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)
    return db


def _creds(token):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def _claims(user):
    return {"sub": str(user.id), "role": user.role, "school_id": user.school_id}


@pytest.fixture(autouse=True)
def _isolate(monkeypatch):
    """Fake the query, Redis and the school lookup: nothing is revoked and the
    school is active, so the only thing that can refuse a token is the gate
    under test."""
    import app.core.cache as _cache
    import app.core.redis_client as _rc
    import app.core.security as _sec

    monkeypatch.setattr(_sec, "select", lambda *a, **k: MagicMock())

    fake = MagicMock()
    fake.is_access_jti_revoked = AsyncMock(return_value=False)
    monkeypatch.setattr(_rc, "redis_manager", fake, raising=False)

    async def _active(school_id, db):
        return True

    monkeypatch.setattr(_cache, "is_school_active_cached", _active, raising=False)


@pytest.mark.asyncio
class TestBearerGate:
    async def test_access_token_for_a_live_account_is_accepted(self):
        user = _FakeUser()
        token = create_access_token(data=_claims(user))
        assert await _get_current_user(_creds(token), _db_returning(user)) is user

    async def test_refresh_token_is_not_an_access_token(self):
        user = _FakeUser()
        token = create_refresh_token(data=_claims(user))
        with pytest.raises(HTTPException) as exc:
            await _get_current_user(_creds(token), _db_returning(user))
        assert exc.value.status_code == 401

    async def test_deactivated_account_is_refused_on_a_live_token(self):
        # 401, not 403: the client's answer to 401 is to try a refresh, which
        # also refuses a deactivated account, and so it signs out cleanly.
        user = _FakeUser()
        user.is_active = False
        token = create_access_token(data=_claims(user))
        with pytest.raises(HTTPException) as exc:
            await _get_current_user(_creds(token), _db_returning(user))
        assert exc.value.status_code == 401
