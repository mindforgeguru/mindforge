"""Add homework and broadcast tables

Revision ID: 005_add_homework_and_broadcast
Revises: 004_grades_test_id_cascade_delete
Create Date: 2026-03-23
"""

import sqlalchemy as sa
from alembic import op

revision = "005_add_homework_and_broadcast"
down_revision = "004_grades_test_id_cascade_delete"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create homework_type enum
    op.execute("CREATE TYPE homework_type AS ENUM ('online_test', 'written')")

    # Create homework table
    op.create_table(
        "homework",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("teacher_id", sa.Integer(), nullable=False),
        sa.Column("grade", sa.Integer(), nullable=False),
        sa.Column("subject", sa.String(100), nullable=False),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("description", sa.String(2000), nullable=True),
        sa.Column(
            "homework_type",
            sa.Enum("online_test", "written", name="homework_type"),
            nullable=False,
            server_default="written",
        ),
        sa.Column("test_id", sa.Integer(), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["teacher_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["test_id"], ["tests.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_homework_id", "homework", ["id"])
    op.create_index("ix_homework_grade", "homework", ["grade"])
    op.create_index("ix_homework_teacher_id", "homework", ["teacher_id"])

    # Create broadcasts table
    op.create_table(
        "broadcasts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("sender_id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("message", sa.String(2000), nullable=False),
        sa.Column("target_type", sa.String(20), nullable=False, server_default="all"),
        sa.Column("target_grade", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_broadcasts_id", "broadcasts", ["id"])
    op.create_index("ix_broadcasts_sender_id", "broadcasts", ["sender_id"])


def downgrade() -> None:
    op.drop_table("broadcasts")
    op.drop_index("ix_homework_teacher_id", table_name="homework")
    op.drop_index("ix_homework_grade", table_name="homework")
    op.drop_index("ix_homework_id", table_name="homework")
    op.drop_table("homework")
    op.execute("DROP TYPE homework_type")
