"""
How long students get to attempt an auto-generated quiz, and when that starts.

Lives here rather than in a router for two reasons. The constant is quoted in a
teacher notification and enforced on the student side, so it needs one home
rather than being imported across routers. And keeping the rule in a module with
no heavy imports means it can be tested without dragging a whole router — and
its transitive stubs — into the test process.
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

# Students get this long once a teacher publishes. Quoted verbatim in the
# "quiz ready to review" notification; change both together or the app tells
# teachers something untrue.
AUTO_TEST_WINDOW_HOURS = 48


def start_window_on_first_publish(test, now: Optional[datetime] = None) -> None:
    """Give a test its attempt window the first time it is published.

    Auto-quizzes are created unpublished and with no deadline, so a teacher
    reviews the AI's questions before students see them. The window therefore has
    to start at approval rather than at generation — otherwise the teacher's
    thinking time comes out of the students' time, and a quiz approved two days
    late would arrive already expired.

    No-op unless the test is published and has no deadline yet. That guard is
    doing real work in both directions: it stops unpublish/republish from
    extending a window (which would hand one class more time than another, or
    revive a closed quiz), and it leaves alone the expiry a manually-created test
    set for itself.
    """
    if not test.is_published or test.expires_at is not None:
        return
    test.expires_at = (now or datetime.now(timezone.utc)) + timedelta(
        hours=AUTO_TEST_WINDOW_HOURS
    )
