"""Add branch column to payment_info table

Revision ID: 010
Revises: 009
Create Date: 2026-04-04
"""
from alembic import op
import sqlalchemy as sa

revision = '010'
down_revision = '009'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'payment_info',
        sa.Column('branch', sa.String(200), nullable=True)
    )


def downgrade():
    op.drop_column('payment_info', 'branch')
