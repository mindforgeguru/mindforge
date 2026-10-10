"""
Keep bearer tokens out of the server log.

The WebSocket handshake carries the access token as `?token=` — browsers cannot
set an Authorization header on it — and uvicorn logs the full path of every
handshake. Without this, each connection writes a usable JWT to stdout and on
to wherever the logs are collected and retained.
"""

import logging
import re

# `token=` or `refresh_token=` followed by its value, up to the next delimiter.
_TOKEN_PARAM = re.compile(r"((?:refresh_)?token=)[^&\s\"']+", re.IGNORECASE)

_UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")


class RedactTokenFilter(logging.Filter):
    """Replace a token query parameter's value with `[redacted]`.

    Never drops a record. One that carries no token is left exactly as it was,
    arguments included.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            message = record.getMessage()
        except Exception:
            return True  # malformed record — let logging report it as usual
        redacted = _TOKEN_PARAM.sub(r"\1[redacted]", message)
        if redacted != message:
            record.msg = redacted
            record.args = None
        return True


def install_token_redaction() -> None:
    """Attach the filter to uvicorn's loggers. Safe to call more than once."""
    for name in _UVICORN_LOGGERS:
        target = logging.getLogger(name)
        if not any(isinstance(f, RedactTokenFilter) for f in target.filters):
            target.addFilter(RedactTokenFilter())
