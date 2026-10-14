"""
Sentry PII/credential scrubber.

Before an error event leaves the process, sensitive keys in the request payload
must be redacted — credentials (a live MPIN/token in a crash report is a real
secret) and a minor's direct identifiers (phone/email). These pin that, plus the
two properties that are easy to get wrong: it must recurse into nested bodies,
and it must never raise (a throwing before_send drops the whole event).
"""

import pytest

from app.core.sentry_scrub import scrub_event, SCRUB_KEYS


def _event(**request):
    return {"request": request}


class TestCredentialsAreRedacted:
    def test_mpin_and_tokens_in_the_body(self):
        e = scrub_event(_event(data={"username": "priya8", "mpin": "918273",
                                     "refresh_token": "eyJ..."}))
        d = e["request"]["data"]
        assert d["mpin"] == "[scrubbed]"
        assert d["refresh_token"] == "[scrubbed]"
        assert d["username"] == "priya8"  # not a secret, kept for debugging

    def test_authorization_and_cookie_headers(self):
        e = scrub_event(_event(
            headers={"Authorization": "Bearer abc", "User-Agent": "x"},
            cookies={"cookie": "session=abc"}))
        assert e["request"]["headers"]["Authorization"] == "[scrubbed]"
        assert e["request"]["headers"]["User-Agent"] == "x"
        assert e["request"]["cookies"]["cookie"] == "[scrubbed]"


class TestMinorIdentifiersAreRedacted:
    def test_phone_and_email_do_not_reach_sentry(self):
        # The app holds children's records; a student's contact details must not
        # ride along in an error report.
        e = scrub_event(_event(data={"phone": "9876543210",
                                     "email": "kid@example.com",
                                     "parent_phone": "9999999999"}))
        d = e["request"]["data"]
        assert d["phone"] == "[scrubbed]"
        assert d["email"] == "[scrubbed]"
        assert d["parent_phone"] == "[scrubbed]"


class TestRobustness:
    def test_matching_is_case_insensitive(self):
        e = scrub_event(_event(data={"MPIN": "918273", "Email": "a@b.com"}))
        assert e["request"]["data"]["MPIN"] == "[scrubbed]"
        assert e["request"]["data"]["Email"] == "[scrubbed]"

    def test_nested_bodies_are_scrubbed(self):
        # A body isn't always flat — a nested parent object must be caught.
        e = scrub_event(_event(data={"student": {"name": "priya",
                                                 "parent": {"phone": "999"}}}))
        assert e["request"]["data"]["student"]["parent"]["phone"] == "[scrubbed]"

    def test_lists_of_objects_are_scrubbed(self):
        e = scrub_event(_event(data={"users": [{"email": "a@b.com"},
                                               {"email": "c@d.com"}]}))
        assert all(u["email"] == "[scrubbed]"
                   for u in e["request"]["data"]["users"])

    def test_a_malformed_event_does_not_raise(self):
        # before_send that throws drops the event entirely, so it must swallow
        # anything odd and return the event.
        for bad in (None, {}, {"request": None}, {"request": {"data": "raw-string"}},
                    {"request": {"data": 12345}}):
            assert scrub_event(bad) is bad

    def test_non_sensitive_data_is_left_intact(self):
        e = scrub_event(_event(data={"grade": 8, "subject": "economics"}))
        assert e["request"]["data"] == {"grade": 8, "subject": "economics"}


class TestQueryStringIsRedacted:
    """The WebSocket handshake carries the access token as `?token=…`, and
    Sentry records the query string of whatever request an event belongs to."""

    def test_the_websocket_token_in_a_query_string(self):
        e = scrub_event(_event(url="ws://h/ws/2",
                               query_string="token=eyJhbGciOi.abc.def&grade=8"))
        assert "eyJ" not in e["request"]["query_string"]
        assert "grade=8" in e["request"]["query_string"]

    def test_a_query_string_given_as_a_mapping(self):
        e = scrub_event(_event(query_string={"token": "eyJ...", "grade": "8"}))
        assert e["request"]["query_string"] == {"token": "[scrubbed]", "grade": "8"}

    def test_a_token_inside_a_breadcrumb(self):
        e = scrub_event({"breadcrumbs": {"values": [
            {"message": 'WebSocket /ws/2?token=eyJhbGciOi.abc.def [accepted]',
             "data": {"url": "ws://h/ws/2?token=eyJhbGciOi.abc.def", "mpin": "918273"}},
        ]}})
        crumb = e["breadcrumbs"]["values"][0]
        assert "eyJ" not in crumb["message"]
        assert "eyJ" not in crumb["data"]["url"]
        assert crumb["data"]["mpin"] == "[scrubbed]"


class TestStackFrameVariablesAreDropped:
    """A frame's local variables are whatever the handler was holding when it
    failed — the login payload, an MPIN, a student's phone. They cannot be
    redacted by name (`payload` is not a sensitive name; its repr is), so they
    do not leave the process at all."""

    def test_locals_are_removed_from_every_frame(self):
        e = scrub_event({"exception": {"values": [{"stacktrace": {"frames": [
            {"function": "login", "vars": {"payload": "LoginRequest(mpin='918273')"}},
            {"function": "inner", "vars": {"student_phone": "'9811122233'"}},
        ]}}]}})
        frames = e["exception"]["values"][0]["stacktrace"]["frames"]
        assert all("vars" not in f for f in frames)
        assert [f["function"] for f in frames] == ["login", "inner"]


class TestWhatActuallyLeavesTheProcess:
    """The scrubber fed by the real SDK, configured the way main.py configures
    it. Hand-built events only prove the scrubber handles the shapes someone
    thought of; this proves a real crash report is clean."""

    MPIN = "CANARY_MPIN_918273"
    TOKEN = "CANARY_TOKEN_eyJhbGciOi"
    PHONE = "CANARY_PHONE_9811122233"

    def _capture(self):
        import json

        sentry_sdk = pytest.importorskip("sentry_sdk")
        from sentry_sdk.transport import Transport

        from app.core.sentry_scrub import sentry_privacy_options

        sent = []

        class _Capture(Transport):
            def capture_envelope(self, envelope):
                sent.extend(json.dumps(i.payload.json) for i in envelope.items)

        client = sentry_sdk.Client(
            dsn="https://key@sentry.invalid/1",
            transport=_Capture,
            default_integrations=False,
            **sentry_privacy_options(),
        )

        def _login(payload, mpin, refresh_token):
            student_phone = self.PHONE
            raise RuntimeError(f"failed for {payload['username']}")

        with sentry_sdk.new_scope() as scope:
            scope.set_client(client)
            scope.add_breadcrumb(message=f"WebSocket /ws/2?token={self.TOKEN} [accepted]")
            try:
                _login({"username": "priya8", "mpin": self.MPIN}, self.MPIN, self.TOKEN)
            except RuntimeError:
                scope.capture_exception()
            client.flush()
        assert sent, "nothing was captured"
        return "\n".join(sent)

    def test_a_crash_report_carries_no_mpin_token_or_phone(self):
        blob = self._capture()
        assert self.MPIN not in blob
        assert self.TOKEN not in blob
        assert self.PHONE not in blob
        assert "failed for priya8" in blob  # the error itself still arrives

    def test_traces_are_scrubbed_as_well_as_errors(self):
        from app.core.sentry_scrub import sentry_privacy_options

        opts = sentry_privacy_options()
        assert opts["before_send_transaction"] is scrub_event
        assert opts["before_send"] is scrub_event
        assert opts["send_default_pii"] is False
        assert opts["include_local_variables"] is False
