"""
Two-factor sign-in holds up once an attacker has the MPIN.

Driven for the first time with an enrolled account on 2026-10-17, and three
gaps found:

- the same authenticator code signed in twice — a code seen over a shoulder or
  through a phishing proxy stayed good for its whole ~90 s window;
- one recovery code sent five times at once gave five sessions, though a
  recovery code is meant to work once;
- a wrong code never counted towards the account lockout. Only the login rate
  limit applied, and that is per IP, so guesses spread over many addresses had
  no limit at all on a six-digit code.
"""

import threading
import time

import httpx
import pyotp
import pytest

from .conftest import BASE_URL, PREFIX, RUN_ID, TEST_MPIN, auth, login


@pytest.fixture
def enrolled(api, owner_token, request):
    """A school admin with two-factor on: (school_id, username, totp, recovery codes)."""
    tag = request.node.name[5:17].replace("_", "")
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest MFA {tag} {RUN_ID}", "slug": f"{PREFIX}-mfa-{tag}"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    username = f"{PREFIX}mfa{tag}"
    r = api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
                 json={"username": username, "mpin": TEST_MPIN})
    assert r.status_code == 201, r.text
    headers = auth(login(api, username, school_id=sid))

    secret = api.post("/api/auth/mfa/setup", headers=headers).json()["secret"]
    totp = pyotp.TOTP(secret)
    r = api.post("/api/auth/mfa/confirm", headers=headers, json={"code": totp.now()})
    assert r.status_code == 200, r.text
    # Let the enrolment code's step pass so the tests start with a fresh one.
    time.sleep(31 - time.time() % 30)
    return sid, username, totp, r.json()["recovery_codes"]


def _login(client, sid, username, **factor):
    return client.post("/api/auth/login",
                       json={"username": username, "mpin": TEST_MPIN, "school_id": sid, **factor})


def test_an_authenticator_code_signs_in_once(api, enrolled):
    sid, username, totp, _ = enrolled
    code = totp.now()
    assert _login(api, sid, username, mfa_code=code).status_code == 200
    r = _login(api, sid, username, mfa_code=code)
    assert r.status_code == 401, r.text


def test_a_recovery_code_sent_at_once_signs_in_once(api, enrolled):
    sid, username, _, codes = enrolled
    statuses = []
    gate = threading.Barrier(5)

    def one():
        with httpx.Client(base_url=BASE_URL, timeout=30) as c:
            gate.wait()
            statuses.append(_login(c, sid, username, recovery_code=codes[0]).status_code)

    threads = [threading.Thread(target=one) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(statuses) == [200, 401, 401, 401, 401], statuses


def test_wrong_codes_lock_the_account_like_wrong_mpins(api, enrolled):
    sid, username, totp, _ = enrolled
    right = totp.now()
    wrong = f"{(int(right) + 1) % 1_000_000:06d}"
    for _ in range(5):
        assert _login(api, sid, username, mfa_code=wrong).status_code == 401
    r = _login(api, sid, username, mfa_code=right)
    assert r.status_code == 429, r.text
