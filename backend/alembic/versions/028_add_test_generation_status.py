"""track auto-quiz generation status on tests

Revision ID: 028
Revises: 027
Create Date: 2026-06-08

When a teacher logs a taught period (POST /api/presentations/{id}/period-log)
we now create the auto-quiz Test row *immediately* in a `generating` state so
the teacher's Tests tab can show progress, then the background job flips it to
`ready` (published) or `failed`. Manual tests stay `ready`.

  - generation_status : 'ready' | 'generating' | 'failed'  (default 'ready')

Idempotent — re-runs are safe.
"""
from alembic import op


revision = '028'
down_revision = '027'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE tests ADD COLUMN IF NOT EXISTS generation_status "
        "VARCHAR(20) NOT NULL DEFAULT 'ready'"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE tests DROP COLUMN IF EXISTS generation_status")
