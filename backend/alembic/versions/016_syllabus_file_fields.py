"""Add file_key and original_filename to syllabus_entries

Revision ID: 016
Revises: 015
Create Date: 2026-04-15
"""
from alembic import op
import sqlalchemy as sa

revision = '016'
down_revision = '015'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('syllabus_entries',
        sa.Column('file_key', sa.String(500), nullable=True))
    op.add_column('syllabus_entries',
        sa.Column('original_filename', sa.String(255), nullable=True))


def downgrade():
    op.drop_column('syllabus_entries', 'original_filename')
    op.drop_column('syllabus_entries', 'file_key')
