"""add feedback_reports table for in-app 'Report a problem' submissions

Revision ID: 023
Revises: 022
Create Date: 2026-05-12

Idempotent — uses IF NOT EXISTS so re-runs are safe.
"""
from alembic import op


revision = '023'
down_revision = '022'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS feedback_reports (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            username VARCHAR(100),
            role VARCHAR(20),
            app_version VARCHAR(40),
            route VARCHAR(200),
            message TEXT NOT NULL,
            resolved BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            resolved_at TIMESTAMPTZ
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_feedback_reports_user_id "
        "ON feedback_reports (user_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_feedback_reports_resolved "
        "ON feedback_reports (resolved)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_feedback_reports_created_at "
        "ON feedback_reports (created_at)"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS feedback_reports")
