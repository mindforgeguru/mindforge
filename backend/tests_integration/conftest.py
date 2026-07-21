"""
Integration-test harness: real backend, real Postgres, real Redis.

Deliberately a sibling of tests/ rather than a subdirectory. tests/conftest.py
stubs the database, Redis and the AI SDKs so the unit suite can run anywhere;
those stubs would make everything here meaningless. pytest only applies a
conftest to its own subtree, so keeping the two apart is what lets both exist.

Requires the local stack (`docker compose up`). The whole suite skips when the
backend is unreachable, so `pytest` at the repo root stays green without Docker.

Fixtures create their own schools and users under a per-run prefix and delete
them afterwards. Nothing here depends on seed data, and a failed run should not
leave rows behind — leftover half-configured schools are how the dev database
accumulated duplicates in the first place.
"""

import asyncio
import os
import uuid

import asyncpg
import httpx
import pytest
import pytest_asyncio

BASE_URL = os.environ.get("MF_TEST_BASE_URL", "http://127.0.0.1:8000")
DB_DSN = os.environ.get(
    "MF_TEST_DB_DSN", "postgresql://mindforge:mindforge_secret@127.0.0.1:5432/mindforge"
)
OWNER_USERNAME = os.environ.get("MF_TEST_OWNER_USERNAME", "chinmay_owner")
OWNER_MPIN = os.environ.get("MF_TEST_OWNER_MPIN", "123456")

# Everything this suite creates is prefixed with this, so teardown can find it
# even if a test aborts midway.
RUN_ID = uuid.uuid4().hex[:8]
PREFIX = f"itest{RUN_ID}"
# Phone numbers are format-validated, so they need a digits-only suffix —
# RUN_ID is hex and will not do.
NUM_ID = f"{uuid.uuid4().int % 100000:05d}"

# MPIN complexity is enforced on the API, so the obvious test values are
# rejected. This one is arbitrary and passes.
TEST_MPIN = "847362"


def _backend_reachable() -> bool:
    try:
        return httpx.get(f"{BASE_URL}/docs", timeout=3).status_code == 200
    except Exception:
        return False


collect_ignore_glob = []
if not _backend_reachable():
    pytest.skip(
        f"integration stack not reachable at {BASE_URL} — start it with "
        "`docker compose --env-file .env.local -f docker-compose.yml "
        "-f docker-compose.local.yml up -d`",
        allow_module_level=True,
    )


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
def api():
    with httpx.Client(base_url=BASE_URL, timeout=30) as client:
        yield client


