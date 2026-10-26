"""J-11: the over-balance guard and the fee summary must agree on a student's
total, and overpayment must be refused only when a fee structure exists.
Pure-logic tests on app.core.fee_math.
"""

from app.core.fee_math import total_fee_for, balance_due, would_overpay


# ── total_fee_for ────────────────────────────────────────────────────────────

def test_total_is_base_when_no_optional_subjects():
    assert total_fee_for(base_amount=40000, economics_fee=8000,
                         computer_fee=8000, ai_fee=8000,
                         additional_subjects=None) == 40000.0
    assert total_fee_for(base_amount=40000, economics_fee=8000,
                         computer_fee=8000, ai_fee=8000,
                         additional_subjects=[]) == 40000.0


def test_optional_subjects_add_their_own_fee():
    assert total_fee_for(base_amount=40000, economics_fee=5000,
                         computer_fee=8000, ai_fee=9000,
                         additional_subjects=["computer"]) == 48000.0
    assert total_fee_for(base_amount=40000, economics_fee=5000,
                         computer_fee=8000, ai_fee=9000,
                         additional_subjects=["economics", "ai"]) == 54000.0


def test_unknown_subject_is_ignored():
    assert total_fee_for(base_amount=40000, economics_fee=5000,
                         computer_fee=8000, ai_fee=9000,
                         additional_subjects=["art"]) == 40000.0


# ── balance_due ──────────────────────────────────────────────────────────────

def test_balance_never_negative():
    assert balance_due(40000, 40000) == 0.0
    assert balance_due(40000, 45000) == 0.0   # overpaid still reads ₹0 due
    assert balance_due(40000, 15000) == 25000.0


# ── would_overpay ────────────────────────────────────────────────────────────

def test_overpay_true_past_total():
    assert would_overpay(40000, 40000, 1) is True
    assert would_overpay(40000, 0, 99_99_999) is True
    assert would_overpay(40000, 30000, 20000) is True   # 50k > 40k


def test_paying_exact_balance_is_allowed():
    assert would_overpay(40000, 30000, 10000) is False   # lands exactly on 40k
    assert would_overpay(40000, 0, 40000) is False


def test_paise_rounding_does_not_trip_the_guard():
    # Paying the last 0.50 when 39,999.50 is already paid must be accepted.
    assert would_overpay(40000, 39999.50, 0.50) is False


def test_no_structure_means_no_bound():
    # total_fee 0 (no FeeStructure) => any amount allowed, no false refusal.
    assert would_overpay(0, 0, 1) is False
    assert would_overpay(0, 0, 10_00_00_000) is False
