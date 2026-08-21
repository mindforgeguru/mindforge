"""
Account-lockout brute-force guard, and the DoS guard on top of it.

Locking an account after N failed logins stops brute force — but a naive
per-username lock hands an attacker a new weapon: fail a victim's login five
times and *they* are locked out. The design here defends against both at once:

  • Layer 1, per-(user, IP): five fails from one IP lock only that IP against
    the account. The real user, on a different IP, is untouched. This is the
    anti-DoS property.
  • Layer 2, per-user global: a much higher bar (50 fails from any source in
    the window) locks the account outright, to catch a distributed attack the
    per-IP limit alone would miss.

These are the tests that were missing — the reason the register row was STALE.
They drive the real RedisManager against a tiny in-memory Redis, and each one
fails if the corresponding guard is removed.

conftest replaces app.core.redis_client with a MagicMock, so the real class is
loaded here straight from its source file, under a private name, to get past
that stub.
"""

import importlib.util
import pathlib

import pytest

_SRC = pathlib.Path(__file__).resolve().parent.parent / "app" / "core" / "redis_client.py"
_spec = importlib.util.spec_from_file_location("_real_redis_client", _SRC)
_real = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_real)
RedisManager = _real.RedisManager


class FakeRedis:
    """Just the async commands the lockout code uses. Records TTLs so a test can
    assert a counter is set to expire rather than accumulate forever."""

    def __init__(self):
        self.store: dict[str, str | int] = {}
        self.ttl: dict[str, int] = {}

    async def incr(self, key):
        self.store[key] = int(self.store.get(key, 0)) + 1
        return self.store[key]

    async def expire(self, key, ttl):
        if key in self.store:
            self.ttl[key] = ttl
            return True
        return False

    async def set(self, key, value, ex=None, nx=False):
        if nx and key in self.store:
            return None
        self.store[key] = value
        if ex is not None:
            self.ttl[key] = ex
        return True

    async def exists(self, key):
        return 1 if key in self.store else 0

    async def delete(self, *keys):
        removed = 0
        for k in keys:
            if k in self.store:
                del self.store[k]
                self.ttl.pop(k, None)
                removed += 1
        return removed


def _mgr():
    m = RedisManager()
    m._client = FakeRedis()
    return m


VICTIM = 42
ATTACKER_IP = "203.0.113.9"
VICTIM_IP = "198.51.100.4"


class TestPerIpLock:
    @pytest.mark.asyncio
    async def test_four_fails_do_not_lock(self):
        m = _mgr()
        for _ in range(4):
            locked = await m.record_failed_login(VICTIM, ATTACKER_IP)
            assert locked is False
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is False

    @pytest.mark.asyncio
    async def test_fifth_fail_locks_that_ip(self):
        m = _mgr()
        for i in range(5):
            locked = await m.record_failed_login(VICTIM, ATTACKER_IP)
        assert locked is True  # the fifth attempt reports the lock
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is True

    @pytest.mark.asyncio
    async def test_counter_is_set_to_expire(self):
        # Without a TTL the counter would accumulate across days and lock an
        # account on the fifth lifetime typo. The window must be bounded.
        m = _mgr()
        await m.record_failed_login(VICTIM, ATTACKER_IP)
        assert m._client.ttl.get(f"failed_logins:{VICTIM}:{ATTACKER_IP}") == m._LOCKOUT_TTL


class TestDosGuard:
    @pytest.mark.asyncio
    async def test_attacker_lockout_does_not_lock_the_real_user(self):
        # THE property. Five fails from the attacker's IP lock the attacker, and
        # the genuine user — same account, different IP — can still get in.
        m = _mgr()
        for _ in range(6):
            await m.record_failed_login(VICTIM, ATTACKER_IP)
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is True
        assert await m.is_user_locked_out(VICTIM, VICTIM_IP) is False

    @pytest.mark.asyncio
    async def test_one_users_failures_do_not_lock_another(self):
        m = _mgr()
        other = 7
        for _ in range(6):
            await m.record_failed_login(VICTIM, ATTACKER_IP)
        assert await m.is_user_locked_out(other, ATTACKER_IP) is False


class TestGlobalBackstop:
    @pytest.mark.asyncio
    async def test_distributed_attack_locks_the_account_outright(self):
        # 50 single failures from 50 distinct IPs: no per-IP lock ever trips
        # (each IP is at 1), but the global backstop must catch the spread and
        # lock the account even for an IP that never failed.
        m = _mgr()
        for n in range(50):
            await m.record_failed_login(VICTIM, f"10.0.{n // 256}.{n % 256}")
        # No single IP was locked...
        assert await m.is_user_locked_out(VICTIM, "10.0.0.0") is True  # global lock covers all
        # ...and a totally fresh IP is locked too, which only a global lock does.
        assert await m.is_user_locked_out(VICTIM, "9.9.9.9") is True

    @pytest.mark.asyncio
    async def test_forty_nine_distributed_fails_stay_below_the_backstop(self):
        m = _mgr()
        for n in range(49):
            await m.record_failed_login(VICTIM, f"10.0.{n // 256}.{n % 256}")
        # A fresh IP is still fine — the backstop has not tripped.
        assert await m.is_user_locked_out(VICTIM, "9.9.9.9") is False


class TestClearOnSuccess:
    @pytest.mark.asyncio
    async def test_success_lifts_the_per_ip_lock(self):
        m = _mgr()
        for _ in range(5):
            await m.record_failed_login(VICTIM, ATTACKER_IP)
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is True
        await m.clear_failed_logins(VICTIM, ATTACKER_IP)
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is False

    @pytest.mark.asyncio
    async def test_a_good_login_resets_the_global_counter(self):
        # A legitimate login from an un-blocked IP clears the distributed-attack
        # tally, so slow background failures can't creep to the backstop over a
        # window in which the real user is active.
        m = _mgr()
        for n in range(49):
            await m.record_failed_login(VICTIM, f"10.0.{n // 256}.{n % 256}")
        await m.clear_failed_logins(VICTIM, VICTIM_IP)  # real user gets in
        # Counter reset: it now takes a fresh 50 to lock, not one more.
        await m.record_failed_login(VICTIM, "10.0.9.9")
        assert await m.is_user_locked_out(VICTIM, "9.9.9.9") is False


class TestDegradesWithoutRedis:
    @pytest.mark.asyncio
    async def test_no_redis_never_locks(self):
        # If Redis is down the guard must fail open, not wedge every login shut.
        m = RedisManager()
        m._client = None
        assert await m.record_failed_login(VICTIM, ATTACKER_IP) is False
        assert await m.is_user_locked_out(VICTIM, ATTACKER_IP) is False
        await m.clear_failed_logins(VICTIM, ATTACKER_IP)  # must not raise
