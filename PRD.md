# MIND FORGE — Product Requirements Document

**Version:** 1.0
**Date:** May 2026
**Owner:** Chinmay Jobanputra
**Status:** Live / In Production

---

## 1. Overview

**MIND FORGE** is an AI-assisted school management and learning platform that connects teachers, students, parents, and school administrators in a single mobile-first app. It replaces the patchwork of paper registers, WhatsApp groups, and disconnected portals that most mid-sized schools still rely on.

The core promise: a teacher can turn a PDF chapter into an auto-graded online test in minutes, students attempt it on their phone, parents see results instantly, and admins keep the institution's records, fees, and timetables in one place.

**One-line description:**
> An AI-powered school platform that lets teachers create tests from any PDF, auto-grades student attempts, and gives parents and admins real-time visibility into attendance, grades, fees, and homework — all on a single mobile app.

---

## 2. Problem Statement

Mid-sized schools (grades 8–10) still operate across fragmented tools:

- **Teachers** spend hours hand-grading tests, taking attendance on paper, and chasing homework completion.
- **Students** miss deadlines because notices live in WhatsApp groups; test prep is decoupled from class material.
- **Parents** only learn about issues at quarterly PTMs; fee receipts and report cards arrive on paper.
- **Admins** juggle Excel sheets for fees, timetables, and academic-year rollovers.

There is no single, affordable platform that ties AI-driven assessment, attendance, fees, and parent communication together for Indian secondary schools.

---

## 3. Target Users

| Role | Primary Goals |
|------|---------------|
| **Teacher** | Generate tests fast, mark attendance in seconds, grade efficiently, broadcast notices |
| **Student** | Know what's due, attempt tests, see grades and timetable, track attendance |
| **Parent** | Monitor child's grades, attendance, homework, fees — without chasing teachers |
| **Admin** | Manage users, fee structures, academic years, timetables, and institution records |

**Initial market:** English-medium secondary schools (grades 8–10) in India, ~300–1,500 students per institution.

---

## 4. Key Features

### 4.1 AI Test Generation (Differentiator)

- Teacher uploads a PDF or image of chapter content.
- The system runs OCR (PyMuPDF + Tesseract), then uses **Google Gemini 2.5 Flash** (with a **Groq LLaMA 3.3-70B** fallback) to generate structured multiple-choice and short-answer questions.
- Teacher reviews, edits, and publishes. The whole loop is < 2 minutes.

### 4.2 Strict Single-Attempt Online Tests

- Students attempt tests on the app with a fixed 3-day window.
- One attempt only — closing the app, switching screens, or running out of time auto-submits with the current state (zero score if blank).
- Auto-grading for objective questions; teachers grade subjective answers from a single screen.

### 4.3 Daily Teacher Workflow ("Road")

- Each grade gets a 6-step daily "road" with milestones: take attendance → publish lesson → assign homework → grade pending → publish test → broadcast.
- Tinted with the grade's color so a teacher with multiple sections can see at a glance what's pending where.

### 4.4 Attendance

- Per-period attendance (configurable periods per day).
- Duplicate-row protection and instant UI refresh after save.
- Holiday-aware timetable.
- Leaderboards visible to students.

### 4.5 Grades & Reports

- Three grade types: online (auto-graded), offline (teacher-entered), manual.
- Charts and percentage breakdowns on student and parent dashboards.
- PDF report generation (test papers, answer keys, result sheets) via ReportLab.

### 4.6 Fees Module

- Admin defines fee structures per grade per academic year.
- Tracks payments, dues, and payment metadata (bank/UPI).
- Parents see fee status and payment history.

### 4.7 Timetable

- Configurable period count per day.
- Per-grade, per-date slots with holiday support.
- Visible to teachers, students, and parents.

### 4.8 Homework Tracking

- Two types: written assignments and online tests.
- Per-student completion tracking.
- Visible to parents.

### 4.9 Broadcasts & Push Notifications

- Teachers can broadcast to all users or a specific grade.
- Firebase Cloud Messaging push notifications for: attendance marked, new test, new grade, broadcast, fee reminder.

### 4.10 Multi-Role Dashboards

- Dedicated home screen for teacher, student, parent, and admin — each tuned to that role's daily decisions.

### 4.11 Admin Console

- User management (4 roles, soft-delete with audit log).
- Fee structure configuration.
- Academic year rollover.
- Reports and database operations.

---

## 5. User Roles & Permissions

