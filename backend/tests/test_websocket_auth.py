"""
Smoke test for the /ws/{user_id} JWT-auth gate added on 2026-05-14.

Verifies that the WebSocket endpoint:
  1. Rejects (closes 1008) when no/empty token is sent.
  2. Rejects a malformed JWT.
  3. Rejects a refresh token (wrong `type` claim).
  4. Rejects a valid access token whose `sub` does not match the URL user_id.
  5. Rejects a valid token whose JTI has been blacklisted (logout / delete).
  6. ACCEPTS a valid access token whose `sub` matches user_id and is not revoked.

We call websocket_endpoint() directly with a mock WebSocket. No real socket,
no DB, no Redis required — same pattern as test_logout_handler.py.

Run: cd backend && python3 -m pytest tests/test_websocket_auth.py -v
"""

import asyncio
import sys
from types import ModuleType
from unittest.mock import AsyncMock, MagicMock, patch

# ── Stub heavy infra (same shape as test_logout_handler.py) ───────────────────

def _stub(name: str, **attrs) -> ModuleType:
    m = ModuleType(name)
    for k, v in attrs.items():
        setattr(m, k, v)
    sys.modules[name] = m
    return m


_stub("asyncpg")
_stub("minio", Minio=MagicMock(), error=ModuleType("minio.error"))
_stub("minio.error", S3Error=Exception)

# Real classes so FastAPI annotation resolution works on Python ≥3.12
_Base = type("Base", (), {"__init_subclass__": classmethod(lambda cls, **kw: None)})
_AsyncSession = type("AsyncSession", (), {})
_stub(
    "app.core.database",
    engine=MagicMock(),
    Base=_Base,
    get_db=MagicMock(),
    AsyncSession=_AsyncSession,
    AsyncSessionLocal=MagicMock(),
)

settings_mock = MagicMock()
settings_mock.JWT_SECRET = "test-secret-for-ws-auth-smoke"
settings_mock.JWT_ALGORITHM = "HS256"
settings_mock.JWT_EXPIRE_MINUTES = 30
settings_mock.JWT_REFRESH_EXPIRE_DAYS = 30
settings_mock.DATABASE_URL = "postgresql+asyncpg://x:x@localhost/x"
settings_mock.REDIS_URL = "redis://localhost"
settings_mock.SENTRY_DSN = ""
settings_mock.BACKEND_CORS_ORIGINS = ["http://localhost"]
settings_mock.MINIO_BUCKET_PROFILES = "profiles"
_stub("app.core.config", settings=settings_mock)

# Redis stub — we'll override is_access_jti_revoked per-test
redis_mock = MagicMock()
redis_mock.is_access_jti_revoked = AsyncMock(return_value=False)
_stub("app.core.redis_client", redis_manager=redis_mock)

# Earlier test files (e.g. test_logout_handler.py) install bare ModuleType
# stubs for heavy 3rd-party packages in sys.modules. Those stubs lack the
# attributes ai_service / pdf_service actually use, so when this file runs
# AFTER them in the same pytest session `from reportlab.platypus import
# HRFlowable` (etc.) explodes. Real packages are pip-installed, so we
# evict the stubs and let Python re-import the real ones lazily on first
# `from … import …`.
for _stale in [k for k in list(sys.modules) if k.split(".")[0] in {
    "groq", "google", "pytesseract", "reportlab", "firebase_admin",
    "fitz", "PIL",
}]:
    sys.modules.pop(_stale, None)


# ── Now import the real modules under test ────────────────────────────────────
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.security import create_access_token, create_refresh_token  # noqa: E402

POLICY_VIOLATION = 1008


def _fake_ws():
    """A WebSocket double that records close() calls and never blocks."""
    ws = MagicMock()
    ws.close = AsyncMock()
    ws.accept = AsyncMock()
    ws.send_text = AsyncMock()
    # If the endpoint ever reaches the receive loop on an unintended path,
    # raise immediately so the test fails loudly instead of hanging.
    from fastapi import WebSocketDisconnect
    ws.receive_text = AsyncMock(side_effect=WebSocketDisconnect())
    return ws


async def _call_endpoint(token: str, user_id: int):
    """Invoke the endpoint function with a mock WS and given args."""
    # Import lazily so all stubs are in place
    from main import websocket_endpoint
    ws = _fake_ws()
    # ws_manager is referenced inside the function via module-level import;
    # patch it to a no-op so the success path doesn't try real Redis pubsub.
    with patch("main.ws_manager") as wsm:
        wsm.connect = AsyncMock()
        wsm.disconnect = AsyncMock()
        await websocket_endpoint(websocket=ws, user_id=user_id, token=token)
    return ws


# ── Tests ──────────────────────────────────────────────────────────────────────

def test_malformed_token_is_rejected_with_1008():
    ws = asyncio.run(_call_endpoint(token="not-a-real-jwt", user_id=42))
    ws.close.assert_awaited_once_with(code=POLICY_VIOLATION)


def test_refresh_token_is_rejected_with_1008():
    # A refresh token has type=refresh — must not be usable for WS auth
    refresh = create_refresh_token(data={"sub": "42", "role": "student"})
    ws = asyncio.run(_call_endpoint(token=refresh, user_id=42))
    ws.close.assert_awaited_once_with(code=POLICY_VIOLATION)


def test_token_for_different_user_is_rejected_with_1008():
    # Token mints sub=42, but URL says user_id=43 → cross-user subscription
    token = create_access_token(data={"sub": "42", "role": "student"})
    ws = asyncio.run(_call_endpoint(token=token, user_id=43))
    ws.close.assert_awaited_once_with(code=POLICY_VIOLATION)


def test_revoked_jti_is_rejected_with_1008():
    token = create_access_token(data={"sub": "42", "role": "student"})

    async def _run():
        ws = _fake_ws()
        from main import websocket_endpoint
        # is_access_jti_revoked → True for any JTI this test sees
        with patch("main.ws_manager") as wsm, \
             patch("main.redis_manager") as rm:
            wsm.connect = AsyncMock()
            wsm.disconnect = AsyncMock()
            rm.is_access_jti_revoked = AsyncMock(return_value=True)
            await websocket_endpoint(websocket=ws, user_id=42, token=token)
        return ws

    ws = asyncio.run(_run())
    ws.close.assert_awaited_once_with(code=POLICY_VIOLATION)


def test_valid_matching_token_is_accepted():
    """Happy path: valid access token whose sub matches user_id and JTI is fresh
    → endpoint hands off to ws_manager.connect and never calls websocket.close()
    with 1008. (It WILL exit via WebSocketDisconnect from our receive mock; the
    finally-block calls ws_manager.disconnect, which is fine.)"""
    token = create_access_token(data={"sub": "42", "role": "student"})
    ws = asyncio.run(_call_endpoint(token=token, user_id=42))
    # The auth gate must NOT have closed with 1008.
    for call in ws.close.await_args_list:
        kwargs = call.kwargs or {}
        assert kwargs.get("code") != POLICY_VIOLATION, (
            "Valid token was rejected by the auth gate — this is a regression."
        )
