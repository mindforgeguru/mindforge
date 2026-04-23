"""add fcm_token to users

Revision ID: 018
Revises: 017
Create Date: 2026-04-22
"""
from alembic import op
import sqlalchemy as sa

revision = '018'
down_revision = '017'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Use raw SQL with IF NOT EXISTS so re-runs don't fail
    # (column may already exist if create_all ran before this migration)
    op.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(512)"
    )


def downgrade() -> None:
    op.drop_column('users', 'fcm_token')
