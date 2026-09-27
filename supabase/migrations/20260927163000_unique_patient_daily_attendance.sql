-- =============================================================================
-- Migration: 20260927163000_unique_patient_daily_attendance.sql
-- Description: Enforce that a patient can have ONLY ONE attendance record per day
-- across all staff. The first staff member to attend is retained.
-- =============================================================================

-- =============================================================================
-- STEP 1: INSPECTION (Run first to check for any duplicate conflicts)
-- =============================================================================
-- SELECT
--   pa.id,
--   pa.patient_id,
--   p.patient_number,
--   p.name AS patient_name,
--   pa.staff_id,
--   pr.full_name AS staff_name,
--   pa.attendance_date,
--   pa.attended_at
-- FROM public.patient_attendance pa
-- LEFT JOIN public.patients p ON p.id = pa.patient_id
-- LEFT JOIN public.profiles pr ON pr.id = pa.staff_id
-- WHERE (pa.patient_id, pa.attendance_date) IN (
--   SELECT patient_id, attendance_date
--   FROM public.patient_attendance
--   GROUP BY patient_id, attendance_date
--   HAVING COUNT(*) > 1
-- )
-- ORDER BY pa.patient_id, pa.attendance_date, pa.attended_at ASC;


-- =============================================================================
-- STEP 2: CLEANUP DUPLICATES (Retains the earliest record by attended_at)
-- =============================================================================
DELETE FROM public.patient_attendance
WHERE id IN (
  SELECT id FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY patient_id, attendance_date
        ORDER BY attended_at ASC
      ) AS rnum
    FROM public.patient_attendance
  ) ranked
  WHERE ranked.rnum > 1
);


-- =============================================================================
-- STEP 3: APPLY UNIQUE CONSTRAINT (patient_id, attendance_date)
-- =============================================================================
BEGIN;

-- Drop old constraints that permitted multiple staff per patient per day
ALTER TABLE public.patient_attendance
  DROP CONSTRAINT IF EXISTS patient_attendance_patient_staff_date_key;

ALTER TABLE public.patient_attendance
  DROP CONSTRAINT IF EXISTS patient_attendance_patient_id_staff_id_attendance_date_key;

ALTER TABLE public.patient_attendance
  DROP CONSTRAINT IF EXISTS patient_attendance_patient_id_attendance_date_key;

-- Add strict daily patient uniqueness constraint
ALTER TABLE public.patient_attendance
  ADD CONSTRAINT patient_attendance_patient_id_attendance_date_key
  UNIQUE (patient_id, attendance_date);

-- Supporting composite index for fast lookups by patient and date
CREATE INDEX IF NOT EXISTS idx_patient_attendance_patient_date
  ON public.patient_attendance(patient_id, attendance_date);

COMMIT;


-- =============================================================================
-- STEP 4: VERIFY CROSS-STAFF READ POLICY
-- =============================================================================
-- Ensures active staff can read all today's patient attendance records
-- to determine which patients are already attended.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'patient_attendance'
      AND policyname = 'Staff can read today patient attendance'
  ) THEN
    CREATE POLICY "Staff can read today patient attendance"
    ON public.patient_attendance
    FOR SELECT TO authenticated
    USING (
      attendance_date = CURRENT_DATE
      AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = 'staff'
          AND profiles.is_active = true
      )
    );
  END IF;
END $$;
