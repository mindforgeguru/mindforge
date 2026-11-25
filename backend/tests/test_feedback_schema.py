"""Feedback must contain real text."""

import pytest
from pydantic import ValidationError

from app.schemas.feedback import FeedbackCreate


@pytest.mark.parametrize("blank", ["   ", "\n\n\n\n", " \t x "])
def test_blank_or_near_blank_reports_are_refused(blank):
    with pytest.raises(ValidationError):
        FeedbackCreate(message=blank)


def test_text_is_trimmed():
    assert FeedbackCreate(message="  app froze on Fees  ").message == "app froze on Fees"
