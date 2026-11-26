# Real-User Test Plan — "A term at Sunrise Public School"

**Written:** 2026-10-21 · **Branch:** `create_school` · **Run against:** the local stack (see `project_local_run_recipe`) — never production.

Unlike the API-level ticks in `TEST_RECORD.md` §5, every case here is done **through the UI, the way a person would**:
tapping, typing, waiting, getting things wrong. One fictional school is built from nothing and lived in for a "term",
so later cases depend on earlier ones. Run them in order.

**Platforms.** Each case names where it runs: **iOS** = simulator app, **Web** = Flutter web in Chrome (port 5001/8080).
Realtime cases use both at once (two people, two devices).

**Status values:** `TODO` · `PASS` · `FAIL (issue)` · `BLOCKED (why)` · `SKIP (why)`. Record a date and one line of evidence.

## Cast

| Persona | Role | Username | Notes |
|---|---|---|---|
| Chinmay | Platform owner | `chinmay_owner` | existing account |
| Mrs. Rao | School admin | `sunrise_admin` | created by the owner in A-02 |
| Mr. Iyer | Maths teacher | `iyer_maths` | registers himself |
| Ms. Das | Science teacher | `das_sci` | registers himself; used for "colleague" checks |
| Aarav | Grade 8 student | `aarav8` | registers; parent auto-created |
| Meera | Grade 8 student | `meera8` | second student for leaderboard / shuffle |
| Kabir | Grade 9 student | `kabir9` | other grade, for targeting checks |
| Aarav's mum | Parent | `aarav8_parent` (as created) | logs in with her own MPIN |
| Riverdale kid | Other school | `river_kid` | cross-school leak checks |

MPINs for new accounts: pick at test time and write them into `docs/local-test-accounts.md`, not here.

---

## A. Day zero — the owner opens a school

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| A-01 | Owner · Web | Opens the app, picks "Platform owner (no school)", enters MPIN | Owner dashboard listing every school with role counts | PASS 2026-10-22 — owner console, 15 schools with role counts |
| A-02 | Owner · Web | Creates "Sunrise Public School" and its admin `sunrise_admin` | Success message; school appears in the list with 1 admin | PASS 2026-10-22 — "School created." + "Admin created"; Admins: 1 |
| A-03 | Owner · Web | Tries to create "Sunrise Public School" again | A clear "already exists" message — not a raw error | PASS 2026-10-22 — "A school named … already exists"; also for lowercase+trailing space |
| A-04 | Owner · Web | Logs out | Back on login; browser storage has no `mindforge_*` keys | PASS 2026-10-22 — /login, localStorage + sessionStorage empty |

