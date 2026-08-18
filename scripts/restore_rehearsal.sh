#!/usr/bin/env bash
#
# Proves a backup can actually be restored, by restoring it and checking the
# result against the manifest.
#
# An untested backup is a guess. The failures that matter — a truncated dump, a
# permissions error that skipped a table, a pg_dump/pg_restore version mismatch
# — all produce a file of plausible size that only fails when you finally need
# it. This restores into a throwaway database and compares row counts, so the
# failure surfaces on a quiet afternoon instead of during an incident.
#
# The live database is never touched. The scratch database is named
# mindforge_rehearsal_<pid> and dropped on exit, including on failure; the
# script refuses to run if that name ever resolves to the real one.
#
# Usage:
#   scripts/restore_rehearsal.sh <backup-dir>
#   scripts/restore_rehearsal.sh backups/20260819T101500Z
#
# Exit code is 0 only when every counted table matches. Wire it into whatever
# runs your backups, so a silent-but-broken backup becomes a loud failure.

set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-mindforge_postgres}"
DB_USER="${POSTGRES_USER:-mindforge}"
LIVE_DB="${POSTGRES_DB:-mindforge}"

BACKUP_DIR="${1:-}"
[ -n "$BACKUP_DIR" ] || { echo "usage: $0 <backup-dir>" >&2; exit 2; }

DUMP="$BACKUP_DIR/mindforge.dump"
MANIFEST="$BACKUP_DIR/manifest.txt"
SCRATCH_DB="mindforge_rehearsal_$$"

die() { echo "rehearsal: $*" >&2; exit 1; }
psql_live() { docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "$1"; }

[ -f "$DUMP" ]     || die "no dump at $DUMP"
[ -f "$MANIFEST" ] || die "no manifest at $MANIFEST"

# Refuse to operate on the live database under any circumstance. The whole point
# is that a rehearsal cannot become an incident.
[ "$SCRATCH_DB" != "$LIVE_DB" ] || die "scratch name collides with the live database"

docker inspect "$PG_CONTAINER" >/dev/null 2>&1 \
  || die "container '$PG_CONTAINER' not running"

cleanup() {
  docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $SCRATCH_DB;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> checksum"
recorded="$(grep '^dump_sha256=' "$MANIFEST" | cut -d= -f2)"
actual="$(shasum -a 256 "$DUMP" | awk '{print $1}')"
if [ "$recorded" != "$actual" ]; then
  die "dump checksum mismatch — the file changed since it was written
       manifest: $recorded
       on disk:  $actual"
fi
echo "    ok ($actual)"

echo "==> restoring into scratch database $SCRATCH_DB"
psql_live "CREATE DATABASE $SCRATCH_DB;" >/dev/null
# pg_restore reports non-fatal issues (missing roles, comments) with a non-zero
# exit even on a good restore, so its status is not the signal. The row-count
# comparison below is. Errors are still shown, because they often explain a
# mismatch when one appears.
docker exec -i "$PG_CONTAINER" pg_restore -U "$DB_USER" -d "$SCRATCH_DB" \
  --no-owner --no-privileges < "$DUMP" 2>&1 | sed 's/^/    pg_restore: /' || true

echo "==> comparing row counts against the manifest"
fail=0
while IFS= read -r line; do
  case "$line" in rows_*) ;; *) continue ;; esac
  table="${line%%=*}"; table="${table#rows_}"
  expected="${line#*=}"
  [ "$expected" != "n/a" ] || continue

  actual="$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$SCRATCH_DB" \
              -tAc "SELECT count(*) FROM $table;" 2>/dev/null | tr -d '[:space:]')" || actual="ERR"

  if [ "$actual" = "$expected" ]; then
    printf '    ok    %-14s %s\n' "$table" "$actual"
  else
    printf '    FAIL  %-14s expected %s, restored %s\n' "$table" "$expected" "$actual"
    fail=1
  fi
done < "$MANIFEST"

echo
if [ "$fail" -eq 0 ]; then
  echo "RESTORE REHEARSAL PASSED — this backup restores to matching row counts."
  echo "Scratch database dropped; the live database was never touched."
else
  echo "RESTORE REHEARSAL FAILED — do not rely on this backup." >&2
  exit 1
fi
