"""Auth / session / account-deletion QA against the LOCAL stack only.

Covers TEST_RECORD.md §3.2, §3.5 (CORS), §4.1, §5.1 and the API rows of §5.7:
registration, approval, login, lockout and rate limit, refresh rotation, logout,
deactivation, MPIN-reset revocation, self-delete and its parent->child cascade.

    python3 tests/auth_session_qa.py        # stack up, run from anywhere

Not a pytest file. It needs the local Docker stack (it reads Postgres and Redis
through `docker exec` to check what the API cannot show) and the accounts in
docs/local-test-accounts.md. It registers four throwaway `qa_*` accounts in
school 1 and ends with them hard-deleted (rejected) or soft-deleted. Takes ~90 s:
one deliberate 61 s wait for the per-username login rate window. Registration is
limited to 5 a minute per IP, so wait a minute between runs.
"""
import base64, json, pathlib, random, subprocess, sys, time
import requests

BASE = "http://localhost:8000/api"
assert "localhost" in BASE
SCHOOL = 1
SUF = str(random.randint(10000, 99999))
RESULTS = []
REDIS_PW = next(l.split("=", 1)[1].strip() for l in open(pathlib.Path(__file__).resolve().parent.parent / ".env.local")
                if l.startswith("REDIS_PASSWORD="))


def rec(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""), flush=True)


def psql(sql):
    out = subprocess.run(
        ["docker", "exec", "mindforge_postgres", "psql", "-U", "mindforge", "-d", "mindforge", "-Atc", sql],
        capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else "ERR " + out.stderr.strip()


def redis(*args):
    out = subprocess.run(
        ["docker", "exec", "-e", "REDISCLI_AUTH=" + REDIS_PW, "mindforge_redis", "sh", "-c",
         "redis-cli " + " ".join(args)],
        capture_output=True, text=True)
    return out.stdout.strip()


def login(username, mpin, school=SCHOOL):
    body = {"username": username, "mpin": mpin}
    if school is not None:
        body["school_id"] = school
    return requests.post(f"{BASE}/auth/login", json=body)


def H(tok):
    return {"Authorization": f"Bearer {tok}"}


def claims(tok):
    p = tok.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))


def me(tok):
    return requests.get(f"{BASE}/auth/me", headers=H(tok)).status_code


def phone():
    return "9" + str(random.randint(100000000, 999999999))


# ── fixtures ────────────────────────────────────────────────────────────────
adm = login("demo_admin", "847362")
assert adm.status_code == 200, adm.text
ADMIN = adm.json()["access_token"]
ADMIN_ID = adm.json()["user_id"]

TA, TB, ST, PA = f"qa_ta_{SUF}", f"qa_tb_{SUF}", f"qa_st_{SUF}", f"qa_pa_{SUF}"
MPIN, MPIN2, PMPIN = "538291", "604817", "719364"
print("suffix", SUF)

# ── §5.1 registration ───────────────────────────────────────────────────────
r = requests.post(f"{BASE}/auth/register", json={
    "username": f"qa_weak_{SUF}", "mpin": "111111", "role": "teacher",
    "school_id": SCHOOL, "phone": phone()})
rec("weak MPIN rejected at register (422)", r.status_code == 422, f"{r.status_code}")

ta_phone, ta_email = phone(), f"ta{SUF}@example.com"
r = requests.post(f"{BASE}/auth/register", json={
    "username": TA, "mpin": MPIN, "role": "teacher", "school_id": SCHOOL,
    "phone": ta_phone, "email": ta_email, "teachable_subjects": ["Maths"]})
rec("register teacher -> 201 pending", r.status_code == 201 and r.json()["is_approved"] is False, f"{r.status_code}")
TA_ID = r.json()["id"]
row = psql(f"select phone, email, is_approved, left(mpin_hash,7) from users where id={TA_ID}")
rec("phone + email both persist", row.startswith(f"{ta_phone}|{ta_email}|f"), row)
rec("MPIN stored as bcrypt, work factor 12", row.endswith("$2b$12$"), row.split("|")[-1])

r = requests.post(f"{BASE}/auth/register", json={
    "username": TB, "mpin": MPIN, "role": "teacher", "school_id": SCHOOL, "phone": phone()})
