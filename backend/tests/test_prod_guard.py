"""
Production write-guard for the API integration suite.

tests/test_api.py registers, approves and revokes users against whatever host it
targets, and its default target is production. A bare run once wrote to the live
database. The guard in tests/prod_guard.py refuses to run against production
without an explicit MF_API_ALLOW_PROD=1. These tests pin it so a refactor can't
quietly reopen that door.

The guard lives at repo-root tests/prod_guard.py; this file (in backend/tests,
where CI's per-file suite runs) loads it straight from source.
"""

import importlib.util
import pathlib

import pytest

_GUARD = pathlib.Path(__file__).resolve().parents[2] / "tests" / "prod_guard.py"
_spec = importlib.util.spec_from_file_location("_prod_guard", _GUARD)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_production = _mod.is_production
should_block = _mod.should_block

PROD_URLS = [
    "https://api.mindforge.guru",
    "https://mindforge.guru",
    "https://www.mindforge.guru",
    "http://api.mindforge.guru",
    "https://api.mindforge.guru/api/auth/login",
]
SAFE_URLS = [
    "http://127.0.0.1:8000",
    "http://localhost:8000",
    "https://staging.example.test",
    "http://backend:8000",
]


class TestIsProduction:
    @pytest.mark.parametrize("url", PROD_URLS)
    def test_production_hosts_are_recognised(self, url):
        assert is_production(url) is True

    @pytest.mark.parametrize("url", SAFE_URLS)
    def test_local_and_staging_hosts_are_not_production(self, url):
        assert is_production(url) is False

    def test_empty_or_none_is_not_production(self):
        assert is_production("") is False
        assert is_production(None) is False


class TestShouldBlock:
    @pytest.mark.parametrize("url", PROD_URLS)
    def test_production_is_blocked_without_the_override(self, url):
        assert should_block(url, None) is True
        assert should_block(url, "") is True
        assert should_block(url, "0") is True
        assert should_block(url, "true") is True   # only the exact "1" opens it

    @pytest.mark.parametrize("url", PROD_URLS)
    def test_production_is_allowed_only_with_the_exact_override(self, url):
        assert should_block(url, "1") is False

    @pytest.mark.parametrize("url", SAFE_URLS)
    def test_non_production_never_blocks(self, url):
        assert should_block(url, None) is False
        assert should_block(url, "1") is False
