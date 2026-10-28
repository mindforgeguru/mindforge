"""
Owner rule for changing a test (#40).

A teacher may change their own test, or a colleague's whose creator has left.
Another teacher's live test in the same school is a 403 that says why — the
school-wide /tests listing already shows it exists, so a 404 only produced a
confusing "Test not found" in the app. Another school's test stays a 404.
"""

import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.routers import teacher as teacher_router


def _check(test, me, creator_active):
    async def fake_creator_is_active(_test, _db):
        return creator_active

    original = teacher_router._creator_is_active
    teacher_router._creator_is_active = fake_creator_is_active
    try:
        asyncio.run(teacher_router._require_test_owner(test, me, db=None))
    finally:
        teacher_router._creator_is_active = original


ME = SimpleNamespace(id=11, school_id=1)


def test_own_test_is_allowed():
    _check(SimpleNamespace(teacher_id=11, school_id=1), ME, creator_active=True)


def test_colleagues_test_whose_creator_left_is_allowed():
    _check(SimpleNamespace(teacher_id=2, school_id=1), ME, creator_active=False)


def test_colleagues_live_test_is_403_and_says_why():
    with pytest.raises(HTTPException) as exc:
        _check(SimpleNamespace(teacher_id=2, school_id=1), ME, creator_active=True)
    assert exc.value.status_code == 403
    assert "created this test" in exc.value.detail


def test_other_schools_test_stays_404():
    with pytest.raises(HTTPException) as exc:
        _check(SimpleNamespace(teacher_id=2, school_id=9), ME, creator_active=True)
    assert exc.value.status_code == 404
