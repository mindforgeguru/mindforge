"""
Redis connection and pub/sub helpers.
Uses redis-py async client for both regular commands and pub/sub messaging.
"""

import json
import logging
from typing import TYPE_CHECKING

import redis.asyncio as aioredis

from app.core.config import settings

if TYPE_CHECKING:
    from app.websockets.manager import WebSocketManager

logger = logging.getLogger(__name__)

REDIS_CHANNEL = "mindforge:events"


class RedisManager:
    def __init__(self):
        self._client: aioredis.Redis | None = None
        self._pubsub: aioredis.client.PubSub | None = None

    async def connect(self):
        """Establish Redis connection."""
        self._client = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
        await self._client.ping()
        logger.info("Redis connected successfully.")

    async def disconnect(self):
        """Close Redis connection."""
        if self._pubsub:
            await self._pubsub.unsubscribe(REDIS_CHANNEL)
            await self._pubsub.close()
        if self._client:
            await self._client.aclose()
        logger.info("Redis disconnected.")

    async def publish(self, event: dict):
        """Publish an event dict to the shared Redis channel."""
        if self._client is None:
            logger.warning("Redis client not connected; skipping publish.")
            return
        await self._client.publish(REDIS_CHANNEL, json.dumps(event))

    async def start_subscriber(self, ws_manager: "WebSocketManager"):
        """
        Subscribe to Redis channel and fan out messages to WebSocket clients.
        This coroutine runs as a background task for the lifetime of the server.
        """
        self._pubsub = self._client.pubsub()
        await self._pubsub.subscribe(REDIS_CHANNEL)
        logger.info(f"Redis subscriber listening on channel: {REDIS_CHANNEL}")

        async for message in self._pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                event = json.loads(message["data"])
                target_type = event.get("target_type")  # "user" | "grade" | "broadcast"
                payload = event.get("payload", {})

                if target_type == "user":
                    user_id = event.get("user_id")
                    if user_id is not None:
                        await ws_manager.broadcast_to_user(user_id, payload)
                elif target_type == "grade":
                    grade = event.get("grade")
                    if grade is not None:
                        await ws_manager.broadcast_to_grade(grade, payload)
                elif target_type == "broadcast":
                    await ws_manager.broadcast_all(payload)
            except Exception as e:
                logger.error(f"Redis subscriber error: {e}")

    async def set_cache(self, key: str, value: str, expire_seconds: int = 3600):
        """Set a cache value with optional TTL."""
        if self._client:
            await self._client.set(key, value, ex=expire_seconds)

    async def get_cache(self, key: str) -> str | None:
        """Get a cached value."""
        if self._client:
            return await self._client.get(key)
        return None

    async def delete_cache(self, key: str):
        """Delete a cache entry."""
        if self._client:
            await self._client.delete(key)

    async def rate_limit(self, key: str, max_attempts: int, window_seconds: int) -> bool:
        """Increment a counter for `key`. Returns True if the limit is exceeded.
        Fails open (returns False) when Redis is unavailable."""
        if self._client is None:
            return False
        count = await self._client.incr(key)
        if count == 1:
            await self._client.expire(key, window_seconds)
        return count > max_attempts

    # ── Refresh-token JTI blacklist ─────────────────────────────────────────

    async def revoke_jti(self, jti: str, ttl_seconds: int) -> None:
        """Mark a refresh-token JTI as used. TTL should match the token's remaining lifetime."""
        if self._client:
            await self._client.set(f"revoked_jti:{jti}", "1", ex=ttl_seconds)

    async def is_jti_revoked(self, jti: str) -> bool:
        """Return True if this JTI has been blacklisted.

        Fails open (returns False) when Redis is unavailable or errors —
        consistent with rate_limit() and the access-token check. A transient
        Redis fault must not 500 every authenticated request; the trade-off is
        that a revoked refresh token may be honoured until it expires during an
        outage."""
        if self._client is None:
            return False
        try:
            return await self._client.exists(f"revoked_jti:{jti}") == 1
        except Exception as e:
            logger.warning("Redis is_jti_revoked failed, failing open: %s", e)
            return False

    # ── Access-token revocation (logout blacklist) ─────────────────────────

    async def revoke_access_jti(self, jti: str, ttl_seconds: int) -> None:
        """Blacklist an access token JTI until it naturally expires."""
        if self._client:
            await self._client.set(f"revoked_access:{jti}", "1", ex=ttl_seconds)

    async def is_access_jti_revoked(self, jti: str) -> bool:
        """Return True if this access token has been revoked (user logged out).

        Fails open (returns False) when Redis is unavailable or errors, so a
        transient Redis fault doesn't 500 every authenticated request. Access
        tokens are short-lived (≤ JWT_EXPIRE_MINUTES), so the window in which a
        logged-out token could be honoured during an outage is bounded."""
        if self._client is None:
            return False
        try:
            return await self._client.exists(f"revoked_access:{jti}") == 1
        except Exception as e:
            logger.warning("Redis is_access_jti_revoked failed, failing open: %s", e)
            return False

    # ── Idempotency keys (replay protection) ──────────────────────────────

    async def consume_idempotency_key(self, key: str, ttl_seconds: int = 60) -> bool:
        """
        Atomically claim an idempotency key.
        Returns True if the key was fresh (first time seen) — request should proceed.
        Returns False if the key already exists — this is a duplicate/replayed request.
        """
        if self._client is None:
            return True  # fail open when Redis is unavailable
        # SET NX: only sets if not already present; returns True on success
        result = await self._client.set(f"idem:{key}", "1", ex=ttl_seconds, nx=True)
        return result is True  # None means key already existed

    # ── Per-user MPIN brute-force lockout ──────────────────────────────────

    _LOCKOUT_MAX   = 5          # failed attempts before lockout
    _LOCKOUT_TTL   = 15 * 60   # 15 minutes in seconds

    async def record_failed_login(self, user_id: int) -> bool:
        """Increment the failed-login counter for user_id.
        Returns True if the account should now be locked out."""
        if self._client is None:
            return False
        key = f"failed_logins:{user_id}"
        count = await self._client.incr(key)
        if count == 1:
            await self._client.expire(key, self._LOCKOUT_TTL)
        if count >= self._LOCKOUT_MAX:
            await self._client.set(f"lockout:user:{user_id}", "1", ex=self._LOCKOUT_TTL)
            return True
        return False

    async def is_user_locked_out(self, user_id: int) -> bool:
        """Return True if this user is currently locked out."""
        if self._client is None:
            return False
        return await self._client.exists(f"lockout:user:{user_id}") == 1

    async def clear_failed_logins(self, user_id: int) -> None:
        """Clear the failed-login counter after a successful login."""
        if self._client:
            await self._client.delete(f"failed_logins:{user_id}")
            await self._client.delete(f"lockout:user:{user_id}")


redis_manager = RedisManager()
