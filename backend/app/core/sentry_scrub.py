"""
Sentry `before_send` scrubber.

Kept out of main.py so it is unit-testable without initialising Sentry or
building the app. Redacts sensitive values from the request payload attached to
an error event before it leaves the process.

Two classes of key are redacted:
  • credentials — an MPIN or bearer token in a crash report is a live secret;
  • direct identifiers of a minor — this app holds children's records, and a
    student's phone or email would otherwise ride along in a request body
    captured on a 500. `send_default_pii=False` stops Sentry attaching the user
    automatically, but not fields inside a body the app itself sent.
"""

# Compared case-insensitively (see below), so list them lowercase.
SCRUB_KEYS = {
    # credentials
    "mpin", "password", "token", "refresh_token", "mpin_hash",
    "access_token", "authorization", "cookie",
    # minor / contact identifiers
    "phone", "parent_phone", "email",
}

_REDACTED = "[scrubbed]"


def _scrub(obj) -> None:
    """Recursively redact matching keys in dicts (and dicts inside lists), in
    place. Request bodies are not always flat, so a nested {"parent": {"phone":
    …}} must be caught too."""
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            if isinstance(k, str) and k.lower() in SCRUB_KEYS:
                obj[k] = _REDACTED
            else:
                _scrub(v)
    elif isinstance(obj, list):
        for item in obj:
            _scrub(item)


def scrub_event(event, hint=None):
    """Sentry before_send hook: redact sensitive keys from request data/headers/
    cookies. Never raises — a scrubber that threw would drop the whole event and
    blind error reporting."""
    try:
        req = (event or {}).get("request") or {}
        for section in ("data", "headers", "cookies"):
            _scrub(req.get(section))
    except Exception:
        pass
    return event
