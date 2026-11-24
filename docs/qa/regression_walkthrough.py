"""Regression walk-through of the real-user test plan on a throwaway school.

Usage: python3 regression.py <owner_token>
Prints one PASS/FAIL line per check and a JSON state dump at the end.
"""
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "http://localhost:8000/api"
RUN = time.strftime("%m%d%H%M")
SCHOOL = f"QA Regression {RUN}"
MPIN = "470381"
results = []
state = {}


def call(method, path, token=None, body=None, headers=None, raw=False):
    data = None
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    if headers:
        h.update(headers)
    if body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = r.read()
            hdrs = {k.lower(): v for k, v in r.headers.items()}
            if raw:
                return r.status, payload, hdrs
            return r.status, (json.loads(payload) if payload else None), hdrs
    except urllib.error.HTTPError as e:
        payload = e.read()
        hdrs = {k.lower(): v for k, v in e.headers.items()}
        try:
            payload = json.loads(payload)
        except Exception:
            pass
        return e.code, payload, hdrs


def check(case, name, ok, detail=""):
    results.append((case, name, bool(ok), detail))
    print(f"{'PASS' if ok else 'FAIL'}  {case:6} {name}" + (f"  — {detail}" if detail and not ok else ""))


def login(username, school_id):
    s, b, _ = call("POST", "/auth/login", body={"username": username, "mpin": MPIN, "school_id": school_id})
    return s, (b or {}).get("access_token") if isinstance(b, dict) else None


owner = sys.argv[1]
today = dt.date.today().isoformat()

# ── A. Owner opens a school ────────────────────────────────────────────────
s, b, _ = call("POST", "/owner/schools", owner, {"name": SCHOOL})
check("A-02", "owner creates school", s == 201, f"{s} {b}")
sid = b["id"]
state["school_id"] = sid
s, b2, _ = call("POST", "/owner/schools", owner, {"name": SCHOOL})
check("A-03", "duplicate school name refused", s == 409, f"{s}")
admin_name = f"qareg{RUN}_admin"
s, b, _ = call("POST", f"/owner/schools/{sid}/admins", owner, {"username": admin_name, "mpin": MPIN})
check("A-02", "owner adds school admin", s == 201, f"{s} {b}")

# ── B. Admin sets up ───────────────────────────────────────────────────────
s, admin = login(admin_name, sid)
check("B-01", "admin logs in with MPIN", s == 200 and admin, f"{s}")
s, b, _ = call("POST", "/auth/register", body={"username": f"qareg{RUN}_early", "mpin": MPIN, "role": "teacher",
                                              "school_id": sid, "phone": f"91{RUN}01", "teachable_subjects": ["Mathematics"]})
check("#1", "registration refused before a year exists", s == 409, f"{s} {b}")
s, b, _ = call("GET", "/admin/academic-years/current", admin)
check("B-03", "no current year yet", s == 200 and b is None, f"{s} {b}")
s, b, _ = call("POST", "/admin/academic-years/init", admin)
check("B-04", "admin starts the academic year", s == 201, f"{s} {b}")
year = (b or {}).get("year_label")
state["year"] = year
s, b, _ = call("PUT", "/admin/school/grades", admin, {"grades": [8, 9]})
check("#5", "admin sets grades taught 8,9", s == 200 and b.get("grades_offered") == [8, 9], f"{s} {b}")
s, b, _ = call("PUT", "/admin/timetable/config", admin, {"periods_per_day": 6, "enable_weekends": True})
check("B-06", "timetable config saved", s == 200, f"{s} {b}")
s, b, _ = call("POST", "/admin/fees/structure", admin, {"academic_year": year, "grade": 8, "base_amount": 40000, "computer_fee": 8000})
check("B-08", "grade 8 fee structure", s == 201, f"{s} {b}")
s, b, _ = call("POST", "/admin/fees/structure", admin, {"academic_year": year, "grade": 9, "base_amount": -5})
check("B-09", "negative fee refused", s == 422, f"{s}")
s, b, _ = call("PUT", "/admin/fees/payment-info/1", admin, {"label": "Main", "upi_id": "qa@upi", "bank_name": "QA Bank"})
check("B-10", "payment info saved", s == 200, f"{s} {b}")

# ── C. People join ─────────────────────────────────────────────────────────
t_name, s1, s2 = f"qareg{RUN}_t", f"qareg{RUN}_s1", f"qareg{RUN}_s2"
s, b, _ = call("POST", "/auth/register", body={"username": t_name, "mpin": MPIN, "role": "teacher", "school_id": sid,
                                              "phone": f"92{RUN}01", "teachable_subjects": ["Mathematics", "Physics"]})
