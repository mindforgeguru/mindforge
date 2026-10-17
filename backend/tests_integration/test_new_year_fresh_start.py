"""
After Close Year, the new year starts empty for the people in it.

Closing the year removes every student, teacher and parent and asks them to
register again; the timetable is cleared. Homework, announcements and tests were
not, and nothing asked which year they belonged to. Found on 2026-10-17:

- a teacher registering on the first day of the new year could not assign
  homework: the review gate wanted completion marks, from this year's students,
  for last year's last homework (409 homework_review_pending);
- a new student saw last year's homework, last year's notices and last year's
  still-open test, and could take it.

They stay in the database (Previous Years); they no longer reach the new year.
"""

import asyncio
import json

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login, register
from .test_realtime_delivery import _mint_access_token

QUESTIONS = [{"id": 1, "type": "mcq", "marks": 1, "answer": "A", "question": "Pick A",
              "options": {"A": "Right", "B": "Wrong", "C": "Wrong", "D": "Wrong"}}]


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


def _approve_all(api, admin):
    for u in api.get("/api/admin/users/pending", headers=admin).json():
        api.post(f"/api/admin/users/{u['id']}/approve", headers=admin)


@pytest.fixture(scope="module")
def new_year(api, owner_token):
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest New Year {RUN_ID}", "slug": f"{PREFIX}-newyear"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin_name = f"{PREFIX}_admin_ny"
    api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
             json={"username": admin_name, "mpin": TEST_MPIN})
    admin = auth(login(api, admin_name, school_id=sid))
    assert api.post("/api/admin/academic-years/init", headers=admin).status_code == 201

    # Last year: a teacher, a pupil, homework from yesterday, a notice, an open test.
    old_t = f"{PREFIX}_ny_old_t"
    assert register(api, username=old_t, mpin=TEST_MPIN, role="teacher", school_id=sid,
                    phone=f"86{RUN_ID[:5].translate(str.maketrans('abcdef', '123456'))}11").status_code == 201
    _approve_all(api, admin)
    old_teacher = auth(login(api, old_t, school_id=sid))
    asyncio.run(_make_student(sid, f"{PREFIX}_ny_old_s"))
    hw = api.post("/api/teacher/homework", headers=old_teacher,
                  json={"grade": 8, "subject": "maths", "title": "Last year's homework"})
    assert hw.status_code == 201, hw.text
    asyncio.run(_sql("UPDATE homework SET created_at = now() - interval '1 day' WHERE id = $1",
                     hw.json()["id"]))
    assert api.post("/api/teacher/broadcast", headers=old_teacher,
                    json={"title": "Last year's notice", "message": "old"}).status_code == 201
    teacher_id = asyncio.run(_sql("SELECT id FROM users WHERE username = $1", old_t))
    asyncio.run(_sql(
        """INSERT INTO tests (title, teacher_id, grade, subject, test_type, questions, total_marks,
                              time_limit_minutes, is_published, expires_at, school_id)
           VALUES ('Last year''s open test', $1, 8, 'maths', 'online', $2::json, 1, 10, true,
                   now() + interval '30 days', $3)""",
        teacher_id, json.dumps(QUESTIONS), sid))

    assert api.post("/api/admin/academic-years/new", headers=admin).status_code == 201

    # This year: a new teacher and a new pupil.
    new_t = f"{PREFIX}_ny_new_t"
    assert register(api, username=new_t, mpin=TEST_MPIN, role="teacher", school_id=sid,
                    phone=f"86{RUN_ID[:5].translate(str.maketrans('abcdef', '123456'))}22").status_code == 201
    _approve_all(api, admin)
    student = asyncio.run(_make_student(sid, f"{PREFIX}_ny_new_s", new=True))
    parent = asyncio.run(_sql(
        """INSERT INTO users (username, mpin_hash, role, school_id, is_active, is_approved)
           VALUES ($1, 'x', 'parent', $2, true, true) RETURNING id""", f"{PREFIX}_ny_new_p", sid))
    asyncio.run(_sql("UPDATE student_profiles SET parent_user_id = $1 WHERE user_id = $2", parent, student))
    return {"teacher": auth(login(api, new_t, school_id=sid)),
            "student": auth(_mint_access_token(student)),
            "parent": auth(_mint_access_token(parent))}


def test_the_new_teacher_can_assign_homework(api, new_year):
    r = api.get("/api/teacher/today-workflow", headers=new_year["teacher"])
    assert r.status_code == 200
    assert r.json()["grades"][0]["pending_review_homework_ids"] == []
    r = api.post("/api/teacher/homework", headers=new_year["teacher"],
                 json={"grade": 8, "subject": "maths", "title": "First homework of the year"})
    assert r.status_code == 201, r.text


@pytest.mark.parametrize("path", ["/api/student/homework", "/api/student/broadcasts",
                                  "/api/student/tests/pending"])
def test_the_new_student_sees_nothing_from_last_year(api, new_year, path):
    r = api.get(path, headers=new_year["student"])
    assert r.status_code == 200, r.text
    titles = {item.get("title") for item in r.json()}
    assert not any(t and t.startswith("Last year") for t in titles), titles


def test_nor_on_the_dashboard(api, new_year):
    r = api.get("/api/student/dashboard-summary", headers=new_year["student"])
    assert r.status_code == 200, r.text
    text = json.dumps(r.json())
    assert "Last year" not in text


@pytest.mark.parametrize("path", ["/api/parent/child/homework", "/api/parent/broadcasts",
                                  "/api/parent/child/tests", "/api/parent/dashboard-summary"])
def test_nor_does_their_parent(api, new_year, path):
    r = api.get(path, headers=new_year["parent"])
    assert r.status_code == 200, r.text
    assert "Last year" not in json.dumps(r.json())
