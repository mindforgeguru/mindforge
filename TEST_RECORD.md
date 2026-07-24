# Mindforge — Testing Record

**Last updated:** 2026-07-25
**Maintainer:** chinmay1975@gmail.com
**Scope:** Reference document for every kind of testing performed on the Mindforge app — automated tests, security/privacy verification, and manual QA. Update this file every time a significant test session is run.

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
| Backend tenancy unit tests | `backend/tests/test_tenancy.py` (19) | `require_school_id`, `same_school_or_404` (404 not 403), `assert_school_active` (suspension, owner exemption), cached student profile carries `school_id`, every tenant model has a `school_id` column | **No — gap, see §10 item 2** |
| Backend tenancy wiring tests | `backend/tests/test_tenancy_wiring.py` (8) | `get_current_user` and `/auth/refresh` both enforce school suspension; owner is not gated | **No — gap, see §10 item 2** |
| Backend realtime fan-out tests | `backend/tests/test_realtime_fanout.py` (8) | Grade audience resolution (students + parents, dedup), explicit user-ID addressing, empty audience publishes nothing, `broadcast_to_users` delivery | **No — gap, see §10 item 2** |
| Backend tenant-isolation integration | `backend/tests_integration/test_tenant_isolation.py` + `…_finance.py` (32) | Router-level cross-school scoping against a live stack | No — skips cleanly when the stack is down |
| Backend realtime delivery integration | `backend/tests_integration/test_realtime_delivery.py` (4) | Real WebSocket: grade broadcast reaches the grade's students and staff, `homework_added` reaches both, school-wide broadcast does **not** cross schools | No — same skip |
| API integration / probes | `tests/test_api.py`, `tests/security_test.py`, `tests/security_test_extended.py`, `tests/performance_test.py` | Live endpoint smoke, security probe matrix, latency | **No — the CI job is unreachable, see §10 item 3** |
| Flutter unit tests | `frontend/test/unit/` (78, 6 files) | `AuthState`, `AuthNotifier`, `ApiClient.logoutOnServer`, models, admin setup status, owner API error messages | **Yes** |
| Flutter widget tests | `frontend/test/widget/` (26, 5 files) | `BadgeDot`, `LoginScreen`, shimmer skeletons, setup road card, **`RealtimeSync` event→cache mapping** | **Yes** |
| Flutter integration tests | `frontend/integration_test/` — `app_test.dart` (5), `all_screens_test.dart` (29) | Auth flows; every screen for every role | No — needs a simulator **and** `--dart-define=LOCAL_DEV=true`, or it hits production |
| Local stack bootstrap | `docker-compose.yml` + `docker-compose.local.yml` + `backend/scripts/seed_integration_test_users.py` | Spin up postgres/redis/minio/backend for integration testing | Manual |

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

**Date:** 2026-07-24 / 25
**Branch:** `create_school`
**Environment:** macOS (darwin 25.5.0), Flutter 3.44.0 (stable), Python 3.14

### 2.1 Backend — each file in its own pytest process (mirrors CI)

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

### 2.2 Frontend

| Suite | Result |
|---|---|
| `flutter test test/unit/` | **PASS — 78/78** |
| `flutter test test/widget/` | **PASS — 26/26** (+5 new `realtime_sync_test.dart`) |
| `flutter test` (everything) | **PASS — 104/104** |
| `flutter analyze lib test integration_test` | **PASS — 0 errors, 0 warnings, 6 style infos** |

The 3 infos: one `prefer_const_declarations` in `lib/features/teacher/screens/homework_screen.dart:741`, two `no_leading_underscores_for_local_identifiers` in `test/unit/auth_notifier_test.dart`. CI runs `flutter analyze --no-fatal-infos`, so none of the three break the build.

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

### 2.3 Not run this session

| Suite | Why |
|---|---|
| `pip-audit` on a CI runner | Green locally in a Python 3.12 venv; the runner has never executed the fixed workflow (see §8) |
| `tests/security_test.py`, `security_test_extended.py` | Not run — no longer blocked (the stack is up), just out of scope for this session. Point them at the **local** stack only; they include login rate-limit probes |
| `tests/performance_test.py` | Same |

