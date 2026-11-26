"""
Push recipients must be active accounts.

Recipient sets are active students plus each one's linked parent, and the
parent was never checked: a deactivated parent kept getting the child's
absence alerts. can_receive_push() is the condition every token lookup uses.

Falsified: drop the is_active or deleted_at term and the matching test fails.
(The suite stubs the DB layer, so this checks the expression's columns by
identity rather than compiling SQL; the live check ran against Postgres.)
"""

from app.core.push_recipients import can_receive_push
from app.models.user import User


def _lefts():
    return [c.left for c in can_receive_push().clauses]


def _has(col) -> bool:
    target = getattr(col, "column", col)  # MappedColumn under the test stubs
    return any(left is target for left in _lefts())


def test_requires_a_token():
    assert _has(User.fcm_token)


def test_requires_an_active_account():
    assert _has(User.is_active)


def test_excludes_deleted_accounts():
    assert _has(User.deleted_at)
