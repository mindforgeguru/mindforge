"""Repair payment_info columns that may be missing if migrations 007/010 never ran.

Revision ID: 013
Revises: 012
Create Date: 2026-04-10
"""
from alembic import op

revision = '013'
down_revision = '012'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # slot (migration 007 may not have run)
    op.execute("ALTER TABLE payment_info ADD COLUMN IF NOT EXISTS slot INTEGER DEFAULT 1")
    op.execute("UPDATE payment_info SET slot = 1 WHERE slot IS NULL")
    op.execute("ALTER TABLE payment_info ALTER COLUMN slot SET NOT NULL")
    op.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE constraint_name = 'uq_payment_info_slot'
                  AND table_name = 'payment_info'
            ) THEN
                ALTER TABLE payment_info ADD CONSTRAINT uq_payment_info_slot UNIQUE (slot);
            END IF;
        END $$
    """)

    # label (migration 007 may not have run)
    op.execute("ALTER TABLE payment_info ADD COLUMN IF NOT EXISTS label VARCHAR(100)")

    # branch (migration 010 / 012 may not have run)
    op.execute("ALTER TABLE payment_info ADD COLUMN IF NOT EXISTS branch VARCHAR(200)")


def downgrade() -> None:
    op.execute("ALTER TABLE payment_info DROP COLUMN IF EXISTS branch")
    op.execute("ALTER TABLE payment_info DROP COLUMN IF EXISTS label")
    op.execute("ALTER TABLE payment_info DROP CONSTRAINT IF EXISTS uq_payment_info_slot")
    op.execute("ALTER TABLE payment_info DROP COLUMN IF EXISTS slot")
