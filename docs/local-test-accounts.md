# Local dev test accounts

**Scope: local development only.** These accounts live in the local Docker
Postgres DB and are used when running the app against the local backend
(`flutter run --dart-define=LOCAL_DEV=true`, backend on `127.0.0.1:8000`).

They were **provisioned by hand** during QA — they are **not** created by any
seed script, so a freshly reset database will not have them. Recreate the
admins from the **Owner Console → Add Admin** on each school if your DB is
fresh. Never use these credentials anywhere but a local machine.

All MPINs are entered on the 6-digit PIN pad on the login screen.

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

## Student logins (grade 8)

Pre-existing students whose MPIN was reset to a known value for testing:

| School | Username | MPIN |
|--------|----------|------|
| Hansel & Gretel | `hansel_kid` | `847362` |
| Riverdale High | `river_kid` | `847362` |

> Teachers and parents: no shared known credentials. Provision an admin with
> the owner console, then create teachers/students from the admin dashboard.
