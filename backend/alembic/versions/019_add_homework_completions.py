"""add homework_completions table

Revision ID: 019
Revises: 018
Create Date: 2026-04-28
"""
from alembic import op


revision = '019'
down_revision = '018'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent — re-runs (or running after Base.metadata.create_all in dev)
    # do not fail. Mirrors the style used by 018.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS homework_completions (
            id SERIAL PRIMARY KEY,
            homework_id INTEGER NOT NULL
                REFERENCES homework(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            completed BOOLEAN NOT NULL DEFAULT FALSE,
            marked_by INTEGER
                REFERENCES users(id) ON DELETE SET NULL,
            marked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_homework_student UNIQUE (homework_id, student_id)
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_homework_completions_homework_id "
        "ON homework_completions (homework_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_homework_completions_student_id "
        "ON homework_completions (student_id)"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS homework_completions")
