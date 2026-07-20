"""
Regression tests for multi-tenancy (schools / school_id scoping).

Every bug these cover was live on the branch that introduced tenancy, and all
of them shared a cause: the guard had never executed. `_ensure_test_in_student_grade`
raised AttributeError on attribute access, which is impossible if it had run
even once. So these lean on *real* objects — the actual dataclass, the actual
helper, the actual mapped columns — rather than mocks. A MagicMock stands in for
anything, including a field that doesn't exist, which is precisely the failure
that shipped.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import json

import pytest
from fastapi import HTTPException


# ── Pure scoping helpers ──────────────────────────────────────────────────────

from app.core.tenancy import require_school_id, same_school_or_404


class _User:
    """Minimal stand-in with the only attribute the helpers read."""

    def __init__(self, school_id):
        self.school_id = school_id


class TestRequireSchoolId:
    def test_returns_school_id_for_tenant_user(self):
        assert require_school_id(_User(7)) == 7

    def test_rejects_school_less_account(self):
        # The owner has no school; reaching a tenant endpoint is a bug, and the
        # helper must fail closed rather than run an unscoped query.
        with pytest.raises(HTTPException) as exc:
            require_school_id(_User(None))
        assert exc.value.status_code == 403

    def test_school_id_zero_is_not_treated_as_missing(self):
        # Guards against a truthiness check replacing the `is None` test.
        assert require_school_id(_User(0)) == 0


class TestSameSchoolOr404:
    def test_allows_matching_school(self):
        same_school_or_404(3, 3)  # must not raise

    def test_rejects_other_school(self):
        with pytest.raises(HTTPException) as exc:
            same_school_or_404(3, 4)
        assert exc.value.status_code == 404

    def test_rejects_untenanted_row(self):
        # school_id NULL means the row belongs to no tenant — not to everyone.
        with pytest.raises(HTTPException) as exc:
            same_school_or_404(None, 4)
        assert exc.value.status_code == 404

    def test_uses_404_not_403(self):
        # 404 keeps another school's record indistinguishable from a
        # nonexistent one; 403 would confirm the id exists.
        with pytest.raises(HTTPException) as exc:
            same_school_or_404(1, 2)
        assert exc.value.status_code == 404
        assert "not found" in exc.value.detail.lower()


# ── Suspended-school enforcement ──────────────────────────────────────────────
# Suspension used to apply only at login: school_id was trusted from the JWT
# thereafter, and rotating refresh tokens renewed access indefinitely.

from app.core import tenancy as _tenancy_mod


@pytest.mark.asyncio
class TestAssertSchoolActive:
    async def test_active_school_passes(self, monkeypatch):
        async def _active(school_id, db):
            return True

        monkeypatch.setattr("app.core.cache.is_school_active_cached", _active)
        await _tenancy_mod.assert_school_active(_User(2), db=None)

    async def test_suspended_school_is_rejected(self, monkeypatch):
        async def _inactive(school_id, db):
            return False

        monkeypatch.setattr("app.core.cache.is_school_active_cached", _inactive)
        with pytest.raises(HTTPException) as exc:
            await _tenancy_mod.assert_school_active(_User(2), db=None)
        assert exc.value.status_code == 403
        assert "suspended" in exc.value.detail.lower()

    async def test_owner_is_exempt_and_never_queried(self, monkeypatch):
        # If the owner were gated, suspending a school would lock the operator
        # out of the console needed to un-suspend it.
        calls = []

        async def _spy(school_id, db):
            calls.append(school_id)
            return False

        monkeypatch.setattr("app.core.cache.is_school_active_cached", _spy)
        await _tenancy_mod.assert_school_active(_User(None), db=None)
        assert calls == [], "owner must not be school-gated"

    async def test_rejection_is_403_not_401(self, monkeypatch):
        # 401 would prompt clients to re-authenticate in a loop; the session is
        # valid, the school is not.
        async def _inactive(school_id, db):
            return False

        monkeypatch.setattr("app.core.cache.is_school_active_cached", _inactive)
        with pytest.raises(HTTPException) as exc:
            await _tenancy_mod.assert_school_active(_User(9), db=None)
        assert exc.value.status_code == 403


# ── Cached student profile ────────────────────────────────────────────────────
# The tenancy guard reads profile.school_id. The cached dataclass omitted it,
# so every student test endpoint raised AttributeError -> 500 for legitimate
# same-school students.

from app.core.cache import CachedStudentProfile, _STUDENT_PROFILE_KEY


class TestCachedStudentProfile:
    def test_carries_school_id(self):
        p = CachedStudentProfile(
            user_id=1,
            grade=8,
            additional_subjects=[],
            parent_user_id=None,
            school_id=3,
        )
        assert p.school_id == 3

    def test_tenancy_comparison_does_not_raise(self):
        # The exact expression from _ensure_test_in_student_grade. Reading a
        # missing attribute is what produced the 500.
        p = CachedStudentProfile(
            user_id=1,
            grade=8,
            additional_subjects=None,
            parent_user_id=None,
            school_id=3,
        )
        assert (p.grade != 8 or p.school_id != 3) is False
        assert (p.grade != 8 or p.school_id != 4) is True

    def test_serialised_payload_round_trips_school_id(self):
        # Mirrors the write/read the cache performs; dropping school_id from
        # either side reintroduces the bug in a subtler form (silent 404s
        # rather than a 500).
        payload = {
            "user_id": 1,
            "grade": 8,
            "additional_subjects": ["ai"],
            "parent_user_id": 2,
            "school_id": 3,
        }
        d = json.loads(json.dumps(payload))
        p = CachedStudentProfile(
            user_id=d["user_id"],
            grade=d["grade"],
            additional_subjects=d.get("additional_subjects"),
            parent_user_id=d.get("parent_user_id"),
            school_id=d.get("school_id"),
        )
        assert p.school_id == 3

    def test_cache_key_is_versioned(self):
        # Entries written before school_id existed would deserialise to
        # school_id=None and 404 legitimate students until the TTL expired.
        # Any future field addition needs the same bump, so pin the version.
        key = _STUDENT_PROFILE_KEY.format(user_id=42)
        assert ":v2:" in key
        assert key.endswith("42")


# ── Structural contract ───────────────────────────────────────────────────────
# Catches the next tenant table that forgets scoping, which no behavioural test
# will notice until data leaks through it.

from app.models.mixins import TenantMixin


def _tenant_models():
    import app.models  # noqa: F401  (registers every mapper)

    seen = {}
    stack = [TenantMixin]
    while stack:
        for sub in stack.pop().__subclasses__():
            if sub not in seen:
                seen[sub] = True
                stack.append(sub)
    return [m for m in seen if hasattr(m, "__tablename__")]


class TestTenantModelContract:
    def test_some_models_are_tenant_scoped(self):
        # Guards the discovery itself: if imports change and this returns
        # nothing, the tests below would vacuously pass.
        assert len(_tenant_models()) > 10

    def test_every_tenant_model_has_school_id(self):
        missing = [
            m.__tablename__ for m in _tenant_models() if not hasattr(m, "school_id")
        ]
        assert missing == [], f"TenantMixin models without school_id: {missing}"

    def test_school_id_column_definition(self):
        # conftest stubs Base, so the models are never mapped and have no
        # __table__. The mixin declares the column once for all of them, so
        # assert the contract where it is actually defined.
        col = TenantMixin.school_id.column
        assert col.nullable is True, "school_id is nullable to keep backfills simple"
        assert col.index is True, "every scoped query filters on school_id"
        fks = list(col.foreign_keys)
        assert {fk.target_fullname for fk in fks} == {"schools.id"}
        # RESTRICT, not CASCADE: deleting a school must not silently take its
        # data with it.
        assert [fk.ondelete for fk in fks] == ["RESTRICT"]

    def test_migration_table_list_matches_models(self):
        # Drift guard: a model gaining TenantMixin without the migration adding
        # the column leaves the app querying a column that doesn't exist.
        import re
        from pathlib import Path

        mig = (
            Path(__file__).resolve().parents[1]
            / "alembic"
            / "versions"
            / "031_tenant_school_id_columns.py"
        )
        block = re.search(
            r"_TENANT_TABLES\s*=\s*\[(.*?)\]", mig.read_text(), re.S
        ).group(1)
        migrated = set(re.findall(r'"([^"]+)"', block))
        # users is handled by 030, audit_logs by 032.
        modelled = {m.__tablename__ for m in _tenant_models()} - {"users", "audit_logs"}
        assert modelled - migrated == set(), (
            f"tenant models missing from migration 031: {modelled - migrated}"
        )