| Role | Can Do |
|------|--------|
| **Admin** | Manage all users, fees, academic years, timetable config, institution settings |
| **Teacher** | Create/grade tests, mark attendance, publish homework, broadcast notices, view own students |
| **Student** | Attempt tests, view own grades/attendance/timetable/fees, see broadcasts |
| **Parent** | View linked child's grades, attendance, homework, fees, broadcasts (read-only) |

Authentication is **MPIN-based** (4-digit PIN over JWT) — chosen because the target users (often parents and younger students) struggle with passwords. JWTs are 1-hour access + 30-day refresh, with Redis-backed revocation on logout.

---

## 6. Technical Architecture

### 6.1 Frontend — Flutter

- **Flutter 3.3+** (Dart), iOS + Android + Web build targets
- **Riverpod 2.5** for state management with async caching
- **go_router 13.2** for navigation
- **Dio 5.4** HTTP client with auth/error interceptors
- **Firebase Messaging 15.1** for push notifications
- **flutter_secure_storage** for MPIN persistence
- **fl_chart** for analytics; **printing** for client-side PDF share
- Material 3 design with shimmer loading skeletons

### 6.2 Backend — FastAPI (Python)

- **FastAPI** async web framework
- **PostgreSQL** via **SQLAlchemy 2.0 async** + asyncpg
- **Alembic** migrations
- **Redis** for token revocation and WebSocket pub/sub fanout
- **MinIO** (S3-compatible) for object storage — 4 buckets: tests, profiles, PDFs, database files
- **Firebase Admin SDK** for FCM
- **ReportLab** for PDF generation
- **PyMuPDF + Tesseract** for OCR
- **Google Gemini 2.5 Flash** + **Groq LLaMA 3.3-70B** for AI question generation
- WebSocket endpoint at `/ws/{user_id}` for real-time updates

### 6.3 Deployment

- Docker Compose for local and production
- Nginx reverse proxy
- Multi-instance ready via Redis pub/sub fanout

### 6.4 Data Model (key entities)

User, StudentProfile, TeacherProfile, Homework, Test, TestSubmission, Grade, Attendance, TimetableConfig, TimetableSlot, AcademicYear, FeeStructure, FeePayment, PaymentInfo, Broadcast, AuditLog.

---

## 7. Non-Functional Requirements

| Area | Requirement |
|------|-------------|
| **Performance** | Test generation < 30s for a 5-page PDF; dashboard load < 1s on 4G |
| **Availability** | 99.5% uptime during school hours (8 AM – 6 PM IST) |
| **Security** | MPIN bcrypt-hashed; JWT with revocation; role-checked endpoints; soft-deletes preserved for audit |
| **Privacy** | Student data isolated per school; parents see only their linked child |
| **Scalability** | Async stack + Redis fanout supports horizontal scaling |
| **Offline tolerance** | Submitted test attempts buffered if network drops |

---

## 8. Differentiators

1. **AI test generation in < 2 minutes** from any PDF — no other Indian SIS does this.
2. **Strict single-attempt enforcement** — tests can't be gamed by app-killing.
3. **Multi-stakeholder visibility** in one app — teacher, student, parent, admin all share a single source of truth.
4. **Mobile-first** — built for the phone, not retrofitted from a web SIS.
5. **MPIN auth** — designed for the actual humans using it, not IT admins.

---

## 9. Success Metrics

- **Adoption:** % of teachers publishing ≥ 1 test/week via AI generator
- **Engagement:** Daily active parents per enrolled child
- **Time saved:** Avg. minutes from upload to test publish (target: < 5)
- **Retention:** % of schools renewing year-over-year
- **NPS:** Teacher and parent NPS (target: > 40)

---

## 10. Roadmap (Post-MVP)

- **Performance pass** (items 3–7 of the April 2026 perf audit) — already tracked
- **App Store / Play Store submission** — Android keystore + iOS dev team setup pending
- **Subject expansion** beyond grades 8–10 (grades 6–7, 11–12)
- **Offline-first test attempts** with sync
- **Parent-teacher chat** (1:1 messaging)
- **Multi-language** (Hindi, regional)
- **Analytics for admin** — cohort and trend reporting
- **Gamification** — student streaks, badges

---

## 11. Tech Stack at a Glance

**Mobile:** Flutter, Riverpod, go_router, Dio, Firebase Messaging
**Backend:** FastAPI, SQLAlchemy 2.0 async, PostgreSQL, Redis, MinIO
**AI:** Google Gemini 2.5 Flash + Groq LLaMA 3.3-70B fallback
**OCR/PDF:** PyMuPDF, Tesseract, ReportLab
**Notifications:** Firebase Cloud Messaging
**Infra:** Docker Compose, Nginx
