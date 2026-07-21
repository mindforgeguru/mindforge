"""Scope the fee unique constraints to a school.

031 added school_id to fee_structures and payment_info but left their unique
constraints keyed on business values alone. Both then behave as
platform-global:

  * uq_fee_structure UNIQUE (academic_year, grade) — every school has a
    grade 8 in 2026-27, so whichever school configures it first takes that
    (year, grade) pair for the entire platform. Every other school gets a
    UniqueViolation, surfacing as a 500.
  * uq_payment_info_slot UNIQUE (slot) — slot is a small per-school index
    (1, 2, 3) for bank account details. Globally unique means exactly one
    school on the platform can hold slot 1, so no second school can configure
    payment details at all.

Same omission as the phone index fixed in 033: the tenant column was added
without revisiting the constraints that now needed it. Constraints keyed on a
globally unique foreign key — user_id, test_id, presentation_id, student_id —
are already implicitly school-scoped, because those rows each belong to exactly
one school; only the ones keyed on natural values needed changing.

Adding a column to a unique key only ever relaxes it, so existing rows cannot
conflict with the new constraints.

Revision ID: 035
Revises: 034
"""

from alembic import op

revision = '035'
down_revision = '034'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # fee_structures
    op.execute("ALTER TABLE fee_structures DROP CONSTRAINT IF EXISTS uq_fee_structure")
    op.execute("DROP INDEX IF EXISTS uq_fee_structure")
    op.execute(
        """
        ALTER TABLE fee_structures
          ADD CONSTRAINT uq_fee_structure_school
          UNIQUE (school_id, academic_year, grade)
        """
    )

    # payment_info
    op.execute(
        "ALTER TABLE payment_info DROP CONSTRAINT IF EXISTS uq_payment_info_slot"
    )
    op.execute("DROP INDEX IF EXISTS uq_payment_info_slot")
    op.execute(
        """
        ALTER TABLE payment_info
          ADD CONSTRAINT uq_payment_info_slot_school
          UNIQUE (school_id, slot)
        """
    )


def downgrade() -> None:
    # NOTE: both of these fail once more than one school has configured fees,
    # which is the situation this migration exists to allow. Check first:
    #   SELECT academic_year, grade FROM fee_structures
    #    GROUP BY 1,2 HAVING count(*) > 1;
    #   SELECT slot FROM payment_info GROUP BY 1 HAVING count(*) > 1;
    op.execute(
        "ALTER TABLE payment_info DROP CONSTRAINT IF EXISTS uq_payment_info_slot_school"
    )
    op.execute(
        "ALTER TABLE payment_info ADD CONSTRAINT uq_payment_info_slot UNIQUE (slot)"
    )
    op.execute(
        "ALTER TABLE fee_structures DROP CONSTRAINT IF EXISTS uq_fee_structure_school"
    )
    op.execute(
        """
        ALTER TABLE fee_structures
          ADD CONSTRAINT uq_fee_structure UNIQUE (academic_year, grade)
        """
    )
