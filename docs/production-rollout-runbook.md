# Production rollout runbook: `create_school` → `main`

**Status as of 2026-10-09:** written, not yet executed. Nothing here has been run
against production. Steps marked **Confirm** are facts this document could not
check from the repository and must be checked in a dashboard before relying on
them.

Production (`api.mindforge.guru`) runs `main`, which stopped at `5cff40d`
(2026-07-18) and is still the single-school app. `create_school` is **127
commits ahead and 0 behind**, so the merge is a fast-forward. It brings
multi-tenancy, the owner console, the realtime rewrite, PyJWT, MFA for
admins/owner, session revocation and the redesigned login, plus **8 database
migrations (030–037)**.

---

## 1. The four facts that shape this plan

**1. Deploying is migrating.** There is no separate migration step to pause at.
`backend/start.sh` runs `alembic upgrade head` and the app's own startup in
`backend/main.py` runs it again. The moment the new backend boots against the
production database, 030–037 apply.

**2. The migration cannot be undone by a downgrade.** 030 adds `owner` to the
`user_role` Postgres enum, and Postgres cannot remove an enum value. A rollback
therefore means **restoring the database from the pre-deploy backup** (§5),
which loses anything written after it. That makes a fresh backup, taken minutes
before the deploy, non-negotiable.

**3. Old installed apps work only while production has exactly one school.**
The old app has no school picker and logs in without a `school_id`. The
backend falls back to the sole active school when there is exactly one
(`_resolve_school` in `backend/app/routers/auth.py`, `len(schools) == 1`).
After the migration production has one school, Hansel & Gretel, so old installs
keep working. **The moment a second school is activated, every old install
gets "Please select your school." and cannot log in.** There is no
forced-update mechanism, and the app version is still `1.0.0+1` on both
branches. So production stays single-school until old installs are gone (§6).

**4. The platform owner must be seeded by environment variable.** The owner
account is created at startup from `OWNER_SEED_MPIN` (and `OWNER_SEED_USERNAME`,
default `chinmay_owner`), never from a migration. Without it there is no account
that can create schools.

What is **not** a risk:

- **No endpoint was removed or renamed.** All 149 routes on `main` still exist
  on the branch (161 in total). Request/response *shapes* can still differ,
  which the old-app smoke test in §3 covers.
- **Nobody is logged out by the deploy**, provided `JWT_SECRET` is unchanged.
  Tokens signed by the old python-jose server verify under PyJWT, and refresh
  tokens rotate (12/12 live cross-library checks, 2026-10-09).
- **The data is small.** At the 2026-08-21 backup: 72 users, 3,406 attendance
  rows, 238 grades, 1 payment. The migrations take seconds.

## 2. Already done (from earlier sessions)

- **Production backups are proven to restore** (2026-08-21):
  `scripts/backup_railway.sh` dumped production read-only and rebuilt it in a
  throwaway database with matching counts. Railway daily Postgres backups are on
  (PITR available but off); MinIO has a daily volume-backup schedule and
  `scripts/backup_minio.sh` makes an independent counted copy. See
  [`backup-runbook.md`](backup-runbook.md).
- **The leftover `admin`/`123456` row in production is disabled** (2026-08-21,
  `is_active=false`, `deleted_at` set).
- **The branch is verified:** CI green on `20e64f3`; Flutter 171/171; backend
  unit 412/412; tenant isolation 37/37; multi-tenancy QA 8/8; security suites
  22 pass (+1 check that can't pass on `http://localhost`) and 48/48. See
  [`../TEST_RECORD.md`](../TEST_RECORD.md).

## 3. Pre-flight (the day before)

Do these in order. Stop if any fails.

1. **Merge the holiday homework fix first** (`claude/holiday-hw-gate`,
   `35f5087`) so production doesn't ship the holiday deadlock (TEST_RECORD §10
   item 18). Re-run CI on the result.

