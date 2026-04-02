"""Add comment column to timetable_slots

Revision ID: 008_add_timetable_comment
Revises: 007_payment_info_slots
Create Date: 2026-04-02
"""

import sqlalchemy as sa
from alembic import op

revision = "008_add_timetable_comment"
down_revision = "007_payment_info_slots"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "timetable_slots",
        sa.Column("comment", sa.String(300), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("timetable_slots", "comment")
