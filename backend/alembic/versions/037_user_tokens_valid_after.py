"""Add users.tokens_valid_after so an MPIN change can end existing sessions.

Revocation used to be per token only (the JTI blacklist, filled on logout and
refresh rotation). Nothing could end *every* session a user has, so an admin
resetting a leaked MPIN left the intruder's refresh token rotating on for its
full lifetime.

Any access or refresh token whose `iat` is earlier than this timestamp is
rejected. NULL — the value for every existing row — revokes nothing.

Revision ID: 037
Revises: 036
"""

from alembic import op
import sqlalchemy as sa

revision = '037'
down_revision = '036'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('tokens_valid_after', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('users', 'tokens_valid_after')
