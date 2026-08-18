"""
Application-level request throttle.

`nginx/nginx.conf` defines a 120 r/m per-IP zone for the API, but nginx only
exists in the docker-compose stack. Production runs `backend/Dockerfile`'s
`start.sh` on :8000 behind Railway's edge, so that zone is never loaded — the
limit reads as present in the repo and does not ship. This module puts an
equivalent ceiling inside the app, where it travels with the deployment.

Scope, deliberately: this is a blast-radius cap on a runaway client or a
scripted burst, not a security control. The limits that matter for security —
login at 10/min per (IP, username), register at 5/min, AI generation at 20/hour
per user — stay in their routers, are much stricter, and are unaffected by
anything here.

Two design choices worth stating:

* **Per identity, not per IP.** A whole school NATs to one address. Bucketing by
  IP would let one busy teacher throttle the entire staff room, which is an
  outage caused by the mitigation.

* **Fails open.** `redis_manager.rate_limit` returns False when Redis is down,
  and that is the behaviour we want here: losing Redis should not take the API
  with it. A tighter stance belongs on the auth endpoints, which have it.
"""

from typing import Optional

# 300/min is roughly 5 requests a second sustained. A dashboard fanning out to
# a handful of endpoints, then the user moving between screens, sits an order of
# magnitude below this; a runaway retry loop clears it in seconds.
GLOBAL_MAX_PER_MINUTE = 300
GLOBAL_WINDOW_SECONDS = 60

# Kept narrow on purpose — see the test that asserts it stays shallow.
#
#  /api/health — a throttled health check turns a traffic spike into a failed
#    liveness probe, which restarts the container and deepens the spike.
#  /ws        — one long-lived connection rather than a request stream, and it
#    authenticates itself (see test_websocket_auth.py).
EXEMPT_PATHS = ("/api/health", "/ws")


def is_exempt(path: str) -> bool:
    """True for paths that must never be throttled."""
    return any(path == p or path.startswith(p + "/") for p in EXEMPT_PATHS)


def throttle_identity(user_id: Optional[int], client_ip: Optional[str]) -> str:
    """Redis key for whoever is making this request.

    Prefers the authenticated user id so shared egress addresses don't pool.
    Falls back to IP for unauthenticated traffic, and to a fixed bucket when the
    ASGI server reports no client — rare, but it must not raise mid-request.
    """
    if user_id is not None:
        return f"rate_limit:global:user:{user_id}"
    if client_ip:
        return f"rate_limit:global:ip:{client_ip}"
    return "rate_limit:global:ip:unknown"
