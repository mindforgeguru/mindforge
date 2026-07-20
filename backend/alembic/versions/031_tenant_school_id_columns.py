"""Add school_id to every tenant table and backfill to the existing school

Revision ID: 031
Revises: 030
Create Date: 2026-07-18

Phase 3 schema foundation. Every tenant-owned table gets a nullable school_id
(FK -> schools, ON DELETE RESTRICT) plus an index, and all existing rows are
stamped with the one pre-existing school (Hansel & Gretel). No query filters on
it yet, so behaviour is unchanged; the read/write scoping lands in later steps.

LevelConfig (xp level thresholds) is intentionally excluded — it's global
platform config shared by every school, not tenant data.

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '031'
down_revision = '030'
branch_labels = None
depends_on = None


# Every tenant-scoped table. Child tables (submissions, slides, transactions…)
# are included too for defence-in-depth so a missed parent filter can't leak.
_TENANT_TABLES = [
    "student_profiles",
    "teacher_profiles",
    "academic_years",
    "attendance",
    "timetable_configs",
    "timetable_slots",
    "grades",
    "tests",
    "test_submissions",
    "fee_structures",
    "fee_payments",
    "payment_info",
    "homework",
    "homework_completions",
    "broadcasts",
    "old_test_papers",
    "chapter_documents",
    "syllabus_entries",
    "student_xp",
    "xp_transactions",
    "feedback_reports",
    "chapter_presentations",
    "presentation_slides",
    "presentation_teacher_progress",
    "presentation_period_logs",
]

_HANSEL = "(SELECT id FROM schools WHERE slug = 'hansel-gretel')"


def upgrade() -> None:
    for t in _TENANT_TABLES:
        op.execute(f"ALTER TABLE {t} ADD COLUMN IF NOT EXISTS school_id INTEGER")
        op.execute(
            f"CREATE INDEX IF NOT EXISTS ix_{t}_school_id ON {t} (school_id)"
        )
        # Backfill: all pre-tenancy data belongs to the one existing school.
        op.execute(
            f"UPDATE {t} SET school_id = {_HANSEL} WHERE school_id IS NULL"
        )
        op.execute(
            f"""
            DO $$ BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'fk_{t}_school_id'
              ) THEN
                ALTER TABLE {t}
                  ADD CONSTRAINT fk_{t}_school_id
                  FOREIGN KEY (school_id) REFERENCES schools (id) ON DELETE RESTRICT;
              END IF;
            END $$;
            """
        )


def downgrade() -> None:
    for t in _TENANT_TABLES:
        op.execute(f"ALTER TABLE {t} DROP CONSTRAINT IF EXISTS fk_{t}_school_id")
        op.execute(f"DROP INDEX IF EXISTS ix_{t}_school_id")
        op.execute(f"ALTER TABLE {t} DROP COLUMN IF EXISTS school_id")
