"""Old-test-paper upload on the real stack: fast response, background classify.

The unit tests (tests/test_old_test_upload.py) pin the logic with fakes. This
proves the wiring: FastAPI actually runs the background task after the
response, the task reaches the real database, and its event reaches the
teacher's socket — and nobody else's.

The local AI keys may be absent or over quota, so this does not assert on the
classification itself; a scan that fails still completes and still notifies.
"""

import asyncio
import json
import time

import websockets

from .conftest import BASE_URL, PREFIX, auth

WS_BASE = BASE_URL.replace("http://", "ws://").replace("https://", "wss://")
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"


def _me(api, token):
    r = api.get("/api/auth/me", headers=auth(token))
    assert r.status_code == 200, r.text
    return r.json()["id"]


async def _collect_events(user_id, token, trigger, want, timeout):
    """Connect, run `trigger()` once connected, collect `event` names."""
    seen = []
    async with websockets.connect(
        f"{WS_BASE}/ws/{user_id}?token={token}", open_timeout=10
    ) as ws:
        result = await asyncio.get_running_loop().run_in_executor(None, trigger)
        deadline = time.monotonic() + timeout
        while seen.count(want) < 2 and time.monotonic() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), deadline - time.monotonic())
            except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed):
                break
            try:
                seen.append(json.loads(raw).get("event"))
            except (ValueError, AttributeError):
                pass
    return result, seen


def test_upload_returns_rows_then_classifies_in_background(api, two_schools):
    token = two_schools["a"]["teacher_token"]
    teacher_id = _me(api, token)
    timings = {}

    def upload():
        files = [
            ("files", (f"{PREFIX}_paper1.pdf", PDF, "application/pdf")),
            ("files", (f"{PREFIX}_paper2.pdf", PDF, "application/pdf")),
        ]
        start = time.monotonic()
        r = api.post("/api/teacher/database/old-tests/upload",
                     headers=auth(token), files=files)
        timings["upload"] = time.monotonic() - start
        return r

    r, events = asyncio.run(_collect_events(
        teacher_id, token, upload, "old_test_papers_classified", timeout=150,
    ))

    assert r.status_code == 200, r.text
    rows = r.json()
    assert [row["original_filename"] for row in rows] == [
        f"{PREFIX}_paper1.pdf", f"{PREFIX}_paper2.pdf",
    ]
    assert all(row["grade"] is None for row in rows), "response waited on the AI"
    assert timings["upload"] < 10, f"upload took {timings['upload']:.1f}s"

    assert events.count("old_test_papers_classified") == 2, (
        f"background classification did not notify the teacher: {events}"
    )

    listed = api.get("/api/teacher/database/old-tests", headers=auth(token)).json()
    assert {row["id"] for row in rows} <= {row["id"] for row in listed}


def test_classification_event_does_not_reach_another_teacher(api, two_schools):
    uploader = two_schools["a"]["teacher_token"]
    other = two_schools["b"]["teacher_token"]
    other_id = _me(api, other)

    def upload():
        return api.post(
            "/api/teacher/database/old-tests/upload", headers=auth(uploader),
            files=[("files", (f"{PREFIX}_paper3.pdf", PDF, "application/pdf"))],
        )

    r, events = asyncio.run(_collect_events(
        other_id, other, upload, "old_test_papers_classified", timeout=45,
    ))
    assert r.status_code == 200, r.text
    assert "old_test_papers_classified" not in events
