"""
Masking helpers for sensitive PII fields.

Rules
-----
Phone  (+91 98765 43210)  →  +91 98***3210
         ^prefix  ^last4       keep first 2 digits after prefix, mask middle, keep last 4
Email  (user@example.com) →  u***@example.com
         keep first char, mask local-part, keep domain

Both functions accept None and return None unchanged so they can be used inline without guards.
"""

import re
from typing import Optional


def mask_phone(phone: Optional[str]) -> Optional[str]:
    """
    Partially mask a phone number for non-privileged display.

    Strips all spaces/dashes/parentheses, keeps a country-code prefix
    (leading + and up to 3 digits) plus the last 4 digits, replacing
    everything in between with ***.
    Examples:
        '+91 98765 43210' → '+91 98***3210'
        '9876543210'      → '98***3210'
        '+1-800-555-1234' → '+1 80***1234'
    """
    if not phone:
        return phone

    # Strip formatting characters (spaces, dashes, dots, parens)
    digits = re.sub(r"[\s\-\.\(\)]", "", phone)

    # Detect country code: leading + followed by 1-3 digits
    prefix = ""
    rest = digits
    if digits.startswith("+"):
        m = re.match(r"^(\+\d{1,3})(.*)", digits)
        if m:
            prefix = m.group(1) + " "
            rest = m.group(2)

    if len(rest) <= 4:
        # Too short to mask meaningfully — just return as-is
        return phone

    # Keep first 2 digits of local part + *** + last 4
    visible_head = rest[:2]
    visible_tail = rest[-4:]
    return f"{prefix}{visible_head}***{visible_tail}"


def mask_email(email: Optional[str]) -> Optional[str]:
    """
    Partially mask an email address.

    Examples:
        'chinmay@gmail.com'   → 'c***@gmail.com'
        'ab@x.co'             → 'a***@x.co'
        'a@b.com'             → 'a***@b.com'
    """
    if not email or "@" not in email:
        return email
    local, domain = email.rsplit("@", 1)
    return f"{local[0]}***@{domain}"
