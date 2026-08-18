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

**Postgres** is Railway-managed. It has its own snapshot mechanism — confirm in
the Railway dashboard that snapshots are (a) enabled, (b) retained long enough
to survive a problem noticed a week late, and (c) *restorable*, which needs the
same rehearsal discipline: restore a snapshot into a scratch Railway database
and compare counts. A snapshot nobody has restored has exactly the same standing
as a dump nobody has restored.

**MinIO** is the sharper risk. Objects live on a Railway volume, and the
register records this failure mode as one that has **already happened** —
avatars and uploads blanked while the media proxy returned clean 404s. Confirm a
volume is mounted at `/data`, then arrange an off-box copy: a volume is
protection against a container restart, not against deletion or corruption.

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
