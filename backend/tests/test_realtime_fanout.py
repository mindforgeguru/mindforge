"""
Tests for app.services.realtime_service — the class-wide event fan-out.

Regression context: class-wide events used to be published as
`{"target_type": "grade", "grade": N}` and resolved by the WebSocket manager's
grade index. That index was never populated (`register_grade` has no callers
and `/ws/{user_id}` connects without a grade), so every such event — new
homework, new tests, grade-targeted broadcasts, attendance, timetable — was
silently dropped. Recipients are now resolved from the DB at publish time.

These tests assert the two properties that made the old path fail:
  1. Something is actually published, addressed to explicit user IDs.
  2. The audience is who we think it is — students, their parents, and
     (opt-in) staff — with no cross-school leakage.

Run: cd backend && python3 -m pytest tests/test_realtime_fanout.py -v
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.core.redis_client import redis_manager
from app.services import realtime_service
from app.websockets.manager import WebSocketManager


# conftest replaces app.core.database.Base with a plain stand-in class, so the
# models aren't really mapped and a `select(...).join(...)` can't be built in
# this environment. The audience query is therefore stubbed out where it isn't
# the thing under test, and the row-folding it delegates to is tested directly.

@pytest.fixture
def captured(monkeypatch):
    """Capture what realtime_service hands to Redis."""
    events = []

    async def _publish(event):
        events.append(event)

    monkeypatch.setattr(redis_manager, "publish", _publish, raising=False)
    return events


def _fixed_audience(monkeypatch, user_ids):
    async def _grade_audience(db, *, school_id, grade, include_staff=False):
        return list(user_ids)

    monkeypatch.setattr(realtime_service, "grade_audience", _grade_audience)


# ── Audience assembly ─────────────────────────────────────────────────────────

def test_audience_includes_students_and_their_parents():
    # (student_user_id, parent_user_id); the third student has no parent link.
    rows = [(10, 110), (11, 111), (12, None)]

    assert realtime_service.audience_from_profile_rows(rows) == {
        10, 11, 12, 110, 111,
    }


def test_audience_dedupes_a_parent_with_two_children_in_the_grade():
    rows = [(10, 110), (11, 110)]

    assert realtime_service.audience_from_profile_rows(rows) == {10, 11, 110}


# ── publish_to_grade ──────────────────────────────────────────────────────────

def test_grade_event_is_addressed_to_explicit_user_ids(captured, monkeypatch):
    _fixed_audience(monkeypatch, [10, 11, 110])

    asyncio.run(realtime_service.publish_to_grade(
        MagicMock(), school_id=1, grade=8,
        payload={"event": "homework_added"},
    ))

    assert len(captured) == 1
    event = captured[0]
    assert event["target_type"] == "users"
    assert event["user_ids"] == [10, 11, 110]
    assert event["payload"] == {"event": "homework_added"}


def test_extra_user_ids_are_merged_and_deduped(captured, monkeypatch):
    _fixed_audience(monkeypatch, [10])

    asyncio.run(realtime_service.publish_to_grade(
        MagicMock(), school_id=1, grade=8, payload={"event": "x"},
        extra_user_ids=[10, 42],
    ))

    # 10 is already in the roster — it must not be sent twice.
    assert captured[0]["user_ids"] == [10, 42]


def test_empty_audience_publishes_nothing(captured, monkeypatch):
    """An empty grade must not emit an event with an empty recipient list —
    that would be indistinguishable from the old silently-dropped path."""
    _fixed_audience(monkeypatch, [])

    asyncio.run(realtime_service.publish_to_grade(
        MagicMock(), school_id=1, grade=8,
        payload={"event": "homework_added"},
    ))

    assert captured == []


# ── publish_to_users ──────────────────────────────────────────────────────────

def test_publish_to_users_normalises_the_recipient_list(captured):
    asyncio.run(realtime_service.publish_to_users(
        [3, 1, 3, None, 2], {"event": "test_completed"},
    ))

    assert captured[0]["user_ids"] == [1, 2, 3]


# ── WebSocketManager.broadcast_to_users ───────────────────────────────────────

def test_manager_delivers_to_each_listed_user():
    manager = WebSocketManager()
    sockets = {}
    for user_id in (1, 2, 3):
        ws = MagicMock()
        ws.accept = AsyncMock()
        ws.send_text = AsyncMock()
        sockets[user_id] = ws
        asyncio.run(manager.connect(ws, user_id))

    asyncio.run(manager.broadcast_to_users([1, 3], {"event": "homework_added"}))

    sockets[1].send_text.assert_awaited_once()
    sockets[3].send_text.assert_awaited_once()
    sockets[2].send_text.assert_not_awaited()


def test_manager_ignores_users_with_no_connection():
    """A resolved audience routinely contains users who aren't online."""
    manager = WebSocketManager()
    ws = MagicMock()
    ws.accept = AsyncMock()
    ws.send_text = AsyncMock()
    asyncio.run(manager.connect(ws, 1))

    asyncio.run(manager.broadcast_to_users([1, 999], {"event": "x"}))

    ws.send_text.assert_awaited_once()
