"""
Cross-tenant isolation against the real API.

The unit suite covers the scoping helpers and that the auth dependency calls
them. Neither can catch a *router* that forgets to scope a query — the helper
stays perfectly correct while data leaks around it. Only a real request against
a real database shows that, which is what this file automates.

Every assertion here corresponds to a probe that was run by hand while the
tenancy branch was being reviewed. Doing it by hand found three bugs; leaving it
by hand means the fourth one ships.
"""

import asyncpg
import pytest

from .conftest import DB_DSN, NUM_ID, PREFIX, TEST_MPIN, auth, login, register


def _phone(n: int) -> str:
    """Per-run unique phone. users.phone is globally unique (not per school),
    so reusing a literal across runs collides with anything a previous run
    left behind.
    """
    return f"9{NUM_ID}{n:04d}"[:10]


# ── Reads ─────────────────────────────────────────────────────────────────────


class TestReadIsolation:
    def test_admin_sees_only_own_school_users(self, api, two_schools):
        for tag, other in (("a", "b"), ("b", "a")):
            r = api.get(
                "/api/admin/users", headers=auth(two_schools[tag]["admin_token"])
            )
            assert r.status_code == 200
            body = r.json()
            users = body if isinstance(body, list) else body.get("users", body)
            names = {u["username"] for u in users}
            assert two_schools[tag]["admin_username"] in names
            assert two_schools[other]["admin_username"] not in names
            assert two_schools[other]["teacher_username"] not in names

    def test_teacher_cannot_read_other_schools_homework(
        self, api, two_schools, homework_in_a
    ):
        r = api.get(
            f"/api/teacher/homework/{homework_in_a}/completions",
            headers=auth(two_schools["b"]["teacher_token"]),
        )
        assert r.status_code == 404, "school B read school A's homework"

    def test_owner_endpoints_are_closed_to_school_admins(self, api, two_schools):
        for verb, path, kwargs in (
            ("get", "/api/owner/schools", {}),
            ("post", "/api/owner/schools", {"json": {"name": f"{PREFIX} sneaky"}}),
        ):
            r = getattr(api, verb)(
                path, headers=auth(two_schools["a"]["admin_token"]), **kwargs
            )
            assert r.status_code == 403, f"{verb} {path} was not owner-only"

    def test_owner_can_read_all_schools(self, api, owner_token, two_schools):
        r = api.get("/api/owner/schools", headers=auth(owner_token))
        assert r.status_code == 200
        ids = {s["id"] for s in r.json()}
        assert {two_schools["a"]["id"], two_schools["b"]["id"]} <= ids

    def test_control_own_school_read_succeeds(self, api, two_schools, homework_in_a):
        # Without this the 404s above could mean "handler is broken" rather
        # than "handler enforced scoping".
        r = api.get(
            f"/api/teacher/homework/{homework_in_a}/completions",
            headers=auth(two_schools["a"]["teacher_token"]),
        )
        assert r.status_code == 200


# ── Writes ────────────────────────────────────────────────────────────────────
# A denied status code is not enough: a 404 response with the row actually gone
# is the dangerous case, so each of these re-reads the row afterwards.


async def _row_exists(table, row_id) -> bool:
    conn = await asyncpg.connect(DB_DSN)
    try:
        return (
            await conn.fetchval(f"SELECT count(*) FROM {table} WHERE id = $1", row_id)
        ) == 1
    finally:
        await conn.close()


@pytest.mark.asyncio
class TestWriteIsolation:
    async def test_cross_school_delete_is_refused_and_row_survives(
        self, api, two_schools, homework_in_a
    ):
        r = api.delete(
            f"/api/teacher/homework/{homework_in_a}",
            headers=auth(two_schools["b"]["teacher_token"]),
        )
        assert r.status_code in (403, 404)
        assert await _row_exists("homework", homework_in_a), (
            "school B deleted school A's homework"
        )

    async def test_cross_school_update_writes_nothing(
        self, api, two_schools, homework_in_a
    ):
        r = api.put(
            f"/api/teacher/homework/{homework_in_a}/completions",
            headers=auth(two_schools["b"]["teacher_token"]),
            json={"records": [{"student_id": 1, "completed": True}]},
        )
        assert r.status_code in (403, 404, 422)
        conn = await asyncpg.connect(DB_DSN)
        try:
            n = await conn.fetchval(
                "SELECT count(*) FROM homework_completions WHERE homework_id = $1",
                homework_in_a,
            )
        finally:
            await conn.close()
        assert n == 0, "cross-tenant write landed"

    async def test_admin_cannot_modify_other_schools_user(self, api, two_schools):
        victim = two_schools["a"]["teacher_id"]
        r = api.patch(
            f"/api/admin/users/{victim}/active",
            headers=auth(two_schools["b"]["admin_token"]),
            json={"is_active": False},
        )
        assert r.status_code in (403, 404)
        conn = await asyncpg.connect(DB_DSN)
        try:
            still_active = await conn.fetchval(
                "SELECT is_active FROM users WHERE id = $1", victim
            )
        finally:
            await conn.close()
        assert still_active is True, "cross-tenant user modification landed"


