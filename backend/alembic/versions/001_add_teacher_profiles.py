"""add teacher_profiles table

Revision ID: 001_add_teacher_profiles
Revises:
Create Date: 2026-03-13
"""

from alembic import op
import sqlalchemy as sa


revision = "001_add_teacher_profiles"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    conn = op.get_bind()
    inspector = inspect(conn)
    if "teacher_profiles" not in inspector.get_table_names():
        op.create_table(
            "teacher_profiles",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("teachable_subjects", sa.JSON(), nullable=True),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("user_id"),
        )
        op.create_index("ix_teacher_profiles_id", "teacher_profiles", ["id"])


def downgrade() -> None:
    op.drop_index("ix_teacher_profiles_id", table_name="teacher_profiles")
    op.drop_table("teacher_profiles")
