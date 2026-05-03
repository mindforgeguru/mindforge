"""add theme unlocks (selected_theme on student_xp + level_configs.unlocks)

Revision ID: 022
Revises: 021
Create Date: 2026-05-02

Adds the cosmetic theme-unlock mechanic on top of the XP system:
  - student_xp.selected_theme — string id of the student's chosen theme
    (NULL = use the default 'mind_forge' theme)
  - level_configs.unlocks — JSON column already exists; this migration
    populates it with {"theme": "<theme_id>"} for the four unlock tiers
    (L5, L15, L30, L50).

Theme palettes themselves are catalogued on the frontend; the backend
only stores theme ids. Idempotent.
"""
from alembic import op


revision = '022'
down_revision = '021'
branch_labels = None
depends_on = None


# Theme unlock schedule — kept here so the migration is self-documenting.
_THEME_UNLOCKS = [
    (5,  'tide_breeze'),
    (15, 'forest_path'),
    (30, 'royal_velvet'),
    (50, 'mythic_aurora'),
]


def upgrade() -> None:
    # student_xp.selected_theme — nullable; NULL means "default theme".
    op.execute(
        """
        ALTER TABLE student_xp
        ADD COLUMN IF NOT EXISTS selected_theme VARCHAR(50)
        """
    )

    # Populate level_configs.unlocks for the unlock tiers. Use jsonb_set
    # so manually-edited JSON on other levels is preserved.
    for level, theme_id in _THEME_UNLOCKS:
        op.execute(
            f"""
            UPDATE level_configs
            SET unlocks = COALESCE(unlocks::jsonb, '{{}}'::jsonb)
                          || jsonb_build_object('theme', '{theme_id}')
            WHERE level = {level}
            """
        )


def downgrade() -> None:
    # Roll back the column; leave level_configs.unlocks intact (other phases
    # may add to it). To wipe: UPDATE level_configs SET unlocks = NULL.
    op.execute("ALTER TABLE student_xp DROP COLUMN IF EXISTS selected_theme")
    for level, _ in _THEME_UNLOCKS:
        op.execute(
            f"UPDATE level_configs SET unlocks = unlocks::jsonb - 'theme' "
            f"WHERE level = {level}"
        )
