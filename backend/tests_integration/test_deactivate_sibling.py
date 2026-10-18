"""
Deactivating one child does not lock their parent out of the other.

Deactivating a student deactivates their parent too, so a family that has left
loses the parent's access as well. With siblings it locked the parent out of
the child still at the school (found 2026-10-18). The parent now goes only with
their last active child.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, _make_student, auth


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


@pytest.fixture
def family(two_schools):
    def make(tag):
        sid = two_schools["a"]["id"]
        kids = [asyncio.run(_make_student(sid, f"{PREFIX}_{tag}_{n}", new=True)) for n in (1, 2)]
        parent = asyncio.run(_sql(
            """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
               VALUES ($1, 'x', 'parent', $2, true, true) RETURNING id""", f"{PREFIX}_{tag}_parent", sid))
        asyncio.run(_sql("UPDATE student_profiles SET parent_user_id = $1 WHERE user_id = ANY($2::int[])",
                         parent, kids))
        return kids, parent
    return make


def _deactivate(api, two_schools, user_id):
    r = api.patch(f"/api/admin/users/{user_id}/active",
                  headers=auth(two_schools["a"]["admin_token"]), json={"is_active": False})
    assert r.status_code == 200, r.text


def _parent_active(parent):
    return asyncio.run(_sql("SELECT is_active FROM users WHERE id = $1", parent))


def test_the_parent_stays_while_another_child_is_active(api, two_schools, family):
    (first, second), parent = family("deact_sib")
    _deactivate(api, two_schools, first)
    assert _parent_active(parent) is True
    _deactivate(api, two_schools, second)
    assert _parent_active(parent) is False


def test_an_only_childs_parent_is_still_deactivated(api, two_schools, family):
    (first, second), parent = family("deact_only")
    asyncio.run(_sql("UPDATE users SET deleted_at = now() WHERE id = $1", second))
    _deactivate(api, two_schools, first)
    assert _parent_active(parent) is False
