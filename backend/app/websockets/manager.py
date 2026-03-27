"""
WebSocket Connection Manager for MIND FORGE.

Manages per-user and per-grade WebSocket connections.
Works alongside Redis pub/sub so events are fan-out across
multiple backend instances (horizontal scaling).
"""

import json
import logging
from collections import defaultdict
from typing import Dict, List, Set

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class WebSocketManager:
    """
    Maintains two indexes:
    - _user_connections: user_id → set of active WebSockets (multiple tabs)
    - _grade_connections: grade → set of user_ids in that grade
    """

    def __init__(self):
        # user_id → list of WebSocket connections (user may have multiple tabs)
        self._user_connections: Dict[int, List[WebSocket]] = defaultdict(list)
        # grade → set of user_ids currently connected in that grade
        self._grade_users: Dict[int, Set[int]] = defaultdict(set)

    async def connect(self, websocket: WebSocket, user_id: int, grade: int = None):
        """Accept and register a new WebSocket connection."""
        await websocket.accept()
        self._user_connections[user_id].append(websocket)
        if grade is not None:
            self._grade_users[grade].add(user_id)
        logger.info(f"WebSocket connected: user_id={user_id}, grade={grade}")

    async def disconnect(self, websocket: WebSocket, user_id: int, grade: int = None):
        """Remove a WebSocket connection from all indexes."""
        connections = self._user_connections.get(user_id, [])
        if websocket in connections:
            connections.remove(websocket)
        if not connections:
            self._user_connections.pop(user_id, None)
        if grade is not None:
            grade_users = self._grade_users.get(grade, set())
            if user_id in grade_users and user_id not in self._user_connections:
                grade_users.discard(user_id)
        logger.info(f"WebSocket disconnected: user_id={user_id}")

    async def broadcast_to_user(self, user_id: int, event: dict):
        """
        Send an event to ALL WebSocket connections for a specific user.
        Removes stale connections if send fails.
        """
        message = json.dumps(event)
        connections = self._user_connections.get(user_id, [])
        dead = []
        for ws in connections:
            try:
                await ws.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send to user {user_id}: {e}")
                dead.append(ws)
        for ws in dead:
            if ws in connections:
                connections.remove(ws)

    async def broadcast_to_grade(self, grade: int, event: dict):
        """
        Send an event to all connected users in a specific grade.
        Fetches all user_ids registered under that grade.
        """
        user_ids = list(self._grade_users.get(grade, set()))
        for user_id in user_ids:
            await self.broadcast_to_user(user_id, event)

    async def broadcast_all(self, event: dict):
        """Send an event to every connected WebSocket client."""
        message = json.dumps(event)
        all_user_ids = list(self._user_connections.keys())
        for user_id in all_user_ids:
            await self.broadcast_to_user(user_id, event)

    def register_grade(self, user_id: int, grade: int):
        """Register a user under a grade bucket (used when grade is known after auth)."""
        self._grade_users[grade].add(user_id)

    @property
    def active_connections_count(self) -> int:
        return sum(len(conns) for conns in self._user_connections.values())

    @property
    def connected_users(self) -> List[int]:
        return list(self._user_connections.keys())


# Singleton instance shared across the application
ws_manager = WebSocketManager()
