"""
Out-of-range input is a validation error, not a server error.

Most request schemas carried no length or range limits, so an over-long title,
a fee of a billion, or marks above the maximum went straight to Postgres, which
refused it (VARCHAR length, NUMERIC precision, a CHECK constraint) and the user
saw "Internal server error". A JSON `NaN` failed the same way, in the audit
row. Each case here was a 500 on 2026-10-16.

The rest were accepted and should not have been: a negative or zero fee
payment, a negative fee, a blank homework title, an empty broadcast.
"""

import pytest

from .conftest import auth

X = lambda n: "x" * n  # noqa: E731


def _teacher_cases(student_id):
    return [
        ("timetable comment", "/api/teacher/timetable",
         {"grade": 8, "slot_date": "2026-10-16", "period_number": 1, "subject": "maths", "comment": X(301)}),
        ("timetable subject", "/api/teacher/timetable",
         {"grade": 8, "slot_date": "2026-10-16", "period_number": 1, "subject": X(101)}),
        ("timetable grade", "/api/teacher/timetable",
         {"grade": 99, "slot_date": "2026-10-16", "period_number": 1, "subject": "maths"}),
        ("grade chapter", "/api/teacher/grades",
         {"student_id": student_id, "subject": "maths", "chapter": X(201), "marks_obtained": 5, "max_marks": 10}),
        ("grade marks overflow", "/api/teacher/grades",
         {"student_id": student_id, "subject": "maths", "chapter": "c", "marks_obtained": 10000, "max_marks": 10000}),
        ("grade above max", "/api/teacher/grades",
         {"student_id": student_id, "subject": "maths", "chapter": "c", "marks_obtained": 50, "max_marks": 10}),
        ("grade max zero", "/api/teacher/grades",
         {"student_id": student_id, "subject": "maths", "chapter": "c", "marks_obtained": 0, "max_marks": 0}),
        ("homework title", "/api/teacher/homework", {"grade": 8, "subject": "maths", "title": X(301)}),
        ("homework description", "/api/teacher/homework",
         {"grade": 8, "subject": "maths", "title": "t", "description": X(2001)}),
        ("homework blank title", "/api/teacher/homework", {"grade": 8, "subject": "maths", "title": "   "}),
        ("broadcast title", "/api/teacher/broadcast", {"title": X(201), "message": "m"}),
        ("broadcast message", "/api/teacher/broadcast", {"title": "t", "message": X(2001)}),
        ("broadcast target", "/api/teacher/broadcast", {"title": "t", "message": "m", "target_type": X(21)}),
        ("broadcast empty", "/api/teacher/broadcast", {"title": " ", "message": ""}),
        # Stored with no grade, it reached nobody while the teacher saw "sent".
        ("broadcast grade without grade", "/api/teacher/broadcast",
         {"title": "t", "message": "m", "target_type": "grade"}),
    ]


def _admin_cases(student_id):
    return [
        ("POST", "payment negative", "/api/admin/fees/payments", {"student_id": student_id, "amount": -5000}),
        ("POST", "payment zero", "/api/admin/fees/payments", {"student_id": student_id, "amount": 0}),
        ("POST", "payment overflow", "/api/admin/fees/payments", {"student_id": student_id, "amount": 1e9}),
        ("POST", "payment notes", "/api/admin/fees/payments",
         {"student_id": student_id, "amount": 1, "notes": X(5001)}),
        ("POST", "structure year", "/api/admin/fees/structure", {"academic_year": X(21), "grade": 8, "base_amount": 1}),
        ("POST", "structure negative", "/api/admin/fees/structure",
         {"academic_year": "2031-32", "grade": 8, "base_amount": -100}),
        ("POST", "structure grade", "/api/admin/fees/structure",
         {"academic_year": "2032-33", "grade": 99, "base_amount": 1}),
        ("POST", "structure overflow", "/api/admin/fees/structure",
         {"academic_year": "2033-34", "grade": 8, "base_amount": 1e9}),
        ("PUT", "payment info label", "/api/admin/fees/payment-info/1", {"label": X(101)}),
        ("PUT", "payment info ifsc", "/api/admin/fees/payment-info/1", {"ifsc": X(21)}),
        ("PUT", "payment info account", "/api/admin/fees/payment-info/1", {"account_number": X(51)}),
        ("PUT", "user phone", f"/api/admin/users/{student_id}", {"phone": "9" * 21}),
        ("PUT", "user email", f"/api/admin/users/{student_id}", {"email": X(290) + "@a.com"}),
    ]


