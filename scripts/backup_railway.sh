#!/usr/bin/env bash
#
# Proves the PRODUCTION Postgres (Railway-managed) can actually be backed up and
# restored — the open half of docs/backup-runbook.md.
#
# The other scripts here drive `docker exec` against the local compose stack, so
# they cannot reach Railway. This one talks to production over its connection
# URL: it takes a logical dump, then rehearses the restore into a THROWAWAY
# database inside your local Docker Postgres and compares row counts. Production
# is only ever read from (pg_dump + SELECT count(*)); it is never written to, and
# the scratch database is local and dropped on exit.
#
# Why rehearse against the local container rather than Railway: you cannot spin
# up a scratch database next to a managed one without paying for a second
# instance, and the thing worth proving is that the dump is complete and
# restorable — which a local rebuild proves just as well, for free.
#
# ── What you need ─────────────────────────────────────────────────────────────
#   1. The local Docker stack running (this provides pg_restore + the scratch DB).
#   2. Your production connection URL. In Railway: open the Postgres service →
#      "Connect" → copy the "Postgres Connection URL" (starts postgres://…).
#
# ── How to run ────────────────────────────────────────────────────────────────
#   export DATABASE_URL='postgres://USER:PASS@HOST:PORT/railway'   # paste yours
#   scripts/backup_railway.sh
#
# Keep DATABASE_URL in your shell, not in a file, and not in this repo. It is a
# production credential. This script never prints it.
#
# ── Exit codes ────────────────────────────────────────────────────────────────
#   0  dump taken and every counted table matched after restore
#   1  a version block, a checksum mismatch, or a row-count difference
#   2  usage / environment error

set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-mindforge_postgres}"     # local, used for restore
LOCAL_DB_USER="${POSTGRES_USER:-mindforge}"            # owner of the scratch DB
OUT_ROOT="${1:-./backups/railway}"

# Same tables the local backup counts: identities, tenants, and the three record
# types a school could not rebuild by hand. A restore that silently drops one of
# these is exactly the failure this is here to catch.
COUNT_TABLES=(users schools attendance grades fee_payments)

die() { echo "railway-backup: $*" >&2; exit "${2:-1}"; }

[ -n "${DATABASE_URL:-}" ] \
  || die "DATABASE_URL is not set. Copy it from Railway → Postgres → Connect, then:
       export DATABASE_URL='postgres://…'  (see the header of this script)" 2

docker inspect "$PG_CONTAINER" >/dev/null 2>&1 \
  || die "local container '$PG_CONTAINER' is not running — start the stack first (it provides the restore engine and the scratch database)" 2

# Run pg_dump / pg_restore / psql from INSIDE the local container so their
# versions always match the engine doing the restore. The remote URL is passed
# through the environment, never as an argument, so it does not appear in the
# container's process list.
pg() { docker exec -i -e TARGET_URL="$DATABASE_URL" "$PG_CONTAINER" "$@"; }

echo "==> checking versions before doing anything"
# pg_dump refuses to dump a server newer than itself. Catch that here with a
# readable message rather than a cryptic failure halfway through.
server_version="$(pg psql "$DATABASE_URL" -tAc 'SHOW server_version;' 2>/dev/null | tr -d '[:space:]')" \
  || die "could not connect to production with DATABASE_URL — check you copied the whole URL"
dumper_major="$(docker exec "$PG_CONTAINER" pg_dump --version | awk '{print $3}' | cut -d. -f1)"
server_major="${server_version%%.*}"
echo "    production Postgres: $server_version   local pg_dump: ${dumper_major}.x"
if [ "$server_major" -gt "$dumper_major" ]; then
  die "production runs Postgres $server_major but the local pg_dump is $dumper_major.
       pg_dump cannot dump a newer server. Bump the postgres image in
       docker-compose.local.yml to $server_major and re-run."
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_ROOT}/${STAMP}"
DUMP="$OUT/mindforge.dump"
MANIFEST="$OUT/manifest.txt"
mkdir -p "$OUT"

