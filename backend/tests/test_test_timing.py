"""#14 / #17: online-test time limits must be one consistent rule per kind of
test, so generation, editing, the stored value and the student timer agree.
Pure-logic tests on app.core.test_timing.
"""

from app.core.test_timing import (
    online_time_limit_minutes,
    auto_quiz_time_limit_minutes,
)


# ── manual online test: 30 seconds per question, rounded up ──────────────────

def test_manual_is_half_a_minute_per_question():
    assert online_time_limit_minutes(10) == 5     # the D-10 case: not 10
    assert online_time_limit_minutes(1) == 1
    assert online_time_limit_minutes(0) == 0


def test_manual_rounds_odd_counts_up():
    assert online_time_limit_minutes(7) == 4      # ceil(3.5)
    assert online_time_limit_minutes(9) == 5


# ── presentation auto-quiz: 1 minute per question plus a buffer ──────────────

def test_auto_quiz_is_a_minute_per_question_plus_buffer():
    assert auto_quiz_time_limit_minutes(5) == 7
    assert auto_quiz_time_limit_minutes(8) == 10
    assert auto_quiz_time_limit_minutes(10) == 12


def test_the_two_rules_differ():
    # The whole point: a manual test and an auto-quiz of the same length are
    # paced differently and must not be collapsed into one number.
    assert online_time_limit_minutes(10) != auto_quiz_time_limit_minutes(10)
