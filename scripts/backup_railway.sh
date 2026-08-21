#!/usr/bin/env bash
#
# Proves the PRODUCTION Postgres (Railway-managed) can actually be backed up and
# restored — the open half of docs/backup-runbook.md.
#
# The other scripts here drive `docker exec` against the local compose stack, so
# they cannot reach Railway. This one talks to production over its public
# connection URL: it takes a logical dump, then rehearses the restore into a
# THROWAWAY Postgres started just for the job, and compares row counts.
# Production is only ever read from (pg_dump + SELECT count(*)); it is never
# written to.
#
# It does NOT use your local dev database. The dump client and the scratch
# server are both a disposable container matched to production's major version,
# so nothing here can disturb the Postgres you develop against — and there is no
# version-mismatch trap, because the engine is always the right version.
#
# ── What you need ─────────────────────────────────────────────────────────────
#   1. Docker running.
#   2. Your production PUBLIC connection URL. In Railway: Postgres service →
#      Variables → reveal and copy DATABASE_PUBLIC_URL (postgres://…). Use the
#      PUBLIC one — the plain DATABASE_URL points at an internal address your
#      laptop cannot reach.
#
# ── How to run ────────────────────────────────────────────────────────────────
#   export DATABASE_URL='postgres://USER:PASS@HOST:PORT/railway'   # paste yours
#   scripts/backup_railway.sh
#
# Keep the URL in your shell, not in a file, and not in this repo. It is a
# production credential. This script never prints it, and passes it to Docker
# through the environment so it does not appear in any process list.
#
# ── Exit codes ────────────────────────────────────────────────────────────────
#   0  dump taken and every counted table matched after restore
#   1  a checksum mismatch or a row-count difference
#   2  usage / environment error

set -euo pipefail

# Client + scratch engine image. Postgres is forward-compatible for dumps (a
# newer client dumps an older server fine), so this only needs to be >= the
# production major version. Bump the tag if Railway ever moves past it.
CLIENT_IMAGE="${PG_CLIENT_IMAGE:-postgres:18}"
OUT_ROOT="${1:-./backups/railway}"

# Same tables the local backup counts: identities, tenants, and the three record
# types a school could not rebuild by hand. A restore that silently drops one of
# these is exactly the failure this is here to catch.
COUNT_TABLES=(users schools attendance grades fee_payments)

die() { echo "railway-backup: $*" >&2; exit "${2:-1}"; }

[ -n "${DATABASE_URL:-}" ] \
  || die "DATABASE_URL is not set. Copy DATABASE_PUBLIC_URL from Railway →
       Postgres → Variables, then:  export DATABASE_URL='postgres://…'" 2
docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop and retry" 2

# Pass the URL to containers through the environment, never as an argument, so
# it never lands in the host's process list.
export DBURL="$DATABASE_URL"

echo "==> preparing a disposable Postgres engine ($CLIENT_IMAGE)"
docker image inspect "$CLIENT_IMAGE" >/dev/null 2>&1 || docker pull "$CLIENT_IMAGE"

# A one-off client (dump / query), and the throwaway server used for the restore.
client() { docker run --rm -e DBURL "$CLIENT_IMAGE" sh -c "$1"; }

echo "==> checking the connection"
server_version="$(client 'psql "$DBURL" -tAc "SHOW server_version;"' 2>/dev/null | tr -d '[:space:]')" \
  || die "could not connect with DATABASE_URL — check you copied the whole PUBLIC url (DATABASE_PUBLIC_URL)"
client_major="$(docker run --rm "$CLIENT_IMAGE" pg_dump --version | awk '{print $3}' | cut -d. -f1)"
server_major="${server_version%%.*}"
echo "    production Postgres: $server_version   client engine: ${client_major}.x"
if [ "$server_major" -gt "$client_major" ]; then
  die "production runs Postgres $server_major but the engine image is $client_major.
       Re-run with a newer image:  PG_CLIENT_IMAGE=postgres:$server_major scripts/backup_railway.sh"
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_ROOT}/${STAMP}"
DUMP="$OUT/mindforge.dump"
MANIFEST="$OUT/manifest.txt"
mkdir -p "$OUT"

echo "==> dumping production → $DUMP (read-only; production is not modified)"
client 'pg_dump "$DBURL" -Fc' > "$DUMP"
[ -s "$DUMP" ] || die "dump is empty — aborting rather than keeping a useless file"

echo "==> writing manifest (row counts read from production)"
{
  echo "created_utc=$STAMP"
  echo "source=railway"
  echo "pg_server_version=$server_version"
  echo "engine_image=$CLIENT_IMAGE"
  echo "dump_sha256=$(shasum -a 256 "$DUMP" | awk '{print $1}')"
  echo "dump_bytes=$(wc -c < "$DUMP" | tr -d '[:space:]')"
  for t in "${COUNT_TABLES[@]}"; do
    n=$(client "psql \"\$DBURL\" -tAc 'SELECT count(*) FROM $t;'" 2>/dev/null | tr -d '[:space:]') || n="n/a"
    echo "rows_${t}=${n:-n/a}"
  done
} > "$MANIFEST"
grep -v '^dump_sha256=' "$MANIFEST" | sed 's/^/    /'

echo "==> checksum"
recorded="$(grep '^dump_sha256=' "$MANIFEST" | cut -d= -f2)"
actual="$(shasum -a 256 "$DUMP" | awk '{print $1}')"
[ "$recorded" = "$actual" ] || die "dump checksum mismatch — the file changed since it was written"
echo "    ok ($actual)"

# ── Rehearse the restore into a throwaway engine ──────────────────────────────
ENGINE="railway_rehearsal_$$"
cleanup() { docker rm -f "$ENGINE" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> starting scratch server and restoring into it (production untouched)"
docker run -d --name "$ENGINE" -e POSTGRES_PASSWORD=rehearsal "$CLIENT_IMAGE" >/dev/null

# Wait for the scratch server to accept connections (up to ~30s).
ready=0
for _ in $(seq 1 30); do
  if docker exec "$ENGINE" pg_isready -U postgres -q 2>/dev/null; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || die "scratch Postgres did not come up in time"

docker exec "$ENGINE" psql -U postgres -c "CREATE DATABASE rehearsal;" >/dev/null
# pg_restore returns non-zero for harmless notices (missing roles, comments), so
# its exit status is not the signal — the row-count comparison below is. Its
# output is shown because it usually explains a mismatch when one appears.
docker exec -i "$ENGINE" pg_restore -U postgres -d rehearsal \
  --no-owner --no-privileges < "$DUMP" 2>&1 | sed 's/^/    pg_restore: /' || true

echo "==> comparing restored row counts against the manifest"
fail=0
while IFS= read -r line; do
  case "$line" in rows_*) ;; *) continue ;; esac
  table="${line%%=*}"; table="${table#rows_}"
  expected="${line#*=}"
  [ "$expected" != "n/a" ] || continue
  restored="$(docker exec "$ENGINE" psql -U postgres -d rehearsal \
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
  echo "  It holds every student record — treat it as sensitive and delete it when done."
  echo "  (./backups is gitignored, so it will not be committed.)"
else
  echo "PRODUCTION RESTORE REHEARSAL FAILED — do not rely on this backup." >&2
  exit 1
fi
