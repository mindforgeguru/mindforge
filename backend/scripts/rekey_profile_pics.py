"""
Re-key existing profile pictures from predictable object names to unguessable ones.

Context: profile pictures used to be stored at a predictable key
(``profiles/{user_id}/avatar.jpg``, ``profiles/teacher/{id}/avatar.jpg``, …) and
served through the *unauthenticated* media proxy (``/api/media/{bucket}/{key}``).
Because user ids are sequential and the filename was fixed, anyone could
enumerate every user's photo — students (minors), teachers and parents — just by
iterating ids and trying a few extensions.

The upload endpoints now mint an unguessable key (``profiles/{id}/{token}.jpg``)
and delete the old object on re-upload, but that only protects users who upload
again. This one-time migration closes the hole for *existing* photos: for each
stored avatar it copies the object to a fresh random key, repoints the DB
url(s), and deletes the old predictable object.

Idempotent + safe:
  • Only objects whose filename is still ``avatar.*`` are touched — already-random
    keys are skipped, so re-running does nothing.
  • Students duplicate the url on both ``User`` and ``StudentProfile``; rows that
    reference the same object are grouped and updated together to one new key.
  • Missing objects (dangling urls from the 2026-06-25 MinIO wipe) are reported
    and left for null_dangling_profile_pics.py — this script never nulls.
  • Copy → commit DB → delete-old ordering means an interruption can only leave a
    harmless orphan, never a broken url.

Usage (from the backend directory, with MinIO + DB env configured):
    python3 scripts/rekey_profile_pics.py            # dry-run, just report
    python3 scripts/rekey_profile_pics.py --apply    # actually re-key

Exits 0 on success.
"""

import argparse
import asyncio
import os
import sys
from urllib.parse import urlparse

# Allow running as `python3 scripts/rekey_profile_pics.py`
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from minio.commonconfig import CopySource
from minio.error import S3Error
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.user import StudentProfile, User
from app.services import storage_service


def parse_bucket_key(url: str):
    """Extract (bucket, key) from a stored profile_pic_url, or None.

    Handles the media-proxy form (https://host/api/media/{bucket}/{key}), legacy
    direct MinIO URLs (https://host/{bucket}/{key}), and bare "bucket/key"."""
    if not url:
        return None
    if url.startswith("http"):
        path = urlparse(url).path.lstrip("/")
        if path.startswith("api/media/"):
            path = path[len("api/media/"):]
    else:
        path = url.lstrip("/")
    parts = path.split("/", 1)
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return None
    return parts[0], parts[1]


def is_predictable_key(key: str) -> bool:
    """True if the object still uses the old fixed ``.../avatar.<ext>`` filename."""
    filename = key.rsplit("/", 1)[-1]
    stem = filename.rsplit(".", 1)[0]
    return stem == "avatar"


def object_exists(bucket: str, key: str) -> bool:
    client = storage_service._get_client()
    try:
        client.stat_object(bucket, key)
        return True
    except S3Error as e:
        if getattr(e, "code", "") in ("NoSuchKey", "NoSuchObject", "NoSuchBucket"):
            return False
        raise


async def rekey(apply: bool):
    client = storage_service._get_client()

    # Group DB rows by the object they reference so a student's two rows
    # (User + StudentProfile, same key) migrate to one new key together.
    #   (bucket, key) -> {"rows": [(model_label, row)], "prefix": str, "ext": str}
    groups: dict[tuple[str, str], dict] = {}

    async with AsyncSessionLocal() as session:
        for label, model in (("User", User), ("StudentProfile", StudentProfile)):
            rows = (
                await session.execute(
                    select(model).where(model.profile_pic_url.is_not(None))
                )
            ).scalars().all()
            for row in rows:
                parsed = parse_bucket_key(row.profile_pic_url)
                if parsed is None:
                    print(f"  [skip] {label}#{row.id}: can't parse url -> {row.profile_pic_url}")
                    continue
                groups.setdefault(parsed, {"rows": []})["rows"].append((label, row))

        rekeyed = already_random = missing = 0
        old_objects_to_delete: list[tuple[str, str]] = []

        for (bucket, key), info in groups.items():
            if not is_predictable_key(key):
                already_random += 1
                continue
            if not object_exists(bucket, key):
                missing += 1
                print(f"  [dangling] {bucket}/{key} — object gone, left for null script")
                continue

            prefix = key.rsplit("/", 1)[0]
            ext = key.rsplit(".", 1)[-1]
            new_key = storage_service.profile_object_key(prefix, ext)
            new_url = storage_service.get_public_url(bucket, new_key)
            row_labels = ", ".join(f"{l}#{r.id}" for l, r in info["rows"])
            action = "WOULD re-key" if not apply else "re-keyed"
            print(f"  [{action}] {bucket}/{key} -> {new_key}  ({row_labels})")

            if apply:
                # Server-side copy first; only repoint the DB once it exists.
                client.copy_object(bucket, new_key, CopySource(bucket, key))
                for _label, row in info["rows"]:
                    row.profile_pic_url = new_url
                old_objects_to_delete.append((bucket, key))
            rekeyed += 1

        if apply:
            await session.commit()
            # Delete old predictable objects only after the DB no longer points
            # at them, so a failure here can only orphan (never break a url).
            for bucket, key in old_objects_to_delete:
                try:
                    client.remove_object(bucket, key)
                except S3Error as e:
                    print(f"  [warn] couldn't delete old object {bucket}/{key}: {e}")

    print()
    print(f"Re-keyed{'' if apply else ' (would)'}: {rekeyed}")
    print(f"Already random (skipped):  {already_random}")
    if missing:
        print(f"Dangling (left as-is):     {missing}")
    if not apply:
        print("\nDry run — nothing changed. Re-run with --apply to commit.")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apply", action="store_true",
                   help="Commit the changes (default is a dry run).")
    args = p.parse_args()
    asyncio.run(rekey(apply=args.apply))


if __name__ == "__main__":
    main()
