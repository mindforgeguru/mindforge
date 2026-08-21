#!/usr/bin/env bash
#
# Makes an off-box copy of the PRODUCTION MinIO object store (avatars, chapter
# PDFs, uploaded decks) and proves it is complete — the second half of item 04
# in docs/backup-runbook.md.
#
# MinIO objects live on a Railway volume. A volume survives a container restart
# but not a deletion or corruption — and losing these objects is a failure this
# project has already seen once (avatars blanked, media proxy returning 404s).
# So the files need a copy somewhere that is not that volume. This pulls every
# object down with `mc mirror`, then confirms the number of files on disk equals
# the number of objects in production. A copy nobody has counted is a guess.
#
# Production is only ever read from. Nothing in MinIO is modified.
#
# ── What you need ─────────────────────────────────────────────────────────────
#   1. Docker running.
#   2. Your production MinIO endpoint and keys. In Railway, open the MinIO
#      service → Variables, and read:
#        MINIO_ENDPOINT     host:port of the PUBLIC endpoint (see note below)
#        MINIO_ACCESS_KEY   (a.k.a. MINIO_ROOT_USER)
#        MINIO_SECRET_KEY   (a.k.a. MINIO_ROOT_PASSWORD)
#      If the service only has an internal address, expose a public TCP proxy on
#      it first (Settings → Networking), the same as we did for Postgres.
#
# ── How to run ────────────────────────────────────────────────────────────────
#   export MINIO_ENDPOINT='your-minio.up.railway.app:443'
#   export MINIO_ACCESS_KEY='…'
#   export MINIO_SECRET_KEY='…'
#   export MINIO_USE_SSL=true            # true for a :443 / https endpoint
#   scripts/backup_minio.sh
#
# Keep the keys in your shell, not in a file. This script never prints them; it
# passes them to Docker through the environment so they stay out of process
# listings.
#
# ── Exit codes ────────────────────────────────────────────────────────────────
#   0  every production object is present in the local copy
#   1  the copy is short of production (or a bucket failed to mirror)
#   2  usage / environment error

set -euo pipefail

MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"
OUT_ROOT="${1:-./backups/minio}"

die() { echo "minio-backup: $*" >&2; exit "${2:-1}"; }

[ -n "${MINIO_ENDPOINT:-}" ]   || die "set MINIO_ENDPOINT (host:port from Railway → MinIO → Variables)" 2
[ -n "${MINIO_ACCESS_KEY:-}" ] || die "set MINIO_ACCESS_KEY (a.k.a. MINIO_ROOT_USER)" 2
[ -n "${MINIO_SECRET_KEY:-}" ] || die "set MINIO_SECRET_KEY (a.k.a. MINIO_ROOT_PASSWORD)" 2
USE_SSL="${MINIO_USE_SSL:-false}"
docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop and retry" 2

scheme="http"; [ "$USE_SSL" = "true" ] && scheme="https"
# The alias URL carries the credentials. Exported (name passed to -e), never in
# an argument, so it appears in no process list; never printed.
export MC_HOST_prod="${scheme}://${MINIO_ACCESS_KEY}:${MINIO_SECRET_KEY}@${MINIO_ENDPOINT}"

# One-off mc run. Entry point of the image is `mc`, so args are mc subcommands.
mc() { docker run --rm --add-host=host.docker.internal:host-gateway -e MC_HOST_prod "$MC_IMAGE" "$@"; }

echo "==> preparing the copy tool ($MC_IMAGE)"
docker image inspect "$MC_IMAGE" >/dev/null 2>&1 || docker pull "$MC_IMAGE" >/dev/null

echo "==> counting objects in production (read-only)"
# One line per object across every bucket. This is the number the local copy
# must match.
remote_objects="$(mc ls --recursive prod/ 2>/dev/null | wc -l | tr -d '[:space:]')" \
  || die "could not connect to MinIO — check MINIO_ENDPOINT/keys and that the endpoint is public"
echo "    production holds $remote_objects object(s)"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_ROOT}/${STAMP}"
mkdir -p "$OUT/data"
OUT_ABS="$(cd "$OUT" && pwd)"
MANIFEST="$OUT/manifest.txt"

echo "==> mirroring every bucket → $OUT/data (production is not modified)"
# mirror copies all buckets under the alias. Mounted so the files land on the
# host; the container only runs mc, all counting happens on the host below.
docker run --rm --add-host=host.docker.internal:host-gateway \
  -v "$OUT_ABS/data":/out -e MC_HOST_prod "$MC_IMAGE" \
  mirror --overwrite prod/ /out/ 2>&1 | sed 's/^/    mc: /' || true

echo "==> counting the local copy and writing the manifest"
disk_objects="$(find "$OUT_ABS/data" -type f | wc -l | tr -d '[:space:]')"
{
  echo "created_utc=$STAMP"
  echo "source=railway-minio"
  echo "endpoint=$MINIO_ENDPOINT"
  echo "remote_objects=$remote_objects"
  echo "local_objects=$disk_objects"
  # Per-bucket file counts, so a shortfall points at which bucket.
  for d in "$OUT_ABS/data"/*/; do
    [ -d "$d" ] || continue
    b="$(basename "$d")"
    n="$(find "$d" -type f | wc -l | tr -d '[:space:]')"
    echo "objects_${b}=$n"
  done
  echo "total_size=$(du -sh "$OUT_ABS/data" 2>/dev/null | cut -f1)"
} > "$MANIFEST"
grep -v '^endpoint=' "$MANIFEST" | sed 's/^/    /'

echo
if [ "$disk_objects" = "$remote_objects" ]; then
  echo "MINIO OFF-BOX COPY COMPLETE"
  echo "  $disk_objects object(s) pulled and counted; the copy matches production."
  echo "  Copy at: $OUT/data"
  echo "  It holds uploaded student material — treat it as sensitive. ./backups is gitignored."
else
  echo "MINIO COPY INCOMPLETE — production has $remote_objects, copy has $disk_objects." >&2
  echo "Re-run; if it persists, check the mc output above for the bucket that failed." >&2
  exit 1
fi
