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
| Verified | **27** |
| Stale | **18** |
| Open | **45** |
| **Total tracked** | **90** across 13 domains |

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
| Account lockout + lockout-DoS guard | STALE | 15-min lockout with a guard against deliberate lockout of another user. Code present; not re-verified since May. |
| Refresh-token rotation and JTI revocation | STALE | Rotate-on-use with old JTI blacklisted in Redis. Passed the extended probe in May; auth layer has changed since. |
| Token lifetime and expiry handling | STALE | 60-min access, 30-day refresh, Dio auto-refresh interceptor. Not re-confirmed. |
| Deactivated, pending or deleted users signing in | STALE | Blocked in `auth.py`; last actually exercised 2026-05-19. |
| Weak / guessable MPIN | STALE | Blocklist added 2026-07-07 at set and change time. Never manually re-tested. |
| Multi-factor authentication | OPEN | Not implemented. A 6-digit PIN is the only factor for every role, including admins and the platform owner. |
| Account enumeration | OPEN | Never probed whether a wrong username and a wrong MPIN are distinguishable by response body or timing. |
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
| Unauthenticated media proxy | STALE | Bucket allowlist verified, but `/api/media/{bucket}/{key}` stays open by design and leans entirely on object keys being unguessable. Never adversarially tested. |
| Business-logic abuse | OPEN | No tests for a student re-taking a locked test, editing submitted answers, tampering with their own grade, or a teacher backdating attendance. |
| Parent–child link tampering | OPEN | Nothing verifies a parent cannot bind themselves to another family's student. |

## 3. Injection & input handling

| Risk | Status | Evidence / note |
|---|---|---|
| SQL injection | VERIFIED | Probed live; SQLAlchemy throughout, and a static sweep confirmed no f-string SQL. |
| Command injection / unsafe deserialization | VERIFIED | Static sweep clean: no `eval`, `exec`, `os.system`, `shell=True`, `pickle.loads` or `yaml.load`. |
| Path traversal | VERIFIED | Covered in `security_test_extended.py`. |
| Cross-site scripting (web build) | STALE | CSP meta tag on the Flutter web entry, and canvas rendering limits DOM surface. Never actively probed. |
| Prompt injection through uploaded documents | OPEN | Teacher PDFs go straight to Claude and the output becomes tests and quizzes students sit. A crafted document steering generation has never been tested. |
| Fuzzing beyond the happy path | OPEN | Input validation is spot-checked, not fuzzed. No schema-driven or property-based testing. |
| Log injection and audit-trail integrity | OPEN | Audit rows exist; nothing prevents forged entries or verifies the trail can't be poisoned. |

## 4. File upload & media

| Risk | Status | Evidence / note |
|---|---|---|
| Malicious image upload | VERIFIED | Genuinely well built: magic-byte check, 5 MB cap, EXIF stripped by re-encode, and a 40 MP decompression-bomb guard in `upload_utils.py`. |
| Oversized document upload | VERIFIED | 25 MB PDFs, 50 MB decks, rejected on declared size before buffering. |
| PDF / PPTX type spoofing | OPEN | Unlike images, documents are gated on the `content_type` header only — which the client sets. No magic-byte or structural check. *(Gap found 2026-08-18.)* |
| Malware in uploaded files | OPEN | No AV or content scanning. Files are stored and served back to other users in the school. |
| Zip-bomb via `.pptx` | OPEN | A `.pptx` is a zip archive; expansion is unbounded at parse time. |

## 5. Transport & network

