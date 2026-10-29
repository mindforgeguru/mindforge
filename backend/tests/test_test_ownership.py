"""
Owner rule for changing a test (#40).

A teacher may change their own test, or a colleague's whose creator has left.
Another teacher's live test in the same school is refused with a reason (403)
— the school-wide /tests listing already shows it exists, so a 404 only
produced a confusing "Test not found" in the app. Another school's test stays
indistinguishable from a missing one (404).
"""

from app.core.test_ownership import decide_test_change


def test_own_test_is_allowed():
    assert decide_test_change(is_creator=True, same_school=True, creator_active=True) == "allow"


def test_colleagues_test_whose_creator_left_is_allowed():
    assert decide_test_change(is_creator=False, same_school=True, creator_active=False) == "allow"


def test_colleagues_live_test_is_forbidden():
    assert decide_test_change(is_creator=False, same_school=True, creator_active=True) == "forbidden"


def test_other_schools_test_is_not_found_even_if_its_creator_left():
    assert decide_test_change(is_creator=False, same_school=False, creator_active=False) == "not_found"
