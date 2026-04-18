"""Add teacher knowledge-base tables (old_test_papers, chapter_documents, syllabus_entries)

Revision ID: 015
Revises: 014
Create Date: 2026-04-15
"""
from alembic import op
import sqlalchemy as sa

revision = '015'
down_revision = '014'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'old_test_papers',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('teacher_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('file_key', sa.String(500), nullable=False),
        sa.Column('original_filename', sa.String(255), nullable=False),
        sa.Column('grade', sa.Integer(), nullable=True, index=True),
        sa.Column('subject', sa.String(100), nullable=True, index=True),
        sa.Column('chapter', sa.String(200), nullable=True),
        sa.Column('title', sa.String(300), nullable=True),
        sa.Column('ai_summary', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        'chapter_documents',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('teacher_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('file_key', sa.String(500), nullable=False),
        sa.Column('original_filename', sa.String(255), nullable=False),
        sa.Column('grade', sa.Integer(), nullable=False, index=True),
        sa.Column('subject', sa.String(100), nullable=False, index=True),
        sa.Column('chapter_name', sa.String(200), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        'syllabus_entries',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('teacher_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('grade', sa.Integer(), nullable=False, index=True),
        sa.Column('subject', sa.String(100), nullable=False, index=True),
        sa.Column('chapters', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('syllabus_entries')
    op.drop_table('chapter_documents')
    op.drop_table('old_test_papers')
