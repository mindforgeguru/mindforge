"""
MinIO (S3-compatible) object storage wrapper.
Handles file uploads and pre-signed URL generation.
"""

import io
import json
import logging
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

# Buckets that should allow anonymous (public) GET access
PUBLIC_READ_BUCKETS = [
    settings.MINIO_BUCKET_PROFILES,
]


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
    """Create required buckets if they don't exist and apply public-read policy."""
    for bucket in REQUIRED_BUCKETS:
        try:
            if not client.bucket_exists(bucket):
                client.make_bucket(bucket)
                logger.info(f"Created MinIO bucket: {bucket}")
        except S3Error as e:
            logger.error(f"MinIO bucket setup error for '{bucket}': {e}")

    for bucket in PUBLIC_READ_BUCKETS:
        try:
            policy = json.dumps({
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"AWS": ["*"]},
                    "Action": ["s3:GetObject"],
                    "Resource": [f"arn:aws:s3:::{bucket}/*"],
                }],
            })
            client.set_bucket_policy(bucket, policy)
            logger.info(f"Set public-read policy on bucket: {bucket}")
        except S3Error as e:
            logger.error(f"MinIO policy error for '{bucket}': {e}")


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
