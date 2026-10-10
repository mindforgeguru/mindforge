# Mindforge — Testing Record

**Last updated:** 2026-10-10
**Maintainer:** chinmay1975@gmail.com
**Scope:** Reference document for every kind of testing performed on the Mindforge app — automated tests, security/privacy verification, and manual QA. Update this file every time a significant test session is run.

> **Companion file.** This record tracks *what was run and when*.
> [`SECURITY_RISK_REGISTER.md`](SECURITY_RISK_REGISTER.md) tracks *what could go wrong*
> — every risk class scored verified / stale / open, including the ones nothing here
> covers yet. Update both when a security gap closes.
>
> **How to use this file.** Each section has a checklist with a status column. When you run a check, set the status to `PASS` / `FAIL` / `SKIP` / `NOT RE-VERIFIED` and add the date. Old results are kept in the "History" section at the bottom so we can see drift over time.
>
> **A status carried forward from an earlier session is not evidence.** If you didn't re-run it, mark it `NOT RE-VERIFIED (last checked YYYY-MM-DD)` rather than leaving a stale `PASS` that reads as fresh. The 2026-07-24 pass relabelled a large block of §3–§4 on exactly these grounds.

---

## 1. Test Inventory

| Layer | Where | What it covers | Runs in CI? |
|---|---|---|---|
| Backend unit tests | `backend/tests/test_unit.py` (34) | JWT round-trip, refresh-token type, expiry, password hashing, login/register schema validation | **Yes** |
| Backend logout-handler tests | `backend/tests/test_logout_handler.py` (3) | FCM token clearing on logout, JWT revocation failure path | **Yes** |
| Backend WebSocket auth tests | `backend/tests/test_websocket_auth.py` (5) | `/ws/{user_id}` rejects malformed / refresh-type / mismatched-sub / revoked-JTI tokens; accepts valid matching token | **Yes** |
| Backend schema invariants | `backend/tests/test_schema_invariants.py` (4) | Models discoverable; `SET NULL` FKs are nullable; audit actor survives its author | **No — gap, see §10 item 2** |
| Backend bearer-gate tests | `backend/tests/test_bearer_token_gate.py` (3), plus 3 account-check cases in `test_websocket_auth.py` | The per-request dependency refuses a refresh token and a deactivated account; the socket's own account check refuses deactivated and unapproved accounts | **Yes** (glob) |
| Backend tenancy unit tests | `backend/tests/test_tenancy.py` (19) | `require_school_id`, `same_school_or_404` (404 not 403), `assert_school_active` (suspension, owner exemption), cached student profile carries `school_id`, every tenant model has a `school_id` column | **No — gap, see §10 item 2** |
| Backend tenancy wiring tests | `backend/tests/test_tenancy_wiring.py` (8) | `get_current_user` and `/auth/refresh` both enforce school suspension; owner is not gated | **No — gap, see §10 item 2** |
| Backend realtime fan-out tests | `backend/tests/test_realtime_fanout.py` (8) | Grade audience resolution (students + parents, dedup), explicit user-ID addressing, empty audience publishes nothing, `broadcast_to_users` delivery | **No — gap, see §10 item 2** |
| Backend tenant-isolation integration | `backend/tests_integration/test_tenant_isolation.py` + `…_finance.py` (32) | Router-level cross-school scoping against a live stack | No — skips cleanly when the stack is down |
| Backend realtime delivery integration | `backend/tests_integration/test_realtime_delivery.py` (6) | Real WebSocket: grade broadcast reaches students + staff, `homework_added` reaches both, and neither a school-wide broadcast nor a timetable-config change crosses schools | No — same skip |
| API integration / probes | `tests/test_api.py`, `tests/security_test.py`, `tests/security_test_extended.py`, `tests/performance_test.py` | Live endpoint smoke, security probe matrix, latency | **No — the CI job is unreachable, see §10 item 3** |
| Auth / session live QA | `tests/auth_session_qa.py` (63 checks) | Registration → approval → login, lockout and rate limit, refresh rotation, logout, deactivation, MPIN-reset revocation, self-delete and its cascade — over HTTP against the local stack, reading Postgres and Redis for what the API cannot show | No — a script, not pytest; local stack only |
| Backend log-redaction tests | `backend/tests/test_log_redaction.py` (6) | The token in a WebSocket handshake path never reaches uvicorn's log; lines without one are untouched | **Yes** (glob) |
| Flutter unit tests | `frontend/test/unit/` (78, 6 files) | `AuthState`, `AuthNotifier`, `ApiClient.logoutOnServer`, models, admin setup status, owner API error messages | **Yes** |
| Flutter widget tests | `frontend/test/widget/` (11 files; 2026-10-10 added `delete_account_dialog_test.dart` and `report_problem_dialog_test.dart`, and label cases to `setup_road_card_test.dart`). `test/unit/` gained `websocket_reconnect_test.dart` the same day | `BadgeDot`, `LoginScreen`, shimmer skeletons, setup road card, **`RealtimeSync` event→cache mapping** | **Yes** |
| Flutter integration tests | `frontend/integration_test/` — `app_test.dart` (5), `all_screens_test.dart` (29) | Auth flows; every screen for every role | No — needs a simulator **and** `--dart-define=LOCAL_DEV=true`, or it hits production |
| Local stack bootstrap | `docker-compose.yml` + `docker-compose.local.yml`; test accounts documented in `docs/local-test-accounts.md` | Spin up postgres/redis/minio/backend for integration testing | Manual |

**How to run everything locally:**

```bash
# Backend — run each file in its own process (see §10 item 4 for why)
cd backend
for f in tests/test_*.py; do python3 -m pytest "$f" -q; done
# ...or the whole suite in one session, which also passes today:
python3 -m pytest tests -q

# Backend integration (needs the local stack up first)
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml up -d
python3 -m pytest tests_integration -q

# Flutter unit + widget
cd frontend
flutter test test/unit/ test/widget/ --reporter compact

# Flutter integration (needs a connected device or simulator)
flutter test integration_test/
```

> Local backend runs need `APP_ENV=local` — `app/core/config.py` refuses to start under `APP_ENV=production` with default credentials. Docker runs need `--env-file .env.local`.

---

## 2. Latest Automated Test Run

**Date:** 2026-10-10 — every automated suite re-run today (backend unit + integration, Flutter unit/widget/integration, both security probe suites, auth/session live QA)
**Branch:** `create_school` at `3271d34`, **with uncommitted work in the tree** (Whiteprint login redesign, `LoginKeys` test handles, dashboard header + MPIN layout fixes, web CSP `img-src`)
**Environment:** macOS (darwin 25.6.0), Flutter 3.44.0, local Docker stack up (`/api/health` 200), iOS simulator iPhone 17 Pro (iOS 26.2) for integration tests; 2026-09-13 backend suite run inside `mindforge_backend` (Python 3.11, full `requirements.txt` + `pytest pytest-asyncio`, mirroring CI)

