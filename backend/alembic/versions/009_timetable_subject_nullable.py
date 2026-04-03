"""make timetable_slots.subject nullable

Revision ID: 009
Revises: 008
Create Date: 2026-04-03
"""
from alembic import op
import sqlalchemy as sa

revision = '009'
down_revision = '008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('timetable_slots', 'subject',
                    existing_type=sa.String(length=100),
                    nullable=True)


def downgrade() -> None:
    # Fill nulls before making NOT NULL again
    op.execute("UPDATE timetable_slots SET subject = '' WHERE subject IS NULL")
    op.alter_column('timetable_slots', 'subject',
                    existing_type=sa.String(length=100),
                    nullable=False)
