# Local dev test accounts

**Scope: local development only.** These accounts live in the local Docker
Postgres DB and are used when running the app against the local backend
(`flutter run --dart-define=LOCAL_DEV=true`, backend on `127.0.0.1:8000`).

They were **provisioned by hand** during QA — they are **not** created by any
seed script, so a freshly reset database will not have them. Recreate the
admins from the **Owner Console → Add Admin** on each school if your DB is
fresh. Never use these credentials anywhere but a local machine.

All MPINs are entered on the 6-digit PIN pad on the login screen.

> Every credential below was verified against `POST /api/auth/login` on
> 2026-08-18 and returned 200 unless the row says otherwise.

## Platform owner

| Field | Value |
|-------|-------|
| School | pick **"Platform owner (no school)"** in the picker |
| Username | `chinmay_owner` |
| MPIN | `123456` |

## Per-school admin

`demo_admin` / `847362` — an admin account in each of the five dev schools.
Select the school in the login picker, then sign in:

- Hansel & Gretel
- Riverdale High
- St. Xavier High
- Greenwood Academy
- Greenwood Academy 5762

All five were login-verified.

Additional school-specific admins:

| School | Username | MPIN |
|--------|----------|------|
| Riverdale High | `river_admin` | `123456` |
| St. Xavier High | `xavier_admin` | unknown — `847362` and `123456` both 401 |
| Greenwood Academy 5762 | `gw_admin_5762` | unknown — `847362` and `123456` both 401 |

## Teachers

| School | Username | MPIN |
|--------|----------|------|
| Hansel & Gretel | `chinmay_sir` | `847362` |
| Riverdale High | `river_teach` | `123456` |

## Students

| School | Username | Grade | MPIN |
|--------|----------|-------|------|
| Hansel & Gretel | `nitin` | 10 | `123456` |
| Hansel & Gretel | `manam` | 10 | `123456` |
| Hansel & Gretel | `dummy8` | 8 | `123456` |
| Riverdale High | `river_kid` | 8 | `847362` |

> `hansel_kid` is listed in older notes but is **deactivated**
> (`users.is_active = false`) and now returns 401. Use `dummy8` for a
> Hansel & Gretel grade-8 student instead.

## Parents

| School | Username | Child | MPIN |
|--------|----------|-------|------|
| Hansel & Gretel | `nitin_dad` | `nitin` (grade 10) | `123456` |
| Riverdale High | `river_par` | `river_kid` (grade 8) | `123456` |

## Notes for cross-school testing

Grade 8 exists in **both** Hansel & Gretel and Riverdale High, which makes this
pair useful for tenant-isolation checks: a leak across schools is visible as
data for the *same grade number* showing up in the wrong account, rather than
being masked by the grade filter. `river_kid` (Riverdale, grade 8) and `dummy8`
(Hansel, grade 8) are the two ends of that test.
