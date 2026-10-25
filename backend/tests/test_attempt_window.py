"""Regression for J-06: a test window closing mid-attempt must not discard the
student's saved answers. The ordering rule lives in
`app.core.attempt_policy.resolve_attempt_action` and is shared by
`/student/tests/{id}/start` and `/submit`.
"""

import pytest

from app.core.attempt_policy import resolve_attempt_action


def act(has_submission, is_finalized, window_expired):
    return resolve_attempt_action(
        has_submission=has_submission,
        is_finalized=is_finalized,
        window_expired=window_expired,
    )


# ── The bug: in-progress attempt + window since closed ───────────────────────

def test_in_progress_attempt_is_graded_even_after_window_closes():
    # This is J-06. Before the fix the endpoints 410'd on window expiry before
    # ever looking at the attempt, so these saved answers were never scored.
    assert act(has_submission=True, is_finalized=False, window_expired=True) == "grade"


def test_in_progress_attempt_is_graded_while_window_open():
    assert act(has_submission=True, is_finalized=False, window_expired=False) == "grade"


# ── A student who never started is still blocked after the window closes ─────

def test_no_attempt_after_window_close_is_expired():
    assert act(has_submission=False, is_finalized=False, window_expired=True) == "expired"


def test_no_attempt_while_window_open_can_create():
    assert act(has_submission=False, is_finalized=False, window_expired=False) == "create"


# ── A finalized attempt is over regardless of the window ─────────────────────

@pytest.mark.parametrize("window_expired", [True, False])
def test_finalized_attempt_shows_result(window_expired):
    assert act(has_submission=True, is_finalized=True, window_expired=window_expired) == "result"


def test_window_expiry_never_strands_an_in_progress_attempt():
    # The property that matters: whenever an attempt exists and isn't finalized,
    # the action is "grade" — never "expired" — so answers are never lost to a
    # window that closed after the student started.
    for window_expired in (True, False):
        assert act(has_submission=True, is_finalized=False, window_expired=window_expired) != "expired"
