"""Fee arithmetic shared by the fee summary and the payment guard.

The over-balance check in record_fee_payment must compute a student's total
fee exactly the way the fee summary does, or an admin would be refused a
payment the balance on screen says is still due (J-11). Keeping the one
formula here, as a pure function, stops the two from drifting apart.
"""

from decimal import Decimal
from typing import Iterable, Optional

# Optional subjects that carry their own line-item fee, mapped to the
# FeeStructure column holding that fee.
_OPTIONAL_SUBJECT_FEES = {
    "economics": "economics_fee",
    "computer": "computer_fee",
    "ai": "ai_fee",
}


def total_fee_for(
    *,
    base_amount: float,
    economics_fee: float,
    computer_fee: float,
    ai_fee: float,
    additional_subjects: Optional[Iterable[str]],
) -> float:
    """The student's total fee: the grade's base plus each optional subject
    they take. Mirrors app/routers/admin.py get_all_fee_summaries."""
    fees = {
        "economics_fee": economics_fee,
        "computer_fee": computer_fee,
        "ai_fee": ai_fee,
    }
    total = float(base_amount)
    for subj in (additional_subjects or []):
        col = _OPTIONAL_SUBJECT_FEES.get(subj)
        if col is not None:
            total += float(fees[col])
    return total


def balance_due(total_fee: float, total_paid: float) -> float:
    """Outstanding balance, never negative (overpayment shows as ₹0 due)."""
    return max(0.0, round(total_fee - total_paid, 2))


def would_overpay(
    total_fee: float, total_paid: float, new_amount, *, tolerance: float = 0.01
) -> bool:
    """True when adding new_amount would push total paid past the total fee.

    Only meaningful when a fee structure exists (total_fee > 0); with no
    structure the total is 0 and there is no balance to exceed, so this
    returns False and the payment is allowed. `tolerance` absorbs float/paise
    rounding so paying the exact balance is never rejected.
    """
    if total_fee <= 0:
        return False
    new_amount = float(Decimal(str(new_amount)))
    return (total_paid + new_amount) > (total_fee + tolerance)
