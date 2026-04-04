#!/bin/bash
set -e

echo "Starting server..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
