"""
A generated question always carries a numeric `marks`.

The models type numbers as strings ("2"), omit the field, or invent a question
type. `_parse_questions` used to store those marks as-is, so an online test's
`total_marks = sum(q["marks"] ...)` at generation and `score += marks` at
grading hit `TypeError` on a non-number — a 500 on an otherwise valid test
(found 2026-10-18). Marks are now coerced to a number and the type is
lower-cased so the enforced-marks table is actually consulted.
"""

import json

from app.services.ai_service import _parse_questions


def _one(q):
    return _parse_questions(json.dumps([{"question": "Q?", "answer": "a", **q}]))


def test_known_type_uses_the_enforced_table_ignoring_a_string():
    out = _one({"type": "mcq", "marks": "99", "options": {"A": "x", "B": "y"}})
    assert out[0]["marks"] == 1 and isinstance(out[0]["marks"], (int, float))


def test_uppercase_type_is_canonicalised_and_scored_from_the_table():
    out = _one({"type": "LONG_ANSWER", "marks": "3"})
    assert out[0]["type"] == "long_answer"
    assert out[0]["marks"] == 3


def test_unknown_type_with_string_marks_becomes_a_number():
    out = _one({"type": "essay", "marks": "4"})
    assert out[0]["marks"] == 4.0
    assert isinstance(out[0]["marks"], (int, float))


def test_unknown_type_with_garbage_marks_falls_back_to_one():
    out = _one({"type": "essay", "marks": "lots"})
    assert out[0]["marks"] == 1


def test_match_following_without_columns_coerces_string_marks():
    out = _one({"type": "match_following", "marks": "5", "column_a": [], "column_b": []})
    assert out[0]["marks"] == 5.0


def test_every_generated_mark_sums_as_a_number():
    qs = _parse_questions(json.dumps([
        {"type": "mcq", "marks": "1", "question": "a", "answer": "x", "options": {"A": "1"}},
        {"type": "essay", "marks": "2", "question": "b", "answer": "y"},
        {"type": "match_following", "marks": True, "question": "c", "answer": "z",
         "column_a": [], "column_b": []},
    ]))
    total = sum(q["marks"] for q in qs)  # must not raise
    assert total == 1 + 2 + 4  # essay→2, match fallback→4 (True rejected)
