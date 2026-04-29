"""add test attempt lifecycle columns

Revision ID: 020
Revises: 019
Create Date: 2026-04-29
"""
from alembic import op


revision = '020'
down_revision = '019'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent: matches the style of 018 / 019. Adds the columns the new
    # in-progress test attempt flow needs and backfills sensible values for
    # any TestSubmission rows that already exist (those rows came from the
    # old "submit-only" flow, so they are all finalized).
    op.execute(
        """
        ALTER TABLE test_submissions
            ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS attempt_expires_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS is_finalized BOOLEAN NOT NULL DEFAULT TRUE
        """
    )
    # Backfill: existing rows came from the old flow where submit == finalize.
    op.execute(
        """
        UPDATE test_submissions
           SET started_at = COALESCE(started_at, submitted_at),
               attempt_expires_at = COALESCE(attempt_expires_at, submitted_at),
               is_finalized = TRUE
         WHERE started_at IS NULL OR attempt_expires_at IS NULL
        """
    )
    # New rows default to FALSE (unfinalized) — the row is created at /start.
    op.execute(
        "ALTER TABLE test_submissions ALTER COLUMN is_finalized SET DEFAULT FALSE"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_test_submissions_is_finalized "
        "ON test_submissions (is_finalized)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_test_submissions_is_finalized")
    op.execute(
        """
        ALTER TABLE test_submissions
            DROP COLUMN IF EXISTS started_at,
            DROP COLUMN IF EXISTS attempt_expires_at,
            DROP COLUMN IF EXISTS is_finalized
        """
    )
