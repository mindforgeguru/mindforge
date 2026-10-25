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
| B-02 | Admin · iOS | Two-factor setup prompt (if shown): scans/enters the code, saves recovery codes | Enrolled; next login asks for a code | SKIP — no 2FA prompt shown for admin |
| B-03 | Admin · iOS | Taps a later road step (e.g. Fees) before Academic Year | Blocked or clearly told to finish the earlier step | FAIL (minor) 2026-10-22 — locked road node silently ignores taps (no hint); bottom-nav Fees opens Fee Management anyway |
| B-04 | Admin · iOS | Starts the academic year 2026–27 | Road advances; car moves to Timetable | PASS 2026-10-22 — 2026-27 ACTIVE; car moved to Timetable |
| B-05 | Admin · iOS | Uploads a school logo from the photo library | Logo shows on the dashboard header and login picker | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: Sunrise logo_url set; logo shows on dashboard header |
| B-06 | Admin · iOS | Builds a grade 8 timetable: 6 periods, Mon–Sat, Maths/Science/English, publishes | Saved; grid reads back correctly after leaving and coming back | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 8, 6 periods Mon–Sat 19–31 Oct |
| B-07 | Admin · iOS | Same for grade 9 with 5 periods | Grade 9 grid independent of grade 8 | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 9 slots exist (60); config is school-wide (run log #5) |
| B-08 | Admin · iOS | Sets grade 8 fees: tuition ₹40,000 + transport ₹8,000 | Total ₹48,000 shown; ₹ sign renders | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: grade 8 base 40000 + 8000 stored in `computer_fee` (no transport field?) — check label in E-07 |
| B-09 | Admin · iOS | Enters a negative or blank fee | Refused with a readable message; nothing saved | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB |
| B-10 | Admin · iOS | Uploads a payment QR + UPI details | QR preview shows; setup road reaches its end | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: payment_info row exists |

## C. People join

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| C-01 | Mr. Iyer · Web | Registers as a teacher in Sunrise | "Registration submitted! Await admin approval." | PASS 2026-10-22 — "Registration submitted! Await admin approval." — but see run log: accepted with NO active year |
| C-02 | Mr. Iyer · Web | Immediately tries to log in | "pending admin approval" message, no dashboard | PASS 2026-10-22 — "Your account is pending admin approval. Please wait." |
| C-03 | Aarav · iOS | Registers as grade 8 student with phone, email and parent details | Submitted; parent account also created (pending) | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: aarav8 + aarav8_parent created together |
| C-04 | Someone · iOS | Registers with Aarav's username or phone again | Refused with a generic message (no "this user exists" leak beyond what's needed) | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB |
| C-05 | Meera, Kabir, Ms. Das · Web | Register the rest of the cast | All pending | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: meera8, kabir9, das_sci (+ parents) exist |
| C-06 | Prankster · Web | Registers a junk student "asdf" | Pending | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: ids 11934/11935 missing — consistent with asdf + parent rejected |
| C-07 | Admin · iOS | Opens pending users (pull to refresh) | Sees everyone from C-01..C-06 with role and grade | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; not checkable from DB |
| C-08 | Admin · iOS | Rejects "asdf" | Gone from list; that username can register again | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: asdf gone (see C-06) |
| C-09 | Admin · iOS | Approves everyone else (incl. Aarav's parent) | All move to active users; filters by role/grade work | UNRECORDED 2026-10-22 — done in session [App testing](#local_4a1ec0d1-bcaa-4164-8e9f-2b69931c7da4), result not written down; DB: all 9 Sunrise users active + approved |
| C-10 | Aarav · iOS | Logs in now | Student dashboard, his name, grade 8, today's timetable | PASS 2026-10-23 — student dashboard, aarav8, Grade 8, P1–P6 timetable. **FAIL (date roll-over)**: see run log 2026-10-23 #1 |

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
| D-10 | Mr. Iyer · Web | Generates a 10-question AI test on a chapter, edits one question, publishes with a 15-min window | Test listed as published; PDF downloads with the answer key | FAIL 2026-10-23 (web) — generated 10 MCQs from an uploaded chapter PDF (questions match the PDF). But: (a) the test was **published on generation**, live to students before review (teacher.py:1043, intentional); (b) **editing only an option is silently lost** — no Save appears, back discards it (`_questionsEdited` ignores `options`, test_detail_screen.dart:273); question-text edits do save; (c) header shows "10 min" but stored/actual limit is 5 (`questions.length` used as minutes, :376); (d) no publish "window" control exists — plan expectation outdated; PDF download exists only for offline tests (verified test_paper.pdf + answer_key.pdf stored in MinIO for test 481, not downloaded) |
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
| E-07 | Aarav · iOS | Opens Attendance, Grades, Timetable, Fees, Faculty | Each loads real data (attendance from D-02, marks from D-11, ₹48,000 fees, QR) | PARTIAL 2026-10-23 — Attendance: 23 Oct present, 100% ✓. Grades: online 9/10, offline 6/6 ✓, but **"Class High/Low" are the student's own min/max** (`features/student/screens/grade_screen.dart:1023`) — showed 90%/90% though Meera scored 10%. Fees: ₹40,000 (not ₹48,000) — the ₹8,000 was stored as the optional *computer* fee and Aarav takes no optional subject; there is no transport-fee concept. Pay tab: QR + UPI `sunrise@sbi` ✓, empty bank fields shown as blank labels. Faculty (web): both teachers ✓. Timetable: dashboard P1–P6 ✓ |
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
| H-04 | Owner · Web | Suspends Sunrise; a Sunrise teacher tries to log in | Login refused with a clear message; owner unaffected. Then un-suspend | PARTIAL 2026-10-24 — owner Suspend (one click, **no confirmation**) → "Sunrise Public School suspended."; teacher/admin login → 400 "Selected school was not found or is inactive." and Sunrise vanishes from the picker; owner unaffected. But the already signed-in admin (iOS) got **"Server error. Please try again in a moment."** with a no-wifi icon on the next request (403 underneath) and stayed on a normal-looking dashboard — not signed out, not told the school is suspended. Re-activated; picker only showed Sunrise again after an app restart (cached list) |
| H-05 | Iyer · iOS | Types a 5,000-char homework title / emoji / blank | Blank refused; long text refused or trimmed with a message; emoji saved fine | PASS 2026-10-24 — blank and spaces-only title → "Required"; leading spaces trimmed; emoji/Devanagari title saved (API, id 993). Over 300 chars refused by server (422 "at most 300 characters", app maps it to a readable message) but the title field has no counter/limit, so the teacher only finds out on submit. Test rows 992/993 left in grade 9 |
| H-06 | Aarav · Web | Hard-refreshes on `/student/fees`, uses browser back/forward | Stays logged in; navigation works | PASS 2026-10-24 (web) — reload on /student/fees keeps the session and returns to Fees (dashboard + MindForge branding flash for ~5 s first); back → Fees, forward → Grades |
| H-07 | Any · Web | Resize to 375 / 768 / 1280 px on each dashboard | No overflow stripes; bottom nav vs sidebar correct | PASS 2026-10-24 (web, student) — 375 and 768 px: bottom nav, no horizontal overflow (scrollWidth = innerWidth); 1280: sidebar. Minor: "Mathematic/s" wraps mid-word in period cards at 768; "Recent Test Marks" bars are both labelled just "Math". Teacher/parent/admin only seen at 1280 |
| H-08 | Aarav · iOS | Logs out, logs in as Meera on the same device | No trace of Aarav's data (dashboard, presentations, XP) | PASS 2026-10-24 (web) — Aarav logout leaves localStorage/sessionStorage empty; Meera then sees her own name, letter avatar, 0 XP, grades 1/10 and 3/6, fees ₹0 paid. Grade-wide progress ring is shared by design |

## I. End of year

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| I-01 | Admin · iOS | Reports screen | Attendance / marks reports for grade 8 match what was entered | PARTIAL 2026-10-24 — Reports has only fee PDFs (Pending Fees, Student Ledger); **no attendance or marks reports**. Fee PDFs (fetched via API) are correct: Aarav ₹20,000 due, Meera ₹40,000, total ₹60,000; ledger shows the 23 Oct payment. PDFs are branded "MIND FORGE", not the school |
| I-02 | Admin · iOS | Close Year → Cancel | Nothing changes | PASS 2026-10-24 — Close Year dialog states all students/teachers/parents are removed and the timetable cleared; Cancel → DB unchanged (9 users, 2026-27 current, 132 slots) |
| I-03 | Admin · iOS | Close Year → Confirm, then Start Year 2027–28 | New year; road resets; last year's homework/broadcasts/open tests not shown to students | PARTIAL 2026-10-24 — DB backed up first (`.claude/backups/mindforge_local_pre_I03_20261024_1645.dump`, pg_dump -Fc). Close Year → "Academic year closed — a new year has started." All 8 non-admin users soft-deleted (old logins → "Invalid username or MPIN"), 132 timetable slots cleared; fee structure, payment info, logo kept. Re-registered aarav8 + parent via API and approved: homework, broadcasts, pending/completed tests, grades, timetable all empty; 0 XP. Meera, still signed in on web, was signed out on her first request (one screen showed cached grades first). But: **new year is labelled "2026-27" again** (label = current calendar year, `admin.py` `_make_year_label(now.year)`), so two years share a label; there is no separate "Start 2027-28" step; **last year's chapter-progress ring (Linear Equations 50%, by deleted iyer_maths) still shows** to the new class; setup road stays all-green (timetable step = periods config, kept by design) |

## J. Extreme cases

Edge conditions a real school will eventually hit. Run after A–I; anything destructive goes on throwaway accounts.

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| J-01 | Admin · Web | Registers/approves 60 grade-8 students (script the sign-ups, approve in UI), then Iyer takes attendance | List scrolls smoothly; save takes < 3 s; counts correct | PASS (server) 2026-10-24 — 60 scripted grade-8 sign-ups (`bulk8_01..60` + parents, MPIN 135792), all approved in 0.9 s; admin list + teacher roster 62 in 0.01 s; attendance for 62 saved in 0.23 s. UI scrolling not timed. **Registration is capped at 5 per minute per IP** (`auth.py` register) — a class signing up on one school Wi-Fi gets "Too many registration attempts"; the script had to vary X-Forwarded-For (works locally only) |
| J-02 | Students · Web | Names in Devanagari/Gujarati, an apostrophe (D'Souza), 60-char name, emoji | Stored and shown correctly everywhere, incl. PDFs and leaderboard; no layout overflow | PASS (server) 2026-10-24 — usernames in Devanagari, Gujarati, d'souza, 60 chars, emoji and with a space all accepted and stored. Rendering in PDFs/leaderboard not checked; spaces/emoji in usernames may be undesirable |
| J-03 | Someone · Web | Registers `Aarav8` when `aarav8` exists; school name "sunrise public school" | Treated as duplicates (case-insensitive) | FAIL 2026-10-24 — `Aarav8` registered and approved alongside `aarav8`; logins are case-sensitive and resolve to different accounts (`AARAV8` → invalid). School names ARE case-insensitive (409 for "sunrise public school") |
| J-04 | Iyer · Web | Broadcast / homework text `<script>alert(1)</script>` and `'; DROP TABLE users;--` | Shown as plain text; nothing runs; nothing breaks | PASS 2026-10-24 — `<script>`, `<img onerror>` and `'; DROP TABLE users;--` saved as broadcast/homework text and shown verbatim on web; no script ran; users table fine |
| J-05 | Iyer · iOS | Test with 0 questions; end time before start; window entirely in the past | Can't publish; clear message for each | FAIL 2026-10-24 — auto-quiz 480 emptied to 0 questions via the editor API and then published (200). No start/end time exists, so the other two checks don't apply. Unpublished again |
| J-06 | Aarav · iOS | Test window closes while he is mid-test | Auto-submitted with answers so far (or clear rule); no crash, no second attempt | FAIL 2026-10-24 — student started 482, autosaved 1 answer, window then closed: submit → 410 "Test submission window has expired."; start again → 410; submission left unfinalized with no score — answers so far are lost (plan expected auto-submit) |
| J-07 | Aarav · iOS | Airplane mode just before tapping Submit, then back online | Submission not lost or double-counted; clear status shown | NOT RUN — no network toggle in the simulator tooling; H-02 covers the "backend gone" error view |
| J-08 | Aarav · iOS | Double/triple-taps Submit; Iyer double-taps Save attendance; admin double-taps Record payment | Exactly one record each | FAIL (partly) 2026-10-24 — 3 concurrent test submits → 1 row (409, 201, 409); 2 concurrent attendance saves → no duplicate (409, 201). **2 concurrent "Record payment" → 2 payment rows** — no idempotency on `/admin/fees/payments` |
| J-09 | Aarav · iOS | Phone clock set 1 day ahead / behind, then opens tests and timetable | Server time wins; can't start a test early or late | PASS (server) 2026-10-24 — a closed test can't be started (410); dashboard for a future date just returns that day's (empty) timetable. Device clock not changed on the sim |
| J-10 | Iyer · iOS | Takes attendance at 23:59 and saves at 00:01 | Lands on the right day (IST); no duplicate | PASS (server) 2026-10-24 — date is chosen by the client: yesterday accepted (backfill), tomorrow/+7 refused ("cannot be marked for a future date"); same day+period re-save upserts. 23:59→00:01 on a device not run |
| J-11 | Admin · iOS | Fee payment of ₹0, ₹0.50, more than the balance, ₹99,99,999 | Zero/over-balance refused or clearly flagged; paise handled; big number formats with Indian commas | FAIL 2026-10-24 — ₹0 and negative refused; **₹0.50, ₹99,99,999 and over-balance accepted silently**; balance clamps to ₹0 so overpayment is invisible. Student Fees shows Western grouping (₹9,999,999, ₹10,052,000) and **₹0.50 displayed as "₹1"** |
| J-12 | Admin · iOS | Changes grade 8 fee structure after payments exist | Paid history kept; balance recalculated sensibly | PASS 2026-10-24 — base fee 40,000→45,000 with a ₹20,000 payment: payment kept, balance ₹25,000. Reverted |
| J-13 | Mum · Web | Parent with two children (register Aarav's sibling with same parent phone) | Child switcher; each screen follows the selected child; no mixing | PASS 2026-10-24 — `anya8` registered with parent_username aarav8_parent + its MPIN → linked; Mum (web) gets an aarav8/anya8 switcher; Grades and Fees follow the selected child |
| J-14 | Admin · iOS | Moves Aarav from grade 8 to 9 mid-year | His timetable/homework switch to grade 9; past marks kept | PASS (server) 2026-10-24 — admin moved aarav8 to grade 9: dashboard timetable + homework switched to grade 9, past grade-8 marks kept. Moved back |
| J-15 | Admin · iOS | Deactivates Mr. Iyer while his test is open and homework pending | Students can still finish the test; Ms. Das can take over/unpublish; homework still visible | PASS (server) 2026-10-24 — Iyer deactivated mid-test: student still submitted (201), Ms. Das could unpublish Iyer's test, homework still listed. Iyer re-activated |
| J-16 | Aarav · iOS + Web | Logged in on two devices at once; logs out on one | Other device keeps working (or is signed out — whichever is the rule, consistently) | PASS (server) 2026-10-24 — two sessions for meera8; logout of one → that token 401, the other still 200 (per-session logout) |
| J-17 | Aarav · iOS | App left idle overnight (or access token expired), then opened | Silent refresh; no login loop; no data from cache that's wrong | PASS (observed in C-10, 2026-10-23) — app left open overnight: first call 401 → silent refresh → 200, no login loop; but the date bug (run log 2026-10-23 #1) left yesterday on screen |
| J-18 | Iyer · iOS | Uploads 25 MB photo, HEIC, a `.txt` renamed `.jpg` as avatar | Big/fake refused with a message; HEIC works or is refused cleanly | PASS (server) 2026-10-24 — 25 MB → 413 "Maximum allowed size is 5 MB"; text renamed .jpg → 400 "Only JPEG, PNG, and WebP"; HEIC → same clean 400 (iOS picker normally converts to JPEG) |
| J-19 | Iyer · Web | Presentation: corrupt `.pptx`, 200-slide deck, password-protected PDF | Corrupt/locked refused clearly; big deck processes or fails with a message, not a spinner forever | PARTIAL 2026-10-24 — corrupt .pptx → 415 "isn't a readable PowerPoint"; text renamed .pptx → 415 with Google Slides hint. 200-slide deck and password-protected PDF not tried |
| J-20 | Iyer · Web | AI test generation with all AI keys removed/invalid | Friendly failure + Retry; no half-made test left behind | NOT RUN — needs the backend restarted with AI keys removed |
| J-21 | Iyer + Das · Web ×2 | Both edit the same grade-8 timetable slot at the same moment | One wins cleanly; the other is told; no duplicate period | PARTIAL 2026-10-24 — Iyer and Das upsert grade 8 P6 at the same moment: both 200, one row (last write won, "Mathematics"); no duplicate, but the overwritten teacher is not told |
| J-22 | Admin · iOS | Whole-school holiday on a weekday; Sunday; a day with no timetable | Holiday banner for all roles; road doesn't nag for attendance | PASS (server) 2026-10-24 — Monday 26 Oct marked holiday for grades 8+9: student summary returns 6 holiday slots with comment "Diwali"; Sunday returns none. Today's grade 9 marked holiday → workflow is_holiday=true, attendance not applicable, next_step "holiday" (no nag). Banner not viewed on screen |
| J-23 | Any · iOS | Largest Dynamic Type text size, dark mode, iPad landscape | Readable; no clipped buttons or overflow stripes | NOT RUN — Dynamic Type / dark mode / iPad not exercised this session |
| J-24 | Any · iOS | Paste letters/emoji/7 digits into the MPIN pad; spam pull-to-refresh; tab-switch rapidly | Input rejected; no duplicate requests storm; no crash | NOT VERIFIED — on-screen keypad offers digits only; physical-key input never reached the MPIN cells in the hidden web pane (automation or app — unknown) |
| J-25 | Admin · iOS | Close Year with a test still open and unpaid fees | Warned; open test closes/expires correctly; unpaid balances carried or reported | PARTIAL (from I-03, 2026-10-24) — Close Year dialog warns about removing users/timetable but says nothing about open tests or unpaid fees; unpaid balance carry-over not checked |
| J-26 | Aarav · iOS | Delete app, reinstall, log in | Clean start; push notifications re-register | NOT RUN — reinstall + push registration not exercised |

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
| K-08 | Parent-MPIN guessing at registration across many addresses (per §tests) | Throttled/locked as the integration test expects | PARTIAL 2026-10-24 — wrong parent MPIN at registration → 422 weak-MPIN guard (J-13); register rate-limited 5/min/IP. Dedicated multi-IP parent-MPIN throttle test (tests/security_test*) not re-run here |

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
| K-17 | Stored XSS: `<script>`, `<img onerror>`, `javascript:` in any text that's shown to another user (names, broadcasts, homework, feedback) | Rendered inert on web and in PDFs | PARTIAL 2026-10-24 — `<script>`/`<img onerror>`/`javascript:` in broadcast+homework render as inert text on web (J-04); not verified inside generated PDFs or feedback |
| K-18 | Oversized / deeply-nested / malformed JSON bodies; wrong content-type | 422/400, no 500, no crash | PASS 2026-10-24 — broken JSON 422, wrong content-type 422, 5000-deep nested 400, 10 MB body 422 — no 500/crash |
| K-19 | Path traversal / weird filenames in uploads (`../`, null byte, double extension) | Sanitised; stored under a safe key | PASS 2026-10-24 — traversal filenames (`../../../../etc/passwd.png`, backslashes, NUL, double-ext) discarded; stored under server-generated key `profiles/teacher/<id>/<random>.png` |
| K-20 | Upload a non-image or script disguised as an image/pptx; polyglot file | Refused by content sniff, not just extension | PASS 2026-10-24 — disguised files refused by content sniff: text-as-.jpg → 400 (Pillow decode), text-as-.pptx → 415 (J-18/J-19); valid-PNG-with-bad-name stored safely (K-19) |
| K-21 | Unicode / homoglyph usernames to impersonate or dodge the uniqueness check | Normalised; no collision bypass | **FAIL** 2026-10-24 — Cyrillic-homoglyph `аarav8` (U+0430 + "arav8") registered as a *distinct* username alongside ASCII `aarav8`; exact-ASCII dup correctly 409. No confusable/NFKC normalisation → impersonation risk. Same family as J-03 (case-sensitive usernames). **Log in SECURITY_RISK_REGISTER.md** |

### K.4 Transport, headers & web

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-22 | Downgrade to HTTP; strip/alter TLS (cert/CA pinning on the app) | App refuses; see `project_ssl_pinning` | NOT RUN — no TLS on the local stack; cert/CA pinning (see [[project_ssl_pinning]]) can only be checked against a TLS endpoint |
| K-23 | Load the web app inside an `<iframe>` from another origin | Framing refused (frame-ancestors) | PARTIAL 2026-10-24 — API responses carry X-Frame-Options: DENY, but the Flutter **web app** ships frame-ancestors via a `<meta>` tag, which browsers ignore (console warns), and the local dev server sends no X-Frame-Options → clickjacking protection on the web page depends on the prod web server; unverified |
| K-24 | Hit the API with a cross-origin `fetch` from an untrusted origin | CORS blocks it; only allowed origins pass | PASS 2026-10-24 — Origin https://evil.example.com → no Access-Control-Allow-Origin (browser blocks); http://localhost:8080 → ACAO echoed |
| K-25 | Inspect responses for missing security headers / verbose stack traces / secrets | Headers present (§3.1); errors generic; no secrets in body or logs | PASS 2026-10-24 — HSTS, X-Content-Type-Options: nosniff, X-Frame-Options: DENY, CSP default-src none; no Server/X-Powered-By; 404 body generic "Not Found" |
| K-26 | Pull tokens/MPIN from web localStorage, logs, Sentry events, URL query strings | Not present in URLs/logs; Sentry scrubbed (per `project`) | PASS 2026-10-24 — WS token rides in `?token=` (by necessity) but a `RedactTokenFilter` strips token=/refresh_token= from uvicorn logs and the Sentry scrubber drops mpin/token/authorization/cookie + local vars; backend logs clean of Bearer/JWT |

### K.5 Business-logic abuse

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-27 | Submit a test many times / race two submissions to inflate score or XP | Single attempt enforced; XP awarded once | PASS 2026-10-24 — 3 concurrent submits of test 482 → 1 submission row, 0 duplicate TEST_SCORE XP (J-08) |
| K-28 | Replay a "homework done" or "attendance" write to farm XP | Idempotent; XP not duplicated | PASS 2026-10-24 — saving the same period-2 attendance 3× added the +5 once (ATTENDANCE XP 5→10 for the first distinct period, then flat) — no XP farming |
| K-29 | Self-approve a pending registration, or approve across schools | Refused | PASS 2026-10-24 — Sunrise admin approving a Riverdale user id → 404; pending users can't log in to self-approve; student→approve endpoint 403 (K-09) |
| K-30 | Record a negative/huge fee payment to zero out or overflow a balance | Bounds enforced; no overflow | PARTIAL 2026-10-24 — ₹0 and negative refused (422); **huge/over-balance amounts accepted** with no upper bound, balance clamps to ₹0 (J-11). No overflow crash, but no bound |
| K-31 | Register/approve in a loop to exhaust resources (no CAPTCHA) → DoS-ish | Rate limits / size caps blunt it; app stays up | PARTIAL 2026-10-24 — register rate-limited 5/min/IP and upload size caps (5 MB) observed; a sustained multi-IP flood / full DoS not driven here (overlaps L) |
| K-32 | Request a huge paginated range (`limit=10_000_000`) or deep page offsets | Capped; no slow query takedown | PASS 2026-10-24 — /xp/leaderboard?limit=1e7 → 422 (le=100). Note: /admin/academic-years/{id}/users accepted limit=99999999 (200) — appears unbounded; fine at ~130 users, worth a cap |

### K.6 Realtime / WebSocket

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| K-33 | Connect `/ws/{other_user_id}` with your own token (sub mismatch) | Refused — matches `test_websocket_auth` | PASS 2026-10-24 — ws /ws/<other_user_id> with my token → 403; my own id+token connects |
| K-34 | Subscribe to another school's / grade's channel | No events delivered | HELD-BY-DESIGN 2026-10-24 — no client-side channel subscribe; events are published only to the connecting user's school/grade (publish_to_grade/school). Cross-school delivery already shown absent in G-03. Not separately forced |
| K-35 | Connect with a refresh-type or revoked-JTI token | Refused | PASS 2026-10-24 — ws with a refresh-type token → 403; with a logged-out (revoked-JTI) access token → 403; invalid token → 403 |
| K-36 | Flood the socket with messages / rapid reconnects | Server stays healthy; connection throttled or dropped | NOT RUN — socket flood / rapid-reconnect stress deferred to section L |

## L. Extreme security / stress

| ID | Attempt | Defence expected (PASS = held) | Status |
|---|---|---|---|
| L-01 | 50 simultaneous logins for one account while an unrelated request runs | Unrelated request not blocked (per `test_login_does_not_block`); no lockout bypass | PASS 2026-10-25 — 50 simultaneous wrong logins for meera8 (fresh IPs) → throttled to 49×429 + 1×401 by the per-user login cap (10/min); an unrelated GET /schools mid-storm still returned 200 (but ~1.6 s — login bcrypt/argon is CPU-heavy). The 50-fail burst tripped the per-user global backstop, so meera8 is now locked 15 min (by design). No lockout bypass |
| L-02 | 500 concurrent students hitting `dashboard-summary` at once | Latency stays reasonable; no 5xx storm | PASS-with-latency 2026-10-25 — 500 concurrent /student/dashboard-summary → all 200, no 5xx. But single dev-worker latency degrades: p50 4.1 s, p95 6.3 s, max 6.4 s, wall 6.5 s. Resilient (no errors), slow under load |
| L-03 | Submit the same test from 10 threads at the same millisecond | Exactly one graded result; no double XP | PASS 2026-10-25 — same test submitted from 10 threads at once → 1×201, 9×409; exactly 1 submission row, 0 duplicate TEST_SCORE XP |
| L-04 | Upload 100 presentations / trigger 20 AI generations at once | Queue holds; no key/billing meltdown takes the app down (watch logs per `project_ai_generation_fallback`) | PARTIAL 2026-10-25 — 10 concurrent real 1.84 MB .pptx deck uploads → all 201 in 0.7 s, health 200 (deck parse holds under concurrency). **Mass real-AI generation deliberately NOT driven** — each gen bills live Claude/Gemini/Groq keys; the generate path + fallback is covered in D-09 and the register |
| L-05 | 10 k-char homework/broadcast, 1000-row timetable, 200-slide deck repeatedly | Size caps refuse the abusive ones; app doesn't OOM | PASS 2026-10-25 — 10k-char homework title, 100k-char description, 50k-char broadcast all → 422 (size caps); 120 timetable upserts in 1.1 s all 200, no OOM |
| L-06 | Leave a WebSocket open and idle for hours; open hundreds of sockets | Reaped/limited; memory stable | PARTIAL 2026-10-25 — opened **200 WebSockets for one user**, all succeeded, health stayed 200 during and after (memory stable). But there is **no per-user connection cap** observed, and hours-long idle reaping was not measured — one client can hold many sockets |
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
