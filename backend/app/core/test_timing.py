"""Time limits for online tests (#14 / #17).

There are two kinds of online test, with two deliberately different pacings:

  - a manually-generated test (teacher picks the chapter and question mix):
    30 seconds per question — a 10-question quiz is 5 minutes;
  - a presentation auto-quiz (short, generated from slide content):
    1 minute per question plus a small settling buffer — 5 questions is 7 min.

The bug was that these rules were scattered and disagreed with each other and
with the teacher-facing display: generation used 30s/question, editing the
questions used 1 min/question (even for manual tests), and the test-detail chip
showed the question count instead of the stored limit. Keeping both rules here,
and routing generation, editing, the stored value and the student timer through
them, keeps every surface in agreement.
"""

import math

# Reading / settling time added on top of 1 minute per question for auto-quizzes.
AUTO_TEST_TIME_BUFFER_MIN = 2


def online_time_limit_minutes(question_count: int) -> int:
    """Manually-generated online test: 30 seconds per question, rounded up to a
    whole minute (10 questions → 5 minutes)."""
    return math.ceil(question_count / 2)


def auto_quiz_time_limit_minutes(question_count: int) -> int:
    """Presentation auto-quiz: 1 minute per question plus a small buffer, so the
    limit scales with however many questions were generated (5 → 7, 10 → 12)."""
    return question_count + AUTO_TEST_TIME_BUFFER_MIN
