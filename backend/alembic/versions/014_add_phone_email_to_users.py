"""Add phone and email columns to users table

Revision ID: 014
Revises: 013
Create Date: 2026-04-10
"""
from alembic import op
import sqlalchemy as sa

revision = '014'
down_revision = '013'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('phone', sa.String(20), nullable=True))
    op.add_column('users', sa.Column('email', sa.String(255), nullable=True))
    # Partial unique index: only one account per phone number (NULLs are excluded)
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_phone_unique
        ON users (phone) WHERE phone IS NOT NULL
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_users_phone_unique")
    op.drop_column('users', 'email')
    op.drop_column('users', 'phone')
