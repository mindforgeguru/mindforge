# Backup and restore runbook

**Status as of 2026-08-19:** tooling exists and has been rehearsed against the
local stack. **Production is not covered yet** — see [Production](#production).

There are two stores holding data you cannot recreate:

| Store | Holds | Recoverable without a backup? |
|---|---|---|
| Postgres | every record — users, attendance, grades, fees, homework | No |
| MinIO | avatars, chapter PDFs, uploaded decks | No |
| Redis | token JTIs, rate-limit counters, pub/sub | Yes — losing it signs everyone out, nothing more |

Redis is deliberately not backed up.

---

## Taking a backup (compose stack)

```bash
scripts/backup.sh              # writes ./backups/<UTC timestamp>/
scripts/backup.sh /some/path   # or somewhere else
```

Produces:

```
mindforge.dump    pg_dump custom format, compressed
minio/            object-store tree
manifest.txt      versions, sha256, and row counts for 5 key tables
```

The manifest is the part that matters. It is what makes the backup *checkable*
rather than merely present.

## Proving it restores

```bash
scripts/restore_rehearsal.sh backups/20260819T101500Z
```

Restores into a throwaway database (`mindforge_rehearsal_<pid>`), compares row
counts against the manifest, and drops it again — on failure as well as success,
via an EXIT trap. **The live database is never touched**, and the script refuses
to run if the scratch name ever resolves to the live one.

Exit codes, so this can be wired into automation:

| Code | Meaning |
|---|---|
| 0 | every counted table matched |
| 1 | checksum mismatch, or a row count differed |
| 2 | usage error |

### Why rehearsing is the point

The failure modes that matter all produce a file of plausible size that only
fails when you finally need it: a truncated dump, a permissions error that
skipped a table, a pg_dump/pg_restore version mismatch. Backing up without ever
restoring tells you a file exists. It does not tell you the file is a backup.

Verified on 2026-08-19 against the local stack — 61 users, 7 schools, 534
attendance rows, 86 grades, 3 fee payments, all matching after restore. Both
failure paths were confirmed to actually fail:

- a corrupted dump is caught at the checksum, exit 1
- a manifest claiming 99 users when the dump holds 61 fails the comparison, exit 1

A check that cannot be made to fail has not been shown to work.

---

## Production

**Not yet covered, and this is the open item.** The scripts above drive
`docker exec` against the compose containers. Production is different in both
halves:

**Postgres** is Railway-managed, and there are two independent things to get
right — Railway's own backups, and a restore you have personally verified.

1. *Railway's built-in backups.* In the dashboard, open the Postgres service →
   **Backups**. Confirm they are (a) enabled, (b) retained long enough to
   survive a problem noticed a week late (30 days is the target), and (c) that
   you know how to trigger a restore. This is your fast recovery path.

2. *A restore you have proven yourself.* Railway's snapshots restore only into
   Railway, so to actually rehearse one without paying for a second instance,
   take a logical dump and rebuild it locally. That is what
   `scripts/backup_railway.sh` does, in one command:

   ```bash
   # Railway → Postgres service → Connect → copy the "Postgres Connection URL"
   export DATABASE_URL='postgres://USER:PASS@HOST:PORT/railway'
   scripts/backup_railway.sh
   ```

   It dumps production (read-only — production is never written to), then
   restores that dump into a throwaway database inside the local Docker Postgres
   and compares row counts against a manifest, exactly like the local rehearsal.
   Exit 0 means a real production backup was taken and rebuilt to matching
   counts. The dump lands under `./backups/railway/` (gitignored) and holds
   every student record — treat it as sensitive and delete it when done.

   A snapshot nobody has restored has exactly the same standing as a dump nobody
   has restored. This is how you stop guessing.

**MinIO** is the sharper risk. Objects live on a Railway volume, and the
register records this failure mode as one that has **already happened** —
avatars and uploads blanked while the media proxy returned clean 404s.

1. *Confirm a volume is mounted at `/data`* on the MinIO service. This is what
   stops a container restart wiping every file — the exact past incident.

2. *An off-box copy.* A volume protects against a restart, not against deletion
   or corruption, so the objects need a copy that is not that volume. Two ways,
   in order of least effort:
   - **Railway volume backups.** The MinIO service has its own Backups tab, the
     same as Postgres — enable scheduled volume backups and set retention. This
     needs no public exposure.
   - **An independent copy you control**, via `scripts/backup_minio.sh`. Given
     the MinIO endpoint and keys it mirrors every bucket to a local folder and
     proves the copy is complete (files on disk == objects in production). This
     needs the MinIO endpoint reachable from your machine (a public TCP proxy),
     so it adds a little attack surface — use it when you want a copy that does
     not depend on Railway, not as the only measure.

Suggested cadence once production is wired up:

| What | How often | Retention |
|---|---|---|
| Postgres snapshot | daily | 30 days |
| Postgres rehearsal | monthly | — |
| MinIO off-box copy | daily | 30 days |
| Full restore drill | quarterly | — |

## What is still missing

- No off-site copy. `./backups/` on the same machine survives a bad migration;
  it does not survive losing the machine.
- No encryption at rest for the dump. It contains every student record, so treat
  the directory as sensitive and do not commit it (`backups/` is gitignored).
- No automated schedule. Both scripts are manual today; wiring
  `restore_rehearsal.sh` into whatever runs the backup is what turns a
  silently-broken backup into a loud failure.
