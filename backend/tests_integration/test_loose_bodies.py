"""
Endpoints that read a bare JSON object reject the wrong shape with a 422.

The admin's own rename, both bio editors and the push-token update took the
body as a plain `dict` and called `.get()` and `.strip()` on it. A JSON array,
a number where text belongs, or an over-long value was a 500 (found
2026-10-18). They now have schemas like every other endpoint.
"""

import pytest

from .conftest import auth


@pytest.fixture(scope="module")
def school(two_schools):
    return two_schools["a"]


def _cases(school):
    tid = school["teacher_id"]
    admin, teacher = school["admin_token"], school["teacher_token"]
    return [
        (admin, "/api/admin/profile/username", ["x"]),
        (admin, "/api/admin/profile/username", {"username": 5}),
        (admin, "/api/admin/profile/username", {"username": "x" * 101}),
        (admin, f"/api/admin/teachers/{tid}/bio", {"bio": 5}),
        (admin, f"/api/admin/teachers/{tid}/bio", []),
        (teacher, "/api/teacher/profile/bio", {"bio": ["a"]}),
        (teacher, "/api/teacher/profile/bio", "text"),
        (teacher, "/api/auth/fcm-token", {"fcm_token": "x" * 600}),
        (teacher, "/api/auth/fcm-token", []),
    ]


CASE_IDS = ["rename array", "rename number", "rename long", "admin bio number", "admin bio array",
            "bio list", "bio string body", "fcm long", "fcm array"]


@pytest.mark.parametrize("idx", range(len(CASE_IDS)), ids=CASE_IDS)
def test_the_wrong_shape_is_422(api, school, idx):
    token, path, body = _cases(school)[idx]
    r = api.put(path, headers=auth(token), json=body)
    assert r.status_code == 422, f"{path}: {r.status_code} {r.text[:200]}"


def test_a_bio_still_saves(api, school):
    r = api.put("/api/teacher/profile/bio", headers=auth(school["teacher_token"]),
                json={"bio": "  Teaches maths.  "})
    assert r.status_code == 200, r.text
    assert r.json()["bio"] == "Teaches maths."
    r = api.put(f"/api/admin/teachers/{school['teacher_id']}/bio",
                headers=auth(school["admin_token"]), json={"bio": ""})
    assert r.status_code == 200, r.text
