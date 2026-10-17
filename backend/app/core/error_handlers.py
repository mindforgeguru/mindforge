"""
The app's own error responses: a 500, a database value error, and a 422.

Which database errors are the client's fault:

Postgres refuses a value that breaks a column's own rules — too long for its
VARCHAR, too big for its NUMERIC, not valid JSON, failing a CHECK — with a
SQLSTATE in class 22 (data exception) or 23514 (check violation). Those are
bad input, answered 422; a unique-key violation (23505) is a 409, the row
already existing; every other database error is still a 500. The
request schemas should catch such values first (app.schemas.bounds); this is
the net for any field they miss.

A 422 from request validation echoes the rejected input. When that input is a
NaN or Infinity — which JSON parsing accepts and a float field then refuses —
the stock handler cannot encode its own answer and the request ends as a 500,
so non-finite numbers are echoed as text.
"""

import logging
import math
from typing import Any, Optional

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DBAPIError

from app.core.config import settings

logger = logging.getLogger("main")

INVALID_VALUE_DETAIL = "A value is too long or out of range."


def sqlstate(exc: BaseException) -> Optional[str]:
    orig = getattr(exc, "orig", None)
    return getattr(orig, "pgcode", None) or getattr(orig, "sqlstate", None)


def is_invalid_value(exc: BaseException) -> bool:
    code = sqlstate(exc) or ""
    return code.startswith("22") or code == "23514"


def is_duplicate(exc: BaseException) -> bool:
    """A unique-key violation: the row already exists. Nearly always two
    requests creating the same thing at once (a double tap, two people)."""
    return sqlstate(exc) == "23505"


DUPLICATE_DETAIL = "That already exists — it may have just been saved."


def _cors_headers(request: Request) -> dict[str, str]:
    headers: dict[str, str] = {}
    origin = request.headers.get("origin")
    if origin and origin in settings.BACKEND_CORS_ORIGINS:
        headers["Access-Control-Allow-Origin"] = origin
        headers["Access-Control-Allow-Credentials"] = "true"
        headers["Vary"] = "Origin"
    return headers


async def internal_error(request: Request, exc: Exception) -> JSONResponse:
    logger.exception(
        "Unhandled error on %s %s", request.method, request.url.path,
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error."},
        headers=_cors_headers(request),
    )


async def db_value_error(request: Request, exc: DBAPIError) -> JSONResponse:
    if is_duplicate(exc):
        logger.warning(
            "Refused a duplicate on %s %s (SQLSTATE 23505)", request.method, request.url.path,
        )
        return JSONResponse(
            status_code=409,
            content={"detail": DUPLICATE_DETAIL},
            headers=_cors_headers(request),
        )
    if not is_invalid_value(exc):
        return await internal_error(request, exc)
    logger.warning(
        "Refused an out-of-range value on %s %s (SQLSTATE %s)",
        request.method, request.url.path, sqlstate(exc),
    )
    return JSONResponse(
        status_code=422,
        content={"detail": INVALID_VALUE_DETAIL},
        headers=_cors_headers(request),
    )


def _finite(value: Any) -> Any:
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {k: _finite(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_finite(v) for v in value]
    return value


async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={"detail": _finite(jsonable_encoder(exc.errors()))},
    )
