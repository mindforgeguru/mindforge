"""tag auto-generated tests from presentation period logs

Revision ID: 026
Revises: 025
Create Date: 2026-05-30

Adds columns to `tests` so a test auto-created when a teacher logs a taught
period (POST /api/presentations/{id}/period-log) can be identified and
sequenced:

  - auto_generated   : TRUE for period-log auto-quizzes
  - presentation_id  : the ChapterPresentation the quiz was generated from
  - slides_from/_to  : the slide range that was taught (drives the title and
                       the per-period dedupe so the same period isn't quizzed
                       twice)

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '026'
down_revision = '025'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE tests ADD COLUMN IF NOT EXISTS auto_generated BOOLEAN "
        "NOT NULL DEFAULT FALSE"
    )
    op.execute(
        """
        ALTER TABLE tests
        ADD COLUMN IF NOT EXISTS presentation_id INTEGER
            REFERENCES chapter_presentations(id) ON DELETE SET NULL
        """
    )
    op.execute("ALTER TABLE tests ADD COLUMN IF NOT EXISTS slides_from INTEGER")
    op.execute("ALTER TABLE tests ADD COLUMN IF NOT EXISTS slides_to INTEGER")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_tests_presentation_id "
        "ON tests (presentation_id)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_tests_presentation_id")
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS slides_to")
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS slides_from")
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS presentation_id")
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS auto_generated")
