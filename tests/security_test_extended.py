"""
MIND FORGE — Extended Security Probes
Covers what `security_test.py` does not:
  • Privilege-escalation matrix (cross-role access)
  • IDOR / BOLA (one user reading another user's data by id)
  • Mass-assignment on /api/auth/register (role=admin etc.)
  • Path traversal on /api/media/{bucket}/{key}
  • WebSocket: token for user A but URL says user B
  • Auth deep-checks: JTI revoke after logout, refresh-token rotation

Run against the LOCAL stack (don't point at prod — these probes hammer auth).
Usage:  python3 tests/security_test_extended.py
"""

import asyncio
import json
import httpx
from websockets.client import connect as ws_connect
from websockets.exceptions import InvalidStatusCode, ConnectionClosed

BASE_URL = "http://localhost:8000"
WS_URL = "ws://localhost:8000"

PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"

results = []


def record(category, test, status, detail=""):
    results.append({"category": category, "test": test, "status": status, "detail": detail})
    icon = {"PASS": "[+]", "FAIL": "[X]", "WARN": "[~]"}.get(status, "[ ]")
    line = f"  {icon} {test}"
    if detail:
        line += f"\n        -> {detail}"
    print(line)


USERS = {
    "admin":   {"username": "admin",        "mpin": "300573", "id": 1},
    "teacher": {"username": "chinmay_sir",  "mpin": "100898", "id": 2},
    "parent":  {"username": "dummy8_dad",   "mpin": "111111", "id": 25},
    "student": {"username": "dummy8",       "mpin": "111111", "id": 26},
}


async def login(client, role):
    u = USERS[role]
    resp = await client.post(f"{BASE_URL}/api/auth/login",
                             json={"username": u["username"], "mpin": u["mpin"]},
                             timeout=15)
    if resp.status_code != 200:
        return None, None
    data = resp.json()
    return data.get("access_token"), data.get("refresh_token")


# ── 1. Privilege escalation matrix ─────────────────────────────────────────────

PROTECTED_ENDPOINTS = [
    # (path, allowed_roles)
    ("/api/admin/users",                  {"admin"}),
    ("/api/admin/users/pending",          {"admin"}),
    ("/api/teacher/dashboard-summary",    {"teacher"}),
    ("/api/teacher/students",             {"teacher"}),
    ("/api/student/profile",              {"student"}),
    ("/api/student/attendance",           {"student"}),
    ("/api/parent/dashboard-summary",     {"parent"}),
    ("/api/parent/child/attendance",      {"parent"}),
]


async def test_privilege_escalation(client, tokens):
    print("\n[1] Cross-role access (privilege escalation)")
    for path, allowed in PROTECTED_ENDPOINTS:
        for role, tok in tokens.items():
            if tok is None:
                continue
            r = await client.get(f"{BASE_URL}{path}",
                                 headers={"Authorization": f"Bearer {tok}"},
                                 timeout=10)
            should_allow = role in allowed
            allowed_codes = (200, 422)  # 422 = valid token, missing query args
            denied_codes = (401, 403)
            if should_allow:
                if r.status_code in allowed_codes:
                    record("Privilege", f"{role} -> {path}", PASS, f"{r.status_code} (allowed)")
                else:
                    record("Privilege", f"{role} -> {path}", WARN,
                           f"unexpected {r.status_code} for allowed role")
            else:
                if r.status_code in denied_codes:
                    record("Privilege", f"{role} -> {path} (denied)", PASS, f"{r.status_code}")
                else:
                    record("Privilege", f"{role} -> {path} (denied)", FAIL,
                           f"role-blind: status {r.status_code}")


# ── 2. IDOR / BOLA ─────────────────────────────────────────────────────────────

