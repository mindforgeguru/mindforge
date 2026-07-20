"""Shared model mixins."""

from typing import Optional

from sqlalchemy import ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column


class TenantMixin:
    """Adds a ``school_id`` foreign key that scopes a row to one school (tenant).

    Applied to every tenant-owned table so reads/writes can be filtered by the
    caller's school. Nullable at the column level to keep backfills and inserts
    simple, but every write path is expected to populate it — a NULL means the
    row belongs to no tenant and will be invisible to school-scoped queries.
    ON DELETE RESTRICT mirrors ``users.school_id``: a school can't be deleted
    while it still owns data.
    """

    school_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("schools.id", ondelete="RESTRICT"),
        nullable=True,
        index=True,
    )
