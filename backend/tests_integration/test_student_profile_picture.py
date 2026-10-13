"""
A student can set and replace their profile picture.

The upload handler read the student's profile through the Redis-backed cache,
which hands back a plain snapshot (grade, subjects, parent, school) rather than
the database row. The snapshot has no picture field, so every upload ended in a
500 — after the image had already been written to storage.
"""

import asyncio
import io

import asyncpg
import pytest
from PIL import Image

from .conftest import DB_DSN, PREFIX, _make_student, auth
from .test_realtime_delivery import _mint_access_token


def _png(colour):
    buf = io.BytesIO()
    Image.new("RGB", (64, 64), colour).save(buf, format="PNG")
    return buf.getvalue()


async def _stored_urls(student_id):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchrow(
            "SELECT u.profile_pic_url AS user_url, p.profile_pic_url AS profile_url "
            "FROM users u JOIN student_profiles p ON p.user_id = u.id "
            "WHERE u.id = $1",
            student_id,
        )
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def pic_student(two_schools):
    sid = asyncio.run(_make_student(two_schools["a"]["id"], f"{PREFIX}_pic_student"))
    return {"id": sid, "headers": auth(_mint_access_token(sid))}


def _upload(api, student, colour):
    return api.post(
        "/api/student/profile/picture",
        headers=student["headers"],
        files={"file": ("me.png", _png(colour), "image/png")},
    )


def test_a_student_can_upload_a_profile_picture(api, pic_student):
    r = _upload(api, pic_student, "navy")
    assert r.status_code == 200, r.text
    url = r.json()["profile_pic_url"]
    assert url

    row = asyncio.run(_stored_urls(pic_student["id"]))
    assert row["user_url"] == url
    assert row["profile_url"] == url

    # Where the app reads it from after login.
    me = api.get("/api/auth/me", headers=pic_student["headers"])
    assert me.status_code == 200, me.text
    assert me.json()["profile_pic_url"] == url

    assert api.get(url, headers=pic_student["headers"]).status_code == 200


def test_replacing_the_picture_removes_the_old_one(api, pic_student):
    first = _upload(api, pic_student, "navy")
    assert first.status_code == 200, first.text
    second = _upload(api, pic_student, "orange")
    assert second.status_code == 200, second.text

    old_url = first.json()["profile_pic_url"]
    new_url = second.json()["profile_pic_url"]
    assert new_url != old_url
    assert api.get(new_url, headers=pic_student["headers"]).status_code == 200
    assert api.get(old_url, headers=pic_student["headers"]).status_code == 404
