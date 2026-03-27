"""Add is_graded column to tests table

Revision ID: 003_add_is_graded_to_tests
Revises: 002_date_based_timetable
Create Date: 2026-03-20
"""

from alembic import op
import sqlalchemy as sa

revision = "003_add_is_graded_to_tests"
down_revision = "002_date_based_timetable"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [c["name"] for c in inspector.get_columns("tests")]
    if "is_graded" not in columns:
        op.add_column(
            "tests",
            sa.Column(
                "is_graded",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )


def downgrade() -> None:
    op.drop_column("tests", "is_graded")