@pytest.fixture(scope="module")
def school_a(two_schools, students):
    return two_schools["a"], students["a"]


@pytest.mark.parametrize("idx", range(len(_teacher_cases(0))), ids=[c[0] for c in _teacher_cases(0)])
def test_teacher_input_out_of_range_is_422(api, school_a, idx):
    school, student_id = school_a
    name, path, body = _teacher_cases(student_id)[idx]
    r = api.post(path, headers=auth(school["teacher_token"]), json=body)
    assert r.status_code == 422, f"{name}: {r.status_code} {r.text[:200]}"


@pytest.mark.parametrize("idx", range(len(_admin_cases(0))), ids=[c[1] for c in _admin_cases(0)])
def test_admin_input_out_of_range_is_422(api, school_a, idx):
    school, student_id = school_a
    method, name, path, body = _admin_cases(student_id)[idx]
    r = api.request(method, path, headers=auth(school["admin_token"]), json=body)
    assert r.status_code == 422, f"{name}: {r.status_code} {r.text[:200]}"


@pytest.mark.parametrize("token", ["NaN", "Infinity", "-Infinity"])
def test_a_non_finite_fee_is_422(api, school_a, token):
    school, student_id = school_a
    r = api.post(
        "/api/admin/fees/payments",
        headers={**auth(school["admin_token"]), "Content-Type": "application/json"},
        content='{"student_id": %d, "amount": %s}' % (student_id, token),
    )
    assert r.status_code == 422, f"{r.status_code} {r.text[:200]}"


@pytest.mark.parametrize("field,value", [
    ("address", X(501)), ("contact_phone", "9" * 21),
    ("contact_email", X(250) + "@a.com"), ("subscription_plan", X(51)),
])
def test_owner_school_fields_out_of_range_are_422(api, owner_token, two_schools, field, value):
    r = api.patch(
        f"/api/owner/schools/{two_schools['a']['id']}",
        headers=auth(owner_token), json={field: value},
    )
    assert r.status_code == 422, f"{field}: {r.status_code} {r.text[:200]}"


def test_in_range_values_are_still_accepted(api, school_a):
    school, student_id = school_a
    admin = auth(school["admin_token"])
    r = api.post("/api/admin/fees/payments", headers=admin,
                 json={"student_id": student_id, "amount": 99_999_999.99, "notes": X(1000)})
    assert r.status_code == 201, r.text
    assert api.delete(f"/api/admin/fees/payments/{r.json()['id']}", headers=admin).status_code == 204

    r = api.post("/api/teacher/homework", headers=auth(school["teacher_token"]),
                 json={"grade": 8, "subject": "maths", "title": X(300), "description": X(2000)})
    assert r.status_code == 201, r.text


@pytest.mark.parametrize("path,params", [
    ("/api/teacher/attendance/dates", {"grade": 8, "month": "10"}),
    ("/api/teacher/attendance/dates", {"grade": 8, "month": "2026-13"}),
    ("/api/teacher/attendance", {"grade": 8, "date": "2026-02-30"}),
    ("/api/teacher/attendance", {"grade": 8, "date": "yesterday"}),
    ("/api/teacher/timetable", {"grade": 8, "date": "16/10/2026"}),
], ids=["month without year", "month 13", "30 February", "a word", "timetable day-first"])
def test_a_malformed_date_filter_is_422(api, school_a, path, params):
    # Parsed by hand with int()/fromisoformat(); a bad value raised inside the
    # handler and came back as a 500. Eight handlers did this; now one helper
    # (school_time.parse_iso_date) answers 422.
    school, _ = school_a
    r = api.get(path, headers=auth(school["teacher_token"]), params=params)
    assert r.status_code == 422, f"{r.status_code} {r.text[:200]}"


# ── Test answers ─────────────────────────────────────────────────────────────
# `answers` was an unbounded Dict[str, Any]: one autosave stored 5 MB, another
# 10,000 made-up question ids, and the app autosaves every 20 seconds.

