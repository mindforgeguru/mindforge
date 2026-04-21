"""
MIND FORGE — Security Test Suite
Checks security headers, rate limiting, JWT tampering, SQL injection,
and cross-user access controls.
Run: python tests/security_test.py
"""

import asyncio
import httpx
import base64
import json
import time

BASE_URL = "https://api.mindforge.guru"

PASS = "✅ PASS"
FAIL = "❌ FAIL"
WARN = "⚠️  WARN"

results = []

def record(category, test, status, detail=""):
    results.append({"category": category, "test": test, "status": status, "detail": detail})
    icon = {"✅ PASS": "✅", "❌ FAIL": "❌", "⚠️  WARN": "⚠️ "}.get(status, "  ")
    line = f"  {icon} {test}"
    if detail:
        line += f"\n       → {detail}"
    print(line)


async def get_token(client, username="admin", mpin="123456"):
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": username, "mpin": mpin}, timeout=15)
    if resp.status_code == 200:
        return resp.json().get("access_token")
    return None


# ── 1. Security Headers ───────────────────────────────────────────────────────

async def test_security_headers(client):
    print("\n[1] Security Headers")
    resp = await client.get(f"{BASE_URL}/api/health", timeout=10)
    h = {k.lower(): v for k, v in resp.headers.items()}

    checks = [
        ("Strict-Transport-Security", "strict-transport-security",
         "max-age=31536000", "HSTS prevents downgrade attacks"),
        ("X-Content-Type-Options", "x-content-type-options",
         "nosniff", "Prevents MIME-type sniffing"),
        ("X-Frame-Options", "x-frame-options",
         "deny", "Prevents clickjacking via iframes"),
        ("Content-Security-Policy", "content-security-policy",
         None, "Prevents XSS attacks"),
    ]

    for name, key, expected_value, desc in checks:
        if key not in h:
            record("Headers", f"{name}", FAIL, f"Missing — {desc}")
        elif expected_value and expected_value.lower() not in h[key].lower():
            record("Headers", f"{name}", WARN,
                   f"Present but value '{h[key]}' may be insufficient")
        else:
            record("Headers", f"{name}", PASS, h[key][:80])

    # HTTPS check
    if resp.url.scheme == "https":
        record("Headers", "HTTPS enforced", PASS)
    else:
        record("Headers", "HTTPS enforced", FAIL)

    # Server header (should not leak version)
    server = h.get("server", "")
    if server and any(x in server.lower() for x in ["uvicorn", "python", "apache", "nginx/1."]):
        record("Headers", "Server header (version leak)", WARN,
               f"Leaks server info: '{server}'")
    else:
        record("Headers", "Server header (version leak)", PASS,
               server or "not present")


# ── 2. Rate Limiting ──────────────────────────────────────────────────────────

async def test_rate_limiting(client):
    print("\n[2] Rate Limiting on Login")
    responses = []
    # Fire 15 bad login attempts rapidly
    for i in range(15):
        resp = await client.post(f"{BASE_URL}/api/auth/login",
                                 json={"username": f"nonexistent_{i}", "mpin": "999999"},
                                 timeout=10)
        responses.append(resp.status_code)

    has_429 = 429 in responses
    has_rate_limit_header = False

    # Check if any response has rate limit headers
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": "ratelimitcheck", "mpin": "000000"},
                             timeout=10)
    rl_headers = {k.lower() for k in resp.headers}
    has_rate_limit_header = any(h in rl_headers for h in
                                ["x-ratelimit-limit", "retry-after", "ratelimit-limit"])

    if has_429:
        record("Rate Limiting", "Login rate limit (429 returned)", PASS,
               f"Status codes seen: {set(responses)}")
    elif has_rate_limit_header:
        record("Rate Limiting", "Login rate limit (429 returned)", WARN,
               "Rate-limit headers present but no 429 triggered in 15 rapid requests")
    else:
        record("Rate Limiting", "Login rate limit (429 returned)", FAIL,
               f"15 rapid requests all returned {set(responses)} — no rate limiting")


# ── 3. JWT Security ───────────────────────────────────────────────────────────

