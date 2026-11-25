"""A fee payment can't be dated in the future."""

from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.schemas.fees import FeePaymentCreate


def test_future_payment_date_is_refused():
    with pytest.raises(ValidationError, match="in the future"):
        FeePaymentCreate(student_id=1, amount=10,
                         paid_at=datetime.now(timezone.utc) + timedelta(days=30))


@pytest.mark.parametrize("paid_at", [None,
                                     datetime.now(timezone.utc),
                                     datetime.now(timezone.utc) - timedelta(days=60),
                                     datetime.now() + timedelta(hours=6)])
def test_today_past_and_missing_dates_are_fine(paid_at):
    FeePaymentCreate(student_id=1, amount=10, paid_at=paid_at)