@pytest.fixture(scope="module")
def answering(two_schools, students):
    import asyncio
    import json

    import asyncpg

    from .conftest import DB_DSN, PREFIX
    from .test_realtime_delivery import _mint_access_token

    school = two_schools["a"]
    questions = [{"id": 1, "type": "long_answer", "marks": 5, "answer": "x", "question": "Explain"}]

    async def make():
        conn = await asyncpg.connect(DB_DSN)
        try:
            return [await conn.fetchval(
                """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions,
                                      total_marks, time_limit_minutes, is_published, expires_at, school_id)
                   VALUES ($1, $2, 8, 'english', 'online', $3::json, 5, 10, true,
                           now() + interval '1 day', $4) RETURNING id""",
                f"{PREFIX} answers {i}", school["teacher_id"], json.dumps(questions), school["id"],
            ) for i in range(2)]
        finally:
            await conn.close()

    return asyncio.run(make()), auth(_mint_access_token(students["a"]))


@pytest.mark.parametrize("answers", [
    {"1": "x" * 5001},
    {str(i): "A" for i in range(201)},
    {"x" * 21: "A"},
    {"1": {"nested": "object"}},
], ids=["huge answer", "too many answers", "long question id", "not text"])
def test_out_of_range_answers_are_422(api, answering, answers):
    (test_id, _), headers = answering
    api.post(f"/api/student/tests/{test_id}/start", headers=headers)
    for path in ("save", "submit"):
        r = api.post(f"/api/student/tests/{test_id}/{path}", headers=headers, json={"answers": answers})
        assert r.status_code == 422, f"{path}: {r.status_code} {r.text[:200]}"


def test_a_long_essay_answer_is_still_accepted(api, answering):
    (_, test_id), headers = answering
    api.post(f"/api/student/tests/{test_id}/start", headers=headers)
    r = api.post(f"/api/student/tests/{test_id}/submit", headers=headers,
                 json={"answers": {"1": "word " * 1000}})
    assert r.status_code == 201, r.text


# ── Attendance ───────────────────────────────────────────────────────────────
# Only the school was checked: a grade-10 student could be filed (and given XP)
# under a grade-8 period, or a removed student marked, and grade and period were
# any integer.

def _school_today():
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.now(ZoneInfo("Asia/Kolkata")).date().isoformat()


@pytest.mark.parametrize("case", ["wrong grade", "removed student", "period 99", "grade 11"])
def test_attendance_only_for_the_class_and_period(api, two_schools, case):
    import asyncio

    import asyncpg

    from .conftest import DB_DSN, PREFIX, _make_student

    school = two_schools["a"]
    grade, period = 8, 6
    student = asyncio.run(_make_student(school["id"], f"{PREFIX}_att_{case.replace(' ', '_')}",
                                        grade=9 if case == "wrong grade" else 8, new=True))
    if case == "removed student":
        async def remove():
            conn = await asyncpg.connect(DB_DSN)
            try:
                await conn.execute("UPDATE users SET deleted_at = now(), is_active = false "
                                   "WHERE id = $1", student)
            finally:
                await conn.close()
        asyncio.run(remove())
    if case == "period 99":
        period = 99
    if case == "grade 11":
        grade = 11
    r = api.post("/api/teacher/attendance", headers=auth(school["teacher_token"]), json={
        "grade": grade, "period": period, "date": _school_today(),
        "records": [{"student_id": student, "grade": grade, "period": period,
                     "date": _school_today(), "status": "present"}],
    })
    assert r.status_code in (404, 422), f"{case}: {r.status_code} {r.text[:200]}"


def test_attendance_for_a_period_past_the_days_count_is_refused(api, two_schools):
    # The school's day has `periods_per_day` periods; period 12 of it was
    # accepted (and earned XP) whatever the day's length.
    import asyncio

    import asyncpg

    from .conftest import DB_DSN, PREFIX, _make_student

    school = two_schools["a"]
    student = asyncio.run(_make_student(school["id"], f"{PREFIX}_att_p12", new=True))

    async def periods():
        conn = await asyncpg.connect(DB_DSN)
        try:
            return await conn.fetchval(
                "SELECT periods_per_day FROM timetable_configs WHERE school_id = $1 "
                "ORDER BY id DESC LIMIT 1", school["id"])
        finally:
            await conn.close()

    per_day = asyncio.run(periods()) or 8
    if per_day >= 12:
        pytest.skip("this school's day already has 12 periods")
    r = api.post("/api/teacher/attendance", headers=auth(school["teacher_token"]), json={
        "grade": 8, "period": 12, "date": _school_today(),
        "records": [{"student_id": student, "grade": 8, "period": 12,
                     "date": _school_today(), "status": "present"}],
    })
    assert r.status_code == 422, r.text
