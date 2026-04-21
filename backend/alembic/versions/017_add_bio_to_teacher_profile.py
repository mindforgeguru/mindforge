"""add bio to teacher_profile

Revision ID: 017
Revises: 016
Create Date: 2026-04-20
"""
from alembic import op
import sqlalchemy as sa

revision = '017'
down_revision = '016'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'teacher_profiles',
        sa.Column('bio', sa.String(500), nullable=True),
    )


def downgrade():
    op.drop_column('teacher_profiles', 'bio')
