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

A request body is not the only place they travel. The WebSocket handshake puts
the access token in the query string, which Sentry records for errors and for
sampled traces alike; log lines kept as breadcrumbs can quote that URL; and a
frame's local variables are whatever the handler was holding when it failed.
"""

import re

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


# `token=…` and friends wherever they turn up inside a string: a query string,
# a URL, a quoted log line.
_SECRET_PARAM = re.compile(
    r"(?i)\b(token|access_token|refresh_token|mpin)=([^&\s\"']+)"
)


def _scrub_text(value):
    if isinstance(value, str):
        return _SECRET_PARAM.sub(lambda m: f"{m.group(1)}={_REDACTED}", value)
    return value


def _scrub_request(req: dict) -> None:
    for section in ("data", "headers", "cookies"):
        _scrub(req.get(section))
    query = req.get("query_string")
    if isinstance(query, str):
        req["query_string"] = _scrub_text(query)
    else:
        _scrub(query)
    if "url" in req:
        req["url"] = _scrub_text(req["url"])


def _scrub_breadcrumbs(event: dict) -> None:
    crumbs = event.get("breadcrumbs") or {}
    values = crumbs.get("values") if isinstance(crumbs, dict) else crumbs
    for crumb in values or []:
        if not isinstance(crumb, dict):
            continue
        if "message" in crumb:
            crumb["message"] = _scrub_text(crumb["message"])
        data = crumb.get("data")
        _scrub(data)
        if isinstance(data, dict):
            for k, v in data.items():
                data[k] = _scrub_text(v)


def _drop_frame_variables(event: dict) -> None:
    """Locals cannot be redacted by name — `payload` is an innocent name whose
    repr holds the MPIN — so none of them leave. `include_local_variables=False`
    already stops the SDK collecting them; this holds if that is ever lost."""
    for section in ("exception", "threads"):
        for item in ((event.get(section) or {}).get("values")) or []:
            for frame in ((item.get("stacktrace") or {}).get("frames")) or []:
                frame.pop("vars", None)


def scrub_event(event, hint=None):
    """Sentry before_send / before_send_transaction hook: redact credentials
    and a minor's identifiers from the request, the breadcrumbs and the stack.
    Never raises — a scrubber that threw would drop the whole event and blind
    error reporting. Each part is tried on its own so one odd shape cannot
    leave the rest unscrubbed."""
    if not isinstance(event, dict):
        return event
    for part in (
        lambda: _scrub_request(event.get("request") or {}),
        lambda: _scrub_breadcrumbs(event),
        lambda: _drop_frame_variables(event),
    ):
        try:
            part()
        except Exception:
            pass
    return event


def sentry_privacy_options() -> dict:
    """The `sentry_sdk.init` arguments that decide what leaves the process.
    Here rather than in main.py so the tests run the SDK with exactly these."""
    return {
        "send_default_pii": False,
        "include_local_variables": False,
        "before_send": scrub_event,
        # Traces do not pass through before_send. One in ten requests is
        # traced, WebSocket handshakes (and their ?token=) included.
        "before_send_transaction": scrub_event,
    }
