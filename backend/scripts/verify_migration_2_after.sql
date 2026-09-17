-- =============================================================================
-- Multitenancy migration (030–035) — STAGING verification, STEP 2 of 2
-- Run this on the SAME staging clone, AFTER `alembic upgrade head`.
-- It diffs against _mt_baseline (from step 1) and checks tenant integrity.
--
--   psql "$STAGING_DSN" -f backend/scripts/verify_migration_2_after.sql
--
-- PASS criteria (all must hold):
--   • Report 1: every delta = 0                (no rows lost or duplicated)
--   • Report 2: zero rows                      (no student data left unstamped)
--   • Report 3: exactly one school, slug hansel-gretel
--   • Report 4: non-owner users all share that one school_id
--   • Report 5: students_mismatched = 0 and count matches step 1
-- =============================================================================

-- Rebuild the "after" counts + NULL-school_id counts dynamically.
DROP TABLE IF EXISTS _mt_after;
CREATE TABLE _mt_after (tbl text PRIMARY KEY, n bigint, null_school bigint);

DO $$
DECLARE
    t text;
    c bigint;
    nn bigint;
    tables text[] := ARRAY[
        'users',
        'student_profiles','teacher_profiles','academic_years',
        'attendance','timetable_configs','timetable_slots',
        'grades','tests','test_submissions',
        'fee_structures','fee_payments','payment_info',
        'homework','homework_completions','broadcasts',
        'old_test_papers','chapter_documents','syllabus_entries',
        'student_xp','xp_transactions','feedback_reports',
        'chapter_presentations','presentation_slides',
        'presentation_teacher_progress','presentation_period_logs',
        'audit_logs'
    ];
BEGIN
    FOREACH t IN ARRAY tables LOOP
        IF to_regclass(t) IS NULL THEN CONTINUE; END IF;
        EXECUTE format('SELECT count(*) FROM %I', t) INTO c;
        EXECUTE format('SELECT count(*) FROM %I WHERE school_id IS NULL', t) INTO nn;
        INSERT INTO _mt_after VALUES (t, c, nn);
    END LOOP;
END $$;

-- ── Report 1: ROW-COUNT INTEGRITY — every delta must be 0 ────────────────────
\echo '== Report 1: row-count integrity (delta must be 0) =='
SELECT COALESCE(b.tbl, a.tbl)          AS tbl,
       b.n                             AS before_rows,
       a.n                             AS after_rows,
       COALESCE(a.n,0) - COALESCE(b.n,0) AS delta,
       CASE WHEN COALESCE(a.n,0) = COALESCE(b.n,0) THEN 'OK'
            ELSE '*** MISMATCH ***' END AS status
FROM _mt_baseline b
FULL JOIN _mt_after a USING (tbl)
ORDER BY tbl;

-- ── Report 2: UNSTAMPED STUDENT DATA — must return ZERO rows ─────────────────
-- Every tenant/student table must be fully backfilled. 'users' and 'audit_logs'
-- are excluded here because a school-less owner (users) and platform-level audit
-- entries (audit_logs) may legitimately have NULL school_id — checked separately.
\echo '== Report 2: tables with unstamped rows (expect ZERO rows) =='
SELECT tbl, null_school
FROM _mt_after
WHERE null_school > 0
  AND tbl NOT IN ('users','audit_logs')
ORDER BY tbl;

-- users: the ONLY acceptable NULL school_id is role = 'owner'. Must be 0.
\echo '== Report 2b: non-owner users left unstamped (must be 0) =='
SELECT count(*) AS users_nonowner_unstamped
FROM users
WHERE school_id IS NULL AND role::text <> 'owner';

-- ── Report 3: exactly one school, and it is Hansel & Gretel ──────────────────
\echo '== Report 3: schools (expect exactly 1 row, slug hansel-gretel) =='
SELECT id, name, slug, is_active, subscription_status FROM schools ORDER BY id;

-- ── Report 4: user distribution by school + role ─────────────────────────────
\echo '== Report 4: users by school_id + role =='
SELECT school_id, role, count(*) AS users
FROM users
GROUP BY school_id, role
ORDER BY school_id NULLS FIRST, role;

-- ── Report 5: SPOT-CHECK hansal_sir and his students survived intact ─────────
-- Student set from step 1 = direct records (attendance/grades) UNION
-- timetable-based class membership (students in the grades he teaches).
-- Every one must still exist and now share hansal_sir's school_id.
-- students_after must equal students_before; students_mismatched must be 0.
\echo '== Report 5: hansal_sir spot-check — timetable-broadened (mismatched must be 0) =='
WITH t AS (
    SELECT id, school_id FROM users WHERE username = 'hansal_sir' AND role = 'teacher'
)
SELECT
    (SELECT school_id FROM t)                                   AS teacher_school_id,
    (SELECT count(*) FROM _mt_hansal_students)                  AS students_before,
    count(*)                                                    AS students_after,
    count(*) FILTER (WHERE su.school_id = (SELECT school_id FROM t)) AS students_same_school,
    count(*) FILTER (WHERE su.school_id IS DISTINCT FROM (SELECT school_id FROM t))
                                                                AS students_mismatched
FROM _mt_hansal_students h
JOIN users su ON su.id = h.student_id;

-- Cleanup (comment out if you want to keep the scratch tables):
-- DROP TABLE IF EXISTS _mt_baseline, _mt_after, _mt_hansal_students;
