"""
The same write arriving twice at once is applied once.

Several handlers read, decided, then wrote, with nothing stopping a second
request from reading the same state in between: a double tap, the test timer's
auto-submit racing the Submit button, or the expiry sweep that runs on a plain
list request. Found on 2026-10-16 with five simultaneous requests:

- a test submitted five times at once got five grade rows, all 201;
- one timetable period saved five times at once became three rows, after which
  every save of that period was a 500 (the upsert found several);
- a fee structure or payment-details slot saved at once: one 2xx, the rest 500
  from the unique index that caught them;
- Close Year sent three times at once left three current years, and from then
  on every registration in the school — which everyone must do after a close —
  was a 500;
- ten XP awards of +10 at once left the student 80 short: each read the total,
  added its own 10 and wrote it back over the others. The ledger said 200.
"""

import asyncio
import json
import threading

import asyncpg
import httpx
import pytest

from .conftest import BASE_URL, DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login, register
from .test_realtime_delivery import _mint_access_token

N = 5


def _at_once(method, path, headers, body=None, n=N):
    """Send `n` identical requests released together; return their statuses."""
    statuses = [None] * n
    gate = threading.Barrier(n)

    def one(i):
        with httpx.Client(base_url=BASE_URL, timeout=30) as c:
            gate.wait()
            statuses[i] = c.request(method, path, headers=headers, json=body).status_code

    threads = [threading.Thread(target=one, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return sorted(statuses)


async def _fetchval(sql, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(sql, *args)
    finally:
        await conn.close()


QUESTIONS = [{"id": 1, "type": "mcq", "marks": 1, "answer": "A", "question": "Pick A",
              "options": {"A": "Right", "B": "Wrong", "C": "Wrong", "D": "Wrong"}}]


@pytest.fixture
def open_test(two_schools):
    school = two_schools["a"]
    test_id = asyncio.run(_fetchval(
        """
        INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions,
                           total_marks, time_limit_minutes, is_published, expires_at, school_id)
        VALUES ($1, $2, 8, 'maths', 'online', $3::json, 1, 10, true,
                now() + interval '1 day', $4)
        RETURNING id
        """,
        f"{PREFIX} race test", school["teacher_id"], json.dumps(QUESTIONS), school["id"],
    ))
    return test_id


@pytest.fixture
def racing_student(two_schools, request):
    sid = asyncio.run(_make_student(two_schools["a"]["id"], f"{PREFIX}_race_{request.node.name[-12:]}"))
    return sid, auth(_mint_access_token(sid))


@pytest.mark.parametrize("started", [True, False], ids=["after start", "without start"])
def test_a_test_submitted_at_once_is_graded_once(api, open_test, racing_student, started):
    student_id, headers = racing_student
    if started:
        assert api.post(f"/api/student/tests/{open_test}/start", headers=headers).status_code == 200

    statuses = _at_once("POST", f"/api/student/tests/{open_test}/submit", headers, {"answers": {"1": "A"}})

    assert statuses.count(201) == 1, statuses
    assert set(statuses) <= {201, 409}, statuses
    grades = asyncio.run(_fetchval(
        "SELECT count(*) FROM grades WHERE student_id = $1 AND test_id = $2", student_id, open_test,
    ))
    assert grades == 1


def test_a_timetable_period_saved_at_once_is_one_slot(api, two_schools):
    school = two_schools["a"]
    headers = auth(school["teacher_token"])
    body = {"grade": 8, "slot_date": "2026-11-03", "period_number": 6, "subject": "maths"}

    assert _at_once("POST", "/api/teacher/timetable", headers, body) == [200] * N
    rows = asyncio.run(_fetchval(
        "SELECT count(*) FROM timetable_slots WHERE school_id = $1 AND grade = 8 "
        "AND slot_date = '2026-11-03' AND period_number = 6", school["id"],
    ))
    assert rows == 1

    # ...and the period can still be edited afterwards.
    r = api.post("/api/teacher/timetable", headers=headers, json={**body, "subject": "science"})
    assert r.status_code == 200, r.text
    assert r.json()["subject"] == "science"


def test_a_fee_structure_created_at_once_is_one_201_and_conflicts(api, two_schools):
    headers = auth(two_schools["a"]["admin_token"])
    body = {"academic_year": "2045-46", "grade": 9, "base_amount": 10}
    statuses = _at_once("POST", "/api/admin/fees/structure", headers, body)
    assert statuses == [201] + [409] * (N - 1), statuses


def test_payment_details_saved_at_once_all_succeed(api, two_schools):
    headers = auth(two_schools["a"]["admin_token"])
    statuses = _at_once("PUT", "/api/admin/fees/payment-info/3", headers, {"label": "Race bank"})
    assert statuses == [200] * N, statuses


def test_saving_payment_details_keeps_the_uploaded_qr_code(api, two_schools):
    # The app saves the bank details without a qr_code_url — the QR is uploaded
    # on its own — and the save used to write every field, so it set the QR to
    # null and parents lost it.
    import io
    from PIL import Image

    headers = auth(two_schools["a"]["admin_token"])
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), "black").save(buf, format="PNG")
    r = api.post("/api/admin/fees/payment-info/2/qr", headers=headers,
                 files={"file": ("qr.png", buf.getvalue(), "image/png")})
    assert r.status_code == 200, r.text
    qr = r.json()["qr_code_url"]
    assert qr

    r = api.put("/api/admin/fees/payment-info/2", headers=headers,
                json={"label": "HDFC", "bank_name": "HDFC", "upi_id": "school@upi"})
    assert r.status_code == 200, r.text
    assert r.json()["qr_code_url"] == qr
    assert r.json()["upi_id"] == "school@upi"


@pytest.fixture
def own_school(api, owner_token, request):
    """A school of its own: closing a year removes everyone in it."""
    tag = request.node.callspec.params["path"]
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest Year {tag} {RUN_ID}", "slug": f"{PREFIX}-year-{tag}"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    username = f"{PREFIX}_admin_year_{tag}"
    r = api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
                 json={"username": username, "mpin": TEST_MPIN})
    assert r.status_code == 201, r.text
    return sid, auth(login(api, username, school_id=sid))