TB_ID = r.json()["id"]

r = requests.post(f"{BASE}/auth/register", json={
    "username": ST, "mpin": MPIN, "role": "student", "school_id": SCHOOL, "phone": phone(),
    "grade": 8, "parent_username": PA, "parent_mpin": PMPIN})
rec("register student -> 201 pending", r.status_code == 201 and r.json()["is_approved"] is False, f"{r.status_code} {r.text[:120]}")
ST_ID = r.json()["id"]
prow = psql(f"select u.id, u.role, u.is_approved, u.school_id from users u join student_profiles sp "
            f"on sp.parent_user_id=u.id where sp.user_id={ST_ID}")
rec("parent auto-created + linked (pending, same school)", prow.endswith("|parent|f|1"), prow)
PA_ID = int(prow.split("|")[0])

r = requests.post(f"{BASE}/auth/register", json={
    "username": f"qa_adm_{SUF}", "mpin": MPIN, "role": "admin", "school_id": SCHOOL})
rec("self-register as admin refused (422)", r.status_code == 422, f"{r.status_code}")

# ── §5.1 pending / approve / login ──────────────────────────────────────────
r = login(TA, MPIN)
rec("login while pending -> 403 pending approval", r.status_code == 403 and "pending" in r.text, f"{r.status_code} {r.json().get('detail')}")
r = requests.get(f"{BASE}/admin/users/pending", headers=H(ADMIN))
rec("admin pending list shows the new accounts", {TA_ID, TB_ID, ST_ID, PA_ID} <= {u["id"] for u in r.json()}, f"{r.status_code}")
r = requests.post(f"{BASE}/admin/users/{TA_ID}/approve", headers=H(ADMIN))
rec("admin approves user -> 200", r.status_code == 200 and r.json()["is_approved"], f"{r.status_code}")
r = login(TA, MPIN)
ok = r.status_code == 200 and r.json()["role"] == "teacher"
rec("approved user logs in -> 200, role teacher", ok, f"{r.status_code}")
ta = r.json(); AT, RT = ta["access_token"], ta["refresh_token"]

ck = r.headers.get("set-cookie", "")
low = ck.lower()
rec("web cookie Secure; HttpOnly; SameSite=Strict; Path=/api",
    all(x in low for x in ("secure", "httponly", "samesite=strict", "path=/api")), ck.split("=")[0] + "=…; " + "; ".join(ck.split("; ")[1:]))

ca, cr = claims(AT), claims(RT)
rec("access token lifetime 60 min", abs(ca["exp"] - ca["iat"] - 3600) < 2 and ca.get("type") == "access", f"{ca['exp']-ca['iat']}s type={ca.get('type')}")
rec("refresh token: separate JWT, type=refresh, 30 days", cr.get("type") == "refresh" and abs(cr["exp"] - cr["iat"] - 30 * 86400) < 2 and cr["jti"] != ca["jti"], f"{(cr['exp']-cr['iat'])/86400}d")
rec("refresh token refused as a bearer", me(RT) == 401, str(me(RT)))
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": AT})
rec("access token refused at /refresh", r.status_code == 401, f"{r.status_code}")

# ── wrong MPIN + lockout counter ────────────────────────────────────────────
r = login(TA, "000001")
rec("wrong MPIN -> 401 'Invalid username or MPIN.'", r.status_code == 401 and r.json()["detail"] == "Invalid username or MPIN.", f"{r.status_code} {r.json().get('detail')}")
r2 = login(f"qa_nobody_{SUF}", "000001")
rec("unknown username answers identically", r2.status_code == 401 and r2.json() == r.json(), f"{r2.status_code}")
codes = [login(TA, "000001").status_code for _ in range(3)]
cnt = redis("--scan", "--pattern", f"'failed_logins:{TA_ID}:*'")
val = redis("get", f"'{cnt.splitlines()[0]}'") if cnt else ""
rec("4 failures counted, not yet locked", codes == [401] * 3 and val == "4", f"{codes} counter={val}")
r = login(TA, MPIN)
left = redis("--scan", "--pattern", f"'*{TA_ID}*'")
left = [k for k in left.splitlines() if k.startswith(("failed_logins", "lockout"))]
rec("correct MPIN after 4 wrong -> 200 and counters cleared", r.status_code == 200 and not left, f"{r.status_code} keys={left}")
ta = r.json(); AT, RT = ta["access_token"], ta["refresh_token"]

