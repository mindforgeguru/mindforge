"""Add slot and label to payment_info for multiple payment options

Revision ID: 007_payment_info_slots
Revises: 006_add_answer_key_url_to_tests
Create Date: 2026-04-02
"""

import sqlalchemy as sa
from alembic import op

revision = "007_payment_info_slots"
down_revision = "006_add_answer_key_url_to_tests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("payment_info", sa.Column("slot", sa.Integer(), nullable=True))
    op.add_column("payment_info", sa.Column("label", sa.String(100), nullable=True))
    # Set existing rows to slot 1
    op.execute("UPDATE payment_info SET slot = 1, label = 'Option 1' WHERE slot IS NULL")
    # Make slot non-nullable after backfill
    op.alter_column("payment_info", "slot", nullable=False, server_default="1")
    op.create_unique_constraint("uq_payment_info_slot", "payment_info", ["slot"])


def downgrade() -> None:
    op.drop_constraint("uq_payment_info_slot", "payment_info", type_="unique")
    op.drop_column("payment_info", "label")
    op.drop_column("payment_info", "slot")
