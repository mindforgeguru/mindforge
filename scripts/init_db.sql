-- =============================================================================
-- MIND FORGE — Initial Database Schema
-- PostgreSQL 15+
-- Soft-delete pattern: deleted_at IS NULL for all active-record queries
-- =============================================================================

-- Enable UUID extension (optional, we use integer PKs here)
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Enums ────────────────────────────────────────────────────────────────────
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('teacher', 'student', 'parent', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE attendance_status AS ENUM ('present', 'absent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE grade_type AS ENUM ('online', 'offline', 'manual');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE test_type AS ENUM ('online', 'offline');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- ACADEMIC YEARS
-- =============================================================================
CREATE TABLE IF NOT EXISTS academic_years (
    id                  SERIAL PRIMARY KEY,
    year_label          VARCHAR(20) NOT NULL,
    is_current          BOOLEAN NOT NULL DEFAULT FALSE,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at            TIMESTAMPTZ,
    started_by_admin_id INT   -- FK added after users table is created
);
CREATE INDEX IF NOT EXISTS ix_academic_years_id ON academic_years (id);

-- =============================================================================
-- USERS
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(100) NOT NULL UNIQUE,
    mpin_hash       VARCHAR(255) NOT NULL,
    role            user_role NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_approved     BOOLEAN NOT NULL DEFAULT FALSE,
    profile_pic_url     VARCHAR(500),
    academic_year_id    INT REFERENCES academic_years(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ                        -- NULL = active
);

-- Index for soft-delete queries (active users only)
CREATE INDEX IF NOT EXISTS idx_users_active ON users (id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_role   ON users (role) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_approval ON users (is_approved) WHERE deleted_at IS NULL;

-- =============================================================================
-- STUDENT PROFILES
-- =============================================================================
CREATE TABLE IF NOT EXISTS student_profiles (
    id                  SERIAL PRIMARY KEY,
    user_id             INT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    grade               SMALLINT NOT NULL CHECK (grade IN (8, 9, 10)),
    profile_pic_url     VARCHAR(500),
    additional_subjects JSONB,
    parent_user_id      INT REFERENCES users(id) ON DELETE SET NULL
);

-- =============================================================================
-- TEACHER PROFILES
-- =============================================================================
CREATE TABLE IF NOT EXISTS teacher_profiles (
    id                  SERIAL PRIMARY KEY,
    user_id             INT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    teachable_subjects  JSONB
);

CREATE INDEX IF NOT EXISTS ix_teacher_profiles_id ON teacher_profiles (id);

CREATE INDEX IF NOT EXISTS idx_student_profiles_parent ON student_profiles (parent_user_id);
CREATE INDEX IF NOT EXISTS idx_student_profiles_grade  ON student_profiles (grade);

-- =============================================================================
-- TIMETABLE CONFIGURATION
-- =============================================================================
CREATE TABLE IF NOT EXISTS timetable_configs (
    id                  SERIAL PRIMARY KEY,
    periods_per_day     SMALLINT NOT NULL DEFAULT 6,
    enable_weekends     BOOLEAN NOT NULL DEFAULT FALSE,
    period_times        JSONB,
    created_by_admin_id INT REFERENCES users(id) ON DELETE SET NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- TIMETABLE SLOTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS timetable_slots (
    id              SERIAL PRIMARY KEY,
    grade           SMALLINT NOT NULL CHECK (grade IN (8, 9, 10)),
    day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Mon
    period_number   SMALLINT NOT NULL,
    subject         VARCHAR(100) NOT NULL,
    teacher_id      INT REFERENCES users(id) ON DELETE SET NULL,
    start_time      TIME,
    end_time        TIME,
    is_holiday      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_timetable_slots_grade ON timetable_slots (grade);
CREATE UNIQUE INDEX IF NOT EXISTS uidx_timetable_slot
    ON timetable_slots (grade, day_of_week, period_number);

-- =============================================================================
-- ATTENDANCE
-- =============================================================================
CREATE TABLE IF NOT EXISTS attendance (
    id          SERIAL PRIMARY KEY,
    student_id  INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    teacher_id  INT REFERENCES users(id) ON DELETE SET NULL,
    grade       SMALLINT NOT NULL,
    period      SMALLINT NOT NULL,
    date        DATE NOT NULL,
    status      attendance_status NOT NULL DEFAULT 'present',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure one attendance record per student per date per period
CREATE UNIQUE INDEX IF NOT EXISTS uidx_attendance_student_date_period
    ON attendance (student_id, date, period);

CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance (student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_grade   ON attendance (grade);
CREATE INDEX IF NOT EXISTS idx_attendance_date    ON attendance (date);

-- =============================================================================
-- TESTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS tests (
    id                  SERIAL PRIMARY KEY,
    title               VARCHAR(300) NOT NULL,
    teacher_id          INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    grade               SMALLINT NOT NULL,
    subject             VARCHAR(100) NOT NULL,
    source_file_url     VARCHAR(500),
    test_type           test_type NOT NULL DEFAULT 'online',
    questions           JSONB,                          -- [{id, type, question, options, answer, marks}]
    total_marks         NUMERIC(6, 2) NOT NULL DEFAULT 0,
    time_limit_minutes  SMALLINT,
    is_published        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ                     -- NULL for offline; created_at + 3 days for online
);

CREATE INDEX IF NOT EXISTS idx_tests_teacher    ON tests (teacher_id);
CREATE INDEX IF NOT EXISTS idx_tests_grade      ON tests (grade);
CREATE INDEX IF NOT EXISTS idx_tests_published  ON tests (is_published) WHERE is_published = TRUE;
CREATE INDEX IF NOT EXISTS idx_tests_expires    ON tests (expires_at);

-- =============================================================================
-- TEST SUBMISSIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS test_submissions (
    id              SERIAL PRIMARY KEY,
    test_id         INT NOT NULL REFERENCES tests(id) ON DELETE CASCADE,
    student_id      INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    answers         JSONB,                              -- {question_id: answer_given}
    score           NUMERIC(6, 2),
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    auto_submitted  BOOLEAN NOT NULL DEFAULT FALSE
);

-- Each student can only submit once per test
CREATE UNIQUE INDEX IF NOT EXISTS uidx_submission_test_student
    ON test_submissions (test_id, student_id);

CREATE INDEX IF NOT EXISTS idx_submissions_student ON test_submissions (student_id);

-- =============================================================================
-- GRADES
-- =============================================================================
CREATE TABLE IF NOT EXISTS grades (
    id              SERIAL PRIMARY KEY,
    student_id      INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    teacher_id      INT REFERENCES users(id) ON DELETE SET NULL,
    subject         VARCHAR(100) NOT NULL,
    chapter         VARCHAR(200) NOT NULL,
    test_id         INT REFERENCES tests(id) ON DELETE SET NULL,
    marks_obtained  NUMERIC(6, 2) NOT NULL,
    max_marks       NUMERIC(6, 2) NOT NULL,
    grade_type      grade_type NOT NULL DEFAULT 'manual',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_marks CHECK (marks_obtained >= 0 AND max_marks > 0 AND marks_obtained <= max_marks)
);

CREATE INDEX IF NOT EXISTS idx_grades_student ON grades (student_id);
CREATE INDEX IF NOT EXISTS idx_grades_subject ON grades (subject);

-- =============================================================================
-- FEE STRUCTURES
-- =============================================================================
CREATE TABLE IF NOT EXISTS fee_structures (
    id              SERIAL PRIMARY KEY,
    academic_year   VARCHAR(20) NOT NULL,       -- e.g. "2024-25"
    grade           SMALLINT NOT NULL CHECK (grade IN (8, 9, 10)),
    base_amount     NUMERIC(10, 2) NOT NULL DEFAULT 0,
    economics_fee   NUMERIC(10, 2) NOT NULL DEFAULT 0,
    computer_fee    NUMERIC(10, 2) NOT NULL DEFAULT 0,
    ai_fee          NUMERIC(10, 2) NOT NULL DEFAULT 0,
    CONSTRAINT uq_fee_structure UNIQUE (academic_year, grade)
);

-- =============================================================================
-- FEE PAYMENTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS fee_payments (
    id                  SERIAL PRIMARY KEY,
    student_id          INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount              NUMERIC(10, 2) NOT NULL,
    paid_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by_admin_id INT REFERENCES users(id) ON DELETE SET NULL,
    notes               TEXT
);

CREATE INDEX IF NOT EXISTS idx_fee_payments_student ON fee_payments (student_id);

-- =============================================================================
-- PAYMENT INFO (bank details / UPI / QR shown to parents)
-- =============================================================================
CREATE TABLE IF NOT EXISTS payment_info (
    id              SERIAL PRIMARY KEY,
    bank_name       VARCHAR(200),
    account_holder  VARCHAR(200),
    account_number  VARCHAR(50),
    ifsc            VARCHAR(20),
    upi_id          VARCHAR(100),
    qr_code_url     VARCHAR(500),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- VIEWS — enforce soft-delete transparently
-- =============================================================================

CREATE OR REPLACE VIEW active_users AS
    SELECT * FROM users WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_students AS
    SELECT u.id, u.username, u.mpin_hash, u.role, u.is_active, u.is_approved,
           u.created_at, u.deleted_at,
           sp.grade, sp.profile_pic_url, sp.additional_subjects, sp.parent_user_id
    FROM users u
    JOIN student_profiles sp ON sp.user_id = u.id
    WHERE u.deleted_at IS NULL AND u.role = 'student';

CREATE OR REPLACE VIEW pending_tests AS
    SELECT t.*
    FROM tests t
    WHERE t.is_published = TRUE
      AND t.test_type = 'online'
      AND t.expires_at > NOW();

-- =============================================================================
-- SEED: default admin account
-- MPIN: 123456 (bcrypt hash — CHANGE IN PRODUCTION)
-- =============================================================================
INSERT INTO users (username, mpin_hash, role, is_active, is_approved)
VALUES (
    'admin',
    '$2b$12$80F76W9aI4iuWX8e7zsR3enN1OQL01RDM/69XBQhWVaaeKO2yaD8W', -- bcrypt of '123456'
    'admin',
    TRUE,
    TRUE
) ON CONFLICT (username) DO NOTHING;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE users IS 'All platform users (teachers, students, parents, admins). Soft-deleted via deleted_at.';
COMMENT ON TABLE student_profiles IS 'Extended profile for student-role users.';
COMMENT ON TABLE attendance IS 'Per-period attendance records. Unique constraint prevents duplicate entries.';
COMMENT ON TABLE tests IS 'AI-generated test papers. Online tests expire after 3 days.';
COMMENT ON TABLE test_submissions IS 'Student answers and auto-graded scores for online tests.';
COMMENT ON TABLE grades IS 'All grade entries — online (auto), offline, or manually entered.';
COMMENT ON TABLE fee_structures IS 'Annual fee amounts broken down by component per grade.';
COMMENT ON TABLE fee_payments IS 'Individual payment receipts for students.';
COMMENT ON TABLE payment_info IS 'Single-row bank/UPI payment details shown to parents.';