@pytest.mark.parametrize("path", ["init", "new"])
def test_starting_a_year_at_once_leaves_one_current_year(api, own_school, path):
    sid, headers = own_school
    if path == "new":
        assert api.post("/api/admin/academic-years/init", headers=headers).status_code == 201

    _at_once("POST", f"/api/admin/academic-years/{path}", headers, n=3)

    current = asyncio.run(_fetchval(
        "SELECT count(*) FROM academic_years WHERE school_id = $1 AND is_current", sid,
    ))
    assert current == 1
    assert api.get("/api/admin/academic-years/current", headers=headers).status_code == 200
    r = register(api, username=f"{PREFIX}_after_{path}", mpin=TEST_MPIN, role="teacher",
                 school_id=sid, phone=f"95{RUN_ID[:4].translate(str.maketrans('abcdef', '123456'))}{'1' if path == 'init' else '2'}777")
    assert r.status_code == 201, r.text


def test_xp_awarded_at_once_all_counts(api, two_schools, request):
    sid = asyncio.run(_make_student(two_schools["a"]["id"], f"{PREFIX}_xp_race"))
    headers = auth(two_schools["a"]["admin_token"])
    body = {"student_id": sid, "amount": 10, "reason": "race"}

    assert _at_once("POST", "/api/xp/admin/adjust", headers, body, n=10) == [201] * 10

    total = asyncio.run(_fetchval("SELECT total_xp FROM student_xp WHERE student_id = $1", sid))
    ledger = asyncio.run(_fetchval("SELECT sum(amount) FROM xp_transactions WHERE student_id = $1", sid))
    assert ledger == 100
    assert total == 100


def test_the_owner_adding_the_same_admin_or_school_at_once_gets_conflicts(api, owner_token, two_schools):
    headers = auth(owner_token)
    statuses = _at_once("POST", f"/api/owner/schools/{two_schools['a']['id']}/admins", headers,
                        {"username": f"{PREFIX}_race_admin", "mpin": TEST_MPIN}, n=4)
    assert statuses == [201, 409, 409, 409], statuses
    statuses = _at_once("POST", "/api/owner/schools", headers,
                        {"name": f"ITest Race School {RUN_ID}", "slug": f"{PREFIX}-race-school"}, n=4)
    assert statuses == [201, 409, 409, 409], statuses
