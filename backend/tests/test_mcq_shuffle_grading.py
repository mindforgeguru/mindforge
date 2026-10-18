"""
The per-student MCQ shuffle and the grader agree.

Each student sees an MCQ's options in their own deterministic order (so a
neighbour can't copy "it's C"), and the server maps the tapped letter back
through the *same* order to score it. If the two ever disagreed — or the seed
were process-salted — correct answers would be marked wrong. These pin the
round-trip: the letter that maps to the key wins for every student, a different
letter loses, the order is stable, and an answer key given as option *text*
also scores.
"""

from types import SimpleNamespace

import pytest

from app.routers.student import (
    _grade_submission,
    _mcq_display_order,
)

OPTIONS = {"A": "Paris", "B": "London", "C": "Rome", "D": "Berlin"}
TEST_ID = 4242


def _test_with_answer(answer):
    return SimpleNamespace(
        id=TEST_ID,
        total_marks=1,
        questions=[{"id": 1, "type": "mcq", "options": dict(OPTIONS),
                    "answer": answer, "marks": 1}],
    )


def _displayed_letter_for(original_key, student_id):
    order = _mcq_display_order(1, list(OPTIONS.keys()),
                               student_id=student_id, test_id=TEST_ID)
    return chr(65 + order.index(original_key))


@pytest.mark.parametrize("student_id", range(1, 61))
def test_the_letter_mapping_to_the_key_scores_for_every_student(student_id):
    test = _test_with_answer("C")  # correct original option is key "C"
    right = _displayed_letter_for("C", student_id)
    assert _grade_submission(test, {"1": right},
                             student_id=student_id, test_id=TEST_ID) == 1


@pytest.mark.parametrize("student_id", range(1, 61))
def test_a_different_letter_scores_zero(student_id):
    test = _test_with_answer("C")
    right = _displayed_letter_for("C", student_id)
    wrong = next(l for l in "ABCD" if l != right)
    assert _grade_submission(test, {"1": wrong},
                             student_id=student_id, test_id=TEST_ID) == 0


def test_the_display_order_is_stable_for_a_student():
    a = _mcq_display_order(1, list(OPTIONS.keys()), student_id=7, test_id=TEST_ID)
    b = _mcq_display_order(1, list(OPTIONS.keys()), student_id=7, test_id=TEST_ID)
    assert a == b


def test_different_students_can_see_different_orders():
    orders = {tuple(_mcq_display_order(1, list(OPTIONS.keys()),
                                       student_id=s, test_id=TEST_ID))
              for s in range(1, 40)}
    assert len(orders) > 1  # shuffle actually varies by student


@pytest.mark.parametrize("student_id", range(1, 21))
def test_an_answer_key_given_as_option_text_also_scores(student_id):
    test = _test_with_answer("Rome")  # key is the text of original option C
    right = _displayed_letter_for("C", student_id)
    assert _grade_submission(test, {"1": right},
                             student_id=student_id, test_id=TEST_ID) == 1


def test_a_blank_answer_scores_zero():
    test = _test_with_answer("C")
    assert _grade_submission(test, {}, student_id=1, test_id=TEST_ID) == 0
    assert _grade_submission(test, {"1": ""}, student_id=1, test_id=TEST_ID) == 0
