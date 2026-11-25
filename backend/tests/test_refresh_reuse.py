"""Rotated refresh tokens are marked so a later replay can be detected."""

import asyncio
import importlib.util
import pathlib
import time

_path = pathlib.Path(__file__).resolve().parents[1] / "app" / "core" / "redis_client.py"
_spec = importlib.util.spec_from_file_location("_real_redis_client_reuse", _path)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
RedisManager = _mod.RedisManager


class _FakeRedis:
    def __init__(self): self.d = {}
    async def set(self, k, v, ex=None): self.d[k] = v.encode() if isinstance(v, str) else v
    async def get(self, k): return self.d.get(k)
    async def exists(self, k): return 1 if k in self.d else 0


def _mgr():
    m = RedisManager(); m._client = _FakeRedis(); return m


def test_rotated_token_reports_its_age():
    m = _mgr()
    asyncio.run(m.revoke_jti("a", 60, rotated_at=time.time() - 45))
    age = asyncio.run(m.rotated_jti_age("a"))
    assert 44 <= age <= 47
    assert asyncio.run(m.is_jti_revoked("a"))


def test_logout_revocation_is_not_a_rotation():
    m = _mgr()
    asyncio.run(m.revoke_jti("b", 60))
    assert asyncio.run(m.is_jti_revoked("b"))
    assert asyncio.run(m.rotated_jti_age("b")) is None


def test_unknown_token_and_no_redis_fail_open():
    m = _mgr()
    assert asyncio.run(m.rotated_jti_age("nope")) is None
    m._client = None
    assert asyncio.run(m.rotated_jti_age("nope")) is None
