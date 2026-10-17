"""At most one current academic year per school.

Closing the year read the current year and then wrote a new one. Three closes
at the same moment — a second tap while the first was still removing users,
or two admins — on 2026-10-16 left three years marked current. Everything that
looks up "the current year" expects one, so from then on registration in that
school, which is what everybody must do after a close, was a 500.

The handlers now lock the school row first. This index makes a second current
year impossible regardless. Schools already holding several keep the newest as
current; the others are ended when the newest began.

Revision ID: 040
Revises: 039
"""

from alembic import op

revision = '040'
down_revision = '039'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE academic_years y
           SET is_current = false,
               ended_at = COALESCE(y.ended_at, newer.started_at)
          FROM academic_years newer
         WHERE newer.school_id = y.school_id
           AND newer.is_current
           AND y.is_current
           AND newer.id > y.id
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_year_current
        ON academic_years (school_id) WHERE is_current
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_academic_year_current")
