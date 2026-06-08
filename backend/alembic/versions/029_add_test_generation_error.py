"""store the auto-quiz failure reason for in-app display

Revision ID: 029
Revises: 028
Create Date: 2026-06-08

When an auto-quiz can't be generated we now store the human-readable reason on
the Test row so the teacher's Tests tab can show it directly on the failed card
(a push notification isn't reliable — web/Safari rarely delivers FCM).

  - generation_error : short reason text, NULL for non-failed tests

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '029'
down_revision = '028'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE tests ADD COLUMN IF NOT EXISTS generation_error "
        "VARCHAR(300)"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS generation_error")
