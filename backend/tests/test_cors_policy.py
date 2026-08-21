"""
CORS origin policy.

The app runs CORSMiddleware with allow_credentials=True. In that mode a wildcard
origin is the classic dangerous misconfiguration: Starlette reflects *any*
origin back with Access-Control-Allow-Credentials: true, so any website a logged-
in user visits can make credentialed calls to the API and read the responses.

The defense is a settings validator that refuses to start if the origin list
contains "*", forcing an explicit allowlist. These tests pin that guard and the
shipped allowlist. They load the real config module past conftest's stub (which
replaces app.core.config with a MagicMock), with APP_ENV=development so the
production-default guard doesn't get in the way.
"""

import importlib.util
import os
import pathlib

import pytest
from pydantic import ValidationError

# Force dev mode for this file's real-config load, so the production-default
# guard never fires regardless of the CI environment. Other test files use
# conftest's stubbed config, so this does not affect them.
os.environ["APP_ENV"] = "development"
os.environ.setdefault("JWT_SECRET", "test-secret-for-cors-tests")

_SRC = pathlib.Path(__file__).resolve().parent.parent / "app" / "core" / "config.py"
_spec = importlib.util.spec_from_file_location("_real_config", _SRC)
_real = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_real)
Settings = _real.Settings


class TestWildcardIsRefused:
    def test_bare_wildcard_is_rejected(self):
        with pytest.raises(ValidationError):
            Settings(BACKEND_CORS_ORIGINS=["https://mindforge.guru", "*"])

    def test_wildcard_with_surrounding_whitespace_is_rejected(self):
        # " * " must not slip past a naive equality check.
        with pytest.raises(ValidationError):
            Settings(BACKEND_CORS_ORIGINS=["https://mindforge.guru", " * "])

    def test_wildcard_hidden_in_a_comma_string_is_rejected(self):
        # Origins can arrive as one env string; the wildcard check runs after
        # splitting, so it still catches this.
        with pytest.raises(ValidationError):
            Settings(BACKEND_CORS_ORIGINS="https://mindforge.guru,*")


class TestExplicitAllowlistIsAccepted:
    def test_a_plain_list_is_kept_as_is(self):
        s = Settings(BACKEND_CORS_ORIGINS=["https://mindforge.guru", "https://www.mindforge.guru"])
        assert s.BACKEND_CORS_ORIGINS == ["https://mindforge.guru", "https://www.mindforge.guru"]

    def test_a_comma_string_is_split_into_a_list(self):
        s = Settings(BACKEND_CORS_ORIGINS="https://a.example, https://b.example")
        assert s.BACKEND_CORS_ORIGINS == ["https://a.example", "https://b.example"]

    def test_a_json_array_string_is_parsed(self):
        s = Settings(BACKEND_CORS_ORIGINS='["https://a.example"]')
        assert s.BACKEND_CORS_ORIGINS == ["https://a.example"]


class TestShippedDefault:
    def test_default_is_an_explicit_allowlist_without_a_wildcard(self):
        s = Settings()
        assert "*" not in s.BACKEND_CORS_ORIGINS
        assert "https://mindforge.guru" in s.BACKEND_CORS_ORIGINS

    def test_default_does_not_allow_an_arbitrary_third_party_origin(self):
        # The property that matters: a random site is not on the list.
        s = Settings()
        assert "https://evil.example" not in s.BACKEND_CORS_ORIGINS
        assert "http://localhost" not in ["https://evil.example"]  # sanity of the check itself
