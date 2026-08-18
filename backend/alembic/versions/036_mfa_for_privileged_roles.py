"""Add TOTP columns for admin and owner accounts.

A 6-digit MPIN is currently the only factor for every role, including the
platform owner and each school's admin. Rate limiting and lockout bound the
online guessing rate, so the realistic exposure is not brute force — it is a
shared, shoulder-surfed or reused PIN. For a student that costs one student's
records; for an admin it costs a whole school's, and for the owner every school
on the platform.

Scoped to admin and owner deliberately. TOTP for parents and students, many of
them on shared family devices with no authenticator app, would generate far more
lockouts than compromises it prevents. Nothing here forces enrolment — the
columns default to off and MFA is opt-in per account.

Three columns, all nullable so the migration is a no-op for existing rows:

  mfa_secret          base32 TOTP secret. Stored as-is, because verification
                      needs the original value — unlike an MPIN it cannot be
                      hashed. It is exactly as sensitive as the MPIN hash beside
                      it and lives under the same access controls.
  mfa_enabled         only true after a code has been verified, so an
                      interrupted enrolment cannot lock anyone out.
  mfa_recovery_codes  JSON array of sha256 hashes. sha256 rather than bcrypt is
                      correct here: these are 160-bit random values, so there is
                      no low-entropy guess space for a slow hash to defend, and
                      bcrypt over ten codes on every fallback attempt would be
                      a needless cost.

Revision ID: 036
Revises: 035
"""

from alembic import op
import sqlalchemy as sa

revision = '036'
down_revision = '035'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('mfa_secret', sa.String(64), nullable=True))
    op.add_column(
        'users',
        sa.Column('mfa_enabled', sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column('users', sa.Column('mfa_recovery_codes', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'mfa_recovery_codes')
    op.drop_column('users', 'mfa_enabled')
    op.drop_column('users', 'mfa_secret')
