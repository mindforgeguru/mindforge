"""Add school_id to audit_logs (tenant-scope the admin audit trail)

Revision ID: 032
Revises: 031
Create Date: 2026-07-18

audit_logs was missed in 031's tenant sweep. Same treatment: nullable school_id
FK + index, backfilled to the existing school. Each entry is scoped to the
acting admin's school so one school's admins can't read another's audit trail.

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '032'
down_revision = '031'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS school_id INTEGER")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_audit_logs_school_id ON audit_logs (school_id)"
    )
    op.execute(
        "UPDATE audit_logs SET school_id = (SELECT id FROM schools WHERE slug = 'hansel-gretel') "
        "WHERE school_id IS NULL"
    )
    op.execute(
        """
        DO $$ BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'fk_audit_logs_school_id'
          ) THEN
            ALTER TABLE audit_logs
              ADD CONSTRAINT fk_audit_logs_school_id
              FOREIGN KEY (school_id) REFERENCES schools (id) ON DELETE RESTRICT;
          END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute("ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS fk_audit_logs_school_id")
    op.execute("DROP INDEX IF EXISTS ix_audit_logs_school_id")
    op.execute("ALTER TABLE audit_logs DROP COLUMN IF EXISTS school_id")
