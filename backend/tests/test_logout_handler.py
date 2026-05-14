"""
Handler-level unit test for the logout endpoint.
Verifies that logout() sets current_user.fcm_token = None and calls db.commit().
No network, no database, no Redis required.

Run: cd backend && python3 -m pytest tests/test_logout_handler.py -v
"""

import asyncio
import sys
import os
from types import ModuleType
from unittest.mock import AsyncMock, MagicMock, patch

# ── Minimal stubs (override conftest.py's Base stub with a real class) ─────────
# conftest.py uses Base=MagicMock() which can't be subclassed. We need a real
# class so that SQLAlchemy model classes (User, etc.) can be imported.

def _stub(name: str, **attrs) -> ModuleType:
    m = ModuleType(name)
    for k, v in attrs.items():
        setattr(m, k, v)
    sys.modules[name] = m
    return m


_stub("asyncpg")
_stub("minio", Minio=MagicMock(), error=ModuleType("minio.error"))
_stub("minio.error", S3Error=Exception)

_real_base = type("Base", (), {"__init_subclass__": classmethod(lambda cls, **kw: None)})

_stub(
    "app.core.database",
    engine=MagicMock(),
    Base=_real_base,
    get_db=MagicMock(),
    AsyncSession=MagicMock(),
    AsyncSessionLocal=MagicMock(),
)

settings_mock = MagicMock()
settings_mock.JWT_SECRET = "test-secret-key-for-unit-tests-only"
settings_mock.JWT_ALGORITHM = "HS256"
settings_mock.JWT_EXPIRE_MINUTES = 30
settings_mock.JWT_REFRESH_EXPIRE_DAYS = 30
settings_mock.DATABASE_URL = "postgresql+asyncpg://x:x@localhost/x"
settings_mock.REDIS_URL = "redis://localhost"
settings_mock.MINIO_ENDPOINT = "localhost:9000"
settings_mock.MINIO_ACCESS_KEY = "test"
settings_mock.MINIO_SECRET_KEY = "test"
settings_mock.MINIO_BUCKET = "test"
settings_mock.MINIO_SECURE = False
_stub("app.core.config", settings=settings_mock)

redis_mock = MagicMock()
redis_mock.revoke_access_jti = AsyncMock()
_stub("app.core.redis_client", redis_manager=redis_mock)

# Stub AI / PDF services that auth.py pulls in transitively via app.services
_stub("google", genai=MagicMock())
_stub("google.genai", Client=MagicMock(), types=MagicMock())
_stub("groq")
_stub("pytesseract")
_stub("reportlab")
_stub("reportlab.lib")
_stub("reportlab.lib.pagesizes")
_stub("reportlab.platypus")
_stub("firebase_admin")
_stub("firebase_admin.messaging")
_stub("firebase_admin.credentials")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


# ── Tests ──────────────────────────────────────────────────────────────────────

def test_logout_sets_fcm_token_to_none_and_commits():
    """
    The logout handler must clear the user's FCM token in the DB so that
    no push notifications are delivered after the session ends.
    """
    async def _run():
        with patch("app.routers.auth._clear_session_cookie"):
            from app.routers.auth import logout

            user = MagicMock()
            user.fcm_token = "device-token-abc123"

            db = AsyncMock()

            request = MagicMock()
            request.headers.get.return_value = ""  # no bearer token to revoke

            response = MagicMock()

            await logout(
                request=request,
                response=response,
                current_user=user,
                db=db,
            )

        assert user.fcm_token is None, "fcm_token must be None after logout"
        db.commit.assert_called_once()

    asyncio.run(_run())


def test_logout_clears_null_fcm_token_without_error():
    """
    Logout when fcm_token is already NULL must not raise — handles the case
    where the user logs out without ever registering an FCM token.
    """
    async def _run():
        with patch("app.routers.auth._clear_session_cookie"):
            from app.routers.auth import logout

            user = MagicMock()
            user.fcm_token = None  # already null

            db = AsyncMock()
            request = MagicMock()
            request.headers.get.return_value = ""
            response = MagicMock()

            await logout(
                request=request,
                response=response,
                current_user=user,
                db=db,
            )

        assert user.fcm_token is None
        db.commit.assert_called_once()

    asyncio.run(_run())


def test_logout_still_clears_fcm_token_when_jwt_revocation_fails():
    """
    If Redis JTI revocation raises, the FCM token must still be cleared and
    the DB must still be committed — logout is not atomic with Redis.
    """
    async def _run():
        with patch("app.routers.auth._clear_session_cookie"), \
             patch("app.routers.auth.redis_manager") as mock_redis:
            mock_redis.revoke_access_jti = AsyncMock(side_effect=Exception("redis down"))

            from importlib import reload
            import app.routers.auth as auth_mod
            reload(auth_mod)

            user = MagicMock()
            user.fcm_token = "device-token-xyz"

            db = AsyncMock()
            request = MagicMock()
            # Provide a token that will trigger the revocation path
            request.headers.get.return_value = "Bearer fake.jwt.token"
            response = MagicMock()

            with patch("app.routers.auth.decode_access_token", side_effect=Exception("bad token")):
                await auth_mod.logout(
                    request=request,
                    response=response,
                    current_user=user,
                    db=db,
                )

        assert user.fcm_token is None
        db.commit.assert_called_once()

    asyncio.run(_run())
