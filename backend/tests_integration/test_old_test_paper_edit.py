"""Setting an old test paper's details by hand (PATCH /old-tests/{id}).

For papers the AI couldn't classify — without a grade and subject, test
generation never uses them.
"""

from .conftest import PREFIX, auth

PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"
URL = "/api/teacher/database/old-tests"


def _upload(api, token, name):
    r = api.post(f"{URL}/upload", headers=auth(token),
                 files=[("files", (f"{PREFIX}_{name}.pdf", PDF, "application/pdf"))])
    assert r.status_code == 200, r.text
    return r.json()[0]["id"]


def _listed(api, token, paper_id):
    return next(p for p in api.get(URL, headers=auth(token)).json() if p["id"] == paper_id)


def test_teacher_sets_details_and_generation_filter_finds_it(api, two_schools):
    token = two_schools["a"]["teacher_token"]
    pid = _upload(api, token, "edit_ok")

    r = api.patch(f"{URL}/{pid}", headers=auth(token),
                  json={"grade": 9, "subject": "Chemistry", "chapter": "Acids, Bases and Salts"})

    assert r.status_code == 200, r.text
    assert (r.json()["grade"], r.json()["subject"]) == (9, "Chemistry")
    # The same exact-match filter test generation uses.
    found = api.get(URL, headers=auth(token), params={"grade": 9, "subject": "Chemistry"}).json()
    assert pid in [p["id"] for p in found]


def test_chapter_is_optional_and_blank_clears_it(api, two_schools):
    token = two_schools["a"]["teacher_token"]
    pid = _upload(api, token, "edit_chapter")
    r = api.patch(f"{URL}/{pid}", headers=auth(token),
                  json={"grade": 8, "subject": "Physics", "chapter": "   "})
    assert r.status_code == 200, r.text
    assert r.json()["chapter"] is None


def test_rejects_values_generation_could_never_match(api, two_schools):
    token = two_schools["a"]["teacher_token"]
    pid = _upload(api, token, "edit_bad")
    for body in (
        {"grade": 11, "subject": "Physics"},
        {"grade": 8, "subject": "Math"},
        {"grade": 8, "subject": "physics"},
        {"subject": "Physics"},
        {"grade": 8},
        {"grade": 8, "subject": "Physics", "chapter": "x" * 201},
    ):
        r = api.patch(f"{URL}/{pid}", headers=auth(token), json=body)
        assert r.status_code == 422, f"{body} -> {r.status_code} {r.text}"
    assert _listed(api, token, pid)["grade"] is None


def test_other_schools_teacher_cannot_edit(api, two_schools):
    pid = _upload(api, two_schools["a"]["teacher_token"], "edit_cross")
    r = api.patch(f"{URL}/{pid}", headers=auth(two_schools["b"]["teacher_token"]),
                  json={"grade": 8, "subject": "Physics"})
    assert r.status_code == 404, r.text
    assert _listed(api, two_schools["a"]["teacher_token"], pid)["subject"] is None


def test_admin_cannot_edit(api, two_schools):
    """Old papers are a teacher's own reference material."""
    pid = _upload(api, two_schools["a"]["teacher_token"], "edit_role")
    r = api.patch(f"{URL}/{pid}", headers=auth(two_schools["a"]["admin_token"]),
                  json={"grade": 8, "subject": "Physics"})
    assert r.status_code == 403, r.text
