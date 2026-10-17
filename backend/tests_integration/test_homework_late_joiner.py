"""
A student who joins mid-year is not on the roster of homework set before they came.

The review roster was "every student in the grade now", so a student approved
today was on yesterday's homework, and the teacher could not assign anything new
until they recorded whether the newcomer had done homework they never received —
in practice by marking them "not done", which their parent then sees. Found
2026-10-17. The roster is now the students whose account existed when the
homework was set.
"""

import asyncio

import asyncpg
import pytest

from .conftest import DB_DSN, PREFIX, RUN_ID, TEST_MPIN, _make_student, auth, login, register


async def _sql(query, *args):
    conn = await asyncpg.connect(DB_DSN)
    try:
        return await conn.fetchval(query, *args)
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def class_with_newcomer(api, owner_token):
    r = api.post("/api/owner/schools", headers=auth(owner_token),
                 json={"name": f"ITest Late {RUN_ID}", "slug": f"{PREFIX}-late"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    admin_name = f"{PREFIX}_admin_late"
    api.post(f"/api/owner/schools/{sid}/admins", headers=auth(owner_token),
             json={"username": admin_name, "mpin": TEST_MPIN})
    admin = auth(login(api, admin_name, school_id=sid))
    assert api.post("/api/admin/academic-years/init", headers=admin).status_code == 201
    asyncio.run(_sql("UPDATE academic_years SET started_at = now() - interval '30 days' "
                     "WHERE school_id = $1", sid))

    teacher_name = f"{PREFIX}_late_t"
    assert register(api, username=teacher_name, mpin=TEST_MPIN, role="teacher", school_id=sid,
                    phone=f"84{RUN_ID[:5].translate(str.maketrans('abcdef', '123456'))}11").status_code == 201
    for u in api.get("/api/admin/users/pending", headers=admin).json():
        api.post(f"/api/admin/users/{u['id']}/approve", headers=admin)
    teacher = auth(login(api, teacher_name, school_id=sid))

    regular = asyncio.run(_make_student(sid, f"{PREFIX}_late_regular"))
    asyncio.run(_sql("UPDATE users SET created_at = now() - interval '10 days' WHERE id = $1", regular))
    hw = api.post("/api/teacher/homework", headers=teacher,
                  json={"grade": 8, "subject": "maths", "title": "Set before the newcomer"})
    assert hw.status_code == 201, hw.text
    asyncio.run(_sql("UPDATE homework SET created_at = now() - interval '1 day' WHERE id = $1",
                     hw.json()["id"]))
    newcomer = asyncio.run(_make_student(sid, f"{PREFIX}_late_newcomer", new=True))
    return {"teacher": teacher, "hw": hw.json()["id"], "regular": regular, "newcomer": newcomer}


def test_the_newcomer_is_not_on_the_roster(api, class_with_newcomer):
    c = class_with_newcomer
    r = api.get(f"/api/teacher/homework/{c['hw']}/completions", headers=c["teacher"])
    assert r.status_code == 200, r.text
    ids = {s["student_id"] for s in r.json()["students"]}
    assert ids == {c["regular"]}


def test_reviewing_the_class_that_had_it_unblocks_new_homework(api, class_with_newcomer):
    c = class_with_newcomer
    r = api.put(f"/api/teacher/homework/{c['hw']}/completions", headers=c["teacher"],
                json={"records": [{"student_id": c["regular"], "completed": True}]})
    assert r.status_code == 200, r.text
    r = api.get("/api/teacher/today-workflow", headers=c["teacher"])
    assert r.json()["grades"][0]["pending_review_homework_ids"] == []
    r = api.post("/api/teacher/homework", headers=c["teacher"],
                 json={"grade": 8, "subject": "maths", "title": "Today's"})
    assert r.status_code == 201, r.text
