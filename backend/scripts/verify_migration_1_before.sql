-- =============================================================================
-- Multitenancy migration (030–035) — STAGING verification, STEP 1 of 2
-- Run this on a STAGING CLONE of production, BEFORE `alembic upgrade head`.
-- It snapshots row counts into a persistent table (_mt_baseline) that survives
-- the migration, so step 2 can diff automatically.
--
--   psql "$STAGING_DSN" -f backend/scripts/verify_migration_1_before.sql
--
-- Then run the migration, then run verify_migration_2_after.sql.
-- NOTE: run this against the PRE-migration (single-tenant) schema.
-- =============================================================================

DROP TABLE IF EXISTS _mt_baseline;
CREATE TABLE _mt_baseline (tbl text PRIMARY KEY, n bigint);

DO $$
DECLARE
    t text;
    c bigint;
    -- every table the migration touches (users + all tenant tables + audit_logs)
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
        IF to_regclass(t) IS NULL THEN
            RAISE NOTICE 'skip (missing on this clone): %', t;
            CONTINUE;
        END IF;
        EXECUTE format('SELECT count(*) FROM %I', t) INTO c;
        INSERT INTO _mt_baseline VALUES (t, c);
    END LOOP;
END $$;

-- Baseline snapshot (keep this output for your records)
SELECT tbl, n AS before_rows FROM _mt_baseline ORDER BY tbl;

-- Spot-check target: hansal_sir's students, defined BROADLY as either
--   (a) students he has directly recorded — teacher_id on their attendance/grades, or
--   (b) students in any grade he teaches on the timetable (timetable_slots.teacher_id).
-- Runs on the PRE-migration single-tenant schema, so no school_id is referenced
-- here (there is only one school's data). Persist the set for step 2.
DROP TABLE IF EXISTS _mt_hansal_students;
CREATE TABLE _mt_hansal_students AS
WITH hs AS (
    SELECT id FROM users WHERE username = 'hansal_sir' AND role = 'teacher'
)
SELECT DISTINCT s.student_id
FROM (
    -- (a) direct records
    SELECT student_id FROM attendance WHERE teacher_id = (SELECT id FROM hs)
    UNION
    SELECT student_id FROM grades     WHERE teacher_id = (SELECT id FROM hs)
    UNION
    -- (b) timetable-based class membership: students in the grades he teaches
    SELECT sp.user_id AS student_id
      FROM student_profiles sp
     WHERE sp.grade IN (
         SELECT DISTINCT ts.grade
           FROM timetable_slots ts
          WHERE ts.teacher_id = (SELECT id FROM hs)
     )
) s;

-- Breakdown so you can see where the students come from (direct vs timetable).
WITH hs AS (
    SELECT id FROM users WHERE username = 'hansal_sir' AND role = 'teacher'
)
SELECT
    (SELECT id FROM hs)                             AS hansal_sir_id,
    (SELECT count(*) FROM _mt_hansal_students)      AS students_total_before,
    (SELECT count(DISTINCT student_id) FROM (
        SELECT student_id FROM attendance WHERE teacher_id = (SELECT id FROM hs)
        UNION
        SELECT student_id FROM grades     WHERE teacher_id = (SELECT id FROM hs)
     ) d)                                           AS via_direct_records,
    (SELECT count(*) FROM student_profiles sp
       WHERE sp.grade IN (
           SELECT DISTINCT grade FROM timetable_slots WHERE teacher_id = (SELECT id FROM hs)
       ))                                           AS via_timetable_grades;
