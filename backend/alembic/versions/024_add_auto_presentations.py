"""add auto-presentation tables (chapter_presentations, presentation_slides,
presentation_teacher_progress, presentation_period_logs)

Revision ID: 024
Revises: 023
Create Date: 2026-05-28

Idempotent — re-runs (or running after Base.metadata.create_all in dev) do
not fail. Mirrors the style used by 021/022/023.
"""
from alembic import op


revision = '024'
down_revision = '023'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── presentation_status enum ─────────────────────────────────────────────
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'presentation_status') THEN
                CREATE TYPE presentation_status AS ENUM (
                    'PROCESSING',
                    'READY',
                    'FAILED'
                );
            END IF;
        END $$;
        """
    )

    # ── chapter_presentations ────────────────────────────────────────────────
    # One row per chapter PDF a teacher uploads. Owns the shared slide deck.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS chapter_presentations (
            id SERIAL PRIMARY KEY,
            created_by_teacher_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            grade INTEGER NOT NULL,
            subject VARCHAR(100) NOT NULL,
            chapter_name VARCHAR(300) NOT NULL,
            source_pdf_key VARCHAR(500),
            total_slides INTEGER NOT NULL DEFAULT 0,
            recommended_periods INTEGER NOT NULL DEFAULT 0,
            default_slides_per_period INTEGER NOT NULL DEFAULT 0,
            status presentation_status NOT NULL DEFAULT 'PROCESSING',
            failure_reason VARCHAR(500),
            last_edited_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            last_edited_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_chapter_presentations_grade_subject "
        "ON chapter_presentations (grade, subject)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_chapter_presentations_created_by "
        "ON chapter_presentations (created_by_teacher_id)"
    )

    # ── presentation_slides ──────────────────────────────────────────────────
    # The shared deck. Any teacher can PATCH a slide's title / body / notes.
    # slide_index is 0-based and stable for the lifetime of the deck.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS presentation_slides (
            id SERIAL PRIMARY KEY,
            presentation_id INTEGER NOT NULL
                REFERENCES chapter_presentations(id) ON DELETE CASCADE,
            slide_index INTEGER NOT NULL,
            title VARCHAR(300) NOT NULL,
            body_md TEXT NOT NULL DEFAULT '',
            speaker_notes TEXT NOT NULL DEFAULT '',
            last_edited_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            last_edited_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_slide_per_presentation
                UNIQUE (presentation_id, slide_index)
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_presentation_slides_presentation_id "
        "ON presentation_slides (presentation_id)"
    )

    # ── presentation_teacher_progress ────────────────────────────────────────
    # Per-teacher pace against a shared deck. Created automatically for the
    # uploader on POST /upload, and for any other teacher who calls POST
    # /{id}/adopt to teach the same chapter to their own class.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS presentation_teacher_progress (
            id SERIAL PRIMARY KEY,
            presentation_id INTEGER NOT NULL
                REFERENCES chapter_presentations(id) ON DELETE CASCADE,
            teacher_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            current_slide_index INTEGER NOT NULL DEFAULT 0,
            periods_used INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_progress_per_teacher_presentation
                UNIQUE (presentation_id, teacher_id)
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_progress_teacher_id "
        "ON presentation_teacher_progress (teacher_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_progress_presentation_id "
        "ON presentation_teacher_progress (presentation_id)"
    )

    # ── presentation_period_logs ─────────────────────────────────────────────
    # Append-only log of "I taught slides X..Y in period N on this date".
    # Scoped by teacher so different teachers can teach at different paces.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS presentation_period_logs (
            id SERIAL PRIMARY KEY,
            presentation_id INTEGER NOT NULL
                REFERENCES chapter_presentations(id) ON DELETE CASCADE,
            teacher_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            period_date DATE NOT NULL,
            period_number INTEGER,
            slides_covered_from INTEGER NOT NULL,
            slides_covered_to INTEGER NOT NULL,
            notes VARCHAR(1000),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_period_logs_presentation_id "
        "ON presentation_period_logs (presentation_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_period_logs_teacher_id "
        "ON presentation_period_logs (teacher_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_period_logs_date "
        "ON presentation_period_logs (period_date)"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS presentation_period_logs")
    op.execute("DROP TABLE IF EXISTS presentation_teacher_progress")
    op.execute("DROP TABLE IF EXISTS presentation_slides")
    op.execute("DROP TABLE IF EXISTS chapter_presentations")
    op.execute("DROP TYPE IF EXISTS presentation_status")
