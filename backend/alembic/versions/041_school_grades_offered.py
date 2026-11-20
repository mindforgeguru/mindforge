"""Grades each school teaches.

Every grade picker offered 8, 9 and 10 to every school, so a school without a
grade 10 still saw it in homework, broadcasts, timetable and registration
(#5). Existing schools keep all three until their admin narrows the list.

Revision ID: 041
Revises: 040
"""

from alembic import op

revision = '041'
down_revision = '040'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE schools ADD COLUMN IF NOT EXISTS grades_offered "
        "integer[] NOT NULL DEFAULT '{8,9,10}'"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE schools DROP COLUMN IF EXISTS grades_offered")