check("C-01", "teacher registers", s == 201, f"{s} {b}")
s, b, _ = call("POST", "/auth/login", body={"username": t_name, "mpin": MPIN, "school_id": sid})
check("C-02", "unapproved teacher can't log in", s in (401, 403), f"{s} {b}")
for uname, par, phone, extra in [(s1, f"{s1}_p", f"93{RUN}01", ["computer"]), (s2, f"{s2}_p", f"93{RUN}02", [])]:
    s, b, _ = call("POST", "/auth/register", body={"username": uname, "mpin": MPIN, "role": "student", "school_id": sid,
                                                  "phone": phone, "grade": 8, "parent_username": par, "parent_mpin": "582914",
                                                  "additional_subjects": extra})
    check("C-03", f"student {uname} registers with parent", s == 201, f"{s} {b}")
s, b, _ = call("POST", "/auth/register", body={"username": f"qareg{RUN}_g10", "mpin": MPIN, "role": "student", "school_id": sid,
                                              "phone": f"93{RUN}03", "grade": 10, "parent_username": f"qareg{RUN}_g10p",
                                              "parent_mpin": "582914"})
check("#5", "grade-10 registration refused (school teaches 8,9)", s == 422, f"{s} {b}")
s, b, _ = call("POST", "/auth/register", body={"username": s1.upper(), "mpin": MPIN, "role": "student", "school_id": sid,
                                              "phone": f"93{RUN}04", "grade": 8, "parent_username": f"{s1}_p2",
                                              "parent_mpin": "582914"})
check("J-03", "case-variant username refused", s == 409, f"{s} {b}")
s, pending, _ = call("GET", "/admin/users/pending", admin)
names = {u["username"]: u["id"] for u in (pending or [])}
check("C-07", "pending list has teacher, 2 students, 2 parents",
      all(n in names for n in [t_name, s1, s2, f"{s1}_p", f"{s2}_p"]), f"{sorted(names)}")
for n, uid in names.items():
    s, _, _ = call("POST", f"/admin/users/{uid}/approve", admin)
    check("C-09", f"approve {n}", s == 200, f"{s}")
state["ids"] = names

s, teacher = login(t_name, sid)
s_, stu1 = login(s1, sid)
s__, stu2 = login(s2, sid)
s___, par1 = call("POST", "/auth/login", body={"username": f"{s1}_p", "mpin": "582914", "school_id": sid})[0:2]
par1 = (par1 or {}).get("access_token") if isinstance(par1, dict) else None
check("C-10", "teacher, students and parent log in", all([teacher, stu1, stu2, par1]), f"{s} {s_} {s__} {s___}")

# ── D. A school day ────────────────────────────────────────────────────────
for p, subj in [(1, "Mathematics"), (2, "Physics")]:
    s, b, _ = call("POST", "/teacher/timetable", teacher, {"grade": 8, "slot_date": today, "period_number": p, "subject": subj,
                                                           "teacher_id": names[t_name], "is_holiday": False,
                                                           "expected": {"exists": False}})
    check("B-06", f"timetable P{p} saved", s == 200, f"{s} {b}")
s, b, _ = call("POST", "/teacher/timetable", teacher, {"grade": 8, "slot_date": today, "period_number": 1, "subject": "History & Civics",
                                                       "is_holiday": False, "expected": {"exists": False}})
check("#39", "stale timetable save refused", s == 409 and b["detail"]["code"] == "timetable_slot_changed", f"{s} {b}")
s, b, _ = call("POST", "/teacher/attendance", teacher, {"grade": 8, "period": 1, "date": today, "records": [
    {"student_id": names[s1], "grade": 8, "period": 1, "date": today, "status": "present"},
    {"student_id": names[s2], "grade": 8, "period": 1, "date": today, "status": "absent"}]})
check("D-02", "P1 attendance saved", s == 201, f"{s} {b}")
s, b, _ = call("GET", "/teacher/today-workflow", teacher)
g8 = next((g for g in (b or {}).get("grades", []) if g.get("grade") == 8), None) if isinstance(b, dict) else None
check("#4", "road shows partial attendance 1/2", g8 is not None and g8.get("attendance_progress") == "1/2", f"{s} {g8}")
s, hw, _ = call("POST", "/teacher/homework", teacher, {"grade": 8, "subject": "Mathematics", "title": "QA Ex 4.2 Q1-10"})
check("D-04", "homework assigned", s == 201, f"{s} {hw}")
s, b, _ = call("POST", "/teacher/homework", teacher, {"grade": 8, "subject": "Mathematics", "title": "x" * 301})
check("H-05", "301-char homework title refused", s == 422, f"{s}")
s, bc, _ = call("POST", "/teacher/broadcast", teacher, {"title": "QA Unit test Friday", "message": "Revise ch 4", "target_type": "grade", "target_grade": 8})
check("D-07", "grade-8 broadcast sent", s == 201, f"{s} {bc}")
for sname, mk in [(s1, 18), (s2, 11)]:
    s, b, _ = call("POST", "/teacher/grades", teacher, {"student_id": names[sname], "subject": "Mathematics", "chapter": "Linear Equations",
                                                        "marks_obtained": mk, "max_marks": 20})
    check("D-11", f"offline marks for {sname}", s == 201, f"{s} {b}")

