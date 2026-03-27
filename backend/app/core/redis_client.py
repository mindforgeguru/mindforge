"""
Redis connection and pub/sub helpers.
Uses redis-py async client for both regular commands and pub/sub messaging.
"""

import json
import logging
import asyncio
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


redis_manager = RedisManager()