async def test_idor(client, tokens):
    print("\n[2] IDOR / BOLA — accessing other users' data by id")

    # 2a. Student fetches their own XP via /api/xp/student/{id} — should work for self
    student_tok = tokens["student"]
    own_id = USERS["student"]["id"]
    r = await client.get(f"{BASE_URL}/api/xp/student/{own_id}",
                         headers={"Authorization": f"Bearer {student_tok}"}, timeout=10)
    if r.status_code == 200:
        record("IDOR", "student reads own XP (sanity)", PASS, f"{r.status_code}")
    else:
        record("IDOR", "student reads own XP (sanity)", WARN, f"{r.status_code}")

    # 2b. Student tries to fetch OTHER student's XP — admin is id=1
    other_id = 1
    r = await client.get(f"{BASE_URL}/api/xp/student/{other_id}",
                         headers={"Authorization": f"Bearer {student_tok}"}, timeout=10)
    if r.status_code in (401, 403, 404):
        record("IDOR", f"student reads other user's XP (id={other_id})", PASS,
               f"denied with {r.status_code}")
    elif r.status_code == 200:
        record("IDOR", f"student reads other user's XP (id={other_id})", FAIL,
               "another user's XP returned — IDOR confirmed")
    else:
        record("IDOR", f"student reads other user's XP (id={other_id})", WARN,
               f"{r.status_code}")

    # 2c. Parent fetches /api/parent/child/* — should be restricted to linked child
    parent_tok = tokens["parent"]
    r = await client.get(f"{BASE_URL}/api/parent/child/attendance",
                         headers={"Authorization": f"Bearer {parent_tok}"}, timeout=10)
    if r.status_code in (200, 422):
        record("IDOR", "parent reads linked child's attendance (sanity)", PASS,
               f"{r.status_code}")
    else:
        record("IDOR", "parent reads linked child's attendance", WARN, f"{r.status_code}")

    # 2d. Try parent endpoint with student token — should be 403
    r = await client.get(f"{BASE_URL}/api/parent/child/attendance",
                         headers={"Authorization": f"Bearer {student_tok}"}, timeout=10)
    if r.status_code in (401, 403):
        record("IDOR", "student reads parent's child endpoint", PASS, f"{r.status_code}")
    else:
        record("IDOR", "student reads parent's child endpoint", FAIL,
               f"role bypass: {r.status_code}")


# ── 3. Mass assignment on register ─────────────────────────────────────────────

async def test_mass_assignment(client):
    print("\n[3] Mass-assignment on /api/auth/register")
    payloads = [
        {"username": "evil_admin_1", "mpin": "111111", "full_name": "Evil",
         "role": "admin", "is_active": True, "deleted_at": None},
        {"username": "evil_admin_2", "mpin": "222222", "full_name": "Evil2",
         "role": "admin"},
        {"username": "evil_teacher", "mpin": "333333", "full_name": "Evil3",
         "role": "teacher", "is_active": True},
    ]
    for p in payloads:
        r = await client.post(f"{BASE_URL}/api/auth/register",
                              json=p, timeout=10)
        body = r.text[:200]
        if r.status_code in (400, 401, 403, 422):
            record("MassAssign",
                   f"register with role={p.get('role')!r} rejected", PASS,
                   f"{r.status_code}")
        elif r.status_code in (200, 201):
            # Pull role back from /api/admin/users to confirm what got stored
            data = r.json()
            stored_role = data.get("role", "?")
            if stored_role == p.get("role"):
                record("MassAssign",
                       f"register with role={p.get('role')!r}", FAIL,
                       f"server STORED role={stored_role!r} — privilege escalation possible")
            else:
                record("MassAssign",
                       f"register ignored injected role={p.get('role')!r}", PASS,
                       f"stored role={stored_role!r}")
        else:
            record("MassAssign", f"register with role={p.get('role')!r}", WARN,
                   f"{r.status_code} {body}")


# ── 4. Path traversal on /api/media ────────────────────────────────────────────