# ── lockout (5 failures) on TB, then rate limit on an unknown name ──────────
seq = []
for i in range(11):
    r = login(TB, "000001")
    seq.append((r.status_code, r.json().get("detail", "")[:26], r.headers.get("Retry-After")))
codes = [s[0] for s in seq]
rec("5 wrong -> account locked (6th..10th 429, Retry-After 900)",
    codes[:5] == [401] * 5 and codes[5:10] == [429] * 5 and seq[5][2] == "900" and "locked" in seq[5][1], str(codes))
rec("11th attempt in a minute -> 429 rate limit (Retry-After 60)", seq[10][0] == 429 and seq[10][2] == "60", str(seq[10]))
lk = redis("--scan", "--pattern", f"'lockout:user:{TB_ID}:*'").splitlines()
ttl = redis("ttl", f"'{lk[0]}'") if lk else "no lockout key"
rec("lockout TTL ~15 min", ttl.isdigit() and 840 <= int(ttl) <= 900, ttl)
seq = [login(f"qa_ghost_{SUF}", "000001").status_code for _ in range(11)]
rec("unknown username: 10x401 then 429 (per IP+username limit)", seq == [401] * 10 + [429], str(seq))

# ── refresh rotation ────────────────────────────────────────────────────────
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": RT})
ok = r.status_code == 200
RT_OLD, RT = RT, (r.json()["refresh_token"] if ok else RT)
AT2 = r.json()["access_token"] if ok else AT
rec("refresh -> 200 with new access + rotated refresh", ok and RT != RT_OLD and me(AT2) == 200, f"{r.status_code}")
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": RT_OLD})
rec("old refresh token refused after rotation (401)", r.status_code == 401, f"{r.status_code}")
c = me(RT_OLD)
rec("rotated-out refresh token refused as a bearer", c == 401, str(c))
rec("old refresh JTI blacklisted in Redis", redis("exists", f"'revoked_jti:{claims(RT_OLD)['jti']}'") == "1" or
    any(claims(RT_OLD)["jti"] in k for k in redis("--scan", "--pattern", f"'*{claims(RT_OLD)['jti']}*'").splitlines()),
    redis("--scan", "--pattern", f"'*{claims(RT_OLD)['jti']}*'"))

# ── logout ──────────────────────────────────────────────────────────────────
r = requests.put(f"{BASE}/auth/fcm-token", headers=H(AT2), json={"fcm_token": f"qa-fcm-{SUF}"})
fcm_before = psql(f"select fcm_token from users where id={TA_ID}")
r = requests.post(f"{BASE}/auth/logout", headers=H(AT2), json={"refresh_token": RT})
rec("logout -> 204", r.status_code == 204, f"{r.status_code}")
rec("logout: access token revoked (401)", me(AT2) == 401, str(me(AT2)))
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": RT})
rec("logout: refresh token revoked (401)", r.status_code == 401, f"{r.status_code}")
c = me(RT)
rec("logout: the revoked refresh token refused as a bearer", c == 401, str(c))
fcm_after = psql(f"select coalesce(fcm_token,'<null>') from users where id={TA_ID}")
rec("logout: FCM token cleared", fcm_before == f"qa-fcm-{SUF}" and fcm_after == "<null>", f"{fcm_before} -> {fcm_after}")
rec("the earlier access token (other JTI) still valid — logout is per-session", me(AT) == 200, str(me(AT)))

print("… waiting 61 s for the per-username login rate window", flush=True)
time.sleep(61)

