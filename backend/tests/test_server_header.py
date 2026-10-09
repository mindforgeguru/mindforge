"""
The API must not announce its server software.

uvicorn sends `server: uvicorn` on every response unless started with
`--no-server-header`. It names no version, so this is minor, but it is free
fingerprinting help and the security probe suite flags it. These pin the flag on
every command that starts the server, so a rewritten start script can't drop it.
"""

import pathlib
import re

import pytest

BACKEND = pathlib.Path(__file__).resolve().parent.parent
REPO = BACKEND.parent


def _uvicorn_commands(text):
    return [line for line in text.splitlines()
            if re.search(r"\buvicorn\s+main:app\b", line)]


def test_production_start_script_hides_the_server_header():
    cmds = _uvicorn_commands((BACKEND / "start.sh").read_text())
    assert cmds, "start.sh no longer starts uvicorn — update this test"
    for cmd in cmds:
        assert "--no-server-header" in cmd, cmd


def test_local_compose_hides_the_server_header():
    # Local security runs should see the same headers as production. The repo
    # root is not mounted into the backend container, so skip there.
    compose = REPO / "docker-compose.local.yml"
    if not compose.exists():
        pytest.skip("repo root not available (running inside the container)")
    cmds = _uvicorn_commands(compose.read_text())
    assert cmds, "docker-compose.local.yml no longer starts uvicorn"
    for cmd in cmds:
        assert "--no-server-header" in cmd, cmd
