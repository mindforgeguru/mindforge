"""Scope phone uniqueness to a school, matching the application's own checks.

`ix_users_phone_unique` came from 014, well before multi-tenancy, and makes a
phone number unique across the whole platform. 030 moved usernames to
(school_id, username) but left this index alone, so the two disagreed:

  * Registration (auth.py) and admin edits (admin.py) both look for a conflict
    filtered by `User.school_id` — per school, deliberately. The comment there
    even asks "is this phone registered ... on *this school's* app?".
  * The index then rejected the insert platform-wide.

The application therefore found no conflict, issued the INSERT, and Postgres
raised UniqueViolation with nothing catching it — a 500 on a duplicate phone
across two unrelated schools, where the code intended to allow it. Two schools
also could not both register a parent who genuinely shares a number, and the
global index leaked the existence of a phone across tenant boundaries.

Widening a unique index is safe in the other direction: every row that
satisfied the global constraint necessarily satisfies the per-school one, so
no data can conflict with the new index.

Revision ID: 033
Revises: 032
"""

from alembic import op

revision = '033'
down_revision = '032'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_users_phone_unique")
    # Partial, so the many users without a phone are not forced to collide on
    # NULL. Mirrors uq_users_school_username: the owner has school_id NULL and
    # Postgres treats NULLs as distinct, so the owner is never boxed in.
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_school_phone_unique
        ON users (school_id, phone) WHERE phone IS NOT NULL
        """
    )


def downgrade() -> None:
    # NOTE: recreating the global index fails when two schools share a phone
    # number — which this migration exists to permit. Check before rolling
    # back:
    #   SELECT phone FROM users WHERE phone IS NOT NULL AND deleted_at IS NULL
    #    GROUP BY phone HAVING count(*) > 1;
    op.execute("DROP INDEX IF EXISTS ix_users_school_phone_unique")
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_phone_unique
        ON users (phone) WHERE phone IS NOT NULL
        """
    )
