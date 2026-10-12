"""
A student cannot wear a theme their level no longer unlocks.

Themes unlock by level, and `select_theme` refuses one the student has not
reached. XP only ever goes down through an admin's manual adjustment, and that
path forgot the theme: a student taken from level 5 back to level 1 kept the
level-5 theme, and the picker showed it as active with a lock on it.
"""

import asyncio

import pytest

from .conftest import PREFIX, _make_student, auth
from .test_realtime_delivery import _mint_access_token

LEVEL_5_XP = 1118  # level_configs: level 5, which unlocks "tide_breeze"


@pytest.fixture(scope="module")
def xp_student(two_schools):
    """A student of this module's own, so XP changes cannot disturb the
    leaderboard and isolation checks that read the shared students."""
    sid = asyncio.run(_make_student(two_schools["a"]["id"], f"{PREFIX}_xp_student"))
    return {"id": sid, "headers": auth(_mint_access_token(sid))}


def _adjust(api, two_schools, student_id, amount):
    r = api.post(
        "/api/xp/admin/adjust",
        headers=auth(two_schools["a"]["admin_token"]),
        json={"student_id": student_id, "amount": amount, "reason": "itest"},
    )
    assert r.status_code == 201, r.text


def _themes(api, student):
    r = api.get("/api/xp/themes", headers=student["headers"])
    assert r.status_code == 200, r.text
    body = r.json()
    return body["selected_theme"], {t["theme_id"]: t for t in body["themes"]}


def test_a_theme_is_dropped_when_the_level_that_unlocked_it_is_lost(
    api, two_schools, xp_student
):
    _adjust(api, two_schools, xp_student["id"], LEVEL_5_XP)
    r = api.post(
        "/api/xp/themes/select",
        headers=xp_student["headers"],
        json={"theme_id": "tide_breeze"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["selected_theme"] == "tide_breeze"

    _adjust(api, two_schools, xp_student["id"], -1)  # 1117 XP: level 4

    selected, themes = _themes(api, xp_student)
    assert themes["tide_breeze"]["unlocked"] is False
    assert themes["tide_breeze"]["selected"] is False, "a locked theme is still active"
    assert selected is None
    assert themes["mind_forge"]["selected"] is True
    me = api.get("/api/xp/me", headers=xp_student["headers"]).json()
    assert me["selected_theme"] is None


def test_a_theme_is_kept_while_the_level_still_unlocks_it(
    api, two_schools, xp_student
):
    """Losing XP is not, by itself, a reason to lose a theme."""
    _adjust(api, two_schools, xp_student["id"], 500)  # 1617 XP: level 6
    r = api.post(
        "/api/xp/themes/select",
        headers=xp_student["headers"],
        json={"theme_id": "tide_breeze"},
    )
    assert r.status_code == 200, r.text

    _adjust(api, two_schools, xp_student["id"], -100)  # 1517 XP: still level 6

    selected, themes = _themes(api, xp_student)
    assert selected == "tide_breeze"
    assert themes["tide_breeze"]["selected"] is True