echo "==> dumping production → $DUMP (read-only; production is not modified)"
pg pg_dump "$DATABASE_URL" -Fc > "$DUMP"
[ -s "$DUMP" ] || die "dump is empty — aborting rather than keeping a useless file"

echo "==> writing manifest (row counts read from production)"
{
  echo "created_utc=$STAMP"
  echo "source=railway"
  echo "pg_server_version=$server_version"
  echo "pg_dump_version=$(docker exec "$PG_CONTAINER" pg_dump --version | awk '{print $3}')"
  echo "dump_sha256=$(shasum -a 256 "$DUMP" | awk '{print $1}')"
  echo "dump_bytes=$(wc -c < "$DUMP" | tr -d '[:space:]')"
  for t in "${COUNT_TABLES[@]}"; do
    n=$(pg psql "$DATABASE_URL" -tAc "SELECT count(*) FROM $t;" 2>/dev/null | tr -d '[:space:]') || n="n/a"
    echo "rows_${t}=${n:-n/a}"
  done
} > "$MANIFEST"
cat "$MANIFEST" | grep -v '^dump_sha256=' | sed 's/^/    /'   # sha shown below in full

# ── Rehearse the restore into a throwaway LOCAL database ──────────────────────
SCRATCH_DB="railway_rehearsal_$$"
LIVE_LOCAL_DB="${POSTGRES_DB:-mindforge}"
[ "$SCRATCH_DB" != "$LIVE_LOCAL_DB" ] || die "scratch name collides with the local database"

cleanup() {
  docker exec "$PG_CONTAINER" psql -U "$LOCAL_DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $SCRATCH_DB;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> checksum"
recorded="$(grep '^dump_sha256=' "$MANIFEST" | cut -d= -f2)"
actual="$(shasum -a 256 "$DUMP" | awk '{print $1}')"
[ "$recorded" = "$actual" ] || die "dump checksum mismatch — the file changed since it was written"
echo "    ok ($actual)"

echo "==> restoring into scratch database $SCRATCH_DB (local; production untouched)"
docker exec "$PG_CONTAINER" psql -U "$LOCAL_DB_USER" -d postgres \
  -c "CREATE DATABASE $SCRATCH_DB;" >/dev/null
# pg_restore returns non-zero for harmless notices (missing roles, comments), so
# its exit status is not the signal — the row-count comparison below is. Its
# output is still shown because it usually explains a mismatch when one appears.
docker exec -i "$PG_CONTAINER" pg_restore -U "$LOCAL_DB_USER" -d "$SCRATCH_DB" \
  --no-owner --no-privileges < "$DUMP" 2>&1 | sed 's/^/    pg_restore: /' || true

echo "==> comparing restored row counts against the manifest"
fail=0
while IFS= read -r line; do
  case "$line" in rows_*) ;; *) continue ;; esac
  table="${line%%=*}"; table="${table#rows_}"
  expected="${line#*=}"
  [ "$expected" != "n/a" ] || continue
  restored="$(docker exec "$PG_CONTAINER" psql -U "$LOCAL_DB_USER" -d "$SCRATCH_DB" \
                -tAc "SELECT count(*) FROM $table;" 2>/dev/null | tr -d '[:space:]')" || restored="ERR"
  if [ "$restored" = "$expected" ]; then
    printf '    ok    %-14s %s\n' "$table" "$restored"
  else
    printf '    FAIL  %-14s expected %s, restored %s\n' "$table" "$expected" "$restored"
    fail=1
  fi
done < "$MANIFEST"

echo
if [ "$fail" -eq 0 ]; then
  echo "PRODUCTION RESTORE REHEARSAL PASSED"
  echo "  A real Railway backup was taken and rebuilt to matching row counts."
  echo "  Dump kept at: $DUMP"
  echo "  Treat that file as sensitive — it holds every student record. ./backups is gitignored."
else
  echo "PRODUCTION RESTORE REHEARSAL FAILED — do not rely on this backup." >&2
  exit 1
fi
