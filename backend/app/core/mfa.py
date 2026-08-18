"""
Recovery codes for MFA-enrolled accounts.

The fallback matters more than the second factor here. An admin who changes
handset with no way back is locked out of a whole school's records, and whoever
fixes that will do it by clearing `mfa_enabled` in the database — which is a
worse outcome than never having enabled MFA. So the recovery path has to work,
and has to be single-use.

Codes are 160-bit random values, stored as sha256. sha256 rather than bcrypt is
deliberate and not a shortcut: slow hashing exists to defend a small guess space,
and there isn't one here. Running bcrypt over ten codes on every fallback attempt
would cost real time and buy nothing.
"""

import hashlib
import hmac
import secrets
from typing import List, Optional, Tuple

RECOVERY_CODE_COUNT = 10

# Crockford-ish: no 0/O/1/I/L, because these get printed and typed back under
# stress, usually by someone already locked out and irritated.
_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_GROUP_LEN = 4
_GROUPS = 3


def _normalise(code) -> Optional[str]:
    """Upper-case, strip surrounding space. None if it isn't a string."""
    if not isinstance(code, str):
        return None
    return code.strip().upper()


def hash_recovery_code(code: str) -> str:
    """Stable sha256 of a normalised code."""
    normalised = _normalise(code) or ""
    return hashlib.sha256(normalised.encode()).hexdigest()


def generate_recovery_codes(
    count: int = RECOVERY_CODE_COUNT,
) -> Tuple[List[str], List[str]]:
    """Return (plaintext, hashed).

    Plaintext is shown to the user exactly once, at enrolment. Only the hashes
    are persisted, so a database leak does not hand over working codes.
    """
    plain: List[str] = []
    seen = set()
    while len(plain) < count:
        groups = [
            "".join(secrets.choice(_ALPHABET) for _ in range(_GROUP_LEN))
            for _ in range(_GROUPS)
        ]
        code = "-".join(groups)
        if code in seen:
            continue
        seen.add(code)
        plain.append(code)
    return plain, [hash_recovery_code(c) for c in plain]


def consume_recovery_code(
    code, stored_hashes: Optional[List[str]]
) -> Tuple[bool, List[str]]:
    """Try to spend one code.

    Returns (accepted, remaining_hashes). On success the matched hash is
    removed, so a code cannot be reused — a recovery code that still works after
    a successful login is just a second permanent password.

    Returns False for anything malformed rather than raising: this is reached
    straight from a request body.
    """
    remaining = list(stored_hashes or [])

    normalised = _normalise(code)
    if not normalised:
        return False, remaining

    candidate = hash_recovery_code(normalised)
    for stored in remaining:
        # compare_digest so a near-miss cannot be narrowed down by timing.
        if hmac.compare_digest(stored, candidate):
            remaining.remove(stored)
            return True, remaining
    return False, remaining
