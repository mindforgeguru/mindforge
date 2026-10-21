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
| A-01 | Owner · Web | Opens the app, picks "Platform owner (no school)", enters MPIN | Owner dashboard listing every school with role counts | TODO |
| A-02 | Owner · Web | Creates "Sunrise Public School" and its admin `sunrise_admin` | Success message; school appears in the list with 1 admin | TODO |
| A-03 | Owner · Web | Tries to create "Sunrise Public School" again | A clear "already exists" message — not a raw error | TODO |
| A-04 | Owner · Web | Logs out | Back on login; browser storage has no `mindforge_*` keys | TODO |

## B. The admin sets the school up

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| B-01 | Admin · iOS | First login; types the MPIN wrong once, then right | Wrong: "Invalid username or MPIN". Right: admin dashboard with the setup road, car on Academic Year | TODO |
| B-02 | Admin · iOS | Two-factor setup prompt (if shown): scans/enters the code, saves recovery codes | Enrolled; next login asks for a code | TODO |
| B-03 | Admin · iOS | Taps a later road step (e.g. Fees) before Academic Year | Blocked or clearly told to finish the earlier step | TODO |
| B-04 | Admin · iOS | Starts the academic year 2026–27 | Road advances; car moves to Timetable | TODO |
| B-05 | Admin · iOS | Uploads a school logo from the photo library | Logo shows on the dashboard header and login picker | TODO |
| B-06 | Admin · iOS | Builds a grade 8 timetable: 6 periods, Mon–Sat, Maths/Science/English, publishes | Saved; grid reads back correctly after leaving and coming back | TODO |
| B-07 | Admin · iOS | Same for grade 9 with 5 periods | Grade 9 grid independent of grade 8 | TODO |
| B-08 | Admin · iOS | Sets grade 8 fees: tuition ₹40,000 + transport ₹8,000 | Total ₹48,000 shown; ₹ sign renders | TODO |
| B-09 | Admin · iOS | Enters a negative or blank fee | Refused with a readable message; nothing saved | TODO |
| B-10 | Admin · iOS | Uploads a payment QR + UPI details | QR preview shows; setup road reaches its end | TODO |

