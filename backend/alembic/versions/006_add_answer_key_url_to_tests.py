"""Add answer_key_url to tests table

Revision ID: 006_add_answer_key_url_to_tests
Revises: 005_add_homework_and_broadcast
Create Date: 2026-04-02
"""

import sqlalchemy as sa
from alembic import op

revision = "006_add_answer_key_url_to_tests"
down_revision = "005_add_homework_and_broadcast"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "tests",
        sa.Column("answer_key_url", sa.String(500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("tests", "answer_key_url")
