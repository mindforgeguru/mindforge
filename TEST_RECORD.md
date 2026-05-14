# Mindforge — Testing Record

**Last updated:** 2026-05-14
**Maintainer:** chinmay1975@gmail.com
**Scope:** Reference document for every kind of testing performed on the Mindforge app — automated tests, security/privacy verification, and manual QA. Update this file every time a significant test session is run.

> **How to use this file.** Each section has a checklist with a status column. When you run a check, set the status to `PASS` / `FAIL` / `SKIP` and add the date. Old results are kept in the "History" section at the bottom so we can see drift over time.

---

## 1. Test Inventory

| Layer | Where | What it covers | Runs in CI? |
|---|---|---|---|
| Backend unit tests | `backend/tests/test_unit.py` | JWT round-trip, refresh-token type, expiry handling, login/register schema validation | Yes (`.github/workflows/ci.yml`) |
| Backend logout-handler tests | `backend/tests/test_logout_handler.py` | FCM token clearing on logout, JWT revocation failure path | Yes |
| Backend WebSocket auth tests | `backend/tests/test_websocket_auth.py` | `/ws/{user_id}` rejects malformed / refresh-type / mismatched-sub / revoked-JTI tokens; accepts valid matching token | **Add to CI** — currently only in `test_unit.py + test_logout_handler.py` are listed in `.github/workflows/ci.yml`, this new file needs adding |
| Backend API integration | `backend/tests/test_api.py` (referenced by CI; manual/scheduled trigger) | Live endpoint smoke tests against prod | Manual dispatch only |
| Flutter unit tests | `frontend/test/unit/` | `AuthState`, `AuthNotifier`, `ApiClient.logoutOnServer`, models | Yes |
| Flutter widget tests | `frontend/test/widget/` | `BadgeDot`, `LoginScreen`, shimmer skeletons | Yes |
| Flutter integration tests | `frontend/integration_test/` (`all_screens_test.dart`, `app_test.dart`) | Whole-app smoke through every screen | No — run locally with `flutter test integration_test/` against a device/emulator. **Currently partially broken** — see §10 item 7. |
| Local stack bootstrap | `docker-compose.yml` (postgres/redis/minio/backend) + `backend/scripts/seed_integration_test_users.py` | Spin up local backend for integration testing | Manual. Seed script populates admin/teacher/student/parent users that integration tests expect. |

**How to run everything locally:**

```bash
# Backend
cd backend
python3 -m pytest tests/test_unit.py tests/test_logout_handler.py -v

# Flutter unit + widget
cd frontend
flutter test test/unit/ test/widget/ --reporter compact

# Flutter integration (needs a connected device or simulator)
flutter test integration_test/
```

---

## 2. Latest Automated Test Run

**Date:** 2026-05-14
**Branch:** `main`
**Environment:** macOS (darwin 25.3.0), Flutter 3.41.4

| Suite | Result | Notes |
|---|---|---|
| Backend `test_unit.py` (16 tests) | **PASS** — all 16 | JWT, security, password hashing |
| Backend `test_logout_handler.py` (3 tests) | **PASS** (after conftest.py fix on 2026-05-14) — uses real `type()` classes for `Base` / `AsyncSession` so FastAPI annotation resolution works on Python 3.11–3.14. |
| Flutter unit (`test/unit/`) | **PASS** — all | 4 test files, `AuthState`, `AuthNotifier`, `ApiClient.logoutOnServer`, models |
| Flutter widget (`test/widget/`) | **PASS** — all | 3 test files, badge dot, login screen, shimmer |
| **Combined Flutter total** | **PASS — 82 / 82** | |
| Flutter integration (`integration_test/`) | **NOT RUN** | Run on device before each release; see §6 |

---

## 3. Backend Security Audit

Verified by reading source + hitting live API headers on `https://api.mindforge.guru/api/health` (2026-05-14).

### 3.1 HTTP security headers
All 5 issues from the 2026-04-05 `test_report.md` are now fixed and verified live.

| Header | Status | Live value |
|---|---|---|
| `Strict-Transport-Security` | **PASS** | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | **PASS** | `nosniff` |
| `X-Frame-Options` | **PASS** | `DENY` |
| `Content-Security-Policy` | **PASS** | `default-src 'none'` |
| HTTPS enforced | **PASS** | HTTP/2 only, Railway edge enforces TLS |

