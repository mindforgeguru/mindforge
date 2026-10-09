"""
The owner's duplicate-school error must name what the owner actually typed.

The Add School form only asks for a name; the slug is derived from it and never
shown. The 409 used to say "Choose a different slug" either way, which is
advice the owner cannot act on. These drive the real handler with only the
session faked.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.routers.owner import create_school
from app.schemas.school import SchoolCreate


@pytest.fixture(autouse=True)
def _neutralise_select(monkeypatch):
    """conftest stubs Base, so `select(School)` raises. The session is faked, so
    the query object is irrelevant to what these tests assert."""
    import app.routers.owner as _owner

    monkeypatch.setattr(_owner, "select", lambda *a, **k: MagicMock())


def _db_with_existing_school():
    """AsyncSession stub whose slug lookup finds a school already there."""
    result = MagicMock()
    result.scalar_one_or_none = MagicMock(return_value=object())
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)
    return db


@pytest.mark.asyncio
async def test_name_clash_tells_the_owner_to_change_the_name():
    with pytest.raises(HTTPException) as exc:
        await create_school(
            SchoolCreate(name="Greenwood Academy"),
            db=_db_with_existing_school(),
            current_owner=MagicMock(),
        )
    assert exc.value.status_code == 409
    detail = exc.value.detail
    assert "Greenwood Academy" in detail
    assert "name" in detail
    assert "slug" not in detail


@pytest.mark.asyncio
async def test_explicit_slug_clash_still_names_the_slug():
    # API callers that pass a slug chose it themselves, so the slug is the
    # thing to change.
    with pytest.raises(HTTPException) as exc:
        await create_school(
            SchoolCreate(name="Greenwood Academy", slug="greenwood"),
            db=_db_with_existing_school(),
            current_owner=MagicMock(),
        )
    assert exc.value.status_code == 409
    assert "'greenwood'" in exc.value.detail
    assert "slug" in exc.value.detail
