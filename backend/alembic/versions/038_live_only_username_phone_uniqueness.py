"""Stop removed accounts holding on to their username and phone number.

Accounts are soft-deleted (`deleted_at` set), and three things do it: closing
the academic year, which removes every student, teacher and parent in the
school and asks them to register again; an admin revoking an account; and a
teacher or parent deleting their own.

Every conflict check in the application — registration, admin edits, the
owner's add-admin, login itself — asks "is this taken by a *live* account?"
and filters on `deleted_at IS NULL`. The two unique indexes did not. So after a
year close the application found no conflict, issued the INSERT, and Postgres
refused it with a UniqueViolation that nothing caught: a 500 for every
returning user who registered under their old username or their old phone
number. Same shape as the disagreement 033 fixed for phone numbers across
schools.

Both indexes now cover live rows only, which is the rule the application has
always applied. Narrowing a unique index to fewer rows cannot conflict with
existing data: any set of rows that satisfied the old index satisfies the new
one.

Revision ID: 038
Revises: 037
"""

from alembic import op

revision = '038'
down_revision = '037'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_school_username_live
        ON users (school_id, username) WHERE deleted_at IS NULL
        """
    )
    op.execute(
        "ALTER TABLE users DROP CONSTRAINT IF EXISTS uq_users_school_username"
    )

    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_school_phone_live
        ON users (school_id, phone)
        WHERE phone IS NOT NULL AND deleted_at IS NULL
        """
    )
    op.execute("DROP INDEX IF EXISTS ix_users_school_phone_unique")


def downgrade() -> None:
    # NOTE: restoring the old indexes fails once a removed account and a live
    # one share a username or phone — which this migration exists to permit.
    # Check before rolling back:
    #   SELECT school_id, username FROM users
    #    GROUP BY school_id, username HAVING count(*) > 1;
    #   SELECT school_id, phone FROM users WHERE phone IS NOT NULL
    #    GROUP BY school_id, phone HAVING count(*) > 1;
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS ix_users_school_phone_unique
        ON users (school_id, phone) WHERE phone IS NOT NULL
        """
    )
    op.execute("DROP INDEX IF EXISTS ix_users_school_phone_live")

    op.execute(
        """
        ALTER TABLE users
          ADD CONSTRAINT uq_users_school_username UNIQUE (school_id, username)
        """
    )
    op.execute("DROP INDEX IF EXISTS ix_users_school_username_live")