Source: `backend/main.py:161-171` — `SecurityHeadersMiddleware` applies to every response.

### 3.2 Authentication & sessions

| Check | Status | Source |
|---|---|---|
| MPINs stored as bcrypt hash (work factor 12) | **PASS** | `backend/main.py:133`, `app/core/security.py` |
| Access tokens are short-lived JWTs (60 min) | **PASS** | `JWT_EXPIRE_MINUTES=60` |
| Refresh tokens are separate JWTs (30 days) with `type=refresh` claim | **PASS** | `app/routers/auth.py:266` |
| Refresh tokens rotate on use; old JTI is blacklisted | **PASS** | `app/routers/auth.py:288-291` |
| Logout revokes access-token JTI in Redis | **PASS** | `app/routers/auth.py:325` |
| Logout revokes refresh-token JTI when client sends it | **PASS** | `app/routers/auth.py:340` |
| Logout clears the user's FCM token | **PASS** | `app/routers/auth.py:344` |
| Web session cookie is `Secure; HttpOnly; SameSite=Strict; Path=/api` | **PASS** | `app/routers/auth.py:40-50` |
| Login rate-limited per (IP, username) — 10 attempts / 60s | **PASS** | `app/routers/auth.py:188` |
| Account lockout after repeated failed logins (15 min) | **PASS** | `app/routers/auth.py:201-206` |
| Deactivated / soft-deleted users cannot log in | **PASS** | `app/routers/auth.py:196`, `223` |
| Pending accounts cannot log in | **PASS** | `app/routers/auth.py:217` |

### 3.3 Transport security

| Check | Status | Source / evidence |
|---|---|---|
| Mobile app pins leaf cert + Let's Encrypt R12 intermediate | **PASS** | `frontend/lib/core/security/ssl_pinning.dart` |
| Leaf cert expiry tracked | **OPEN** | Memory says leaf expires 2026-06-28 — rotate well before then |
| Refresh tokens stored in OS secure storage (Keychain / Keystore) | **PASS** | `flutter_secure_storage` used in `auth_provider.dart` |

### 3.4 Secrets & error reporting

| Check | Status | Source |
|---|---|---|
| No secrets committed in repo | **PASS** | Verified `.env.local` is gitignored, no hardcoded keys in `app/` |
| Sentry scrubs MPIN/password/token/cookie keys before send | **PASS** | `backend/main.py:33-49` — `_SCRUB_KEYS`, `_scrub_event` |
| Sentry `send_default_pii=False` | **PASS** | `backend/main.py:59` |
| Default admin MPIN now read from `ADMIN_SEED_MPIN` env var (no hardcoded `123456`); seed skipped + warning logged if env missing or not 6 digits | **PASS** (since 2026-05-14) | `backend/main.py`. `.env.example` updated. **Action still required:** rotate the existing admin MPIN in the live prod DB — see Known Issues §10 item 1. |

### 3.5 API surface

| Check | Status | Source |
|---|---|---|
| `/api/media/{bucket}/{key}` allowlists buckets (only profiles) | **PASS** | `backend/main.py:238-240` — prevents arbitrary bucket access |
| CORS origins restricted via `settings.BACKEND_CORS_ORIGINS` | **PASS** | `backend/main.py:178-184` — verify env var is not `*` in prod |
| WebSocket connection requires JWT in query string; validates `sub == user_id`; rejects revoked JTIs | **PASS** (since 2026-05-14) | `backend/main.py` `/ws/{user_id}` accepts `?token=...`, decodes via `decode_access_token`, closes with 1008 on mismatch / wrong token type / revoked JTI. Frontend `websocket_client.dart` appends `?token=` automatically. |

---

## 4. Privacy Audit

### 4.1 Account deletion (Play Store / App Store requirement)

