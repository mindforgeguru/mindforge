"""add no-homework marker flag

Revision ID: 027
Revises: 026
Create Date: 2026-06-02

Adds `homework.is_no_homework` so a teacher can record a grade-wide
"no homework today" marker. The marker satisfies the daily "assign
homework" workflow step but is filtered out of student/parent/teacher
homework feeds and never needs a completion review.

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '027'
down_revision = '026'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE homework ADD COLUMN IF NOT EXISTS is_no_homework "
        "BOOLEAN NOT NULL DEFAULT FALSE"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE homework DROP COLUMN IF EXISTS is_no_homework")
