"""
Null out profile_pic_url values that point to objects no longer in MinIO.

Context: on 2026-06-25 the MinIO storage volume on Railway lost its data (no
persistent volume was attached), so every uploaded avatar disappeared while
Postgres kept the now-dangling URLs. Dangling URLs render as blank circles in
the app; nulling them lets the UI fall back to initials until users re-upload.

Both columns are cleaned: User.profile_pic_url (all roles) and
StudentProfile.profile_pic_url (students duplicate it there).

Safety: each URL is checked against MinIO first — a row is only nulled when the
underlying object is genuinely missing. So this is safe to run AFTER the volume
fix even if some users have already re-uploaded (those objects exist and are
left untouched). Pass --force to skip the existence check and null everything.

Usage (from the backend directory, with MinIO + DB env configured):
    python3 scripts/null_dangling_profile_pics.py            # dry-run, just report
    python3 scripts/null_dangling_profile_pics.py --apply    # actually null missing
    python3 scripts/null_dangling_profile_pics.py --apply --force   # null all, no check

Exits 0 on success.
"""

import argparse
import asyncio
import os
import sys
from urllib.parse import urlparse

# Allow running as `python3 scripts/null_dangling_profile_pics.py`
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from minio.error import S3Error
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.user import StudentProfile, User
from app.services import storage_service


def parse_bucket_key(url: str):
    """Extract (bucket, key) from a stored profile_pic_url.

    Handles the media-proxy form produced by get_public_url
    (https://host/api/media/{bucket}/{key}), legacy direct MinIO URLs
    (https://host/{bucket}/{key}), and bare "bucket/key" path references.
    Returns None if it can't be parsed.
    """
    if not url:
        return None

    if url.startswith("http"):
        path = urlparse(url).path.lstrip("/")
        # Strip the proxy prefix if present.
        if path.startswith("api/media/"):
            path = path[len("api/media/"):]
    else:
        path = url.lstrip("/")

    parts = path.split("/", 1)
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return None
    return parts[0], parts[1]


def object_exists(bucket: str, key: str) -> bool:
    """True if the object is present in MinIO, False if missing."""
    client = storage_service._get_client()
    try:
        client.stat_object(bucket, key)
        return True
    except S3Error as e:
        if getattr(e, "code", "") in ("NoSuchKey", "NoSuchObject", "NoSuchBucket"):
            return False
        # Unexpected S3 error — re-raise so we don't blindly null on a transient fault.
        raise


async def clean(apply: bool, force: bool):
    nulled = 0
    kept = 0
    unparseable = 0

    async with AsyncSessionLocal() as session:
        # (label, model) pairs — both columns share the same field name.
        targets = [("User", User), ("StudentProfile", StudentProfile)]

        for label, model in targets:
            rows = (
                await session.execute(
                    select(model).where(model.profile_pic_url.is_not(None))
                )
            ).scalars().all()

            for row in rows:
                url = row.profile_pic_url
                missing = True  # default for --force / unparseable

                if not force:
                    parsed = parse_bucket_key(url)
                    if parsed is None:
                        unparseable += 1
                        print(f"  [skip] {label}#{row.id}: can't parse URL -> {url}")
                        continue
                    missing = not object_exists(*parsed)

                if missing:
                    nulled += 1
                    action = "WOULD null" if not apply else "nulled"
                    print(f"  [{action}] {label}#{row.id} -> {url}")
                    if apply:
                        row.profile_pic_url = None
                else:
                    kept += 1

        if apply:
            await session.commit()

    print()
    print(f"Dangling (missing object){' nulled' if apply else ' to null'}: {nulled}")
    print(f"Kept (object still present):                {kept}")
    if unparseable:
        print(f"Skipped (unparseable URL):                  {unparseable}")
    if not apply:
        print("\nDry run — nothing changed. Re-run with --apply to commit.")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apply", action="store_true",
                   help="Commit the changes (default is a dry run).")
    p.add_argument("--force", action="store_true",
                   help="Skip the MinIO existence check and null every profile_pic_url.")
    args = p.parse_args()
    asyncio.run(clean(apply=args.apply, force=args.force))


if __name__ == "__main__":
    main()
