"""
Audit-log coverage.

The audit trail only helps if sensitive admin actions actually write a row. The
mechanism was confirmed live (deactivate/activate produced correctly-attributed
rows), and this guards the *coverage* against regression: it extracts the action
name from every `_audit(...)` / `AuditLog(action=...)` call in the admin and auth
routers and asserts the security-relevant user-lifecycle actions are all still
emitted.

Because it reads the action out of the audit call specifically (not just any
occurrence of the word), deleting the audit line from an endpoint drops that
action from the set and fails the test — which is the point.
"""

import pathlib
import re

_BACKEND = pathlib.Path(__file__).resolve().parents[1]
_SOURCES = [
    _BACKEND / "app" / "routers" / "admin.py",
    _BACKEND / "app" / "routers" / "auth.py",
]


def _emitted_actions() -> set[str]:
    actions: set[str] = set()
    for path in _SOURCES:
        # Drop comment lines so a commented-out audit call isn't counted as
        # coverage — the scan should reflect live code only.
        src = "\n".join(
            ln for ln in path.read_text().splitlines()
            if not ln.lstrip().startswith("#"))
        # _audit(db, actor_id, ACTION, "target_type", ...). ACTION is a string
        # literal, or a ternary `"a" if cond else "b"` — capture both branches.
        for m in re.finditer(
            r'_audit\(\s*db\s*,\s*[^,]+,\s*'
            r'"([a-z_]+)"(?:\s+if\s+.+?\s+else\s+"([a-z_]+)")?',
            src, re.S,
        ):
            actions.add(m.group(1))
            if m.group(2):
                actions.add(m.group(2))
        # db.add(AuditLog(..., action="ACTION", ...)) — keyword form.
        for m in re.finditer(r'AuditLog\((?:[^)]*?)action="([a-z_]+)"', src, re.S):
            actions.add(m.group(1))
    return actions


# The user-lifecycle actions whose audit trail is security-relevant: an admin
# turning accounts on/off, editing them, approving, removing, or a self-delete.
REQUIRED = {
    "approve_user",
    "edit_user",
    "activate_user",
    "deactivate_user",
    "delete_pending_user",
    "revoke_user",
    "self_delete",
    "self_delete_cascade_child",
}


def test_every_sensitive_user_action_is_audited():
    emitted = _emitted_actions()
    missing = REQUIRED - emitted
    assert not missing, (
        f"these sensitive actions are no longer audited: {sorted(missing)}. "
        f"Emitted actions found: {sorted(emitted)}")


def test_audit_coverage_does_not_silently_shrink():
    # A floor, not an exact count: coverage today spans user, teacher, fee and
    # feedback actions. If this drops below the floor, an audit call was removed.
    emitted = _emitted_actions()
    assert len(emitted) >= 12, (
        f"audit-action coverage shrank to {len(emitted)}: {sorted(emitted)}")


def test_actions_are_reasonable_names():
    # Guard against a stray capture: audit actions are short snake_case verbs.
    for a in _emitted_actions():
        assert re.fullmatch(r"[a-z][a-z_]{2,49}", a), a
