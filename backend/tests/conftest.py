"""
conftest.py — stubs out heavy infrastructure (DB, Redis, MinIO, AI clients)
so the pure-logic unit tests can import app modules without needing a running
Postgres, Redis, or real credentials.
"""

import sys
from types import ModuleType
from unittest.mock import MagicMock, AsyncMock


def _stub(name: str, **attrs) -> ModuleType:
    m = ModuleType(name)
    for k, v in attrs.items():
        setattr(m, k, v)
    sys.modules[name] = m
    return m


# ── asyncpg (pulled in by SQLAlchemy asyncpg dialect) ─────────────────────────
_stub("asyncpg")

# ── SQLAlchemy async engine / session ─────────────────────────────────────────
engine_mock = MagicMock()
engine_mock.connect = AsyncMock()
engine_mock.begin = AsyncMock()

session_mock = MagicMock()
session_mock.__aenter__ = AsyncMock(return_value=session_mock)
session_mock.__aexit__ = AsyncMock(return_value=False)

db_module = _stub(
    "app.core.database",
    engine=engine_mock,
    Base=MagicMock(),
    get_db=MagicMock(),
    AsyncSession=MagicMock(return_value=session_mock),
)

# ── Redis ─────────────────────────────────────────────────────────────────────
redis_module = _stub(
    "app.core.redis_client",
    redis_manager=MagicMock(),
)

# ── Settings — provide minimal defaults so config.py doesn't crash ─────────────
settings_mock = MagicMock()
settings_mock.JWT_SECRET = "test-secret-key-for-unit-tests-only"
settings_mock.JWT_ALGORITHM = "HS256"
settings_mock.JWT_EXPIRE_MINUTES = 30
settings_mock.JWT_REFRESH_EXPIRE_DAYS = 30
settings_mock.DATABASE_URL = "postgresql+asyncpg://x:x@localhost/x"
settings_mock.REDIS_URL = "redis://localhost"

_stub("app.core.config", settings=settings_mock)
