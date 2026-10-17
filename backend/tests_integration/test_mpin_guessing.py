"""
Every place that checks an MPIN counts wrong guesses, not just the login.

Found 2026-10-17:

- Registering a student under an existing parent checks that parent's MPIN and
  answers 201 or 401 — an unauthenticated way to test a parent's MPIN. Only the
  registration limit (5 a minute per address) applied, and the login lockout
  never heard of it, so guesses spread over addresses were unlimited.
- The MPIN-change screens (every role) and turning off two-factor ask for the
  current MPIN, with nothing but the general 300-a-minute cap behind them: a
  stolen session could grind the MPIN and keep the account after the session
  ended.

A wrong MPIN anywhere is now a failed login for that account.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth
from .test_realtime_delivery import _mint_access_token

WRONG = "513962"


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _real_mpin_hash(two_schools):
    """The hash of TEST_MPIN, borrowed from the fixture teacher."""
    return asyncio.run(_sql("SELECT mpin_hash FROM users WHERE username = $1",
                            two_schools["a"]["teacher_username"]))


def test_wrong_current_mpins_lock_the_mpin_change(api, two_schools):
    sid = two_schools["a"]["id"]
    student = asyncio.run(_make_student(sid, f"{PREFIX}_guess_s"))
    asyncio.run(_sql("UPDATE users SET mpin_hash = $1 WHERE id = $2", _real_mpin_hash(two_schools), student))
    headers = auth(_mint_access_token(student))
    body = lambda current: {"current_mpin": current, "new_mpin": "604817"}  # noqa: E731

    for _ in range(5):
        assert api.put("/api/student/profile/mpin", headers=headers, json=body(WRONG)).status_code == 400
    r = api.put("/api/student/profile/mpin", headers=headers, json=body(TEST_MPIN))
    assert r.status_code == 429, r.text


def test_registration_cannot_be_used_to_guess_a_parents_mpin(api, two_schools):
    sid = two_schools["a"]["id"]
    parent_name = f"{PREFIX}_guess_parent"
    asyncio.run(_sql(
        """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
           VALUES ($1, $2, 'parent', $3, true, true)""",
        parent_name, _real_mpin_hash(two_schools), sid))

    digits = RUN_ID[:4].translate(str.maketrans("abcdef", "123456"))

    def attempt(n, parent_mpin, address):
        return api.post(
            "/api/auth/register",
            headers={"X-Forwarded-For": address},
            json={"username": f"{PREFIX}_guess_kid{n}", "mpin": "538291", "role": "student",
                  "school_id": sid, "grade": 8, "phone": f"8{digits}{n:05d}",
                  "parent_username": parent_name, "parent_mpin": parent_mpin},
        )

    # Fifty wrong guesses from ten addresses — under every per-address limit.
    for n in range(50):
        r = attempt(n, WRONG, f"203.0.113.{n // 5 + 1}")
        assert r.status_code == 401, f"guess {n}: {r.status_code} {r.text}"

    # The right MPIN from a fresh address no longer gets through.
    r = attempt(99, TEST_MPIN, "203.0.113.200")
    assert r.status_code == 401, r.text
