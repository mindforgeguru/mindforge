"""
Refresh tokens are single-use, and logout ends them.

`/auth/refresh` rotates: it blacklists the token it consumed and hands back a
new pair, so a captured-then-replayed refresh token is refused. `/auth/logout`
blacklists the refresh token the client sends, so it can't mint access after
sign-out. Both land in the same Redis namespace `/refresh` checks — verified by
code 2026-10-18 and pinned here so a namespace drift (logout revoking where
refresh doesn't look) can't pass silently.
"""

import pytest

from .conftest import TEST_MPIN, auth


def _login(api, school):
    r = api.post("/api/auth/login", json={
        "username": school["teacher_username"], "mpin": TEST_MPIN, "school_id": school["id"]})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
def tokens(api, two_schools):
    return _login(api, two_schools["a"])


def test_refresh_rotates_and_the_old_token_is_single_use(api, tokens):
    old_refresh = tokens["refresh_token"]
    r1 = api.post("/api/auth/refresh", json={"refresh_token": old_refresh})
    assert r1.status_code == 200, r1.text
    new_refresh = r1.json()["refresh_token"]
    assert new_refresh != old_refresh

    # Replaying the consumed token is refused …
    assert api.post("/api/auth/refresh", json={"refresh_token": old_refresh}).status_code == 401
    # … while the rotated one still works.
    assert api.post("/api/auth/refresh", json={"refresh_token": new_refresh}).status_code == 200


def test_logout_invalidates_the_refresh_token(api, two_schools):
    t = _login(api, two_schools["a"])
    r = api.post("/api/auth/logout", headers=auth(t["access_token"]),
                 json={"refresh_token": t["refresh_token"]})
    assert r.status_code == 204, r.text
    # The refresh token the client handed to logout can no longer mint access.
    assert api.post("/api/auth/refresh",
                    json={"refresh_token": t["refresh_token"]}).status_code == 401


def test_a_new_access_token_from_refresh_is_usable(api, two_schools):
    t = _login(api, two_schools["a"])
    r = api.post("/api/auth/refresh", json={"refresh_token": t["refresh_token"]})
    assert r.status_code == 200, r.text
    me = api.get("/api/auth/me", headers=auth(r.json()["access_token"]))
    assert me.status_code == 200, me.text
