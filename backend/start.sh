#!/bin/bash
set -e

echo "Running database migrations..."
alembic upgrade head

echo "Starting server..."
# --no-server-header: don't announce `server: uvicorn` (tests/test_server_header.py)
exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4 --no-server-header