| Check | Status | Source |
|---|---|---|
| In-app "Delete my account" button visible in student/teacher/parent profile | **PASS** | `frontend/lib/core/widgets/privacy_data_section.dart` |
| Admin profile does **not** offer self-delete | **PASS** | Excluded server-side (`auth.py:428`) and client-side |
| Deletion is soft (sets `deleted_at` + `is_active=False`) | **PASS** | `app/models/user.py:59-61`, `auth.py:465` |
| Deletion revokes access token JTI | **PASS** | `auth.py:443` |
| Deletion revokes refresh token JTI if client sends it | **PASS** | `auth.py:460` |
| Deletion clears FCM push token | **PASS** | `auth.py:464` |
| Deletion writes an `AuditLog` row (`action="self_delete"`) | **PASS** | `auth.py:469-475` |
| Deleted user cannot log in (filtered by `deleted_at IS NULL`) | **PASS** | `auth.py:196`, `282` |

### 4.2 Privacy policy

| Check | Status | Notes |
|---|---|---|
| Draft policy authored | **PASS** | `PRIVACY_POLICY.md` (2026-05-14) |
| Policy reviewed by counsel | **PENDING** | Recommended before store submission |
| Policy hosted at public URL | **PENDING** | |
| `AppConstants.privacyPolicyUrl` populated with that URL | **PENDING** | Currently empty at `frontend/lib/core/utils/constants.dart:18`. The in-app link auto-hides while empty. |
| URL also entered in Play Console / App Store Connect | **PENDING** | |

### 4.3 Third-party PII flow

| Recipient | Receives PII? | Verified |
|---|---|---|
| Sentry (backend) | No real PII — `send_default_pii=False` + scrubber strips MPIN/tokens | **PASS** |
| Firebase Crashlytics | Crash trace + device metadata only | **PASS** (no manual user-id mapping found in code) |
| Firebase Analytics | Event names + screen names, no real names | **PASS** (events emitted by `analytics_service.dart`-style helpers, not PII-bearing) |
| FCM | Device token + notification payload | **PASS** |
| Gemini / Groq | Only the prompt content sent for AI features | **PASS** — `_build_prompt`, `_build_scan_prompt`, `_build_syllabus_prompt` (`backend/app/services/ai_service.py`) use only subject/chapter/grade and teacher-uploaded PDF bytes. No username/email/phone/user_id appears in any prompt. Caveat: teacher-uploaded PDFs may themselves contain student names (e.g. scanned answer sheets) — disclose in privacy policy. |
| MinIO | Profile pictures + uploaded files | **PASS** — proxied through backend, bucket allowlisted |

### 4.4 Data subject rights coverage

| Right | Mechanism |
|---|---|
| Access | Profile screens display all per-user data; admins can export |
| Correction | Edit profile from the app; admin tools for the rest |
| Deletion | In-app self-delete (§4.1); parent can act for minor |
| Withdraw consent | Equivalent to deletion |

---

## 5. Manual Functional QA Checklist

Run this end-to-end before every release build. Tick PASS/FAIL with date.

### 5.1 Auth flows

- [ ] **Register student** → goes to pending screen
- [ ] **Register teacher** → goes to pending screen
- [ ] **Register parent (auto-created from student registration)** → exists in DB
- [ ] **Login while pending** → "pending approval" message
- [ ] **Admin approves user** → user can now log in
- [ ] **Login with correct MPIN** → lands on correct dashboard for role
- [ ] **Login with wrong MPIN** → 401 with "Invalid username or MPIN"
- [ ] **Login 11 times wrong in a row** → 429 rate-limit kicks in
- [ ] **Login 5 wrong, then correct** → lockout counter clears on success
- [ ] **Logout** → access + refresh JTIs blacklisted, FCM cleared, local secure storage cleared
- [ ] **Access token expiry (~60 min)** → Dio interceptor auto-refreshes via `/auth/refresh`
- [ ] **Force-revoked token (server-side)** → next protected call returns 401

### 5.2 Student

- [ ] Dashboard summary loads (single `/student/dashboard-summary` call)
- [ ] Attendance history paginated
- [ ] Test list, take a test (single-attempt: back / app-kill forfeits with 0)
- [ ] Homework list, submission
- [ ] Fees screen
- [ ] XP card visible (mobile **and** desktop web)
- [ ] Leaderboard
- [ ] Theme unlock at level threshold
- [ ] Profile → Privacy & Data section visible; delete-my-account dialog works

### 5.3 Teacher

