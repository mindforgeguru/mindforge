"""
Access tokens must not reach the server log.

The WebSocket handshake carries the JWT as `?token=` (browsers cannot set
headers on it), and uvicorn logs the full request path of every handshake —
so each connection wrote a live access token to stdout, and from there to
whatever collects the logs. Seen on the local stack 2026-10-10: 110 tokens in
15 minutes of log.
"""

import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.log_redaction import RedactTokenFilter, install_token_redaction

JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIyNiJ9.HzZlERO4eSZ0rAOuyY0a9LP-7qN61VedSk2rWgZ2Sc8"


def _record(msg, *args):
    return logging.LogRecord("uvicorn.error", logging.INFO, __file__, 1, msg, args, None)


def test_token_in_uvicorn_websocket_line_is_redacted():
    # The shape uvicorn emits: the path arrives as a %s argument.
    rec = _record('%s - "WebSocket %s" [accepted]', ("172.17.0.1", 5000), f"/ws/26?token={JWT}")
    assert RedactTokenFilter().filter(rec) is True
    out = rec.getMessage()
    assert JWT not in out
    assert "eyJ" not in out
    assert '"WebSocket /ws/26?token=[redacted]" [accepted]' in out


def test_token_is_redacted_wherever_it_sits_in_the_query():
    rec = _record('GET %s', f"/x?a=1&token={JWT}&b=2")
    RedactTokenFilter().filter(rec)
    assert rec.getMessage() == "GET /x?a=1&token=[redacted]&b=2"


def test_refresh_token_parameter_is_redacted_too():
    rec = _record(f"refresh_token={JWT} rejected")
    RedactTokenFilter().filter(rec)
    assert JWT not in rec.getMessage()


def test_lines_without_a_token_are_untouched():
    rec = _record('%s - "GET %s HTTP/1.1" %d', "1.2.3.4", "/api/health", 200)
    RedactTokenFilter().filter(rec)
    assert rec.getMessage() == '1.2.3.4 - "GET /api/health HTTP/1.1" 200'
    # Untouched means untouched: args stay lazy for any other handler.
    assert rec.args == ("1.2.3.4", "/api/health", 200)


def test_a_record_that_cannot_be_formatted_is_passed_through():
    rec = _record("%s %s", "only-one-arg")
    assert RedactTokenFilter().filter(rec) is True


def test_install_covers_the_uvicorn_loggers_once():
    install_token_redaction()
    install_token_redaction()
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        filters = [f for f in logging.getLogger(name).filters if isinstance(f, RedactTokenFilter)]
        assert len(filters) == 1, name