> **Where to run the backend suite.** The host `python3.12` lacks `sentry_sdk` and `google-genai`, so `test_alerting.py`, `test_prompt_injection_defence.py` and `test_websocket_auth.py` fail there at import (as of 2026-10-09 also `test_ai_fallback_chain.py`, `test_old_test_upload.py` and `test_subjects.py` — the host's `google-genai` lacks `types.GenerateContentConfig`) — an environment gap, not a defect. Conversely the container only mounts `backend/`, so `test_prod_guard.py` (reads `tests_integration/`) errors and `test_secrets_gitignore.py` skips (no git). Each file below is reported from the environment that can actually run it.

### 2.1 Backend unit — each file in its own pytest process (mirrors CI) — **re-run 2026-10-10: 430 PASS**

2026-10-10: every `tests/test_*.py` file in its own process inside `mindforge_backend` (Python 3.11, `pytest pytest-asyncio` installed for the run) — **385 passed**, with the three known container gaps run on the host instead: `test_prod_guard.py` 24, `test_secrets_gitignore.py` 12, and the 3 host-only cases in `test_subjects.py` / `test_server_header.py`. **424 passed, 0 failed** across 38 files (was 418; +3 `test_bearer_token_gate.py`, +3 in `test_websocket_auth.py`). Re-run the same way in the evening after the log-redaction fix: **430 passed** across 39 files (+6 `test_log_redaction.py`).


2026-10-09: every `tests/test_*.py` file in its own process, on the host in a Python 3.12 venv carrying PyJWT 2.15.1 plus `google-genai==2.2.0` and `sentry-sdk` (the host's own `python3.12` can't import 6 files — see the note above). **412 passed, 0 failed**, including the new `test_jwt_library.py` (11) and `test_owner_school_create.py` (2). Not re-run in the container this time: the running `mindforge_backend` was serving another worktree (§10 item 21).

Previous run (2026-09-13):

| Suite | Result |
|---|---|
| 28 files in the container | **PASS — all green**, file-by-file |
| `test_prod_guard.py` (host) | **PASS — 24/24** |
| `test_secrets_gitignore.py` (host) | **PASS — 12/12** |
| `test_attendance_window.py` *(new, uncommitted)* | **PASS — 9/9** |
| **Whole suite in one session** (container, `--ignore` prod_guard) | **PASS — 295 passed, 12 skipped** (the 12 skips are the gitignore tests, green on host) |

Total: **331 backend unit tests pass** (295 container + 24 prod_guard + 12 gitignore on host) (was 81 on 2026-07-24).

### 2.2 Backend integration (live local stack) — **re-run 2026-10-10 on the fixed code: 77/77 PASS in 170 s** (the table below is the 2026-09-13 breakdown)

> `tests_integration/` reads `../../.env.local`, so it must run **from the host** (`cd backend && python3 -m pytest tests_integration/...`). Inside the container it fails at collection with `FileNotFoundError: /app/tests_integration/../../.env.local`.

| Suite | Result |
|---|---|
| `test_tenant_isolation.py` | **PASS — 24/24** |
| `test_tenant_isolation_finance.py` | **PASS — 13/13** |
| `test_parent_child_linking.py` | **PASS — 12/12** |
| `test_realtime_delivery.py` | **PASS — 6/6** |
| `test_homework_review_gate.py` *(new, uncommitted)* | **PASS — 3/3** |
| **`tests_integration/` total** | **PASS — 58/58** in 131 s |

### 2.3 Frontend

| Suite | Result |
|---|---|
| `flutter test` (unit + widget, everything) | **PASS — 197/197** (2026-10-10 night; 173 at the start of the day, +24 from the seven frontend fixes in §9) |
| `flutter analyze lib test integration_test` | **PASS — 0 errors, 0 warnings, 39 style infos** (2026-10-10, unchanged) |
| `integration_test/app_test.dart` (iPhone 17 Pro sim, iOS 26.2, `LOCAL_DEV=true`) | **PASS — 5/5** (2026-10-10) |
| `integration_test/all_screens_test.dart` (same) | **PASS — 29/29** (2026-10-10, 10 m 47 s; no overflow or framework exception in the log) |

The infos: 33 `prefer_const_constructors` across the role screens, 4 `no_leading_underscores_for_local_identifiers`, 1 `prefer_const_declarations`, 1 `dangling_library_doc_comments`. CI runs `--no-fatal-infos`, so none break the build.

> Both integration suites were run twice on 2026-10-10: in the afternoon, and again in the evening at `f4b0234` — every fix in §9 except the two-factor prompt (`573ba63`), which landed from a separate session while the second run was in progress. 5/5 and 29/29 both times, no overflow or framework exception in the log. The two-factor fix is covered by `flutter test` 190/190.

### 2.4 Not run this session

| Suite | Why / last result |
|---|---|
| `tests/performance_test.py` | Not run. Point at the **local** stack only |
| `tests/security_test.py`, `security_test_extended.py` | **Re-run 2026-10-10** on the local stack after the bearer-gate fix: 22 PASS / 1 expected FAIL (HTTPS on `http://localhost`) / 0 WARN, and 48/48 — same as 2026-10-09 |
| `pip-audit` | Not run this session |
| Manual QA (§5) | 2026-10-10: §5.1 and the API rows of §5.7 over the API; §5.3, §5.7 and parts of §5.4–§5.6 and §5.8 by hand on the simulator. Still unticked: taking a test, homework submission from the student side, presentations, push notifications, the web-only rows, most of §5.10 |

---

## 3. Backend Security Audit

### 3.1 HTTP security headers — **re-verified live 2026-07-24**

`curl https://api.mindforge.guru/api/health` → `HTTP/2 200`, body `{"status":"ok","app":"MIND FORGE"}`, 0.27–0.31 s warm.

| Header | Status | Live value (2026-07-24) |
|---|---|---|
| `Strict-Transport-Security` | **PASS** | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | **PASS** | `nosniff` |
| `X-Frame-Options` | **PASS** | `DENY` |
| `Content-Security-Policy` | **PASS** | `default-src 'none'` |
| HTTPS enforced | **PASS** | HTTP/2 only; `server: railway-hikari` |

Source: `backend/main.py` — `SecurityHeadersMiddleware` (~line 220). Headers are applied to error responses too — a `HEAD` to the same path returns 405 and still carries all four.

> Note: the edge `server` header is now `railway-hikari` (was `railway-edge` in the 2026-05-19 record). Cosmetic; it still overrides uvicorn's banner.

### 3.2 Authentication & sessions — **re-verified live 2026-10-10**

Every row below was driven over HTTP against the local stack by `tests/auth_session_qa.py` (63/63 after the fix), with Postgres and Redis read directly where the API cannot show the result. **Two rows failed on the first run and were fixed the same day** — see §9.

| Check | Status | Evidence (2026-10-10) |
|---|---|---|
| MPINs stored as bcrypt hash (work factor 12) | **PASS** | a freshly registered row's `mpin_hash` starts `$2b$12$` |
| Access tokens are short-lived JWTs (60 min) | **PASS** | `exp − iat` = 3600 s, `type=access` |
| Refresh tokens are separate JWTs (30 days) with `type=refresh` | **PASS** | 30 d, own `jti`; an access token is refused at `/auth/refresh` (401) |
| **A refresh token is not accepted as a bearer** | **PASS — was FAIL** | was 200 on `/auth/me`, including after logout and after rotation; now 401 in all three cases. `test_bearer_token_gate.py` |
| Refresh tokens rotate on use; old JTI blacklisted | **PASS** | new pair returned; the old token → 401; `revoked_jti:<jti>` present in Redis |
| Logout revokes access-token JTI in Redis | **PASS** | same bearer → 401 afterwards; a second session's token keeps working |
| Logout revokes refresh-token JTI when client sends it | **PASS** | `/auth/refresh` → 401 |
| Logout clears the user's FCM token | **PASS** | `users.fcm_token` set, then NULL after logout; also `test_logout_handler.py` |
| Web session cookie `Secure; HttpOnly; SameSite=Strict; Path=/api` | **PASS** | `Set-Cookie: session=…; HttpOnly; Max-Age=3600; Path=/api; SameSite=strict; Secure` |
| Login rate-limited per (IP, username) | **PASS** | unknown username: 10 × 401, then 429 with `Retry-After: 60` |
| Account lockout after repeated failed logins (15 min) | **PASS** | 5 × 401, then 429 "temporarily locked", `Retry-After: 900`, lock key TTL 900 s. 4 wrong then the right MPIN → 200 and the counters are gone |
| Deactivated / soft-deleted users cannot log in | **PASS** | deactivated → 403 "deactivated"; soft-deleted → 401, same text as an unknown user |
| **A deactivated user's live session ends** | **PASS — was FAIL** | an access token issued before deactivation was 200; now 401, and the WebSocket handshake is refused. Re-activation restores both |
| Pending accounts cannot log in | **PASS** | 403 "pending admin approval"; 200 once approved |
| MPIN reset ends existing sessions | **PASS** | access and refresh tokens issued before an admin reset → 401; old MPIN 401, new MPIN 200 |
| Wrong MPIN and unknown username answer identically | **PASS** | same status and body |
| **Suspended school blocks login and refresh; owner exempt** | **PASS** | `test_tenancy_wiring.py` 8/8, re-run today |

### 3.3 Transport security — **partially re-verified 2026-07-24**

| Check | Status | Source / evidence |
|---|---|---|
| Mobile app CA-pins Let's Encrypt (not leaf-pinned) | **PASS** | `frontend/lib/core/security/ssl_pinning.dart` — pins the issuer org, with known-good leaf fingerprints kept as a fast path / audit trail |
| Current leaf expiry tracked | **PASS** | Current leaf expires **2026-08-27** (issued 2026-05-29, Let's Encrypt YE1). Under CA pinning a leaf rotation is no longer a release-blocking event |
| Refresh tokens in OS secure storage | NOT RE-VERIFIED | `flutter_secure_storage` in `auth_provider.dart` |

### 3.4 Secrets & error reporting — **NOT RE-VERIFIED (last checked 2026-05-19)**

| Check | Status | Source |
|---|---|---|
| No secrets committed in repo | NOT RE-VERIFIED | `.env` / `.env.local` gitignored |
| Sentry scrubs MPIN/password/token/cookie keys | NOT RE-VERIFIED | `backend/main.py` — `_SCRUB_KEYS`, `_scrub_event` |
| Sentry `send_default_pii=False` | NOT RE-VERIFIED | `backend/main.py` |
| Admin seed MPIN from `ADMIN_SEED_MPIN`, skipped + warned if missing/invalid | **PASS** (spot-checked) | `backend/main.py:134` |
| Firebase **client** API keys are public by design; server secret is `FIREBASE_CREDENTIALS_JSON`, env-only | **PASS** (documented) | `SECURITY.md` — console-side key restriction confirmed in place 2026-08-21 (§10 item 7) |

### 3.5 API surface — **partially re-verified 2026-07-24**

| Check | Status | Source |
|---|---|---|
| `/api/media/{bucket}/{key}` allowlists buckets (profiles only) | **PASS** (spot-checked) | `backend/main.py:362` — `ALLOWED_BUCKETS` |
| CORS forbids wildcard origin | **PASS** (2026-10-10, local) | preflight from `https://evil.example` gets no `Access-Control-Allow-Origin` (400); `http://localhost:5001` is echoed exactly, never `*` |
| WebSocket requires JWT, validates `sub == user_id`, rejects revoked JTIs | **PASS** | `test_websocket_auth.py`, re-run today (5/5) |
| Cross-school row access returns 404, not 403 | **PASS** | `test_tenancy.py::TestSameSchoolOr404`, re-run today |
| Every tenant-scoped model carries `school_id`, and the migration list matches the models | **PASS** | `test_tenancy.py::TestTenantModelContract`, re-run today |

---

## 4. Privacy Audit

### 4.1 Account deletion — **backend re-verified live 2026-10-10; the in-app screens not re-checked**

Driven end to end by `tests/auth_session_qa.py` on the local stack: a teacher self-deletes, and a parent self-deletes with one linked student.

| Check | Status |
|---|---|
| In-app "Delete my account" in teacher/parent profile | NOT RE-VERIFIED (UI; last checked 2026-05-14) |
| Student profile offers no self-delete, and the API refuses it | **PASS** (API, 2026-10-10) — `DELETE /api/auth/account` as a student → 403, account intact. *This row used to list students as able to self-delete; the policy changed 2026-05-14 — a parent or admin removes a student.* UI not re-checked |
| Admin cannot self-delete | **PASS** (API, 2026-10-10) — 403, account intact. UI not re-checked |
| **Owner cannot self-delete** | **PASS** (2026-10-10) — 403, account intact |
| Deletion is soft (`deleted_at` + `is_active=False`) | **PASS** (2026-10-10) — read from Postgres |
| A parent's deletion cascades to the one linked student | **PASS** (2026-10-10) — both rows soft-deleted |
| Deletion revokes access + refresh token JTIs | **PASS** (2026-10-10) — both → 401; the cascaded child's live token → 401 too |
| Deletion clears FCM push token | **PASS** (2026-10-10) — NULL on parent and child |
| Deletion writes an `AuditLog` row (`action="self_delete"`) | **PASS** (2026-10-10) — plus `self_delete_cascade_child` for the student, both school-scoped |
| Deleted user cannot log in | **PASS** (2026-10-10) — 401, same text as an unknown username |

### 4.2 Privacy policy

| Check | Status | Notes |
|---|---|---|
| Draft policy authored | **PASS** | `PRIVACY_POLICY.md` |
| Policy reviewed by counsel | **PENDING** | Recommended before store submission |
| Policy hosted at public URL | **PENDING** | |
| `AppConstants.privacyPolicyUrl` populated | **PENDING** (re-checked 2026-07-24) | Still `''` at `frontend/lib/core/utils/constants.dart:30`. The in-app link auto-hides while empty |
| URL entered in Play Console / App Store Connect | **PENDING** | |
| Policy covers **Anthropic/Claude** as an AI recipient | **PENDING** | New since the policy was written — see §4.3 |

### 4.3 Third-party PII flow

| Recipient | Receives PII? | Verified |
|---|---|---|
| **Anthropic (Claude)** | Prompt content + uploaded files via the Files API | **NOT VERIFIED — new recipient.** Claude became the *primary* generation provider (2026-06-08, `ai_service.py` pipeline is Claude → Gemini → Groq). The May PII sweep predates it. Re-run the prompt audit and update `PRIVACY_POLICY.md` §5/§7 |
| Gemini | Prompt content only | NOT RE-VERIFIED (clean as of 2026-05-14) |
| Groq | Text extracted from files | NOT RE-VERIFIED (clean as of 2026-05-14) |
| Sentry (backend) | No real PII — `send_default_pii=False` + scrubber | NOT RE-VERIFIED |
| Firebase Crashlytics | Crash trace + device metadata | NOT RE-VERIFIED |
| Firebase Analytics | Event + screen names | NOT RE-VERIFIED |
| FCM | Device token + notification payload | NOT RE-VERIFIED |
| MinIO | Profile pictures + uploads | NOT RE-VERIFIED — avatar keys made unguessable 2026-07-07 |

Standing caveat (still applies): teacher-uploaded PDFs may themselves contain student names (scanned answer sheets). Disclosed in `PRIVACY_POLICY.md` §5.

### 4.4 Data subject rights coverage

| Right | Mechanism |
|---|---|
| Access | Profile screens display all per-user data; admins can export |
| Correction | Edit profile in-app; admin tools for the rest |
| Deletion | In-app self-delete (§4.1); parent can act for a minor |
| Withdraw consent | Equivalent to deletion |

---

## 5. Manual Functional QA Checklist

Run end-to-end before every release build. Tick PASS/FAIL with date.
**None of §5 was executed on 2026-07-24** — this session was automated suites + CI/live-endpoint verification only.

### 5.1 Auth flows

- [x] **Register student** → pending screen — PASS 2026-10-10 (API: 201, `is_approved=false`; screen not viewed)
- [x] **Register teacher** → pending screen — PASS 2026-10-10 (API: 201, `is_approved=false`; screen not viewed)
- [x] **Register parent (auto-created from student registration)** → exists in DB — PASS 2026-10-10 (pending parent row in the same school, linked from the student profile; logs in with its own MPIN once approved)
- [ ] **Register with Phone + Email on the wide/web form** → both persist (fixed 2026-07-22) — *partial 2026-10-10: both persist through the API; the web form itself not driven*
- [x] **Login while pending** → "pending approval" message — PASS 2026-10-10 (403 "Your account is pending admin approval. Please wait.")
- [x] **Admin approves user** → user can now log in — PASS 2026-10-10
- [x] **Login with correct MPIN** → correct dashboard for role — PASS 2026-10-09 (web: teacher `chinmay_sir`, students `dummy8` + `river_kid`; sim: admin, teacher, student, parent via `all_screens_test`)
- [x] **Login with wrong MPIN** → 401 "Invalid username or MPIN" — PASS 2026-10-10 (an unknown username gets the identical reply)
- [x] **Login 11 times wrong** → 429 rate limit — PASS 2026-10-10. For a real account the lockout arrives first: 5 × 401, then 429 "temporarily locked" (`Retry-After: 900`); the 11th in a minute is the rate limit (`Retry-After: 60`). For an unknown username: 10 × 401, then 429
- [x] **Login 4 wrong, then correct** → lockout counter clears — PASS 2026-10-10 (counter read 4 in Redis, then gone). *Was "5 wrong": the fifth failure is the one that locks, so a correct MPIN after it is refused for 15 minutes*
- [x] **Weak/blocklisted MPIN rejected at set/change time** (added 2026-07-07) — PASS 2026-10-10 at register and at admin reset (422); self-service change not driven (covered by unit tests)
- [x] **Logout** → access + refresh JTIs blacklisted, FCM cleared, secure storage cleared — PASS 2026-10-10: server side over the API (access 401, refresh 401, `fcm_token` NULL); on the simulator, Log Out (with its confirm prompt) returns to the login screen for parent and teacher, and relaunching the app stays logged out. Secure storage not inspected directly
- [ ] **Access token expiry (~60 min)** → Dio interceptor auto-refreshes
- [x] **Force-revoked token** → next protected call 401 — PASS 2026-10-10 (admin MPIN reset; deactivation, **after the fix in §9**; account deletion)

### 5.2 Multi-tenancy & owner *(feature landed 2026-07-22; full pass 2026-10-09)*

Run 2026-10-09 against the local stack: API checks with real tokens (script in the §9 entry), the owner console in the web build, and `tests_integration/test_tenant_isolation*.py` re-run **37/37**. Two throwaway schools ("QA Tenancy A/B 42441", ids 173/174) were created for the suspension checks and left **suspended** afterwards, so they are out of the picker.

- [x] Platform owner logs in and lands on the owner dashboard — PASS 2026-10-09 (login with no school → role `owner`; dashboard lists all schools with per-role counts, Add Admin / Suspend)
- [x] Owner can create a school; admin for that school can log in — PASS 2026-10-09 (2 schools + 2 admins created; both admins log in; the same username against the other school → 401)
- [x] User in school A cannot read school B's rows (expect **404**, not 403) — PASS 2026-10-09 (QA admin approving Hansel's `dummy8` → 404 "User not found."; `/admin/users` holds only its own school; a school admin on owner endpoints → 403; isolation suites 24/24 + 13/13)
- [x] Suspending a school blocks its users' login **and** token refresh — PASS 2026-10-09 (login → 400 "Selected school was not found or is inactive."; refresh → 401; an already-issued access token → 403 "access has been suspended"; school leaves the public picker; the other school unaffected; reactivating restores login)
- [x] Owner is exempt from suspension gating — PASS 2026-10-09 (owner logs in and lists schools while one is suspended)
- [x] Phone-number uniqueness is scoped per school, not global — PASS 2026-10-09 (phone P in A → 201; P again in A → 409 with the generic, non-enumerating message; P in B → 201)
- [x] Fees and academic years are school-scoped — PASS 2026-10-09 via `test_tenant_isolation_finance.py` 13/13 (not re-checked by hand)
- [x] Owner error messages surface the backend detail, not a raw `DioException` — PASS 2026-10-09 (duplicate school shows the server's text). The text itself said "Choose a different slug" though the console never shows a slug — **fixed same day**: a name clash now says "A school named '…' already exists. Choose a different name."; the slug wording stays only when an API caller passed a slug (`tests/test_owner_school_create.py`). Still open: the Add School dialog closes on the error, so the typed details are lost

### 5.3 Admin school setup *(new — 2026-07-23/24)*

- [ ] Graphical school-setup workflow gates steps in the right order — *partial 2026-10-10 (simulator): the completed state renders — five done steps, Close Year unlocked, "Setup complete — tap any step to edit." The "Academic Year" label sat on top of its step; fixed, §9. Gating on a fresh school only via `setup_road_card_test`*
- [ ] School Logo setup task uploads and displays
- [ ] Close-Year workflow step completes

### 5.4 Student

- [x] Dashboard summary loads (single `/student/dashboard-summary` call) — PASS 2026-10-09 (web, `dummy8`; one call in the network log)
- [x] Attendance history paginated — PASS 2026-10-10 (API: `skip`/`limit` pages of 5, no overlap; the screen itself only via `all_screens_test`)
- [x] Test list; take a test (single-attempt: back / app-kill forfeits with 0) — PASS 2026-10-10. API, three throwaway grade-8 students: pending list and attempt payload carry no answers; autosave; submit → score; second submit 409; re-entering an in-progress attempt finalizes it (`auto_submitted`, credit for saved answers only); the test moves to Completed; a grade-10 student gets 404. Simulator, `dummy8`: Start Test → the "single attempt" warning → answer → app killed → reopening ended the attempt. **The result dialog blamed the timer with six minutes left — fixed, §9.** The in-app back path (confirm, then submit) not driven
- [x] Test review matches the per-student option shuffle — PASS 2026-10-10 (API): two students got different question and option orders; answering by the labels as shown scored 6/6; the review returns the same option mapping the student saw, with the correct-answer label remapped to it. The review lists questions in the original order, not the shuffled one
- [x] Homework list + submission; completion status auto-refreshes — PASS 2026-10-10 (simulator, §5.8: list shown, pill flipped live). There is no student-side "submission": completion is recorded by the teacher
- [ ] Fees screen
- [ ] XP card visible (mobile **and** desktop web) — *partial 2026-10-10: visible on the simulator dashboard ("Novice I — 85 / 283 XP"); desktop web not checked*
- [ ] Leaderboard; theme unlock at level threshold
- [ ] Holiday banner shows on a holiday — *not testable 2026-10-10: a Saturday with no timetable slots shows "No classes today"; the student banner needs a declared holiday on a school day (slots flagged holiday)*
- [x] Profile → Privacy & Data — PASS 2026-10-10 (simulator): the student profile offers **no** delete, matching the policy (a parent or admin removes a student). The "Privacy & Data" heading stood over an empty section — fixed same day, §9

### 5.5 Teacher

- [x] Dashboard summary loads — PASS 2026-10-10 (web and simulator, `chinmay_sir`)
- [ ] Daily Workflow road shows current grade's color; car advances per milestone
- [ ] Every milestone tappable; car replaces current pending milestone (no duplicates)
- [ ] Pre-fill attendance from previous period
- [ ] Holiday / no-class day → car advances correctly; whole-school holiday banner shows — *partial 2026-10-09: "Holiday! No classes today" banner shows on the teacher dashboard; car not checked. On the same holiday the teacher **cannot assign homework** — §10 item 18*
- [ ] HW review uses most-recent-HW model; tiles color-coded by review status
- [ ] Presentations: upload PDF and `.pptx`, adopt, log a period — *partial 2026-10-10 (API): a ten-slide `.pptx` uploaded READY with 10 slides and 2 recommended periods; a legacy `.ppt` and a non-deck file → 415 with a usable message; period log before adopt → 409; adopt → 201; period log → 201. **The chapter-PDF path (AI writes the deck) was not run**, and none of it on a screen*
- [x] Auto-quiz appears in the Online Tests tab as "Generating", then flips to ready/failed — PASS 2026-10-10 (API): `generating` in the teacher's test list immediately after the period log, `ready` 9 s later with 5 questions, unpublished until the teacher publishes; once published it showed on the student's Tests tab on the simulator with a 48-hour window. Generated by Gemini — the local stack has no Anthropic key, so the Claude leg cannot be exercised here
- [x] Retry on a failed auto-quiz card works — **was FAIL, fixed 2026-10-10**: the retry was sent (202) but when it failed again the Retry button never came back. Now PASS on the simulator. §9
- [ ] Broadcasts are shared school-wide across teachers
- [x] Profile → Privacy & Data visible — PASS 2026-10-10 (simulator; "Delete my account" present)

### 5.6 Parent

- [x] Dashboard shows linked child's data — PASS 2026-10-10 (simulator, `dummy8_dad`: the child's test marks and timetable)
- [x] Attendance / tests / homework / fees visible read-only — PASS 2026-10-10 (API, `nitin_dad`: all four return the child's data; the same token on student, teacher and admin endpoints → 403. Screens via `all_screens_test`)
- [x] Profile → Privacy & Data visible — PASS 2026-10-10 (simulator). The delete dialog shows the cascade warning and keeps Delete disabled until the username is typed; it **overflowed and errored on Cancel — both fixed same day**, §9

### 5.7 Admin

- [x] Dashboard loads, no overflow on small screens — PASS 2026-10-10 on the simulator (402 pt wide; the school name truncates to "Hansel & Gret…" beside the three header icons). Narrower widths not checked by hand
- [x] Pending users — approve flow — PASS 2026-10-10 (API). On the simulator the pending list showed a new registration after Refresh — it does not appear live, which nothing requires — with Approve and delete on the row
- [x] Pending users — reject (hard-delete) flow, no 500 — PASS 2026-10-10 (API: 204, row gone — including a pending student with its parent; an approved user → 400. Repeated on the simulator: trash icon → confirm → 204, row gone)
- [ ] Faculty approval filter — *not checked; the Active Users tab's User Type and Grade filters render (simulator, 2026-10-10)*
- [x] User management (deactivate / re-activate) — PASS 2026-10-10 (API). Deactivation now also ends the live session — §9
- [x] Feedback viewer shows in-app problem reports — **was FAIL, fixed 2026-10-10**: no report could be sent at all — Send always answered "Could not send", for every role. After the fix a report sent from the admin dashboard on the simulator returned 204 and appears in `GET /admin/feedback` with its user, role and route. The viewer screen itself was not opened. §9
- [x] Profile **does NOT** show "Delete my account" — PASS 2026-10-10 (simulator)
- [x] `DELETE /api/auth/account` as admin → 403 — PASS 2026-10-10 (owner → 403 too)

### 5.8 Realtime *(reworked 2026-07-24; first manual pass 2026-10-09, web only)*

The WebSocket fan-out was rewritten on 2026-07-24. **First manual pass 2026-10-09**, in the web build against the local stack: two users side by side, one per origin (`http://localhost:8080` and `http://localhost:5001`, the two CORS-allowed dev ports, so each keeps its own login). Not yet repeated on a device. The homework items are blocked by the holiday deadlock in §10 item 18 — re-run them on a school day.

- [ ] Teacher sends a school-wide broadcast → appears live on student / parent / other-teacher **Broadcasts screen** without navigating or refreshing
- [x] Teacher sends a **grade-targeted** broadcast → reaches that grade's students + parents, and all teachers — PASS 2026-10-09 for the student leg: grade-8 broadcast from `chinmay_sir` appeared on `dummy8`'s open Broadcasts screen in ~2 s, no refresh (web, two origins). Parent and other-teacher legs not checked
- [x] Teacher assigns homework → appears live on the student/parent homework screen **and** on other teachers' dashboards — PASS 2026-10-10 for the student leg, on a device: with `dummy8`'s Homework screen open on the simulator, a grade-8 homework assigned through the API appeared at the top within 3 s, no refresh. Done on a no-class Saturday, so it also confirms the §10 item 18 fix. Parent and other-teacher legs not checked
- [ ] Auto-quiz from a presentation period log → appears in the teacher Online Tests list immediately, without pull-to-refresh
- [x] Marking homework completion updates the student's Pending/Complete pill live — PASS 2026-10-10 on the simulator: homework 75 flipped Pending → Complete within 3 s of the teacher's `PUT …/completions` (which returned 200 with `attendance_required: false` on a no-class day)
- [ ] Attendance / timetable / grade events refresh the relevant screen live
- [x] Events do **not** leak across schools (two schools, two browsers) — PASS 2026-10-09: a Hansel & Gretel grade-8 broadcast did not reach Riverdale's grade-8 `river_kid` (screen unchanged; backend log shows no refetch by user 42 after the `POST … 201`). Riverdale's list also never showed the Hansel broadcast at rest
- [x] Backgrounding the app for >30 s then resuming reconnects once (no double-reconnect, no infinite loop) — PASS 2026-10-10 on the simulator: 40 s in the background, then exactly one new socket in the backend log. **The infinite loop did exist, on a different trigger — a server outage — and is fixed, §9.** After the fix, restarting the backend under the running app produced exactly one reconnect and nothing further for 75 s

### 5.9 Web build QA

Last executed **2026-05-19** on Flutter 3.41.7 / Chrome against the local stack. **Not re-run since**, and the web build has changed materially (sidebar nav, Firebase web config, favicon/PWA icons, CSP `blob:` for avatar upload). Treat the ticks below as historical.

- [x] Debug build (`flutter run -d chrome --web-port=5001`) loads — PASS (2026-05-19)
- [x] CORS preflight from `http://localhost:5001` returns 200 — PASS (2026-05-19)
- [x] Login + golden path on all four roles — PASS (2026-05-19)
- [x] Responsive at 375 / 768 / 1280 px — PASS (2026-05-19)
- [x] Hard refresh on a deep route keeps the user logged in — PASS (2026-05-19)
- [x] Browser back/forward navigates inside the SPA — PASS (2026-05-19)
- [x] Logout clears `mindforge_*` localStorage keys — PASS (2026-05-19)
- [x] WebSocket upgrades to 101 and pushes realtime messages — PASS (2026-05-19)
- [x] Release bundle sanity check via static server — PASS (2026-05-19)
- [x] Deep-route fallback to `index.html` — PASS (2026-05-19)
- [ ] **Firebase on web (FCM/Analytics/Crashlytics)** — was FAIL; **config added 2026-06-30**, re-test needed
- [x] Left sidebar nav renders and navigates on desktop widths (new) — PASS 2026-10-09 (student + teacher, 800 px)
- [ ] Avatar upload works through the CSP (`blob:` in `connect-src`, added 2026-07-03)
- [x] School logo + avatars **display** on a local web build — PASS 2026-10-09 after adding the local API origins to `img-src` (was FAIL: blocked by CSP, header fell back to the MindForge mark)
- [ ] MindForge favicon + PWA icons show (new)

### 5.10 Cross-cutting

- [ ] Pull-to-refresh on every list screen
- [ ] Error states show `ErrorView` with retry
- [ ] Loading states show shimmer skeletons
- [ ] Push notification received (attendance, test, fees, HW, broadcast) — *not testable locally (2026-10-10): the local backend has no Firebase credentials and no account holds a device token; the simulator is never issued one. Needs a real device against a configured backend*
- [ ] WebSocket reconnect after backgrounding (no infinite loop)
- [ ] Desktop web — student XP card visible
- [ ] All routes emit a `screen_view` analytics event

---

## 6. Release-Build QA (Android)

Release builds are **obfuscated**. Without `--obfuscate`, Dart class, method and
field names ship in the binary, so anyone unzipping the APK reads the API routes,
the auth flow and the pinning logic as source-like symbols. Added 2026-08-19.

```bash
cd frontend
V=$(grep '^version:' pubspec.yaml | awk '{print $2}')   # e.g. 1.0.0+9

flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/$V
flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols/$V
```

> **Keep `build/symbols/<version>` for every release you ship.** Obfuscation
> renames symbols, so a Crashlytics stack trace from an obfuscated build is
> unreadable without the matching symbol files — and they are the *only* copy.
> Lose them and every crash report from that build is permanently undecodable.
> Archive them outside `build/` (that directory is disposable and gitignored),
> keyed by version, before the next `flutter clean`.
>
> Upload per release so crashes stay legible:
> `firebase crashlytics:symbols:upload --app <android-app-id> build/symbols/$V`

- [ ] Release build is obfuscated (`--obfuscate --split-debug-info` both present)
- [ ] Symbol files archived for this version, outside `build/`
- [ ] Crashlytics symbols uploaded, and a forced crash **symbolicates readably**
- [ ] APK installs on a real Android device (not emulator)
- [ ] Login works on release build (catches ProGuard stripping JSON model classes)
- [ ] Push notification received on release build
- [ ] SSL pinning still works (bad cert via mitmproxy → refused). Note: pinning is now **CA-level**, so a mis-issued cert from a *different* CA is the case to test
- [ ] All dashboards load
- [ ] Crashlytics receives a forced test crash
- [ ] Sentry receives a forced backend error in prod
- [ ] App icon, splash, app name correct
- [ ] Signed with release keystore (`frontend/android/key.properties`, `mindforge-release.jks`)

---

## 7. Release-Build QA (iOS)

**Blocked** — not enrolled in the Apple Developer Program. Once enrolled:

- [ ] Xcode → Signing & Capabilities → Team picked, `DEVELOPMENT_TEAM` in `project.pbxproj`
- [ ] `flutter build ipa --release --obfuscate --split-debug-info=build/symbols/$V` succeeds
      (same symbol-retention rule as §6 — archive them per version)
- [ ] TestFlight upload + install
- [ ] Repeat §5 and §6 on the IPA build

---

## 8. CI Status

Workflow: `.github/workflows/ci.yml`. Jobs: `backend-unit`, `dependency-audit`, `flutter`, `api-integration`.

| Check | Status | Evidence |
|---|---|---|
| Latest CI run | **PASS** | Run `30119086970` on `create_school`, 2026-07-25 — **success**. First green run since 2026-06-18 |
| `pip-audit` on a runner | **PASS** | "No known vulnerabilities found, 1 ignored" — confirms the dependency work holds on CI, not just in a local venv |
| Backend unit on a runner | **PASS** | **81 tests across all 7 files** via the glob. Before this branch CI ran 3 files (42 tests) |
| Flutter unit + widget on a runner | **PASS** | 1m25s |
| `api-integration` | **SKIPPED by design** | Requires the explicit `run_api_integration` input — see §10 item 17 |
| History before the fix | 8 consecutive red runs | 2026-06-23 → 07-18, every one the `dependency-audit` job |
| CI runs on the current working branch | **NO** (unchanged) | Push triggers are `main`, `feature/**`, `fix/**`, `test/**`. `create_school` still matches none; this run was a manual `workflow_dispatch` |
| CI Flutter version matches local | **NO** | CI pins `3.41.4`; local is `3.44.0`. Untouched — §10 item 11 |

---

## 9. Past Test Sessions (History)

### 2026-10-10 (night — taking a test, presentations, and one more fix)
- **Taking a test (§5.4):** 16 API checks with throwaway students against a grade-8 test whose expiry was moved forward for the run and restored afterwards, then the same flow by hand on the simulator. Single attempt, forfeit on re-entry, no answer leakage, per-student shuffle with correct scoring and review — all as designed.
- **Found and fixed — the wrong reason on the result dialog.** A student who left mid-test was told "Time Up! Your test was auto-submitted when the timer ran out." with 06:05 on the clock. Every automatic submission used the timer's wording. Leaving — back, app closed, or opening the test again — now shows "Test Ended: You left the test, so it was submitted with the answers you had saved. A test can only be taken once." `test/widget/test_result_dialog_test.dart` (7) covers the wording and the rule that tells the cases apart (auto-submitted with time remaining). Written alongside the fix rather than before it, since the dialog was private; the failing observation is the simulator one. Re-checked on the simulator.
- **Presentations (§5.5), over the API:** deck upload, the adopt gate, period log and the auto-quiz lifecycle all work. One paid generation call was made (Gemini, 5 questions from 8 slides).
- **Worth knowing:** answers autosave every 20 s, so an app killed within 20 s of an answer loses that answer — the attempt on the simulator kept the first answer because it waited. And after the app was killed mid-test (not backgrounded — backgrounding submits) the attempt stayed open on the server until the student tapped Start Test again; whether anything finalizes it if they never do was not checked.
- **Not possible here:** push notifications (no Firebase credentials locally, no device tokens) and the web-only rows (the browser pane was hidden again).
- **Suites:** Flutter **197/197**, analyzer unchanged. No backend change in this pass.
- **Housekeeping:** the QA deck and its quiz were deleted, the old test's expiry restored, the throwaway students revoked.

### 2026-10-10 (late — the two-factor prompt's disposed controller, §10 item 22)
- **Fixed — Cancel on the two-factor prompt raised a framework error.** The same defect as the delete-account dialog this afternoon: `_promptForSecondFactor` in `login_screen.dart` created the code controller, awaited `showDialog`, and disposed it on the next line, while the dialog was still animating out with its TextField attached. The prompt is now its own widget whose State owns and disposes the controller; it pops the trimmed entry and the recovery flag, and the caller no longer reads the controller. Look, copy and the recovery-code toggle are unchanged.
- **Test first.** Three cases added to `test/widget/login_screen_test.dart`, reaching the prompt the way the app does: a fake `ApiClient` answers the sign-in with 401 `mfa_required`, and the real `AuthNotifier` turns that into `MfaRequiredException`. Before the fix the Cancel case failed with "A TextEditingController was used after being disposed" at the prompt's TextField. The other two pin what the rewrite could have broken: Verify retries with the trimmed entry as `mfaCode`, and after "I don't have my phone" as `recoveryCode`; Cancel makes no second attempt.
- **Suites after it:** Flutter **190/190** (was 187); analyzer unchanged at 0 errors, 0 warnings, 39 style infos.
- **Not done:** not driven by hand — there is still no MFA-enrolled account on the local stack, so the prompt has only been seen in the widget test. Integration suites not re-run.

### 2026-10-10 (evening — realtime on a device, the admin screens, and four more defects)
- **Realtime on the simulator (§5.8):** homework assignment and completion both reached an open student screen live, on a no-class day; background-and-resume reconnected once. Three more rows ticked.
- **Found and fixed — reconnect storm after an outage.** Reading the backend log for the resume check showed one idle web client opening about 60 sockets a second, each closed 2 ms later, 105 in 15 minutes. `WebSocketClient` scheduled a retry from each of the ways a failed socket reports itself (`ready` failing, the stream erroring, the stream closing), all in the same generation; each retry then closed whatever socket was current, and that close scheduled another. So retries multiplied while the server was unreachable — the backend had auto-reloaded several times today — and kept each other alive once it was back. Now at most one reconnect is pending, and a socket's callbacks act only while it is still the current one. `test/unit/websocket_reconnect_test.dart` (4) drives the real client against scripted sockets under fake time: before the fix, a 60-second outage produced 400+ attempts (the test's safety cap; uncapped it never finished) and no stable socket afterwards. **Live after the fix:** backend restarted under the running app → one reconnect, then quiet.
- **Found and fixed — access tokens in the server log.** The WebSocket handshake carries the JWT as `?token=`, and uvicorn logs the full path of every handshake: 110 usable access tokens in 15 minutes of local log. A logging filter on uvicorn's loggers (`app/core/log_redaction.py`) now writes `token=[redacted]`. `tests/test_log_redaction.py` (6); live, a real handshake logs `"WebSocket /ws/3?token=[redacted]" [accepted]` and a grep for `token=eyJ` finds nothing. Register updated.
- **Found and fixed — "Report a problem" never sent (§5.7).** Send answered "Could not send. Please try again." every time and no request left the app. The dialog looked up the current route from its own context, which sits above every route, so the lookup threw and the catch-all reported a send failure. Every role's report button shares the dialog. The route is now read where the dialog is opened. `test/widget/report_problem_dialog_test.dart` (3) mounts it inside a real router. On the simulator afterwards: 204, "Thanks — your report was sent.", and the row in the admin feedback list.
- **Found and fixed — the "Academic Year" label on the admin setup road** wrapped to two lines and ran over its step's circle. Labels above the road are anchored by their bottom edge now. Two cases added to `setup_road_card_test.dart`; confirmed on the simulator.
- **Admin by hand (§5.3, §5.7):** dashboard, the setup road in its completed state, pending list and on-screen reject (204, row gone), Active Users with its filters, profile without a delete option.
- **Suites after all of it, at `f4b0234`:** backend unit **430**; `tests_integration/` **77/77**; Flutter **187/187**, analyzer unchanged; Flutter integration on the simulator **5/5 and 29/29**. The two security probe suites were last run in the afternoon, before the log-redaction and client fixes.
- **Production:** `main` has the same reconnect code, the same report dialog, and uvicorn's default logging (read from git, not checked against production). So production logs very likely hold access tokens, each valid for up to an hour from issue; the shipped app's problem-report button very likely fails; and a production outage would likely start the same storm from every open client.
- **Seen, not changed:** on the admin profile's MPIN pad the "0" key sits about 4 pt left of the column above it. A new registration does not appear on an open pending list until Refresh.
- **Housekeeping:** homework 75's completion was recorded for grade 8 and stays; the QA homework (167) was deleted and the QA problem report resolved. One throwaway account was registered and rejected on screen.

### 2026-10-10 (afternoon — remaining suites, and student / teacher / parent by hand on the simulator)
- **Automated, all on today's code:** Flutter **173/173** before the fixes below and **178/178** after; analyzer unchanged; integration on the iPhone 17 Pro simulator **`app_test` 5/5, `all_screens_test` 29/29**; `security_test_extended.py` **48/48**; `security_test.py` **22 PASS / 1 expected FAIL / 0 WARN**. A read-only API sweep of 26 student and parent endpoints returned 200 throughout (two 422s were a required query parameter).
- **Found and fixed — auto-quiz Retry (§5.5).** After Retry, a quiz that failed again showed no Retry button until the teacher left the screen: the tile is keyed by test id, so its State survives the refetch, and `_retrying` was never cleared. `didUpdateWidget` now clears it when the refetched row arrives. Seen in the web build, confirmed fixed on the simulator (POST 202, "thin source" failure, Retry back). **No widget test** — the tile is private to a screen that needs most of the app's providers to mount.
- **Found and fixed — the delete-account dialog (§5.6), two defects**, both pinned by the new `test/widget/delete_account_dialog_test.dart`:
  - With the keyboard up (the field autofocuses) the parent's dialog, which carries the cascade warning, **overflowed by 41 px** and pushed "Type your username below to confirm" under the field. The dialog now scrolls.
  - **Cancel raised a framework error** — a red screen in this debug build ("`_dependents.isEmpty`", and in the test "A TextEditingController was used after being disposed"). The caller disposed the controller as soon as `showDialog` returned, while the dialog was still animating out. The dialog's State owns the controller now. Release builds skip these assertions, so users most likely saw nothing; it had also been invisible to the integration tests, which never open the dialog.
  - Both re-checked on the simulator after a rebuild.
- **Found and fixed — an empty "Privacy & Data" heading on the student profile.** No delete tile (by policy) and no policy link (URL unset, §10 item 6) left the heading over nothing. It is now hidden when the section has no rows.
- **Open — the same disposed-controller pattern in the two-factor prompt** (`login_screen.dart`, the MFA code dialog). Not fixed here: it has no test and needs an MFA-enrolled account to drive. §10 item 22.
- **Checked by hand on the simulator, no defect:** parent dashboard shows the child's marks; parent, teacher and student profiles (delete offered to parent and teacher, not to the student); logout with its confirm prompt, for two roles; the school picker omits the two suspended QA schools; school logo and avatar display; teacher "Holiday!" banner; student XP card.
- **Not done:** §5.3 (school setup), the admin screens by hand, taking a test, homework submission, presentations, the realtime homework legs (a no-class Saturday again — the gate fix allows assignment, but this pass did not get to it), push notifications, backgrounding/reconnect. `all_screens_test` opens every one of those screens without error, which is not the same as exercising them.
- **Tooling:** the built-in browser pane was hidden for this session, and a hidden pane stops producing animation frames — the Flutter web build then never leaves its animated splash. §10 item 23. The afternoon's hand checks therefore ran on the simulator.

### 2026-10-10 (auth, sessions and account deletion — two bearer-token defects found and fixed)
- **What ran:** `tests/auth_session_qa.py`, new this session — 63 checks over HTTP against the local stack (the main checkout, confirmed per §10 item 21), covering §3.2, §4.1, §5.1 and the API rows of §5.7 with four throwaway accounts in Hansel & Gretel. First run **57 PASS / 4 FAIL**; the four failures were two defects in `_get_current_user` (`backend/app/core/security.py`), the dependency every authenticated request passes.
- **Found: a refresh token worked as an access token.** It is signed with the same key and carries the same `sub`, and the dependency never looked at `type`. So the 60-minute access lifetime was really 30 days for anyone holding a refresh token — and logout did not help, because a refresh JTI is revoked under `revoked_jti:` while the dependency checks only the access-token namespace. Measured: `GET /api/auth/me` with a refresh token → **200**; with a refresh token already rotated out → **200**; with one revoked by logout → **200**. Only an MPIN reset or deleting the account ended it. The WebSocket already refused refresh tokens; HTTP did not.
- **Found: deactivating a user did not end their session.** Login and `/auth/refresh` both check `is_active`; the per-request dependency and the socket's `_ws_account_allows` did not. A deactivated user's access token kept returning 200 (up to its hour — or, through the first defect, the refresh token's 30 days) and the socket kept delivering events.
- **Fixed:** the dependency refuses `type == "refresh"` and an inactive account, both with 401 (so the client tries a refresh, is refused, and signs out); `_ws_account_allows` requires `is_active`. Tests written first and seen to fail: `tests/test_bearer_token_gate.py` (3) and three account-check cases in `test_websocket_auth.py`, which until now replaced that function with a mock.
- **Verified on the fixed code:** the live script **63/63** (the four cases now 401, plus a real socket refused for a deactivated user and reopened after re-activation); backend unit **424**, 0 failing; `tests_integration/` **77/77**.
- **Everything else in the block passed first time** — bcrypt cost 12, cookie flags, lockout (5 fails, 15 min) and rate limit (10/min), rotation, logout, pending/approve, MPIN-reset revocation, CORS, and the whole deletion path including the parent → child cascade and its audit rows.
- **Production very likely has both gaps.** `main` — what production runs — has neither check in `_get_current_user` (read from `git show main:`; production itself was not probed). They close when `create_school` ships.
- **Two checklist rows were wrong, corrected in place:** §5.1 said "5 wrong, then correct → counter clears" (the fifth failure locks; four is the testable case), and §4.1 listed students as able to self-delete (policy since 2026-05-14: they cannot).
- **Housekeeping:** registration allows 5 a minute per IP, and two back-to-back runs tripped it mid-script; the six accounts those aborted runs left were rejected or revoked through the admin API. `pytest` and `pytest-asyncio` were pip-installed into the running `mindforge_backend` container for the unit run; they vanish on the next rebuild. Not re-run today: Flutter suites (no frontend change), the two security probe suites.

### 2026-10-09 (holiday homework fix merged; local stack back on the branch)
- Merged `claude/holiday-hw-gate` (`35f5087`, from a separate session) as `edb6d4f`, clean. The fix makes homework-completion review require attendance only when the grade has a non-holiday period today (the same rule as `attendance_applicable` in today-workflow), returns `attendance_required` so the teacher screen stops disabling Submit, and moves every daily gate to the school-local date via `core/school_time.py` — UTC was a day behind between 00:00 and 05:30 IST.
- **Verified on the merged code:** backend unit **418** across 37 files (was 412; +`test_school_time.py` and the extended `test_attendance_window.py`), none failing; Flutter **173/173** (+2 model tests), analyzer unchanged; **`tests_integration/` 77/77** against the live stack (incl. the extended `test_homework_review_gate.py`, tenant isolation, realtime delivery, session revocation). On today's real holiday data, homework 75's completions now return `attendance_required: false`.
- **Local stack restored to the main checkout** (§10 item 21): rebuilt and restarted `mindforge_backend` from `./backend` — PyJWT 2.15.1, no `jose`, no `server` header.

### 2026-10-09 (owner dialogs and Parent Fees layout)
- **Owner dialogs (§10 item 20):** Add School and Add Admin both closed *before* calling the server, so a rejection (duplicate name, taken username) discarded everything typed — Add Admin included the MPIN. Both now use one `_SubmitDialog` that submits in place: spinner while waiting, the server's message inline on failure, dialog and input kept, closes only on success. `owner_dialogs_test.dart` (4) failed 3/4 before the change. Checked in the web build: a duplicate name left the dialog open with the name and email intact and the error shown.
- **Parent Fees (§10 item 16):** the reported "13 px on the bottom at 390 px" overflow **did not reproduce** — not with `dummy8_dad`'s real data (three payment options, nothing paid) at 390/360 px, and today's simulator run visited Parent Fees with no overflow in the log. A new layout test using that real data plus a fuller variant (every optional fee, a payment history) found two real flaws instead, both rows where nothing could shrink: `_FeeRow` (label + amount) overflowed to the right with the extra-subject fee labels, and the "Fee Summary" title + academic-year chip overflowed at 1.5× text. Both now give the text the remaining width (`Expanded`) and keep the amount/chip at natural size. Caveat: widget tests draw text in a square-glyph test font, so the measured overflows (up to 163 px) overstate a real phone at normal text size; the realistic triggers are large accessibility text and narrow phones, which the 1.5× and 320 px cases cover. 13 cases, all pass.
- Flutter suite **171/171**; analyzer unchanged at 39 style infos, 0 errors/warnings.

### 2026-10-09 (stale known issues closed)
- §10 items 7, 10, 11 and 12 described problems already fixed, and one had misled this session (CI was assumed not to run on `create_school`; it does). Each re-checked before striking: item 7 against the register row and the 2026-08-21 console check; item 10 in code (`publish_to_school`, `21b05bb`) plus the passing leak test; items 11 and 12 in `ci.yml` (`3bcbe81`, `0fa8a71`) and today's CI runs. Struck in place rather than moved, because later sections cite §10 items by number. Also corrected §3.4 and the register's to-do list, which still called the Firebase key restriction open.

### 2026-10-09 (security probe suites — first run on `create_school`)
- **Target:** an image built from the branch (PyJWT, no `jose`), run as a second container on `:8001` against the shared local Postgres/Redis — the `:8000` backend was serving another worktree (§10 item 21) and was left alone. Removed afterwards. **`security_test.py` defaults to production** (`MF_SEC_BASE_URL` unset → `https://api.mindforge.guru`); always set it. Fixture: Hansel & Gretel (`MF_SEC_SCHOOL_ID=1`) — `demo_admin` 280, `chinmay_sir` 2, `dummy8_dad` 25, `dummy8` 26.
- **`security_test.py`: 21 PASS, 1 FAIL, 1 WARN.** Headers (HSTS, nosniff, DENY, CSP), login rate limit (429), JWT tampering/missing/malformed (401), role isolation and input validation all pass. The FAIL is "HTTPS enforced", which only checks the *target URL's* scheme and so cannot pass against `http://localhost` — not an app finding. The WARN: `server: uvicorn` was sent; `backend/start.sh` ran uvicorn without `--no-server-header`, so prod likely sent it too unless Railway's edge strips it (not checked against prod). Product name only, no version. **Fixed same day:** `--no-server-header` on `start.sh` and the `docker-compose.local.yml` command, pinned by `tests/test_server_header.py`; an image started through `start.sh` sends no `server` header and the suite re-ran at **22 PASS / 1 expected FAIL / 0 WARN**. The running local stack keeps the old command until it is restarted.
- **Fixed a vacuous probe — SQL injection.** The five payloads were sent without `school_id`, so a multi-school stack answered 400 "Please select your school." after only the owner lookup; the per-school username query never saw them. They now send `MF_SEC_SCHOOL_ID` when set: all five → 401 in ~250 ms (the constant-time dummy-hash path), `pg_sleep(3)` causes no delay, no server errors.
- **`security_test_extended.py`: 48/48** — the privilege-escalation matrix, IDOR, path traversal on `/api/media`, WebSocket (cross-user token refused at handshake), access token revoked after logout, old refresh token refused after rotation.
- **Fixed a vacuous probe — mass assignment.** All three payloads used weak MPINs (`111111`/`222222`/`333333`) and were refused by the weak-MPIN check (422) before the role or injected flags were read. Rewritten as two probes with otherwise-valid bodies: `role=admin` must be refused **on the `role` field** (else WARN, "probe not meaningful"); a legitimate teacher registration with `is_active`/`is_approved` injected must be stored `is_approved=False` and refused at login (403) — then the school admin deletes it, so the run leaves no account behind. Both PASS.

### 2026-10-09 (python-jose → PyJWT)
- **Trigger:** CI's pip-audit job failed on `python-jose` 3.5.0, GHSA-3qf3-8w2g-rqmx / CVE-2026-85394 (published 2026-09-03): python-jose's guard against using a public key as an HMAC secret can be bypassed with a DER-encoded key, so a holder of the public key can forge HS256 tokens when algorithms are not pinned. An incomplete fix of CVE-2024-33663; no patched release.
- **Assessed not exploitable here:** tokens are only ever verified with the symmetric `JWT_SECRET`, no public key exists anywhere in the backend, and the one decode call pins `algorithms=[JWT_ALGORITHM]` (HS256). Migrated anyway: the second incomplete fix of the same bug, and python-jose was the only source of `ecdsa` (the one ignored advisory).
- **Change:** `PyJWT==2.15.1` replaces `python-jose[cryptography]` (already required by `firebase-admin`, so no new dependency); `except JWTError` → `jwt.PyJWTError` in `security.py`, `routers/auth.py`, `main.py`. `python-jose`, `ecdsa` and `rsa` leave the dependency tree; the CI `--ignore-vuln PYSEC-2026-1325` is removed. New `test_jwt_library.py` (11) pins the error path (bad/expired tokens still 401 through the auth dependency and refresh), sub-second `iat` verifying immediately, algorithm pinning (`none` and HS512 refused), and that no app code imports `jose` — the type/import cases failed before the change.
- **Verified:** backend unit 412/412; `pip-audit -r backend/requirements.txt --strict` with **no** ignores → "No known vulnerabilities found"; the image built from the branch boots with the real local config incl. `SENTRY_DSN` (§10 item 13); and, run side by side with the python-jose server, 12/12 live checks — tokens cross both ways (no forced logout on deploy, safe rollback), an old refresh token rotates, garbage tokens 401, the WebSocket accepts a PyJWT token and refuses garbage.

### 2026-10-09 (multi-tenancy & owner QA — §5.2 complete)
- **All eight §5.2 items PASS**, no tenancy defect found. API checks drove real tokens through owner login, school + admin creation, a cross-school action (404), suspension (login 400 / refresh 401 / live access token 403 / gone from the picker / other school unaffected / owner exempt / reactivation restores login) and per-school phone uniqueness; the owner console was checked in the web build. `test_tenant_isolation.py` + `_finance.py` re-run 37/37.
- **Fixed:** the duplicate-school error told the owner to "choose a different slug", which the console never shows. It now names the school when the slug was derived from the name; new `tests/test_owner_school_create.py` (2 tests, the name case falsified against the old text).
- **Rate-limit interplay:** registration allows 5 attempts/min per IP, and the isolation suites register users from the same IP — run back to back, the next registrations 429. Expected behaviour; wait out the window.
- **The local backend was serving another worktree.** Mid-session a parallel session restarted the Docker stack from `.claude/worktrees/youthful-elion-30dc62/backend` (its holiday fix, `35f5087`, on top of `3271d34`). The tenancy checks therefore ran against that code — same backend as the branch apart from the homework gates, so the results stand. §10 item 21.
- **Host test environment drift:** 6 backend files now fail to import under the host `python3.12` (outdated/missing `google-genai`, missing `sentry_sdk`), up from 3. Environment only; every other file passes on the host.

### 2026-10-09 (Flutter integration back to green; first manual realtime pass; holiday homework deadlock)
- **Flutter integration on the iOS sim: `app_test` 0/5 → 5/5, `all_screens_test` 21/29 → 29/29.** The first runs failed on the uncommitted Whiteprint login redesign, not on app behaviour: the tests found controls by visible text, and the redesign uppercases labels, draws the delete key as an icon and has no `ElevatedButton`. Fix: a public `LoginKeys` class in `login_screen.dart` (tabs, school, username, role, phone, email, submit, mode toggle, each PIN key); `app_test`, `all_screens_test` and `test/widget/login_screen_test.dart` now find controls by key. One more text assumption: after a school is picked, the header wordmark becomes the school's name, so "still on the login screen" is now asserted via `LoginKeys.submit`.
- **`all_screens_test` defaulted to a deactivated student.** `hansel_kid` is `is_active = false` locally (401, then 429 once the lockout tripped), which failed all 8 student screens. Default is now `dummy8` / `123456` (child of `dummy8_dad`). Admin, teacher and parent screens passed on the first run.
- **Realtime, first manual pass (web, two origins):** grade-8 broadcast live to a grade-8 student — PASS; same-grade-number cross-school leak (Hansel → Riverdale) — PASS, none. Homework legs blocked by the holiday deadlock below. Backend `test_realtime_delivery.py` re-run 6/6.
- **Found: on a holiday a teacher cannot assign homework** — §10 item 18.
- **Fixed: school logo and avatars never displayed on a local web build.** The CSP `img-src` allowed only `https://api.mindforge.guru`; locally media comes from `http://localhost:8000`, so the browser blocked it (console: `violates … img-src`) and the header fell back to the MindForge mark. `img-src` now carries the same API origins as `connect-src`; a new `web_csp_test` case fails if they drift apart. Production was not affected (media is served from `api.mindforge.guru`, assuming `BACKEND_PUBLIC_URL` is set to it — not checked) and native apps don't apply the CSP.
- **Fixed two narrow-width layout defects:** the six MPIN cells overflowed the login card below ~240 px of card width (a 34 px minimum cell width; now no floor and a tighter gap), and a long school name ran under the logout icon on the student/teacher/parent dashboards (wordmark now inset by the button's footprint; tagline held to one line). Checked in the browser at 280, 300 and 375 px.
- **Testing caveat:** after `flutter build web`, the browser kept serving the previous `main.dart.js` from its HTTP cache through normal reloads — §10 item 19.

### 2026-09-13 (full automated re-run)
- Backend unit **331 PASS**, integration **58/58 PASS**, Flutter **143/143 PASS**, analyze 0 errors / 0 warnings. Full detail in §2.
- New uncommitted tests green: `test_attendance_window.py` 9/9, `test_homework_review_gate.py` 3/3.
- Found: the host `python3.12` cannot run 3 backend files (missing `sentry_sdk`, `google-genai`); the container cannot run 2 (no repo root, no git). Run the suite split accordingly until one environment covers both.

### 2026-07-24 / 25 (previous §2 — superseded by 2026-09-13)

**Date:** 2026-07-24 / 25
**Branch:** `create_school`
**Environment:** macOS (darwin 25.5.0), Flutter 3.44.0 (stable), Python 3.14

#### 2.1 Backend — each file in its own pytest process (mirrors CI)

| Suite | Result |
|---|---|
| `tests/test_unit.py` | **PASS — 34/34** |
| `tests/test_logout_handler.py` | **PASS — 3/3** |
| `tests/test_websocket_auth.py` | **PASS — 5/5** |
| `tests/test_schema_invariants.py` | **PASS — 4/4** |
| `tests/test_tenancy.py` | **PASS — 19/19** |
| `tests/test_tenancy_wiring.py` | **PASS — 8/8** |
| `tests/test_realtime_fanout.py` | **PASS — 8/8** (new this session) |
| **Whole suite in one session** (`pytest tests`) | **PASS — 81/81** |
| `tests_integration/` (stack up, upgraded deps) | **PASS — 36/36** — 32 tenant-isolation + 4 new realtime-delivery |

The one-session run passing is worth noting: the per-file split in CI was introduced because `test_logout_handler.py` and `test_websocket_auth.py` install module-level `sys.modules` stubs. That ordering hazard has not resurfaced, but the split is still the safer default. See §10 item 4.

#### 2.2 Frontend

| Suite | Result |
|---|---|
| `flutter test test/unit/` | **PASS — 78/78** |
| `flutter test test/widget/` | **PASS — 26/26** (+5 new `realtime_sync_test.dart`) |
| `flutter test` (everything) | **PASS — 104/104** |
| `flutter analyze lib test integration_test` | **PASS — 0 errors, 0 warnings, 6 style infos** |

The 3 infos: one `prefer_const_declarations` in `lib/features/teacher/screens/homework_screen.dart:741`, two `no_leading_underscores_for_local_identifiers` in `test/unit/auth_notifier_test.dart`. CI runs `flutter analyze --no-fatal-infos`, so none of the three break the build.

`test/widget/realtime_sync_test.dart` now drives **all 22** event names across all three role branches (was 5), asserting the exact provider set each invalidates; falsified against a typo'd case and an over-broad invalidate.

**Flutter integration — `app_test.dart`: PASS 5/5** on iPhone 17 Pro against the local stack (`--dart-define=LOCAL_DEV=true`), in 61 s. Was 2/5 at the start of the session.

**Flutter integration — `all_screens_test.dart`: 26 pass / 3 fail.** Was `+0 -15`. Two fixes moved it: the WebSocket disposed-container bug (§9) took it to `+19 -10`, and a working teacher account cleared 7 more.

Five layered problems were fixed across the two files, each only visible once the one above it was:

1. The login form's school picker (multi-tenancy, 2026-07-22) was never set, so `login_screen.dart` bailed with "Please select your school." and never called the API.
2. The taller form pushed the Login button 0.3 px off-screen; `tap()` only *warns* on a missed hit, so the run hung rather than failing.
3. `main()` is async, so `MaterialApp` was not mounted when test 1 asserted on it.
4. **`main()` installs Crashlytics as `FlutterError.onError` / `PlatformDispatcher.onError` before `runApp`.** In a widget test that displaces the binding's reporter, so real failures went to Crashlytics and the binding reported only `_pendingExceptionDetails != null`. Suite-wide, and had masked every framework error since these tests were written — §10 item 14.
5. Seeded credentials were stale: three of the four accounts in `seed_integration_test_users.py` now 401 — §10 item 15.

`pumpAndSettle` is bounded to 20 s in both files; the 10-minute default turned failures into silent stalls that made diagnosis unaffordable.

**The 3 remaining failures are pre-existing app bugs, not test rot** — and were invisible until the tests reclaimed error handling:

| Test | Defect |
|---|---|
| Admin Timetable, Teacher Tests | Framework assertion: a `ListTile` inside a colour-filled `DecoratedBox` (`mindForgeCardDecoration()`) hides its own background and ink splashes, so tap feedback does not render. Fix is to wrap the tile in its own `Material`, or drop the colour from the intermediate box. |
| Parent Fees | `RenderFlex overflowed by 13 pixels on the bottom` at a 390 px-wide viewport. |

Both are debug-mode assertions and do **not** crash release builds. Deliberately left unfixed: the `ListTile` pattern comes from a shared card decoration used across 12+ screens, so correcting it is a visual change wanting review, not a test fix.

#### 2.3 Not run this session

| Suite | Why |
|---|---|
| `pip-audit` on a CI runner | Green locally in a Python 3.12 venv; the runner has never executed the fixed workflow (see §8) |
| `tests/security_test.py`, `security_test_extended.py` | Not run — no longer blocked (the stack is up), just out of scope for this session. Point them at the **local** stack only; they include login rate-limit probes |
| `tests/performance_test.py` | Same |

`pip-audit` **was** run locally this session (Python 3.12 venv, since `pymupdf` won't build on the default 3.14) and is now green — see §10 item 1.

### 2026-07-24 (automated re-run + record rewrite)
- Re-ran every automated suite. **Backend 81/81 PASS** (7 files, also green file-by-file). **Flutter 99/99 PASS** (78 unit + 21 widget). `flutter analyze lib test` clean — 0 errors, 0 warnings, 3 style infos.
- Added `backend/tests/test_realtime_fanout.py` (8 tests) alongside a WebSocket fan-out fix: class-wide events were published as `target_type: "grade"` and resolved through a `ws_manager` grade index that **nothing ever populated**, so all 7 grade-targeted publish sites were silently dropped. Recipients are now resolved from the DB at publish time and addressed as explicit user IDs. Same change closed a cross-school leak in `broadcast_all`.
- `tests_integration/` skips cleanly when the stack is down — the skip message names the exact compose command, which is good ergonomics.
- **Found: CI on `main` has been red for ~5 weeks** (8 consecutive failures since 2026-06-23; last green 2026-06-18). Every failure is the `dependency-audit` job. Latest run reports **20 findings across 5 packages** — see §10 item 1. `backend-unit` and `flutter` are green in the same runs, so this is purely the audit gate.
- **Found: 4 of 7 backend test files never run in CI** — `test_schema_invariants.py`, `test_tenancy.py`, `test_tenancy_wiring.py`, `test_realtime_fanout.py` (39 tests, including the entire multi-tenancy safety net). §10 item 2.
- **Found: the `api-integration` job can never run** — its `if:` gates on `workflow_dispatch`/`schedule`, neither of which is in the workflow's `on:` block. §8's old advice to "kick it off with `gh workflow run ci.yml`" would have failed. §10 item 3.
- Live API re-verified: `https://api.mindforge.guru/api/health` → 200, 0.27–0.31 s warm, all four security headers present.
- Relabelled most of §3.2, §3.4, §4.1 and §4.3 from `PASS` to `NOT RE-VERIFIED`. Those rows were last actually checked in May, and the auth layer has since gained multi-tenancy, suspension gating, an MPIN blocklist and audit logging. Carrying the old ticks forward would have overstated coverage.
- **Found: Claude is now the primary AI provider** (pipeline Claude → Gemini → Groq), added 2026-06-08. Anthropic is a PII recipient that the May privacy sweep and `PRIVACY_POLICY.md` predate. §10 item 5.
- Closed §10 item 2 from the old record (SSL leaf expiry) — pinning moved to CA-level on 2026-06-01, so leaf rotation is no longer release-blocking. Current leaf expires 2026-08-27.
- Closed §10 item 8 from the old record (Firebase web unconfigured) — `firebase_options.dart` now has a real `web` block as of 2026-06-30. Functional re-test still outstanding.

### 2026-07-25 (admin leak fix, security re-run, stale-file cleanup, UI defects)
- **Fixed a second cross-school leak.** `admin.py`'s `timetable_config_updated` and `new_academic_year` still published with `target_type: "broadcast"`, reaching every tenant on the instance — the same class as the fan-out bug. Both now use `publish_to_school`; no unscoped `broadcast` publish remains anywhere in the backend. Two integration tests added (positive + no-leak), falsified against the un-fixed code. Backend integration 36 → 38.
- **`RealtimeSync` coverage 5 → all 22 events**, per role, asserting the exact provider set each invalidates. Falsified two ways: a typo'd `case` label and an over-broad invalidate both fail.
- **Re-ran `security_test.py` against the upgraded stack**: 21 PASS / 1 FAIL / 1 WARN, matching the 2026-05-19 baseline — the fastapi/starlette jump did not regress the security surface (rate limit, JWT tampering, SQL injection, role isolation, input validation). FAIL/WARN are local-stack artifacts (no TLS, uvicorn banner). Made the suite env-targetable (`MF_SEC_BASE_URL` + admin creds), which also un-skipped the access-control block that a missing `school_id` had silently disabled.
- **Retired `seed_integration_test_users.py`.** Orphaned (nothing referenced it but the docs), broken (no `school_id`), and now unfixable-in-place — its accounts span multiple schools, and re-running it would reset the MPINs of the accounts the tests depend on. `docs/local-test-accounts.md` is the source of truth.
- **Hardened `test_api.py` with a file-level production guard.** The CI job was already gated, but a bare `pytest tests/test_api.py` still wrote to prod. It now refuses a production host unless `MF_API_ALLOW_PROD=1`, and is env-targetable via `MF_API_BASE_URL`. Verified: default target skips with zero requests; opt-in and local both collect. The suite still needs multi-tenancy modernization (school_id + the parent-creation flow, which self-register-as-parent no longer supports) before it passes — left documented, not blind-edited.
- **Fixed two UI defects the integration suite surfaced.** Admin Timetable and Teacher Tests wrapped an interactive `ListTile`/`SwitchListTile` directly in a colour-filled card, hiding its ink splash (Flutter asserts in debug). Both now sit in a transparent `Material` — no visual change. Parent Fees' 13 px overflow is left unfixed: its creator is DEFUNCT in the log, so locating it needs a dedicated reproduction rather than a guess.

### 2026-07-25 (CI green for the first time in five weeks)
- Run `30119086970` on `create_school`: **success**. Last green run before it was 2026-06-18, followed by 8 consecutive failures.
- **`pip-audit` on a real runner: "No known vulnerabilities found, 1 ignored."** This was the largest unverified claim in the record — the dependency work was only ever proven in a local Python 3.12 venv, and CI runs 3.11.
- **The backend glob ran all 7 test files, 81 tests.** CI previously ran 3 files / 42 tests, so 39 tests — including the whole multi-tenancy safety net — had never executed on CI.
- **A mistake worth recording.** Adding `workflow_dispatch` (commit `2cd83ea`) made the previously-unreachable `api-integration` job runnable, but that job's `tests/test_api.py` targets **production** and registers/approves/revokes users. Triggering CI by hand therefore pointed it at the live database. It was cancelled once noticed; no data was created, but only because the suite is itself stale and every write 422'd on the missing `school_id`. The job now needs an explicit opt-in input (`fa2b6cd`). The lesson generalises: enabling a trigger is not the same as understanding what it will do, and that check belongs *before* the button, not after. §10 item 17.
- `create_school` still matches no push trigger, so this was a manual dispatch; merging to `main` remains the only way this runs automatically.

### 2026-07-24/25 (RealtimeSync covered; all_screens_test +0 -15 -> +26 -3)
- **`RealtimeSync` now has coverage** — `frontend/test/widget/realtime_sync_test.dart`, 5 tests, no simulator or backend, so unlike the integration suites these run in CI. Covers student broadcast/homework refresh, teacher auto-quiz refresh, and two negative cases (an unrelated event must not invalidate; a student session must not run the teacher branch). Verified by falsification: deleting one `ref.invalidate` fails exactly one test, then restores to 5/5. This closes the last gap from the original realtime request — backend delivery was already proven end-to-end, client-side invalidation was not.
- **Found a real WebSocket bug via `all_screens_test`.** The delayed reconnect resolved its token as a *call argument*, so the generation guard inside `_connect` could never prevent it; once the Riverpod container was disposed the pending timer threw `Bad state: Tried to read a provider from a ProviderContainer that was already disposed`. Latent until `RealtimeSync` began opening a socket for **every** role — admin and owner never had one before. **Not test-only:** an admin logout could raise it in the real app. Fixed by checking the generation *before* resolving the token (`_scheduleReconnect`) plus a defensive catch. Took `all_screens_test` from `+0 -15` to `+19 -10`, Admin 0/6 → 5/6 and the Student group fully green.
- The 99 unit and widget tests pass with that bug present and structurally cannot reach it. **Second time this session the integration suite caught something the unit tests cannot** — the first being the dropped event fan-out.
- A working teacher account (`metas_teacher2`, school 64 "metas") cleared 7 more failures → `+26 -3`. Credentials in `all_screens_test.dart` are now `(username, mpin, school)` triples: the teacher lives in a different school to the admin/student/parent accounts, so one shared school name could not log all four roles in. That also exercises the picker resolving different schools within a run.
- Remaining 3 failures are pre-existing app bugs (see §2.2), left unfixed deliberately.
- Full sweep at close: backend **81/81**, backend integration **36/36**, Flutter unit+widget **104/104**, `app_test.dart` **5/5**, `all_screens_test.dart` **26/29**, analyze 0 errors / 0 warnings / 6 style infos.

### 2026-07-24 (Flutter integration tests: 2/5 -> 5/5)
- `app_test.dart` **passes 5/5** on iPhone 17 Pro against the local stack, in 61 s. Five separate problems, each only visible once the one above it was fixed — which is why this took several runs rather than one speculative batch of fixes.
- The one that mattered most was not a test bug at all: **`main()` installs Crashlytics as `FlutterError.onError` and `PlatformDispatcher.onError` before `runApp`**, so inside a widget test the app displaced the binding's reporter and real failures were shipped to Crashlytics. The binding could only report `_pendingExceptionDetails != null`. That had been masking every framework error in the suite since it was written; the admin-login failure was invisible for three runs because of it. §10 item 14.
- Bounded `pumpAndSettle` to 20 s. The 10-minute default turned the first failing run into a 13-minute silent stall that printed nothing until killed — the single biggest drag on diagnosis. A hang is now a legible failure naming the exact `await`.
- The admin login was failing on **stale credentials**, not on the UI: `admin` / 300573 comes from the pre-multi-tenancy seed script and returns 401 against the current local DB. Verified `demo_admin` / 847362 against the API before changing the test. §10 item 15.
- Corrected an earlier claim from this session: the 13-minute hang was **not** caused by `tap()` warning-instead-of-failing on the off-screen Login button. That was fixed and the hang persisted; it was the unbounded `pumpAndSettle` plus the leaked binding state.
- **Still unverified:** nothing exercises `RealtimeSync`. `all_screens_test.dart` has the school/login helpers but has never been run, and does not yet reclaim the error handlers.

### 2026-07-24 (local stack — caught a boot-breaking regression the venv missed)
- **The dependency upgrade did not boot.** With the stack up and the backend image rebuilt on Python 3.11, the container **crashed on startup**: `ImportError: jinja2 must be installed to use Jinja2Templates`. `sentry-sdk` 2.18.0's Starlette integration decides whether to patch `Jinja2Templates` by probing for `markupsafe` as a proxy for "jinja2 is installed" — but `alembic → Mako` pulls markupsafe in independently, so the probe passes and it then does an unguarded `from starlette.templating import Jinja2Templates`. starlette <1.0 tolerated that; **1.x raises at module import**, killing the uvicorn worker. Fixed by `sentry-sdk[fastapi]` 2.18.0 → **2.66.1**, verified by reproducing the crash and the fix in isolation before rebuilding.
- **Why the earlier venv check missed it:** Sentry integrations are only wired up when `sentry_sdk.init()` actually runs, which needs a `SENTRY_DSN`. The venv had none, so `setup_integrations` never executed. The Docker stack loads `.env.local`, which does. **A dependency bump is not verified until the app has started with production-shaped configuration** — imports and unit tests are not enough.
- After the fix the backend boots clean: Postgres, Redis (including the pub/sub subscriber the realtime fan-out depends on) and MinIO all connect, `/api/health` 200 in ~40 ms.
- **`tests_integration/` now runs: 36/36 PASS** (was skipping). 32 pre-existing tenant-isolation tests, all green against the upgraded stack.
- **Added `tests_integration/test_realtime_delivery.py` (4 tests)** — the first real coverage that a published event reaches a connected socket, closing the biggest gap flagged in §5.8. Covers: grade broadcast → the grade's students; grade broadcast → staff (`include_staff`); `homework_added` → students *and* staff; and school-wide broadcast **not** crossing into another school.
- **Falsified the new tests rather than trusting them green.** Temporarily reverted `send_broadcast` to the old `target_type: "grade"` publish: the two broadcast tests failed and the homework test kept passing (a separate call site), which is the expected shape. Restored and re-verified. Worth recording *why*: the leak test asserts an absence, so on its own it would also pass if delivery were broken outright — the exact failure being fixed. It is only meaningful alongside the positive tests.
- Backend unit suite still **81/81** on the upgraded dependency set.

### 2026-07-24 (CI repair — dependency audit + missing test files)
- **`pip-audit` green: 20 findings across 5 packages → 0 (1 ignored).** Bumped `Pillow` 12.2.0→12.3.0, `python-multipart` 0.0.27→0.0.32, `fastapi` 0.120.4→0.139.2, `python-jose` 3.4.0→3.5.0; newly pinned `starlette==1.3.1` and `pyasn1==0.6.4`. Both items the 2026-05-19 session recorded as *blocked* had unblocked upstream: python-jose 3.5.0 relaxed `pyasn1<0.5.0`, and fastapi 0.133.0 dropped the `starlette<1.0` cap. The PyJWT migration that was on the table is not needed.
- `ecdsa` PYSEC-2026-1325 is **ignored, not fixed** — no fix exists (upstream calls side channels out of scope) and the vulnerable ECDSA/ECDH paths are unreachable under HS256. Rationale is written into `ci.yml` next to the flag, with a re-evaluate trigger if `JWT_ALGORITHM` changes.
- Verified the whole upgrade in a Python 3.12 venv rather than trusting the pins: resolution clean, `pip-audit --strict` green, backend **81/81**, FastAPI resolves **144 OpenAPI paths / 160 operations**, TestClient smoke gives 200 + all four security headers on `/api/health`, 403 on a non-allowlisted media bucket, 422 on an empty login body. The starlette 0.49→1.3 major jump touches only `BaseHTTPMiddleware`, the single starlette symbol the codebase imports directly.
- **CI now runs all 7 backend test files** (was 3). Replaced the hand-written step list with a glob over `tests/test_*.py` so this can't silently regress again; per-file processes retained. Dry-ran the failure path (build goes red, loop continues so every failure is visible) and the empty-glob guard (fails loudly instead of passing vacuously).
- Added `workflow_dispatch:` to the workflow's `on:` block, making the previously-unreachable `api-integration` job runnable.
- **Not yet CI-verified.** All of the above was validated locally; `create_school` matches no CI trigger, so no runner has executed it.
- Noted one cosmetic upstream change: starlette 1.x deprecates using `httpx` with `starlette.testclient` in favour of `httpx2`. The repo's tests call functions directly rather than through TestClient, so nothing is affected today.

### 2026-05-19 (full security audit + critical fixes)
- Wrote `tests/security_test_extended.py` covering privilege escalation, IDOR/BOLA, mass assignment, path traversal, WebSocket auth, JTI revoke after logout, refresh rotation. Initial run 47 PASS / 2 FAIL.
- **CRITICAL — mass assignment on `/api/auth/register` (fixed).** Schema accepted any `UserRole`; `role="admin"` rows could be created. Fix: `restrict_self_register_role` validator in `backend/app/schemas/user.py` allowing only `student`/`teacher`. Re-run 49/0/0. Verified via curl: student 201, teacher 201, admin 422, parent 422; the auto-create-parent flow still works.
- **HIGH — backend dependency CVEs.** `pip-audit` flagged 17 CVEs across 6 packages. Bumped `python-jose` 3.3.0→3.4.0, `python-multipart` 0.0.9→0.0.27, `python-dotenv` 1.0.1→1.2.2, then `Pillow` 10.3.0→12.2.0 and `fastapi` 0.111.0→0.120.4 (pulling `starlette` 0.37.2→0.49.3). Final pip-audit that day: 17 → 2. *(Superseded — back to 20 findings by 2026-07-18 as new advisories landed against those same pins.)*
- `docker-compose.yml` host-port hardening: removed `ports:` for postgres/redis/minio from the base compose; moved them to `docker-compose.local.yml`.
- CSP `<meta>` added to `frontend/web/index.html`; allowlist needed `https://www.gstatic.com` (canvaskit) and `https://fonts.gstatic.com` (google_fonts).
- Tier-C static checks clean: no hardcoded secrets, no `eval/exec/os.system/shell=True/pickle.loads/yaml.load`, no f-string SQL.

### 2026-05-19 (web build QA + security re-run)
- Local stack up via docker compose; `/api/health` 200 in ~55 ms. Re-seeded 4 integration-test users.
- Manual golden path PASS on all four roles in the Chrome debug build. Web checks all PASS (see §5.9).
- Release bundle built in 58.9 s; tree-shaken icon fonts (99.4% / 98.2%). Golden path passed against the minified bundle.
- `tests/security_test.py` against local stack — 21 PASS / 1 FAIL / 1 WARN; both non-passes were local-stack artifacts (no TLS on localhost; uvicorn `server` header).
- Logged Firebase-web and `flutter_secure_storage_web` wasm findings.

### 2026-05-14 (fifth pass — integration tests 5/5 PASS)
- Root-caused the iPhone 17 Pro failures to one line in `app_test.dart`: an unconditional `tester.view.physicalSize` override that breaks taps on the live binding. Gated it on `binding is! LiveTestWidgetsFlutterBinding`. Re-ran on iPhone 17 Pro → **5/5 PASS in ~108 s**, including admin end-to-end login.

### 2026-05-14 (fourth pass — integration tests on iOS simulator)
- iPhone 17 Pro 2/4, iPhone 16e 0/5 — hardcoded tap coordinates off-screen, then suite-level cascade. Test-suite issues, not app bugs; fixed in the fifth pass.

### 2026-05-14 (third pass — verification + new WS test)
- Wrote `backend/tests/test_websocket_auth.py` (5 tests). Backend sweep 38/38.
- Found the pre-existing `test/widget_test.dart` failure (autogenerated smoke test, no Firebase init). Deleted later that day.

### 2026-05-14 (second pass — fixed 4 of 5 Known Issues)
- Fixed `conftest.py` for Python 3.11–3.14 (real `type()` classes for `Base`/`AsyncSession`). Backend 33/33.
- Hardened admin seed behind `ADMIN_SEED_MPIN`. Added JWT auth to `/ws/{user_id}`. Verified AI prompts carried no PII.

### 2026-05-14 (initial audit)
- 82/82 Flutter, backend 30/33 (3 Python 3.14 MagicMock issues). Live API headers verified; all April 5 issues fixed.

### 2026-04-05 (`test_report.md`)
- API smoke 8/8. TTFB 473 ms. 5 security issues flagged (HSTS, rate limit, nosniff, frame options, CSP) — all fixed by 2026-05-14.

---

## 10. Known Issues & Caveats

1. **~~CI red on `main` since 2026-06-23 (dependency-audit)~~** — fixed 2026-07-24. The audit went from **20 findings across 5 packages to 0 (1 ignored)**. Bumps in `backend/requirements.txt`:

   | Package | Was | Now | Advisories cleared |
   |---|---|---|---|
   | `Pillow` | 12.2.0 | 12.3.0 | PYSEC-2026-2253/2254/2255/2256/2257/3451/3452/3453 |
   | `python-multipart` | 0.0.27 | 0.0.32 | PYSEC-2026-3036/3037/3040 |
   | `fastapi` | 0.120.4 | 0.139.2 | *(enabler — 0.133.0 is the first release to drop the `starlette<1.0` cap)* |
   | `starlette` | 0.49.3 (transitive) | 1.3.1 (now pinned) | PYSEC-2026-161/248/249/2280/2281 |
   | `python-jose[cryptography]` | 3.4.0 | 3.5.0 | *(enabler — relaxes `pyasn1<0.5.0` to `>=0.5.0`)* |
   | `pyasn1` | 0.4.8 (transitive) | 0.6.4 (now pinned) | PYSEC-2026-2263 |

   The two previously-"blocked" items both unblocked themselves upstream: python-jose 3.5.0 relaxed the pyasn1 cap, and fastapi 0.133.0 dropped the starlette cap. No migration to PyJWT was needed. `starlette` and `pyasn1` are now pinned explicitly so the audited version is the deployed one.

   *(Superseded 2026-10-09: `ecdsa` left with python-jose and the ignore is gone — see §9.)* **One advisory is ignored, not fixed:** `ecdsa==0.19.2` / PYSEC-2026-1325 (CVE-2024-23342), the Minerva timing attack on P-256. It affects every released version and upstream considers side-channel attacks out of scope, so there is no fix version. `ecdsa` is a hard dependency of `python-jose`, not something the app imports, and the vulnerable paths are ECDSA signing/keygen/ECDH — MindForge signs JWTs with **HS256** (`JWT_ALGORITHM`, `app/core/config.py:50`), so no ECDSA private-key operation ever runs. The `--ignore-vuln` in `ci.yml` carries this rationale. **Re-evaluate if `JWT_ALGORITHM` ever becomes ES256/384/512.**

   Verified locally in a Python 3.12 venv (CI is on 3.11; the repo's default `python3` is 3.14, where `pymupdf` won't build): dependency resolution clean, `pip-audit --strict` → "No known vulnerabilities found, 1 ignored", backend suite 81/81, FastAPI resolves all 144 OpenAPI paths / 160 operations, and a TestClient smoke returns 200 + all four security headers on `/api/health`, 403 on a non-allowlisted media bucket, 422 on an empty login body.

2. **~~4 of 7 backend test files are not in CI~~** — fixed 2026-07-24. The three hand-listed pytest steps are replaced by a glob over `tests/test_*.py`, so all 7 files (81 tests) run and any new file is picked up automatically — the hand-written list is what let 39 tests, including the whole multi-tenancy safety net, go unrun for weeks. Each file still gets its own process (see item 4), wrapped in `::group::` so the log stays readable. The loop continues past a failure and then exits non-zero, so one broken file doesn't mask the rest; an empty glob fails loudly rather than passing vacuously. Both the failure path and the empty-glob guard were dry-run before committing.

3. **~~The `api-integration` CI job can never run~~** — fixed 2026-07-24. `workflow_dispatch:` added to the workflow's `on:` block, so `gh workflow run ci.yml` now reaches the job (it was previously rejected outright). `schedule:` is still not declared — add it if you want the live-API suite on a timer; the job's `if:` already accounts for it. The job runs `pytest tests/test_api.py` from the repo root, which is correct: that file lives at `tests/test_api.py`, not under `backend/`. **Still unproven** — the job has never actually executed, and it needs the `ADMIN_MPIN` secret to be set.

4. **Backend tests are split into one pytest process per file in CI.** `test_logout_handler.py` and `test_websocket_auth.py` install module-level `sys.modules` stubs that mutate state shared with `test_unit.py`. The whole suite *does* pass in a single session today (81/81), so the hazard is latent rather than active, but the split stays until the stubs move into `conftest.py`. Any new file that installs its own stubs must get its own step.

5. **Claude is a new, unaudited PII recipient.** `ai_service.py` has been Claude → Gemini → Groq since 2026-06-08, with Claude reading uploaded PDFs/images natively through the Anthropic Files API. The May prompt-PII sweep and `PRIVACY_POLICY.md` §5/§7 both predate this. Re-run the prompt audit and add Anthropic to the policy's sharing table before store submission.

6. **`AppConstants.privacyPolicyUrl` is still empty** (`frontend/lib/core/utils/constants.dart:30`). The in-app link auto-hides while empty, so this is not user-visible breakage, but it blocks store submission along with hosting the policy and counsel review.

7. **~~Firebase client API keys are not yet restricted in the GCP console~~** — resolved; confirmed in the GCP console 2026-08-21 that all three keys have carried application restrictions since April 2026 (see the register's "Firebase client keys restricted" row). Stale here until 2026-10-09. Original note: Documented in `SECURITY.md` with the exact keys and the restriction each should carry. Defense-in-depth, not a leak — the app uses only Core/FCM/Analytics/Crashlytics, so a copied key cannot read user data. Worst case is quota abuse.

8. **Firebase web config landed but was never functionally re-tested.** `firebase_options.dart` gained a real `web` block on 2026-06-30, which should close the old "FCM/Analytics/Crashlytics silently disabled on web" finding. Nobody has confirmed a push actually arrives in a browser. §5.9.

9. **`flutter_secure_storage_web` blocks future wasm builds.** The wasm dry-run flags `dart:html` + `dart:js_util` usage. The JS build works today; revisit when Flutter's wasm target stabilises.

10. **~~Realtime fan-out unverified on the client~~** — closed 2026-07-25. `tests_integration/test_realtime_delivery.py` proves the backend delivers (falsified against the old code), and `test/widget/realtime_sync_test.dart` proves the client invalidates the right cache per role (also falsified). ~~**Still open in the same area:** `admin.py`'s `timetable_config_updated` and `new_academic_year` continue to use the unscoped `broadcast_all`, so those two events cross school boundaries.~~ Fixed 2026-07-25 (`21b05bb`): both now go through `publish_to_school`. `test_realtime_delivery.py::test_timetable_config_does_not_leak_to_another_school` pins the first (passed 2026-10-09); `new_academic_year` uses the same call but has no dedicated test. Confirmed in code 2026-10-09.

11. **~~CI Flutter version drift~~** — fixed 2026-08-21 (`3bcbe81`): CI pins `3.44.0`, matching local; confirmed 2026-10-09. Original note: CI pinned `3.41.4`; local development is on `3.44.0`. A version-specific analyzer or test failure would not be caught symmetrically.

12. **~~CI does not run on most working branches~~** — fixed 2026-08-19 (`0fa8a71`): `push` now triggers on every branch (`branches: ["**"]`); three CI runs on `create_school` on 2026-10-09 alone. Original note: Triggers were `main`, `feature/**`, `fix/**`, `test/**`. Branches like `create_school` get no CI at all, so work merges to `main` having never been CI-verified.


13. **A dependency bump is not verified until the app boots with a real config.** The 2026-07-24 upgrade passed imports, 81 unit tests, OpenAPI generation and a TestClient smoke in a venv — then failed to start in Docker, because Sentry only wires up its integrations when a `SENTRY_DSN` is present and the venv had none. Any future `requirements.txt` change should be validated by rebuilding the image and watching the container reach "Application startup complete", not by a venv smoke test alone.

14. **An app that installs its own error handlers blinds the integration tests.** `main()` sets Crashlytics as both `FlutterError.onError` and `PlatformDispatcher.onError` (`main.dart:63-64`) before `runApp`. Every integration test calls `app.main()`, so the app displaces the test binding's reporter: framework errors are shipped to Crashlytics instead of failing the test, and the binding surfaces only `_pendingExceptionDetails != null` — an assertion that replaces the real cause with a message about error handling. This silently masked every framework error in the suite from the day it was written until 2026-07-24. `app_test.dart` now reclaims both handlers in `launchApp()`; `all_screens_test.dart` does the same since `078f4e3` (2026-07-24) — confirmed 2026-10-09; kept here as a caveat for any new integration file.

15. **~~`seed_integration_test_users.py` is stale and misleading~~** — retired 2026-07-25. Orphaned (docs-only references), broke on missing `school_id`, and unfixable in place: its four accounts now live in different schools, and re-running it would reset the MPINs of the accounts the tests rely on. `docs/local-test-accounts.md` is the source of truth for local test credentials.

16. **~~One UI defect remains: Parent Fees overflow~~** — the reported overflow did not reproduce on 2026-10-09; two related ones were found and fixed instead (§9). `test/widget/parent_fees_layout_test.dart` now renders the real screen with the real local data at 390/360/320 px and at 1.5× text. Original note: `RenderFlex overflowed by 13 pixels on the bottom` at a 390 px viewport — debug-mode only, does not crash release builds. Its creator is DEFUNCT in the failure log, so pinning the exact widget needs a dedicated reproduction, not a guess. *(The `ListTile`/`SwitchListTile` ink-splash assertions on Admin Timetable and Teacher Tests were fixed 2026-07-25 with a transparent `Material` wrapper — no visual change.)*

17. **`tests/test_api.py` points at production and is stale.** Its `BASE_URL` is `https://api.mindforge.guru` and it registers, approves and revokes users against the live database. It is also broken: it predates multi-tenancy and omits `school_id`, so every write returns 422. This was discovered the hard way on run `30118897312` — adding `workflow_dispatch` to make the previously-unreachable `api-integration` job runnable also meant a plain `gh workflow run ci.yml` fired it at production. No data was created, only because the 422s rejected every write, and the run was cancelled once the target was noticed. The job now requires an explicit `run_api_integration` input defaulting to false. A file-level production guard was added 2026-07-25: it now refuses a production host unless `MF_API_ALLOW_PROD=1` and is env-targetable via `MF_API_BASE_URL`. **The suite itself still needs multi-tenancy modernization** — `school_id` threaded through register/login, and a reworked parent path (self-register-as-parent is no longer allowed) — before it passes. That was left documented rather than blind-edited, since verifying it properly wants a staging server.

18. **~~On a school holiday a teacher cannot assign homework~~** — fixed 2026-10-09 (`35f5087`, merged in `edb6d4f`): review needs attendance only when the grade has a non-holiday period today, and every daily gate uses the school-local date (Asia/Kolkata). On the live local stack the same holiday, homework 75 now reports `attendance_required: false`. The two blocked §5.8 homework checks still need a run on a school day. Original note: Two gates in `backend/app/routers/teacher.py` combine into a dead end: `create_homework` returns 409 `homework_review_pending` while a past homework's completion review is unfinished, and recording completion returns 400 "Mark attendance for {date} first" unless today's attendance exists for the grade. A holiday has no attendance, so the review can never be closed and no new homework can be assigned for that grade all day. Seen on 2026-10-09 (Hansel & Gretel, grade 8, homework 75) with the "Holiday! No classes today" banner showing at the same time. Both gates also take "today" from UTC, so between 00:00 and 05:30 IST it is still yesterday. This also blocks two §5.8 realtime checks.

19. **A rebuilt web bundle is not picked up by a normal reload.** The browser kept the previous `main.dart.js` in its HTTP cache (no service worker or Cache Storage entries were involved), so a fix looked like it hadn't worked. When verifying a web change against `python -m http.server`, force-fetch the bundle (`fetch('main.dart.js', {cache: 'reload'})`) or hard-reload before judging the result. Also: `http.server` ignores `_redirects`, so a hard refresh on a deep route (`/login`) 404s there — a property of the dev server, not the app.

20. **~~The owner's Add School dialog closes on a server error~~** — fixed 2026-10-09: it (and Add Admin, which had the same flaw) now submits in place and stays open with the server's message; `test/widget/owner_dialogs_test.dart`. Original note: the typed name, email and phone were lost and had to be re-entered. Minor; noticed 2026-10-09 while checking §5.2.

21. **Check which checkout the local backend is serving before trusting a result.** `docker-compose.yml` bind-mounts `./backend:/app` relative to wherever `docker compose up` ran, so a stack started from a worktree serves that worktree's code to every session. Verify with `docker inspect mindforge_backend --format '{{range .Mounts}}{{.Source}}{{end}}'`. Seen 2026-10-09 (§9).

22. **~~The two-factor prompt disposes its text controller too early~~** — fixed 2026-10-10 (late): the prompt's State owns the controller; `test/widget/login_screen_test.dart`, "two-factor prompt" group. Not yet driven by hand with an MFA-enrolled account. Original note: `login_screen.dart` creates the MFA code controller, awaits `showDialog`, and disposes it on the next line — the pattern that put a red error screen up when the delete-account dialog was cancelled (§9, 2026-10-10). Debug-only as far as is known (release builds skip the assertions). Untested and unfixed; it needs a widget test that reaches the prompt, or an MFA-enrolled account.

23. **A hidden browser pane cannot drive the Flutter web build.** With the pane not displayed the page stops getting animation frames, the splash's animation controllers never complete, and the app sits on the splash with an empty accessibility tree. It looks like an app hang and is not one. When the pane is visible, Flutter's accessibility tree (click the `flt-semantics-placeholder` once) reads every screen as text. Seen 2026-10-10.

24. **Production logs probably contain access tokens.** Until the 2026-10-10 fix ships, every WebSocket handshake logs its `?token=`. Once it has shipped, consider how long the existing logs are retained and who can read them. A token is good for an hour from issue, so old log lines are not a live credential — but the log is still not where they belong.

### Resolved (kept for history)
- ~~Duplicate-school error asks the owner to change a slug they never see~~ — fixed 2026-10-09; name clashes now name the school.
- ~~Flutter integration tests broke on the login redesign~~ — fixed 2026-10-09; tests find login controls via `LoginKeys`, not visible text.
- ~~School logo and avatars blocked by CSP on a local web build~~ — fixed 2026-10-09; `img-src` now lists the local API origins, pinned by `web_csp_test`.
- ~~MPIN cells overflow the login card on narrow phones; school name runs under the dashboard logout icon~~ — fixed 2026-10-09.
- ~~SSL pin leaf cert expires 2026-06-28~~ — superseded 2026-06-01 by CA-level pinning (`ssl_pinning.dart`). Leaf rotation no longer breaks the app; current leaf expires 2026-08-27.
- ~~Firebase not configured for the Flutter web build~~ — `web` block added 2026-06-30. Functional re-test still open (item 8).
- ~~`test_logout_handler.py` fails on Python ≥3.12 locally~~ — fixed 2026-05-14 via real `type()` classes in `conftest.py`.
- ~~Default admin MPIN `123456` hardcoded in seed~~ — fixed 2026-05-14; reads `ADMIN_SEED_MPIN`, skips with a warning if missing/invalid.
- ~~Live admin MPIN was still the legacy default~~ — rotated 2026-05-14.
- ~~`/ws/{user_id}` accepts any user id with no token check~~ — fixed 2026-05-14; validated against `sub` + JTI blacklist. Covered by `test_websocket_auth.py`.
- ~~Mass assignment on `/api/auth/register`~~ — fixed 2026-05-19.
- ~~Integration test suite needs maintenance~~ — fixed 2026-05-14; 5/5 on iPhone 17 Pro.
- ~~Add `test_websocket_auth.py` to CI~~ — done 2026-05-14. (Four *other* files are still missing — item 2.)
- ~~No CSP `<meta>` on the Flutter web entry HTML~~ — added 2026-05-19; `blob:` added to `connect-src` 2026-07-03 for avatar upload.
- ~~Production `docker-compose.yml` exposes postgres/redis/minio to the host~~ — fixed 2026-05-19.
- ~~`frontend/test/widget_test.dart` fails~~ — deleted 2026-05-14, superseded by `integration_test/app_test.dart`.
- ~~`google.generativeai` package deprecated~~ — migrated to `google-genai==2.2.0` on 2026-05-14.
- ~~AI source PII residual risk~~ — disclosed in `PRIVACY_POLICY.md` §5 on 2026-05-14. *(Reopened in spirit as item 5 — the disclosure names Gemini/Groq, not Anthropic.)*

---

## 11. Re-running This Record

When you finish a test session:

1. Update §2 with the new date and per-suite pass/fail.
2. For any item in §3–§7 you actually re-checked, update its status and date inline. **If you didn't re-check it, mark it `NOT RE-VERIFIED` rather than leaving a stale `PASS`.**
3. Add a dated entry at the top of §9 summarising what changed.
4. Add new gaps to §10; move fixed ones into "Resolved" with a strikethrough and the fix date.
5. Prefer citing a file and symbol (`main.py` — `SecurityHeadersMiddleware`) over a line number. Line numbers in this file have gone stale twice.

Keep this file in version control so the history is preserved.
