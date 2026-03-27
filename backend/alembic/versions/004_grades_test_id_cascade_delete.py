"""Change grades.test_id FK from SET NULL to CASCADE DELETE

Revision ID: 004_grades_test_id_cascade_delete
Revises: 003_add_is_graded_to_tests
Create Date: 2026-03-21
"""

from alembic import op

revision = "004_grades_test_id_cascade_delete"
down_revision = "003_add_is_graded_to_tests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint("grades_test_id_fkey", "grades", type_="foreignkey")
    op.create_foreign_key(
        "grades_test_id_fkey",
        "grades", "tests",
        ["test_id"], ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint("grades_test_id_fkey", "grades", type_="foreignkey")
    op.create_foreign_key(
        "grades_test_id_fkey",
        "grades", "tests",
        ["test_id"], ["id"],
        ondelete="SET NULL",
    )
