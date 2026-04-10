"""Idempotent repair: add any columns that may have been missed when
the DB was bootstrapped via create_all instead of full Alembic history.

Revision ID: 012
Revises: 011
Create Date: 2026-04-10
"""
from alembic import op
import sqlalchemy as sa

revision = '012'
down_revision = '011'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # payment_info.branch (migration 010 may not have run)
    op.execute("""
        ALTER TABLE payment_info
        ADD COLUMN IF NOT EXISTS branch VARCHAR(200)
    """)

    # timetable_slots.subject nullable (migration 009 may not have run)
    op.execute("""
        ALTER TABLE timetable_slots
        ALTER COLUMN subject DROP NOT NULL
    """)

    # Composite indexes (migration 011 may not have run) — IF NOT EXISTS
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_fee_structures_grade_year
        ON fee_structures (grade, academic_year)
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_test_submissions_student_test
        ON test_submissions (student_id, test_id)
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_fee_payments_student
        ON fee_payments (student_id)
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_fee_payments_student")
    op.execute("DROP INDEX IF EXISTS ix_test_submissions_student_test")
    op.execute("DROP INDEX IF EXISTS ix_fee_structures_grade_year")
    op.execute("ALTER TABLE payment_info DROP COLUMN IF EXISTS branch")