# ── deactivate / reactivate ─────────────────────────────────────────────────
r = requests.patch(f"{BASE}/admin/users/{TA_ID}/active", headers=H(ADMIN), json={"is_active": False})
rec("admin deactivates user -> 200", r.status_code == 200 and r.json()["is_active"] is False, f"{r.status_code}")
r = login(TA, MPIN)
rec("deactivated user cannot log in (403)", r.status_code == 403 and "deactivated" in r.text, f"{r.status_code} {r.json().get('detail')}")
c = me(AT)
rec("deactivated user's live access token refused", c in (401, 403), str(c))
def ws_opens(uid, tok):
    import asyncio, websockets
    async def go():
        try:
            async with websockets.connect(f"ws://localhost:8000/ws/{uid}?token={tok}", open_timeout=5) as ws:
                try:
                    await asyncio.wait_for(ws.recv(), timeout=1.5)
                except asyncio.TimeoutError:
                    return True
                return True
        except Exception as e:
            return f"refused ({type(e).__name__})"
    return asyncio.run(go())
w = ws_opens(TA_ID, AT)
rec("deactivated user's WebSocket refused", w is not True, str(w))
r = requests.patch(f"{BASE}/admin/users/{TA_ID}/active", headers=H(ADMIN), json={"is_active": True})
w = ws_opens(TA_ID, AT)
rec("re-activated user's WebSocket opens (control)", w is True, str(w))
r = login(TA, MPIN)
rec("re-activated user logs in again", r.status_code == 200, f"{r.status_code}")
ta = r.json(); AT, RT = ta["access_token"], ta["refresh_token"]

# ── MPIN reset = forced revocation ──────────────────────────────────────────
r = requests.put(f"{BASE}/admin/users/{TA_ID}", headers=H(ADMIN), json={"new_mpin": "222222"})
rec("weak MPIN rejected at admin reset (422)", r.status_code == 422, f"{r.status_code}")
time.sleep(1.1)
r = requests.put(f"{BASE}/admin/users/{TA_ID}", headers=H(ADMIN), json={"new_mpin": MPIN2})
rec("admin MPIN reset -> 200", r.status_code == 200, f"{r.status_code} {r.text[:100]}")
c = me(AT)
rec("force-revoked: access token issued before the reset -> 401", c == 401, str(c))
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": RT})
rec("force-revoked: refresh token issued before the reset -> 401", r.status_code == 401, f"{r.status_code}")
rec("old MPIN no longer works", login(TA, MPIN).status_code == 401)
time.sleep(1.1)
r = login(TA, MPIN2)
rec("new MPIN works", r.status_code == 200, f"{r.status_code}")
ta = r.json(); AT, RT = ta["access_token"], ta["refresh_token"]

# ── §5.7 admin: reject pending, admin/owner self-delete ─────────────────────
r = requests.delete(f"{BASE}/admin/users/{TB_ID}/pending", headers=H(ADMIN))
gone = psql(f"select count(*) from users where id={TB_ID}")
rec("reject pending user -> 204, row hard-deleted, no 500", r.status_code == 204 and gone == "0", f"{r.status_code} rows={gone}")
r = requests.delete(f"{BASE}/admin/users/{TA_ID}/pending", headers=H(ADMIN))
rec("reject refuses an already-approved user (400)", r.status_code == 400, f"{r.status_code}")
r = requests.delete(f"{BASE}/auth/account", headers=H(ADMIN))
alive = psql(f"select deleted_at is null and is_active from users where id={ADMIN_ID}")
rec("DELETE /auth/account as admin -> 403, account intact", r.status_code == 403 and alive == "t", f"{r.status_code} alive={alive}")
ow = login("chinmay_owner", "123456", school=None)
if ow.status_code == 200:
    r = requests.delete(f"{BASE}/auth/account", headers=H(ow.json()["access_token"]))
    alive = psql(f"select deleted_at is null and is_active from users where id={ow.json()['user_id']}")
    rec("DELETE /auth/account as owner -> 403, account intact", r.status_code == 403 and alive == "t", f"{r.status_code} alive={alive}")
else:
    rec("owner login for self-delete check", False, f"{ow.status_code}")
r = requests.get(f"{BASE}/admin/users", headers=H(AT))
rec("teacher on an admin endpoint -> 403", r.status_code == 403, f"{r.status_code}")

# ── §4.1 student / parent deletion ──────────────────────────────────────────
for uid in (ST_ID, PA_ID):
    requests.post(f"{BASE}/admin/users/{uid}/approve", headers=H(ADMIN))