def login(api, username, mpin=TEST_MPIN, school_id=None):
    """Return an access token, or None when the login is refused."""
    body = {"username": username, "mpin": mpin}
    if school_id is not None:
        body["school_id"] = school_id
    r = api.post("/api/auth/login", json=body)
    if r.status_code != 200:
        return None
    return r.json()["access_token"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def register(api, **body):
    """POST /auth/register, waiting out the rate limiter.

    Registration is capped per IP per minute. A single run stays under the cap,
    but consecutive runs — or a developer iterating — will hit it, and a 429
    here would look like a tenancy failure. Retries rather than fails so the
    suite is re-runnable back to back.
    """
    import time

    for attempt in range(4):
        r = api.post("/api/auth/register", json=body)
        if r.status_code != 429:
            return r
        if attempt < 3:
            time.sleep(20)
    return r


@pytest.fixture(scope="session")
def owner_token(api):
    token = login(api, OWNER_USERNAME, OWNER_MPIN)
    if token is None:
        pytest.skip(
            "owner login failed — set MF_TEST_OWNER_USERNAME / MF_TEST_OWNER_MPIN "
            "to a valid platform-owner account"
        )
    return token


# Every tenant table carries school_id, so teardown can key off that rather
# than chase per-table user columns. Ordered children-first: the FKs between
# these are plain references, only school_id is ON DELETE RESTRICT.
_PURGE_ORDER = (
    # First: audit_logs.admin_id is NOT NULL while its FK is ON DELETE SET
    # NULL, so deleting a user who has performed an audited action raises
    # NotNullViolation. The app soft-deletes, so this only bites a hard delete
    # like this teardown — but it does have to go first.
    "audit_logs",
    "homework_completions",
    "test_submissions",
    "xp_transactions",
    "student_xp",
    "grades",
    "attendance",
    "presentation_period_logs",
    "presentation_teacher_progress",
    "presentation_slides",
    "timetable_slots",
    "fee_payments",
    "homework",
    "tests",
    "chapter_presentations",
    "timetable_configs",
    "fee_structures",
    "payment_info",
    "feedback_reports",
    "broadcasts",
    "old_test_papers",
    "chapter_documents",
    "syllabus_entries",
    "academic_years",
    "student_profiles",
    "teacher_profiles",
    "users",
)


async def _purge():
    """Delete everything this run created, children first.

    Keyed on school_id for the tenant tables and on the username prefix for
    users, so a run that aborted mid-setup still cleans up. schools.id is
    ON DELETE RESTRICT, so any row this misses blocks the final delete and
    fails loudly rather than leaving a half-deleted school behind.
    """
    conn = await asyncpg.connect(DB_DSN)
    try:
        school_ids = [
            r["id"]
            for r in await conn.fetch(
                "SELECT id FROM schools WHERE slug LIKE $1", f"{PREFIX}%"
            )
        ]
        if school_ids:
            for table in _PURGE_ORDER:
                await conn.execute(
                    f"DELETE FROM {table} WHERE school_id = ANY($1::int[])", school_ids
                )
        # Users created against a pre-existing school (none today, but cheap
        # insurance) are matched by prefix instead. Their audit rows have to go
        # first for the reason noted above.
        await conn.execute(
            "DELETE FROM audit_logs WHERE admin_id IN "
            "(SELECT id FROM users WHERE username LIKE $1)",
            f"{PREFIX}%",
        )
        await conn.execute("DELETE FROM users WHERE username LIKE $1", f"{PREFIX}%")
        if school_ids:
            await conn.execute(
                "DELETE FROM schools WHERE id = ANY($1::int[])", school_ids
            )
    finally:
        await conn.close()


@pytest.fixture(scope="session", autouse=True)
def _cleanup_after_run():
    yield
    asyncio.run(_purge())


@pytest.fixture(scope="session")
def two_schools(api, owner_token):
    """Two independent schools, each with an admin and an approved teacher.

    Session-scoped: the setup is several round trips and the tests only read
    from it, apart from the suspend test which restores state itself.
    """
    schools = {}
    for tag in ("a", "b"):
        r = api.post(
            "/api/owner/schools",
            headers=auth(owner_token),
            json={"name": f"ITest {tag.upper()} {RUN_ID}", "slug": f"{PREFIX}-{tag}"},
        )
        assert r.status_code == 201, f"school {tag} create failed: {r.text}"
        sid = r.json()["id"]

        admin_username = f"{PREFIX}_admin_{tag}"
        r = api.post(
            f"/api/owner/schools/{sid}/admins",
            headers=auth(owner_token),
            json={"username": admin_username, "mpin": TEST_MPIN},
        )
        assert r.status_code == 201, f"admin {tag} create failed: {r.text}"

        admin_token = login(api, admin_username, school_id=sid)
        assert admin_token, f"admin {tag} login failed"

        # Teachers arrive through registration and need approving by their own
        # school's admin — which also exercises that the pending queue is
        # correctly scoped.
        teacher_username = f"{PREFIX}_teacher_{tag}"
        r = register(
            api,
            username=teacher_username,
            mpin=TEST_MPIN,
            role="teacher",
            school_id=sid,
            phone=f"9{NUM_ID}{'1' if tag == 'a' else '2'}000"[:10],
        )
        assert r.status_code == 201, f"teacher {tag} register failed: {r.text}"
        teacher_id = r.json()["id"]

        r = api.post(
            f"/api/admin/users/{teacher_id}/approve", headers=auth(admin_token)
        )
        assert r.status_code in (200, 204), f"approve {tag} failed: {r.text}"

        teacher_token = login(api, teacher_username, school_id=sid)
        assert teacher_token, f"teacher {tag} login failed"

        # Bootstrap an academic year so year-scoped endpoints (rosters,
        # ledgers) have something to resolve. 409 = already initialised, fine.
        r = api.post(
            "/api/admin/academic-years/init", headers=auth(admin_token)
        )
        assert r.status_code in (200, 201, 409), f"year init {tag}: {r.text}"

        schools[tag] = {
            "id": sid,
            "admin_username": admin_username,
            "admin_token": admin_token,
            "teacher_username": teacher_username,
            "teacher_id": teacher_id,
            "teacher_token": teacher_token,
        }
    return schools


async def _make_student(school_id: int, username: str, grade: int = 8) -> int:
    """Insert an approved student straight into the database.

    Registration is exercised elsewhere and is rate limited; these fixtures
    only need a student row with the right school_id to hang fees and XP off.
    The MPIN hash is a placeholder — nothing logs in as these accounts.
    """
    conn = await asyncpg.connect(DB_DSN)
    try:
        uid = await conn.fetchval(
            """
            INSERT INTO users (username, mpin_hash, role, school_id,
                               is_active, is_approved)
            VALUES ($1, 'x', 'student', $2, true, true)
            RETURNING id
            """,
            username,
            school_id,
        )
        await conn.execute(
            """
            INSERT INTO student_profiles (user_id, grade, school_id)
            VALUES ($1, $2, $3)
            """,
            uid,
            grade,
            school_id,
        )
        return uid
    finally:
        await conn.close()


@pytest.fixture(scope="session")
def students(two_schools):
    """One student per school, keyed by school tag."""
    return {
        tag: asyncio.run(
            _make_student(two_schools[tag]["id"], f"{PREFIX}_student_{tag}")
        )
        for tag in ("a", "b")
    }


@pytest.fixture(scope="session")
def fee_structure_in_a(api, two_schools):
    """A fee structure owned by school A."""
    r = api.post(
        "/api/admin/fees/structure",
        headers=auth(two_schools["a"]["admin_token"]),
        json={"academic_year": "2026-27", "grade": 8, "base_amount": 1000},
    )
    assert r.status_code in (200, 201), f"fee structure create failed: {r.text}"
    return r.json()["id"]


@pytest.fixture(scope="session")
def fee_payment_in_a(api, two_schools, students):
    """A fee payment owned by school A."""
    r = api.post(
        "/api/admin/fees/payments",
        headers=auth(two_schools["a"]["admin_token"]),
        json={"student_id": students["a"], "amount": 500},
    )
    assert r.status_code in (200, 201), f"fee payment create failed: {r.text}"
    return r.json()["id"]


@pytest.fixture(scope="session")
def homework_in_a(api, two_schools):
    """A homework row owned by school A, used as the cross-tenant target."""
    r = api.post(
        "/api/teacher/homework",
        headers=auth(two_schools["a"]["teacher_token"]),
        json={
            "grade": 8,
            "subject": "Physics",
            "title": f"{PREFIX} hw",
            "description": "integration fixture",
            "homework_type": "written",
        },
    )
    assert r.status_code in (200, 201), f"homework create failed: {r.text}"
    return r.json()["id"]
