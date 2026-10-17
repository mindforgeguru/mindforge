"""
A value the database refuses as out of range is a 422, not a 500.

`app.core.error_handlers` decides from the SQLSTATE and answers; `main.py` registers it.
Both are exercised here without a database: the error is built the way the
asyncpg adapter builds it, with the code on `orig.pgcode`.
"""

import pytest
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, Field
from fastapi.testclient import TestClient
from sqlalchemy.exc import DBAPIError, IntegrityError

from app.core.error_handlers import INVALID_VALUE_DETAIL, db_value_error, internal_error, is_invalid_value, validation_error


class _Orig(Exception):
    def __init__(self, pgcode):
        super().__init__(pgcode)
        self.pgcode = pgcode


def _err(code, cls=DBAPIError):
    return cls("INSERT ...", {}, _Orig(code))


@pytest.mark.parametrize("code", ["22001", "22003", "22P02", "22007", "23514"])
def test_value_errors_are_the_clients(code):
    assert is_invalid_value(_err(code))


@pytest.mark.parametrize("code", ["23505", "23503", "40001", "08006", None])
def test_other_database_errors_are_not(code):
    # A duplicate key or a lost connection is not bad input.
    assert not is_invalid_value(_err(code))


def _app_raising(exc):
    app = FastAPI()
    app.add_exception_handler(DBAPIError, db_value_error)
    app.add_exception_handler(Exception, internal_error)

    @app.get("/boom")
    async def boom():
        raise exc

    return TestClient(app, raise_server_exceptions=False)


def test_the_app_answers_a_value_error_with_422():
    r = _app_raising(_err("22001")).get("/boom")
    assert r.status_code == 422
    assert r.json() == {"detail": INVALID_VALUE_DETAIL}


def test_a_duplicate_is_a_409():
    # Two requests creating the same row at once; the loser hits the unique
    # index. It already exists — a conflict, not a server fault.
    r = _app_raising(_err("23505", IntegrityError)).get("/boom")
    assert r.status_code == 409


def test_the_app_still_answers_other_database_errors_with_500():
    r = _app_raising(_err("23503", IntegrityError)).get("/boom")
    assert r.status_code == 500
    assert r.json() == {"detail": "Internal server error."}


class _Fee(BaseModel):
    amount: float = Field(gt=0, allow_inf_nan=False)


@pytest.mark.parametrize("token", ["NaN", "Infinity", "-Infinity"])
def test_a_non_finite_number_is_a_readable_422(token):
    # JSON parsing accepts these; the 422 echoes them back, and the stock
    # handler could not encode its own answer, so the client got a 500.
    app = FastAPI()
    app.add_exception_handler(RequestValidationError, validation_error)

    @app.post("/fee")
    async def fee(body: _Fee):
        return {"ok": True}

    r = TestClient(app, raise_server_exceptions=False).post(
        "/fee", content='{"amount": %s}' % token, headers={"Content-Type": "application/json"},
    )
    assert r.status_code == 422, r.text
    assert r.json()["detail"][0]["loc"] == ["body", "amount"]