# ── E/F. Student and parent see it ─────────────────────────────────────────
s, b, _ = call("GET", f"/student/dashboard-summary?date={today}", stu1)
tt = (b or {}).get("timetable") if isinstance(b, dict) else None
check("E-01", "student dashboard has today's periods", s == 200 and tt and len(tt) == 2, f"{s} {str(b)[:200]}")
s, b, _ = call("GET", "/student/broadcasts", stu1)
check("E-02", "student sees the broadcast", s == 200 and any(x.get("title") == "QA Unit test Friday" for x in b), f"{s}")
s, b, _ = call("GET", "/student/grades", stu1)
check("E-07", "student sees marks with class high/low",
      s == 200 and b and b[0].get("class_high") == 90.0 and b[0].get("class_low") == 55.0, f"{s} {str(b)[:300]}")
s, b, _ = call("GET", "/student/fees", stu1)
check("E-07", "student fee is base + computer = 48,000", s == 200 and float(b.get("total_fee", 0)) == 48000, f"{s} {str(b)[:200]}")
s, b, _ = call("GET", "/parent/children", par1)
check("F-01", "parent sees their child", s == 200 and any(c.get("username") == s1 for c in (b or [])), f"{s} {b}")

# ── Fees ───────────────────────────────────────────────────────────────────
key = str(uuid.uuid4())
s, p1, _ = call("POST", "/admin/fees/payments", admin, {"student_id": names[s1], "amount": 20000}, {"X-Idempotency-Key": key})
s2_, p2, _ = call("POST", "/admin/fees/payments", admin, {"student_id": names[s1], "amount": 20000}, {"X-Idempotency-Key": key})
check("F-03", "payment recorded", s == 201, f"{s} {p1}")
check("J-08", "same idempotency key doesn't double-charge", s2_ != 201 or (isinstance(p2, dict) and p2.get("id") == p1.get("id")), f"{s2_} {p2}")
s, b, _ = call("POST", "/admin/fees/payments", admin, {"student_id": names[s1], "amount": 30000})
check("J-11", "over-balance payment refused", s in (400, 409, 422), f"{s} {b}")
s, b, _ = call("GET", "/parent/fees", par1)
check("F-02", "parent sees balance 28,000", s == 200 and float(b.get("balance_due", -1)) == 28000, f"{s} {str(b)[:200]}")

# ── I. Reports and warnings ────────────────────────────────────────────────
for kind in ["attendance", "marks"]:
    s, body, _ = call("GET", f"/admin/reports/{kind}?grade=8", admin, raw=True)
    check("#28", f"{kind} report PDF", s == 200 and body[:5] == b"%PDF-", f"{s} {body[:80]}")
s, body, _ = call("GET", f"/admin/reports/pending-fees?academic_year={year}", admin, raw=True)
check("I-01", "pending-fees PDF", s == 200 and body[:5] == b"%PDF-", f"{s}")
s, b, _ = call("GET", "/admin/academic-years/current", admin)
check("J-25", "close-year warning data (2 unpaid, 68,000)",
      s == 200 and b.get("unpaid_students") == 2 and float(b.get("unpaid_total")) == 68000.0, f"{s} {b}")
state["next_year"] = (b or {}).get("next_year_label")

# ── H-04. Suspension ───────────────────────────────────────────────────────
s, b, _ = call("PATCH", f"/owner/schools/{sid}", owner, {"is_active": False})
check("H-04", "owner suspends school", s == 200, f"{s} {b}")
s, b, h = call("GET", "/student/grades", stu1)
check("#26", "suspended student gets 403 + X-Session-Ended", s == 403 and h.get("x-session-ended") == "school_suspended", f"{s} {h.get('x-session-ended')}")
s, b, _ = call("PATCH", f"/owner/schools/{sid}", owner, {"is_active": True})
check("H-04", "owner re-activates school", s == 200, f"{s}")
time.sleep(1)

# ── I-03. Close year ───────────────────────────────────────────────────────
s, b, _ = call("POST", "/admin/academic-years/new", admin)
check("I-03", "close year starts the next label", s == 201 and b.get("year_label") == state["next_year"], f"{s} {b} expected {state['next_year']}")
s, b, _ = call("GET", "/student/grades", stu1)
check("I-03", "removed student's session no longer works", s in (401, 403), f"{s}")
s, b, _ = call("GET", "/admin/users", admin)
check("I-03", "only the admin remains", s == 200 and all(u.get("role") == "admin" for u in b), f"{s} {[u.get('username') for u in (b or [])]}")

print()
fails = [r for r in results if not r[2]]
print(f"{len(results) - len(fails)} passed, {len(fails)} failed")
print("STATE " + json.dumps(state))
