"""
Secrets in the working tree.

Real credentials live in .env files (POSTGRES_*, MINIO_*, JWT_SECRET, provider
API keys). The only thing standing between those and a public git repo is
.gitignore, and it's easy to add a new environment file — .env.production,
.env.staging — that an older pattern didn't cover. These tests ask git directly:
every sensitive env variant is ignored, the committed template is not, and no
real .env is tracked. gitleaks guards what's already committed; this guards what
could be committed next.
"""

import pathlib
import subprocess

import pytest

_REPO = pathlib.Path(__file__).resolve().parents[2]

# Every one of these would carry live secrets and must be ignored.
SECRET_ENV_FILES = [
    ".env",
    ".env.local",
    ".env.production",
    ".env.staging",
    ".env.dev",
    ".env.production.local",
    "backend/.env",
    "backend/.env.production",
    "frontend/.env",
    "frontend/.env.production",
]

# The one env file that is meant to be committed (no secrets, just keys).
TEMPLATE = ".env.example"


def _has_git() -> bool:
    try:
        subprocess.run(["git", "-C", str(_REPO), "rev-parse"],
                       capture_output=True, check=True)
        return True
    except Exception:
        return False


def _is_ignored(path: str) -> bool:
    # git check-ignore exits 0 when the path is ignored, 1 when it is not.
    r = subprocess.run(["git", "-C", str(_REPO), "check-ignore", "-q", path],
                       capture_output=True)
    return r.returncode == 0


pytestmark = pytest.mark.skipif(not _has_git(), reason="git not available")


@pytest.mark.parametrize("path", SECRET_ENV_FILES)
def test_secret_env_files_are_ignored(path):
    assert _is_ignored(path), (
        f"{path} is NOT gitignored — a real secret file at that path could be "
        f"committed. Widen the .env pattern in .gitignore.")


def test_the_example_template_stays_trackable():
    # Over-broad ignoring would swallow the template developers copy from.
    assert not _is_ignored(TEMPLATE), (
        f"{TEMPLATE} is ignored — add a `!{TEMPLATE}` negation so it stays "
        f"tracked.")


def test_no_real_env_file_is_committed():
    out = subprocess.run(
        ["git", "-C", str(_REPO), "ls-files"],
        capture_output=True, text=True, check=True).stdout.splitlines()
    tracked_env = [
        f for f in out
        if pathlib.PurePosixPath(f).name.startswith(".env")
        and not pathlib.PurePosixPath(f).name.startswith(".env.example")
        and ".sample" not in f and ".template" not in f
    ]
    assert not tracked_env, f"real .env file(s) are tracked in git: {tracked_env}"
