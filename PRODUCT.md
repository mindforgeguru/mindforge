# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Existing codebase: Flutter (app, web + iOS/Android) and FastAPI (backend). The
marketing landing page is a separate standalone HTML/CSS page, previewed as a
hosted link before anything ships; it can later be served at mindforge.guru or
carried into the Flutter login screen.

## Users

Landing-page audience (confirmed 2026-09-17): **parents and students whose
school already uses MindForge.** They arrive knowing the school has adopted it
and need to know what it gives them and how to get in — not to be sold a
platform.

Product users overall (PRD.md §3):

- **Teacher** — generate tests, mark attendance, grade, broadcast notices.
- **Student** — grades 8–10; see what's due, attempt tests, check grades,
  timetable and attendance on a phone.
- **Parent** — monitor a child's grades, attendance, homework and fees without
  chasing teachers.
- **Admin** — users, fee structures, academic years, timetables.

Market: English-medium secondary schools (grades 8–10) in India, roughly
300–1,500 students each.

## Product Purpose

One mobile-first platform replacing paper registers, WhatsApp groups and
disconnected portals. A teacher turns a PDF chapter into an auto-graded test in
minutes; students attempt it on their phone; parents see results immediately;
admins keep records, fees and timetables in one place.

## Positioning

AI test generation from any chapter PDF, tied to the same system that holds
attendance, grades, fees and parent communication. Neighbouring products do one
half or the other.

## Capabilities the page may describe

Confirmed shipped (PRD.md §4): AI test generation from PDFs; single-attempt
online tests with a 3-day window and auto-submit; auto-grading plus a teacher
screen for subjective answers; attendance; grades and reports; fees with
receipts; timetable; homework tracking; broadcasts and push notifications;
role-based dashboards; admin console.

## Evidence and claims

**No proof assets are approved yet** (confirmed 2026-09-17). No school names, no
usage numbers, no testimonials, no ratings, no press. Anything of that kind on
the page must be an obvious `[PLACEHOLDER]` for the owner to fill in. Never
invent a number, a quote or a customer.

## Brand commitments

- Name is styled **MIND FORGE** in the app; "MindForge" in prose.
- Logo: navy monogram M crossed by an orange swoosh
  (`frontend/assets/images/logo.png`, 500×500). Owner is supplying
  higher-resolution logos; the repo file is a stand-in until then.
- Schools are shown their own logo inside the app, so a school logo may appear
  beside the product logo.
- App palette today: navy `#1D3557`-family text, orange accent, light blue-grey
  surfaces; Poppins throughout. The owner has given the landing page free rein
  on colour and type, with the logo as the fixed point.

## Accessibility and context

Phones first, often mid-range Android on patchy connections. Parents may not be
comfortable in English-heavy interfaces or with jargon; copy stays plain. The
page must work at 360px wide and read in sunlight (real contrast, no grey-on-grey).

## Confirmed for the landing page (2026-09-18)

- **Primary action:** sign in / open the app. The page is a front door for
  families whose school already uses MindForge, not a pitch to schools.
- **Imagery:** authored UI, drawn as design material and labelled illustrative.
  No app screenshots, no invented records.
- **Language:** plain English only.

## Open decisions

- Final home for the page (mindforge.guru root vs. a path) — undecided.
- Whether the Flutter login screen adopts the same world — deferred until the
  page is approved.
- App store links: iOS is not released (no Apple Developer enrolment yet), so
  any store badge is a placeholder.
