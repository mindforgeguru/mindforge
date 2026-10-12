"""
Schema invariants that hold across every model.

These exist because of a bug that a per-model test would probably never have
been written for: audit_logs.admin_id was declared NOT NULL while its foreign
key said ON DELETE SET NULL. Those cannot both be true — the database is told
to null a column it is forbidden from nulling, so the delete raises
NotNullViolation instead. It sat there unnoticed because nothing hard-deletes
an admin today.

Checking the shape of the whole schema catches the next one for free, which is
cheaper than remembering to check each column by hand.
"""

import inspect
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm.properties import MappedColumn

import app.models as models


def _mapped_columns():
    """(tablename, attribute, Column) for every mapped column on every model.

    Walks the model classes rather than SQLAlchemy metadata because
    conftest stubs Base, so nothing is actually mapped and __table__ does not
    exist. MappedColumn still exposes the underlying Column.
    """
    out = []
    for _, obj in vars(models).items():
        if inspect.isclass(obj) and hasattr(obj, "__tablename__"):
            for attr, val in vars(obj).items():
                if isinstance(val, MappedColumn):
                    out.append((obj.__tablename__, attr, val.column))
    return out


def _fks_with(ondelete):
    hits = []
    for table, attr, col in _mapped_columns():
        for fk in col.foreign_keys:
            if (fk.ondelete or "").upper() == ondelete:
                hits.append((table, attr, col))
    return hits


def test_models_are_discoverable():
    # If the import surface changes and this returns nothing, every assertion
    # below would pass vacuously.
    cols = _mapped_columns()
    assert len(cols) > 50, f"only {len(cols)} mapped columns found — discovery broke"


def test_set_null_foreign_keys_are_nullable():
    """ON DELETE SET NULL requires a nullable column.

    Otherwise deleting the referenced row raises NotNullViolation and the
    delete fails outright — the parent row becomes undeletable while the
    schema claims the opposite.
    """
    offenders = [
        f"{table}.{attr}" for table, attr, col in _fks_with("SET NULL") if not col.nullable
    ]
    assert offenders == [], (
        "columns declared ON DELETE SET NULL but NOT NULL: " + ", ".join(offenders)
    )


def test_set_null_coverage_is_meaningful():
    # Guards the check above: if the FK metadata stopped being readable this
    # would silently find nothing to test.
    assert len(_fks_with("SET NULL")) >= 10


def test_audit_actor_survives_its_author():
    """An audit entry must outlive the account that wrote it.

    Pinned explicitly because the alternatives are both plausible-looking and
    both wrong: RESTRICT makes admins undeletable, and CASCADE erases the
    audit history exactly when someone is being removed — which is when it
    matters most.
    """
    from app.models.audit_log import AuditLog

    col = AuditLog.admin_id.column
    assert col.nullable is True, "audit_logs.admin_id must be nullable"
    ondelete = {(fk.ondelete or "").upper() for fk in col.foreign_keys}
    assert ondelete == {"SET NULL"}, (
        f"audit_logs.admin_id should be ON DELETE SET NULL, got {ondelete}"
    )


def test_user_uniqueness_covers_live_accounts_only():
    """A removed account must not reserve its username or phone number.

    Removal is a soft delete, and every conflict check in the application
    filters on `deleted_at IS NULL`. While the unique indexes covered removed
    rows too, the two disagreed: after a year close the application let a
    returning user through and the database turned them away with a 500.
    Pinned here so a plain `unique=True` or UniqueConstraint cannot come back.
    """
    from sqlalchemy import Index, UniqueConstraint

    from app.models.user import User

    args = User.__table_args__
    assert not [a for a in args if isinstance(a, UniqueConstraint)], (
        "users must not carry a table-wide UniqueConstraint — it would count "
        "removed accounts"
    )

    unique = [a for a in args if isinstance(a, Index) and a.unique]
    assert len(unique) == 2, f"expected the username and phone indexes, got {unique}"
    for idx in unique:
        where = str(idx.dialect_options["postgresql"]["where"])
        assert "deleted_at IS NULL" in where, (
            f"{idx.name} counts removed accounts: WHERE {where}"
        )

    for column in ("username", "phone"):
        assert not getattr(User, column).column.unique, (
            f"users.{column} is unique on its own, across removed accounts too"
        )
