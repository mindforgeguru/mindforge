"""add xp_system tables (student_xp, xp_transactions, level_configs)

Revision ID: 021
Revises: 020
Create Date: 2026-05-02

Idempotent — re-runs (or running after Base.metadata.create_all in dev) do
not fail. Mirrors the style used by 018/019.

LevelConfig is seeded with 50 levels:
  level 1  → 0 XP (entry level — everyone starts here)
  level k  → round(100 * k ^ 1.5) for k ≥ 2

Titles progress through ten tiers (Novice → Mythic) with five steps each.
"""
from alembic import op


revision = '021'
down_revision = '020'
branch_labels = None
depends_on = None


_TIERS = [
    "Novice", "Apprentice", "Scholar", "Adept", "Expert",
    "Master", "Grandmaster", "Sage", "Legendary", "Mythic",
]
_ROMAN = ["I", "II", "III", "IV", "V"]


def _level_rows() -> list[tuple[int, int, str]]:
    rows: list[tuple[int, int, str]] = []
    for level in range(1, 51):
        xp_required = 0 if level == 1 else round(100 * (level ** 1.5))
        tier = _TIERS[(level - 1) // 5]
        step = _ROMAN[(level - 1) % 5]
        title = f"{tier} {step}"
        rows.append((level, xp_required, title))
    return rows


def upgrade() -> None:
    # ── xp_reason enum ───────────────────────────────────────────────────────
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'xp_reason') THEN
                CREATE TYPE xp_reason AS ENUM (
                    'ATTENDANCE',
                    'HOMEWORK_ON_TIME',
                    'HOMEWORK_LATE',
                    'TEST_SCORE',
                    'TEST_PERFECT',
                    'STREAK_BONUS',
                    'MANUAL_ADJUSTMENT'
                );
            END IF;
        END $$;
        """
    )

    # ── student_xp ───────────────────────────────────────────────────────────
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS student_xp (
            id SERIAL PRIMARY KEY,
            student_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            total_xp INTEGER NOT NULL DEFAULT 0,
            current_level INTEGER NOT NULL DEFAULT 1,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_student_xp_student UNIQUE (student_id)
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_student_xp_student_id "
        "ON student_xp (student_id)"
    )

    # ── xp_transactions ──────────────────────────────────────────────────────
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS xp_transactions (
            id SERIAL PRIMARY KEY,
            student_id INTEGER NOT NULL
                REFERENCES users(id) ON DELETE CASCADE,
            amount INTEGER NOT NULL,
            reason xp_reason NOT NULL,
            reference_id VARCHAR(100),
            description VARCHAR(300),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_xp_transactions_student_id "
        "ON xp_transactions (student_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_xp_transactions_reason "
        "ON xp_transactions (reason)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_xp_transactions_created_at "
        "ON xp_transactions (created_at)"
    )
    # Idempotency index — one (student, reason, reference_id) tuple may only
    # appear once. NULL reference_id is excluded so MANUAL_ADJUSTMENTs can
    # stack without conflict.
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_xp_txn_student_reason_ref
        ON xp_transactions (student_id, reason, reference_id)
        WHERE reference_id IS NOT NULL
        """
    )

    # ── level_configs ────────────────────────────────────────────────────────
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS level_configs (
            level INTEGER PRIMARY KEY,
            xp_required INTEGER NOT NULL,
            title VARCHAR(100) NOT NULL,
            unlocks JSON
        )
        """
    )

    # Seed levels 1..50. Idempotent via ON CONFLICT — re-running won't
    # clobber any operator-edited titles.
    for level, xp_required, title in _level_rows():
        # Escape single quotes in the title — defensive only; current
        # titles contain none.
        safe_title = title.replace("'", "''")
        op.execute(
            f"INSERT INTO level_configs (level, xp_required, title) "
            f"VALUES ({level}, {xp_required}, '{safe_title}') "
            f"ON CONFLICT (level) DO NOTHING"
        )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS xp_transactions")
    op.execute("DROP TABLE IF EXISTS student_xp")
    op.execute("DROP TABLE IF EXISTS level_configs")
    op.execute("DROP TYPE IF EXISTS xp_reason")
