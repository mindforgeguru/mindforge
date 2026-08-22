"""
Production write-guard for the API integration suite (tests/test_api.py).

That suite REGISTERS, APPROVES and REVOKES users against whatever host it points
at. Its default target is production, and a bare `pytest tests/test_api.py` once
wrote to the live database by accident (run 30118897312). These two pure
functions are the guard that now refuses to run against production without an
explicit override, pulled out here so they can be unit-tested without importing
the suite (which would trigger its module-level skip).
"""


def is_production(url: str) -> bool:
    """True if the target host is production. Substring match on the production
    domain, so every prod form — bare, www, api, http/https — is caught."""
    return "mindforge.guru" in (url or "")


def should_block(url: str, allow_prod_env: str | None) -> bool:
    """True if the write-heavy suite must refuse to run.

    Blocks any production target unless the operator has explicitly set
    MF_API_ALLOW_PROD=1. A non-production target (local/staging) never blocks.
    Fails safe: only the exact string "1" opens the gate, so an empty, unset, or
    fat-fingered value keeps production protected.
    """
    return is_production(url) and allow_prod_env != "1"