`pip-audit` **was** run locally this session (Python 3.12 venv, since `pymupdf` won't build on the default 3.14) and is now green — see §10 item 1.

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

### 3.2 Authentication & sessions — **NOT RE-VERIFIED (last checked 2026-05-19)**

These were verified by source reading in May. The auth layer has changed materially since (multi-tenancy, school suspension gating, MPIN blocklist, lockout-DoS guard, audit logging), so the line numbers in the previous record are stale and the table below is **carried forward, not re-confirmed**. Spot-checked as still present on 2026-07-24: bcrypt MPIN hashing, JTI revocation on logout, `ADMIN_SEED_MPIN` env gate (`backend/main.py:134`).

| Check | Status | Source |
|---|---|---|
| MPINs stored as bcrypt hash (work factor 12) | NOT RE-VERIFIED | `app/core/security.py` |
| Access tokens are short-lived JWTs (60 min) | NOT RE-VERIFIED | `JWT_EXPIRE_MINUTES=60` |
| Refresh tokens are separate JWTs (30 days) with `type=refresh` | NOT RE-VERIFIED | `app/routers/auth.py` |
| Refresh tokens rotate on use; old JTI blacklisted | NOT RE-VERIFIED | `app/routers/auth.py` |
| Logout revokes access-token JTI in Redis | NOT RE-VERIFIED | `app/routers/auth.py` |
| Logout revokes refresh-token JTI when client sends it | NOT RE-VERIFIED | `app/routers/auth.py` |
| Logout clears the user's FCM token | **PASS** | covered by `test_logout_handler.py`, re-run today |
| Web session cookie `Secure; HttpOnly; SameSite=Strict; Path=/api` | NOT RE-VERIFIED | `app/routers/auth.py` |
| Login rate-limited per (IP, username) | NOT RE-VERIFIED | `app/routers/auth.py` |
| Account lockout after repeated failed logins (15 min) | NOT RE-VERIFIED | plus lockout-DoS guard added 2026-07-07 |
| Deactivated / soft-deleted users cannot log in | NOT RE-VERIFIED | `app/routers/auth.py` |
| Pending accounts cannot log in | NOT RE-VERIFIED | `app/routers/auth.py` |
| **Suspended school blocks login and refresh; owner exempt** | **PASS** | `test_tenancy_wiring.py`, re-run today (8/8) |

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
| Firebase **client** API keys are public by design; server secret is `FIREBASE_CREDENTIALS_JSON`, env-only | **PASS** (documented) | `SECURITY.md` — console-side key restriction is still an open action |

### 3.5 API surface — **partially re-verified 2026-07-24**

| Check | Status | Source |
|---|---|---|
| `/api/media/{bucket}/{key}` allowlists buckets (profiles only) | **PASS** (spot-checked) | `backend/main.py:362` — `ALLOWED_BUCKETS` |
| CORS forbids wildcard origin | NOT RE-VERIFIED | hardened 2026-06-23; `settings.BACKEND_CORS_ORIGINS` |
| WebSocket requires JWT, validates `sub == user_id`, rejects revoked JTIs | **PASS** | `test_websocket_auth.py`, re-run today (5/5) |
| Cross-school row access returns 404, not 403 | **PASS** | `test_tenancy.py::TestSameSchoolOr404`, re-run today |
| Every tenant-scoped model carries `school_id`, and the migration list matches the models | **PASS** | `test_tenancy.py::TestTenantModelContract`, re-run today |

---

## 4. Privacy Audit

### 4.1 Account deletion — **NOT RE-VERIFIED (last checked 2026-05-14)**

All items below passed on 2026-05-14 by source reading. The auth router has changed since; re-verify before store submission.

| Check | Status |
|---|---|
| In-app "Delete my account" in student/teacher/parent profile | NOT RE-VERIFIED |
| Admin profile does **not** offer self-delete | NOT RE-VERIFIED |
| Deletion is soft (`deleted_at` + `is_active=False`) | NOT RE-VERIFIED |
| Deletion revokes access + refresh token JTIs | NOT RE-VERIFIED |
| Deletion clears FCM push token | NOT RE-VERIFIED |
| Deletion writes an `AuditLog` row (`action="self_delete"`) | NOT RE-VERIFIED |
| Deleted user cannot log in | NOT RE-VERIFIED |

**New since May:** the platform **owner** role exists and is school-less. Confirm whether owner self-delete is permitted or blocked, and add a row here.

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

- [ ] **Register student** → pending screen
- [ ] **Register teacher** → pending screen
- [ ] **Register parent (auto-created from student registration)** → exists in DB
- [ ] **Register with Phone + Email on the wide/web form** → both persist (fixed 2026-07-22)
- [ ] **Login while pending** → "pending approval" message
- [ ] **Admin approves user** → user can now log in
- [ ] **Login with correct MPIN** → correct dashboard for role
- [ ] **Login with wrong MPIN** → 401 "Invalid username or MPIN"
- [ ] **Login 11 times wrong** → 429 rate limit
- [ ] **Login 5 wrong, then correct** → lockout counter clears
- [ ] **Weak/blocklisted MPIN rejected at set/change time** (added 2026-07-07)
- [ ] **Logout** → access + refresh JTIs blacklisted, FCM cleared, secure storage cleared
- [ ] **Access token expiry (~60 min)** → Dio interceptor auto-refreshes
- [ ] **Force-revoked token** → next protected call 401

### 5.2 Multi-tenancy & owner *(new section — feature landed 2026-07-22)*

- [ ] Platform owner logs in and lands on the owner dashboard
- [ ] Owner can create a school; admin for that school can log in
- [ ] User in school A cannot read school B's rows (expect **404**, not 403)
- [ ] Suspending a school blocks its users' login **and** token refresh
- [ ] Owner is exempt from suspension gating
- [ ] Phone-number uniqueness is scoped per school, not global
- [ ] Fees and academic years are school-scoped
- [ ] Owner error messages surface the backend detail, not a raw `DioException`

### 5.3 Admin school setup *(new — 2026-07-23/24)*

- [ ] Graphical school-setup workflow gates steps in the right order
- [ ] School Logo setup task uploads and displays
- [ ] Close-Year workflow step completes

### 5.4 Student

- [ ] Dashboard summary loads (single `/student/dashboard-summary` call)
- [ ] Attendance history paginated
- [ ] Test list; take a test (single-attempt: back / app-kill forfeits with 0)
- [ ] Test review matches the per-student option shuffle
- [ ] Homework list + submission; completion status auto-refreshes
- [ ] Fees screen
- [ ] XP card visible (mobile **and** desktop web)
- [ ] Leaderboard; theme unlock at level threshold
- [ ] Holiday banner shows on a holiday
- [ ] Profile → Privacy & Data; delete-my-account dialog

### 5.5 Teacher

- [ ] Dashboard summary loads
- [ ] Daily Workflow road shows current grade's color; car advances per milestone
- [ ] Every milestone tappable; car replaces current pending milestone (no duplicates)
- [ ] Pre-fill attendance from previous period
- [ ] Holiday / no-class day → car advances correctly; whole-school holiday banner shows
- [ ] HW review uses most-recent-HW model; tiles color-coded by review status
- [ ] Presentations: upload PDF and `.pptx`, adopt, log a period
- [ ] Auto-quiz appears in the Online Tests tab as "Generating", then flips to ready/failed
- [ ] Retry on a failed auto-quiz card works
- [ ] Broadcasts are shared school-wide across teachers
- [ ] Profile → Privacy & Data visible

### 5.6 Parent

- [ ] Dashboard shows linked child's data
- [ ] Attendance / tests / homework / fees visible read-only
- [ ] Profile → Privacy & Data visible

### 5.7 Admin

- [ ] Dashboard loads, no overflow on small screens
- [ ] Pending users — approve flow
- [ ] Pending users — reject (hard-delete) flow, no 500
- [ ] Faculty approval filter
- [ ] User management (deactivate / re-activate)
- [ ] Feedback viewer shows in-app problem reports
- [ ] Profile **does NOT** show "Delete my account"
- [ ] `DELETE /api/auth/account` as admin → 403

### 5.8 Realtime *(new section — reworked 2026-07-24, unverified on-device)*

The WebSocket fan-out was rewritten this session. **None of this is manually verified yet** — it is the highest-priority manual QA item.

- [ ] Teacher sends a school-wide broadcast → appears live on student / parent / other-teacher **Broadcasts screen** without navigating or refreshing
- [ ] Teacher sends a **grade-targeted** broadcast → reaches that grade's students + parents, and all teachers
- [ ] Teacher assigns homework → appears live on the student/parent homework screen **and** on other teachers' dashboards
- [ ] Auto-quiz from a presentation period log → appears in the teacher Online Tests list immediately, without pull-to-refresh
- [ ] Marking homework completion updates the student's Pending/Complete pill live
- [ ] Attendance / timetable / grade events refresh the relevant screen live
- [ ] Events do **not** leak across schools (two schools, two browsers)
- [ ] Backgrounding the app for >30 s then resuming reconnects once (no double-reconnect, no infinite loop)

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
- [ ] Left sidebar nav renders and navigates on desktop widths (new)
- [ ] Avatar upload works through the CSP (`blob:` in `connect-src`, added 2026-07-03)
- [ ] MindForge favicon + PWA icons show (new)

### 5.10 Cross-cutting

- [ ] Pull-to-refresh on every list screen
- [ ] Error states show `ErrorView` with retry
- [ ] Loading states show shimmer skeletons
- [ ] Push notification received (attendance, test, fees, HW, broadcast)
- [ ] WebSocket reconnect after backgrounding (no infinite loop)
- [ ] Desktop web — student XP card visible
- [ ] All routes emit a `screen_view` analytics event

---

## 6. Release-Build QA (Android)

```bash
cd frontend
flutter build appbundle --release
flutter build apk --release
```

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
- [ ] `flutter build ipa --release` succeeds
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

   **One advisory is ignored, not fixed:** `ecdsa==0.19.2` / PYSEC-2026-1325 (CVE-2024-23342), the Minerva timing attack on P-256. It affects every released version and upstream considers side-channel attacks out of scope, so there is no fix version. `ecdsa` is a hard dependency of `python-jose`, not something the app imports, and the vulnerable paths are ECDSA signing/keygen/ECDH — MindForge signs JWTs with **HS256** (`JWT_ALGORITHM`, `app/core/config.py:50`), so no ECDSA private-key operation ever runs. The `--ignore-vuln` in `ci.yml` carries this rationale. **Re-evaluate if `JWT_ALGORITHM` ever becomes ES256/384/512.**

   Verified locally in a Python 3.12 venv (CI is on 3.11; the repo's default `python3` is 3.14, where `pymupdf` won't build): dependency resolution clean, `pip-audit --strict` → "No known vulnerabilities found, 1 ignored", backend suite 81/81, FastAPI resolves all 144 OpenAPI paths / 160 operations, and a TestClient smoke returns 200 + all four security headers on `/api/health`, 403 on a non-allowlisted media bucket, 422 on an empty login body.

2. **~~4 of 7 backend test files are not in CI~~** — fixed 2026-07-24. The three hand-listed pytest steps are replaced by a glob over `tests/test_*.py`, so all 7 files (81 tests) run and any new file is picked up automatically — the hand-written list is what let 39 tests, including the whole multi-tenancy safety net, go unrun for weeks. Each file still gets its own process (see item 4), wrapped in `::group::` so the log stays readable. The loop continues past a failure and then exits non-zero, so one broken file doesn't mask the rest; an empty glob fails loudly rather than passing vacuously. Both the failure path and the empty-glob guard were dry-run before committing.

3. **~~The `api-integration` CI job can never run~~** — fixed 2026-07-24. `workflow_dispatch:` added to the workflow's `on:` block, so `gh workflow run ci.yml` now reaches the job (it was previously rejected outright). `schedule:` is still not declared — add it if you want the live-API suite on a timer; the job's `if:` already accounts for it. The job runs `pytest tests/test_api.py` from the repo root, which is correct: that file lives at `tests/test_api.py`, not under `backend/`. **Still unproven** — the job has never actually executed, and it needs the `ADMIN_MPIN` secret to be set.

4. **Backend tests are split into one pytest process per file in CI.** `test_logout_handler.py` and `test_websocket_auth.py` install module-level `sys.modules` stubs that mutate state shared with `test_unit.py`. The whole suite *does* pass in a single session today (81/81), so the hazard is latent rather than active, but the split stays until the stubs move into `conftest.py`. Any new file that installs its own stubs must get its own step.

5. **Claude is a new, unaudited PII recipient.** `ai_service.py` has been Claude → Gemini → Groq since 2026-06-08, with Claude reading uploaded PDFs/images natively through the Anthropic Files API. The May prompt-PII sweep and `PRIVACY_POLICY.md` §5/§7 both predate this. Re-run the prompt audit and add Anthropic to the policy's sharing table before store submission.

6. **`AppConstants.privacyPolicyUrl` is still empty** (`frontend/lib/core/utils/constants.dart:30`). The in-app link auto-hides while empty, so this is not user-visible breakage, but it blocks store submission along with hosting the policy and counsel review.

7. **Firebase client API keys are not yet restricted in the GCP console.** Documented in `SECURITY.md` with the exact keys and the restriction each should carry. Defense-in-depth, not a leak — the app uses only Core/FCM/Analytics/Crashlytics, so a copied key cannot read user data. Worst case is quota abuse.

8. **Firebase web config landed but was never functionally re-tested.** `firebase_options.dart` gained a real `web` block on 2026-06-30, which should close the old "FCM/Analytics/Crashlytics silently disabled on web" finding. Nobody has confirmed a push actually arrives in a browser. §5.9.

9. **`flutter_secure_storage_web` blocks future wasm builds.** The wasm dry-run flags `dart:html` + `dart:js_util` usage. The JS build works today; revisit when Flutter's wasm target stabilises.

10. **~~Realtime fan-out unverified on the client~~** — closed 2026-07-25. `tests_integration/test_realtime_delivery.py` proves the backend delivers (falsified against the old code), and `test/widget/realtime_sync_test.dart` proves the client invalidates the right cache per role (also falsified). **Still open in the same area:** `admin.py`'s `timetable_config_updated` and `new_academic_year` continue to use the unscoped `broadcast_all`, so those two events cross school boundaries.

11. **CI Flutter version drift.** CI pins `3.41.4`; local development is on `3.44.0`. A version-specific analyzer or test failure would not be caught symmetrically.

12. **CI does not run on most working branches.** Triggers are `main`, `feature/**`, `fix/**`, `test/**`. Branches like `create_school` get no CI at all, so work merges to `main` having never been CI-verified.


13. **A dependency bump is not verified until the app boots with a real config.** The 2026-07-24 upgrade passed imports, 81 unit tests, OpenAPI generation and a TestClient smoke in a venv — then failed to start in Docker, because Sentry only wires up its integrations when a `SENTRY_DSN` is present and the venv had none. Any future `requirements.txt` change should be validated by rebuilding the image and watching the container reach "Application startup complete", not by a venv smoke test alone.

14. **An app that installs its own error handlers blinds the integration tests.** `main()` sets Crashlytics as both `FlutterError.onError` and `PlatformDispatcher.onError` (`main.dart:63-64`) before `runApp`. Every integration test calls `app.main()`, so the app displaces the test binding's reporter: framework errors are shipped to Crashlytics instead of failing the test, and the binding surfaces only `_pendingExceptionDetails != null` — an assertion that replaces the real cause with a message about error handling. This silently masked every framework error in the suite from the day it was written until 2026-07-24. `app_test.dart` now reclaims both handlers in `launchApp()`; **`all_screens_test.dart` does not yet** and should get the same treatment.

15. **`backend/scripts/seed_integration_test_users.py` is stale and misleading.** It predates multi-tenancy, has no `school_id` handling, and the credentials it documents (`admin` / 300573) now return 401 against the local database — which is what made the admin-login integration test fail. The tests were repointed at `demo_admin` / 847362 from `docs/local-test-accounts.md` instead. The script was deliberately **not** run, since it writes users and could create school-less rows in a dev database. Update it for multi-tenancy or retire it.

16. **Two UI defects surfaced by the integration suite, left unfixed.** Both are debug-mode assertions that do not crash release builds, and both were invisible until the tests stopped letting Crashlytics swallow framework errors (item 14). (a) *Admin Timetable* and *Teacher Tests*: a `ListTile` sits inside a colour-filled `DecoratedBox` from the shared `mindForgeCardDecoration()`, which hides the tile's own background and ink splashes — tap feedback silently does not render. The helper is used across 12+ screens, so fixing it is a visual change wanting review rather than a test fix. (b) *Parent Fees*: `RenderFlex overflowed by 13 pixels on the bottom` at a 390 px viewport.

17. **`tests/test_api.py` points at production and is stale.** Its `BASE_URL` is `https://api.mindforge.guru` and it registers, approves and revokes users against the live database. It is also broken: it predates multi-tenancy and omits `school_id`, so every write returns 422. This was discovered the hard way on run `30118897312` — adding `workflow_dispatch` to make the previously-unreachable `api-integration` job runnable also meant a plain `gh workflow run ci.yml` fired it at production. No data was created, only because the 422s rejected every write, and the run was cancelled once the target was noticed. The job now requires an explicit `run_api_integration` input defaulting to false. **The underlying file still needs fixing or retiring** — point it at a staging URL and add `school_id`, or delete it. Same bucket as item 15.

### Resolved (kept for history)
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