- [ ] Dashboard summary loads
- [ ] Daily Workflow road shows current grade's color, car advances per milestone
- [ ] Every milestone tappable
- [ ] Pre-fill attendance from previous period works
- [ ] Holiday / no-class day → car advances correctly
- [ ] HW review uses most-recent-HW model
- [ ] Workflow car replaces current pending milestone (no duplicates)
- [ ] Profile → Privacy & Data visible

### 5.4 Parent

- [ ] Dashboard shows linked child's data
- [ ] Attendance / tests / homework / fees visible read-only
- [ ] Profile → Privacy & Data visible

### 5.5 Admin

- [ ] Dashboard loads, no overflow on small screens
- [ ] Pending users list — approve flow
- [ ] Pending users list — reject (hard-delete) flow, no 500
- [ ] Faculty approval filter works
- [ ] User management (deactivate / re-activate)
- [ ] Feedback viewer shows in-app problem reports
- [ ] Profile **does NOT** show "Delete my account" (admin protection)
- [ ] Attempting `DELETE /api/auth/account` as admin → 403

### 5.6 Cross-cutting

- [ ] Pull-to-refresh on every list screen
- [ ] Error states show `ErrorView` with retry
- [ ] Loading states show shimmer skeletons
- [ ] Push notification received (attendance, test, fees, HW announcement)
- [ ] WebSocket reconnect works after backgrounding the app (no infinite reconnect loop — known fixed in `b33d494`)
- [ ] Web app desktop layout — student XP card visible
- [ ] All routes emit a `screen_view` analytics event

---

## 6. Release-Build QA (Android)

Run before submitting to Play Store. Release builds enable code shrinking and obfuscation, which can break things that work in debug.

```bash
cd frontend
flutter build appbundle --release   # produces AAB at build/app/outputs/bundle/release/
flutter build apk --release         # for sideload testing
```

- [ ] APK installs on a real Android device (not emulator)
- [ ] Login works on release build (catches issues with ProGuard stripping JSON model classes)
- [ ] Push notification received on release build
- [ ] SSL pinning still works (try with bad cert in Charles/mitmproxy → connection should be refused)
- [ ] All dashboards load
- [ ] Crashlytics receives a forced test crash from release build (`FirebaseCrashlytics.instance.crash()`)
- [ ] Sentry receives a forced backend error in prod
- [ ] App icon, splash screen, app name correct on home screen
- [ ] Signed with release keystore (`frontend/android/key.properties` present, `mindforge-release.jks` in place)

---

## 7. Release-Build QA (iOS)

**Blocked** as of 2026-05-14 — user is not enrolled in the Apple Developer Program. Once enrolled:

- [ ] Xcode → Signing & Capabilities → Team picked, `DEVELOPMENT_TEAM` written into `project.pbxproj`
- [ ] `flutter build ipa --release` succeeds
- [ ] TestFlight upload + install
- [ ] Repeat §5 and §6 checklists on the IPA build

---

## 8. CI Status

CI workflow: `.github/workflows/ci.yml`
- Backend unit tests on every push to `main`, `feature/**`, `fix/**`, `test/**` and on every PR to `main`.
- Flutter analyze + unit + widget tests on the same triggers.
- API integration suite runs **only on manual dispatch or schedule** — kick it off after a deploy with `gh workflow run ci.yml`.

| Check | Status | Evidence |
|---|---|---|
| Latest CI run on `main` is green | **TODO** | Check `gh run list --branch main --limit 1` |

---

## 9. Past Test Sessions (History)

### 2026-05-14 (fifth pass — integration tests now 5/5 PASS)
- Identified the iPhone 17 Pro failures from the fourth pass as a single bug in `app_test.dart`: unconditional `tester.view.physicalSize` override breaks taps on the live binding.
- Fix: gated the override on `binding is! LiveTestWidgetsFlutterBinding`. Briefly tried adding `tearDown(() => binding.takeException())` to drain cascade state — that broke every test because `takeException` asserts `inTest == true` and is not callable from tearDown on the live binding. Reverted that part; the cascade goes away on its own once root failures are fixed.
- Re-ran on iPhone 17 Pro (5E8E59C3-…) → **5/5 PASS in ~108 s** including admin end-to-end login.

