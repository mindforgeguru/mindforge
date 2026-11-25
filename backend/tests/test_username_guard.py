"""username_taken counts case and cross-script look-alikes (J-03/K-21)."""

import asyncio
import importlib.util
import pathlib
import sys
import types


def _load():
    # conftest may stub app.models; give the guard a minimal User with the
    # attributes the query builder touches, and load the real module.
    root = pathlib.Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location(
        "_real_username_guard", root / "app" / "core" / "username_guard.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class _Result:
    def __init__(self, rows): self._rows = rows
    def all(self): return self._rows


class _DB:
    def __init__(self, rows): self.rows = rows
    async def execute(self, _query): return _Result(self.rows)


ROWS = [(1, "aarav8"), (2, "sunrise_admin")]


def _taken(name, exclude=None):
    mod = _load()
    return asyncio.run(mod.username_taken(_DB(ROWS), 944, name, exclude_user_id=exclude))


def test_exact_case_and_lookalike_are_taken():
    assert _taken("aarav8")
    assert _taken("AARAV8")
    assert _taken("аarav8")   # Cyrillic а


def test_a_new_name_is_free():
    assert not _taken("meera8")


def test_renaming_yourself_to_a_case_variant_is_allowed():
    assert not _taken("Sunrise_Admin", exclude=2)
