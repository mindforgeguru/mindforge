"""The Redis subscriber must survive a dropped connection.

It used to end on the first ConnectionError (Redis restarted), which silently
stopped every live update until the backend restarted. Now it re-subscribes.
"""

import asyncio
import importlib.util
import json
import pathlib

import pytest

# conftest stubs `app.core.redis_client` for the rest of the suite; load the
# real module from its file under a private name.
_path = pathlib.Path(__file__).resolve().parents[1] / "app" / "core" / "redis_client.py"
_spec = importlib.util.spec_from_file_location("_real_redis_client", _path)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
RedisManager = _mod.RedisManager


class _FakePubSub:
    def __init__(self, script):
        self._script = script  # list of messages, or an exception to raise
        self.closed = False

    async def subscribe(self, channel):
        pass

    async def listen(self):
        for item in self._script:
            if isinstance(item, Exception):
                raise item
            yield item
        # Keep the stream open, like a healthy subscription.
        await asyncio.Event().wait()

    async def aclose(self):
        self.closed = True


class _FakeClient:
    def __init__(self, scripts):
        self._scripts = list(scripts)
        self.subscriptions = 0
        self.pubsubs = []

    def pubsub(self):
        self.subscriptions += 1
        ps = _FakePubSub(self._scripts.pop(0))
        self.pubsubs.append(ps)
        return ps


class _FakeWS:
    def __init__(self):
        self.to_user = []

    async def broadcast_to_user(self, user_id, payload):
        self.to_user.append((user_id, payload))


def _msg(user_id):
    return {"type": "message",
            "data": json.dumps({"target_type": "user", "user_id": user_id,
                                "payload": {"n": user_id}})}


@pytest.mark.asyncio
async def test_resubscribes_after_connection_drop_and_keeps_delivering():
    client = _FakeClient([
        [_msg(1), ConnectionError("Connection closed by server.")],
        [_msg(2)],
    ])
    mgr = RedisManager()
    mgr._client = client
    ws = _FakeWS()

    task = asyncio.create_task(mgr.start_subscriber(ws, max_backoff=0.01))
    try:
        for _ in range(200):
            if len(ws.to_user) == 2:
                break
            await asyncio.sleep(0.01)
    finally:
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    assert ws.to_user == [(1, {"n": 1}), (2, {"n": 2})]
    assert client.subscriptions == 2
    assert client.pubsubs[0].closed  # the dead subscription was cleaned up


@pytest.mark.asyncio
async def test_cancel_stops_the_subscriber():
    client = _FakeClient([[]])
    mgr = RedisManager()
    mgr._client = client
    task = asyncio.create_task(mgr.start_subscriber(_FakeWS()))
    await asyncio.sleep(0.01)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert client.subscriptions == 1
