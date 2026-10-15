"""
A burst of logins must not stall everyone else's requests.

Checking an MPIN is a bcrypt comparison at cost 12 — about a quarter of a
second of CPU. The login handler is `async`, and it called bcrypt directly, so
for that quarter second the worker's event loop ran nothing else: no other API
request, no WebSocket frame. Eight students signing in together froze a health
check that normally answers in 2 ms for over two seconds. A class logging in at
the start of a lesson is exactly that burst.

The comparison now runs on a worker thread (bcrypt releases the GIL while it
hashes), and the loop keeps serving while it does.
"""

import asyncio
import statistics
import time

import asyncpg
import bcrypt
import httpx

from .conftest import BASE_URL, DB_DSN, PREFIX, TEST_MPIN

BURST = 6  # under the 10-per-minute (IP, username) login limit


async def _student_with_real_mpin(school_id: int, username: str) -> None:
    """`_make_student` stores a placeholder hash; logging in needs a real one."""
    conn = await asyncpg.connect(DB_DSN)
    try:
        uid = await conn.fetchval(
            """
            INSERT INTO users (username, mpin_hash, role, school_id,
                               is_active, is_approved)
            VALUES ($1, $2, 'student', $3, true, true)
            RETURNING id
            """,
            username,
            bcrypt.hashpw(TEST_MPIN.encode(), bcrypt.gensalt()).decode(),
            school_id,
        )
        await conn.execute(
            "INSERT INTO student_profiles (user_id, grade, school_id) VALUES ($1, 8, $2)",
            uid,
            school_id,
        )
    finally:
        await conn.close()


async def _measure(school_id: int, username: str):
    body = {"username": username, "mpin": TEST_MPIN, "school_id": school_id}
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=30) as c:
        t = time.perf_counter()
        r = await c.post("/api/auth/login", json=body)
        one_login = (time.perf_counter() - t) * 1000
        assert r.status_code == 200, r.text

        health, done = [], asyncio.Event()

        async def probe():
            while not done.is_set():
                t = time.perf_counter()
                await c.get("/api/health")
                health.append((time.perf_counter() - t) * 1000)
                await asyncio.sleep(0.02)

        prober = asyncio.create_task(probe())
        await asyncio.sleep(0.1)
        logins = await asyncio.gather(
            *[c.post("/api/auth/login", json=body) for _ in range(BURST - 1)]
        )
        done.set()
        await prober
    return one_login, [r.status_code for r in logins], health


def test_other_requests_are_served_while_logins_hash(two_schools):
    school_id = two_schools["a"]["id"]
    username = f"{PREFIX}_burst_student"
    asyncio.run(_student_with_real_mpin(school_id, username))

    one_login, statuses, health = asyncio.run(_measure(school_id, username))

    assert statuses == [200] * (BURST - 1)
    assert health, "the health probe never completed a request"
    worst = max(health)
    # Blocked, the worst wait is several logins long. Unblocked it is a few
    # milliseconds; twice one login's time leaves room for a busy machine.
    assert worst < 2 * one_login, (
        f"a health check waited {worst:.0f} ms behind the logins "
        f"(one login takes {one_login:.0f} ms; median wait "
        f"{statistics.median(health):.0f} ms)"
    )