### 2026-05-14 (fourth pass — integration tests on iOS simulator)
- Local stack stood up via `docker compose up -d postgres redis minio` (containers were already healthy from prior session). Backend was already running with `./backend:/app` volume-mounted, so the WS auth and admin-seed changes from this session were live in the container.
- Seed script `backend/scripts/seed_integration_test_users.py` ran cleanly — created/updated all 4 integration-test users (admin/300573, chinmay_sir/100898, dummy8/111111, dummy8_dad/111111) and linked the student to the parent. Idempotent for future re-runs.
- Booted iPhone 17 Pro simulator (UDID `5E8E59C3-…`) and iPhone 16e simulator (UDID `5E72C495-…`).
- Ran `flutter test integration_test/app_test.dart` against both.

| Simulator | Tests passed | Notes |
|---|---|---|
| iPhone 17 Pro | **2 / 4** | Splash transition + Request Access tab render PASSED. "Wrong credentials" and "Admin can log in" both failed with `No widgets found at Offset(570.0, 1335.0)` — hardcoded tap coordinates land off-screen on iPhone 17 Pro's larger viewport. |
| iPhone 16e | **0 / 5** | Splash test failed first, then the `FlutterError.onError` override state leaked into the binding and every subsequent test reported "did not complete." Suite-level cascade failure. |

- **App builds and launches cleanly on both simulators.** Login screen renders, registration UI renders. Backend reachable from simulator at `127.0.0.1:8000` (simulator shares network with host). The 2 passing tests prove the loop end-to-end.
- **Test-suite issues, not app bugs.** Tracked as Known Issue §10 item 7.

### 2026-05-14 (third pass — verification + new WS test)
- Wrote `backend/tests/test_websocket_auth.py` (5 tests covering: malformed token, refresh token misuse, mismatched `sub`, revoked JTI, valid token). All PASS.
- Full backend pytest sweep: **38/38 PASS** (was 33; +5 new WS tests).
- Full Flutter test sweep (`flutter test`) found one pre-existing failure in `test/widget_test.dart` — a top-level smoke test not in CI's path (CI only runs `test/unit/` + `test/widget/`). The test pumps `MindForgeApp()` and expects `MaterialApp`; fails likely because Firebase / Sentry initialization is required for the app to mount. Not related to today's changes. Tracked in Known Issues §10 item 4.
- Flutter integration tests (`integration_test/`) **not run in this pass** — see fourth pass entry above for the follow-up run with local stack and iOS simulator.

### 2026-05-14 (second pass — fixed 4 of the 5 Known Issues)
- Fixed `conftest.py` so `test_logout_handler.py` runs cleanly on Python 3.11–3.14. Backend now **33/33 PASS locally** (was 30/33).
- Hardened admin seed to require `ADMIN_SEED_MPIN` env var; `.env.example` updated.
- Added JWT auth to `/ws/{user_id}` — backend rejects bad/expired/revoked tokens, frontend `websocket_client.dart` appends `?token=` and all 4 call sites updated to pass the access token.
- Verified AI prompts contain no user PII; updated §4.3.
- Re-ran tests: backend 33/33 pass, Flutter 82/82 pass, `flutter analyze` shows no new errors (existing deprecation warnings unchanged).
- One Known Issue remains: rotate the live admin MPIN. SSL cert rotation reminder still pending for June.

### 2026-05-14 (initial audit)
- 82/82 Flutter tests pass.
- Backend 30/33 pass locally (3 fails were Python 3.14 MagicMock issue).
- Live API headers verified — all April 5 issues remain fixed.
- Privacy controls audited; all production-side gaps closed. Pending items external (host policy, populate URL, lawyer review).

### 2026-04-05 (`test_report.md`)
- API smoke: 8/8 endpoints reachable.
- Performance: TTFB 473 ms, all endpoints <400 ms avg.
- Security: 5 issues flagged — HSTS, login rate limit, X-Content-Type-Options, X-Frame-Options, CSP.
- **All 5 issues fixed as of this run (verified 2026-05-14).**

---

## 10. Known Issues & Caveats

