"""
Detection and alerting for attacks the rate limiters do not stop.

Login is capped at 10/min per (IP, username). That stops someone grinding a
single account. It does nothing about the opposite shape — one likely password
tried once against many accounts — because spraying 200 usernames from one IP is
200 requests that each sit at a tenth of their own budget. The global 300/min
per-IP throttle caps the volume but cannot distinguish a spray from a busy
classroom sharing an address.

Detection is separate from throttling, and this module is the detection half.

**On log levels.** Failed logins are logged at WARNING, and Sentry's logging
integration records WARNING as a *breadcrumb* — attached to some later event,
never an alert on its own. So a spray in progress is invisible unless something
unrelated errors in the same request. Anything here that crosses a threshold is
logged at ERROR precisely so it becomes a Sentry event, and therefore something
that can page a human.

Thresholds are tuned to be quiet. An alert that fires on ordinary behaviour is
worse than no alert, because it teaches people to close the tab.
"""

import logging

# Distinct usernames one IP may fail against inside the window before it counts
# as spraying. A reception desk or a shared family tablet legitimately fails a
# few different logins in a row; an attacker walking a class list tries tens.
SPRAY_DISTINCT_USERNAMES = 8

# Spraying is deliberately slow to stay under per-account limits, so the window
# has to be long enough to span that. A 60-second window would miss it.
SPRAY_WINDOW_SECONDS = 900  # 15 minutes

_log = logging.getLogger("mindforge.security")


def is_spray(distinct_usernames: int) -> bool:
    """True when this many distinct accounts have failed from one IP."""
    return distinct_usernames >= SPRAY_DISTINCT_USERNAMES


def spray_summary(ip: str, distinct_usernames: int) -> str:
    """One line describing the pattern, safe to ship to Sentry.

    Deliberately carries the IP and a count and nothing else. The alert needs to
    say "this address is spraying"; it must not ship a list of the children's
    accounts that were targeted, which would put exactly the data an attacker
    was fishing for into a third-party service.
    """
    return (
        f"Credential spraying suspected: {distinct_usernames} distinct accounts "
        f"failed from ip={ip} within {SPRAY_WINDOW_SECONDS // 60}m"
    )


async def note_failed_login(username: str, ip: str) -> bool:
    """Record a failed login and report whether the source looks like a spray.

    Counts *distinct* usernames per IP over the window using a Redis set, which
    is what separates spraying from one person mistyping repeatedly — the latter
    adds the same member over and over and never grows the set.

    Fails open: a detector that takes the login endpoint down with it is a worse
    outcome than a missed alert.
    """
    from app.core.redis_client import redis_manager

    client = getattr(redis_manager, "_client", None)
    if client is None:
        return False

    key = f"secevent:spray:{ip}"
    try:
        added = await client.sadd(key, username)
        if added:
            # Only (re)set the TTL when the set actually grew, so a steady
            # trickle cannot keep the window alive indefinitely.
            await client.expire(key, SPRAY_WINDOW_SECONDS)
        distinct = await client.scard(key)
    except Exception:
        return False

    if is_spray(distinct):
        # ERROR, not WARNING — see the module docstring. This is the line that
        # turns into a Sentry event.
        _log.error(spray_summary(ip, distinct))
        return True
    return False
