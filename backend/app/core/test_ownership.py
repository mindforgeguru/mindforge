"""Who may change a test (edit, delete, publish, download, post grades).

The /tests listing is school-wide, but changing a test is for its creator —
unless the creator has left, so a colleague can look after a stranded test.
Kept pure so the rule is unit-tested in one place and shared by the owner
check and the listing's ``can_manage`` flag (#40).
"""

from typing import Literal

Refusal = Literal["allow", "not_found", "forbidden"]


def decide_test_change(
    *, is_creator: bool, same_school: bool, creator_active: bool
) -> Refusal:
    """Decide whether a teacher may change a test.

    - ``"allow"``     — their own test, or a same-school test whose creator left.
    - ``"not_found"`` — another school's test: stays indistinguishable from a
      missing one (404).
    - ``"forbidden"`` — a live colleague's test. The listing already shows it
      exists, so the refusal says why (403) instead of "Test not found".
    """
    if is_creator:
        return "allow"
    if not same_school:
        return "not_found"
    if not creator_active:
        return "allow"
    return "forbidden"