| Risk | Status | Evidence / note |
|---|---|---|
| TLS enforcement and HSTS | VERIFIED | Live-checked: HTTP/2 only, `max-age=31536000; includeSubDomains`. |
| Missing security headers | VERIFIED | All four present on success *and* error responses: nosniff, `X-Frame-Options: DENY`, CSP `default-src 'none'`, HSTS. |
| WebSocket authentication | VERIFIED | JWT required, `sub` matched to the path user id, revoked JTIs rejected. 5/5 in `test_websocket_auth.py`. |
| Man-in-the-middle on mobile | STALE | CA-level pinning to Let's Encrypt is implemented and code-reviewed, but the mitmproxy test that would prove it is still an unticked release-QA item. |
| Permissive CORS | STALE | Wildcard origin removed 2026-06-23; not re-verified since. |
| Pinning bypass on a rooted device | OPEN | No Frida / objection testing. Pinning stops a network attacker, not someone who owns the handset. |

## 6. Mobile & client hardening

| Risk | Status | Evidence / note |
|---|---|---|
| Android backup exfiltration | VERIFIED | `android:allowBackup="false"` set in the manifest. |
| Token at rest on device | STALE | Refresh tokens go to `flutter_secure_storage` (Keychain / Keystore). Not re-verified. |
| Token at rest in the browser | STALE | Logout clears `mindforge_*` localStorage keys — confirmed 2026-05-19, not since. |
| Reverse engineering the release binary | OPEN | Builds run without `--obfuscate --split-debug-info`. Dart symbol names, API routes and logic are readable from the APK. *(Gap found 2026-08-18.)* |
| Rooted / jailbroken device | OPEN | No root, jailbreak or Play Integrity detection anywhere in the app. |
| Screen capture of student records | OPEN | No `FLAG_SECURE` or iOS equivalent on screens showing grades, fees or attendance. |
| Runtime tampering / hooking | OPEN | No anti-debug or integrity checks. A hooked client can call any endpoint the user's token permits. |
| Deep-link and intent hijacking | OPEN | Exported activities and URL schemes have never been reviewed. |

## 7. Secrets & configuration

| Risk | Status | Evidence / note |
|---|---|---|
| Weak or defaulted signing key | VERIFIED | `JWT_SECRET` has no default — the app refuses to start without it. |
| Shipping default infrastructure credentials | VERIFIED | Backend refuses to boot under `APP_ENV=production` if Postgres, Redis or MinIO are on built-in defaults. |
| **Seeded default admin account** | **OPEN** | `init_db.sql` seeds a live `admin` / `123456` backfilled into school 1. Confirmed logging in on local; **status on the Railway production database is unverified.** Highest-severity open item in this register. |
| Firebase client keys unrestricted | OPEN | Documented in `SECURITY.md` with the exact restriction each key needs — never applied in the GCP console. Defence-in-depth; worst case is quota abuse. |
| Secrets committed to git history | OPEN | No `gitleaks` or `trufflehog` scan has ever run over the repo or its history. |
| Secrets in the working tree | STALE | `.env` and `.env.local` are gitignored; last actually audited in May. |

## 8. Supply chain

| Risk | Status | Evidence / note |
|---|---|---|
| Vulnerable Python dependencies | VERIFIED | `pip-audit --strict` green on a real CI runner — 20 findings across 5 packages driven to 0, with one documented ignore (`ecdsa`, unreachable under HS256). |
| Vulnerable Dart / Flutter dependencies | OPEN | No audit equivalent runs against `pubspec.lock`. Only Python is scanned. |
| Vulnerable base images | OPEN | No container scanning (`trivy`, `grype`) on the backend image. |
| Static analysis for security defects | OPEN | No SAST in CI — no CodeQL, no Semgrep. `flutter analyze` is a linter, not a security tool. |
| Malicious or typosquatted package | OPEN | No provenance or lockfile-integrity gate. |

## 9. Availability, abuse & cost

| Risk | Status | Evidence / note |
|---|---|---|
| AI generation cost abuse | VERIFIED | Per-user rate limits on test generation and presentation processing. |
| Unthrottled API surface | OPEN | Rate limiting exists on 4 routers only — auth, feedback, presentations, teacher AI. Every other endpoint is uncapped. *(Gap found 2026-08-18.)* |
| DDoS / volumetric attack | OPEN | No WAF. Whatever the Railway edge provides has never been established or tested. |
| Backup and disaster recovery | OPEN | No documented backup schedule, and no restore has ever been rehearsed. |
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
| Account deletion completeness | STALE | Soft delete, JTI revocation, FCM clear and audit row — all verified by reading in May, before the owner role existed. Whether owner self-delete is blocked is an open question. |
| PII reaching error-reporting vendors | STALE | Sentry runs `send_default_pii=False` plus a key scrubber. Not re-confirmed. |

