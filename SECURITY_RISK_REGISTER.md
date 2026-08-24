# Security Risk Register

**Compiled:** 2026-08-18
**Scope:** Every class of risk an app like MindForge faces, scored against what this
repo actually tests today — not what was intended.
**Companion docs:** [`TEST_RECORD.md`](TEST_RECORD.md) (what was run, when),
[`SECURITY.md`](SECURITY.md) (console-side operational hardening).

There is also a rendered, filterable version of this register:
<https://claude.ai/code/artifact/21c5d455-376a-4b10-87a7-7075764709d9>
(source kept in-repo at [`docs/security-risk-register.html`](docs/security-risk-register.html)).

---

## How to read the status column

| Status | Meaning |
|---|---|
| **VERIFIED** | Exercised by a test or a live check, with evidence in the repo. |
| **STALE** | The control exists in code and passed once, but the record marks it unconfirmed since May and the surrounding code has changed. Not a claim that it is broken — a claim that nobody currently knows. |
| **OPEN** | Never tested, or not built. |

> **A status carried forward is not evidence.** This file inherits that rule from
> `TEST_RECORD.md` §0. If you didn't re-run it, don't promote it.

## Posture at a glance

| | Count |
|---|---|
| Verified | **42** |
| Stale | **24** |
| Open | **24** |
| **Total tracked** | **90** across 13 domains |

