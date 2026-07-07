"""
MinIO (S3-compatible) object storage wrapper.
Handles file uploads and pre-signed URL generation.
"""

import io
import logging
import secrets
from typing import Optional

from minio import Minio
from minio.error import S3Error

from app.core.config import settings

logger = logging.getLogger(__name__)

_minio_client: Optional[Minio] = None

# Buckets that must exist on startup
REQUIRED_BUCKETS = [
    settings.MINIO_BUCKET_TESTS,
    settings.MINIO_BUCKET_PROFILES,
    settings.MINIO_BUCKET_PDFS,
    settings.MINIO_BUCKET_DATABASE,
]

# All buckets are private. External access to profile pics goes through the
# /api/media/{bucket}/{key} proxy in main.py — never directly. The proxy is
# unauthenticated (so <img>/CachedNetworkImage can load without a token), so
# object keys MUST be unguessable — see profile_object_key(). Keeping the
# bucket private is defence-in-depth in case MinIO is ever exposed publicly
# (Railway domain, port forward, etc.).


def _get_client() -> Minio:
    """Lazily initialize and return the MinIO client."""
    global _minio_client
    if _minio_client is None:
        _minio_client = Minio(
            endpoint=settings.MINIO_ENDPOINT,
            access_key=settings.MINIO_ACCESS_KEY,
            secret_key=settings.MINIO_SECRET_KEY,
            secure=settings.MINIO_USE_SSL,
        )
        _ensure_buckets(_minio_client)
    return _minio_client


def _ensure_buckets(client: Minio):
    """Create required buckets if missing and force every bucket to private.

    Revoking any public-read policy lingering from older boots — the proxy
    in main.py is the only legitimate external access path to objects.
    """
    for bucket in REQUIRED_BUCKETS:
        try:
            if not client.bucket_exists(bucket):
                client.make_bucket(bucket)
                logger.info(f"Created MinIO bucket: {bucket}")
        except S3Error as e:
            logger.error(f"MinIO bucket setup error for '{bucket}': {e}")

        try:
            client.delete_bucket_policy(bucket)
        except S3Error as e:
            # NoSuchBucketPolicy is the expected case (already private) — ignore.
            if getattr(e, "code", "") != "NoSuchBucketPolicy":
                logger.warning(f"Could not clear bucket policy on '{bucket}': {e}")


def get_public_url(bucket: str, key: str) -> str:
    """
    Return a permanent public URL for an object served through the backend media proxy.
    The URL never contains internal hostnames (minio:9000, minio.railway.internal, etc.)
    """
    base = settings.BACKEND_PUBLIC_URL.rstrip("/")
    return f"{base}/api/media/{bucket}/{key}"


async def upload_file(
    bucket: str,
    key: str,
    data: bytes,
    content_type: str = "application/octet-stream",
) -> str:
    """
    Upload raw bytes to MinIO.
    Returns the object key (use get_presigned_url to get a downloadable URL).
    """
    client = _get_client()
    stream = io.BytesIO(data)
    length = len(data)

    # Auto-detect content type from key extension
    if key.endswith(".pdf"):
        content_type = "application/pdf"
    elif key.endswith((".jpg", ".jpeg")):
        content_type = "image/jpeg"
    elif key.endswith(".png"):
        content_type = "image/png"

    try:
        client.put_object(
            bucket_name=bucket,
            object_name=key,
            data=stream,
            length=length,
            content_type=content_type,
        )
        logger.info(f"Uploaded to MinIO: {bucket}/{key}")
        # Return a path reference; can be resolved to URL via get_presigned_url
        return f"{bucket}/{key}"
    except S3Error as e:
        logger.error(f"MinIO upload error: {e}")
        raise


async def get_presigned_url(
    bucket: str,
    key: str,
    expires_seconds: int = 3600,
) -> str:
    """
    Generate a pre-signed URL for downloading a file from MinIO.
    The URL is valid for `expires_seconds` seconds (default 1 hour).
    """
    from datetime import timedelta

    client = _get_client()
    try:
        url = client.presigned_get_object(
            bucket_name=bucket,
            object_name=key,
            expires=timedelta(seconds=expires_seconds),
        )
        return url
    except S3Error as e:
        logger.error(f"MinIO presigned URL error: {e}")
        raise


async def download_file(bucket: str, key: str) -> bytes:
    """Download a file from MinIO and return its raw bytes."""
    client = _get_client()
    try:
        response = client.get_object(bucket_name=bucket, object_name=key)
        data = response.read()
        response.close()
        response.release_conn()
        return data
    except S3Error as e:
        logger.error(f"MinIO download error: {e}")
        raise


async def delete_file(bucket: str, key: str):
    """Delete an object from MinIO."""
    client = _get_client()
    try:
        client.remove_object(bucket_name=bucket, object_name=key)
        logger.info(f"Deleted from MinIO: {bucket}/{key}")
    except S3Error as e:
        logger.error(f"MinIO delete error: {e}")
        raise


def profile_object_key(prefix: str, ext: str) -> str:
    """Build an *unguessable* object key for a profile picture.

    The old scheme used a predictable path (``profiles/{user_id}/avatar.jpg``),
    which let anyone enumerate every user's photo through the media proxy just
    by iterating sequential user ids. Embedding a random 128-bit token in the
    filename makes enumeration infeasible while keeping the per-user folder for
    housekeeping. ``prefix`` is the folder (e.g. ``profiles/teacher/7``).
    """
    token = secrets.token_urlsafe(16)  # 128 bits of entropy
    return f"{prefix.rstrip('/')}/{token}.{ext}"


def parse_media_url(url: Optional[str]) -> Optional[tuple[str, str]]:
    """Extract ``(bucket, key)`` from a backend media-proxy URL, or None.

    Handles the canonical ``.../api/media/{bucket}/{key}`` form regardless of
    host so old objects can be located for deletion during a re-upload."""
    if not url:
        return None
    marker = "/api/media/"
    idx = url.find(marker)
    if idx == -1:
        return None
    rest = url[idx + len(marker):]
    bucket, sep, key = rest.partition("/")
    if not sep or not bucket or not key:
        return None
    return bucket, key


async def delete_by_media_url(url: Optional[str]) -> None:
    """Best-effort delete of the object referenced by a media-proxy URL.

    Used when a user replaces their profile picture so the previous (and, for
    legacy accounts, predictably-named) object doesn't linger and stay
    harvestable. Never raises — a missing/at-rest object must not fail the
    upload it's cleaning up after."""
    parsed = parse_media_url(url)
    if not parsed:
        return
    try:
        await delete_file(*parsed)
    except Exception as e:  # noqa: BLE001 — cleanup must not break the caller
        logger.warning(f"Old profile object cleanup skipped: {e}")