async def test_jwt_security(client, valid_token):
    print("\n[3] JWT Tampering")

    # 3a. Completely fake token
    fake = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI5OTk5OTkiLCJyb2xlIjoidGVhY2hlciJ9.fakesignature123"
    resp = await client.get(f"{BASE_URL}/api/teacher/dashboard-summary",
                            headers={"Authorization": f"Bearer {fake}"}, timeout=10)
    if resp.status_code == 401:
        record("JWT", "Fake token rejected (401)", PASS)
    else:
        record("JWT", "Fake token rejected (401)", FAIL, f"Got {resp.status_code}")

    # 3b. Tampered payload (change role to admin)
    if valid_token:
        parts = valid_token.split(".")
        try:
            # Decode payload, change role
            payload_padded = parts[1] + "=" * (-len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(payload_padded))
            payload["role"] = "admin"
            payload["sub"] = "1"
            tampered_payload = base64.urlsafe_b64encode(
                json.dumps(payload).encode()).decode().rstrip("=")
            tampered = f"{parts[0]}.{tampered_payload}.{parts[2]}"
            resp = await client.get(f"{BASE_URL}/api/admin/users",
                                    headers={"Authorization": f"Bearer {tampered}"},
                                    timeout=10)
            if resp.status_code in (401, 403):
                record("JWT", "Tampered payload rejected", PASS,
                       f"Status {resp.status_code}")
            else:
                record("JWT", "Tampered payload rejected", FAIL,
                       f"Got {resp.status_code} — tampered token accepted!")
        except Exception as e:
            record("JWT", "Tampered payload test", WARN, f"Could not run: {e}")

    # 3c. No token
    resp = await client.get(f"{BASE_URL}/api/teacher/dashboard-summary", timeout=10)
    if resp.status_code == 401:
        record("JWT", "Missing token rejected (401)", PASS)
    else:
        record("JWT", "Missing token rejected (401)", FAIL, f"Got {resp.status_code}")

    # 3d. Expired / malformed token
    malformed = "Bearer not.a.token"
    resp = await client.get(f"{BASE_URL}/api/teacher/dashboard-summary",
                            headers={"Authorization": malformed}, timeout=10)
    if resp.status_code == 401:
        record("JWT", "Malformed token rejected (401)", PASS)
    else:
        record("JWT", "Malformed token rejected (401)", FAIL, f"Got {resp.status_code}")


# ── 4. SQL Injection ──────────────────────────────────────────────────────────

async def test_sql_injection(client):
    print("\n[4] SQL Injection")

    payloads = [
        ("Classic OR bypass", "' OR '1'='1"),
        ("Drop table attempt", "'; DROP TABLE users; --"),
        ("Union select", "' UNION SELECT * FROM users --"),
        ("Comment bypass", "admin'--"),
        ("Sleep injection", "'; SELECT pg_sleep(3); --"),
    ]

    for name, payload in payloads:
        start = time.perf_counter()
        resp = await client.post(f"{BASE_URL}/api/auth/login",
                                 json={"username": payload, "mpin": "123456"},
                                 timeout=15)
        elapsed = (time.perf_counter() - start) * 1000

        if resp.status_code == 500:
            record("SQL Injection", f"{name}", FAIL,
                   f"Server error (500) — possible injection vulnerability!")
        elif resp.status_code == 200:
            record("SQL Injection", f"{name}", FAIL,
                   f"Login succeeded with SQL payload — CRITICAL!")
        elif elapsed > 2500 and "sleep" in name.lower():
            record("SQL Injection", f"{name}", WARN,
                   f"Response took {elapsed:.0f}ms — possible time-based injection")
        else:
            record("SQL Injection", f"{name}", PASS,
                   f"{resp.status_code} in {elapsed:.0f}ms")


# ── 5. Cross-User Access Control ─────────────────────────────────────────────

