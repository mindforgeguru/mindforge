"""
Sentry PII/credential scrubber.

Before an error event leaves the process, sensitive keys in the request payload
must be redacted — credentials (a live MPIN/token in a crash report is a real
secret) and a minor's direct identifiers (phone/email). These pin that, plus the
two properties that are easy to get wrong: it must recurse into nested bodies,
and it must never raise (a throwing before_send drops the whole event).
"""

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