## C. People join

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| C-01 | Mr. Iyer · Web | Registers as a teacher in Sunrise | "Registration submitted! Await admin approval." | TODO |
| C-02 | Mr. Iyer · Web | Immediately tries to log in | "pending admin approval" message, no dashboard | TODO |
| C-03 | Aarav · iOS | Registers as grade 8 student with phone, email and parent details | Submitted; parent account also created (pending) | TODO |
| C-04 | Someone · iOS | Registers with Aarav's username or phone again | Refused with a generic message (no "this user exists" leak beyond what's needed) | TODO |
| C-05 | Meera, Kabir, Ms. Das · Web | Register the rest of the cast | All pending | TODO |
| C-06 | Prankster · Web | Registers a junk student "asdf" | Pending | TODO |
| C-07 | Admin · iOS | Opens pending users (pull to refresh) | Sees everyone from C-01..C-06 with role and grade | TODO |
| C-08 | Admin · iOS | Rejects "asdf" | Gone from list; that username can register again | TODO |
| C-09 | Admin · iOS | Approves everyone else (incl. Aarav's parent) | All move to active users; filters by role/grade work | TODO |
| C-10 | Aarav · iOS | Logs in now | Student dashboard, his name, grade 8, today's timetable | TODO |

## D. A school day — teacher side

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| D-01 | Mr. Iyer · iOS | Opens dashboard in the morning | Daily road for grade 8 (blue) and grade 9 (purple); car on first pending step | TODO |
| D-02 | Mr. Iyer · iOS | Takes period-1 attendance: Meera absent | Saved; road advances | TODO |
| D-03 | Mr. Iyer · iOS | Opens period 2 attendance | Pre-filled from period 1 (Meera absent); can change before saving | TODO |
| D-04 | Mr. Iyer · iOS | Assigns grade 8 Maths homework "Ex 4.2 Q1–10" | Saved; appears on his dashboard | TODO |
| D-05 | Mr. Iyer · iOS | Tries to assign another homework before reviewing the last | Told to review the previous one first | TODO |
| D-06 | Mr. Iyer · iOS | Next "day": reviews homework — Aarav done, Meera not | Tiles colour-coded; Aarav gets XP | TODO |
| D-07 | Mr. Iyer · iOS | Sends a grade-8 broadcast "Unit test on Friday" | Sent; listed in broadcasts | TODO |
| D-08 | Mr. Iyer · iOS | Uploads a chapter `.pptx` presentation and adopts it | Slides render; recommended periods shown | TODO |
| D-09 | Mr. Iyer · iOS | Logs a period on the presentation | Auto-quiz card appears as "Generating", flips to ready or failed (with Retry) | TODO |
| D-10 | Mr. Iyer · Web | Generates a 10-question AI test on a chapter, edits one question, publishes with a 15-min window | Test listed as published; PDF downloads with the answer key | TODO |
| D-11 | Mr. Iyer · iOS | Enters offline marks for a written test | Marks saved; re-saving replaces, doesn't duplicate | TODO |

## E. A school day — student side

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| E-01 | Aarav · iOS | Opens app after D-04 | New homework visible without restarting | TODO |
| E-02 | Aarav · iOS | Opens Broadcasts | "Unit test on Friday" with unread dot; dot clears after reading | TODO |
| E-03 | Kabir (grade 9) · Web | Opens Broadcasts | Does **not** see the grade-8 broadcast | TODO |
| E-04 | Aarav · iOS | Takes the test from D-10, answers all, submits | Score shown; no answer key while the test is still open | TODO |
| E-05 | Meera · Web | Starts the same test, presses browser Back mid-test | Warned; leaving forfeits — scores 0, can't re-enter | TODO |
| E-06 | Aarav · iOS | After the window closes, opens the review | Answers and key shown, matching his shuffled order | TODO |
| E-07 | Aarav · iOS | Opens Attendance, Grades, Timetable, Fees, Faculty | Each loads real data (attendance from D-02, marks from D-11, ₹48,000 fees, QR) | TODO |
| E-08 | Aarav · iOS | Opens XP and leaderboard | XP reflects homework + test; ranked against Meera; locked themes say why | TODO |
| E-09 | Aarav · iOS | Opens Profile, changes avatar | New avatar everywhere; no "Delete account" for a student | TODO |
| E-10 | Aarav · iOS | Dashboard chapter-progress ring | Reflects the presentation periods logged in D-09 | TODO |

## F. The parent

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| F-01 | Aarav's mum · Web | Logs in | Parent dashboard for Aarav: marks, timetable, progress ring | TODO |
| F-02 | Aarav's mum · Web | Opens Attendance, Homework, Grades, Fees | Same data as Aarav sees, read-only — no edit controls | TODO |
| F-03 | Admin · iOS + Mum · Web | Admin records a ₹20,000 fee payment | Mum's fee balance updates to ₹28,000 live | TODO |
| F-04 | Aarav's mum · Web | Profile → Delete account dialog | Cascade warning; Delete disabled until username typed. **Cancel**, don't delete | TODO |

## G. Two people at once (realtime)

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| G-01 | Iyer · iOS → Aarav · Web | Iyer marks Aarav's homework done | Aarav's pill flips Pending → Complete without refresh | TODO |
| G-02 | Iyer · iOS → Das · Web | Iyer sends school-wide broadcast | Appears live on Ms. Das's screen | TODO |
| G-03 | Sunrise → Riverdale | Iyer sends grade-8 broadcast; `river_kid` (Riverdale grade 8) watching | Nothing arrives at Riverdale | TODO |
| G-04 | Aarav · iOS | Backgrounds the app 40 s, returns | Reconnects once; then a new broadcast still arrives live | TODO |

## H. Things going wrong

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| H-01 | Aarav · iOS | Wrong MPIN 5 times | Locked with a "try again later" message, not a crash | TODO |
| H-02 | Aarav · iOS | Backend stopped, opens Grades | "No internet connection" error view with Retry; Retry works once backend is back | TODO |
| H-03 | Admin · iOS | Deactivates Kabir while Kabir is logged in on Web | Kabir is signed out on his next action; can't log in | TODO |
| H-04 | Owner · Web | Suspends Sunrise; a Sunrise teacher tries to log in | Login refused with a clear message; owner unaffected. Then un-suspend | TODO |
| H-05 | Iyer · iOS | Types a 5,000-char homework title / emoji / blank | Blank refused; long text refused or trimmed with a message; emoji saved fine | TODO |
| H-06 | Aarav · Web | Hard-refreshes on `/student/fees`, uses browser back/forward | Stays logged in; navigation works | TODO |
| H-07 | Any · Web | Resize to 375 / 768 / 1280 px on each dashboard | No overflow stripes; bottom nav vs sidebar correct | TODO |
| H-08 | Aarav · iOS | Logs out, logs in as Meera on the same device | No trace of Aarav's data (dashboard, presentations, XP) | TODO |

## I. End of year

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| I-01 | Admin · iOS | Reports screen | Attendance / marks reports for grade 8 match what was entered | TODO |
| I-02 | Admin · iOS | Close Year → Cancel | Nothing changes | TODO |
| I-03 | Admin · iOS | Close Year → Confirm, then Start Year 2027–28 | New year; road resets; last year's homework/broadcasts/open tests not shown to students | TODO |

## J. Extreme cases

Edge conditions a real school will eventually hit. Run after A–I; anything destructive goes on throwaway accounts.

| ID | Persona · Platform | What the user does | What they should see | Status |
|---|---|---|---|---|
| J-01 | Admin · Web | Registers/approves 60 grade-8 students (script the sign-ups, approve in UI), then Iyer takes attendance | List scrolls smoothly; save takes < 3 s; counts correct | TODO |
| J-02 | Students · Web | Names in Devanagari/Gujarati, an apostrophe (D'Souza), 60-char name, emoji | Stored and shown correctly everywhere, incl. PDFs and leaderboard; no layout overflow | TODO |
| J-03 | Someone · Web | Registers `Aarav8` when `aarav8` exists; school name "sunrise public school" | Treated as duplicates (case-insensitive) | TODO |
| J-04 | Iyer · Web | Broadcast / homework text `<script>alert(1)</script>` and `'; DROP TABLE users;--` | Shown as plain text; nothing runs; nothing breaks | TODO |
| J-05 | Iyer · iOS | Test with 0 questions; end time before start; window entirely in the past | Can't publish; clear message for each | TODO |
| J-06 | Aarav · iOS | Test window closes while he is mid-test | Auto-submitted with answers so far (or clear rule); no crash, no second attempt | TODO |
| J-07 | Aarav · iOS | Airplane mode just before tapping Submit, then back online | Submission not lost or double-counted; clear status shown | TODO |
| J-08 | Aarav · iOS | Double/triple-taps Submit; Iyer double-taps Save attendance; admin double-taps Record payment | Exactly one record each | TODO |
| J-09 | Aarav · iOS | Phone clock set 1 day ahead / behind, then opens tests and timetable | Server time wins; can't start a test early or late | TODO |
| J-10 | Iyer · iOS | Takes attendance at 23:59 and saves at 00:01 | Lands on the right day (IST); no duplicate | TODO |
| J-11 | Admin · iOS | Fee payment of ₹0, ₹0.50, more than the balance, ₹99,99,999 | Zero/over-balance refused or clearly flagged; paise handled; big number formats with Indian commas | TODO |
| J-12 | Admin · iOS | Changes grade 8 fee structure after payments exist | Paid history kept; balance recalculated sensibly | TODO |
| J-13 | Mum · Web | Parent with two children (register Aarav's sibling with same parent phone) | Child switcher; each screen follows the selected child; no mixing | TODO |
| J-14 | Admin · iOS | Moves Aarav from grade 8 to 9 mid-year | His timetable/homework switch to grade 9; past marks kept | TODO |
| J-15 | Admin · iOS | Deactivates Mr. Iyer while his test is open and homework pending | Students can still finish the test; Ms. Das can take over/unpublish; homework still visible | TODO |
| J-16 | Aarav · iOS + Web | Logged in on two devices at once; logs out on one | Other device keeps working (or is signed out — whichever is the rule, consistently) | TODO |
| J-17 | Aarav · iOS | App left idle overnight (or access token expired), then opened | Silent refresh; no login loop; no data from cache that's wrong | TODO |
| J-18 | Iyer · iOS | Uploads 25 MB photo, HEIC, a `.txt` renamed `.jpg` as avatar | Big/fake refused with a message; HEIC works or is refused cleanly | TODO |
| J-19 | Iyer · Web | Presentation: corrupt `.pptx`, 200-slide deck, password-protected PDF | Corrupt/locked refused clearly; big deck processes or fails with a message, not a spinner forever | TODO |
| J-20 | Iyer · Web | AI test generation with all AI keys removed/invalid | Friendly failure + Retry; no half-made test left behind | TODO |
| J-21 | Iyer + Das · Web ×2 | Both edit the same grade-8 timetable slot at the same moment | One wins cleanly; the other is told; no duplicate period | TODO |
| J-22 | Admin · iOS | Whole-school holiday on a weekday; Sunday; a day with no timetable | Holiday banner for all roles; road doesn't nag for attendance | TODO |
| J-23 | Any · iOS | Largest Dynamic Type text size, dark mode, iPad landscape | Readable; no clipped buttons or overflow stripes | TODO |
| J-24 | Any · iOS | Paste letters/emoji/7 digits into the MPIN pad; spam pull-to-refresh; tab-switch rapidly | Input rejected; no duplicate requests storm; no crash | TODO |
| J-25 | Admin · iOS | Close Year with a test still open and unpaid fees | Warned; open test closes/expires correctly; unpaid balances carried or reported | TODO |
| J-26 | Aarav · iOS | Delete app, reinstall, log in | Clean start; push notifications re-register | TODO |

---

## Run log

Record each session here: date, platform build, cases run, failures with issue links.