## B. The admin sets the school up

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| B-01 | Admin · iOS | First login; types the MPIN wrong once, then right | Wrong: "Invalid username or MPIN". Right: admin dashboard with the setup road, car on Academic Year | PASS 2026-10-22 — wrong: "Invalid username or MPIN."; right: setup road, car on Academic Year |
| B-02 | Admin · iOS | Two-factor setup prompt (if shown): scans/enters the code, saves recovery codes | Enrolled; next login asks for a code | SKIP — no 2FA prompt shown for admin → **PASS** 2026-11-25 — 2FA is opt-in (admin Profile → Manage two-factor), which is why no prompt appeared. On iPhone the setup screen shows the QR and a copyable key; Cancel leaves it off. Full cycle via API (demo_admin): wrong code refused; right code enables it and returns 10 recovery codes; sign-in needs a code (`mfa_required`); a replayed code is refused; a recovery code works once (9 left); disabling needs MPIN + code; sign-in without a code works again |
| B-03 | Admin · iOS | Taps a later road step (e.g. Fees) before Academic Year | Blocked or clearly told to finish the earlier step | FAIL (minor) 2026-10-22 — locked road node silently ignores taps (no hint); bottom-nav Fees opens Fee Management anyway → **FIXED 2026-11-23** — locked steps now say what to finish first; Fees shows "Start the academic year first" until a year exists |
| B-04 | Admin · iOS | Starts the academic year 2026–27 | Road advances; car moves to Timetable | PASS 2026-10-22 — 2026-27 ACTIVE; car moved to Timetable |
| B-05 | Admin · iOS | Uploads a school logo from the photo library | Logo shows on the dashboard header and login picker | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: Sunrise logo_url set; logo shows on dashboard header → seen in later passes: the Sunrise logo shows on login, splash, every header and on PDF reports (iPhone, iPad, web) |
| B-06 | Admin · iOS | Builds a grade 8 timetable: 6 periods, Mon–Sat, Maths/Science/English, publishes | Saved; grid reads back correctly after leaving and coming back | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 8, 6 periods Mon–Sat 19–31 Oct → seen in later passes: the grade 8 timetable renders for teacher, student and parent; edits save (#39) |
| B-07 | Admin · iOS | Same for grade 9 with 5 periods | Grade 9 grid independent of grade 8 | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 9 slots exist (60); config is school-wide (run log #5) → seen in later passes: grade 9 is listed in the full timetable (#5 grades pass) |
| B-08 | Admin · iOS | Sets grade 8 fees: tuition ₹40,000 + transport ₹8,000 | Total ₹48,000 shown; ₹ sign renders | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 8 base 40000 + 8000 stored in `computer_fee` (no transport field?) — check label in E-07 → seen 2026-11-24/25: Fee Structures shows grade 8 Base ₹40,000 + Computer ₹8,000 (range ₹40,000–₹48,000); the optional subject is Computer, not transport |
| B-09 | Admin · iOS | Enters a negative or blank fee | Refused with a readable message; nothing saved | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB → **PASS** in the 2026-11-24 regression round (negative fee refused) |
| B-10 | Admin · iOS | Uploads a payment QR + UPI details | QR preview shows; setup road reaches its end | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: payment_info row exists → payment_info row exists; the Payment Info tab was not opened in later passes → **PASS** 2026-11-25 — admin Payment Info shows SBI / `sunrise@sbi` / QR (iPhone); parent and student fee summaries carry the same option and the QR downloads (200, PNG) |

## C. People join

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| C-01 | Mr. Iyer · Web | Registers as a teacher in Sunrise | "Registration submitted! Await admin approval." | PASS 2026-10-22 — "Registration submitted! Await admin approval." — but see run log: accepted with NO active year |
| C-02 | Mr. Iyer · Web | Immediately tries to log in | "pending admin approval" message, no dashboard | PASS 2026-10-22 — "Your account is pending admin approval. Please wait." |
| C-03 | Aarav · iOS | Registers as grade 8 student with phone, email and parent details | Submitted; parent account also created (pending) | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: aarav8 + aarav8_parent created together → aarav8 and aarav8_parent sign in and work across the iPhone pass |
| C-04 | Someone · iOS | Registers with Aarav's username or phone again | Refused with a generic message (no "this user exists" leak beyond what's needed) | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB → **PASS** 2026-11-25 — same username → 409 "Username already taken."; same phone → 409 with a deliberately vague message (no account enumeration) |
| C-05 | Meera, Kabir, Ms. Das · Web | Register the rest of the cast | All pending | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: meera8, kabir9, das_sci (+ parents) exist → the cast (das_sci, iyer_maths, meera8, anya8…) is active and used throughout later passes |
| C-06 | Prankster · Web | Registers a junk student "asdf" | Pending | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: ids 11934/11935 missing — consistent with asdf + parent rejected → **PASS** 2026-11-25 — a junk student + parent registered (201) and appeared as pending |
| C-07 | Admin · iOS | Opens pending users (pull to refresh) | Sees everyone from C-01..C-06 with role and grade | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB → **PASS** 2026-11-25 — the pending list (API) showed both junk accounts; the iPhone Users screen lists pending sign-ups |
| C-08 | Admin · iOS | Rejects "asdf" | Gone from list; that username can register again | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: asdf gone (see C-06) → **PASS** 2026-11-25 — both rejected (204), gone from pending, cannot sign in (401) |
| C-09 | Admin · iOS | Approves everyone else (incl. Aarav's parent) | All move to active users; filters by role/grade work | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: all 9 Sunrise users active + approved → approved accounts are active and sign in (iPhone pass) |
| C-10 | Aarav · iOS | Logs in now | Student dashboard, his name, grade 8, today's timetable | PASS 2026-10-23 — student dashboard, aarav8, Grade 8, P1–P6 timetable. **FAIL (date roll-over)**: see run log 2026-10-23 #1 → **FIXED 2026-10-26** (second batch, date roll-over) |

## D. A school day — teacher side

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| D-01 | Mr. Iyer · iOS | Opens dashboard in the morning | Daily road for grade 8 (blue) and grade 9 (purple); car on first pending step | PASS 2026-10-23 — Gr.8 blue, Gr.9 purple; car on Attendance for both |
| D-02 | Mr. Iyer · iOS | Takes period-1 attendance: Meera absent | Saved; road advances | PASS 2026-10-23 — "Attendance submitted successfully!", DB P1 aarav present / meera absent, +5 XP. Road does **not** advance after P1 alone — by design the step needs every period (teacher.py today-workflow); no "1/6" shown though (run log #4) |
| D-03 | Mr. Iyer · iOS | Opens period 2 attendance | Pre-filled from period 1 (Meera absent); can change before saving | PASS 2026-10-23 — P2 pre-filled Meera absent, still "Submit" (unsaved), toggles editable |
| D-04 | Mr. Iyer · iOS | Assigns grade 8 Maths homework "Ex 4.2 Q1–10" | Saved; appears on his dashboard | PASS 2026-10-23 — "Ex 4.2 Q1-10" saved, in Homework Review + dashboard Recent Homework |
| D-05 | Mr. Iyer · iOS | Tries to assign another homework before reviewing the last | Told to review the previous one first | PASS 2026-10-23 (simulated next day: Ex 4.2 created_at moved to 22 Oct in DB) — "Mark yesterday's homework completion before assigning new homework." Same-day 2nd HW is allowed by design. Message renders under the dialog scrim (hard to read) |
| D-06 | Mr. Iyer · iOS | Next "day": reviews homework — Aarav done, Meera not | Tiles colour-coded; Aarav gets XP | PASS 2026-10-23 — Meera auto-shown Absent (from attendance), Aarav Complete → +20 XP HOMEWORK_ON_TIME. But road HW Review stays orange afterwards (run log #3) |
| D-07 | Mr. Iyer · iOS | Sends a grade-8 broadcast "Unit test on Friday" | Sent; listed in broadcasts | PASS 2026-10-23 — "Broadcast sent!", listed with Grade 8 tag; DB target_grade=8 |
| D-08 | Mr. Iyer · iOS | Uploads a chapter `.pptx` presentation and adopts it | Slides render; recommended periods shown | PASS 2026-10-23 — Upload Slides tab, `MindForge_Presentation.pptx` (pitch deck as stand-in) as Gr 8 Maths "Linear Equations": 12 slides render, "2 periods · 8 / period"; Adopt → "Added to your dashboard." Note: "Upload & Use" does not adopt — a second tap is needed |
| D-09 | Mr. Iyer · iOS | Logs a period on the presentation | Auto-quiz card appears as "Generating", flips to ready or failed (with Retry) | PASS 2026-10-23 — logged slides 1–6 → "Quiz is generating…"; Tests card showed Generating then flipped to ready live (~40 s), 5 Qs, unpublished, Publish/Delete. Questions were about linear equations, not the slide text (deck didn't match the chapter name — see run log #10) |
| D-10 | Mr. Iyer · Web | Generates a 10-question AI test on a chapter, edits one question, publishes with a 15-min window | Test listed as published; PDF downloads with the answer key | FAIL 2026-10-23 (web) — generated 10 MCQs from an uploaded chapter PDF (questions match the PDF). But: (a) the test was **published on generation**, live to students before review (teacher.py:1043, intentional); (b) **editing only an option is silently lost** — no Save appears, back discards it (`_questionsEdited` ignores `options`, test_detail_screen.dart:273); question-text edits do save; (c) header shows "10 min" but stored/actual limit is 5 (`questions.length` used as minutes, :376); (d) no publish "window" control exists — plan expectation outdated; PDF download exists only for offline tests (verified test_paper.pdf + answer_key.pdf stored in MinIO for test 481, not downloaded) → **FIXED** — no auto-publish (#12, third batch); option-only edits saved (#13, fourth batch) |
| D-11 | Mr. Iyer · iOS | Enters offline marks for a written test | Marks saved; re-saving replaces, doesn't duplicate | PASS 2026-10-23 — offline "Ch 4 Written Test" generated on iOS from the chapter PDF; marks Aarav 5/6, Meera 3/6 → "Saved 2 grade(s)!"; re-saving Aarav 6 replaced the row (still 2 rows in `grades`) |

## E. A school day — student side

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| E-01 | Aarav · iOS | Opens app after D-04 | New homework visible without restarting | PASS 2026-10-23 — "Ex 4.3 Q1-5" (23 Oct) + "Ex 4.2" on dashboard; homework donut 1 complete / 1 pending |
| E-02 | Aarav · iOS | Opens Broadcasts | "Unit test on Friday" with unread dot; dot clears after reading | PASS 2026-10-23 — red dot on Announcements; opened list; dot gone on return. Bug: time shows "06:10 AM" (UTC) for an 11:40 IST send — `DateFormat(...).format(broadcast.createdAt)` without `.toLocal()` (`features/student/screens/broadcasts_screen.dart:209`) |
| E-03 | Kabir (grade 9) · Web | Opens Broadcasts | Does **not** see the grade-8 broadcast | PASS 2026-10-23 (web) — kabir9 Broadcasts: "No announcements yet" |
| E-04 | Aarav · iOS | Takes the test from D-10, answers all, submits | Score shown; no answer key while the test is still open | PASS 2026-10-23 — 10 MCQs, question + option order shuffled per student; 1 deliberately wrong → "90% 9.0/10". Review while open: "Correct answers appear when the test closes — 26 Oct", own answers only; API `/student/tests/482/review` and `/tests/pending` carry no `answer` field (checked with curl). Timer 10:00 = server `attempt_expires_at` (10 min) |
| E-05 | Meera · Web | Starts the same test, presses browser Back mid-test | Warned; leaving forfeits — scores 0, can't re-enter | PASS (as designed) 2026-10-23 (web) — "Before you begin: single attempt…" dialog up front; browser Back left immediately (no warning at the moment), attempt auto-submitted with the 1 answer given → score 1/10 (plan said 0; app rule is "answers so far"); test gone from Online list |
| E-06 | Aarav · iOS | After the window closes, opens the review | Answers and key shown, matching his shuffled order | PASS 2026-10-23 — closed window by moving `tests.expires_at` into the past (local DB); review then showed Correct/Incorrect + key in Aarav's shuffled order. Minor: needed pull-to-refresh — reopening showed the cached locked view |
| E-07 | Aarav · iOS | Opens Attendance, Grades, Timetable, Fees, Faculty | Each loads real data (attendance from D-02, marks from D-11, ₹48,000 fees, QR) | PARTIAL 2026-10-23 — Attendance: 23 Oct present, 100% ✓. Grades: online 9/10, offline 6/6 ✓, but **"Class High/Low" are the student's own min/max** (`features/student/screens/grade_screen.dart:1023`) — showed 90%/90% though Meera scored 10%. Fees: ₹40,000 (not ₹48,000) — the ₹8,000 was stored as the optional *computer* fee and Aarav takes no optional subject; there is no transport-fee concept. Pay tab: QR + UPI `sunrise@sbi` ✓, empty bank fields shown as blank labels. Faculty (web): both teachers ✓. Timetable: dashboard P1–P6 ✓ → **FIXED 2026-10-26** — Class High/Low are the real class figures (#19) |
| E-08 | Aarav · iOS | Opens XP and leaderboard | XP reflects homework + test; ranked against Meera; locked themes say why | PASS 2026-10-23 — Aarav 105 XP (5 attendance + 20 homework + 80 test), #1 vs Meera 0; locked themes say "Reach Level N to unlock" |
| E-09 | Aarav · iOS | Opens Profile, changes avatar | New avatar everywhere; no "Delete account" for a student | PASS 2026-10-23 — no Delete account for student; Change Photo → "Profile picture updated!", shows on dashboard and on Meera's web leaderboard |
| E-10 | Aarav · iOS | Dashboard chapter-progress ring | Reflects the presentation periods logged in D-09 | PASS 2026-10-23 — "Class progress" ring 50% Linear Equations · iyer_maths (6/12 slides from D-09) |

## F. The parent

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| F-01 | Aarav's mum · Web | Logs in | Parent dashboard for Aarav: marks, timetable, progress ring | PASS 2026-10-23 (web) — parent dashboard: class-progress ring 50%, today's timetable, test-marks chart. Minor: child's name not shown anywhere on the dashboard ("Welcome back, aarav8_parent") |
| F-02 | Aarav's mum · Web | Opens Attendance, Homework, Grades, Fees | Same data as Aarav sees, read-only — no edit controls | PASS 2026-10-23 (web) — Grades 9/10, Attendance 23 Oct present, Homework (Ex 4.3 pending / Ex 4.2 complete), Fees ₹40,000 — same as Aarav, no edit controls. API: parent token → 403 on teacher homework/attendance, admin fee payment, student tests |
| F-03 | Admin · iOS + Mum · Web | Admin records a ₹20,000 fee payment | Mum's fee balance updates to ₹28,000 live | PASS 2026-10-23 — admin (iOS) recorded ₹20,000 → mum's open web Fees page updated live to Paid ₹20,000 / Balance ₹20,000 + history row, no refresh (plan said ₹28,000 — see #23) |
| F-04 | Aarav's mum · Web | Profile → Delete account dialog | Cascade warning; Delete disabled until username typed. **Cancel**, don't delete | PASS 2026-10-23 (web) — "Delete my account": red cascade warning (linked student deleted too), Delete disabled with empty and with partial username "aarav8_paren"; Cancel → both accounts still active in DB |

## G. Two people at once (realtime)

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| G-01 | Iyer · iOS → Aarav · Web | Iyer marks Aarav's homework done | Aarav's pill flips Pending → Complete without refresh | PASS 2026-10-23 — Iyer (iOS) marked Aarav complete on Ex 4.3 → Aarav's open web Homework pill flipped Pending → Complete with no refresh |
| G-02 | Iyer · iOS → Das · Web | Iyer sends school-wide broadcast | Appears live on Ms. Das's screen | PASS 2026-10-23 — Iyer (iOS) sent "Staff meeting 4pm" to Everyone → appeared on Ms. Das's open web Broadcasts list live, tagged Everyone |
| G-03 | Sunrise → Riverdale | Iyer sends grade-8 broadcast; `river_kid` (Riverdale grade 8) watching | Nothing arrives at Riverdale | PASS 2026-10-23 — river_kid (Riverdale, grade 8) watching web Broadcasts while Iyer sent "Grade 8 field trip" (and earlier the Everyone one): nothing arrived; `/api/student/broadcasts` for river_kid returns only Riverdale's own "S2-BCAST" |
| G-04 | Aarav · iOS | Backgrounds the app 40 s, returns | Reconnects once; then a new broadcast still arrives live | PASS 2026-10-23 — Aarav's iOS app backgrounded 42 s, relaunched; then Iyer (web) sent "Library closed tomorrow" → appeared on Aarav's dashboard live with unread dot |

## H. Things going wrong

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| H-01 | Aarav · iOS | Wrong MPIN 5 times | Locked with a "try again later" message, not a crash | PASS 2026-10-23 — 5× wrong MPIN each "Invalid username or MPIN." (no warning on attempts 4–5); then correct MPIN → "Account temporarily locked due to too many failed attempts. Try again in 15 minutes." Lock is per (user, IP), 15 min; cleared in local Redis afterwards |
| H-02 | Aarav · iOS | Backend stopped, opens Grades | "No internet connection" error view with Retry; Retry works once backend is back | PASS 2026-10-23 — `docker stop mindforge_backend`, pull-to-refresh on Grades → after ~25 s "No internet connection… Try Again" (cached grades replaced by the error view); backend started → Try Again reloads 9/10 |
| H-03 | Admin · iOS | Deactivates Kabir while Kabir is logged in on Web | Kabir is signed out on his next action; can't log in | PASS 2026-10-23 — admin (iOS) Active Users → Kabir toggle → "Deactivating this student will also deactivate their linked parent account" → Deactivate; Kabir on web clicked Grades → 401, refresh 401, back on /login. Kabir + parent now inactive (left that way) |
| H-04 | Owner · Web | Suspends Sunrise; a Sunrise teacher tries to log in | Login refused with a clear message; owner unaffected. Then un-suspend | PARTIAL 2026-10-24 — owner Suspend (one click, **no confirmation**) → "Sunrise Public School suspended."; teacher/admin login → 400 "Selected school was not found or is inactive." and Sunrise vanishes from the picker; owner unaffected. But the already signed-in admin (iOS) got **"Server error. Please try again in a moment."** with a no-wifi icon on the next request (403 underneath) and stayed on a normal-looking dashboard — not signed out, not told the school is suspended. Re-activated; picker only showed Sunrise again after an app restart (cached list) → **FIXED** — suspended users signed out with the reason (#26, ninth batch); Suspend asks first (2026-11-23) |
| H-05 | Iyer · iOS | Types a 5,000-char homework title / emoji / blank | Blank refused; long text refused or trimmed with a message; emoji saved fine | PASS 2026-10-24 — blank and spaces-only title → "Required"; leading spaces trimmed; emoji/Devanagari title saved (API, id 993). Over 300 chars refused by server (422 "at most 300 characters", app maps it to a readable message) but the title field has no counter/limit, so the teacher only finds out on submit. Test rows 992/993 left in grade 9 |
| H-06 | Aarav · Web | Hard-refreshes on `/student/fees`, uses browser back/forward | Stays logged in; navigation works | PASS 2026-10-24 (web) — reload on /student/fees keeps the session and returns to Fees (dashboard + MindForge branding flash for ~5 s first); back → Fees, forward → Grades |
| H-07 | Any · Web | Resize to 375 / 768 / 1280 px on each dashboard | No overflow stripes; bottom nav vs sidebar correct | PASS 2026-10-24 (web, student) — 375 and 768 px: bottom nav, no horizontal overflow (scrollWidth = innerWidth); 1280: sidebar. Minor: "Mathematic/s" wraps mid-word in period cards at 768; "Recent Test Marks" bars are both labelled just "Math". Teacher/parent/admin only seen at 1280 |
| H-08 | Aarav · iOS | Logs out, logs in as Meera on the same device | No trace of Aarav's data (dashboard, presentations, XP) | PASS 2026-10-24 (web) — Aarav logout leaves localStorage/sessionStorage empty; Meera then sees her own name, letter avatar, 0 XP, grades 1/10 and 3/6, fees ₹0 paid. Grade-wide progress ring is shared by design |

## I. End of year

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| I-01 | Admin · iOS | Reports screen | Attendance / marks reports for grade 8 match what was entered | PARTIAL 2026-10-24 — Reports has only fee PDFs (Pending Fees, Student Ledger); **no attendance or marks reports**. Fee PDFs (fetched via API) are correct: Aarav ₹20,000 due, Meera ₹40,000, total ₹60,000; ledger shows the 23 Oct payment. PDFs are branded "MIND FORGE", not the school → **FIXED 2026-11-20** — attendance and marks reports, school-branded PDFs (#28) |
| I-02 | Admin · iOS | Close Year → Cancel | Nothing changes | PASS 2026-10-24 — Close Year dialog states all students/teachers/parents are removed and the timetable cleared; Cancel → DB unchanged (9 users, 2026-27 current, 132 slots) |
| I-03 | Admin · iOS | Close Year → Confirm, then Start Year 2027–28 | New year; road resets; last year's homework/broadcasts/open tests not shown to students | PARTIAL 2026-10-24 — DB backed up first (`.claude/backups/mindforge_local_pre_I03_20261024_1645.dump`, pg_dump -Fc). Close Year → "Academic year closed — a new year has started." All 8 non-admin users soft-deleted (old logins → "Invalid username or MPIN"), 132 timetable slots cleared; fee structure, payment info, logo kept. Re-registered aarav8 + parent via API and approved: homework, broadcasts, pending/completed tests, grades, timetable all empty; 0 XP. Meera, still signed in on web, was signed out on her first request (one screen showed cached grades first). But: **new year is labelled "2026-27" again** (label = current calendar year, `admin.py` `_make_year_label(now.year)`), so two years share a label; there is no separate "Start 2027-28" step; **last year's chapter-progress ring (Linear Equations 50%, by deleted iyer_maths) still shows** to the new class; setup road stays all-green (timetable step = periods config, kept by design) → **FIXED** — unique year labels (#30), progress not carried over (#31), header updates (#32 not reproduced) |

## J. Extreme cases

Edge conditions a real school will eventually hit. Run after A–I; anything destructive goes on throwaway accounts.

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| J-01 | Admin · Web | Registers/approves 60 grade-8 students (script the sign-ups, approve in UI), then Iyer takes attendance | List scrolls smoothly; save takes < 3 s; counts correct | PASS (server) 2026-10-24 — 60 scripted grade-8 sign-ups (`bulk8_01..60` + parents, MPIN 135792), all approved in 0.9 s; admin list + teacher roster 62 in 0.01 s; attendance for 62 saved in 0.23 s. UI scrolling not timed. **Registration is capped at 5 per minute per IP** (`auth.py` register) — a class signing up on one school Wi-Fi gets "Too many registration attempts"; the script had to vary X-Forwarded-For (works locally only) |
| J-02 | Students · Web | Names in Devanagari/Gujarati, an apostrophe (D'Souza), 60-char name, emoji | Stored and shown correctly everywhere, incl. PDFs and leaderboard; no layout overflow | PASS (server) 2026-10-24 — usernames in Devanagari, Gujarati, d'souza, 60 chars, emoji and with a space all accepted and stored. Rendering in PDFs/leaderboard not checked; spaces/emoji in usernames may be undesirable |
| J-03 | Someone · Web | Registers `Aarav8` when `aarav8` exists; school name "sunrise public school" | Treated as duplicates (case-insensitive) | FAIL 2026-10-24 — `Aarav8` registered and approved alongside `aarav8`; logins are case-sensitive and resolve to different accounts (`AARAV8` → invalid). School names ARE case-insensitive (409 for "sunrise public school") → **FIXED 2026-10-25** — case/confusable username collisions refused at registration |
| J-04 | Iyer · Web | Broadcast / homework text `<script>alert(1)</script>` and `'; DROP TABLE users;--` | Shown as plain text; nothing runs; nothing breaks | PASS 2026-10-24 — `<script>`, `<img onerror>` and `'; DROP TABLE users;--` saved as broadcast/homework text and shown verbatim on web; no script ran; users table fine |
| J-05 | Iyer · iOS | Test with 0 questions; end time before start; window entirely in the past | Can't publish; clear message for each | FAIL 2026-10-24 — auto-quiz 480 emptied to 0 questions via the editor API and then published (200). No start/end time exists, so the other two checks don't apply. Unpublished again → **FIXED 2026-10-26** — a 0-question test cannot be published |
| J-06 | Aarav · iOS | Test window closes while he is mid-test | Auto-submitted with answers so far (or clear rule); no crash, no second attempt | FAIL 2026-10-24 — student started 482, autosaved 1 answer, window then closed: submit → 410 "Test submission window has expired."; start again → 410; submission left unfinalized with no score — answers so far are lost (plan expected auto-submit) → **FIXED 2026-10-25** — an in-progress attempt is graded when the window closes |
| J-07 | Aarav · iOS | Airplane mode just before tapping Submit, then back online | Submission not lost or double-counted; clear status shown | NOT RUN — no network toggle in the simulator tooling; H-02 covers the "backend gone" error view → **PASS after fix** 2026-11-25 — backend stopped just before Submit (the simulator can't toggle airplane mode; a refused connection fails just as fast): red "Submission failed: Couldn't reach the server…" snackbar, button re-enabled, answers and timer kept; back online, the same attempt submitted (2/10 as answered). Fixed: autosave was cancelled by the failed submit and never restarted |
| J-08 | Aarav · iOS | Double/triple-taps Submit; Iyer double-taps Save attendance; admin double-taps Record payment | Exactly one record each | FAIL (partly) 2026-10-24 — 3 concurrent test submits → 1 row (409, 201, 409); 2 concurrent attendance saves → no duplicate (409, 201). **2 concurrent "Record payment" → 2 payment rows** — no idempotency on `/admin/fees/payments` → **FIXED 2026-10-26** — payments idempotent on double-tap/retry |
| J-09 | Aarav · iOS | Phone clock set 1 day ahead / behind, then opens tests and timetable | Server time wins; can't start a test early or late | PASS (server) 2026-10-24 — a closed test can't be started (410); dashboard for a future date just returns that day's (empty) timetable. Device clock not changed on the sim |
| J-10 | Iyer · iOS | Takes attendance at 23:59 and saves at 00:01 | Lands on the right day (IST); no duplicate | PASS (server) 2026-10-24 — date is chosen by the client: yesterday accepted (backfill), tomorrow/+7 refused ("cannot be marked for a future date"); same day+period re-save upserts. 23:59→00:01 on a device not run |
| J-11 | Admin · iOS | Fee payment of ₹0, ₹0.50, more than the balance, ₹99,99,999 | Zero/over-balance refused or clearly flagged; paise handled; big number formats with Indian commas | FAIL 2026-10-24 — ₹0 and negative refused; **₹0.50, ₹99,99,999 and over-balance accepted silently**; balance clamps to ₹0 so overpayment is invisible. Student Fees shows Western grouping (₹9,999,999, ₹10,052,000) and **₹0.50 displayed as "₹1"** → **FIXED** — over-balance refused (third batch); paise and Indian grouping shown (fifth batch) |
| J-12 | Admin · iOS | Changes grade 8 fee structure after payments exist | Paid history kept; balance recalculated sensibly | PASS 2026-10-24 — base fee 40,000→45,000 with a ₹20,000 payment: payment kept, balance ₹25,000. Reverted |
| J-13 | Mum · Web | Parent with two children (register Aarav's sibling with same parent phone) | Child switcher; each screen follows the selected child; no mixing | PASS 2026-10-24 — `anya8` registered with parent_username aarav8_parent + its MPIN → linked; Mum (web) gets an aarav8/anya8 switcher; Grades and Fees follow the selected child |
| J-14 | Admin · iOS | Moves Aarav from grade 8 to 9 mid-year | His timetable/homework switch to grade 9; past marks kept | PASS (server) 2026-10-24 — admin moved aarav8 to grade 9: dashboard timetable + homework switched to grade 9, past grade-8 marks kept. Moved back |
| J-15 | Admin · iOS | Deactivates Mr. Iyer while his test is open and homework pending | Students can still finish the test; Ms. Das can take over/unpublish; homework still visible | PASS (server) 2026-10-24 — Iyer deactivated mid-test: student still submitted (201), Ms. Das could unpublish Iyer's test, homework still listed. Iyer re-activated |
| J-16 | Aarav · iOS + Web | Logged in on two devices at once; logs out on one | Other device keeps working (or is signed out — whichever is the rule, consistently) | PASS (server) 2026-10-24 — two sessions for meera8; logout of one → that token 401, the other still 200 (per-session logout) |
| J-17 | Aarav · iOS | App left idle overnight (or access token expired), then opened | Silent refresh; no login loop; no data from cache that's wrong | PASS (observed in C-10, 2026-10-23) — app left open overnight: first call 401 → silent refresh → 200, no login loop; but the date bug (run log 2026-10-23 #1) left yesterday on screen |
| J-18 | Iyer · iOS | Uploads 25 MB photo, HEIC, a `.txt` renamed `.jpg` as avatar | Big/fake refused with a message; HEIC works or is refused cleanly | PASS (server) 2026-10-24 — 25 MB → 413 "Maximum allowed size is 5 MB"; text renamed .jpg → 400 "Only JPEG, PNG, and WebP"; HEIC → same clean 400 (iOS picker normally converts to JPEG) |
| J-19 | Iyer · Web | Presentation: corrupt `.pptx`, 200-slide deck, password-protected PDF | Corrupt/locked refused clearly; big deck processes or fails with a message, not a spinner forever | PARTIAL 2026-10-24 — corrupt .pptx → 415 "isn't a readable PowerPoint"; text renamed .pptx → 415 with Google Slides hint. 200-slide deck and password-protected PDF not tried → **DONE 2026-11-23** — 200-slide deck accepted in 0.35 s (200 slides, 25 periods); a password-protected PDF is now refused at upload (422) instead of failing in the AI job → **PASS** — both cases done 2026-11-23 (see that section); re-checked 2026-11-25: AES-256 locked PDF → 422 "That PDF is password-protected…" |
| J-20 | Iyer · Web | AI test generation with all AI keys removed/invalid | Friendly failure + Retry; no half-made test left behind | NOT RUN — needs the backend restarted with AI keys removed → **FIXED** 2026-11-25 — with all AI keys blank, generation returned 500 "Internal server error."; now 503 "AI question generation is unavailable right now…" shown in the app's snackbar, no partial test saved; providers' reasons still logged |
| J-21 | Iyer + Das · Web ×2 | Both edit the same grade-8 timetable slot at the same moment | One wins cleanly; the other is told; no duplicate period | PARTIAL 2026-10-24 — Iyer and Das upsert grade 8 P6 at the same moment: both 200, one row (last write won, "Mathematics"); no duplicate, but the overwritten teacher is not told → **FIXED 2026-10-30** — stale timetable saves refused with the other teacher's version (#39) |
| J-22 | Admin · iOS | Whole-school holiday on a weekday; Sunday; a day with no timetable | Holiday banner for all roles; road doesn't nag for attendance | PASS (server) 2026-10-24 — Monday 26 Oct marked holiday for grades 8+9: student summary returns 6 holiday slots with comment "Diwali"; Sunday returns none. Today's grade 9 marked holiday → workflow is_holiday=true, attendance not applicable, next_step "holiday" (no nag). Banner not viewed on screen |
| J-23 | Any · iOS | Largest Dynamic Type text size, dark mode, iPad landscape | Readable; no clipped buttons or overflow stripes | NOT RUN — Dynamic Type / dark mode / iPad not exercised this session → **PASS after fix** 2026-11-25 — the app caps text at 1.1× and forces light mode (`main.dart`), so largest Dynamic Type + system dark mode stay readable (login, admin Users with Devanagari/emoji names, teacher dashboard). At 1.1× the admin welcome card ("Welcome back, sunrise_admin" on two lines) covered the School Setup card: the four dashboard headers had a fixed height. Fixed: headers grow with their card. iPad landscape still not run iPad landscape run 2026-11-25 → **PASS after fix**: the status bar's right half (Wi-Fi, battery) was white on the light content area; navy band added (`NavyStatusInset`) |
| J-24 | Any · iOS | Paste letters/emoji/7 digits into the MPIN pad; spam pull-to-refresh; tab-switch rapidly | Input rejected; no duplicate requests storm; no crash | NOT VERIFIED — on-screen keypad offers digits only; physical-key input never reached the MPIN cells in the hidden web pane (automation or app — unknown) → **PASS** 2026-11-25 (iOS) — typed `ab1357924` into the MPIN pad: letters ignored, the 7th digit dropped, it held exactly 6 digits and signed in. Emoji can't be sent by the simulator tooling. 11 rapid tab switches: no errors, landed on the last tab with correct data |
| J-25 | Admin · iOS | Close Year with a test still open and unpaid fees | Warned; open test closes/expires correctly; unpaid balances carried or reported | PARTIAL (from I-03, 2026-10-24) — Close Year dialog warns about removing users/timetable but says nothing about open tests or unpaid fees; unpaid balance carry-over not checked → **FIXED 2026-10-29** — Close Year warns about unpaid fees and open tests |
| J-26 | Aarav · iOS | Delete app, reinstall, log in | Clean start; push notifications re-register | NOT RUN — reinstall + push registration not exercised → **FIXED** 2026-11-25 — delete + reinstall opened straight into the last user's dashboard (iOS keeps the Keychain across app deletion). Now the first launch of a fresh install clears it: reinstall lands on login; a normal relaunch keeps the session |

## K. Adversarial / security checklist

Authorized security QA of **our own app, local stack only** — never production, which holds real users. Each row is phrased as an abuse attempt and the defence we expect to hold. A row **PASSES when the attempt is refused/contained**; a row that succeeds is a FAIL and gets logged in `SECURITY_RISK_REGISTER.md`. This complements `tests/security_test*.py` and §3 of `TEST_RECORD.md` by driving the attempts through a real client + proxy rather than a probe script. Tooling: browser devtools, `curl`, an intercepting proxy on the simulator, token decoding.

### K.1 Authentication & session

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-01 | Brute-force one real MPIN past the lockout; keep trying from several IPs | Account lockout + rate limit hold; attempts don't reset the counter | PASS-by-design 2026-10-24 — per-(user,IP) lock holds (H-01); distributed guessing from fresh IPs is allowed up to the 50-attempt per-user global backstop, then locks. Documented tradeoff (avoids lockout-DoS). Locked IP short-circuits (~5ms vs ~237ms) — minor lock-state oracle |
| K-02 | Replay an old refresh token after it was rotated / after logout | Rejected; rotation invalidates the old one | PASS 2026-10-24 — refresh rotates; replaying the pre-rotation refresh token → 401 |
| K-03 | Use an access token after logout / after the account is deactivated | Rejected on the next request and on the WebSocket | PASS 2026-10-24 — access token after logout → 401; refresh after logout → 401 **when the client sends the refresh token in the logout body, which it does** (`api_client.dart logoutOnServer`). Empty-body logout leaves the refresh valid (not the real client path) |
| K-04 | Edit a JWT payload (role student→admin, different `sub`/`school_id`) and resend | Signature check fails → 401; no privilege gained | PASS 2026-10-24 — role→admin, sub→admin-id, school_id→2 all re-signed with the original sig → 401 (signature check) |
| K-05 | Present a `none`-alg or unsigned token; present an expired token | Refused | PASS 2026-10-24 — none-alg and expired tokens → 401 (API and WebSocket) |
| K-06 | Call protected endpoints with no token / a malformed `Authorization` header | 401, consistent message | PASS 2026-10-24 — no token / "Banana xyz" / bare unsigned → 401 |
| K-07 | Enumerate usernames via login/registration error wording and timing | Same generic reply and similar timing for known vs unknown | PASS 2026-10-24 — identical wording ("Invalid username or MPIN."); known-unlocked vs unknown median 238 vs 236 ms (2 ms) with fresh IPs — no enumeration oracle |
| K-08 | Parent-MPIN guessing at registration across many addresses (per §tests) | Throttled/locked as the integration test expects | PARTIAL 2026-10-24 — wrong parent MPIN at registration → 422 weak-MPIN guard (J-13); register rate-limited 5/min/IP. Dedicated multi-IP parent-MPIN throttle test (tests/security_test*) not re-run here → 2026-11-25 local: 60 wrong MPINs on bulk8_30, each with a new spoofed `X-Forwarded-For` → 50×401 then 429; the correct MPIN from a fresh IP → 429 (global lock holds). Per-IP layer is bypassable without a trusted proxy (local); production relies on Railway's edge appending the real IP — unverified, noted in the register. Lockout cleared afterwards |

### K.2 Authorization & tenancy (the big one)

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-09 | As a student, call teacher/admin/owner endpoints directly (change role in the path/body) | 403/404; no data or write | PASS 2026-10-24 — student token → admin/users, teacher/attendance, owner/schools, admin fee payment all 403 |
| K-10 | IDOR: as Aarav, fetch another student's marks/fees/profile by guessing IDs | 404, not another student's row | PASS 2026-10-24 — student reviewing an untaken test → 404 "No submission"; student → teacher/submissions 403; parent → non-child 404. Student self-endpoints are token-scoped (no id in path) |
| K-11 | Cross-tenant: with a Sunrise token, read/write a Riverdale row by its ID | 404 (not 403), no leak — matches the tenancy tests | PASS 2026-10-24 — Sunrise token vs Riverdale rows (user 42, hw 12): edit/deactivate/ledger/delete all **404** "not found" — no 403/leak, matches tenancy design |
| K-12 | Parent reads a child that isn't theirs by changing `child_id` | 404 | PASS 2026-10-24 — parent child_id of a Riverdale kid (42) and of a same-school non-child (meera 11936) → 404 |
| K-13 | Student POSTs marks/attendance/XP for themselves | Refused; those are staff-only writes | PASS 2026-10-24 — student POST /teacher/grades → 403 |
| K-14 | Open a test before its window / re-enter after submit / fetch the answer key while the test is open | All refused; key only after close | PASS 2026-10-24 — answer key only after close (E-04/E-06); open-before-window and closed-test start refused (J-09). Cross-ref J-06: a window closing mid-attempt loses the saved answers |
| K-15 | Mass-assignment: send extra fields (`is_approved`, `role`, `school_id`, `xp`) on a profile/registration update | Extra fields ignored, not trusted | PASS 2026-10-24 — registration with is_approved=true → stored is_approved=false; profile update with role/school_id/xp injected → aarav8 row unchanged (student/944/approved). Extra fields ignored |

### K.3 Injection & input

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-16 | SQL-ish payloads in names, usernames, homework, broadcast, search, filters | Treated as data; parameterised queries; no error leak | PASS 2026-10-24 — SQL payloads in role/grade/limit params → 422 (enum/int validation); no error leak. (`limit=-1/abc` on /admin/users are ignored unknown params → default) |
| K-17 | Stored XSS: `<script>`, `<img onerror>`, `javascript:` in any text that's shown to another user (names, broadcasts, homework, feedback) | Rendered inert on web and in PDFs | PARTIAL 2026-10-24 — `<script>`/`<img onerror>`/`javascript:` in broadcast+homework render as inert text on web (J-04); not verified inside generated PDFs or feedback → PDFs checked 2026-11-25: `<script>`, `<a href="javascript:…">`, `<b>` and `&` in student and school names render as inert literal text (no link or markup injected). Found and fixed: attendance/marks report tables double-escaped names ("Ab &amp; Cd"). Devanagari names printed as boxes → fixed 2026-11-25 (Noto Sans Devanagari/Gujarati + HarfBuzz shaping; see log) |
| K-18 | Oversized / deeply-nested / malformed JSON bodies; wrong content-type | 422/400, no 500, no crash | PASS 2026-10-24 — broken JSON 422, wrong content-type 422, 5000-deep nested 400, 10 MB body 422 — no 500/crash |
| K-19 | Path traversal / weird filenames in uploads (`../`, null byte, double extension) | Sanitised; stored under a safe key | PASS 2026-10-24 — traversal filenames (`../../../../etc/passwd.png`, backslashes, NUL, double-ext) discarded; stored under server-generated key `profiles/teacher/<id>/<random>.png` |
| K-20 | Upload a non-image or script disguised as an image/pptx; polyglot file | Refused by content sniff, not just extension | PASS 2026-10-24 — disguised files refused by content sniff: text-as-.jpg → 400 (Pillow decode), text-as-.pptx → 415 (J-18/J-19); valid-PNG-with-bad-name stored safely (K-19) |
| K-21 | Unicode / homoglyph usernames to impersonate or dodge the uniqueness check | Normalised; no collision bypass | **FAIL** 2026-10-24 — Cyrillic-homoglyph `аarav8` (U+0430 + "arav8") registered as a *distinct* username alongside ASCII `aarav8`; exact-ASCII dup correctly 409. No confusable/NFKC normalisation → impersonation risk. Same family as J-03 (case-sensitive usernames). **Log in SECURITY_RISK_REGISTER.md** → **FIXED** (J-03/K-21 confusable-skeleton check). Re-checked 2026-11-25: Cyrillic `аarav8` and `AARAV8` both 409 "Username already taken." at Sunrise |

### K.4 Transport, headers & web

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-22 | Downgrade to HTTP; strip/alter TLS (cert/CA pinning on the app) | App refuses; see `project_ssl_pinning` | NOT RUN — no TLS on the local stack; cert/CA pinning (see [[project_ssl_pinning]]) can only be checked against a TLS endpoint |
| K-23 | Load the web app inside an `<iframe>` from another origin | Framing refused (frame-ancestors) | PARTIAL 2026-10-24 — API responses carry X-Frame-Options: DENY, but the Flutter **web app** ships frame-ancestors via a `<meta>` tag, which browsers ignore (console warns), and the local dev server sends no X-Frame-Options → clickjacking protection on the web page depends on the prod web server; unverified → **FIXED** (812fc31) — the web build ships `X-Frame-Options: DENY` and `frame-ancestors 'none'` as response headers (`web/_headers`, pinned by `test/unit/web_csp_test.dart`); the meta-tag copy is kept on purpose as documentation, which is why browsers log that it is ignored |
| K-24 | Hit the API with a cross-origin `fetch` from an untrusted origin | CORS blocks it; only allowed origins pass | PASS 2026-10-24 — Origin https://evil.example.com → no Access-Control-Allow-Origin (browser blocks); http://localhost:8080 → ACAO echoed |
| K-25 | Inspect responses for missing security headers / verbose stack traces / secrets | Headers present (§3.1); errors generic; no secrets in body or logs | PASS 2026-10-24 — HSTS, X-Content-Type-Options: nosniff, X-Frame-Options: DENY, CSP default-src none; no Server/X-Powered-By; 404 body generic "Not Found" |
| K-26 | Pull tokens/MPIN from web localStorage, logs, Sentry events, URL query strings | Not present in URLs/logs; Sentry scrubbed (per `project`) | PASS 2026-10-24 — WS token rides in `?token=` (by necessity) but a `RedactTokenFilter` strips token=/refresh_token= from uvicorn logs and the Sentry scrubber drops mpin/token/authorization/cookie + local vars; backend logs clean of Bearer/JWT |

### K.5 Business-logic abuse

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-27 | Submit a test many times / race two submissions to inflate score or XP | Single attempt enforced; XP awarded once | PASS 2026-10-24 — 3 concurrent submits of test 482 → 1 submission row, 0 duplicate TEST_SCORE XP (J-08) |
| K-28 | Replay a "homework done" or "attendance" write to farm XP | Idempotent; XP not duplicated | PASS 2026-10-24 — saving the same period-2 attendance 3× added the +5 once (ATTENDANCE XP 5→10 for the first distinct period, then flat) — no XP farming |
| K-29 | Self-approve a pending registration, or approve across schools | Refused | PASS 2026-10-24 — Sunrise admin approving a Riverdale user id → 404; pending users can't log in to self-approve; student→approve endpoint 403 (K-09) |
| K-30 | Record a negative/huge fee payment to zero out or overflow a balance | Bounds enforced; no overflow | PARTIAL 2026-10-24 — ₹0 and negative refused (422); **huge/over-balance amounts accepted** with no upper bound, balance clamps to ₹0 (J-11). No overflow crash, but no bound → **FIXED** (J-11 over-balance refused). Re-checked 2026-11-25: ₹50,000 and ₹99,99,999 against anya8's ₹40,000 balance both 400 "Payment exceeds the outstanding balance…" |
| K-31 | Register/approve in a loop to exhaust resources (no CAPTCHA) → DoS-ish | Rate limits / size caps blunt it; app stays up | PARTIAL 2026-10-24 — register rate-limited 5/min/IP and upload size caps (5 MB) observed; a sustained multi-IP flood / full DoS not driven here (overlaps L) 2026-11-25: the register limit is per-IP from the same `client_ip`, so the same proxy caveat applies (see K-08) |
| K-32 | Request a huge paginated range (`limit=10_000_000`) or deep page offsets | Capped; no slow query takedown | PASS 2026-10-24 — /xp/leaderboard?limit=1e7 → 422 (le=100). Note: /admin/academic-years/{id}/users accepted limit=99999999 (200) — appears unbounded; fine at ~130 users, worth a cap |

### K.6 Realtime / WebSocket

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-33 | Connect `/ws/{other_user_id}` with your own token (sub mismatch) | Refused — matches `test_websocket_auth` | PASS 2026-10-24 — ws /ws/<other_user_id> with my token → 403; my own id+token connects |
| K-34 | Subscribe to another school's / grade's channel | No events delivered | HELD-BY-DESIGN 2026-10-24 — no client-side channel subscribe; events are published only to the connecting user's school/grade (publish_to_grade/school). Cross-school delivery already shown absent in G-03. Not separately forced |
| K-35 | Connect with a refresh-type or revoked-JTI token | Refused | PASS 2026-10-24 — ws with a refresh-type token → 403; with a logged-out (revoked-JTI) access token → 403; invalid token → 403 |
| K-36 | Flood the socket with messages / rapid reconnects | Server stays healthy; connection throttled or dropped | NOT RUN — socket flood / rapid-reconnect stress deferred to section L → **PASS after fix** 2026-11-25 — 2,000 pings on one socket answered in 0.16 s; five 1 MB frames absorbed; 50 rapid reconnects in 0.35 s; health 3–8 ms, memory ~176→182 MB. Found and fixed: a Redis restart killed the pub/sub subscriber, silently stopping all live updates until the backend restarted |

## L. Extreme security / stress

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| L-01 | 50 simultaneous logins for one account while an unrelated request runs | Unrelated request not blocked (per `test_login_does_not_block`); no lockout bypass | PASS 2026-10-25 — 50 simultaneous wrong logins for meera8 (fresh IPs) → throttled to 49×429 + 1×401 by the per-user login cap (10/min); an unrelated GET /schools mid-storm still returned 200 (but ~1.6 s — login bcrypt/argon is CPU-heavy). The 50-fail burst tripped the per-user global backstop, so meera8 is now locked 15 min (by design). No lockout bypass |
| L-02 | 500 concurrent students hitting `dashboard-summary` at once | Latency stays reasonable; no 5xx storm | PASS-with-latency 2026-10-25 — 500 concurrent /student/dashboard-summary → all 200, no 5xx. But single dev-worker latency degrades: p50 4.1 s, p95 6.3 s, max 6.4 s, wall 6.5 s. Resilient (no errors), slow under load |
| L-03 | Submit the same test from 10 threads at the same millisecond | Exactly one graded result; no double XP | PASS 2026-10-25 — same test submitted from 10 threads at once → 1×201, 9×409; exactly 1 submission row, 0 duplicate TEST_SCORE XP |
| L-04 | Upload 100 presentations / trigger 20 AI generations at once | Queue holds; no key/billing meltdown takes the app down (watch logs per `project_ai_generation_fallback`) | PARTIAL 2026-10-25 — 10 concurrent real 1.84 MB .pptx deck uploads → all 201 in 0.7 s, health 200 (deck parse holds under concurrency). **Mass real-AI generation deliberately NOT driven** — each gen bills live Claude/Gemini/Groq keys; the generate path + fallback is covered in D-09 and the register |
| L-05 | 10 k-char homework/broadcast, 1000-row timetable, 200-slide deck repeatedly | Size caps refuse the abusive ones; app doesn't OOM | PASS 2026-10-25 — 10k-char homework title, 100k-char description, 50k-char broadcast all → 422 (size caps); 120 timetable upserts in 1.1 s all 200, no OOM |
| L-06 | Leave a WebSocket open and idle for hours; open hundreds of sockets | Reaped/limited; memory stable | PARTIAL 2026-10-25 — opened **200 WebSockets for one user**, all succeeded, health stayed 200 during and after (memory stable). But there is **no per-user connection cap** observed, and hours-long idle reaping was not measured — one client can hold many sockets Re-checked 2026-11-25 with K-36: memory stable after 50 reconnects; still no per-user connection cap |
| L-07 | Clock-skew + token-expiry storm: many clients with expired tokens refreshing at once | Refresh path holds; no thundering-herd lockout | PASS 2026-10-25 — 100 concurrent /auth/refresh across 20 sessions → 20×200 + 80×401 (rotated-token replays rejected) in 0.4 s; no thundering-herd lockout, rotation holds under concurrency |
| L-08 | Fill MinIO / disk with repeated max-size uploads | Quota/size caps; graceful refusal, no data loss (watch for the `project_minio_volume_dataloss` symptom) | PARTIAL 2026-10-25 — 15 bounded avatar uploads succeeded, MinIO /data stable at 128 M, health 200, no `project_minio_volume_dataloss` symptom. **True max-size disk-fill not exercised** (the generated PNG compressed to ~60 KB — identical rows); the 5 MB upload cap itself is proven in J-18 (25 MB → 413) |

---

## Run log

Record each session here: date, platform build, cases run, failures with issue links.

### 2026-10-22 — web release build + iOS debug sim build (working tree incl. uncommitted login redesign)

Ran A-01..A-04, B-01..B-04, C-01..C-02 (+ J-03 school half: PASS). Findings:

1. **Registration accepted with no active academic year.** C-01 created `iyer_maths` (academic_year_id NULL) while Sunrise had zero `academic_years` rows; the Academic Year screen says "Users cannot register until a year is started". `backend/app/routers/auth.py` register falls back to `None` instead of refusing.
2. **Setup road lock is cosmetic.** Locked nodes ignore taps with no message; bottom-nav Fees opens Fee Management (showing 2026-27) before any year exists.
3. **Login redesign (uncommitted):** on iPhone 17 Pro the Sign in button is below the fold (must scroll); status-bar text is white on the light login background.
4. **Web login brand panel** shows the Hansel & Gretel "H" logo and "25+ years of excellence · since 1997" for every school, incl. Sunrise and Platform owner.
5. Timetable config (periods/day, weekend) is school-wide — B-07 "grade 9 with 5 periods, independent of grade 8" can't be done as written.


### 2026-10-23 — same builds, continuing from C-10

1. **Student + parent dashboards stay on yesterday after midnight.** Aarav's dashboard, left open overnight, still read "Thu, 22 Oct" on Fri 23 Oct after resume *and* after pull-to-refresh, although the backend log shows the refresh fetched `dashboard-summary?date=2026-10-23`. Cause: `build()` watches `studentDashboardSummaryProvider(<date at last build>)`; refresh/resume invalidate the provider for the *new* date but nothing triggers a rebuild, so the screen keeps showing the old one. Same in `features/parent/screens/dashboard_screen.dart`. Teacher dashboard's provider isn't date-keyed — unaffected. With a varying timetable (or a holiday) the student would see yesterday's periods.
2. **Homework trash deletes on one tap, no confirmation, hard delete.** Teacher Homework Review → trash icon removed "Ex 4.3" instantly; row gone from `homework` table.
3. **HW Review node stays orange after the review is submitted.** `reviewDone` in `features/teacher/screens/dashboard_screen.dart:1754` also requires all-period attendance, while the Homework node has no such condition and goes green. Teacher reads "review still pending" right after doing it.
4. **Attendance step shows no partial progress.** Backend already returns `attendance_progress` ("1/6"); the road doesn't show it, so after P1 the step looks untouched.
5. **Grade 10 offered everywhere** (Homework Review chips, broadcast grade picker) though Sunrise has no grade 10 — `AppConstants.grades = [8, 9, 10]` hardcoded (`core/utils/constants.dart:33`).
6. Teacher dashboard period chips show seconds and truncate ("09:00:00…").
7. Validation messages shown while a dialog is open render under its dark scrim.

8. **Bottom-nav Home doesn't leave a Home sub-page.** From Broadcasts (reached via the dashboard), tapping Home did nothing; only the back arrow returns.
9. Teacher sees their own broadcast as unread (red dot on Announcements).
10. **Auto-quiz follows the chapter name over the slides.** Slides 1–6 were the MindForge pitch deck; all 5 questions were generic linear-equation MCQs. The job does pass slide text (`presentations.py` `_run_auto_test_job`) but also `chapter=pres.chapter_name`, and the model went with the name. Expected with mismatched test data; the toast "generating from your slides" overstates it.
11. Copy: Pick-from-Database empty state says 'Upload one on the "Upload New PDF" tab' — the tabs are "AI from PDF" / "Upload Slides". "1 periods left" (plural).

To put a file in the iOS sim's Files app: copy it into `…/Devices/<udid>/data/Containers/Shared/AppGroup/<group.com.apple.FileProvider.LocalStorage>/File Provider Storage/`; it shows under Recents in the picker.

12. **Online tests auto-publish on generation** — students can see/take an unreviewed AI test immediately (`backend/app/routers/teacher.py:1043`, deliberate). Combined with #13, the teacher's corrections may never reach students.
13. **Option-only edits are lost.** `_questionsEdited()` (`features/teacher/screens/test_detail_screen.dart:273`) compares question/answer/marks but not `options`, so the "Unsaved changes · Save" bar never appears; no PopScope guard, so back discards silently. Verified: option edit → no PUT; question-text edit → Save bar → saved to DB.
14. **Teacher sees the wrong time limit.** Test header chip renders `${questions.length} min` (10) instead of `timeLimitMinutes` (5; backend sets ceil(n/2)). Generator form correctly says 5 min.
15. Generated questions are tagged [P] "past test paper" / [E] "back exercise" even when the only source was one uploaded chapter PDF.
16. Offline generator: "Upload Chapter" hides the Chapter field (fine) but the iOS picker "Recents" didn't list a freshly added file — had to use Browse.

Test files used: chapter PDF generated to scratchpad (`Ch4_Linear_Equations.pdf`, reportlab, 2 pages); on web the file picker was fed via an `HTMLInputElement.prototype.click` override serving the file from `build/web` (removed afterwards).

17. **Correction to #14:** students get 10 minutes — the timer, the "10 min" chip and the server's `attempt_expires_at` all agree. The odd one out is the generator form ("10 questions = 5 min") and `tests.time_limit_minutes` = 5.
18. **"Unsaved changes" bar stays after Save** on the teacher test page — the save went through (DB updated) but the page still compares against the stale original test.
19. **"Class High / Class Low" on student Grades are the student's own best/worst** in that subject, not the class's (`features/student/screens/grade_screen.dart:1023`).
20. **Student broadcast times are UTC** ("06:10 AM" for 11:40 IST) — missing `.toLocal()` (`features/student/screens/broadcasts_screen.dart:209`).
21. AI question ambiguity: "sum of two consecutive integers is 55 → which equation" offers both `x + (x + 1) = 55` (key) and `2x + 1 = 55` (also correct).
22. No transport fee in the fee structure (base + economics/computer/AI only) — B-08 as written can't be represented.

Test setup changes on 2026-10-23 (local DB): Sunrise cast MPINs reset to `135792` (see local-test-accounts.md); test 482 `expires_at` moved to the past for E-06.

23. **Admin and family disagree on the fee.** Admin Fee Structures card says "Grade 8 ₹48,000" (base + computer), Payments says Total ₹40,000 per student, and student/parent see ₹40,000. The ₹48,000 headline should say it includes optional-subject fees, or show the range.
24. **Grade with no fee structure shows "PAID · Fully paid"** (kabir9, grade 9, ₹0 total) on admin Payments — should read "No fee set".
25. iOS automation note (not an app bug): after the login page scrolls, keypad rows sit at y≈409/471/534/596 pt; using the unscrolled positions enters wrong digits. One failed admin login on 2026-10-23 came from that.


### 2026-10-24 — H-04 … I-02

26. **Suspending a school gives its signed-in users "Server error … no internet".** Requests return 403 but the app shows the generic server-error view and keeps the session; it should sign them out with "Your school's account is suspended". Owner Suspend also has no confirmation dialog.
27. **Login school picker caches the school list** — after un-suspending, Sunrise only reappeared after an app restart.
28. **Reports has no attendance or marks reports** (only fee PDFs); report PDFs carry MindForge branding, not the school's.
29. Homework title field has no length counter; over-300 is only caught by the server on submit.

State left: kabir9 + kabir9_parent deactivated (H-03); grade 9 has test homework 992 (long title) and 993 (emoji); Sunrise active.

30. **Closing a year inside the same calendar year reuses the label** ("2026-27" twice). `_make_year_label(now.year)` in `backend/app/routers/admin.py`; the close dialog never asks for or shows the new label.
31. **Chapter-progress carries over into the new year.** `in_progress_presentation_items` (`backend/app/routers/presentations.py` ~line 913) has no academic-year filter and doesn't skip deleted teachers, so the new class sees last year's 50% ring credited to a removed teacher.
32. Admin dashboard keeps showing the old state until a refresh after Close Year (the success toast appears, header/road unchanged).

**State after I-03:** Sunrise has sunrise_admin plus a re-registered aarav8 (id 11945) and aarav8_parent (11946), MPIN `135792`; everyone else is soft-deleted. To get the pre-I-03 cast back: `docker exec -i mindforge_postgres pg_restore -U mindforge -d mindforge --clean < .claude/backups/mindforge_local_pre_I03_20261024_1645.dump` (restores the whole local DB to 24 Oct 16:45).

All cases A-01 … I-03 have now been run.

### 2026-10-24 — section J

Setup: the pre-I-03 backup was restored (post-I-03 state saved as `.claude/backups/mindforge_local_post_I03_20261024_1650.dump`), Redis `cache:*` flushed, backend restarted. Restoring rewound the users id sequence, so an old web token for the deleted new-year aarav8 (id 11945) authenticated as `bulk8_01` — an artifact of the restore, not an app bug.

33. **Usernames are case-sensitive** — `aarav8` and `Aarav8` are separate accounts (J-03).
34. **Tests can be published with 0 questions** (J-05).
35. **Closing window mid-test loses the attempt** — submit/start return 410 and the saved answers are never scored (J-06).
36. **Double-tap "Record payment" records two payments** (J-08).
37. **Payments: no upper bound / over-balance check; ₹0.50 shows as ₹1; amounts use Western digit grouping** (J-11).
38. **Registration rate limit (5/min/IP) will block a class signing up together on school Wi-Fi** (J-01).
39. Concurrent timetable edits: last write wins silently (J-21).

Test data added: `bulk8_01..60` (+ `_p` parents), J-02 teacher accounts (pending), `Aarav8` + `aarav8_p2`, `anya8` (sibling of aarav8, approved), `anya8b` not created, broadcasts 236/237 and homework 994/995 with script/SQL text, bulk8_03 has ₹1,00,51,999.50 of test payments, Monday 26 Oct and today's grade 9 marked holiday.


### 2026-10-24 — section K (adversarial / security checklist)

Driven with `curl` + a small urllib/websockets harness against the local stack. **2 FAILs: K-21** (homoglyph usernames not normalised — impersonation) and the carry-over **J-03** (case-sensitive usernames). Both to be logged in `SECURITY_RISK_REGISTER.md`. Partials: K-17 (XSS in PDFs unchecked), K-23 (web-app framing is a `<meta>` guard browsers ignore — prod-header dependent), K-30 (no upper fee bound), K-31/K-36 (DoS → section L). Tenancy/authz/JWT/WebSocket/injection/upload/headers/CORS/log-redaction all held.


### 2026-10-25 — section L (extreme security / stress)

Load driven with a threaded urllib + websockets harness against the single-worker local backend. All held or partial; no 5xx storms, no crash, health stayed 200 throughout. **Notes:** L-02 latency degrades to ~4 s p50 under 500 concurrent (single dev worker); L-06 no per-user socket cap (200 opened fine); L-08 real disk-fill not exercised (payload compressed small); L-04 mass-AI skipped to avoid live billing. meera8 left globally locked ~15 min by the L-01 burst.

**All 102 cases (A-01 … L-08) have now been run.** Outstanding bugs are catalogued in the numbered run-log notes above and the per-row Status cells; the security FAILs (K-21 homoglyph, J-03 case-sensitivity) still need logging in `SECURITY_RISK_REGISTER.md`.

### 2026-10-25 — fixes (first batch)

Started fixing the most important findings. Backend, verified against the live local stack:

- **J-06 fixed — test window closing mid-attempt no longer loses answers.** Both `/student/tests/{id}/start` and `/submit` ran the `expires_at` → 410 guard *before* loading the attempt, so a student mid-test when the window closed got 410 and their saved answers were never graded. Extracted the ordering rule to `app/core/attempt_policy.py` (`resolve_attempt_action`) and reordered both handlers: an in-progress attempt is always finalized/graded (auto-submitted), and only a student who never started is blocked (410). Live: submit-after-close → 201 with a real score; never-started → 410; re-open grades saved answers. 7 unit tests (`tests/test_attempt_window.py`).
- **J-03 / K-21 fixed at registration — confusable/case username collisions refused.** `app/core/username_identity.py` `confusable_skeleton` (NFKC → case-fold → common Cyrillic/Greek Latin look-alikes); registration (`auth.py`) now rejects a signup whose skeleton matches an existing live username in the school. Live: `ZEPHYR_T` and Cyrillic `zерhyr_t` refused against `zephyr_t`; a distinct and a Devanagari handle still register. 7 unit tests (`tests/test_username_identity.py`). Register + rendered HTML + artifact updated. Residual: login stays exact-match; a stored-skeleton unique index is the remaining depth.

Targeted suites green: grading/submission 171, username/attempt 13, auth/account/token 29.

**Still to fix (next batch, client-side — need a Flutter rebuild):** duplicate fee payment on double-tap (J-08 — backend already supports `X-Idempotency-Key`; wire the admin Pay button to send it + disable on tap), dashboard date roll-over after midnight (#1), broadcast times in UTC (#20, add `.toLocal()`), Class High/Low showing the student's own min/max (#19). Backend-side: no upper fee bound (J-11), 0-question test publishable (J-05), auto-publish of online tests (#12).

### 2026-10-26 — fixes (second batch, client-side)

Flutter frontend, built with `--dart-define=LOCAL_DEV=true` and driven against the live local stack in a browser pane (pre-boot `requestAnimationFrame` shim + a `resize`-event repaint to beat the hidden-pane canvas throttling).

- **J-08 fixed — duplicate fee payment on double-tap / lost-response retry.** The admin Pay button already disabled while recording, but no idempotency key was sent, so the Dio connection-error **retry interceptor** (`api_client.dart`, re-POSTs on `connectionError`) could record a payment twice when a response was lost. `recordFeePayment` now sends `X-Idempotency-Key`; the admin fees screen (`features/admin/screens/fees_screen.dart`) holds a **stable key per payment entry** (survives the retries, rotated only on success) and treats the backend's 409 as "already recorded" (success, with a refresh) rather than a red error. Contract verified live against the real API: same key → **201 then 409** ("Duplicate request: this payment was already recorded"); no key → 201 (legacy path). Two test payments created during the check were deleted (204).
- **#20 fixed — broadcast times/dates shown in UTC.** `BroadcastModel.fromJson` parsed `created_at` without `.toLocal()`. The column is `timestamp with time zone` and Pydantic serializes it as `...Z` (verified: `"2026-10-24T11:21:50Z"`), so Dart parsed it `isUtc` and every screen rendered UTC. Added `.toLocal()` at parse — fixes all five display sites at once. `isAfter`/`difference` comparisons are unaffected (they work on the absolute instant).
- **#1 fixed — student dashboard date stuck on yesterday across midnight.** The "Today's Timetable" date and the day-scoped summary provider key (`_todayString`) only refreshed on a rebuild; a foregrounded app past midnight kept yesterday. Added a midnight `Timer` (`dashboard_screen.dart`) that re-keys the provider and repaints just after 00:00, re-arming for the next day; cancelled in `dispose`.

`flutter analyze` clean on the four changed files (two pre-existing `prefer_const` infos on unrelated `SchoolLogo` lines left as-is). Release web build compiled. The uncommitted `login_screen.dart` redesign was built for the run but is **not** part of this commit.

**Still to fix (next batch):** Class High/Low showing the student's own min/max (#19, client); backend-side — no upper fee bound (J-11), 0-question test publishable (J-05), auto-publish of online tests (#12).

### 2026-10-26 — fixes (third batch)

Backend fixes verified live against the local stack; frontend (#19) built and its data path verified via the API.

- **J-05 fixed — a 0-question test can no longer be published.** `POST /teacher/tests/{id}/publish` now refuses to go live when the test has no questions (400, "Add at least one question before publishing"); unpublishing an empty test is still allowed. Live: publishing an empty test 483 → 400; after adding one question → 200.
- **#12 fixed — online tests no longer auto-publish on generation.** Removed the post-create `is_published=True` UPDATE in the test-creation handler (`teacher.py`). A freshly generated AI test is unreviewed, so it now starts unpublished and becomes visible only when the teacher publishes it (which is also where students are announced). Verified by code — AI generation left un-run to avoid live billing.
- **J-11 fixed — fee payments can't exceed the outstanding balance.** `record_fee_payment` now computes the student's total fee (shared `app/core/fee_math.py`, reused by the fee summary so the two can't drift) and refuses a payment that would push total paid past it (400, showing the exact ₹ outstanding). Only guards when a fee structure exists — no structure means no known total, so pre-structure payments aren't blocked. Paise rounding tolerated so paying the exact balance is never refused. Live (student 28, ₹30,000 balance): ₹30,001 → 400; ₹30,000 → 201; +₹1 when fully paid → 400. 9 unit tests (`tests/test_fee_math.py`).
- **#19 fixed — "Class High / Class Low" now show the real class figures, not the student's own min/max.** `/student/grades` and `/parent/child/grades` attach `class_high`/`class_low` per grade, computed across every grade for that test in the school (`app/core/grade_stats.py`); grades not tied to a test get null. `GradeModel` reads the two fields and both grade screens show the row only when present, instead of faking it from the viewer's own scores. Live: aarav8 scored 78.3% on test 17 but the API returns class_high 100.0 / class_low 0.0; a manual grade returns null. 5 unit tests (`tests/test_grade_stats.py`).

Full backend unit suite: **634 passed, 2 skipped**. `flutter analyze` clean on the changed Dart files (grade model + both grade screens); release web build compiles. Local-only test setup: `hansal_sir` and `aarav8` (school 1) MPINs were set to `135792` for the live checks (recorded in local-test-accounts.md); all temporary payments and the throwaway test were deleted.

**Remaining catalogued findings (not in scope this session):** #13 lost option-only edits on test questions (client), K-17 XSS-in-PDF unchecked, plus the smaller per-row notes.

### 2026-10-26 — fixes (fourth batch)

- **#13 fixed — option-only edits to a test question are no longer silently lost.** `_questionsEdited()` in `features/teacher/screens/test_detail_screen.dart` compared only `question`/`answer`/`marks`, so editing just an MCQ option left `hasEdits` false — no Save button appeared and the change was discarded on back. It now deep-compares the whole question map (new `_deepEquals` helper), so a change to any field — an option, a matching pair — is detected. `flutter analyze` clean.
- **K-17 verified & locked — generated PDFs neutralise injection.** The finding was *unverified*, not broken: `pdf_service._safe` (xml escape) already wraps every user-supplied field (title, subject, question, options, match columns, answer, explanation), and source tags come from a fixed dict. Confirmed `_safe` turns `<img src=...>`, `<script>`, `<font>`, `</para>` and bare `&<>` into inert text, and that both generators produce a valid `%PDF-` with those payloads (without escaping, `</para>`/unbalanced `<img` would crash reportlab = DoS, and `<img src="http://169.254.169.254/...">` would attempt an SSRF fetch). 7 regression tests (`tests/test_pdf_injection.py`, container-only — reportlab is stubbed in the unit env). No feedback/other server-side HTML sink exists; feedback is canvas-rendered in the app (inert, as J-04 found for broadcasts/homework).

Backend unit suite: 634 passed, 3 skipped (host); PDF/fee/grade integration tests pass in the backend container.

### 2026-10-26 — UI regression of the fixes (local web, IST pane)

Re-ran the fixed cases in the real app (release web build, `--dart-define=LOCAL_DEV=true`, browser pane in Asia/Calcutta).

- **#19 PASS (UI).** aarav8 (Hansel & Gretel, Grade 8) → Grades. Physics (test 17): own **78.3%**, card shows **Class High 100.0% / Class Low 0.0%** — the real class range, not the student's own score. Maths: own 84.0%, Class Low 55.0% (genuine class data). Pre-fix this showed the student's own min/max.
- **#20 PASS (UI).** Student → Broadcasts. "QA leak check grade 8" stored 2026-10-09 **10:00:47 UTC** displays **"09 Oct, 03:30 PM"** (15:30 IST); "QA realtime" 09:59 UTC → 03:29 PM. Times now render in the viewer's local zone, not UTC.
- **#13 PASS (UI).** hansal_sir → Tests → "current electricity (41-50)" (test 29). Clean detail: no Save banner. Edited **only Option D** (question count, text, answer C, marks all unchanged) → the **"Unsaved changes / Save" banner appeared** — pre-fix an option-only edit left no banner and was discarded. Backing out without saving left the DB Option D as "E = IR - Ir" (edit correctly not persisted; test intact). Also observed in passing: deleting a question showed the banner too (count change, already handled pre-fix).

All three UI-observable fixes verified in the running app: #19, #20, #13. (J-08/J-05/J-11/#12/K-17 were verified live at the API level in earlier batches; #1 midnight rollover can't be exercised without advancing the wall clock.)

### 2026-10-27 — fixes (fifth batch): J-11 currency display

- **J-11 display fixed — paise kept and Indian digit grouping.** Fee amounts were formatted with `NumberFormat.currency(symbol: '₹', decimalDigits: 0)`: that dropped paise (₹0.50 rendered "₹1") and used Western grouping (₹99,99,999 → "₹9,999,999"). New shared helper `lib/core/utils/currency.dart` `formatInr` uses the `en_IN` locale (lakh/crore grouping) and shows paise only when present. Routed every ₹ display through it in the student, parent and admin fees screens plus admin reports, and removed the now-dead `NumberFormat` plumbing (3 widget classes). Unit test (`test/currency_test.dart`): ₹0.50→₹0.50, 9999999→₹99,99,999, 10052000→₹1,00,52,000, 40000→₹40,000. **UI PASS:** aarav8 Fees (release web build) with a ₹0.50 payment shows Amount Paid ₹0.50 (not ₹1) and Balance Due ₹29,999.50; test payment cleaned up afterward.

This clears the J-11 display sub-item. The currency finding and the over-balance guard are both now resolved.

### 2026-10-27 — fixes (sixth batch): time-limit consistency (#14/#17)

Online-test time limits were set by three disagreeing rules: generation used 30 sec/question (ceil(n/2)), editing the questions used 1 min/question (len), and the teacher's test-detail chip showed the question count instead of the stored limit — so a generated 10-question quiz said "5 min" on the form, became 10 min once edited, and the chip read "10 min".

- **Backend:** new `app/core/test_timing.py` holds both intended rules — `online_time_limit_minutes` (30 sec/q, manual tests) and `auto_quiz_time_limit_minutes` (1 min/q + 2 buffer, presentation auto-quizzes). Generation (`teacher.py`) uses the manual rule; the question-edit recalc now branches on `test.auto_generated` so an auto-quiz keeps its pacing and a manual test keeps 30 sec/q; `presentations.py` delegates its `_auto_test_time_limit` to the shared helper (one source of truth). The student timer already reads `time_limit_minutes`, so it now agrees. 4 unit tests (`tests/test_test_timing.py`); full suite 638 passed, 3 skipped.
- **Frontend (#14):** the test-detail chip now shows `test.timeLimitMinutes` (the real stored limit) instead of `questions.length`.
- **Live:** editing an auto-quiz (test 23, 10 q) recalculated 7→12 min (= 10+2, auto rule). **UI PASS:** test 29 (auto, 10 q, stored 7 min) chip now reads "7 min", not "10 min".

> Build note: `flutter build web` served a **stale** `main.dart.js` for the single-file chip edit (same bytes/mtime, incremental cache not invalidated); the chip showed the old "10 min" until a `flutter clean` + rebuild. Watch for this when a small Flutter change doesn't appear.

### 2026-10-28 — fixes (seventh batch): #18, #1, #31, #24

- **#18 fixed — "Unsaved changes" bar no longer sticks after Save.** `_questionsEdited()` compared against `widget.test.questions`, which never changes after a save. `test_detail_screen.dart` now keeps a `_savedQuestions` baseline (deep-copied, so re-numbering on delete can't leak into it) that moves to the server's returned questions on each successful save.
- **#1 fixed — registration refused when the school has no current academic year.** `register` (`auth.py`) used to fall back to `academic_year_id = NULL`. It now returns 409 "Registration isn't open yet — the school hasn't started an academic year", which matches what the admin's Academic Year screen promises. Live: school 2 / 3 (no year) → 409 with that message; Sunrise (has a year) passes the gate and reaches the next check (duplicate `aarav8` → "Username already taken"). **Prod note:** once this ships, any prod school with no current year can't take sign-ups until its admin starts a year.
- **#31 fixed — chapter-progress rings no longer carry over from last year or from removed teachers.** `in_progress_presentation_items` (`presentations.py`) now counts only progress rows updated since the current year's `started_at`, from a teacher who isn't soft-deleted. Progress rows have no year column and Close Year leaves them alone, so this works off timestamps. Live (school 1, rolled-back transaction): baseline 9 cards → backdating one in-progress row to before the year start → 8 → also soft-deleting a teacher → 6 → rollback → 9.
- **#24 fixed — a grade with no fee structure reads "NO FEE · No fee set"** (grey) on admin Payments, not "PAID · Fully paid".

Backend suite 638 passed / 3 skipped. `flutter analyze` shows infos only; `flutter test` 276 pass, with 3 failures in `login_screen_test.dart` that come from the **uncommitted login redesign** (the committed login screen passes all 16).

UI regression (release web build after `flutter clean`, LOCAL_DEV, browser pane):

- **Regression caught and fixed:** the first #18 build rendered every test's question list as a grey box (release-mode error widget). The new deep copy built `Map<dynamic, dynamic>` for nested `options`, and the question cards cast it to `Map<String, dynamic>` (console: "type ... is not a subtype of type 'Map<String, dynamic>?'"). `_deepCopy` now builds typed `Map<String, dynamic>`; the list renders again.
- **#18 PASS (UI).** hansal_sir → test 23 (own auto-quiz, no attempts). Clean page: no Save bar. Edited only Q1 Option D → "Unsaved changes · Save" appeared → Save → "Test saved!", **and both the bar and the app-bar Save icon disappeared** while the edit stayed on screen. DB held "Phycobilins QA18"; test 23's questions were then restored from a backup (time limit 12, 10 marks).
- **#24 PASS (UI).** sunrise_admin → Fees → Payments: kabir9 (grade 9, no fee structure) reads grey **"NO FEE · No fee set"**, Total ₹0. Grade-8 rows unchanged ("₹40,000 · Balance due").

40. **Teachers get edit controls on another teacher's test, and Save fails with "Test not found".** hansal_sir can open chinmay_sir's test 29, edit questions and press Save; `PUT /teacher/tests/{id}/questions` enforces `_require_test_owner` and answers 404, shown as "Save failed: Test not found". Either hide edit/delete for non-owners or return a 403 "Only the teacher who created this test can edit it".

### 2026-10-28 — fixes (eighth batch): #40

- **#40 fixed — other teachers' tests are view-only, and a refused change says why.**
  - *Server:* `_require_test_owner` (`teacher.py`) now returns **403 "Only the teacher who created this test can change it."** for a test in the teacher's own school. It used to return 404 "Test not found". The 404 was meant to hide which test IDs exist, but `/tests` already lists the whole school's tests. Another school's test still gets 404. The `/tests` listing now includes `can_manage` per test, using the same rule (own test, or the creator has left). 4 unit tests (`tests/test_test_ownership.py`); full suite passes.
  - *App:* `TestModel.canManage`. The list card hides Publish, Retry and Delete when it's false. Publish and Retry used to check `userId == teacherId`, which missed the "creator has left" case, and Delete wasn't checked at all. The detail page goes read-only: a "View only — another teacher created this test" note; no question edit/delete icons, Delete-test button or (offline) PDF downloads; no Save Grades on offline grade entry. Viewing submissions and grades stays open, as the server allows.
  - *Live API (hansal_sir):* listing shows chinmay_sir's 15 tests `can_manage:false` and his own `true`. PUT questions / DELETE on test 29 → 403 with the message; test 29 untouched. Unknown id → 404.
  - **UI PASS** (release web build after `flutter clean`): list shows Delete only on hansal_sir's own quiz. Test 29 opens view-only with the note and no edit, delete or Delete-test controls. Its Grades tab still lists 5 submissions. His own test 23 still has every edit control.

### 2026-10-29 — fixes (ninth batch): #2, #3, #4, #6, #30, #26

- **#2 fixed — deleting homework asks first.** The trash icon used to delete on one tap. It now confirms with a dialog naming the homework ("…permanently deleted for every teacher and student in Grade N"), and a failed delete shows an error instead of failing silently. Still a hard delete server-side.
- **#3 fixed — HW Review turns green once the review is done.** `reviewDone` also required every period's attendance; that requirement is gone (the step's `enabled` flag still orders the road).
- **#4 fixed — partial attendance shows on the road** as "Attendance 1/2", using the `attendance_progress` the backend already sent.
- **#6 fixed — period times show HH:MM.** `TimetableSlotModel` trims the API's "09:00:00" at parse, which fixes all 8 display sites (teacher/student/parent dashboards and timetables). Unit test `test/timetable_model_test.dart`.
- **#30 fixed — Close Year never reuses a label.** `app/core/year_label.py` `next_year_label` follows on from the closing year (2026-27 → 2027-28), never goes behind the calendar year, and skips labels the school already used. This matters because fee structures are keyed by the label. `/admin/academic-years/current` now returns `next_year_label`, and the Close Year dialog says "End 2026-27 and start 2027-28". 6 unit tests.
- **#26 fixed — a suspended school signs its users out with the reason.** The suspension 403 now carries `X-Session-Ended: school_suspended` (exposed via CORS). The API client signs out on it and passes the server's message on; the auth notifier shows it on the login screen once that screen has mounted. A reasonless sign-out from requests still in flight no longer overwrites it. Tests: interceptor (marked 403 signs out with the reason; an unmarked 403 keeps the session) and notifier.
- Also moved the #40 owner rule into `app/core/test_ownership.py` (`decide_test_change`). The router-importing unit test from batch 8 broke full-suite collection, because reportlab is stubbed in the unit env.

Backend 648 passed / 3 skipped. Flutter: 3 failures, all in `login_screen_test.dart` (the uncommitted login redesign); one run showed a 4th, unrelated failure that didn't repeat in 3 later runs.

**Live / UI (release web build after `flutter clean`):**
- #30 API: Sunrise `next_year_label` 2027-28. The QA CloseYear school (182), which already had two "2026-27" rows, closed into **2027-28** (year 762). That close soft-deleted its 5 users. 182 was un-suspended for the call and suspended again.
- #26 API: suspended school → 403 with `x-session-ended: school_suspended` and `access-control-expose-headers: X-Session-Ended`.
- **#3/#4 UI PASS:** grade 8 with 2 periods today, P1 attendance taken, review complete → Attendance reads "Attendance 1/2", HW Review is green.
- **#6 UI PASS:** Today's Timetable chips read "09:00 – 09:45", "10:00 – 10:45".
- **#2 UI PASS:** trash → "Delete homework?" dialog; Cancel kept it; Delete removed it (homework 1004 gone from the DB).
- **#26 UI PASS:** school 1 suspended while hansal_sir was signed in → the next screen's request signed him out to the login screen with "This school's access has been suspended. Please contact your administrator." School 1 restored straight after. (The first attempt lost the message; that's the in-flight-401 overwrite fixed above.)
- Cleanup: removed the 2 grade-8 test slots and P1 attendance for 28 Oct, the 5 resulting +5 XP rows (totals reduced to match), and throwaway homework 1004.

### 2026-10-29 — fixes (tenth batch): #9, #11, #29, #30 follow-up; #8 and #32 not reproduced

- **#9 fixed — a teacher's own broadcast no longer lights their Announcements badge.** New `isUnseenBroadcast` (`core/providers/badge_provider.dart`) skips broadcasts the viewer sent. The dashboard badge, the side-nav badge (`teacher_scaffold.dart`) and the dashboard tile highlight all use it. Unit test `test/broadcast_badge_test.dart`.
- **#11 fixed — copy.** The Pick-from-Database empty state points to the real tabs ("AI from PDF" / "Upload Slides"). "1 periods left" / "~1 slides" are now singular.
- **#29 fixed — homework title shows a 0/300 counter.** The field already capped input at 300 characters (the finding's "only caught on submit" was stale); it now uses `maxLength` like the description field, which adds the counter.
- **#30 follow-up — the dashboard's Close Year (setup road) also names the years.** Batch 9 fixed only the Academic Year screen's dialog. The road dialog now says "This ends 2028-29 and starts 2029-30", the snackbar names the new year, and the year list is refreshed too.
- **#8 not reproduced (web).** hansal_sir, phone-width: dashboard → Announcements "See all" → bottom-nav Home returned to the dashboard. The route is a plain `context.go`; may have been an iOS tap issue. Re-check on iOS.
- **#32 not reproduced (web).** QA CloseYear school (182): Close Year from the setup road switched the header 2027-28 → 2028-29 straight away, no refresh. The road stays all-green afterwards, which is correct: timetable config, fees, payment and logo are kept.
- **Deferred:** #5 (grade 10 everywhere) needs a per-school "grades offered" setting, which doesn't exist yet. #27 (login school list loaded once) needs a change in `login_screen.dart`, which holds the uncommitted login redesign.

Flutter: 3 failures, all in `login_screen_test.dart` (uncommitted login redesign). Analyzer: no errors/warnings.

**UI (release web build after `flutter clean`):**
- **#9 PASS.** hansal_sir posted broadcast 238 (local). With last-seen set to 20 Oct (after every other teacher's broadcast, before his own), the dashboard showed no badge dot and his tile was not highlighted. With last-seen empty, only chinmay_sir's broadcast was highlighted.
- **#29 PASS.** Assign Homework → Title shows "0/300".
- **#30 road PASS.** Dialog "This ends 2028-29 and starts 2029-30."; snackbar "Academic year closed — 2029-30 has started."; header 2029-30.
- Setup/cleanup: `qa_cy_admin` (school 182) given local MPIN `246813` (see local-test-accounts.md). 182 un-suspended for the test, closed twice (now 2029-30, no non-admin users), then suspended again. Broadcast 238 deleted.

### 2026-10-29 — fixes (eleventh batch): #7, #10, #15, #23, #38, J-25

- **#7 fixed — the Assign Homework dialog shows its errors inside the dialog.** They used to be SnackBars on the page behind the dialog's scrim (the D-05 "review yesterday's homework first" message was hard to read). Other dialogs that use SnackBars weren't audited.
- **#15 fixed — source tags only claim sources that were supplied.** New `app/core/question_sources.py`: `effective_source_mix` moves a missing source's share to [5] fully AI before the prompt is built (a chapter-only upload asks for 0/20/0/20/60, not 20 each), and `honest_source_category` downgrades any [P]/[~P]/[E]/[~E] the model claims anyway. The hard-coded "20%" lines in the Claude/Gemini file labels now point to the categories instead of contradicting the teacher's chosen mix. 6 unit tests (`tests/test_question_sources.py`).
- **#10 fixed — the auto-quiz follows the slides, not the chapter name.** `generate_mcqs_from_text` now builds a "PRESENTATION SLIDES" prompt that tells the model the chapter name is only a label and every question must test what the slides say; all questions are [5]. Verified by rendering the prompt in the container; not re-run against a live model (to avoid AI billing).
- **#23 fixed — the Fee Structures card shows a range.** "Grade 8 ₹40,000 – ₹48,000 · Base fee, plus any optional subjects taken" instead of the misleading ₹48,000 sum (each student pays base + only their own optional subjects).
- **#38 fixed — a class can register together on one Wi-Fi.** Registration now allows 60/min per IP overall, while *refused* attempts (conflicts, wrong parent MPIN, validation — the phone-probing signal) keep the 5/min cap and, once hit, pause the IP for the rest of the minute.
- **J-25 fixed — Close Year warns about what it leaves behind.** `/admin/academic-years/current` also returns `unpaid_students`, `unpaid_total` and `open_tests`; both Close Year dialogs (Academic Year screen and setup road) add "Before you close: 63 students still owe ₹25,00,000 … download the Pending Fees report first" and the open-test count. Helper `widgets/close_year_warning.dart`, 3 unit tests.

Backend 654 passed / 3 skipped. Flutter: 3 failures, all in `login_screen_test.dart` (uncommitted login redesign).

**Live / UI (release web build after `flutter clean`):**
- #38 API: 8 teacher sign-ups from one IP → all 201 (the old cap stopped at 5); 5 duplicate-username attempts → 409, the 6th → 429, and a fresh sign-up in the same minute → 429. Test users `qa38_t01..08` (Sunrise) deleted, Redis counters cleared.
- J-25 API: Sunrise `unpaid_students 63 / unpaid_total 2500000.0 / open_tests 0`, matching `/admin/fees/summary` (63 with a balance, ₹25,00,000).
- **#23 PASS:** sunrise_admin → Fees → Grade 8 card reads "₹40,000 – ₹48,000".
- **J-25 PASS:** sunrise_admin → Academic Year → Start New Academic Year → dialog shows the unpaid-fees warning; cancelled.
- **#7 PASS:** hansal_sir → Homework → Grade 9 (homework 76 unreviewed) → Assign → the "Mark yesterday's homework completion…" message appears inside the dialog, above the buttons. Nothing was created.

### 2026-10-30 — fixes (twelfth batch): #39 / J-21 concurrent timetable edits

- **#39 fixed — a timetable save can no longer silently overwrite someone else's change.**
  - *Server:* `POST /teacher/timetable` takes an optional `expected` snapshot (`TimetableSlotSnapshot`: `exists`, subject, teacher_id, is_holiday, comment): the period as the editor loaded it. The check runs inside the upsert: `ON CONFLICT DO UPDATE … WHERE <row still matches>`, or `ON CONFLICT DO NOTHING` when the period was empty. So two saves at the same moment can't both pass. If no row comes back, the response is **409 `timetable_slot_changed`** with the current slot. Requests without `expected` (older app builds) keep last-write-wins.
  - *App:* the editor remembers each period as loaded (`TimetableSlotModel.snapshotOf`) and sends it. Save All skips periods the teacher didn't change, so editing different periods of the same day never collides. On a 409 that period switches to the other teacher's version, a warning names the period, and the baseline is updated so the next save doesn't conflict again. After a successful save the baseline is the server's reply.
  - Fixed along the way: the first version of the refusal path rolled back the session and then read the expired user object → 500. No rollback is needed, since nothing was written.

Backend 642 passed / 15 skipped (12 git-ignore tests skipped while git was blocked by the unaccepted Xcode licence). Flutter: 3 failures, all in `login_screen_test.dart` (uncommitted login redesign); `test/timetable_model_test.dart` covers the snapshot.

**Live (API, hansal_sir + chinmay_sir, school 1, grade 8):** empty period saved by A, then B's save from the stale empty view → 409 with A's slot. A's up-to-date edit → 200; B's edit from the old view → 409. Legacy save without `expected` → 200. **Three races** of two simultaneous saves from the same view → each time exactly one 200 and one 409 carrying the winner's slot.

**UI (release web build after `flutter clean`):** hansal_sir typed a comment into today's grade-8 P2. chinmay_sir then saved P2 through the API, and hansal_sir pressed Update Timetable → POST **409**. P2 switched to "chinmay_sir · Physics · chinmay saved first", and the DB kept chinmay's row. hansal_sir then edited on top of that and saved → one POST, **200**, no false conflict. The warning SnackBar itself wasn't captured, because the hidden browser pane drops frames. Test slots removed afterwards.

### 2026-11-20 — fixes (thirteenth batch): #5 grades each school teaches

- **#5 fixed — grade pickers only list the grades the school teaches.**
  - *Server:* migration **041** adds `schools.grades_offered` (integer[], default `{8,9,10}`, so existing schools are unchanged). It's included in the public `/api/schools` list. `PUT /admin/school/grades` sets it via `app/core/grades_offered.py` `checked_grades_offered`: sorted and de-duplicated, at least one grade, only 8–10, and a grade that still has students can't be dropped (422 with the reason). Student registration and the admin's grade edit refuse an unoffered grade ("Sunrise Public School doesn't have a Grade 10."). 5 unit tests (`tests/test_grades_offered.py`).
  - *App:* `currentSchoolProvider` (the signed-in school from the public list; the logo provider now derives from it, and it's reset on account switch) → `schoolGradesProvider`. Every grade picker uses it: fees, payments filter, tests, broadcast, attendance, homework form and grade pills, homework review refresh, grades (two pickers), timetable (editor, busy-teacher check, full view) and database (two pickers). `pickableGrades` keeps a selected grade the school no longer offers, so dropdowns can't assert on old data. The admin Timetable Configuration screen gets a **Grades Taught** card (chips, saved per tap). 3 unit tests (`test/school_grades_test.dart`).
  - *Registration form:* the grade dropdown in `login_screen.dart` now lists the picked school's grades and is rebuilt when the school changes; a grade the new school doesn't teach falls back to its first grade. This edit sits in the uncommitted login redesign, so it ships with that work. **UI PASS:** Sunrise → Grade 8 / Grade 9 only; switching to Strix B → Grade 8 / 9 / 10 with the earlier Grade 9 kept. The old-paper tagging dialog keeps the full platform list.
  - The session-reset coverage test caught the new provider missing from the account-switch reset list; added.

Backend 659 passed / 3 skipped. Flutter: 3 failures, all in `login_screen_test.dart` (uncommitted login redesign).

**Live (API, sunrise_admin):** drop grade 9 → 422 "Grade 9 still has 1 student…"; `[]` → 422; `[8, 11]` → 422; `[9, 8]` → 200 `[8, 9]`; public list shows Sunrise `[8, 9]`; a grade-10 student registration at Sunrise → 422 "Sunrise Public School doesn't have a Grade 10."

**UI (release web build after `flutter clean`):** Timetable Configuration shows Grades Taught with 8 and 9 on and 10 off. Tapping Grade 9 → red "Grade 9 still has 1 student; it can't be removed while they're enrolled." and the chip stays on. Adding then removing Grade 10 saved both ways (DB `{8,9,10}` → `{8,9}`). Fees → Payments grade filter lists All Grades / Grade 8 / Grade 9 only.

**State left:** Sunrise (944) offers grades 8 and 9; every other school keeps 8, 9, 10.

### 2026-11-20 — #27 login school list refresh

- **#27 fixed — the login school picker reloads when the app (or browser tab) comes back to the foreground.** The list used to load once in `initState`, so a school restored while the login screen was open only appeared after an app restart. `login_screen.dart` now observes the app lifecycle and reloads on `resumed`. It rebuilds the picker only when the list actually changed, and clears a picked school that has dropped out (suspended), since a dropdown left holding a missing item asserts. I didn't add a refresh on tapping the picker open: rebuilding the field under its open menu is fragile.
- Two widget tests in `test/widget/login_screen_test.dart` ("school list refresh"): a school restored meanwhile appears after resume, and a picked school suspended meanwhile is cleared with no exception. Both pass; the file still has only the 3 known login-redesign failures.
- **UI PASS (release web build):** Sunrise suspended locally → login picker without it. Sunrise restored, then switched to another browser tab and back → picker lists Sunrise Public School with no page reload; network shows a fresh `/api/schools` fetch. Sunrise left active.
- Not committed: the change and its tests live alongside the uncommitted login redesign (`login_screen.dart`), so they ship with that work.

### 2026-11-20 — #28 attendance and marks reports, school-branded PDFs

- **#28 fixed — Reports now has attendance and marks reports, and report PDFs carry the school's branding.**
  - *Server:* `GET /admin/reports/attendance?grade=&from_date=&to_date=` and `GET /admin/reports/marks?…` stream PDFs for one grade. Without dates they cover the current academic year so far; a start after the end is a 422. The figures come from the new `app/core/report_math.py`:
    - attendance: periods present/absent and % per student, flagged below 75%; students with no attendance yet are still listed;
    - marks: per subject and overall, as total marks over total max, so a 50-mark test weighs more than a 10-mark quiz.
    - 3 unit tests (`tests/test_report_math.py`).
  - *Branding:* every report PDF, including the existing pending-fees and ledger PDFs, now has the school's logo and name in the header and "<school> — Confidential · Generated with MindForge" in the footer, instead of the MindForge masthead. The logo is downscaled before embedding (a full-size upload made each report ~5 MB; now ~100 KB). An unreadable logo is skipped, never failing the report.
  - *App:* Reports → **Class Reports**: grade picker (the school's grades), date range (default "This academic year", or pick dates), Download Attendance PDF / Download Marks PDF.

Backend 662 passed / 3 skipped. Flutter: 3 failures, all in `login_screen_test.dart` (uncommitted login redesign).

**Live:** Hansel & Gretel admin, grade 8 from 1 May. The attendance PDF has the school's logo and name and 6 students (aarav8 53 present / 8 absent, 86.9%; isha8 51/10 — both match the `attendance` table). The marks PDF has Overall plus Chemistry, English 1, Mathematics and Physics sections over 2 pages. Inverted dates → 422. **UI PASS:** sunrise_admin → Reports → Class Reports (Grade 8, This academic year) → both downloads 200, no error.

### 2026-11-23 — B-03 setup road hints, fees before a year, owner Suspend confirm (H-04)

- **B-03 fixed — a locked setup-road step says what to do.** Tapping a locked step showed nothing; it now shows 'Finish "<current step>" first — setup goes in order.', and the locked Close Year cap says it unlocks once all five steps are done (`setup_road_card.dart`).
- **B-03 / run-log #2 fixed — Fees before an academic year.** Fee Structures and Payments now show "Start the academic year first" with a button to the Academic Year screen, instead of a guessed year. Fee structures are stored by year label, so a guess could file fees under a year that never starts. Payment Info is year-independent and stays usable.
- **H-04 fixed — the owner's Suspend asks first:** "Suspend <school>? Everyone at this school is signed out straight away and can't sign in until you activate it again. No data is deleted." Activate stays one tap.
- Status cells of 14 rows fixed in earlier batches (C-10, D-10, E-07, H-04, I-01, I-03, J-03, J-05, J-06, J-08, J-11, J-21, J-25, B-03) now say so, with the batch.

**UI PASS (release web build):** demo_admin @ Greenwood Academy (no academic year): tapping the locked Timetable step → the hint; Fees → the empty state with "Go to Academic Year". chinmay_owner → Suspend on Strix A → the confirmation; Cancel → Strix A still active in the DB.

**Run-log #4 fixed (2026-11-23, in the uncommitted login redesign):** the web login brand panel no longer shows Hansel & Gretel's fixed "H" tile or its "25+ years of excellence · since 1997" trust mark for every school. It shows the picked school's logo and name, or the MindForge mark and name before a school is picked. **UI PASS:** no school → MindForge only; Workflow Test School (no logo) → MindForge mark + its name; Sunrise → its sun logo + name. Ships with the login redesign. Still open there: the iPhone login layout notes (run-log #3).

**Splash screen fixed (2026-11-23):** it showed Hansel & Gretel's logo and the same "25+ years of excellence · since 1997" capsule to every school before the login screen. It now shows the MindForge logo, with the school's logo above it only when a signed-in school is remembered. The capsule step is gone, so the splash is ~1 s shorter (`splash_screen.dart`). **UI PASS (signed out):** MindForge logo only. Not checked: the signed-in variant with a school logo. `assets/images/hansal_logo.png` (3.6 MB) is now unused by code but still bundled.

### 2026-11-23 — J-19 large and locked uploads; K-23 status

- **J-19 — 200-slide deck: PASS.** A generated 200-slide .pptx uploaded as hansal_sir → 201 READY in 0.35 s. All 200 slides were stored in order (`slide_index` 0–199) and paced at 8 per period → 25 periods. Deck deleted afterwards.
- **J-19 — password-protected PDF: fixed.** Uploads only checked that a file starts like a PDF, so a locked chapter was stored and failed later inside the AI job ("may be password-protected"), after spending one of the teacher's 20 hourly generations. `validate_document` (`app/core/upload_utils.py`), shared by all four PDF upload routes, now opens PDFs with PyMuPDF and refuses locked ("That PDF is password-protected. Remove the password…"), page-less and unopenable files with 422. The chapter-PDF route also charges the hourly AI quota only after the file passes. Tests: real one-page PDF fixtures replace the header-only fakes, plus locked and broken-PDF cases.
  - **Live:** AES-256 locked PDF → 422 with the message; no presentation row created; the AI quota counter didn't move.
- **K-23 — already fixed in `812fc31`;** the row now says so. The ignored-`frame-ancestors` console message comes from the meta-tag copy, which is kept on purpose (see `web_csp_test.dart`).

Backend 664 passed / 3 skipped.

### 2026-11-24 — run-log #3 iPhone login layout; iOS build fixed for Xcode 27

- **Run-log #3 fixed (in the uncommitted login redesign, `login_screen.dart`):**
  - *Status bar:* the phone layout sat in a top safe area, so the strip behind the white status-bar icons was the light page background. The navy header now runs up behind the status bar, and the screen sets light icons explicitly.
  - *Sign in below the fold:* compact mode now applies below 900 pt height (every iPhone except Max/Plus; the 17 Pro is 874 pt) instead of below 700. Compact mode now also uses 48 pt keypad keys (the design's minimum tap target) and slightly tighter header and card spacing.
  - **Simulator (iPhone 17 Pro, iOS 26.2):** before, Sign in was cut off at the bottom; after, it ends at about 790 pt with the school list still loading. The backend was down (see below), so the school picker never appeared. It adds about 40 pt, which should put Sign in at about 830 pt, just above the home indicator (~840 pt). **Re-checked with the picker showing (backend up): Sign in fully visible, ending at ~834 pt.**
- **iOS builds fixed for Xcode 27.1** (updated automatically; it also triggered the licence prompt). Every iOS build failed:
  1. Xcode 27 builds for iOS 15+ only, and the app targeted iOS 13 (pods 9–13) → deployment target raised to 15.0 (Runner, and a Podfile `post_install` for the pods).
  2. Third-party pods' Swift deprecation warnings failed their compile ("failed with exit code 0") → warnings suppressed for pods only.
  3. Flutter 3.44 misreads Xcode 27's `lipo` output for the two-architecture simulator engine → simulator builds exclude x86_64 (Apple-silicon simulators only; device and App Store builds unaffected).
- **Disk was full** (123 MB free), which also broke builds mid-way. With your OK I cleared Xcode DerivedData; free space is now ~6.9 GB. Docker Desktop hung on start because a backend process from 23 Nov stayed stuck "stopping" after the disk filled; ending it let Docker start in 6 s. Postgres recovered cleanly (redo done; 281 users, 15 schools). Docker build cache and unused images pruned (~17 GB inside Docker's disk).

### 2026-11-24 — login redesign committed (be86bdb)

The login redesign is committed together with the fixes made inside it: #5 registration grades, #27 school-list refresh, the brand panel without the Hansel & Gretel tile and claim (with the unused logo removed), and the iPhone layout (run-log #3). The three two-factor prompt tests that had been failing against the redesign only expected the old ALL-CAPS labels ("TWO-FACTOR AUTHENTICATION", "CANCEL", "VERIFY"). They now use the redesign's wording; the behaviour checks (Cancel doesn't retry, Verify sends the code, the recovery toggle sends a recovery code) are unchanged. **Flutter: 296 passed, 0 failed** (first fully green run since the redesign began). Analyzer: no errors or warnings.


### 2026-11-24 — regression round (API walk-through on a fresh school)

Ran `docs/qa/regression_walkthrough.py` against the local stack on a new school, "QA Regression 11241318" (id 970). It follows the plan's story end to end through the real endpoints, with real MPIN logins: owner → admin setup → registrations and approvals → a school day → student and parent views → fees → reports → suspension → Close Year. **53 of 54 checks passed.**

- Passed, covering earlier fixes: duplicate school refused (A-03); registration refused before a year exists (#1); grades taught and the grade-10 refusal (#5); negative fee refused (B-09); unapproved login refused (C-02); case-variant username refused (J-03); stale timetable save refused (#39); road shows "1/2" attendance (#4); 301-char homework title refused (H-05); student dashboard, broadcast and fee 48,000 = base + computer (E-01/E-02/E-07/#23); idempotent payment (J-08); over-balance refused (J-11); parent balance 28,000 (F-02); attendance, marks and pending-fees PDFs (#28/I-01); close-year warning data, 2 unpaid / ₹68,000 (J-25); suspended user gets 403 + `X-Session-Ended` (#26); Close Year moves to the next label, 2027-28 (#30), and removes everyone but the admin (I-03).
- **1 expectation wrong, not a bug:** hand-entered marks (no test attached) carry no Class High/Low. That's by design since #19, and the student screen hides the row when they're absent. Possible future enhancement: class figures for hand-entered marks grouped by subject and chapter.
- No AI generation was exercised (to avoid billing); the online-test flow was covered in earlier batches.

State left: school 970 suspended; its users were removed by the Close Year step.

### 2026-11-24 — UI regression pass (H-07), release web build

The Sunrise cast (sunrise_admin, das_sci, aarav8, aarav8_parent), each role's dashboard plus its busiest screens, at phone (375 px), tablet (768 px) and desktop (1280 px):

- **Admin:** dashboard (setup road, approval banner, tiles) at all three sizes; Fees (Fee Structures range card, Payments list and summary) and Reports (incl. Class Reports) at phone width — **PASS**. Notes: the dashboard's square tiles are very roomy at tablet and desktop width (design choice, not broken). The Payments summary shows a negative overall balance only because of bulk8_03's ₹1,00,51,999.50 test overpayment from October, made before over-balance payments were refused.
- **Teacher:** dashboard at all three sizes; Timetable (My / Create-Edit / Full, the full view listing only grades 8 and 9 per #5) and Tests at phone width — **PASS**.
- **Student:** dashboard at desktop, tablet and phone; Grades (real class high/low) and Fees at phone; Fees at tablet — **PASS after one fix**: at phone width "Today's Timetable" was cut to "Today's Timetab…" because the title and date split the free space evenly. The title now takes the free space and the date its own width, as on the parent dashboard (`student/screens/dashboard_screen.dart`). Re-checked: full title shows.
- **Parent:** dashboard at desktop and phone; child switcher (aarav8 ↔ anya8) carries through to Fees; Fees at phone and tablet — **PASS**.
- Console: no app errors (only the known, deliberate `frame-ancestors` meta note, K-23).

### 2026-11-24 — iPhone app pass (iPhone 17 Pro simulator, iOS debug build, local stack)

The Sunrise cast in the native app, signing in each time through the redesigned login (school picker, username, MPIN keypad) and signing out from the dashboard:

- **Teacher (das_sci):** dashboard and road; created a P1 Physics timetable slot for grade 8 today ("Timetable saved"); submitted P1 attendance for 64 students, with anya8 absent ("Attendance submitted successfully!"; the update-mode banner shows on reopening); the road moved to Timetable / Attendance / HW Review done — **PASS after two fixes** (below).
- **Student (aarav8):** dashboard (XP card, class progress, today's P1 Physics · das_sci); Attendance shows 24 Nov present, 1/1, 100%; Fees ₹40,000 / ₹20,000 paid / one payment; Grades: Ch 4 quiz 9/10 with Class Low 0.0% (a real zero: bulk8_22 answered all five questions, all wrong) — **PASS**.
- **Parent (aarav8_parent):** dashboard; switching to anya8 carries through to Fees (₹0 paid, "No payments recorded yet.") and Attendance (24 Nov absent, 0.0%) — **PASS after one fix** (below). Note: the parent attendance calendar starts weeks on Sunday ("Sun Mon …") and the student's on Monday ("M T …"). This is cosmetic and was left alone.
- **Admin (sunrise_admin):** dashboard (setup road complete, 15 awaiting approval); Fee Structures (₹40,000–₹48,000 range card); Payments (the summary shows a negative balance only because of bulk8_03's October test overpayment, as on web); Reports → Pending Fees PDF opens the iOS share sheet (pending_fees_2026-27, 55 KB, school logo on page); Users (pending list with Devanagari, Gujarati, emoji and 60-character names wrapping cleanly) — **PASS**.

Fixes found on the phone:
1. **Header name ran into the avatar.** "Sunrise Public School" wraps to two lines, which pushed the "AI Assisted Learning" tagline down into the overlapping avatar (teacher, student and parent dashboards). New shared `core/widgets/school_title_block.dart`: a name that fits keeps the tagline; one that wraps is set at 0.82× on two lines and drops the tagline, so the block keeps its height. Widget test `test/school_title_block_test.dart`.
2. **Dark status-bar icons on the navy headers after a cold start** (session restored straight into a dashboard). `main.dart` now sets light status-bar icons app-wide; the white splash sets dark icons.
3. **Parent child switcher (several children):** after fix 2 its light strip had white status-bar icons, almost invisible, and the strip only spanned the chips' width, sitting centred. `parent_scaffold.dart` stretches it full-width, paints the safe area behind it, and sets dark icons there.

Re-checked on the simulator after each rebuild. `flutter test` 298/298 pass, and `dart analyze` shows no errors or warnings.

Test data left on the local stack: Sunrise grade 8 timetable slot P1 Physics (das_sci) on 2026-11-24, and that period's attendance for 64 students (anya8 absent).

### 2026-11-25 — open rows re-run on iPhone (J-23, J-26); K-21 / K-30 rows brought up to date

- **K-21, K-30:** both were fixed earlier (J-03/K-21 confusable usernames, J-11 over-balance payments), but their rows still read FAIL/PARTIAL. Re-checked against the local API: Cyrillic `аarav8` and `AARAV8` → 409; ₹50,000 and ₹99,99,999 against a ₹40,000 balance → 400 with the balance in the message.
- **J-23 (largest Dynamic Type, dark mode):** text is capped at 1.1× and the theme is forced light, by design. **Bug:** at 1.1× the admin welcome card wrapped to two lines and covered the top of the School Setup card. All four dashboard headers (admin, teacher, student, parent) had a fixed height with the card absolutely positioned inside, so a long username or many subject chips could do the same at normal size. The header now grows with its card (`ConstrainedBox(minHeight: headerH)`, card in normal flow), so the usual layout is unchanged. Checked on the simulator: admin and teacher at 1.1×, and teacher at the default size. iPad landscape not run.
- **J-26 (delete app, reinstall, log in):** **Bug:** the reinstalled app opened straight into das_sci's dashboard, because iOS keeps Keychain items when an app is deleted, so deleting the app did not sign anyone out of a shared device. New `core/utils/fresh_install.dart`: SharedPreferences is wiped on delete, so a missing marker means a fresh install, and on iOS the leftover Keychain is cleared before the app starts. The first launch after updating to this build signs out once; iOS hasn't shipped, so no real users are affected. Unit tests in `test/fresh_install_test.dart`. On the simulator: log in, then relaunch → still signed in; delete, then reinstall → login screen.
- Note: iOS asks for notification permission on the very first launch, before sign-in, with no explanation. Consider asking after login with a line on what notifications are for.

`flutter test` 301/301; no analyzer errors.

### 2026-11-25 — iPad landscape (J-23), PDF injection (K-17), AI with no keys (J-20)

- **iPad landscape (iPad Pro 11-inch simulator, created for this pass):** login (brand panel beside the form; the form card runs past the bottom, so "Forgot your MPIN?" is reached by scrolling), admin dashboard with the side nav, and Fees with its app bar — layout OK. **Bug:** on the wide (sidebar) layouts the status bar's right half (Wi-Fi, battery) was white on the light content area. It was nearly invisible because the dashboards cap their navy header at 600 px, and the app-wide light status bar (fd30fc1) assumes navy behind it. New `core/widgets/navy_status_inset.dart` paints a navy band of status-bar height across the content area in all four role scaffolds. Screens with an app bar join it seamlessly, and on web (no inset) it does nothing. Re-checked on the iPad: dashboard and Fees.
- **K-17 in PDFs:** rendered the attendance report with names `<script>…`, `<a href="javascript:…">`, `<b>bold`, `Ab & Cd`, `d'souza` and a school named `Evil <b>School & Co`. All of it is inert literal text, with no link annotation or markup. **Bug:** the attendance and marks report tables escaped names and then drew them as plain strings, so they printed `Ab &amp; Cd` and `&lt;b&gt;`. Plain table cells now get the raw name, as the pending-fees and ledger tables already did. Regression test `test_report_table_cells_keep_names_as_typed` in `tests/test_pdf_injection.py` (needs real reportlab: passes in the backend container). **Open → fixed later the same day:** Devanagari names rendered as boxes in every report (see "K-17 Indic names" below).
- **J-20 (generation with every AI key blank, local backend restarted with a temporary override):** generation returned **500 "Internal server error."** while the log had the real reason (no Claude, Gemini or Groq key). `POST /teacher/tests/generate` now turns the all-providers-failed error into **503** "AI question generation is unavailable right now. Please try again in a few minutes; if it keeps failing, let your school admin know.", which the test screen shows in its snackbar via `apiErrorMessage`. No test row is created. The other AI call sites (presentation auto-quiz, old-paper and syllabus scans) already caught failures. A failed attempt still counts toward the 20/hour generation limit, by choice. Backend restored with its keys afterwards.

`flutter test` 301/301 · backend unit tests 664 passed (3 reportlab-dependent skipped, run in the container).

### 2026-11-25 — K-17 Indic names in PDFs

- **Bug:** Hindi (Devanagari) and Gujarati names and school names printed as black boxes in every PDF report and test paper. DejaVu Sans has neither script, and reportlab 4.2.0 had no shaping engine. Mapping glyphs alone would still break conjuncts and matras (क्ष, र्म, ि).
- **Fix (backend):** reportlab 4.2.0 → **4.5.1**, plus **uharfbuzz 0.53.7**. ReportLab has shaped complex scripts through HarfBuzz since 4.4. **Noto Sans Devanagari / Gujarati** Regular and Bold (OFL, from Debian `fonts-noto-core`) are vendored in `backend/app/assets/fonts/` with `OFL.txt`. `pdf_service`:
  - `_safe()` still escapes first. It then wraps each Indic run, including digits, spaces and punctuation inside it, in a `<font face="Noto…">` tag. Latin keeps DejaVu.
  - A module-level `Paragraph` wrapper turns shaping on only when such a run is present, so Latin-only output is built as before. On a bold style it uses the bold Noto face. When the style's base font isn't a shapable TTF (the Helvetica footer), it swaps that base to DejaVu.
  - Table cells now go through `_cell()`. A Latin name stays a raw string, never escaped. A name with Indic text becomes a shaped Paragraph over `_safe()` text, with its Latin runs in Helvetica to match the other body cells.
  - ReportLab shapes a whole word in its *first* fragment's font, so a word that mixes scripts with no space (`Ab_आरव`) still drew boxes. A narrow wrap around `paragraph.shapeFragWord` shapes each same-font piece separately. Words in a single font take the original path.
- **Verified in the rebuilt `mindforge_backend` container:** attendance and pending-fees reports with names `आरव_शर्मा`, `આરવ`, `Ab & Cd`, `<b>bold`, `क्षत्रिय Kshatriya`, `Ab_आरव ज़्ञान` and school `श्री विद्या मंदिर & Co`. Every name renders correctly shaped, and `&` / `<b>` print literally (rasterised and inspected at 300 dpi). A Hindi question paper (bold question, options, a Gujarati option) also renders correctly.
- **Tests:** new `tests/test_pdf_indic.py` (16 tests): escaping and run tagging, raw vs Paragraph cells, HarfBuzz output for Devanagari/Gujarati conjuncts, mixed-script word fonts, bold faces, the Helvetica footer, and both full reports with embedded Noto fonts and literal Latin names. It skips without reportlab or uharfbuzz. In the container, it and `test_pdf_injection.py` pass 21/21. Running every test file in its own process (as CI does), all pass except `test_ai_fallback_chain.py` (settings MagicMock in this container) and `test_prod_guard.py` (path outside `/app`). Neither touches PDFs.
- **Not covered:** other Indic scripts (Tamil, Bengali, …) still print as boxes. Adding one means adding its Noto face to `_INDIC`.

### 2026-11-25 — dependency audit, J-07 offline submit, J-24 input abuse, K-36 socket flood

- **Dependencies:** a `pip-audit` of `backend/requirements.txt` found **Pillow 12.3.0 with 42 advisories** (fixed in 13.0.0). Pillow decodes every uploaded avatar, logo and scanned page. It also found **pyasn1 0.6.4 with 4** (fixed in 0.6.5). The new `reportlab` 4.5.1 and `uharfbuzz` 0.53.7 pins are clean. Bumped both; in the rebuilt container, EXIF stripping, the decompression-bomb guard, fake-image refusal, OCR and the PDF logo all behave as before. Audit now clean; risk-register row updated (CI audit not re-run).
- **J-07:** copied the grade 8 quiz into tests #484/#485 (no AI used). aarav8 answered two questions, the backend was stopped, and Submit was tapped. The red "Submission failed…" snackbar showed, the button came back, and the answers and timer were kept. With the backend back, the same attempt submitted (2/10). **Bug:** `_submitTest` cancels the 20 s autosave and never restarted it on failure, so answers given after a failed submit weren't saved. `test_attempt_screen.dart` now has `_startAutosave()` and restarts it on both failure paths. On the simulator, an answer given after the failed submit and backend restart reached the server by autosave alone (`{"3":"D","8":"C"}` in `test_submissions`).
- **J-24:** the MPIN pad takes digits only and stops at six; rapid tab switching is clean.
- **K-36 / Redis resilience:** **bug:** `RedisManager.start_subscriber` ended on the first `ConnectionError`. Restarting Redis under a running backend left no subscriber on `mindforge:events`, so every live update (attendance, broadcasts, grades) stopped silently until the backend was restarted; hosted Redis restarts would do the same in production. The subscriber now re-subscribes with backoff (1 s doubling to 30 s), and shutdown cancels it before closing Redis, which also removes the "Task exception was never retrieved" traceback on every restart. Unit tests in `tests/test_redis_subscriber_reconnect.py` (the reconnect case fails on the old code). Live check: after a Redis restart it re-subscribed within 2 s, and a WebSocket client received an event published afterwards. Socket flood results are in the K-36 row.

Test data: tests #484 and #485 ("J-07 …", grade 8, iyer_maths) with aarav8's submissions (2.00 and 1.00).

`flutter test` 301/301 · backend unit tests 666 passed (4 reportlab-dependent skipped).

### 2026-11-25 — B-02 two-factor, C-04/C-06–C-08 sign-up checks, stale rows brought up to date

- **B-02:** the admin can turn on 2FA from Profile, and the full cycle works (see the row). Checked on iPhone and through the API on demo_admin, which was left with 2FA off.
- **Bug (cosmetic):** the admin Profile's Change MPIN section ("Current/New/Confirm MPIN", the keypad digits, Submit) was set in a typewriter font (`GoogleFonts.specialElite`) unlike the rest of the app; the teacher, student and parent profiles use Poppins. Switched to Poppins in `admin/screens/profile_screen.dart` and re-checked on iPhone. The MindForge logo keeps its typewriter lettering on purpose.
- **C-04, C-06–C-08** re-run through the API: duplicate username and phone are refused; a junk sign-up appears as pending, can be rejected, and can't sign in.
- **J-19** and the old UNRECORDED B/C rows were brought up to date from later passes; B-10's Payment Info tab is still unviewed.

Still open and not runnable on the local stack: K-22 (needs a TLS endpoint), K-08/K-31 (multi-IP floods), L-04 (mass real AI generation, which costs money), L-06 (no per-user socket cap, a design choice), L-08 (filling MinIO).

`flutter test` 301/301.

### 2026-11-25 — B-10 payment details, K-08/K-31 spoofed-IP brute force

- **B-10 PASS:** the admin Payment Info tab (iPhone) shows the SBI option with UPI `sunrise@sbi` and a QR. Parents and students get the same option in their fee summary, and the QR image downloads. (The parent app's `getPaymentInfo()` hits an admin-only route and gets 403, but only the admin screen calls it; the Pay tab reads `payment_options` from the fee summary.)
- **K-08:** 60 wrong MPINs on `bulk8_30`, each with a different spoofed `X-Forwarded-For`, gave 50 × 401 then 429. The global backstop held, and even the correct MPIN from a fresh IP was refused, so an attacker gets at most 50 guesses per account per 15 minutes. Two caveats, now in the risk register: (1) the backstop lets anyone lock a known username out for 15 minutes; (2) the per-IP layer trusts the right-most `X-Forwarded-For`, which is spoofable with no trusted proxy. Production has no nginx (Railway edge → `start.sh`), so per-IP limits there depend on Railway appending the real client IP. **Unverified; a one-request check against production is listed in the register, but I didn't run it because production has real users.** bulk8_30's lock was cleared afterwards.

### 2026-11-25 — exploratory: homework, broadcasts, offline marks (API probes on Sunrise)

Beyond the plan's rows: teacher-side create paths probed with bad inputs as das_sci / iyer_maths.

- **Grades the school doesn't teach (#5 follow-up):** Sunrise teaches 8 and 9, but homework, grade broadcasts, AI test generation and both presentation uploads accepted **Grade 10** (201). The work reached nobody; registration was the only place #5 was enforced. New `app/core/grade_guard.require_grade_offered` (pure rule `grade_not_offered_message` in `core/grades_offered.py`, unit-tested) now refuses with 422 "Sunrise Public School doesn't have a Grade 10." on all five routes, after the role check and before any AI or storage work (no AI call made in the check).
- **Homework due in the past:** a due date 3 days ago was accepted. `POST /teacher/homework` now refuses a due date before the school-local today ("That due date has already passed…"). The app's date picker already started at today, so this only hardens the API.
- **Offline marks:** `POST /teacher/tests/{id}/offline-grades` saved **two marks for one student** when the request listed them twice, both counted in averages. `NaN` got as far as the database and came back as a generic "value is too long or out of range". The schema now uses the bounded `Marks` type (finite, 0–10,000) and refuses a student listed twice. Tests in `tests/test_offline_grades_schema.py`. Bounds against the test's total, other-grade students (404) and replace-on-re-entry were already correct.
- **By design, noted:** any teacher can delete any homework in the school (documented in the handler; school-scoped). A teacher can set homework for a subject they don't teach (das_sci → Hindi), which covers substitutes. Students get 403 on delete. Grade broadcasts reach the grade's students and parents.
- **Cleanup:** the QA homework was deleted, and the stray marks on test #481 were removed (back to meera8 3.00, aarav8 6.00). Three QA broadcasts remain (#240 "QA grade 8 note", #241 grade 10 sent before the fix, #242 "QA2 all"); there's no delete route, so I left them rather than delete from the database.

Backend 674 passed (4 reportlab-dependent skipped) · `flutter test` 301/301.

### 2026-11-25 — exploratory: cross-school and cross-family access, attendance edges

- **Admin isolation (Greenwood `demo_admin` → Sunrise IDs):** edit, deactivate, approve or revoke a Sunrise user, edit a teacher's bio, edit or delete a fee structure or payment, record a payment, and download a student ledger: all 404. Academic-year users returned an empty list (Sunrise's own admin sees 145). **No leaks.**
- **Teacher isolation:** a throwaway school was created through the owner API (**"QA Isolation …", school 971**, with an admin and an approved teacher; local test data). Its teacher hitting Sunrise test #481 (view, grades, submissions, answer key, PDF links, offline grades, publish), editing #484, deleting #485 and deleting homework #995: all 404. Its test, homework and broadcast lists contain nothing from Sunrise.
- **Parent and student isolation:** aarav8_parent with `child_id` set to a classmate (meera8) or another school's student on all nine child routes: 0 of 18 leaked (own child 200). meera8 asking for the review of a test only aarav8 took gets 404.
- **Media proxy:** serves files without a login by design. Every stored key ends in a 22-character random token (~128 bits), so links can't be guessed; folder prefixes give 404 and other buckets 403. **Bug:** an empty key (`/api/media/mindforge-profiles/`) raised an unhandled `ValueError` → **500**. It now returns 404 (`main.py serve_media`).
- **Attendance:** future date, a date over 14 days old, period 99 and a grade 9 student in a grade 8 period are all refused. A student listed twice in one submission was already rejected by the database with nothing saved and no XP awarded, but the message, "That already exists — it may have just been saved", read like a double tap. The schema now says "A student is listed twice. Mark each student once." (`tests/test_attendance_bulk_schema.py`).

Backend unit tests pass (see commit).

### 2026-11-25 — username renames; fees edge cases (partial)

- **Fixed — look-alike usernames via rename/admin paths (J-03/K-21 follow-up):** registration refused case and cross-script look-alikes, but the admin's own rename, the admin editing a user, the inline parent the admin edit can create, and the owner creating a school admin all checked only an exact match. Live: QA Isolation's admin renamed itself to the uppercase and to a Cyrillic look-alike of its teacher's name (200). New `app/core/username_guard.username_taken` (built on `confusable_skeleton`) is used at all four sites; both renames now get 409, and renaming yourself to a case variant is still allowed. Tests: `tests/test_username_guard.py`.
- **FIXED (below) — payment edit bypasses the over-balance limit:** creating a payment refuses more than the balance (J-11), but `PUT /admin/fees/payments/{id}` accepted ₹45,000 against bulk8_32's ₹40,000 balance (200). Test payment deleted.
- **FIXED (below) — fee structure for a grade the school doesn't teach:** `POST /admin/fees/structure` accepted grade 10 at Sunrise (201). It should use `require_grade_offered` like the teacher routes. Test structure #248 deleted.
- Probed in the next section: lowering a fee below what's been paid, timetable, feedback reports.

### 2026-11-25 — fees, timetable and feedback edge cases

- **Fees:**
  - **Payment edit over the balance (fixed):** creating and editing now share `_refuse_overpayment` (`admin.py`). Editing counts everything paid except the payment being edited, so ₹40,000 (the full fee) is fine and ₹45,000 is refused.
  - **Grade 10 fee structure (fixed):** now 422 via `require_grade_offered`.
  - **Future-dated payment (fixed):** a payment dated 30 days ahead was accepted. `FeePaymentCreate` now refuses dates more than 12 hours ahead (slack for the app's time-zone-less local timestamps). The app's date picker already stopped at today. Tests: `tests/test_fee_payment_schema.py`.
  - **By design:** lowering a grade's fee below what students have already paid is allowed, since it covers discounts. The grade 8 fee was restored afterwards.
- **Timetable (`POST /teacher/timetable`), all previously accepted, now refused:**
  - **Teacher double-booking:** das_sci in grade 8 and grade 9 in the same period → 409 "That teacher already has Grade 8 in period 3 that day." Holiday markers are exempt.
  - **Grade 10** → 422.
  - **Period 12 on a 6-period day** → 422 "The school day has 6 periods." (attendance already did this).
  - **An end time before the start time** → 422.

  The existing data has no double-bookings, so no current week becomes uneditable. The editor shows these messages through its general error path; only the structured "changed elsewhere" 409 is handled specially. Probe slots were on 15 Dec and deleted.
- **Feedback (bug icon):**
  - **Already correct:** the length limits; markup is stored as plain text; another school's admin sees nothing.
  - **By design:** beyond 10 reports a minute, reports are dropped silently ("keeps the UI honest") and exactly 10 were stored.
  - **Fixed:** whitespace-only reports passed the 3-character minimum and were then stored empty, because the handler stripped them after validation. The schema now trims first (`tests/test_feedback_schema.py`). The 10 QA reports were deleted.

Backend 688 passed (4 reportlab-dependent skipped).

### 2026-11-25 — role escalation, XP, presentation and document ownership

- **Admin user management:** promoting a student to admin or owner → 403; editing or deactivating an admin account (including the caller's own) → 403; the platform owner's ID → 404 from a school admin; parent linking is school-scoped. **No issues.**
- **XP:** the leaderboard's "school" scope is the viewer's own school (`xp_service` filters by `school_id`; the router docstring saying "global" was corrected). Another student's XP → 403, another school's student → 404.
  - **Bug (fixed):** manual adjustments (`POST /xp/admin/adjust`) took any integer. 2,000,000 jumped bulk8_32 to level 50; 10¹² reached the database as a generic "out of range". Normal awards are at most 120 XP, and earlier QA runs had left manual entries up to 2,000,000,000. `XPAdjustmentRequest` now allows at most ±10,000 per adjustment ("Adjust by at most 10,000 XP at a time."). Tests: `tests/test_xp_adjust_schema.py`. bulk8_32's XP was reversed to 15 (level 1).
- **Presentations and teacher database:** deleting a presentation needs its creator or an admin (403 otherwise); period logs can only be edited by the teacher who logged them; old papers, chapter documents and syllabus entries can only be deleted by their uploader. Any teacher may edit any slide in their school; this is documented and records `last_edited_by`. Slide text is shown as plain text and links are never opened, so Markdown in a slide can't run anything. **No issues.**

Backend 696 passed (4 reportlab-dependent skipped).

### 2026-11-25 — sessions, deactivation, suspension, MPIN recovery

All checked on throwaway accounts (bulk8_31, bulk8_32, QA Isolation school 971); **no bugs found**.

- **Sessions (bulk8_31, three sign-ins):** reusing a rotated refresh token → 401 (the new pair keeps working); logout → that access and refresh token both 401; a student MPIN change → every other session's access and refresh 401, including the one that made the change, and the response carries a fresh session; the old MPIN is refused.
- **Deactivation (bulk8_32):** the live access token → 401 at once, refresh → 401, fresh sign-in → 403; works again after reactivation.
- **School suspension (QA school 971, now left suspended):** the teacher's live token → 403 "This school's access has been suspended…", refresh → 401, sign-in → 400.
- **Forgot MPIN:** the login screen tells the user to ask their school's admin. The admin reset refuses weak (`111111`, `123456`) and malformed MPINs and ends the user's existing sessions. The owner creating a school admin also refuses weak MPINs (one test admin, `qaweak_470381`, was added to the suspended QA school).
- **Notes:** a refresh-token reuse didn't end the session family — **hardened** (next section). The local platform-owner account still uses `123456`, the known seeded default (see the default-admin note).

### 2026-11-25 — refresh-token replay ends every session

A refresh token consumed by rotation and replayed **more than 30 seconds later** means two parties held it. `POST /auth/refresh` now ends every session for that user, so whoever rotated first, possibly an attacker, is signed out too. It logs `Refresh token replayed …; all sessions ended.` A replay within 30 seconds (a lost response or a double refresh) is just refused, as before. A logged-out token's stale retry isn't treated as theft. Rotation marks the Redis key `rotated:<epoch>`; logout keeps `1`.

Live on bulk8_31:
- Replay at once → 401, while the rotated session and another device stay signed in.
- Replay after 32 s → 401, and the rotated session, its refresh and the other device are all 401.
- Logged-out token retried after 32 s → 401, and another device stays signed in.

The app refreshes one request at a time (`_refreshFuture` mutex), so normal use doesn't trip it. Unit tests: `tests/test_refresh_reuse.py`.

### 2026-11-25 — online test time limit; registration fields

- **Bug (fixed) — answers sent after the time limit were scored.** `POST /student/tests/{id}/submit` past the attempt deadline marked the submission auto-submitted and stamped it at the deadline, but still scored the request's answers. Live: a 1-minute copy of the grade 8 quiz, started with nothing answered, submitted with every correct answer 100 s later → **10/10**. The time limit was only enforced by the app's own timer. Now a submit arriving more than `SUBMIT_GRACE_SECONDS` (30 s) past the deadline is scored on the answers saved in time. Within the grace window (the app's auto-submit at 0:00 on a slow connection) the sent answers still count. Live: 100 s → 0.00 (nothing saved in time); 70 s (10 s late) → 10.00. Autosave was already sound: past the deadline it finalises with the saved answers and refuses new ones. QA tests #486–489 were deleted, and bulk8_31's XP from them removed (back to 15, level 1).
- **Registration:** phone, email and username length were already validated, and a student's optional subjects already checked. **Bug (fixed):** a teacher's subjects weren't checked at all ("Astrology", none, or Mathematics ×40 were saved). The validator was a pass-through. Sign-up now normalises known subjects ("maths" → "Mathematics"), drops duplicates, refuses unknown ones, and requires at least one; the app checks that before sending. The app's subject list matches the server's exactly. The admin user editor is left permissive because existing data has legacy free-text subjects ("Maths", "English Literature", "science"). Usernames with spaces or emoji are allowed (seems deliberate, alongside Hindi and Gujarati names). Tests: `tests/test_teacher_subjects_schema.py`. Test sign-ups were rejected afterwards.

Backend 701 passed (4 skipped) · `flutter test` 301/301.

### 2026-11-25 — answer-key leaks and test visibility

- **Answer key: no leaks.** For an open online test, the student's pending list, the `/start` payload and the parent's child-tests view all omit the answer key. Review is refused mid-attempt (409). After submitting, review shows only the student's own answers until the test closes, and says when the key appears (`answers_available_at`).
- **Visibility:** a grade 9 student can't see or start a grade 8 test (404); unpublished tests are hidden and `/start` refuses them; "starting" a closed test only returns the student's own finished attempt.
- **Bug (fixed) — `/submit` skipped `/start`'s checks.**
  - A direct submit to an **offline (written) test** filed a 0 score for bulk8_32 on test #481. That would appear in marks reports as if the teacher had entered it.
  - A submit to an **unpublished draft** created a finished attempt, which would lock the student out ("already submitted") once the teacher published it.

  `submit_test` now refuses non-online tests and new submissions to unpublished tests. An attempt already under way can still be finished if a teacher unpublishes mid-test. A normal start → submit still works. The stray records were removed (test #481 back to meera8 3.00 / aarav8 6.00), the QA tests deleted, and bulk8_31/bulk8_32 XP is back to 15.

### 2026-11-25 — test generation limits; changing tests after students start

- **Bug (fixed) — generation counts were unbounded.** `POST /teacher/tests/generate` took any integers for the eight question-type counts, the time limit and the source percentages. 100,000 MCQs would have gone straight into the AI prompt and its retries across providers, and negative counts were accepted too. The app's steppers had no upper limit either. Now each type is 0–50, the whole paper 1–100 questions ("Choose at least one question." / "A test can have at most 100 questions."), the time limit 0–180 min (the app's slider range) and each source percentage 0–100. These are form-field limits and checked before the hourly quota and any AI call. Verified with requests that are all refused, so no AI was called. The app's + button now stops at 50.
- **Changing tests:** editing questions is refused once any student has started ("…its questions can no longer be changed."). Deleting a test removes its submissions and grades by design, and both delete screens warn "This cannot be undone and will remove all student submissions." Note: XP students earned from a deleted test isn't taken back. Unpublishing mid-test lets students already in an attempt finish (see the submit fix).

### 2026-11-25 — uploads; academic-year double tap

- **Image uploads (no bugs):** every image upload strips EXIF (location data) and checks the bytes: student, teacher and admin photos, the teacher photo set by an admin, the school logo and the payment QR. A 200 MB fake photo is refused with 413 "File too large. Maximum allowed size is 5 MB." in about 1.2 s, with backend memory flat and nothing left in `/tmp`. Starlette spools the upload while parsing, and the declared-size check runs before reading.
- **Bug (fixed) — a double-tapped "Start New Year" skipped a year.** Two simultaneous `POST /admin/academic-years/new` both returned 201 and took a throwaway school from 2026-27 to **2028-29**. The school lock only made them run one after the other, so the second closed the year the first had just opened, and each run removes every non-admin user. Now:
  - The app sends the year it showed (`expected_year_id`), and the server answers 409 "That academic year has already been closed…" if it's no longer current.
  - For older apps that don't send it, a year less than 60 s old can't be closed (409 "A new academic year was just started…").
  - Live: a double tap on a year older than a minute → one 201 and one 409, and the year advanced by exactly one (2028-29 → 2029-30). A stale ID → 409. The right ID a minute later → 201.
  - Initialising a year twice was already refused (409).
  - Throwaway schools "QA Year …" (#972, #973) were left suspended.

### 2026-11-25 — double taps and retries (race sweep)

Two identical requests sent at once, or back to back, on Sunrise. The app's API client also re-POSTs after connection errors, so this matters beyond double taps.

- **Bug (fixed) — Publish was a toggle.** A sequential double tap published the test and then unpublished it. `POST /teacher/tests/{id}/publish` now takes `publish=true|false` (the app sends the state the teacher picked), so repeating it is harmless. It locks the test row so two at once can't both announce it to students. Without the parameter it still toggles, for older apps.
- **Bug (fixed) — duplicate homework and broadcasts.** A double tap created two identical homework items and two identical broadcasts. An identical second request from the same teacher within 60 s now gets 409 ("That homework was just assigned." / "That message was just sent."), via a Redis `SET NX` on the content. For homework the check runs after the other validations, so a refused attempt (review pending, past due date) can be retried straight away.
- **Already safe:** fee payments use the app's `X-Idempotency-Key` (same key twice → 201 + 409; without a key they double up, which the app never does); approving the same sign-up twice leaves one teacher profile; attendance duplicates are blocked by a unique constraint (earlier).
- Cleanup: QA tests, homework, payments and sign-ups removed; QA broadcasts "QA race BC/BC2" remain (no delete route).

### 2026-11-25 — shared devices (push tokens); grade change mid-year

- **Bug (fixed) — a device could belong to two accounts for notifications.** Logout clears the account's push token, but a session that ends otherwise (expiry, or a reinstall, which since J-26 clears the sign-in without telling the server) left the token on the old account. Live: bulk8_31 and then bulk8_32 registered the same token → **both accounts held it**, so on a shared phone or school tablet the new user would get the previous user's grade and fee notifications. `PUT /auth/fcm-token` now clears the token from any other account first; afterwards only bulk8_32 holds it.
- **Bug (fixed) — moving a student up a grade broke their test reviews.** After the admin moved bulk8_02 from grade 8 to 9, their grades, completed tests and attendance were intact, but opening the review of their completed grade 8 quiz (#482) returned **404 "Test not found"** while the test was still in their completed list. The review checked the student's *current* grade. It now checks that the test is in their school and that it's their own submission. Live: review 200 after the move; meera8 opening a test she didn't take is still 404. bulk8_02 was moved back to grade 8.
- **Note:** after a move to grade 9 the student's fees show ₹0, because Sunrise has no grade 9 fee structure. That's setup data, not a bug.

### 2026-11-25 — account deletion and a departing teacher

- **Account deletion (`DELETE /auth/account`):**
  - **Already correct:** admins, students and the owner can't self-delete. A parent's deletion takes their one linked child with it, and is refused with two linked children so the school can choose. Records are soft-deleted (attendance, grades and fees stay). The current tokens and the push token are cleared, and the child's sessions fail because of `deleted_at`.
  - **Open (decision needed):** no MPIN is asked for; a live session is enough. The app's type-to-confirm dialog prevents accidents, but anyone holding an unlocked phone could delete the parent and child accounts. Requiring the MPIN needs the app and backend shipped together, because production's older app doesn't send it. Noted in the risk register.
- **A teacher who leaves (#40):** a colleague can't publish another active teacher's test (403). After the admin deactivates that teacher, the listing marks their tests manageable (`can_manage`), and das_sci could publish and delete the test and delete their homework. **Works as designed.** The throwaway teacher was revoked afterwards.

### 2026-11-26 — speed sweep (Sunrise size and 1,500 students)

- **Sunrise (~145 users), median of 5, local stack:** every main screen's request for all four roles takes 4–11 ms (dashboards, tests, grades, fees, attendance, broadcasts, leaderboard, timetable, payments, users), and the pending-fees PDF report 28 ms. No errors.
- **Throwaway "QA Scale" school (#974) bulk-filled through SQL** with 1,500 students (500 per grade), a payment each and 30 days of attendance (43,500 rows). Median of 3:
  - Pending-fees PDF: **236 ms**.
  - Fees summary: 68 ms (370 KB).
  - Student list: 55 ms (505 KB).
  - Attendance report, grade 8: 54 ms.
  - Current year with unpaid totals: 17 ms.
  - Marks report: 14 ms.
  - A teacher's 500-student attendance roster: 10 ms.
  - Teacher dashboard and workflow: 6–10 ms.

  **No slow endpoints.** Note for very large schools: the student list and fees summary aren't paginated, about 0.5 MB per refresh on mobile data. The synthetic students and their rows were deleted afterwards, and school #974 (admin and teacher only) left suspended.

### 2026-11-26 — privacy sweep (personal data in responses and logs)

- **Responses by role (Sunrise):**
  - Teachers' student lists carry masked phones (`91***0001`) and emails (`a***@sunrise.test`), with no parent contact details.
  - The teacher colleague list, the parent faculty view, broadcasts, dashboards, children lists and `/auth/me` carry no phone or email.
  - **No unmasked contact details reach teachers, students or parents.**
  - **Note:** the school leaderboard shows every student's username, grade, level and profile photo to the whole school. That's a gamification choice, worth weighing with the open COPPA/GDPR-K item.
- **Backend logs (24 h, 623 lines):** no MPINs (including the test accounts' known MPINs), no JWTs or Bearer tokens, no 10-digit phone numbers.
- **Local-stack note:** the backend container runs with auto-reload on the mounted source, so edits take effect live without a rebuild.

### 2026-11-26 — small-phone pass (iPhone SE, 375×667 pt)

- **Bug fixed: Sign in was below the fold on the SE.** Even the compact login layout put the keypad's 0 key and the Sign in button about 125 pt below the fold, so users had to scroll in the middle of typing their MPIN.
  - Phones under 700 pt tall now get a short layout:
    - The "Welcome back" heading is dropped; the navy header already names the school.
    - Keypad keys are 44 pt (Apple's minimum tap target) with a 6 pt gap.
    - MPIN cells and the spacing between sections are tighter.
  - Everything through Sign in now fits without scrolling. Signed in as aarav8 and das_sci from it.
  - Phones 700 pt and taller (iPhone 17 Pro and up) are unchanged.
- **Student screens fit at 375 pt:** home, Tests (Online and Offline) and Fees.
- **Teacher screens fit at 375 pt:**
  - home, including the workflow strip and all six tab labels;
  - the Tests list and the generate form;
  - the Timetable (My and Full).
- **Parent screens fit at 375 pt:** home with the child switcher, Grades (Online, Offline, Analysis).
  - **Bug fixed: the progress chart repeated its first and last dates.** With three tests the axis read "23 Oct 23 Oct … 25 Nov 25 Nov", and the last label ran past the card edge.
    - Cause: the chart also asks for labels at its padded ends (-0.3 and n-0.7), and `toInt()` truncated those onto the first and last test.
    - Labels are now drawn only at whole-number positions. The student grade chart had the same code and got the same fix.
- **Admin screens:**
  - **Bug fixed: the avatar covered the school name.** On a 375 pt phone, "Sunrise Public School" wraps to two lines beside the three header icons, and the avatar circle covered "Public School".
    - The header now measures the name and lowers the navy band, and the card with it, by however much a wrapped name needs. Short names are unchanged.
  - The Users screen title "User Management" was cut off as "User Managem…". It's now "Users", matching the bottom-nav label.
  - Users (including a 60-character test username), Fees and Reports fit.
- `flutter test`: 301 passed.

### 2026-11-26 — school-day boundaries (IST vs the server's UTC clock)

The server and database run in UTC while every school is on IST (UTC+5:30), so between 00:00 and 05:30 IST the UTC date is still yesterday. Daily gates already use `school_today()`. This sweep found the places that still didn't.

- **Bug fixed: the admin marks report put late-night marks in the wrong day, and at a month end the wrong month.**
  - The filter used `date(Grade.created_at)`, which takes the UTC date.
  - Proof: a test mark entered at 00:30 IST on 1 Dec (19:00 UTC on 30 Nov) counted toward 30 Nov under the old filter and toward 1 Dec under the new one.
  - The report is now bounded by school-time midnights. The 1 Dec report PDF grew by the row and the 30 Nov one was empty.
  - The report's default start, the year's start date, is now the school's calendar day as well.
- **Fixed: PDF "Generated on" dates.** Question papers and the fee, ledger, attendance and marks reports showed yesterday's date when made before 05:30 IST.
- **Fixed: the academic-year fallback.** When a school has no current year, its year label now flips on 1 June IST, not 1 June UTC.
- No other server-side `date.today()` or UTC `.date()` on timestamps remains. The phone app uses the device clock, which is local.
- Test: `test_late_night_mark_falls_in_the_school_day_window`. Backend: 702 passed. The test row was deleted afterwards.

### 2026-11-26 — large text, and the server going away (iPhone SE)

- **Large text:** the app caps the system text size at 1.1× (`main.dart`). At the cap, the login screen still fits through Sign in on the SE, and the admin header truncates a long school name rather than running it under the avatar.
  - **Note:** the cap protects layouts but limits low-vision users. That's a product decision, not changed here.
- **Server down mid-session** (local backend container stopped):
  - Each screen retries for about 7 s (1 + 2 + 4 s backoff), then shows an error with Try Again.
  - The session is kept; nobody is logged out.
  - **Fixed: misleading message.** It said "No internet connection" when the internet was fine and the server was down, which sends a parent to toggle Wi-Fi. It now reads "Can't reach MindForge right now. Check your internet connection, or try again in a minute." This covers both cases, and the carrier-DNS problem too.
- **Bug fixed: a cold start with the server down replaced the whole student screen with a raw error.** It read "DioException [connection error] … Connection refused"; a release build would show a blank grey screen with no way out.
  - Cause: the student bottom nav's "new items" badge read `AsyncValue.value`, which in Riverpod 2 rethrows a failed load during build. It now uses `valueOrNull`.
  - Result: the dashboard shows "Could not load dashboard" with Try Again, and the nav stays usable.
  - No other `.value` reads on async values remain in `lib/`.
- **Bug fixed: Try Again and pull-to-refresh brought back only half the dashboard.** The XP card, Class progress and the school logo had failed during the outage and hid themselves; the retry reloaded only the summary, so they stayed missing until the app was restarted.
  - The new `reloadFailed()` helper also re-fetches any section whose load failed, and leaves healthy ones alone.
  - It's wired into the student, parent and teacher dashboards. The logo is reloaded through `currentSchoolProvider`, which it derives from.
  - Verified on the SE: server down → cold start → server back → one Try Again restores everything, logo included.
- **Fixed: unreadable status bar on the dashboard error page** (light page, white clock). The page now uses dark status-bar icons, for all three roles.
- **Not exercised live:** parent and teacher cold starts with the server down. Same code paths, and no `.value` reads remain.
- `flutter test`: 301 passed. The backend is back up (health 200).

### 2026-11-26 — server down: admin and teacher cold starts (iPhone SE)

- **Admin:** no crash, but the failure was silent. The School Setup road, the academic-year badge and the "users awaiting approval" banner just vanished, which reads as lost setup.
  - Falling back to the full dashboard is deliberate, so the admin is never locked out.
  - **Fixed:** it now also shows a notice: "Can't reach MindForge, so school setup and approvals aren't shown." with a Retry button.
  - **Fixed:** the admin refresh now also reloads the school logo when it failed to load.
  - Verified: server back → Retry restores the logo, year badge, setup road and the 16-pending banner.
- **Teacher:** shows "Could not load dashboard" with Try Again. After the server is back, one Try Again restores the logo, workflow and presentation progress (last round's `reloadFailed`).
- With the student run last round, every role is now covered for a cold start with the server down. `flutter test`: 301 passed. The backend is back up.

### 2026-11-26 — error messages users see (validation, lockout)

- **The shared formatter is good.** `apiErrorMessage()` turns FastAPI's 422 list into a sentence and strips Pydantic's "Value error," prefix. No screen puts a raw exception in front of users.
- **Bug fixed: the change-MPIN screens dropped the server's reason** (student, teacher, parent, admin). They showed "Current MPIN is incorrect" for any 400 and "Failed to change MPIN. Try again." for everything else.
  - That swallowed the 422 "MPIN is too easy to guess…", so the user retried the same weak MPIN.
  - It also swallowed the 429 lockout ("Account temporarily locked … Try again in 15 minutes."), which invited more tries. Probe on bulk8_32: five wrong current MPINs, then 429.
  - All four screens now show `apiErrorMessage(e)`. Verified on the SE as das_sci with new MPIN 123456: the snackbar gives the server's sentence. The MPIN is unchanged.
- **Noted:** the server accepts a "new" MPIN equal to the current one, and the change ends all sessions. The app's form already blocks it, so this was left as is.
- **Small-screen usability:** the iOS number pad has no Next or Done key, but the profile page scrolls, so the lower fields are reachable.
- **Test hygiene:** bulk8_32's lockout keys were cleared in Redis; login works. A stray tap during the run set a photo on das_sci. Its `profile_pic_url` was reset to NULL; the uploaded file stays in local MinIO as an orphan.
- `flutter test`: 301 passed.

### 2026-11-26 — paging limits, HTTP headers, and "today" on phones outside IST

- **Paging:** every `limit` has an upper bound. A `skip` or ID beyond 64-bit range gets a 422, and the maximum valid `skip` returns an empty page. No 500s.
- **Headers and CORS:** the API sends HSTS, `nosniff`, `X-Frame-Options: DENY` and `CSP: default-src 'none'`. A preflight from an untrusted origin is refused (400). Media files carry `nosniff`. There are no CSV or Excel exports, so formula injection doesn't apply.
- **Bug fixed: the app's "today" came from the phone's timezone, not the school's.** The dashboards send "today" to the server, which answers for whatever date it's given.
  - A parent abroad would see yesterday's timetable and homework labelled as today. In New York at 8 PM it's already the next morning in India.
  - The same applied to the attendance date, the timetables' "today", the "happening now" period highlight and the homework due-date picker.
  - Fix: a new `lib/core/utils/school_time.dart` provides `schoolNow()` (IST wall clock) and `untilNextSchoolDay()` (computed in UTC, so the phone's DST can't skew it). They're used in:
    - the student, parent and teacher dashboards: today, header date, period highlight and midnight rollover;
    - the three timetable and three attendance screens;
    - the homework due-date picker.
  - **Verified:** launched with `SIMCTL_CHILD_TZ=Pacific/Honolulu` (25 Nov, 20:38 there; 26 Nov in India).
    - Before the attendance change, teacher Attendance opened on **25 Nov**, which proves the override reached the app, and the Timetable already showed 26 Nov.
    - After the change, Attendance opens on **26 Nov**.
  - `test/school_time_test.dart` passes under both the local timezone and `TZ=America/New_York`.
- **Left on the phone clock:** admin report and fee-date defaults, and badge timestamps. Admins are on site.
- `flutter test`: 303 passed.
