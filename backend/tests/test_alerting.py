"""
Security alerting pipeline.

Detection (credential-spray) is covered in test_security_events.py. This covers
the *alerting* half: that a security event logged at ERROR actually becomes a
Sentry event (an alert), that ordinary warnings stay breadcrumbs (so the alert
channel isn't drowned in noise), and that the spray alert names no accounts —
the whole reason spray_summary ships only an IP and a count.

Runs Sentry with a discarding transport (no network) and a before_send that
records events, so the pipeline is exercised without a live DSN.
"""

import logging

import pytest
import sentry_sdk
from sentry_sdk.transport import Transport

from app.core.security_events import (
    SPRAY_DISTINCT_USERNAMES,
    is_spray,
    spray_summary,
)

SEC = logging.getLogger("mindforge.security")


class _DiscardTransport(Transport):
    """Swallows every envelope — the pipeline runs, nothing leaves the process."""

    def capture_envelope(self, envelope):  # noqa: D401
        pass


@pytest.fixture
def alerts():
    captured = []
    sentry_sdk.init(
        dsn="https://public@example.invalid/1",
        before_send=lambda event, hint: (captured.append(event), event)[1],
        transport=_DiscardTransport,  # never touches the network
        default_integrations=True,  # includes LoggingIntegration (event_level=ERROR)
    )
    try:
        yield captured
    finally:
        sentry_sdk.get_client().close()


def _events(captured):
    return [e for e in captured if e.get("level") == "error"]


def _message(event):
    return (event.get("logentry") or {}).get("message") or event.get("message") or ""


def test_an_error_escalates_to_a_sentry_alert(alerts):
    SEC.error("something security-relevant happened")
    sentry_sdk.flush(timeout=1)
    assert _events(alerts), "an ERROR log did not produce a Sentry event"


def test_a_warning_stays_a_breadcrumb_not_an_alert(alerts):
    # The design relies on this: spray detection escalates to ERROR *precisely*
    # so it alerts, while routine warnings (a single failed login) do not.
    SEC.warning("one failed login — routine")
    sentry_sdk.flush(timeout=1)
    assert not alerts, "a warning should be a breadcrumb, not an alert event"


def test_the_spray_alert_reaches_sentry_without_naming_accounts(alerts):
    n = SPRAY_DISTINCT_USERNAMES
    assert is_spray(n)
    SEC.error(spray_summary("203.0.113.9", n))
    sentry_sdk.flush(timeout=1)

    events = _events(alerts)
    assert events, "the spray summary at ERROR did not alert"
    msg = _message(events[0])
    # The alert says which address and how many accounts...
    assert "203.0.113.9" in msg
    assert f"{n} distinct" in msg
    # ...but never the accounts themselves — shipping the targeted usernames to a
    # third party is exactly the data an attacker was fishing for.
    for account in ("priya8", "isha8", "hansel_kid", "demo_admin"):
        assert account not in msg


def test_just_below_the_threshold_is_not_a_spray():
    # A boundary check on the detector the alert is built on.
    assert is_spray(SPRAY_DISTINCT_USERNAMES) is True
    assert is_spray(SPRAY_DISTINCT_USERNAMES - 1) is False