# ── Username scoping ──────────────────────────────────────────────────────────


class TestPerSchoolUsernames:
    def test_same_username_in_two_schools_are_different_accounts(
        self, api, owner_token, two_schools
    ):
        shared = f"{PREFIX}_shared"
        ids = {}
        for tag in ("a", "b"):
            r = api.post(
                f"/api/owner/schools/{two_schools[tag]['id']}/admins",
                headers=auth(owner_token),
                json={"username": shared, "mpin": TEST_MPIN},
            )
            assert r.status_code == 201, f"{tag}: {r.text}"
            ids[tag] = r.json()["id"]
        assert ids["a"] != ids["b"]

        # And they resolve independently at login.
        for tag in ("a", "b"):
            r = api.post(
                "/api/auth/login",
                json={
                    "username": shared,
                    "mpin": TEST_MPIN,
                    "school_id": two_schools[tag]["id"],
                },
            )
            assert r.status_code == 200
            assert r.json()["user_id"] == ids[tag]

    def test_duplicate_username_within_a_school_is_refused(
        self, api, owner_token, two_schools
    ):
        name = f"{PREFIX}_dup"
        sid = two_schools["a"]["id"]
        first = api.post(
            f"/api/owner/schools/{sid}/admins",
            headers=auth(owner_token),
            json={"username": name, "mpin": TEST_MPIN},
        )
        assert first.status_code == 201
        second = api.post(
            f"/api/owner/schools/{sid}/admins",
            headers=auth(owner_token),
            json={"username": name, "mpin": TEST_MPIN},
        )
        assert second.status_code == 409

    def test_login_to_wrong_school_fails(self, api, two_schools):
        assert (
            login(
                api,
                two_schools["a"]["admin_username"],
                school_id=two_schools["b"]["id"],
            )
            is None
        )


# ── Suspension ────────────────────────────────────────────────────────────────
# Suspension used to apply only at login: existing sessions kept working and
# rotating refresh tokens renewed them indefinitely.


class TestSuspension:
    def test_suspension_kills_live_sessions_and_reactivation_restores(
        self, api, owner_token, two_schools
    ):
        b = two_schools["b"]
        sid = b["id"]

        # Session established while active, including a refresh token.
        r = api.post(
            "/api/auth/login",
            json={
                "username": b["teacher_username"],
                "mpin": TEST_MPIN,
                "school_id": sid,
            },
        )
        assert r.status_code == 200
        live_token = r.json()["access_token"]
        refresh_token = r.json()["refresh_token"]
        assert api.get("/api/teacher/tests", headers=auth(live_token)).status_code == 200

        try:
            r = api.patch(
                f"/api/owner/schools/{sid}",
                headers=auth(owner_token),
                json={"is_active": False},
            )
            assert r.status_code == 200

            # The token minted before suspension must stop working.
            assert (
                api.get("/api/teacher/tests", headers=auth(live_token)).status_code
                == 403
            )
            # And it must not be renewable — otherwise rotation makes the
            # bypass unbounded.
            assert (
                api.post(
                    "/api/auth/refresh", json={"refresh_token": refresh_token}
                ).status_code
                == 401
            )
            # Fresh logins refused, and the school leaves the public picker.
            assert login(api, b["teacher_username"], school_id=sid) is None
            listed = {s["id"] for s in api.get("/api/schools").json()}
            assert sid not in listed

            # The other school is untouched.
            assert (
                api.get(
                    "/api/teacher/tests",
                    headers=auth(two_schools["a"]["teacher_token"]),
                ).status_code
                == 200
            )
        finally:
            api.patch(
                f"/api/owner/schools/{sid}",
                headers=auth(owner_token),
                json={"is_active": True},
            )

        # Reactivation takes effect immediately — the cached flag is
        # invalidated rather than left to expire.
        assert login(api, b["teacher_username"], school_id=sid) is not None

    def test_owner_keeps_access_while_a_school_is_suspended(
        self, api, owner_token, two_schools
    ):
        sid = two_schools["b"]["id"]
        try:
            api.patch(
                f"/api/owner/schools/{sid}",
                headers=auth(owner_token),
                json={"is_active": False},
            )
            # If the owner were school-gated this would fail and a suspension
            # would be unrecoverable through the API.
            assert (
                api.get("/api/owner/schools", headers=auth(owner_token)).status_code
                == 200
            )
        finally:
            api.patch(
                f"/api/owner/schools/{sid}",
                headers=auth(owner_token),
                json={"is_active": True},
            )


