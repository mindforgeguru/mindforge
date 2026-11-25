"""Manual XP adjustments are bounded."""

import pytest
from pydantic import ValidationError

from app.schemas.xp import MAX_MANUAL_XP, XPAdjustmentRequest


@pytest.mark.parametrize("amount", [MAX_MANUAL_XP + 1, -(MAX_MANUAL_XP + 1), 10**12, 0])
def test_out_of_range_or_zero_is_refused(amount):
    with pytest.raises(ValidationError):
        XPAdjustmentRequest(student_id=1, amount=amount, reason="r")


@pytest.mark.parametrize("amount", [1, -50, MAX_MANUAL_XP, -MAX_MANUAL_XP])
def test_normal_adjustments_are_fine(amount):
    assert XPAdjustmentRequest(student_id=1, amount=amount, reason="r").amount == amount
