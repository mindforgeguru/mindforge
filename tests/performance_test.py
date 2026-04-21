"""
MIND FORGE — Performance Test Suite
Tests key API endpoints under concurrent load and measures response times.
Run: python tests/performance_test.py
"""

import asyncio
import time
import statistics
import httpx

BASE_URL = "https://api.mindforge.guru"

# ── Helpers ───────────────────────────────────────────────────────────────────

async def timed_request(client: httpx.AsyncClient, method: str, url: str, **kwargs):
    start = time.perf_counter()
    try:
        resp = await client.request(method, url, timeout=30, **kwargs)
        elapsed = (time.perf_counter() - start) * 1000
        return {"status": resp.status_code, "ms": elapsed, "error": None}
    except Exception as e:
        elapsed = (time.perf_counter() - start) * 1000
        return {"status": 0, "ms": elapsed, "error": str(e)}


def stats(results: list[dict], label: str):
    times = [r["ms"] for r in results if r["error"] is None]
    errors = [r for r in results if r["error"]]
    statuses = {}
    for r in results:
        statuses[r["status"]] = statuses.get(r["status"], 0) + 1

    if not times:
        print(f"  {label}: ALL FAILED ({len(errors)} errors)")
        return

    print(f"\n  {label} ({len(results)} requests):")
    print(f"    Avg:    {statistics.mean(times):.0f} ms")
    print(f"    Median: {statistics.median(times):.0f} ms")
    print(f"    p95:    {sorted(times)[int(len(times)*0.95)]:.0f} ms")
    print(f"    Min:    {min(times):.0f} ms  /  Max: {max(times):.0f} ms")
    print(f"    Status codes: {statuses}")
    if errors:
        print(f"    Errors: {len(errors)}")

    # Rating
    avg = statistics.mean(times)
    if avg < 300:
        rating = "✅ Excellent"
    elif avg < 700:
        rating = "✅ Good"
    elif avg < 1500:
        rating = "⚠️  Acceptable"
    else:
        rating = "❌ Slow"
    print(f"    Rating: {rating}")


async def get_token(client, username="admin", mpin="123456"):
    """Login and return access token."""
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": username, "mpin": mpin},
                             timeout=15)
    if resp.status_code == 200:
        return resp.json().get("access_token")
    return None


# ── Tests ─────────────────────────────────────────────────────────────────────

async def test_health(client, n=50):
    """Health endpoint — no auth, should be sub-100ms."""
    tasks = [timed_request(client, "GET", f"{BASE_URL}/api/health") for _ in range(n)]
    return await asyncio.gather(*tasks)


async def test_login_concurrent(client, n=20):
    """Concurrent valid logins — simulates multiple users logging in at once."""
    tasks = [timed_request(client, "POST", f"{BASE_URL}/api/auth/login",
                           json={"username": "admin", "mpin": "123456"})
             for _ in range(n)]
    return await asyncio.gather(*tasks)


async def test_login_invalid(client, n=10):
    """Invalid login attempts — also verifies 401 is returned, not 500."""
    tasks = [timed_request(client, "POST", f"{BASE_URL}/api/auth/login",
                           json={"username": "admin", "mpin": "000000"})
             for _ in range(n)]
    return await asyncio.gather(*tasks)


async def test_dashboard_concurrent(client, token, n=10):
    """Concurrent dashboard-summary requests — simulates 10 teachers opening the app."""
    headers = {"Authorization": f"Bearer {token}"}
    tasks = [timed_request(client, "GET", f"{BASE_URL}/api/teacher/dashboard-summary",
                           headers=headers)
             for _ in range(n)]
    return await asyncio.gather(*tasks)


async def test_sequential_latency(client, token, n=5):
    """Sequential requests to measure baseline latency without concurrency."""
    headers = {"Authorization": f"Bearer {token}"}
    results = []
    for _ in range(n):
        r = await timed_request(client, "GET", f"{BASE_URL}/api/teacher/dashboard-summary",
                                headers=headers)
        results.append(r)
    return results


async def test_websocket_connections(n=10):
    """Open N WebSocket connections simultaneously and measure connect time."""
    import websockets
    results = []

    async def connect_one(user_id):
        start = time.perf_counter()
        try:
            ws_url = f"wss://api.mindforge.guru/ws/{user_id}"
            async with websockets.connect(ws_url, open_timeout=10) as ws:
                elapsed = (time.perf_counter() - start) * 1000
                await ws.send("ping")
                pong = await asyncio.wait_for(ws.recv(), timeout=5)
                return {"connected": True, "ms": elapsed, "pong": pong == "pong"}
        except Exception as e:
            elapsed = (time.perf_counter() - start) * 1000
            return {"connected": False, "ms": elapsed, "error": str(e)}

    tasks = [connect_one(i + 1) for i in range(n)]
    results = await asyncio.gather(*tasks)
    connected = sum(1 for r in results if r.get("connected"))
    times = [r["ms"] for r in results if r.get("connected")]
    print(f"\n  WebSocket ({n} concurrent connections):")
    print(f"    Connected: {connected}/{n}")
    if times:
        print(f"    Avg connect time: {statistics.mean(times):.0f} ms")
        print(f"    Pong received: {sum(1 for r in results if r.get('pong'))}/{connected}")
    return results


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    print("=" * 60)
    print("  MIND FORGE — Performance Test")
    print(f"  Target: {BASE_URL}")
    print("=" * 60)

    async with httpx.AsyncClient() as client:
        # 1. Health endpoint
        print("\n[1] Health endpoint (50 concurrent)")
        results = await test_health(client, n=50)
        stats(results, "GET /api/health")

        # 2. Concurrent valid logins
        print("\n[2] Concurrent valid logins (20 simultaneous)")
        results = await test_login_concurrent(client, n=20)
        stats(results, "POST /auth/login (valid)")

        # 3. Invalid logins (should be 401, not 500)
        print("\n[3] Invalid login attempts (10 concurrent)")
        results = await test_login_invalid(client, n=10)
        stats(results, "POST /auth/login (invalid)")
        statuses = set(r["status"] for r in results)
        if statuses <= {401}:
            print("    ✅ All returned 401 (correct)")
        else:
            print(f"    ⚠️  Unexpected statuses: {statuses}")

        # 4. Get token for authenticated tests
        print("\n[4] Getting auth token...")
        token = await get_token(client)
        if token:
            print("    ✅ Token obtained")

            # 5. Concurrent dashboard-summary
            print("\n[5] Concurrent dashboard-summary (10 teachers simultaneously)")
            results = await test_dashboard_concurrent(client, token, n=10)
            stats(results, "GET /teacher/dashboard-summary")

            # 6. Sequential baseline
            print("\n[6] Sequential dashboard-summary (5 requests, no concurrency)")
            results = await test_sequential_latency(client, token, n=5)
            stats(results, "GET /teacher/dashboard-summary (sequential)")
        else:
            print("    ❌ Could not get token — skipping authenticated tests")

    # 7. WebSocket
    print("\n[7] WebSocket concurrent connections (10)")
    try:
        import websockets
        await test_websocket_connections(n=10)
    except ImportError:
        print("    ⚠️  websockets package not available — skipping")

    print("\n" + "=" * 60)
    print("  Performance test complete")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