# ── Registration ──────────────────────────────────────────────────────────────


@pytest.mark.asyncio
class TestRegistrationScoping:
    async def test_registration_tenants_both_user_and_profile_rows(
        self, api, two_schools
    ):
        sid = two_schools["a"]["id"]
        username = f"{PREFIX}_reg"
        r = register(
            api,
            username=username,
            mpin=TEST_MPIN,
            role="teacher",
            school_id=sid,
            phone=_phone(11),
        )
        assert r.status_code == 201, r.text

        conn = await asyncpg.connect(DB_DSN)
        try:
            row = await conn.fetchrow(
                """
                SELECT u.school_id AS user_school, tp.school_id AS profile_school
                  FROM users u
                  LEFT JOIN teacher_profiles tp ON tp.user_id = u.id
                 WHERE u.username = $1
                """,
                username,
            )
        finally:
            await conn.close()
        # A mismatch here produces a user who passes login scoping but fails
        # every profile-based tenancy check — the shape of the cached-profile
        # bug.
        assert row["user_school"] == sid
        assert row["profile_school"] == sid

    async def test_pending_user_appears_only_in_its_own_school_queue(
        self, api, two_schools
    ):
        username = f"{PREFIX}_pending"
        r = register(
            api,
            username=username,
            mpin=TEST_MPIN,
            role="teacher",
            school_id=two_schools["a"]["id"],
            phone=_phone(12),
        )
        assert r.status_code == 201, r.text

        def pending_for(tag):
            resp = api.get(
                "/api/admin/users/pending",
                headers=auth(two_schools[tag]["admin_token"]),
            )
            assert resp.status_code == 200
            body = resp.json()
            users = body if isinstance(body, list) else body.get("users", body)
            return {u["username"] for u in users}

        assert username in pending_for("a")
        assert username not in pending_for("b")


# Module level: the class above carries a class-wide asyncio mark, and these
# checks need no database round trip.
def test_registration_into_unknown_school_is_refused(api):
    r = register(
        api,
        username=f"{PREFIX}_ghost",
        mpin=TEST_MPIN,
        role="teacher",
        school_id=999999,
        phone=_phone(13),
    )
    assert r.status_code == 400


class TestPhoneScoping:
    """Phone uniqueness is per school, like usernames.

    The index was global (from 014, before multi-tenancy) while both code
    paths filtered by school_id. So the app found no conflict, inserted, and
    the database raised UniqueViolation with nothing catching it — a 500 when
    two unrelated schools happened to share a number. Migration 033 aligned
    the index with the code.
    """

    def test_same_phone_allowed_in_two_schools(self, api, two_schools):
        phone = _phone(21)
        for tag, n in (("a", 21), ("b", 22)):
            r = register(
                api,
                username=f"{PREFIX}_ph_{tag}",
                mpin=TEST_MPIN,
                role="teacher",
                school_id=two_schools[tag]["id"],
                phone=phone,
            )
            assert r.status_code == 201, (
                f"school {tag} rejected a phone already used by another "
                f"school: {r.status_code} {r.text}"
            )

    def test_duplicate_phone_within_a_school_is_a_clean_conflict(
        self, api, two_schools
    ):
        phone = _phone(23)
        sid = two_schools["a"]["id"]
        first = register(
            api,
            username=f"{PREFIX}_ph_dup1",
            mpin=TEST_MPIN,
            role="teacher",
            school_id=sid,
            phone=phone,
        )
        assert first.status_code == 201, first.text

        second = register(
            api,
            username=f"{PREFIX}_ph_dup2",
            mpin=TEST_MPIN,
            role="teacher",
            school_id=sid,
            phone=phone,
        )
        # 409, never 500 — a raw IntegrityError reaching the client is the
        # regression this guards.
        assert second.status_code == 409, second.text
        # And the message must not confirm which detail collided; phone
        # numbers are PII and a precise error would let someone probe for
        # registered numbers.
        assert phone not in second.text
