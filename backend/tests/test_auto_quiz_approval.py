"""
Auto-generated quizzes must pass the same gate as every other test.

Manually-created tests are already teacher-gated: they exist unpublished, and
students only ever see `is_published == True` — filtered in five separate places.
Auto-quizzes set `is_published=True` on themselves at generation and broadcast
straight to the grade, so they walked around a gate the rest of the app respects.

That mattered because nothing else in the chain has a human in it: a teacher
uploads a chapter PDF, a model writes slides, a period log turns those slides
into a quiz, and it reaches students. Content from an uploaded document could
land in front of children with nobody having read it.

The fix reuses what exists rather than inventing an approval concept: the quiz
is created unpublished, and the teacher's existing Publish button is the review.

**The timing trap this has to avoid.** `expires_at` was set at generation. Hold
the quiz for review without changing that and the teacher's thinking time eats
the students' 48 hours — publish a day late and they get 24, publish two days
late and they get a quiz that is already dead. So the window has to start at
publish.
"""

from datetime import datetime, timedelta, timezone

import pytest

# Imported from app.core.quiz_window, not from a router. Pulling a router in
# here drags its transitive module stubs into the process and reorders them for
# every test that runs afterwards — which is exactly what broke test_realtime_fanout
# the first time this file existed.
from app.core.quiz_window import (
    AUTO_TEST_WINDOW_HOURS as _AUTO_TEST_WINDOW_HOURS,
    start_window_on_first_publish as _start_window_on_first_publish,
)


class _Test:
    """Stand-in for the Test row — only the fields this logic touches."""
    def __init__(self, is_published=False, expires_at=None):
        self.is_published = is_published
        self.expires_at = expires_at


class TestWindowStartsAtPublish:
    def test_first_publish_sets_the_window(self):
        t = _Test(is_published=True, expires_at=None)
        now = datetime(2026, 8, 19, 12, 0, tzinfo=timezone.utc)
        _start_window_on_first_publish(t, now=now)
        assert t.expires_at == now + timedelta(hours=_AUTO_TEST_WINDOW_HOURS)

    def test_students_get_the_full_window_however_long_review_took(self):
        # The point of the change. A teacher who reviews three days later still
        # hands students a full window rather than an expired quiz.
        t = _Test(is_published=True, expires_at=None)
        much_later = datetime(2026, 8, 22, 9, 0, tzinfo=timezone.utc)
        _start_window_on_first_publish(t, now=much_later)
        assert t.expires_at == much_later + timedelta(hours=_AUTO_TEST_WINDOW_HOURS)


class TestWindowIsNotExtendable:
    def test_republishing_does_not_move_an_existing_deadline(self):
        # Unpublish/republish must not become a way to hand one class more time
        # than another, or to revive a quiz after it closed.
        original = datetime(2026, 8, 19, 12, 0, tzinfo=timezone.utc)
        t = _Test(is_published=True, expires_at=original)
        _start_window_on_first_publish(
            t, now=datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc)
        )
        assert t.expires_at == original

    def test_a_manually_created_test_with_its_own_deadline_is_untouched(self):
        # Manual tests set their own expiry at creation. This must not reach in
        # and rewrite it.
        own = datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc)
        t = _Test(is_published=True, expires_at=own)
        _start_window_on_first_publish(t)
        assert t.expires_at == own


class TestUnpublishing:
    def test_unpublishing_keeps_the_deadline(self):
        # Pulling a quiz to fix a question and putting it back must not reset
        # the clock — see the extension test above.
        original = datetime(2026, 8, 19, 12, 0, tzinfo=timezone.utc)
        t = _Test(is_published=False, expires_at=original)
        _start_window_on_first_publish(t)
        assert t.expires_at == original

    def test_nothing_happens_while_the_test_is_unpublished_and_unstarted(self):
        # An auto-quiz sitting unreviewed has no deadline, and must not acquire
        # one just because someone toggled it off.
        t = _Test(is_published=False, expires_at=None)
        _start_window_on_first_publish(t)
        assert t.expires_at is None


class TestGenerationDefaults:
    def test_the_window_constant_is_still_what_the_message_promises(self):
        # The teacher notification quotes this number. If one changes without
        # the other, the app tells teachers something untrue.
        assert _AUTO_TEST_WINDOW_HOURS == 48
