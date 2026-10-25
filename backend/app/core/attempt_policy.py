"""Pure decision for what a test-attempt call (start / submit) should do.

Extracted so the ordering rule — *an in-progress attempt is always finalized,
never refused because the test window has since closed* — is unit-tested in one
place and shared by both endpoints. Keeping it inline let the expiry guard run
*before* the submission was loaded, so a student who was mid-test when the
window closed got a 410 and their saved answers were never graded (bug J-06).
"""

from typing import Literal

AttemptAction = Literal["result", "grade", "expired", "create"]


def resolve_attempt_action(
    *, has_submission: bool, is_finalized: bool, window_expired: bool
) -> AttemptAction:
    """Decide the action for a /start or /submit call.

    - ``"result"``  — a finalized submission already exists. The attempt is
      over; the caller shows the result (/start) or 409s (/submit).
    - ``"grade"``   — an in-progress submission exists. Finalize and grade the
      answers saved so far (or just sent), marked auto-submitted if the window
      or per-attempt deadline has passed. **This is returned even when the test
      window has expired**, so answers entered before the close are never lost.
    - ``"expired"`` — no submission and the window is closed. The student never
      started; they cannot start or submit now → 410.
    - ``"create"``  — no submission and the window is open. Start a fresh
      attempt (/start) or create a one-shot finalized row (legacy /submit).
    """
    if has_submission:
        return "result" if is_finalized else "grade"
    return "expired" if window_expired else "create"
