"""link chapter_presentations to chapter_documents

Revision ID: 025
Revises: 024
Create Date: 2026-05-28

Adds a nullable source_chapter_document_id column so a teacher can pick
an existing chapter from the database instead of re-uploading a PDF. The
column is also the dedupe key — POST /api/presentations/from-chapter
returns the existing presentation if one already exists for the chapter.

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '025'
down_revision = '024'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE chapter_presentations
        ADD COLUMN IF NOT EXISTS source_chapter_document_id INTEGER
            REFERENCES chapter_documents(id) ON DELETE SET NULL
        """
    )
    # Look-ups in POST /from-chapter hit this column.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_chapter_presentations_source_chapter "
        "ON chapter_presentations (source_chapter_document_id)"
    )


def downgrade() -> None:
    op.execute(
        "DROP INDEX IF EXISTS ix_chapter_presentations_source_chapter"
    )
    op.execute(
        "ALTER TABLE chapter_presentations "
        "DROP COLUMN IF EXISTS source_chapter_document_id"
    )