*Last verification sweep: 2026-08-20 (see [Verification log](#verification-log)).*

**The shape of it.** Multi-tenancy and authentication are genuinely strong — that is
where the tests are, and it shows. The open items cluster in three places instead:
the **client binary**, which is essentially unhardened; **privacy and compliance**,
which matters more here than in most apps because the records are children's; and
**operational readiness** — backups, alerting, and a plan for the day something
goes wrong.

---

## 1. Authentication & sessions

| Risk | Status | Evidence / note |
|---|---|---|
| Credential storage | VERIFIED | MPINs bcrypt-hashed at work factor 12. Covered by `test_unit.py`. |
| Brute force / credential stuffing | VERIFIED | 10 attempts/min per (IP, username) at `auth.py:361`; register capped 5/60s. Probed by `security_test.py`. |
| JWT forgery, tampering, alg confusion | VERIFIED | HS256, no `none` acceptance. Probed by `test_jwt_security`. |
| Suspended tenant still authenticating | VERIFIED | Login *and* refresh both gated; owner exempt. `test_tenancy_wiring.py` 8/8. |
| Session bleed on account switch (shared device) | VERIFIED | Cache-reset race let the next sign-in read the previous user's data. Found and fixed 2026-08-18 — commit `2bbb630`. |
| Account lockout + lockout-DoS guard | VERIFIED | Two layers, now pinned by 10 tests (`test_account_lockout.py`): per-(user, IP) lock after 5 fails, plus a per-user global backstop at 50 for distributed attacks. The **anti-DoS** property is tested directly — an attacker locking themselves out from one IP leaves the real user, on another IP, able to log in — and each guard was falsified: breaking the IP scope, removing the backstop, or forgetting the global keys on success each fails the matching test. Fails open with no Redis. Known limit: attacker + victim behind one NAT share an IP, so the per-IP lock can catch both — inherent to any IP-based guard. |
| Refresh-token rotation and JTI revocation | VERIFIED | Rotate-on-use with old JTI blacklisted in Redis. Re-confirmed 2026-08-18: `security_test_extended.py` §6 — access token 401s after logout, and a rotated refresh token 401s on reuse. |
| Token lifetime and expiry handling | VERIFIED | 8 tests (`test_token_lifetime.py`): access token carries `exp` at the configured lifetime, a unique `jti` and `type=access`; refresh is long-lived, typed, and outlives access; an expired token is **rejected on decode** (minted with a past expiry, `ExpiredSignatureError`), proving expiry is enforced not merely present. Assertions read the lifetimes from settings, so they track config. Falsified: dropping `exp` fails the expiry tests. |
| Deactivated, pending or deleted users signing in | VERIFIED | The login state-gate is now a pure `login_block_reason` in `app.core.account_state` (the router calls it, keeping its logging + IP), pinned by 8 tests: unapproved → 403 pending, deactivated → 403 deactivated, and a soft-deleted account → an opaque 401 *identical* to a wrong-username reply (no enumeration tell). Deleted is checked first, so a deactivated-then-deleted account can't leak via a stale flag. Deleted rows are also excluded by the login query itself; the function re-asserts it as a single choke-point for reuse. Falsified: skipping the active check or losing deleted-precedence each fails the matching test. |
| Weak / guessable MPIN | VERIFIED | 32 tests (`test_weak_mpin.py`) pin the guessability rule (all-same, runs, half-repeats, keypad shapes) and — the part that matters — the **wiring**: weak PINs are rejected at every set site (register, change `new_mpin`, admin reset) and accepted at login and `current_mpin`, so a legacy weak-PIN user can still sign in and fix it. Falsified: making login strict or register lenient each fails the matching wiring test. |
| Multi-factor authentication | VERIFIED | TOTP (RFC 6238, stdlib) for **admin and owner**, opt-in: enrolment screen (admin profile + owner console) with QR plus typed key, single-use recovery codes, screen-capture blocked while the secret shows; two-step enrolment so an abandoned setup can't lock the account; disable needs MPIN *and* a factor. **The 'marking your own homework' gap is now closed:** beyond the six official RFC vectors, `test_totp_interop.py` carries a from-scratch second implementation (anchored to the RFC vector) that agrees with the app both ways *and* on the secret parsed out of the actual `otpauth://` QR — which is spec-compliant SHA1/6-digit/30s. A real authenticator app is one more RFC-6238 implementation of that same URI, so a physical phone scan (checklist 06) is now a formality, not an open correctness risk. Falsified: a 60s step or a mangled QR secret breaks the interop tests. Other roles keep a single factor by design. |
| Account enumeration | VERIFIED | **Was exploitable.** Bodies always matched, but `login()` short-circuited past bcrypt for an unknown username: 238.7 ms vs 3.9 ms, a 61x tell. Closed with `verify_mpin_constant_time`, which always hashes; re-measured at 240.6 vs 239.7 ms (1.00x). 5 tests. |
| Forgot-MPIN / recovery flow abuse | OPEN | The login screen offers "Forgot your MPIN?" — that flow has no security test at all. |
| Session fixation | OPEN | Not assessed. |

## 2. Authorization & tenant isolation

| Risk | Status | Evidence / note |
|---|---|---|
| Cross-school data access | VERIFIED | Strongest area in the codebase: 32 integration + 19 unit + 8 wiring tests. Cross-school reads return 404 rather than 403, so row existence doesn't leak. |
| Vertical privilege escalation | VERIFIED | Student → teacher → admin paths probed in `security_test_extended.py`. |
| Mass assignment / role injection | VERIFIED | Was **critical** — `/auth/register` accepted `role="admin"`. Fixed 2026-05-19 with a schema validator. |
| Admin escalating a user to platform owner | VERIFIED | Blocked; commit `f9e2386`. |
| IDOR / BOLA on object ids | VERIFIED | Covered by the extended probe suite. |
| Realtime events crossing tenants | VERIFIED | Two separate leaks found and fixed (fan-out, then `admin.py` config events). Tests falsified against the unfixed code. |
| Cross-school foreign keys accepted on write | VERIFIED | Timetable `teacher_id` now validated against the caller's school; commit `25451eb`. |
| Unauthenticated media proxy | STALE | Bucket allowlist and path traversal re-probed 2026-08-18 — 5/5 rejected, including double-encoded and null-byte keys. Still STALE because the actual risk is different: the endpoint stays open by design and leans on object keys being *unguessable*, which no probe tests. |
| Business-logic abuse | STALE | Score is server-computed by `_grade_submission` against the test key; `/save` and `/submit` both 409 once `is_finalized` is set. 9 tests pin the submission surface as exactly `{answers, auto_submitted}`, so a score-bearing field cannot be added silently. STALE: teacher-side abuse — backdating attendance, editing a published grade — is still untested. |
| Parent–child link tampering | VERIFIED | Structurally prevented: `parent_user_id` is written only in `admin.py`, the parent router is read-only, and `_get_child_profile` resolves the child from the authenticated parent's id — there is no id in the request to swap. Both admin link paths scope to `current_admin.school_id`. 12 integration tests, including that another school's student id cannot redirect the read. |

## 3. Injection & input handling

| Risk | Status | Evidence / note |
|---|---|---|
| SQL injection | VERIFIED | Probed live; SQLAlchemy throughout, and a static sweep confirmed no f-string SQL. |
| Command injection / unsafe deserialization | VERIFIED | Static sweep clean: no `eval`, `exec`, `os.system`, `shell=True`, `pickle.loads` or `yaml.load`. |
| Path traversal | VERIFIED | Covered in `security_test_extended.py`. |
| Cross-site scripting (web build) | VERIFIED | Flutter's canvas rendering already removes the usual XSS sinks (no `innerHTML`), so the CSP is the remaining defence — and it is strong: `default-src 'self'`, `frame-ancestors 'none'`, `base-uri 'self'`, `form-action 'self'`, connect-src scoped to the app's own API origins, no bare wildcard anywhere. Now pinned by **6 tests** (`web_csp_test.dart`) that parse `web/index.html` and assert each of those, so weakening the policy fails CI. Falsified: `default-src *` fails 2, dropping `frame-ancestors 'none'` fails 1. `unsafe-inline`/`unsafe-eval`/`blob:` in script-src are left unpinned — Flutter's bootstrap requires them. |
| Prompt injection through uploaded documents | STALE | All three prompts that read uploaded files now frame the document as data and tell the model to ignore directives inside it — previously there was no defence at all. **Mitigation of unverified efficacy:** the tests prove the wording is present, not that a model obeys it. No provider was reachable to test (no Claude key locally; Gemini over its spending cap). `scripts/probe_prompt_injection.py` runs the empirical half, with a control, when a key exists. |
| Fuzzing beyond the happy path | OPEN | Input validation is spot-checked, not fuzzed. No schema-driven or property-based testing. |
| Log injection and audit-trail integrity | OPEN | Audit rows exist; nothing prevents forged entries or verifies the trail can't be poisoned. |

## 4. File upload & media

| Risk | Status | Evidence / note |
|---|---|---|
| Malicious image upload | VERIFIED | Genuinely well built: magic-byte check, 5 MB cap, EXIF stripped by re-encode, and a 40 MP decompression-bomb guard in `upload_utils.py`. |
| Oversized document upload | VERIFIED | 25 MB PDFs, 50 MB decks, rejected on declared size before buffering. |
| Document type spoofing | VERIFIED | `validate_document` decides from the bytes; wired into the PDF path and all three knowledge-base uploads, where the extension used to come off the filename and route the AI. 11 tests, plus live proof: an ELF payload named `.pdf` is 415 under both `application/pdf` and `application/octet-stream`, while a genuine PDF is 202. *(`.pptx` already checked its ZIP header — the original note overstated that half.)* |
| Malware in uploaded files | OPEN | No AV or content scanning. Files are stored and served back to other users in the school. |
| Zip-bomb via `.pptx` | VERIFIED | A `.pptx` is a ZIP; the 50 MB upload cap bounds the file, not what it unpacks to. `reject_if_zip_bomb` now reads the archive's central directory (metadata only — nothing decompressed) before `parse_pptx` opens it, and rejects on a 300 MB unpacked total or any entry above 1 MB with a ratio over 120. Falsified against the real parser: a 500 KB file declaring 500 MB is refused in **1.6 ms**, where the unguarded parse grew RSS by ~496 MB first. 6 tests build genuine archives — bomb rejected, ordinary deck and tidy XML pass. |

## 5. Transport & network

| Risk | Status | Evidence / note |
|---|---|---|
| TLS enforcement and HSTS | VERIFIED | Live-checked: HTTP/2 only, `max-age=31536000; includeSubDomains`. |
| Missing security headers | VERIFIED | All four present on success *and* error responses: nosniff, `X-Frame-Options: DENY`, CSP `default-src 'none'`, HSTS. |
| WebSocket authentication | VERIFIED | JWT required, `sub` matched to the path user id, revoked JTIs rejected. 5/5 in `test_websocket_auth.py`. |
| Man-in-the-middle on mobile | STALE | CA-level pinning to Let's Encrypt is implemented and code-reviewed, but the mitmproxy test that would prove it is still an unticked release-QA item. |
| Permissive CORS | VERIFIED | The app runs credentialed CORS (`allow_credentials=True`), where a `*` origin would reflect **any** site back with credentials allowed — so a settings validator refuses to start if the origin list contains `*`, forcing an explicit allowlist. 8 tests (`test_cors_policy.py`, real config loaded past conftest's stub) pin it: bare `*`, whitespaced ` * `, and a wildcard hidden in a comma string are all rejected; comma and JSON strings parse to a list; the shipped default is an explicit allowlist (mindforge.guru present, no wildcard). Falsified: removing the guard fails all three wildcard tests. |
| Pinning bypass on a rooted device | OPEN | No Frida / objection testing. Pinning stops a network attacker, not someone who owns the handset. |

## 6. Mobile & client hardening

| Risk | Status | Evidence / note |
|---|---|---|
| Android backup exfiltration | VERIFIED | `android:allowBackup="false"` set in the manifest. |
| Token at rest on device | VERIFIED | Access + refresh tokens go to `flutter_secure_storage`. Verified on the iOS simulator 2026-08-22: after login, a JWT is grep-absent from the app's entire on-disk container (Documents, Library, Preferences plists) and not readable in plaintext in the keychain DB; a **force-quit + relaunch restores the session**, proving the token is persisted at rest (encrypted Keychain) and read back — not held in memory or written to a plaintext file. Logout-clears-storage is separately pinned by `auth_notifier_test.dart`. Android Keystore uses the same `flutter_secure_storage` backend but was not separately observed. |
| Token at rest in the browser | VERIFIED | App-level contract pinned by **6 tests** in `auth_notifier_test.dart`: login persists the JWT + refresh token to storage, logout calls `deleteAll()` (wipes every `mindforge_*` key), the session restores from storage on reload, stays logged out when storage is empty, and still clears in-memory tokens even if the secure store throws. On web `flutter_secure_storage` maps these to `localStorage`. Live in Chrome 2026-08-22: the logged-out browser held **no tokens and no cookies**. The full populate→clear cycle wasn't re-driven live — the web splash hangs on the unwired FCM-on-web path (a boot quirk, not storage) — but the persist/clear logic is now regression-guarded rather than a one-off May check. |
| Reverse engineering the release binary | STALE | Build commands now carry `--obfuscate --split-debug-info` (`TEST_RECORD.md` §6/§7, 2026-08-19), with the symbol-retention rule Crashlytics needs. STALE not VERIFIED: no obfuscated build has actually been produced or inspected yet. |
| Rooted / jailbroken device | OPEN | **Deliberately not built** (decided 2026-08-19). Defeated by anyone motivated, needs native code on both platforms, and does not address the actual threat here — a student after grades or a test edge would use a second device, which no client hardening touches. Revisit if the threat model changes. |
| Screen capture of student records | STALE | `FLAG_SECURE` via a native MethodChannel, reference-counted so nested secured screens don't unsecure each other; wired into the six fee and grade screens. 5 tests. STALE not VERIFIED: no Android device or emulator has confirmed a screenshot is actually blocked, and iOS has no implementation (blocked on Apple enrolment). Attendance and timetables are deliberately left capturable. |
| Runtime tampering / hooking | OPEN | No anti-debug or integrity checks. A hooked client can call any endpoint the user's token permits. |
| Deep-link and intent hijacking | VERIFIED | Reviewed 2026-08-21. **No inbound-link surface exists to hijack:** Android declares only the `MAIN`/`LAUNCHER` filter — no custom scheme, no `BROWSABLE`, no App Links — and `MainActivity` never reads `intent.data`; iOS declares no `CFBundleURLTypes` and no `open:url`/universal-link handler. `taskAffinity=""` additionally blocks task-affinity hijacking. The real addressable surface is the **web** build, where every go_router path is a URL: the guard redirects logged-out users to login, bounces wrong-role users out of another role's section, and rejects non-numeric path ids — now a pure `resolveRouteRedirect` with **10 unit tests**, falsified by removing the guard and watching them fail. This is a UX guard; the enforced boundary is server-side authz (§2), separately verified. |

## 7. Secrets & configuration

| Risk | Status | Evidence / note |
|---|---|---|
| Weak or defaulted signing key | VERIFIED | `JWT_SECRET` has no default — the app refuses to start without it. |
| Shipping default infrastructure credentials | VERIFIED | Backend refuses to boot under `APP_ENV=production` if Postgres, Redis or MinIO are on built-in defaults. |
| Seeded default admin account | VERIFIED | Removed from `init_db.sql` 2026-08-19 (commit `7e5de32`) — provisioning is now only via the env-gated seed in `main.py` or Owner Console. **Production checked and closed 2026-08-21:** the leftover `admin` row *had* run there and was neutralised (`is_active=false`, `deleted_at` set) via the Railway console — `admin`/`123456` can no longer log in. Not hard-deleted (FK safety); reversible. |
| Firebase client keys restricted | VERIFIED | **Assumption corrected 2026-08-21.** The register long assumed these were never applied; the GCP console shows all three keys carry application restrictions (auto-created by Firebase, Apr 2026) and the specifics were confirmed by inspection: Android = package `com.mindforge.mindforge` + the release SHA-1 from `SECURITY.md`; Web = HTTP referrers incl. `mindforge.guru/*`; iOS = iOS apps. API allowlists broad and stable. Residual: add the Play App-Signing SHA-1 if/when the app ships via Play App Signing. |
| Secrets committed to git history | VERIFIED | gitleaks over all 231 commits: **zero real secrets**. The 8 hits are 3 public-by-design Firebase client keys and 1 deliberately-invalid JWT fixture, allowlisted by exact value in `.gitleaks.toml` and falsified (a new high-entropy key in an allowlisted file is still caught). Green on a real runner, `32176217465`. |
| Secrets in the working tree | VERIFIED | Re-audited 2026-08-24 and a real gap closed: `.gitignore` only covered `.env`, `.env.local`, `.env.*.local`, so a `.env.production` / `.env.staging` (or per-service `backend/.env.production`) holding live prod secrets would **not** have been ignored. Widened to `.env` + `.env.*` with a `!.env.example` negation — every secret variant is now ignored, the template stays tracked, and no real `.env` is committed. Pinned by `test_secrets_gitignore.py` (12 tests) that ask `git check-ignore`/`git ls-files` directly. Falsified: reverting to the narrow pattern fails 5. gitleaks guards what's already committed; this guards what could be committed next. |

## 8. Supply chain

| Risk | Status | Evidence / note |
|---|---|---|
| Vulnerable Python dependencies | VERIFIED | `pip-audit --strict` green on a real CI runner — 20 findings across 5 packages driven to 0, with one documented ignore (`ecdsa`, unreachable under HS256). |
| Vulnerable Dart / Flutter dependencies | VERIFIED | osv-scanner over `pubspec.lock`: **192 packages, 0 issues**. Image pinned by digest; green on a real runner, `32176217465`. |
| Vulnerable base images | VERIFIED | trivy (v0.74.0, pinned by digest) scans the **built** backend image on every push. Baseline 2026-08-20, reproduced identically locally and on a CI runner (`32338143062`): **122 HIGH/CRITICAL — 109 with no upstream fix, 13 fixable**, 8 of those one util-linux CVE counted per sibling package. Reports, does not gate; `--ignore-unfixed --exit-code 1` is the documented one-line change once the 13 are cleared. |
| Static analysis for security defects | VERIFIED | CodeQL on every push and weekly (`codeql.yml`), languages `python` + `actions`. First run 2026-08-20 scanned **137/137 Python files, 43 rules, 0 findings** and **2/2 workflow files, 17 rules, 7 findings**. The pipeline was falsified by its own result rather than a planted bug: the 7 were real, were fixed in `91f37e4`, and the next run reported 0 open / 7 fixed. Dart is unsupported by CodeQL; Swift (7 tracked files) and Kotlin (1) both need a full build and are skipped on purpose. |
| Malicious or typosquatted package | OPEN | No provenance or lockfile-integrity gate. |

## 9. Availability, abuse & cost

| Risk | Status | Evidence / note |
|---|---|---|
| AI generation cost abuse | VERIFIED | Per-user rate limits on test generation and presentation processing. |
| Unthrottled API surface | VERIFIED | 300/min per authenticated user, in-app so it ships with the deployment. `nginx.conf` **did** define a 120 r/m zone, which is why this looked covered — but nginx is compose-only and production runs `start.sh` on :8000 behind Railway's edge, so it never loaded. Verified live: 330 requests → exactly 300×200 then 30×429, health exempt, 429 carries Retry-After and all four security headers. |
| DDoS / volumetric attack | OPEN | No WAF. Whatever the Railway edge provides has never been established or tested. |
| Backup and disaster recovery | STALE | Local rehearsed 2026-08-19. **Production Postgres proven 2026-08-21** (`scripts/backup_railway.sh`: real Railway dump rebuilt into a throwaway PG18, counts matching) with Railway daily volume backups on. **MinIO 2026-08-21:** confirmed on a volume, daily volume backups now scheduled + one taken, and `scripts/backup_minio.sh` gives an independent counted copy. Still STALE, not VERIFIED, on the register's own rule — *a backup nobody has restored is a guess*: the MinIO/volume backups have not been restore-rehearsed. Also note production is a pre-multi-tenancy schema (this branch undeployed), so what restores is the old app. |
| Object-storage data loss | OPEN | A known live failure mode: MinIO losing its objects blanks every avatar and upload. Production needs a volume mounted at `/data`. |
| Push-notification abuse | OPEN | Broadcast and FCM paths have no send-rate ceiling per sender. |

## 10. Privacy & compliance

| Risk | Status | Evidence / note |
|---|---|---|
| Privacy policy drafted | VERIFIED | `PRIVACY_POLICY.md` exists and discloses that teacher uploads may contain student names. |
| **Children's data regulation** | **OPEN** | This app holds records on minors. No COPPA, GDPR-K or local equivalent assessment has been done, and no verifiable parental-consent mechanism exists. For a school product this is the largest compliance exposure in this register. |
| Undisclosed AI recipient | OPEN | Claude became the primary generation provider on 2026-06-08 and reads uploaded PDFs natively. The policy's sharing table names Gemini and Groq — not Anthropic. |
| PII leaking into AI prompts | OPEN | The prompt sweep that found this clean predates the entire Claude pipeline. |
| Policy not published | OPEN | Not hosted at a public URL, not reviewed by counsel, and `AppConstants.privacyPolicyUrl` is still empty. Blocks store submission. |
| Data retention | OPEN | No defined retention or purge policy. Soft-deleted rows persist indefinitely. |
| Account deletion completeness | VERIFIED | The open question — *is owner self-delete blocked?* — was a real gap: `delete_my_account` blocked admin and student but let **owner fall through and soft-delete itself**, orphaning the platform. Fixed: the role policy is now `self_delete_block_reason` in `app.core.account_state` (admin/student/owner blocked; parent/teacher allowed, parent cascades to its one child), pinned by 14 tests and falsified — reverting the owner block fails the owner test. Deletion side-effects (soft-delete flags, access+refresh JTI revocation, FCM clear, audit row, parent→child cascade) remain verified by reading; an end-to-end deletion test is the remaining depth. |
| PII reaching error-reporting vendors | VERIFIED | Sentry runs `send_default_pii=False` and a `before_send` scrubber, now extracted to `app.core.sentry_scrub` and pinned by **8 tests**. It redacts credentials (mpin, tokens, authorization, cookie) **and** a minor's direct identifiers (phone, parent_phone, email) from request data/headers/cookies — hardened here, since the app holds children's records and those fields could ride a request body into a 500. Case-insensitive, recurses nested bodies and lists, and never raises (a throwing before_send would drop the event). Falsified: dropping the PII keys fails 4, removing recursion fails 2. |
## 11. AI pipeline

| Risk | Status | Evidence / note |
|---|---|---|
| Provider fallback reliability | STALE | Claude → Gemini → Groq. Understood operationally, but no test asserts the chain degrades correctly when the primary fails. |
| Trusting generated content | VERIFIED | Auto-quizzes are created unpublished and reach students only when a teacher publishes — the same gate manual tests already passed through, which auto-quizzes were setting `is_published=True` on themselves to skip. The 48h attempt window now starts at publish, so review time is not taken out of the students'. Verified live: a student cannot see the quiz before publish, can after, and the window is 48h from approval. |
| Cross-tenant contamination in AI context | OPEN | Nothing verifies that one school's uploaded material can't surface in another school's generated output. |
| Uploaded documents retained by third parties | OPEN | Files sent through the Anthropic Files API — retention and deletion on the vendor side is undocumented here. |

## 12. Detection & response

| Risk | Status | Evidence / note |
|---|---|---|
| Audit logging | VERIFIED | Coverage mapped and pinned. Verified **live** 2026-08-24: an admin deactivate→reactivate on the simulator produced `deactivate_user` + `activate_user` rows, each correctly attributed (actor `demo_admin`, target, before/after details, timestamp, school-scoped). Coverage across the routers is **15+ actions** — user lifecycle (approve/edit/activate/deactivate/delete-pending/revoke/self-delete + child cascade), teacher bio/photo, fee record/update/delete, feedback — now guarded by `test_audit_coverage.py` (3 tests): the security-relevant user-lifecycle actions must each be emitted from an `_audit`/`AuditLog` call, with a floor so coverage can't silently shrink. Falsified: deleting an audit line drops that action and fails. Residual: the trail is append-only but not cryptographically tamper-evident (see 'Log injection'), and no periodic human review process exists. |
| Error visibility | STALE | Sentry on the backend, Crashlytics on the client. Both wired; neither verified end-to-end recently. |
| Security alerting | STALE | Credential-spray detection (distinct usernames per IP over 15 min, ERROR at 8). **Pipeline now pinned by `test_alerting.py` (4 tests):** an ERROR log becomes a Sentry event, a warning stays a breadcrumb (so the channel isn't drowned), and the spray alert ships only the IP + count — never the targeted accounts (falsified: leaking a username, or making warnings alert, each fails). STALE for two reasons the code can't supply: only this one pattern is watched (impossible travel, mass data access are not), and **no Sentry notification route is configured** — so the alert reaches Sentry but pages no human. The route is a user task; see [[project_user_owned_security_todos]]. |
| Incident response | OPEN | No runbook for a breach: no containment steps, no notification path, no mass token-revocation procedure. |
| Responsible disclosure | OPEN | No `security.txt`, no contact route for someone who finds a flaw. |

## 13. Build & release pipeline

| Risk | Status | Evidence / note |
|---|---|---|
| Android release signing | VERIFIED | Signed with a release keystore; `key.properties` gitignored. |
| Test suite writing to production | VERIFIED | `tests/test_api.py` registers/approves/revokes users on whatever host it targets, defaults to production, and once wrote to the live DB by accident (run 30118897312). The guard — refuse a production target unless `MF_API_ALLOW_PROD=1`, exact-match only — is now a pure `tests/prod_guard.py` with **24 tests** (`test_prod_guard.py`, in the CI-run suite): every prod URL form blocked without the override and allowed only with the exact `1`, local/staging never blocked. Falsified: disabling the guard or weakening the host check fails the tests. Confirmed behaviourally too — default target skips, `MF_API_BASE_URL=http://127.0.0.1:8000` collects all 107. (The suite itself still needs a multi-tenancy rework to *pass* — a quality TODO, not a prod-write risk.) |
| Code merging without CI | VERIFIED | Push trigger widened to `"**"`. Proven on run `32176217465` — the first push-triggered CI this branch has ever had, all 5 jobs green, `api-integration` correctly skipped. It caught a real break on its first attempt (see log). |
| Toolchain drift | VERIFIED | CI and local both pin Flutter 3.44.0 / Dart 3.12.0 (stable), aligned 2026-08-21. Analyze (0 warnings), 87 unit and 38 widget tests were run on 3.44.0 locally — the same toolchain CI now uses — so "green on CI" and "works locally" are one claim. The pin carries a comment to bump both together. |
| iOS release verification | OPEN | Blocked on Apple Developer Program enrolment. No IPA has ever been built or tested. |
| Independent penetration test | OPEN | Every result in this register comes from self-testing. No external assessment, no DAST, no bug bounty. |

---

## Verification log

### 2026-08-18 — Wave 0: re-run the existing probe suites

Both suites run against the **local** stack (`MF_SEC_BASE_URL=http://127.0.0.1:8000`),
with school-1 fixtures. Pinning matters: `security_test.py` defaults to production and
fires rate-limit and injection probes.

```bash
# 21 PASS / 1 FAIL / 1 WARN
MF_SEC_BASE_URL=http://127.0.0.1:8000 MF_SEC_ADMIN_USER=demo_admin \
ADMIN_MPIN=847362 MF_SEC_SCHOOL_ID=1 python3 tests/security_test.py

# 49 PASS / 0 FAIL / 0 WARN
MF_SEC_BASE_URL=http://127.0.0.1:8000 MF_SEC_SCHOOL_ID=1 \
MF_SEC_ADMIN_USER=demo_admin   MF_SEC_ADMIN_MPIN=847362   MF_SEC_ADMIN_ID=280 \
MF_SEC_TEACHER_USER=chinmay_sir MF_SEC_TEACHER_MPIN=847362 MF_SEC_TEACHER_ID=2 \
MF_SEC_STUDENT_USER=nitin       MF_SEC_STUDENT_MPIN=123456 MF_SEC_STUDENT_ID=3 \
MF_SEC_PARENT_USER=nitin_dad    MF_SEC_PARENT_MPIN=123456  MF_SEC_PARENT_ID=4 \
python3 tests/security_test_extended.py
```

`security_test.py`'s one FAIL (HTTPS enforced) and one WARN (uvicorn `server` banner)
are local-stack artifacts — there is no TLS on localhost, and in production the Railway
edge overrides the banner. This matches the 2026-05-19 and 2026-07-25 baselines exactly,
so the surface has not regressed.

**Net effect on this register: one row moved.** Refresh-token rotation and JTI
revocation went STALE → VERIFIED. Everything else the suites cover was already VERIFIED
and was simply re-confirmed — valuable as regression evidence, but it does not change
posture.

**The finding worth keeping:** the remaining STALE items are stale *precisely because no
existing test covers them*. Account lockout, token lifetime, deactivated-user login,
MPIN blocklist, CORS, token-at-rest, Sentry scrubbing, account deletion — none is
touched by either suite. Re-running what exists cannot clear them; each needs a test
written first. Treat "run the suites" as a regression check, not as a way to pay down
the STALE column.

### 2026-08-19 — Wave 1: config-level hardening

Five rows moved: three to VERIFIED, two to STALE.

| Change | Result |
|---|---|
| Removed the hardcoded admin seed from `init_db.sql` (`7e5de32`) | OPEN → VERIFIED |
| gitleaks over 231 commits | **0 real secrets**; OPEN → VERIFIED |
| osv-scanner over `pubspec.lock` | **192 packages, 0 issues**; OPEN → VERIFIED |
| `--obfuscate --split-debug-info` in documented builds | OPEN → STALE |
| CI push trigger widened to `"**"` | OPEN → STALE |

Both scanners are wired into `ci.yml` as jobs, with images **pinned by digest** —
a scanner whose rules float between runs makes a green build meaningless.

**On the gitleaks allowlist.** All 8 baseline findings are benign: three Firebase
*client* keys (public by design, and three of the hits are in `SECURITY.md`, which
documents them deliberately) plus one invalid JWT fixture whose signature is the
literal `fakesignature123`. `.gitleaks.toml` allowlists them **by exact value, not by
path** — allowing `firebase_options.dart` wholesale would also allow the next
credential dropped into it. Falsified: a new high-entropy key placed in an
already-allowlisted file is still reported.

Two earlier falsification attempts produced false confidence and are worth recording,
because both failure modes are easy to repeat. A planted key of the wrong length
(38 chars; the rule needs `AIza` + exactly 35) was silently ignored, as was one built
from 33 identical characters, which falls below the rule's entropy floor. In both cases
gitleaks reported "no leaks found" and looked like a passing test. A scanner that
cannot be made to fail has not been shown to work.

**Why two rows are STALE, not VERIFIED.** Obfuscation flags are documented but no
obfuscated build has been produced; the CI trigger is widened but nothing has been
pushed, so no runner has executed it or the new jobs. Writing the config is not the
same as watching it run — precisely the lesson in §10 item 17 of `TEST_RECORD.md`.

### 2026-08-19 — first push-triggered CI run, and what it caught

Run `32175724699` (first ever on push for this branch) **failed**, and the failure
was mine. `2bbb630` staged only `realtime_sync.dart`, on the reasoning that the
branch's other uncommitted work shouldn't be swept in. But that file imports
`session_reset.dart`, which was untracked — so `HEAD` did not analyze on a clean
checkout: one unresolved URI and two undefined-method errors.

It passed locally throughout, because the file was sitting on my disk. Only a clean
checkout could surface it, and the widened trigger produced one within minutes of
being merged. Fixed in `cbddcba`; re-verified in a throwaway clone before pushing —
0 analyze errors, 82 unit and 27 widget tests green — then confirmed on run
`32176217465`, all 5 jobs green.

Two things worth carrying forward. Staging narrowly is still right; the missing step
was checking that the file being staged didn't depend on one that wasn't. And "passes
locally" is not a claim about the repository — it is a claim about a working directory,
which is a different thing and was wrong here.

### 2026-08-19 — Wave 2 (partial): upload validation and throttling

| Change | Result |
|---|---|
| `validate_document` on 4 unchecked upload sites | OPEN → VERIFIED |
| 300/min in-app throttle | OPEN → VERIFIED |

**A correction to this register.** The upload row claimed documents were gated on
`content_type` alone. `.pptx` already checked its ZIP header — the real gaps were
the PDF path, and `database_router.py`, which checked nothing and took the
extension off the *filename* to decide how the AI parsed the file. That is worse
than the row described, and in a different place.

**Why "unthrottled" was both wrong and right.** `nginx.conf` defines a 120 r/m
API zone, so the repo reads as throttled. nginx is a docker-compose service;
production runs `backend/Dockerfile`'s `start.sh` on :8000 behind Railway's edge,
confirmed by the live `server: railway-hikari`. The protection was real locally
and absent in production — the worst shape for a control, because reading the
config tells you it is handled.

**A bug this introduced and the reason the suite missed it.** Registering the
throttle last makes it outermost, so its 429 short-circuits above
`SecurityHeadersMiddleware` and ships bare — silently breaking the "headers on
error responses too" property that §5 records as VERIFIED. Registering it first
makes it innermost and the 429 inherits the headers. Nothing in the suite
assembles the middleware stack, so this was only visible by curling a throttled
response. Worth remembering when adding any middleware that can short-circuit.

`FLAG_SECURE` landed after that call was made: fees and grades only, native
MethodChannel rather than a pub package, since this app holds minors' data and
dependency scanning was just added to shrink that surface. It stays STALE until
a real device confirms a screenshot is blocked.

Wiring it surfaced the `2bbb630` trap a second time. All six screens carried
uncommitted `SchoolLogo` work and imported `school_logo.dart`, which was
untracked — so committing them alone would have failed a clean checkout on an
unresolved import, exactly as before. Caught this time by checking the
dependency closure *before* committing rather than by watching CI go red.

### 2026-08-19 — Wave 3 (partial): backup tooling, rehearsed

Backup and disaster recovery moves OPEN → STALE. Not VERIFIED, because the half
that matters most is still uncovered: these scripts drive `docker exec` against
the compose stack, and production is Railway-managed Postgres plus a MinIO
volume. Local backups being provably restorable says nothing about production.

Started here rather than with MFA on consequence: a breach is recoverable, and
deleted student records are not. This register already carries object-store data
loss as a failure mode that **has happened** — avatars and uploads blanked while
the media proxy returned clean 404s.

`restore_rehearsal.sh` is the piece worth having. It restores into a throwaway
database, compares row counts against a manifest written at backup time, and
drops the scratch copy on every path including failure. The live database is
never touched and the script refuses to run if the scratch name ever resolves to
it. The failure modes it exists for — a truncated dump, a permissions error that
skipped a table, a version mismatch — all produce a plausible-looking file that
only fails when you need it.

Falsified in both directions, per the gitleaks lesson: a corrupted dump is
caught at the checksum, and a manifest claiming 99 users against a 61-user dump
fails the comparison. Both exit 1.

One thing this turned up: `backups/` was not gitignored. A dump holds every
student record in plaintext, so the tooling as first written created a
convenient way to commit the entire database. Fixed, and the ignore rule was
verified rather than assumed.

### 2026-08-19 — Wave 4: business-logic and authorization edges

Went after the risks specific to a school app rather than the remaining Wave 3
items. A student changing their own grade, or a parent reaching another family's
child, matter more here than root detection.

**One real vulnerability, found and fixed.** Account enumeration by timing.
`login()` read `if not user or not verify_mpin(...)`; Python short-circuits, so
an unknown username never reached bcrypt — 3.9 ms against 238.7 ms for a real
one. Identical bodies, 61x tell. That matters more than usual here: usernames
are school-issued and guessable, so confirming which exist turns guesswork into
a target list of children's accounts. Now 1.00x.

**Two properties confirmed sound.** Parent → child access has no id in the
request to tamper with, and the score never leaves the server. Both were correct
by construction; neither had a test, so both were one refactor from breaking
silently.

Two measurement mistakes worth recording, because each produced a confident
wrong answer. Timing samples taken in a tight loop tripped the login limiter, so
most were instant 429s that never reached the password check — making the two
cases look identical and the vulnerability look absent. And `/child/timetable`
422s without a `date`, which would have made that authorization case pass
without testing anything. Both were caught by checking status codes rather than
trusting the aggregate.

### 2026-08-19 — Wave 3 continued: spray detection

Two gaps that compound. The login limiter is keyed `{ip}:{username}` at 10/min,
which stops someone grinding one account and does nothing about one password
tried once against many — spraying 200 usernames is 200 requests each at a tenth
of its own budget. And failed logins log at WARNING, which Sentry's logging
integration records as a *breadcrumb*, never an alert, so a spray in progress was
invisible unless something unrelated errored in the same request.

Counts distinct usernames per IP, which is what separates spraying from
mistyping — the latter re-adds the same set member and never grows it. Crosses
at 8, logs at ERROR so it becomes a Sentry event.

The summary line carries an IP and a count and nothing else. Shipping the list of
targeted accounts to a third party would hand over exactly what the attacker was
fishing for.

STALE, not VERIFIED: one pattern is covered. Impossible travel and mass data
access are still unwatched, and no alert *route* exists — Sentry will receive the
event, but nothing has been configured to tell a human about it.

### 2026-08-19 — Wave 3 completed: MFA, and a decision not to build

**MFA for admin and owner.** A compromised student MPIN costs one student's
records; an admin's costs a school's, the owner's costs every school. Scoped
there deliberately — TOTP for parents and students on shared family devices
would cause more lockouts than it prevents compromises.

TOTP is implemented from RFC 6238 rather than added as a dependency, and checked
against all six of the RFC's own vectors. Wave 1 was spent shrinking the
dependency surface of an app holding minors' data; forty lines of stdlib
implementing a fully specified construction with published vectors is the better
side of that trade.

Two ordering decisions carry the security: the second factor is checked *after*
the MPIN, so it cannot become the enumeration oracle the constant-time check
exists to prevent; and enrolment is two steps, so an abandoned setup leaves the
account exactly as it was.

**Two bugs found by running it, neither reachable from the suites.**

The login fields were patched in against a non-unique anchor and landed on
`UserRegisterRequest` — login 500'd, and `mfa_code` briefly became accepted input
on the public signup route.

Then Dio's interceptor treated *any* 401 on `/auth/login` as terminal — clearing
storage and firing `onUnauthorized`. An `mfa_required` challenge went down that
path, so the app tore its own session down mid-sign-in and the prompt never
appeared. The backend was correct throughout; only driving the real screen
against the real server showed it.

And a process note worth keeping: the first browser attempt proved nothing,
because `flutter run` does not recompile on save and the page was serving a
bundle built before any of the changes.

**Root detection: deliberately not built.** Easily defeated, native work on both
platforms, and orthogonal to the real threat — a student wanting grades early
would use a second device. Recorded as a decision rather than left looking like
an oversight.

### 2026-08-19 — Prompt injection on the chapter-PDF pipeline

The path is: teacher uploads a PDF → model writes slides → a period log turns
those slides into an auto-quiz → broadcast to students. **No human reads
anything in between.** So text inside an uploaded document reaches children
unreviewed.

The realistic attack is not a malicious teacher but an ordinary one downloading
a chapter PDF from the web that carries instructions in white 5pt text —
invisible on the page, plainly readable in the text layer the model receives.
Built one to confirm: it does not render, and it does come back from
`get_text()`.

All three prompts reading uploaded files had **no defence whatsoever**. They now
frame the document as data and say directives inside it must be ignored,
including the slide-fill stage — whose input is model output derived from the
untrusted file, so an injection surviving stage one would otherwise get a second
attempt.

**Recorded as STALE, and the distinction matters.** The tests prove the wording
exists. They cannot prove a model obeys it, and prompt-level defence against
injection is known to be imperfect. Nothing was reachable to test against: no
Claude key locally, and Gemini has exceeded its monthly spending cap — which
also means AI generation is currently down on this machine.

**The stronger fix is a product decision, not a prompt.** If a person reviewed
generated quizzes before they reached students, this risk would mostly
disappear regardless of what any prompt says. Worth considering.

### 2026-08-19 — A human back in the loop on AI-generated tests

The strongest answer to prompt injection turned out not to be a better prompt.
It was noticing that the gate already existed and auto-quizzes were walking
around it.

Every test carries `is_published`, students only ever see published ones
(filtered in five places), and teachers have a Publish button. Manual tests
respect that. Auto-quizzes set `is_published=True` on themselves at generation
and broadcast straight to the grade — so the one path with no human in it was
also the one path that skipped the human gate.

They are now created unpublished, and the existing Publish button is the review.
No new concept, no migration, no UI work: the teacher's list already showed
unpublished tests and already had the button.

**The trap worth recording.** `expires_at` was set at generation. Holding the
quiz for review without changing that would have taken the teacher's thinking
time out of the students' 48 hours — approve a day late and they get 24, approve
two days late and they get a quiz that is already dead. The window now starts at
publish, and cannot be extended by unpublish/republish.

Two mistakes made along the way, both caught before they shipped. The helper was
first put in the router, which made its test import a router and reorder module
stubs for everything running afterwards — breaking `test_realtime_fanout` exactly
as `TEST_RECORD` §10 item 4 warns. It now lives in `app/core/quiz_window.py`,
which has no heavy imports. And the broadcast helper, when moved into
`realtime_service`, referenced `asyncio` and `notification_service` without
importing either — a crash that would have fired on the first real publish and
that no unit test would have reached.

---

### 2026-08-20 — Scanners that read the code and the image

Everything CI checked until today was *around* the software: dependency
manifests, commit history. Nothing read the application source, and nothing
looked inside the container the backend actually runs in. Every finding in this
register up to this point came from a person deciding to go and look — which
finds things exactly once, on the day someone looks.

**CodeQL** (`.github/workflows/codeql.yml`), free only because this repository
is public — a fact this register had never recorded, and one that changes the
threat model: nothing here is protected by being hard to find, and any secret
ever committed is exposed permanently.

Languages `python` and `actions`. The second is not box-ticking. A workflow
that interpolates untrusted input into a `run:` block executes
attacker-controlled shell holding the repository token, and this repo has
several multi-line `run:` blocks.

Its own workflow, not another job in `ci.yml`, because it needs
`security-events: write` and nothing else in CI does.

First run:

| Language | Files scanned | Rules | Findings |
|---|---|---|---|
| python | 137 / 137 | 43 | 0 |
| actions | 2 / 2 | 17 | **7** |

The Python zero is a real zero, not a vacuous pass: the log records full
extraction coverage and the interpreted query list includes SSRF, path
injection, LDAP injection, XXE, reflected XSS and weak-crypto checks.

**The 7 findings were the falsification.** No planted bug was needed — the
scanner found something real on its first run: every job in `ci.yml` inherited
the repository's default `GITHUB_TOKEN` permissions
(`actions/missing-workflow-permissions`, one alert per job). The default is
`read` today, so nothing was exposed; but it is a checkbox in Settings, and
flipping it would silently hand a write-scoped token to seven jobs, several of
which run third-party container images over the repository contents. The same
shape as the branch allowlist that failed open for weeks. Fixed in `91f37e4`
with a workflow-level `permissions: contents: read`; the following run reported
**0 open, 7 fixed**, which closes the loop in both directions — the pipeline
demonstrably produces findings *and* demonstrably clears them.

**trivy** (`ci.yml`, job `container-scan`), v0.74.0 pinned by digest to match
gitleaks and osv-scanner. `pip-audit` reads `requirements.txt`, which covers
what we chose to install and nothing underneath it; the image is
`python:3.11-slim` plus tesseract, poppler, gcc and curl, and nothing had ever
looked at that layer.

Scanned from a `docker save` tarball via `--input` rather than by mounting
`/var/run/docker.sock`, which would hand the scanner control of the host
daemon — a lot of trust for a tool whose job is parsing untrusted package
metadata.

Baseline, identical locally and on runner `32338143062`:

- **122 HIGH/CRITICAL** (117 OS, 5 Python)
- **109 have no upstream fix** — Debian has not shipped one, so they are not
  actionable here
- **13 are fixable today**: 8 are a single util-linux CVE (`CVE-2026-53615`)
  counted once per sibling package, plus `setuptools`, `wheel`,
  `jaraco.context` and `msgpack`
- `ecdsa` `CVE-2024-23342` reappears here; it is the advisory already assessed
  and ignored in the pip-audit job — HS256 only, no ECDSA operation is ever
  performed

**Neither scanner gates.** `--exit-code 0` on trivy and no failure threshold on
CodeQL are deliberate and temporary. The first run of a new scanner returns a
backlog, and a red build nobody can fix is how people learn to ignore red
builds. Each file records the exact change that turns it into a gate.

Both workflows lint clean under `actionlint` before push.

**Caveat worth keeping visible.** On a public repo the alert *list* still needs
write access to read, so unfixed findings are not published. But code scanning
annotations **on a pull request** are visible to anyone. A PR carrying a live
finding advertises it for as long as it is open.

---

## What to fix first

Ordered by consequence, not by how interesting the work is. Items 5–8 of the
original list (rate limiting, upload validation, secret scanning, CI triggers)
were completed on 2026-08-19 and have been removed rather than left looking
outstanding.

**Yours — none of these are coding tasks**

1. **Confirm no `admin` row survives in a deployed database.** Two minutes, and
   still the highest-consequence item here. The seed is gone from `init_db.sql`
   (`7e5de32`), but removing it does not clean an environment that already ran
   the old file. Railway's managed Postgres would not have executed it —
   confirm rather than assume, then this closes fully.
2. **Decide the children's-data position.** COPPA / GDPR-K governs a product
   holding minors' records. Legal weight rather than hardening, and it gates
   store submission. A lawyer question, not an engineering one.
3. **Publish the privacy policy, and add Anthropic to it.** Host it, populate
   `privacyPolicyUrl`, disclose Claude as a recipient of uploaded documents.
   Three small tasks that together unblock store submission.
4. **Restrict the Firebase keys in the GCP console.** `SECURITY.md` already
   lists each key and the restriction it needs. Console clicks, no code.
5. **Confirm production backups actually restore.** The tooling is rehearsed
   locally; production — Railway Postgres plus the MinIO volume — is untested.
   `docs/backup-runbook.md` says what is needed.

**Mine, if you want them**

6. **Scan the MFA QR with a real authenticator app.** The enrolment screen
   landed 2026-08-19, so an admin can now switch two-factor on from the app.
   What remains is a phone: every code in testing was produced by the same
   implementation that verifies it, which proves the maths and not the
   interoperability. One scan closes this row.
7. **Produce one obfuscated release build and check it.** The flags are in the
   documented commands but have never been run. Confirm the symbol files are
   archived and that a forced crash still reports readably — get this wrong and
   crash reports from that build are permanently unreadable.
8. **Run `scripts/probe_prompt_injection.py` once an AI key works.** The
   prompts are hardened and a teacher now approves every generated quiz, so the
   dangerous half is closed. This is the outstanding *measurement* — whether the
   prompt wording actually holds — and it cannot run while Gemini is over its
   spending cap and no Claude key is set locally.

9. **Clear the 13 fixable CVEs in the backend image, then make trivy a gate.**
   The scan added 2026-08-20 found 122 HIGH/CRITICAL, of which 109 have no
   upstream fix and 13 do. Eight of the thirteen are one util-linux CVE
   counted once per sibling package, so an `apt-get upgrade` in the Dockerfile
   likely takes most of it; the rest are `setuptools`, `wheel`,
   `jaraco.context` and `msgpack`. Once the actionable list is empty, switch
   the job to `--ignore-unfixed --exit-code 1` so it blocks rather than
   reports — the one-line change is documented in `ci.yml`.

---

## A note on threat priorities

Popular security content concentrates on the client-side spectacle — root detection,
obfuscation, pinning bypass. Those are real, and several are genuinely open above.
But the risks that actually sink a product like this one are duller: a default
credential left in a seed script, an unpublished privacy policy, a backup nobody has
ever restored. The ordering above reflects consequence rather than visibility.

---

## Maintaining this file

Same discipline as `TEST_RECORD.md`:

1. When you re-check an item, update its status **and** the evidence cell in the same edit.
2. If you didn't re-check it, leave it — do not promote STALE to VERIFIED on the strength
   of the code still looking right.
3. When you close an OPEN item, move it to VERIFIED and cite the test or commit that
   closed it. If the fix has no test, it is STALE, not VERIFIED.
4. Re-run the counts in "Posture at a glance" after any status change.
5. Re-publish the rendered version so the two do not drift:
   `docs/security-risk-register.html` → the artifact URL at the top of this file.
