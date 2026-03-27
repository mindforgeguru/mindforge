"""Replace day_of_week with slot_date in timetable_slots

Revision ID: 002_date_based_timetable
Revises: 001_add_teacher_profiles
Create Date: 2026-03-18
"""

from alembic import op
import sqlalchemy as sa

revision = "002_date_based_timetable"
down_revision = "001_add_teacher_profiles"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect, text
    conn = op.get_bind()
    inspector = inspect(conn)
    columns = [c["name"] for c in inspector.get_columns("timetable_slots")]
    if "day_of_week" in columns:
        # Clear incompatible day_of_week data
        op.execute(text("DELETE FROM timetable_slots"))
        # Add slot_date if not already present
        if "slot_date" not in columns:
            op.add_column("timetable_slots", sa.Column("slot_date", sa.Date(), nullable=True))
            op.execute(text("ALTER TABLE timetable_slots ALTER COLUMN slot_date SET NOT NULL"))
        op.drop_column("timetable_slots", "day_of_week")
    elif "slot_date" not in columns:
        # Neither column exists — just add slot_date
        op.add_column("timetable_slots", sa.Column("slot_date", sa.Date(), nullable=True))
        op.execute(text("ALTER TABLE timetable_slots ALTER COLUMN slot_date SET NOT NULL"))


def downgrade() -> None:
    op.execute("DELETE FROM timetable_slots")
    op.add_column("timetable_slots", sa.Column("day_of_week", sa.Integer(), nullable=True))
    op.execute("ALTER TABLE timetable_slots ALTER COLUMN day_of_week SET NOT NULL")
    op.drop_column("timetable_slots", "slot_date")