async def test_access_control(client, token):
    print("\n[5] Cross-User / Role Access Control")

    if not token:
        record("Access Control", "All tests", WARN, "No token available — skipped")
        return

    headers = {"Authorization": f"Bearer {token}"}

    # Admin-only endpoints should reject teacher/student tokens
    # (admin token used here — should succeed)
    admin_endpoints = [
        ("GET", "/api/admin/users"),
        ("GET", "/api/admin/pending-users"),
    ]

    for method, path in admin_endpoints:
        resp = await client.request(method, f"{BASE_URL}{path}",
                                    headers=headers, timeout=10)
        # Admin token should get 200, not 403/404
        if resp.status_code in (200, 422):
            record("Access Control", f"Admin endpoint accessible with admin token: {path}",
                   PASS, f"Status {resp.status_code}")
        elif resp.status_code == 403:
            record("Access Control",
                   f"Admin endpoint wrongly rejects admin token: {path}", FAIL,
                   f"Status {resp.status_code}")
        else:
            record("Access Control", f"{method} {path}", WARN,
                   f"Status {resp.status_code}")

    # Teacher endpoint with admin token (should be rejected — wrong role)
    resp = await client.get(f"{BASE_URL}/api/teacher/dashboard-summary",
                            headers=headers, timeout=10)
    if resp.status_code in (401, 403):
        record("Access Control",
               "Teacher endpoint rejects admin token (role isolation)", PASS,
               f"Status {resp.status_code}")
    elif resp.status_code == 200:
        record("Access Control",
               "Teacher endpoint rejects admin token (role isolation)", WARN,
               "Admin token accepted on teacher endpoint — consider stricter role checks")
    else:
        record("Access Control", "Teacher endpoint role check", WARN,
               f"Status {resp.status_code}")

    # Accessing student data without auth
    resp = await client.get(f"{BASE_URL}/api/student/dashboard-summary", timeout=10)
    if resp.status_code == 401:
        record("Access Control", "Unauthenticated student access rejected", PASS)
    else:
        record("Access Control", "Unauthenticated student access rejected", FAIL,
               f"Got {resp.status_code}")


# ── 6. Input Validation ───────────────────────────────────────────────────────

async def test_input_validation(client):
    print("\n[6] Input Validation")

    # Oversized username
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": "A" * 10000, "mpin": "123456"}, timeout=10)
    if resp.status_code in (400, 422, 413):
        record("Input Validation", "Oversized username rejected", PASS,
               f"Status {resp.status_code}")
    elif resp.status_code == 500:
        record("Input Validation", "Oversized username rejected", FAIL,
               "Server error (500) on large input")
    else:
        record("Input Validation", "Oversized username rejected", WARN,
               f"Status {resp.status_code}")

    # Null bytes in username
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": "admin\x00injected", "mpin": "123456"},
                             timeout=10)
    if resp.status_code in (400, 401, 422):
        record("Input Validation", "Null byte in username rejected", PASS,
               f"Status {resp.status_code}")
    else:
        record("Input Validation", "Null byte in username rejected", WARN,
               f"Status {resp.status_code}")

    # Missing required fields
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": "admin"}, timeout=10)
    if resp.status_code == 422:
        record("Input Validation", "Missing field returns 422", PASS)
    else:
        record("Input Validation", "Missing field returns 422", WARN,
               f"Got {resp.status_code}")


# ── Summary ───────────────────────────────────────────────────────────────────

def print_summary():
    print("\n" + "=" * 60)
    print("  SECURITY TEST SUMMARY")
    print("=" * 60)
    passed = [r for r in results if r["status"] == PASS]
    failed = [r for r in results if r["status"] == FAIL]
    warned = [r for r in results if r["status"] == WARN]
    print(f"  ✅ Passed:   {len(passed)}")
    print(f"  ❌ Failed:   {len(failed)}")
    print(f"  ⚠️  Warnings: {len(warned)}")

    if failed:
        print("\n  Critical Issues:")
        for r in failed:
            print(f"    ❌ [{r['category']}] {r['test']}")
            if r['detail']:
                print(f"       {r['detail']}")
    if warned:
        print("\n  Warnings:")
        for r in warned:
            print(f"    ⚠️  [{r['category']}] {r['test']}")
            if r['detail']:
                print(f"       {r['detail']}")
    print("=" * 60)


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    print("=" * 60)
    print("  MIND FORGE — Security Test")
    print(f"  Target: {BASE_URL}")
    print("=" * 60)

    async with httpx.AsyncClient(follow_redirects=True) as client:
        await test_security_headers(client)
        await test_rate_limiting(client)

        token = await get_token(client)
        if token:
            print(f"\n  Auth token obtained ✅")
        else:
            print(f"\n  ⚠️  Could not obtain auth token")

        await test_jwt_security(client, token)
        await test_sql_injection(client)
        await test_access_control(client, token)
        await test_input_validation(client)

    print_summary()


if __name__ == "__main__":
    asyncio.run(main())
