"""Add composite indexes for performance

Revision ID: 011
Revises: 010
Create Date: 2026-04-04
"""
from alembic import op

revision = '011'
down_revision = '010'
branch_labels = None
depends_on = None


def upgrade():
    # fee_structures: fast lookup by (grade, academic_year) — hit on every fee page load
    op.create_index(
        'idx_fee_structures_grade_year',
        'fee_structures',
        ['grade', 'academic_year'],
    )

    # test_submissions: fast duplicate-check by (student_id, test_id) — checked on every submission
    op.create_index(
        'idx_test_submissions_student_test',
        'test_submissions',
        ['student_id', 'test_id'],
    )

    # fee_payments: fast lookup of all payments for a student
    op.create_index(
        'idx_fee_payments_student_id',
        'fee_payments',
        ['student_id'],
    )


def downgrade():
    op.drop_index('idx_fee_payments_student_id', table_name='fee_payments')
    op.drop_index('idx_test_submissions_student_test', table_name='test_submissions')
    op.drop_index('idx_fee_structures_grade_year', table_name='fee_structures')
