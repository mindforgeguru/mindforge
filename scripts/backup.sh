#!/usr/bin/env bash
#
# Backs up the two stores that hold data you cannot recreate:
#
#   postgres — every record in the app
#   minio    — avatars, chapter PDFs, uploaded decks
#
# Redis is deliberately not backed up. It holds access-token JTIs, rate-limit
# counters and the pub/sub channel; losing it signs everyone out and resets some
# counters, which is an inconvenience rather than data loss.
#
# Scope: this backs up the **docker-compose** stack — local or self-hosted.
# Production on Railway uses managed Postgres with its own snapshots, and the
# MinIO objects there live on a Railway volume. See docs/backup-runbook.md for
# what production needs; do not assume this script covers it.
#
# Usage:
#   scripts/backup.sh [output-dir]        # default: ./backups
#
# Produces  <output-dir>/<UTC timestamp>/
#   mindforge.dump     pg_dump custom format, compressed
#   minio/             object-store tree
#   manifest.txt       versions, checksums and row counts
#
# The manifest is what makes the backup checkable: restore_rehearsal.sh compares
# a restored copy against it. A dump nobody has restored is not a backup, it is
# a file.

set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-mindforge_postgres}"
MINIO_CONTAINER="${MINIO_CONTAINER:-mindforge_minio}"
DB_NAME="${POSTGRES_DB:-mindforge}"
DB_USER="${POSTGRES_USER:-mindforge}"

OUT_ROOT="${1:-./backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_ROOT}/${STAMP}"

# Tables whose counts go in the manifest. Chosen because a restore that silently
# loses one of these is the failure worth catching: identities, tenants, and the
# three record types a school would be unable to reconstruct by hand.
COUNT_TABLES=(users schools attendance grades fee_payments)

die() { echo "backup: $*" >&2; exit 1; }

docker inspect "$PG_CONTAINER" >/dev/null 2>&1 \
  || die "container '$PG_CONTAINER' not running — start the stack first"

mkdir -p "$OUT/minio"

echo "==> Postgres → $OUT/mindforge.dump"
# Custom format (-Fc): compressed, and pg_restore can then rebuild into a
# differently-named database, which the rehearsal depends on.
docker exec "$PG_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc \
  > "$OUT/mindforge.dump"

[ -s "$OUT/mindforge.dump" ] || die "dump is empty — aborting rather than keeping a useless backup"

echo "==> MinIO → $OUT/minio/"
if docker inspect "$MINIO_CONTAINER" >/dev/null 2>&1; then
  # Copy the object tree wholesale. Crude next to `mc mirror`, but it needs no
  # extra client and no credentials, and the shape on disk is what MinIO reads
  # back on restore.
  docker cp "$MINIO_CONTAINER:/data/." "$OUT/minio/" 2>/dev/null \
    || echo "    (warning: MinIO copy failed — Postgres dump is still valid)"
else
  echo "    (skipped: '$MINIO_CONTAINER' not running)"
fi

echo "==> manifest"
{
  echo "created_utc=$STAMP"
  echo "pg_server_version=$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc 'SHOW server_version;' | tr -d '[:space:]')"
  echo "pg_dump_version=$(docker exec "$PG_CONTAINER" pg_dump --version | awk '{print $3}')"
  echo "dump_sha256=$(shasum -a 256 "$OUT/mindforge.dump" | awk '{print $1}')"
  echo "dump_bytes=$(wc -c < "$OUT/mindforge.dump" | tr -d '[:space:]')"
  echo "minio_files=$(find "$OUT/minio" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
  for t in "${COUNT_TABLES[@]}"; do
    n=$(docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
          "SELECT count(*) FROM $t;" 2>/dev/null | tr -d '[:space:]') || n="n/a"
    echo "rows_${t}=${n:-n/a}"
  done
} > "$OUT/manifest.txt"

cat "$OUT/manifest.txt"
echo
echo "Backup complete: $OUT"
echo "Now prove it: scripts/restore_rehearsal.sh $OUT"