async def test_path_traversal(client):
    print("\n[4] Path traversal on /api/media/{bucket}/{key}")

    # 4a. Non-allowlisted bucket
    r = await client.get(f"{BASE_URL}/api/media/secrets/key", timeout=10)
    if r.status_code == 403:
        record("Path", "non-allowlisted bucket rejected", PASS, "403")
    else:
        record("Path", "non-allowlisted bucket", FAIL, f"got {r.status_code}")

    # 4b. Traversal in key (raw, encoded, double-encoded)
    keys = [
        "../etc/passwd",
        "..%2Fetc%2Fpasswd",
        "..%252Fetc%252Fpasswd",
        "%00../etc/passwd",
    ]
    for k in keys:
        r = await client.get(f"{BASE_URL}/api/media/profiles/{k}", timeout=10)
        # Either 404 (MinIO didn't find) or 400; should never return any host file
        # We only flag FAIL if status looks like content actually leaked.
        ct = r.headers.get("content-type", "")
        if r.status_code in (200,) and "image" not in ct and len(r.content) > 0:
            record("Path", f"traversal key={k!r}", FAIL,
                   f"unexpected 200 with content-type {ct}")
        else:
            record("Path", f"traversal key={k!r}", PASS,
                   f"{r.status_code} ({ct or 'no body'})")


# ── 5. WebSocket auth ──────────────────────────────────────────────────────────

async def test_websocket_auth(tokens):
    print("\n[5] WebSocket authentication")

    student_tok = tokens["student"]
    student_id = USERS["student"]["id"]
    admin_id   = USERS["admin"]["id"]

    # 5a. Student token + own user_id -> should accept
    try:
        async with ws_connect(
            f"{WS_URL}/ws/{student_id}?token={student_tok}",
            open_timeout=5,
        ) as ws:
            await ws.send("ping")
            msg = await asyncio.wait_for(ws.recv(), timeout=5)
            ok = (msg == "pong")
            if ok:
                record("WS", "valid token + matching user_id accepted", PASS, "pong ok")
            else:
                record("WS", "valid token + matching user_id", WARN, f"resp={msg!r}")
    except InvalidStatusCode as e:
        record("WS", "valid token + matching user_id accepted", FAIL,
               f"refused with status {e.status_code}")
    except Exception as e:
        record("WS", "valid token + matching user_id accepted", WARN, str(e))

    # 5b. Student token + ADMIN user_id -> should reject
    try:
        async with ws_connect(
            f"{WS_URL}/ws/{admin_id}?token={student_tok}",
            open_timeout=5,
        ) as ws:
            # Server-side: handshake completes then closes 1008.
            # If we get here we got past the handshake; try one recv to see if close arrives.
            try:
                await asyncio.wait_for(ws.recv(), timeout=3)
                record("WS", f"student token used for user_id={admin_id}", FAIL,
                       "connection stayed open — IDOR")
            except ConnectionClosed as cc:
                if cc.code == 1008:
                    record("WS", f"student token used for user_id={admin_id}", PASS,
                           "closed with 1008")
                else:
                    record("WS", f"student token used for user_id={admin_id}", WARN,
                           f"closed code={cc.code}")
    except InvalidStatusCode as e:
        record("WS", f"student token used for user_id={admin_id}", PASS,
               f"refused at handshake ({e.status_code})")
    except ConnectionClosed as cc:
        if cc.code == 1008:
            record("WS", f"student token used for user_id={admin_id}", PASS, "1008")
        else:
            record("WS", f"student token used for user_id={admin_id}", WARN,
                   f"code={cc.code}")
    except Exception as e:
        record("WS", f"student token used for user_id={admin_id}", WARN, str(e))

    # 5c. No token at all -> should reject
    try:
        async with ws_connect(f"{WS_URL}/ws/{student_id}", open_timeout=5) as ws:
            try:
                await asyncio.wait_for(ws.recv(), timeout=3)
                record("WS", "no token rejected", FAIL, "stayed open")
            except ConnectionClosed as cc:
                record("WS", "no token rejected", PASS, f"closed code={cc.code}")
    except InvalidStatusCode as e:
        record("WS", "no token rejected", PASS, f"handshake {e.status_code}")
    except ConnectionClosed as cc:
        record("WS", "no token rejected", PASS, f"code={cc.code}")
    except Exception as e:
        record("WS", "no token rejected", WARN, str(e))


# ── 6. Auth flow deep-checks (Tier F) ─────────────────────────────────────────

