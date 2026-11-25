"""Teacher subjects at sign-up: known, normalised, de-duplicated."""

import pytest
from pydantic import ValidationError

from app.schemas.user import UserRegisterRequest as _Reg


def _make(subjects):
    return _Reg(username="qa_teacher", mpin="470381", role="teacher",
                phone="9312345678", teachable_subjects=subjects)


def test_unknown_subject_is_refused():
    with pytest.raises(ValidationError, match="Unknown subject"):
        _make(["Astrology"])


def test_aliases_are_normalised_and_duplicates_dropped():
    assert _make(["maths", "Mathematics", "PHYSICS"] + ["Physics"] * 10).teachable_subjects == \
        ["Mathematics", "Physics"]