2. **Confirm what production is running.**
   - Railway → backend service → the deployed commit is `5cff40d` (or note what
     it is, and stop to reconcile if it isn't).
   - Railway → Postgres → Data: `SELECT version_num FROM alembic_version;`
     must return `029`. If it doesn't, the migration path in this document
     doesn't apply.
   - **Confirm** which branch the backend deploys from and whether auto-deploy
     is on. That decides whether §4's "merge" is also the deploy.
   - **Confirm** where the web app is hosted (`frontend/web/_redirects` suggests
     Netlify or Cloudflare Pages) and how it deploys.

3. **Rehearse the migration on a copy of production.** This is the step that
   catches a migration that only fails on real data.
   1. Restore a fresh production dump into a throwaway local database
      (`scripts/backup_railway.sh` already does dump-and-restore; keep the
      restored database instead of dropping it).
   2. `psql "$COPY_DSN" -f backend/scripts/verify_migration_1_before.sql`
      (snapshots row counts into `_mt_baseline`).
   3. Run the branch's backend image against that copy so its startup applies
      030–037. Watch for `Alembic migrations applied.` and
      `Application startup complete.`
   4. `psql "$COPY_DSN" -f backend/scripts/verify_migration_2_after.sql` and
      check its pass criteria: every row-count delta 0; no tenant rows left
      without a school; exactly one school, slug `hansel-gretel`; every
      non-owner user in that school.
   5. The verify scripts were written for 030–035. Also check that 036/037
      landed: `users` has `mfa_enabled`, `mfa_secret`, `mfa_recovery_codes`,
      `tokens_valid_after`, and `SELECT version_num FROM alembic_version`
      returns `037`.

4. **Smoke-test against the migrated copy**, with the backend from step 3 still
   pointed at it:
   - **The old app** (a build from `main`/`5cff40d`, pointed at the copy): an
     existing parent, student and teacher log in **without** picking a school,
     load their dashboards, and a teacher marks attendance. This proves fact 3
     on real data.
   - **The new app**: the same users log in via the school picker; the owner
     logs in with "Platform owner (no school)".
   - **Code-only rollback viability**: run the *old* backend (`5cff40d`)
     against the migrated copy and repeat the old-app logins. If it works, a
     code-only rollback is possible without losing data (§5). If not, rollback
     means restoring the database.

5. **Prepare Railway environment variables** on the backend service (do not
   change `JWT_SECRET`):
   - `OWNER_SEED_MPIN`: a strong 6-digit MPIN (not on the weak-MPIN blocklist).
     Optionally `OWNER_SEED_USERNAME`.
   - **Confirm** the rest are present and production values:
     `APP_ENV=production`, `BACKEND_PUBLIC_URL=https://api.mindforge.guru`,
     `SENTRY_DSN`, the AI keys (Claude is the primary provider, then Gemini,
     then Groq), the MinIO and Redis settings, `FIREBASE_CREDENTIALS_JSON`.
     `backend/app/core/config.py` has the same settings fields on both branches;
     the new requirement is only the owner seed.

6. **Open a pull request `create_school` → `main`** so CI runs on the PR. Don't
   merge yet.

7. **Bump the app version** (`frontend/pubspec.yaml` `version:` and
   `AppConstants.appVersion`, both still `1.0.0`) so new builds can be told
   apart from old ones in feedback reports and analytics.

## 4. Deploy window

Pick a time outside school hours (an evening or a Sunday), when no teacher is
marking attendance. Have the Railway dashboard and logs open.

1. **Take the pre-deploy backup, immediately before.** Railway → Postgres →
   Backups → create one now, and run `scripts/backup_railway.sh` for an
   independent dump you have proven restores. Note the time. Take a MinIO volume
   backup too.
2. **Merge the PR** (fast-forward). If auto-deploy is on, this starts the
   deploy; otherwise trigger the backend deploy in Railway.
3. **Watch the backend logs** for, in order: `Alembic migrations applied.`,
   `Platform owner seeded (username=chinmay_owner) with OWNER_SEED_MPIN`,
   `MIND FORGE backend is ready.` and `Application startup complete.` If you
   see `OWNER_SEED_MPIN not set … skipping owner seed`, the variable didn't
   reach the service (§3.5). A crash-loop here means stop and go to §5.
4. **Deploy the web app** if it doesn't deploy automatically.
5. **Post-deploy checks (15 minutes):**
   - `GET https://api.mindforge.guru/api/health` → 200.
   - `alembic_version` = `037`; `SELECT COUNT(*) FROM schools` = 1;
     `SELECT COUNT(*) FROM users WHERE school_id IS NULL AND role <> 'owner'` = 0.
   - Row counts for `users`, `attendance`, `grades`, `fee_payments` match the
     pre-deploy dump's manifest.
   - An existing parent and teacher log in on the **old installed app**
     without picking a school.
   - The same users log in on the **web app**; the owner logs in.
   - A teacher's realtime broadcast reaches a student.
   - Response headers: no `server: uvicorn` (the `--no-server-header` change).
6. **Set up MFA on the owner account straight away** (owner console → the
   shield icon, "Two-factor authentication").
   The owner can suspend or create any school; it should not rest on a 6-digit
   MPIN alone.

## 5. Rollback

**Roll back if:** the backend crash-loops on startup, the post-deploy checks
show lost or unstamped rows, or existing users can't log in on the old app.

- **If §3.4 proved the old code works on the migrated schema:** redeploy
  `5cff40d` in Railway. No data is lost; the new columns and the `schools` table
  are simply unused. Fix forward from there.
- **Otherwise, restore the database:** stop the backend, restore the pre-deploy
  backup from §4.1 (Railway → Postgres → Backups → restore), then redeploy
  `5cff40d`. **Anything written between the backup and the restore is lost**,
  which is why the window is outside school hours and short.

Either way, leave `main` alone until the cause is understood. Revert the merge
on `main` rather than force-pushing, so the history shows what happened.

## 6. After the deploy

- **Stay single-school until old installs are gone.** Don't activate a second
  school in production until the old app is no longer in use: Play Store update
  adoption, plus asking the existing school's parents and teachers to update
  (or use the web app). A forced-update check (a minimum supported version the
  app checks at launch) would make this enforceable; it doesn't exist yet and is
  worth adding before onboarding school two.
- **Then onboard the second school** through the owner console: create the
  school, provision its admin, and have the admin enable MFA.
- **Re-run the local test record** for anything changed by the deploy, and
  update `TEST_RECORD.md` and `SECURITY_RISK_REGISTER.md`. The register
  describes the branch; after this it describes production too.

## 7. Still open, outside this runbook

- **Children's privacy (COPPA / GDPR-K).** The app holds minors' records and no
  assessment has been done. A legal question rather than an engineering one;
  it gates store submission, not this deploy.
- **iOS** stays blocked until the Apple Developer Program enrolment.
- **Privacy policy** hosting, `privacyPolicyUrl`, and naming Anthropic/Claude as
  a recipient of uploaded documents (TEST_RECORD §4.2).
