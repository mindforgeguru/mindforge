"""
Call-site tests for tenancy enforcement.

test_tenancy.py proves the guards behave correctly in isolation. It cannot
prove anything *calls* them — delete the `assert_school_active` line from
`_get_current_user` and every test in that file still passes while suspension
enforcement silently dies. That absence-of-a-call-site is exactly what bug #3
was: the helper logic was never wrong, it just never ran outside login.

So these drive the real dependency and the real refresh handler end to end,
with only the session and Redis faked.
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


def _db_returning(user):
    """AsyncSession stub whose single query yields `user`."""
    result = MagicMock()
    result.scalar_one_or_none = MagicMock(return_value=user)
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)
    return db


def _creds(token):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def _token_for(user):
    return create_access_token(
        data={"sub": str(user.id), "role": user.role, "school_id": user.school_id}
    )


@pytest.fixture(autouse=True)
def _neutralise_select(monkeypatch):
    """conftest stubs Base, so the models are never mapped and `select(User)`
    raises. The session is faked anyway, so the query object is irrelevant to
    what these tests assert — the guard, not the SQL.
    """
    import app.core.security as _sec
    import app.routers.auth as _auth

    monkeypatch.setattr(_sec, "select", lambda *a, **k: MagicMock())
    monkeypatch.setattr(_auth, "select", lambda *a, **k: MagicMock())


@pytest.fixture(autouse=True)
def _redis_allows_everything(monkeypatch):
    """No token is revoked; isolates these tests to the school check."""
    import app.core.redis_client as _rc
    import app.routers.auth as _auth

    fake = MagicMock()
    fake.is_access_jti_revoked = AsyncMock(return_value=False)
    fake.is_jti_revoked = AsyncMock(return_value=False)
    fake.revoke_jti = AsyncMock()
    # conftest injects this module straight into sys.modules, so it is not an
    # attribute of the app.core package and cannot be patched by dotted path.
    monkeypatch.setattr(_rc, "redis_manager", fake, raising=False)
    monkeypatch.setattr(_auth, "redis_manager", fake, raising=False)
    return fake


def _school_active(monkeypatch, active: bool):
    import app.core.cache as _cache

    monkeypatch.setattr(
        _cache, "is_school_active_cached", _passthrough(active), raising=False
    )


# ── The auth dependency every authenticated request passes through ────────────


@pytest.mark.asyncio
class TestGetCurrentUserEnforcesSuspension:
    async def test_active_school_is_allowed(self, monkeypatch):
        user = _FakeUser(school_id=2)
        _school_active(monkeypatch, True)
        got = await _get_current_user(_creds(_token_for(user)), _db_returning(user))
        assert got is user

    async def test_suspended_school_is_rejected(self, monkeypatch):
        # The regression that matters: a token minted while the school was
        # active must stop working once it is suspended.
        user = _FakeUser(school_id=2)
        _school_active(monkeypatch, False)
        with pytest.raises(HTTPException) as exc:
            await _get_current_user(_creds(_token_for(user)), _db_returning(user))
        assert exc.value.status_code == 403
        assert "suspended" in exc.value.detail.lower()

    async def test_owner_is_not_gated(self, monkeypatch):
        # school_id NULL. Gating the owner would make a suspension
        # unrecoverable — the console needed to undo it lives behind this
        # same dependency.
        owner = _FakeUser(user_id=99, school_id=None, role=UserRole.owner)
        _school_active(monkeypatch, False)
        got = await _get_current_user(_creds(_token_for(owner)), _db_returning(owner))
        assert got is owner

    async def test_unapproved_user_still_rejected(self, monkeypatch):
        # The new check must not have displaced the existing ones.
        user = _FakeUser(school_id=2)
        user.is_approved = False
        _school_active(monkeypatch, True)
        with pytest.raises(HTTPException) as exc:
            await _get_current_user(_creds(_token_for(user)), _db_returning(user))
        assert exc.value.status_code == 403
        assert "approval" in exc.value.detail.lower()

    async def test_missing_user_still_401(self, monkeypatch):
        _school_active(monkeypatch, True)
        with pytest.raises(HTTPException) as exc:
            await _get_current_user(
                _creds(_token_for(_FakeUser())), _db_returning(None)
            )
        assert exc.value.status_code == 401


# ── Refresh: the path that made the bypass unbounded ──────────────────────────
# Refresh does not go through _get_current_user, so it needs its own check.
# Without one, rotation hands out a fresh 30-day refresh token indefinitely and
# suspension never takes hold for anyone who stays logged in.


@pytest.mark.asyncio
class TestRefreshEnforcesSuspension:
    async def _call(self, user, monkeypatch, active):
        from fastapi import Response
        from app.routers.auth import refresh_access_token
        from app.schemas.user import RefreshRequest

        # auth.py binds the helper at import time, so patching it on
        # app.core.cache would not affect the name the handler actually calls.
        import app.routers.auth as _auth

        monkeypatch.setattr(
            _auth, "is_school_active_cached", _passthrough(active), raising=False
        )
        token = create_refresh_token(
            data={
                "sub": str(user.id),
                "role": user.role,
                "school_id": user.school_id,
            }
        )
        return await refresh_access_token(
            Response(), RefreshRequest(refresh_token=token), _db_returning(user)
        )

    async def test_suspended_school_cannot_refresh(self, monkeypatch):
        user = _FakeUser(school_id=2)
        with pytest.raises(HTTPException) as exc:
            await self._call(user, monkeypatch, active=False)
        assert exc.value.status_code == 401

    async def test_active_school_can_refresh(self, monkeypatch):
        user = _FakeUser(school_id=2)
        out = await self._call(user, monkeypatch, active=True)
        assert out.access_token and out.refresh_token

    async def test_owner_can_refresh_during_suspension(self, monkeypatch):
        owner = _FakeUser(user_id=99, school_id=None, role=UserRole.owner)
        out = await self._call(owner, monkeypatch, active=False)
        assert out.access_token


def _passthrough(active):
    async def _impl(school_id, db):
        return active

    return _impl
