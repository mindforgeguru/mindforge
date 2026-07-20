"""Add multi-tenancy: schools table, users.school_id, owner role, per-school usernames

Revision ID: 030
Revises: 029
Create Date: 2026-07-18

First tenancy layer. Introduces:
  - schools            : one row per customer school (the tenant root)
  - user_role += owner : platform super-admin, not tied to any school
  - users.school_id    : links every user to their school (NULL only for owner)
  - username uniqueness : now per-school (school_id, username) instead of global

Backfill: creates the existing 'Hansel & Gretel' school and stamps every current
user with it, so behaviour is unchanged (one school, everyone in it). The owner
account itself is seeded at app startup from OWNER_SEED_MPIN — never here, so no
credential ships in a migration.

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '030'
down_revision = '029'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add 'owner' to the user_role enum. Postgres forbids ALTER TYPE ... ADD
    #    VALUE inside the surrounding migration transaction, so run it in an
    #    autocommit block. The value isn't *used* here (the owner account is
    #    seeded later at startup), so there's no "unsafe use of new value" risk.
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'owner'")

    # 2. schools table (tenant root).
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS schools (
            id                  SERIAL PRIMARY KEY,
            name                VARCHAR(200) NOT NULL,
            slug                VARCHAR(80)  NOT NULL,
            logo_url            VARCHAR(500),
            address             VARCHAR(500),
            contact_email       VARCHAR(255),
            contact_phone       VARCHAR(20),
            is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
            subscription_status VARCHAR(30) NOT NULL DEFAULT 'active',
            subscription_plan   VARCHAR(50),
            created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_schools_slug ON schools (slug)")

    # 3. users.school_id (nullable — the owner has none), FK + index.
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id INTEGER")
    op.execute(
        """
        DO $$ BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_school_id'
          ) THEN
            ALTER TABLE users
              ADD CONSTRAINT fk_users_school_id
              FOREIGN KEY (school_id) REFERENCES schools (id) ON DELETE RESTRICT;
          END IF;
        END $$;
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_school_id ON users (school_id)")

    # 4. Backfill: create the existing school, then stamp all current users.
    op.execute(
        """
        INSERT INTO schools (name, slug, is_active, subscription_status)
        VALUES ('Hansel & Gretel', 'hansel-gretel', TRUE, 'active')
        ON CONFLICT (slug) DO NOTHING
        """
    )
    # The platform owner is deliberately school-less (see step 3) and must stay
    # that way: login resolves the owner by matching school_id IS NULL, so
    # sweeping them into a tenant here would lock them out of the console. On a
    # first-time upgrade no owner exists yet (it is seeded at app startup, after
    # migrations), but this also runs on a re-upgrade — e.g. recovering from a
    # rollback — where one does.
    op.execute(
        """
        UPDATE users
           SET school_id = (SELECT id FROM schools WHERE slug = 'hansel-gretel')
         WHERE school_id IS NULL
           AND role::text <> 'owner'
        """
    )

    # 5. Username uniqueness: global -> per-school. Drop whichever global unique
    #    object exists (index name varies by how it was originally created),
    #    keep a plain lookup index, add the composite unique constraint. Safe
    #    because every current user now shares one school and usernames were
    #    globally unique before, so no (school_id, username) collisions exist.
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key")
    op.execute("DROP INDEX IF EXISTS ix_users_username")
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_username ON users (username)")
    op.execute(
        """
        DO $$ BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'uq_users_school_username'
          ) THEN
            ALTER TABLE users
              ADD CONSTRAINT uq_users_school_username UNIQUE (school_id, username);
          END IF;
        END $$;
        """
    )


def downgrade() -> None:
    # DESTRUCTIVE AND NOT REVERSIBLE ONCE A SECOND SCHOOL EXISTS.
    #
    # Dropping the schools table discards the school registry outright. Running
    # `upgrade` afterwards does not restore it: 031 recreates a single default
    # school and backfills every row into it, so a 5-school install comes back
    # as one school with all tenants merged — every school's users, tests and
    # homework sharing one namespace, visible to each other. Verified on a
    # populated clone: 5 schools + 44 users returned as 1 school + 44 users.
    #
    # Two further hazards:
    #   * Recreating the *global* unique username index fails when two schools
    #     share a username — and it fails partway, after the per-school
    #     constraint has already been dropped. Check for collisions first:
    #       SELECT username FROM users WHERE deleted_at IS NULL
    #        GROUP BY username HAVING count(*) > 1;
    #   * Postgres can't drop an enum value, so 'owner' is left in place.
    #
    # Take a dump before running this. For a multi-school install, restoring
    # that dump is the only real rollback path.
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS uq_users_school_username")
    op.execute("DROP INDEX IF EXISTS ix_users_username")
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_username ON users (username)")
    op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS fk_users_school_id")
    op.execute("DROP INDEX IF EXISTS ix_users_school_id")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS school_id")
    op.execute("DROP TABLE IF EXISTS schools")
