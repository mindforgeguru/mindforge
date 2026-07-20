"""Let audit_logs.admin_id be NULL, matching its ON DELETE SET NULL.

The column was declared NOT NULL while its foreign key says ON DELETE SET
NULL. Those cannot both hold: deleting a user the database is supposed to
null out raises NotNullViolation instead, so the delete fails.

Nothing hits this today — the only hard deletes are of pending, non-admin
accounts (delete_pending_user explicitly refuses admins), and only admins ever
appear as admin_id. Revocation is a soft delete. But it is a trap for anything
that later deletes an admin for real: a GDPR erasure, an account cleanup, or a
test fixture tearing down its own data.

Resolved in favour of the foreign key rather than the column, because an audit
trail should outlive the account that wrote it. The alternatives are worse:
RESTRICT makes admins undeletable, and CASCADE destroys the audit history
exactly when someone is being removed — which is when it matters most. A row
with a NULL actor still records what happened, when, and to what.

Revision ID: 034
Revises: 033
"""

from alembic import op

revision = '034'
down_revision = '033'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE audit_logs ALTER COLUMN admin_id DROP NOT NULL")


def downgrade() -> None:
    # Only reinstatable while no row has been nulled out by a user deletion.
    # Check first:
    #   SELECT count(*) FROM audit_logs WHERE admin_id IS NULL;
    # Orphaned rows would have to be reassigned or dropped before this runs.
    op.execute("ALTER TABLE audit_logs ALTER COLUMN admin_id SET NOT NULL")
