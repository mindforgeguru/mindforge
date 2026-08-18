"""
A student must not be able to influence their own score.

The grade is computed server-side in `_finalize_submission`: `_grade_submission`
scores the saved answers against the test's key, and the resulting `Grade` row
is built from that number and `test.total_marks`. Nothing the client sends is
carried into it.

That property rests on the request schema, which is where it would quietly break
— someone adds a field to `TestSubmissionCreate` for a reasonable-looking
reason, and the student is suddenly supplying part of their own grade. These
tests pin the accepted surface so that change has to be deliberate.

The write path is also single-shot: `/save` and `/submit` both 409 once
`is_finalized` is set, and `_finalize_submission` returns early on an
already-finalized row, so answers cannot be rewritten and a grade cannot be
recomputed.
"""

import pytest

from app.schemas.test import TestAnswersSave, TestSubmissionCreate


class TestSubmissionSurfaceIsMinimal:
    def test_only_answers_and_auto_submitted_are_accepted(self):
        # If this set grows, whatever was added is now student-controlled input
        # on the path that produces a grade. That deserves a conscious decision,
        # not a silent schema edit.
        assert set(TestSubmissionCreate.model_fields) == {"answers", "auto_submitted"}

    def test_autosave_only_accepts_answers(self):
        assert set(TestAnswersSave.model_fields) == {"answers"}


class TestClientCannotSupplyAScore:
    @pytest.mark.parametrize(
        "field", ["score", "marks_obtained", "max_marks", "is_finalized", "student_id"]
    )
    def test_score_bearing_fields_are_not_bound(self, field):
        # Pydantic ignores unknown keys by default, so this does not raise — the
        # point is that the value never becomes an attribute and so can never
        # reach the Grade row.
        payload = TestSubmissionCreate(**{"answers": {"1": "A"}, field: 999})
        assert not hasattr(payload, field), (
            f"{field!r} was bound from the request body; a student could set it"
        )

    def test_a_forged_score_does_not_survive_into_the_dump(self):
        payload = TestSubmissionCreate(answers={"1": "A"}, score=100, marks_obtained=100)
        dumped = payload.model_dump()
        assert "score" not in dumped
        assert "marks_obtained" not in dumped
        assert dumped["answers"] == {"1": "A"}


class TestAnswersAreStillRequired:
    def test_answers_is_mandatory(self):
        # Guards the other direction: a submission with no answers must not be
        # silently accepted and graded against an empty key.
        with pytest.raises(Exception):
            TestSubmissionCreate()
