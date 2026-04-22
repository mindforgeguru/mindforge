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
    op.add_column(
        'users',
        sa.Column('fcm_token', sa.String(512), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('users', 'fcm_token')
