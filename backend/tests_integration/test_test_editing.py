"""
A test's questions are locked once a student has started it.

The question editor accepted changes at any time: once students had submitted,
their scores no longer matched the paper (the review showed the new key beside
the old score), and anyone mid-attempt was graded against a key they never saw.
Its body was also an untyped dict, so a question that was not an object, or
marks that were not a number, was a 500. Found 2026-10-18.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth
from .test_realtime_delivery import _mint_access_token

Q = {"type": "mcq", "marks": 1, "answer": "A", "question": "Pick A",
     "options": {"A": "Right", "B": "Wrong"}}


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


@pytest.fixture
def test_id(two_schools, request):
    school = two_schools["a"]
    return asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, expires_at, school_id)
           VALUES ($1, $2, 8, 'maths', 'online', $3::json, 1, 10, true,
                   now() + interval '1 day', $4) RETURNING id""",
        f"{PREFIX} edit {request.node.name[5:30]}", school["teacher_id"],
        json.dumps([{"id": 1, **Q}]), school["id"]))


def _edit(api, two_schools, test_id, questions):
    return api.put(f"/api/teacher/tests/{test_id}/questions",
                   headers=auth(two_schools["a"]["teacher_token"]), json={"questions": questions})


def test_an_untouched_test_can_be_edited(api, two_schools, test_id):
    r = _edit(api, two_schools, test_id, [Q, {**Q, "marks": 2}])
    assert r.status_code == 200, r.text
    assert r.json()["total_marks"] == 3


def test_once_a_student_has_started_the_questions_are_locked(api, two_schools, test_id):
    student = asyncio.run(_make_student(two_schools["a"]["id"], f"{PREFIX}_edit_s", new=True))
    headers = auth(_mint_access_token(student))
    assert api.post(f"/api/student/tests/{test_id}/start", headers=headers).status_code == 200
    r = _edit(api, two_schools, test_id, [{**Q, "answer": "B"}])
    assert r.status_code == 409, r.text
    key = asyncio.run(_sql("SELECT questions->0->>'answer' FROM tests WHERE id = $1", test_id))
    assert key == "A"


@pytest.mark.parametrize("questions", [["oops"], [{"question": "q", "marks": "five"}],
                                       [Q] * 201],
                         ids=["not an object", "marks not a number", "too many"])
def test_a_malformed_edit_is_422(api, two_schools, test_id, questions):
    assert _edit(api, two_schools, test_id, questions).status_code == 422