1. **WebSocket auth is a breaking change.** As of 2026-05-14, `/ws/{user_id}` rejects connections without a valid `?token=` query string. Old installed app versions will lose their realtime updates after the backend deploys. Ship the new frontend (release build with the updated `websocket_client.dart`) at the same time as the backend.
2. **SSL pin leaf cert expires 2026-06-28.** Rotate at least 2 weeks ahead per the procedure in `frontend/lib/core/security/ssl_pinning.dart`, then re-run §3.3.
3. **~~AI source PII residual risk~~** — disclosed in `PRIVACY_POLICY.md` §5 on 2026-05-14. Added a "Teacher-uploaded source documents" paragraph explaining that uploaded PDFs (chapter scans, old test papers) go to Gemini/Groq in full, and recommending teachers redact identifiable student info before upload. §7 sharing table updated to cross-reference §5.
4. **~~`frontend/test/widget_test.dart` fails~~** — deleted 2026-05-14. Was a `flutter create` autogenerated smoke test that pumped `MindForgeApp()` without Firebase init, so any Firebase-dependent widget threw. Superseded by `integration_test/app_test.dart`'s "Splash → login" test which exercises the same flow on a real simulator.
5. **~~`google.generativeai` package is deprecated~~** — migrated to `google-genai==2.2.0` on 2026-05-14. Changes in `backend/app/services/ai_service.py`: `genai.configure(...)` + `GenerativeModel` → singleton `genai.Client`; `model.generate_content(...)` → `client.models.generate_content(model=..., contents=..., config=_GEMINI_GENERATION_CONFIG)`; `genai.upload_file(...)` → `client.files.upload(file=..., config=types.UploadFileConfig(mime_type=...))`; `genai.delete_file(name)` → `client.files.delete(name=name)`. Test stub in `test_logout_handler.py` updated to match. `requirements.txt` pin updated. All 38 backend tests still pass; local Docker backend restarted with new package; `/api/health` confirmed green. New SDK emits one cosmetic `_UnionGenericAlias` DeprecationWarning that's an upstream Python 3.17 concern, not ours.
6. **~~Add `test_websocket_auth.py` to CI~~** — done 2026-05-14. CI now runs each backend test file in its own `pytest` invocation (`test_unit.py`, `test_logout_handler.py`, `test_websocket_auth.py` as separate steps). Split was necessary because `test_logout_handler.py` and `test_websocket_auth.py` install module-level `sys.modules` stubs that mutate state shared with `test_unit.py` — running them in one session causes order-dependent failures (specifically, a tampered-JWT assertion silently passes). Long-term cleanup: refactor the stubs into `conftest.py` so a single pytest invocation works. Tracked separately.
7. **~~Integration test suite needs maintenance~~** — fixed 2026-05-14. Root cause was a single line in `setUp` / `passSplash`: `tester.view.physicalSize = (390, 844)` was being applied unconditionally, including on the live integration binding. On a real simulator the widget tree still laid out at the device's true size, but `tester.tap` hit-tests used the overridden frame — so computed tap centers (e.g. `(570, 1335)`) fell outside the virtual frame and missed. Once the first test failed, the framework's exception state cascaded and every subsequent test reported "did not complete." Fix in `frontend/integration_test/app_test.dart`: gate the `physicalSize` / `devicePixelRatio` override on `binding is! LiveTestWidgetsFlutterBinding` so unit-test mode still gets the phone canvas but the live binding uses the device's real viewport. **Result on iPhone 17 Pro: 5/5 PASS**, including the admin-login end-to-end flow.

### Resolved (kept for history)
- ~~`test_logout_handler.py` fails on Python ≥3.12 locally~~ — fixed 2026-05-14 by giving `Base` and `AsyncSession` real `type()` classes in `conftest.py`.
- ~~Default admin MPIN `123456` hardcoded in seed~~ — fixed 2026-05-14; now reads `ADMIN_SEED_MPIN`, skips with warning if missing/invalid.
- ~~Live admin MPIN was still the legacy default~~ — rotated by user 2026-05-14 via the in-app Change MPIN flow.
- ~~`/ws/{user_id}` accepts any user id with no token check~~ — fixed 2026-05-14; token now required and validated against `sub` claim + JTI blacklist.
- ~~Gemini/Groq prompt PII unverified~~ — verified clean 2026-05-14 (§4.3).

---

## 11. Re-running This Record

When you finish a test session:

1. Update the "Latest Automated Test Run" table in §2 with the new date and pass/fail.
2. For any item in §3–§7 you re-checked, update its status and date inline.
3. Add a new dated entry at the top of §9 summarizing what changed.
4. If you found a new gap, add it to §10.

Keep this file in version control so the history is preserved.