s = login(ST, MPIN); p = login(PA, PMPIN)
rec("student and auto-created parent both log in once approved", s.status_code == 200 and p.status_code == 200 and p.json()["role"] == "parent", f"{s.status_code}/{p.status_code}")
SAT, PAT, PRT = s.json()["access_token"], p.json()["access_token"], p.json()["refresh_token"]
r = requests.delete(f"{BASE}/auth/account", headers=H(SAT))
rec("student self-delete -> 403", r.status_code == 403 and me(SAT) == 200, f"{r.status_code}")
requests.put(f"{BASE}/auth/fcm-token", headers=H(SAT), json={"fcm_token": "qa-s"})
requests.put(f"{BASE}/auth/fcm-token", headers=H(PAT), json={"fcm_token": "qa-p"})
r = requests.delete(f"{BASE}/auth/account", headers=H(PAT), json={"refresh_token": PRT})
rec("parent self-delete -> 204", r.status_code == 204, f"{r.status_code}")
rows = psql(f"select id, deleted_at is not null, is_active, coalesce(fcm_token,'<null>') from users where id in ({PA_ID},{ST_ID}) order by id")
exp = sorted([f"{PA_ID}|t|f|<null>", f"{ST_ID}|t|f|<null>"], key=lambda x: int(x.split("|")[0]))
rec("soft delete: deleted_at set, is_active false, FCM cleared — parent and cascaded child", rows.splitlines() == exp, rows.replace("\n", " ; "))
rec("deletion revokes the access token", me(PAT) == 401, str(me(PAT)))
r = requests.post(f"{BASE}/auth/refresh", json={"refresh_token": PRT})
rec("deletion revokes the refresh token", r.status_code == 401, f"{r.status_code}")
rec("cascaded child's live access token refused", me(SAT) == 401, str(me(SAT)))
a = login(PA, PMPIN); b = login(ST, MPIN)
rec("deleted users cannot log in (401, same text as unknown user)",
    a.status_code == b.status_code == 401 and a.json()["detail"] == "Invalid username or MPIN.", f"{a.status_code}/{b.status_code}")
aud = psql(f"select action, admin_id, target_id, school_id from audit_logs where target_id in ({PA_ID},{ST_ID}) and action like 'self_delete%' order by id")
rec("AuditLog rows: self_delete + self_delete_cascade_child",
    aud.splitlines() == [f"self_delete|{PA_ID}|{PA_ID}|1", f"self_delete_cascade_child|{PA_ID}|{ST_ID}|1"], aud.replace("\n", " ; "))

# teacher self-delete (cleans up TA)
r = requests.delete(f"{BASE}/auth/account", headers=H(AT), json={"refresh_token": RT})
row = psql(f"select deleted_at is not null, is_active from users where id={TA_ID}")
aud = psql(f"select count(*) from audit_logs where target_id={TA_ID} and action='self_delete'")
rec("teacher self-delete -> 204, soft-deleted, audited, token dead", r.status_code == 204 and row == "t|f" and aud == "1" and me(AT) == 401, f"{r.status_code} {row} audit={aud}")

# ── §3.5 CORS ───────────────────────────────────────────────────────────────
def preflight(origin):
    return requests.options(f"{BASE}/auth/login", headers={
        "Origin": origin, "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type"})
r = preflight("https://evil.example")
rec("CORS: foreign origin gets no Access-Control-Allow-Origin", "access-control-allow-origin" not in r.headers, f"{r.status_code} {r.headers.get('access-control-allow-origin')}")
r = preflight("http://localhost:5001")
rec("CORS: allowed origin echoed exactly, never '*'", r.headers.get("access-control-allow-origin") == "http://localhost:5001", f"{r.status_code} {r.headers.get('access-control-allow-origin')}")

fails = [x for x in RESULTS if not x[1]]
print(f"\n{len(RESULTS) - len(fails)} PASS / {len(fails)} FAIL  (suffix {SUF}; ids TA={TA_ID} TB={TB_ID} ST={ST_ID} PA={PA_ID})")
for f in fails:
    print("  FAIL:", f[0], "|", f[2])
sys.exit(1 if fails else 0)
