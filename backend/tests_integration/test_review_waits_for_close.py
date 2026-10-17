"""
The answer key stays hidden until the test closes for everyone.

A student who finished early could open the review straight away and read every
correct answer while the test was still open for the rest of the class — found
2026-10-17, with a day still to run. The review now gives the score and the
student's own answers while the test is open, says when the answers appear, and
shows the key once it has closed.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth
from .test_realtime_delivery import _mint_access_token

QUESTIONS = [
    {"id": 1, "type": "mcq", "marks": 1, "answer": "A", "question": "Powerhouse of the cell?",
     "options": {"A": "Mitochondria", "B": "Nucleus", "C": "Ribosome", "D": "Golgi"}},
    {"id": 2, "type": "fill_blank", "marks": 1, "answer": "photosynthesis",
     "question": "Plants make food by ____."},
]


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


@pytest.fixture
def finished_early(api, two_schools, request):
    school = two_schools["a"]
    student = asyncio.run(_make_student(school["id"], f"{PREFIX}_rv_{request.node.name[5:]}", new=True))
    test_id = asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, expires_at, school_id)
           VALUES ($1, $2, 8, 'science', 'online', $3::json, 2, 10, true,
                   now() + interval '1 day', $4) RETURNING id""",
        f"{PREFIX} review", school["teacher_id"], json.dumps(QUESTIONS), school["id"]))
    headers = auth(_mint_access_token(student))
    assert api.post(f"/api/student/tests/{test_id}/start", headers=headers).status_code == 200
    assert api.post(f"/api/student/tests/{test_id}/submit", headers=headers,
                    json={"answers": {"1": "B", "2": "photosynthesis"}}).status_code == 201
    return test_id, headers


def test_while_open_the_review_has_no_answer_key(api, finished_early):
    test_id, headers = finished_early
    r = api.get(f"/api/student/tests/{test_id}/review", headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["answers_available_at"]
    assert all("answer" not in q for q in body["questions"]), body["questions"]
    assert "Mitochondria" in r.text  # the questions and options are still there
    assert body["student_answers"] == {"1": "B", "2": "photosynthesis"}
    assert body["score"] is not None


def test_once_closed_the_key_is_shown(api, finished_early):
    test_id, headers = finished_early
    asyncio.run(_sql("UPDATE tests SET expires_at = now() - interval '1 minute' WHERE id = $1", test_id))
    r = api.get(f"/api/student/tests/{test_id}/review", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["answers_available_at"] is None
    assert all("answer" in q for q in r.json()["questions"])


def test_no_test_list_carries_the_answer_key(api, two_schools, finished_early):
    # The completed list returned the stored test, key included, while it was
    # open — and the parent's test list and dashboard returned the key for every
    # published test, taken or not.
    test_id, headers = finished_early
    r = api.get("/api/student/tests/completed", headers=headers)
    assert r.status_code == 200
    assert all("answer" not in q for t in r.json() for q in (t.get("questions") or []))

    school = two_schools["a"]
    student_id = asyncio.run(_sql(
        "SELECT student_id FROM test_submissions WHERE test_id = $1", test_id))
    parent = asyncio.run(_sql(
        """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
           VALUES ($1, 'x', 'parent', $2, true, true) RETURNING id""",
        f"{PREFIX}_rv_parent_{test_id}", school["id"]))
    asyncio.run(_sql("UPDATE student_profiles SET parent_user_id = $1 WHERE user_id = $2",
                     parent, student_id))
    parent_headers = auth(_mint_access_token(parent))
    for path, key in (("/api/parent/child/tests", None), ("/api/parent/dashboard-summary", "child_tests")):
        r = api.get(path, headers=parent_headers, params={"child_id": student_id})
        assert r.status_code == 200, r.text
        tests = r.json() if key is None else r.json()[key]
        assert tests, path
        assert all("answer" not in q for t in tests for q in (t.get("questions") or [])), path


def test_the_dashboard_does_not_send_the_key_of_an_untaken_test(api, two_schools, request):
    school = two_schools["a"]
    student = asyncio.run(_make_student(school["id"], f"{PREFIX}_rv_dash", new=True))
    asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, expires_at, school_id)
           VALUES ($1, $2, 8, 'science', 'online', $3::json, 2, 10, true,
                   now() + interval '1 day', $4)""",
        f"{PREFIX} untaken", school["teacher_id"], json.dumps(QUESTIONS), school["id"]))
    r = api.get("/api/student/dashboard-summary", headers=auth(_mint_access_token(student)))
    assert r.status_code == 200, r.text
    pending = r.json()["pending_tests"]
    assert any(t["title"] == f"{PREFIX} untaken" for t in pending)
    for key in ("pending_tests", "offline_tests"):
        assert all("answer" not in q for t in r.json()[key] for q in (t.get("questions") or [])), key
