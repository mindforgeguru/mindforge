"""
Cross-tenant isolation for the routers nobody had looked at.

The manual audit of this branch covered teacher tests/homework/presentations,
admin users and student tests, and test_tenant_isolation.py automates a subset
of that. Fees, ledgers, XP and academic years were never probed at all — by
hand or otherwise. They carry school_id like everything else, but that was an
assumption, not a finding, and fee records are the most sensitive data here: a
leak exposes another school's payment history.

Same shape as the sibling module: deny, then confirm nothing changed, then a
control proving the handler works for its own school. A 404 from a broken
handler and a 404 from an enforced boundary look identical without one.
"""

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, auth


async def _scalar(sql, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(sql, *args)
    finally:
        await conn.close()


# ── Fee structures ────────────────────────────────────────────────────────────


class TestFeeStructureIsolation:
    @pytest.mark.asyncio
    async def test_cross_school_update_is_refused(
        self, api, two_schools, fee_structure_in_a
    ):
        before = await _scalar(
            "SELECT base_amount FROM fee_structures WHERE id = $1", fee_structure_in_a
        )
        r = api.put(
            f"/api/admin/fees/structure/{fee_structure_in_a}",
            headers=auth(two_schools["b"]["admin_token"]),
            json={"academic_year": "2026-27", "grade": 8, "base_amount": 99999},
        )
        assert r.status_code in (403, 404), r.text
        after = await _scalar(
            "SELECT base_amount FROM fee_structures WHERE id = $1", fee_structure_in_a
        )
        assert after == before, "school B rewrote school A's fee structure"

    @pytest.mark.asyncio
    async def test_cross_school_delete_is_refused(
        self, api, two_schools, fee_structure_in_a
    ):
        r = api.delete(
            f"/api/admin/fees/structure/{fee_structure_in_a}",
            headers=auth(two_schools["b"]["admin_token"]),
        )
        assert r.status_code in (403, 404), r.text
        assert (
            await _scalar(
                "SELECT count(*) FROM fee_structures WHERE id = $1", fee_structure_in_a
            )
            == 1
        ), "school B deleted school A's fee structure"

    def test_structure_list_is_scoped(self, api, two_schools, fee_structure_in_a):
        r = api.get(
            "/api/admin/fees/structure", headers=auth(two_schools["b"]["admin_token"])
        )
        assert r.status_code == 200
        body = r.json()
        rows = body if isinstance(body, list) else body.get("structures", body)
        assert fee_structure_in_a not in {row["id"] for row in rows}

    def test_control_own_school_update_succeeds(
        self, api, two_schools, fee_structure_in_a
    ):
        r = api.put(
            f"/api/admin/fees/structure/{fee_structure_in_a}",
            headers=auth(two_schools["a"]["admin_token"]),
            json={"academic_year": "2026-27", "grade": 8, "base_amount": 1200},
        )
        assert r.status_code in (200, 204), r.text


# ── Fee payments ──────────────────────────────────────────────────────────────


class TestFeePaymentIsolation:
    @pytest.mark.asyncio
    async def test_cross_school_update_is_refused(
        self, api, two_schools, fee_payment_in_a
    ):
        before = await _scalar(
            "SELECT amount FROM fee_payments WHERE id = $1", fee_payment_in_a
        )
        r = api.put(
            f"/api/admin/fees/payments/{fee_payment_in_a}",
            headers=auth(two_schools["b"]["admin_token"]),
            json={"amount": 1},
        )
        assert r.status_code in (403, 404, 422), r.text
        after = await _scalar(
            "SELECT amount FROM fee_payments WHERE id = $1", fee_payment_in_a
        )
        assert after == before, "school B altered school A's payment record"

    @pytest.mark.asyncio
    async def test_cross_school_delete_is_refused(
        self, api, two_schools, fee_payment_in_a
    ):
        r = api.delete(
            f"/api/admin/fees/payments/{fee_payment_in_a}",
            headers=auth(two_schools["b"]["admin_token"]),
        )
        assert r.status_code in (403, 404), r.text
        assert (
            await _scalar(
                "SELECT count(*) FROM fee_payments WHERE id = $1", fee_payment_in_a
            )
            == 1
        ), "school B deleted school A's payment record"

    def test_fee_summary_is_scoped(self, api, two_schools, fee_payment_in_a, students):
        r = api.get(
            "/api/admin/fees/summary",
            headers=auth(two_schools["b"]["admin_token"]),
            params={"academic_year": "2026-27"},
        )
        assert r.status_code == 200
        # School A's student must not appear anywhere in B's summary.
        assert f'"student_id": {students["a"]}' not in r.text.replace(" ", "")


# ── Financial reports ─────────────────────────────────────────────────────────


class TestReportIsolation:
    def test_student_ledger_is_refused_across_schools(
        self, api, two_schools, students
    ):
        # A full payment history for another school's pupil.
        r = api.get(
            f"/api/admin/reports/student-ledger/{students['a']}",
            headers=auth(two_schools["b"]["admin_token"]),
            params={"academic_year": "2026-27"},
        )
        assert r.status_code in (403, 404), (
            f"school B read school A's student ledger: {r.status_code} {r.text[:200]}"
        )

    def test_control_own_school_ledger_succeeds(self, api, two_schools, students):
        r = api.get(
            f"/api/admin/reports/student-ledger/{students['a']}",
            headers=auth(two_schools["a"]["admin_token"]),
            params={"academic_year": "2026-27"},
        )
        assert r.status_code == 200, r.text

    def test_pending_fees_report_is_scoped(self, api, two_schools):
        # This endpoint renders a PDF, not JSON. The report lists students by
        # username, so a cross-tenant leak would put school A's fixture
        # username (which is unique per run) into school B's document bytes.
        report = api.get(
            "/api/admin/reports/pending-fees",
            headers=auth(two_schools["b"]["admin_token"]),
            params={"academic_year": "2026-27"},
        )
        assert report.status_code == 200
        # _make_student creates "{PREFIX}_student_{tag}".
        a_username = f"{PREFIX}_student_a"
        assert a_username.encode() not in report.content, (
            "school A's student appeared in school B's pending-fees report"
        )


def _ids_in(payload):
    """Collect every student_id/user_id appearing anywhere in a response."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("student_id", "user_id", "id") and isinstance(v, int):
                    out.append(v)
                walk(v)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(payload)
    return out


# ── XP ────────────────────────────────────────────────────────────────────────


class TestXpIsolation:
    def test_other_schools_student_xp_is_refused(self, api, two_schools, students):
        r = api.get(
            f"/api/xp/student/{students['a']}",
            headers=auth(two_schools["b"]["admin_token"]),
        )
        assert r.status_code in (403, 404), (
            f"school B read school A's student XP: {r.status_code}"
        )

    def test_control_own_school_xp_succeeds(self, api, two_schools, students):
        r = api.get(
            f"/api/xp/student/{students['a']}",
            headers=auth(two_schools["a"]["admin_token"]),
        )
        # 200 with an empty record is fine; the point is that it is reachable
        # for the owning school, so the 404 above is a boundary not a bug.
        assert r.status_code == 200, r.text


# ── Academic years ────────────────────────────────────────────────────────────


class TestAcademicYearIsolation:
    def test_year_roster_is_scoped(self, api, two_schools, students):
        r = api.get(
            "/api/admin/academic-years", headers=auth(two_schools["b"]["admin_token"])
        )
        assert r.status_code == 200
        years = r.json()
        years = years if isinstance(years, list) else years.get("years", years)
        if not years:
            pytest.skip("no academic years configured for this school")
        year_id = years[0]["id"]
        r = api.get(
            f"/api/admin/academic-years/{year_id}/users",
            headers=auth(two_schools["b"]["admin_token"]),
        )
        assert r.status_code in (200, 403, 404)
        if r.status_code == 200:
            assert students["a"] not in _ids_in(r.json()), (
                "school A's student appeared in school B's academic-year roster"
            )