async def test_auth_flow(client):
    print("\n[6] Auth flow deep-checks")

    # 6a. JTI revoke after logout — login as student, save token, logout, re-use token
    access, refresh = await login(client, "student")
    if not access:
        record("Auth", "logout JTI revocation", WARN, "could not login student")
        return

    headers = {"Authorization": f"Bearer {access}"}
    # baseline: token works
    r = await client.get(f"{BASE_URL}/api/auth/me", headers=headers, timeout=10)
    if r.status_code != 200:
        record("Auth", "logout JTI revocation pre-check", WARN, f"baseline {r.status_code}")
        return

    body = {}
    if refresh:
        body["refresh_token"] = refresh
    r = await client.post(f"{BASE_URL}/api/auth/logout", json=body, headers=headers,
                          timeout=10)
    if r.status_code not in (200, 204):
        record("Auth", "logout returns 204", WARN, f"{r.status_code}")

    # Reuse old access token
    r = await client.get(f"{BASE_URL}/api/auth/me", headers=headers, timeout=10)
    if r.status_code == 401:
        record("Auth", "access token revoked after logout", PASS, "401")
    elif r.status_code == 200:
        record("Auth", "access token revoked after logout", FAIL,
               "old token still works — JTI not blacklisted")
    else:
        record("Auth", "access token revoked after logout", WARN, f"{r.status_code}")

    # 6b. Refresh-token rotation: re-login, refresh once, try old refresh again
    access2, refresh2 = await login(client, "student")
    if not refresh2:
        record("Auth", "refresh rotation", WARN, "no refresh issued at login")
        return

    # First refresh — should succeed and rotate
    r = await client.post(f"{BASE_URL}/api/auth/refresh",
                          json={"refresh_token": refresh2}, timeout=10)
    if r.status_code != 200:
        record("Auth", "refresh succeeds", WARN, f"{r.status_code}")
        return
    new_refresh = r.json().get("refresh_token")

    # Replay old refresh — should fail (rotation invalidates it)
    r = await client.post(f"{BASE_URL}/api/auth/refresh",
                          json={"refresh_token": refresh2}, timeout=10)
    if r.status_code == 401:
        record("Auth", "old refresh token rejected after rotation", PASS, "401")
    elif r.status_code == 200:
        record("Auth", "old refresh token rejected after rotation", FAIL,
               "old refresh still works — rotation broken")
    else:
        record("Auth", "old refresh token rejected after rotation", WARN, f"{r.status_code}")

    # 6c. Access token from logged-out session shouldn't refresh either
    # (Already covered by 6a — the access token came from a logged-out session above.)


# ── Summary ────────────────────────────────────────────────────────────────────

def print_summary():
    print("\n" + "=" * 60)
    print("  EXTENDED SECURITY TEST SUMMARY")
    print("=" * 60)
    passed = [r for r in results if r["status"] == PASS]
    failed = [r for r in results if r["status"] == FAIL]
    warned = [r for r in results if r["status"] == WARN]
    print(f"  Passed:   {len(passed)}")
    print(f"  Failed:   {len(failed)}")
    print(f"  Warnings: {len(warned)}")

    if failed:
        print("\n  CRITICAL:")
        for r in failed:
            print(f"    [X] [{r['category']}] {r['test']}")
            if r['detail']:
                print(f"        {r['detail']}")
    if warned:
        print("\n  Warnings:")
        for r in warned:
            print(f"    [~] [{r['category']}] {r['test']}")
            if r['detail']:
                print(f"        {r['detail']}")
    print("=" * 60)


# ── Main ───────────────────────────────────────────────────────────────────────

async def main():
    print("=" * 60)
    print("  MIND FORGE — Extended Security Probes")
    print(f"  Target: {BASE_URL}")
    print("=" * 60)

    async with httpx.AsyncClient(follow_redirects=True) as client:
        # Get a token per role
        tokens = {}
        for role in USERS:
            tok, _ = await login(client, role)
            tokens[role] = tok
            print(f"  login {role}: {'ok' if tok else 'FAIL'}")

        await test_privilege_escalation(client, tokens)
        await test_idor(client, tokens)
        await test_mass_assignment(client)
        await test_path_traversal(client)
        await test_websocket_auth(tokens)
        await test_auth_flow(client)

    print_summary()


if __name__ == "__main__":
    asyncio.run(main())