## 11. AI pipeline

| Risk | Status | Evidence / note |
|---|---|---|
| Provider fallback reliability | STALE | Claude → Gemini → Groq. Understood operationally, but no test asserts the chain degrades correctly when the primary fails. |
| Trusting generated content | OPEN | AI-generated questions and answer keys become graded material with no human-approval gate in the flow. |
| Cross-tenant contamination in AI context | OPEN | Nothing verifies that one school's uploaded material can't surface in another school's generated output. |
| Uploaded documents retained by third parties | OPEN | Files sent through the Anthropic Files API — retention and deletion on the vendor side is undocumented here. |

## 12. Detection & response

| Risk | Status | Evidence / note |
|---|---|---|
| Audit logging | STALE | An `AuditLog` table exists and survives its author. No review process, and coverage across sensitive actions is unmapped. |
| Error visibility | STALE | Sentry on the backend, Crashlytics on the client. Both wired; neither verified end-to-end recently. |
| Security alerting | OPEN | Failed logins are logged as warnings but nothing alerts on a spike, an impossible-travel pattern, or mass data access. |
| Incident response | OPEN | No runbook for a breach: no containment steps, no notification path, no mass token-revocation procedure. |
| Responsible disclosure | OPEN | No `security.txt`, no contact route for someone who finds a flaw. |

## 13. Build & release pipeline

| Risk | Status | Evidence / note |
|---|---|---|
| Android release signing | VERIFIED | Signed with a release keystore; `key.properties` gitignored. |
| Test suite writing to production | STALE | `tests/test_api.py` targeted the live database and was fired at it once by accident. A production guard now blocks it — but the suite itself is still stale. |
| Code merging without CI | OPEN | Triggers cover `main`, `feature/**`, `fix/**`, `test/**`. Working branches like `create_school` match none, so that work is unverified by CI. |
| Toolchain drift | OPEN | CI pins Flutter 3.41.4; local is 3.44.0. A version-specific failure would not surface symmetrically. |
| iOS release verification | OPEN | Blocked on Apple Developer Program enrolment. No IPA has ever been built or tested. |
| Independent penetration test | OPEN | Every result in this register comes from self-testing. No external assessment, no DAST, no bug bounty. |

---

## What to fix first

Ordered by consequence, not by how interesting the work is.

1. **Check whether `admin` / `123456` works in production.** Everything else here is
   theoretical if a default credential is live. Confirm against the Railway database,
   and delete or rotate the seeded row.
2. **Decide the children's-data position.** COPPA / GDPR-K governs a product holding
   minors' records. This gates store submission and carries real legal weight — it is
   not a hardening task you can defer past launch.
3. **Publish the privacy policy and add Anthropic to it.** Host it, populate
   `privacyPolicyUrl`, disclose Claude as a recipient. Three small tasks that together
   unblock submission.
4. **Turn on build obfuscation.** Adding `--obfuscate --split-debug-info` is a one-line
   change that removes a whole class of reconnaissance from the shipped binary.
5. **Extend rate limiting past the four routers that have it.** A global default with
   per-route overrides. Currently most of the API can be hammered freely by any
   authenticated user.
6. **Validate document uploads by content, not by header.** Images already do this
   properly — apply the same magic-byte treatment to PDFs and decks.
7. **Add secrets scanning and a Dart dependency audit to CI.** Both are configuration,
   not engineering, and they close the two supply-chain blind spots `pip-audit`
   doesn't reach.
8. **Make CI run on the branch you actually work on.** Every gate above is worth less
   while the branch carrying the work matches no trigger.

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
