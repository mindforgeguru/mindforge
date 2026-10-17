"""One timetable slot per school, grade, date and period.

The teacher's save looked for the slot and inserted one when it found none, so
two saves at the same moment — a double tap, two teachers editing the same
period — both inserted. From then on every save of that period was a 500: the
lookup expects one row and found several. Five simultaneous saves on
2026-10-16 left three rows.

The save is now an INSERT ... ON CONFLICT on this index. Duplicates already in
the table are removed first, keeping the newest row of each — the one the last
save wrote. No other table references timetable_slots.

Revision ID: 039
Revises: 038
"""

from alembic import op

revision = '039'
down_revision = '038'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DELETE FROM timetable_slots t
         USING timetable_slots newer
         WHERE newer.school_id = t.school_id
           AND newer.grade = t.grade
           AND newer.slot_date = t.slot_date
           AND newer.period_number = t.period_number
           AND newer.id > t.id
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_timetable_slot_period
        ON timetable_slots (school_id, grade, slot_date, period_number)
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_timetable_slot_period")
