-- ============================================================
-- MKES CARE+ Sprint 3 Patient Attendance — Fix Migration
-- ============================================================
-- Run AFTER supabase_sprint3_patient_attendance.sql and
-- supabase_sprint3_patients.sql have been applied.
--
-- CHANGES:
--   1. Fix UNIQUE constraint on patient_attendance:
--      OLD: UNIQUE(patient_id, attendance_date)
--           → only ONE attendance record per patient per day (wrong — blocks
--             a second staff member from also marking the same patient)
--      NEW: UNIQUE(patient_id, staff_id, attendance_date)
--           → each staff member can record one attendance per patient per day
--
--   2. Add a date-scoped staff SELECT policy so the staff UI can check
--      whether ANY staff has already attended a given patient today
--      (read-only, limited to today's records only).
-- ============================================================

-- ─── 1. Fix UNIQUE constraint ────────────────────────────────────────────────

-- Drop the old per-patient-per-day unique constraint.
-- Using DO $$ to make this idempotent (safe to re-run).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'patient_attendance_patient_id_attendance_date_key'
      AND conrelid = 'public.patient_attendance'::regclass
  ) THEN
    ALTER TABLE public.patient_attendance
      DROP CONSTRAINT patient_attendance_patient_id_attendance_date_key;
  END IF;
END $$;

-- Add the correct per-staff-per-patient-per-day unique constraint.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'patient_attendance_patient_staff_date_key'
      AND conrelid = 'public.patient_attendance'::regclass
  ) THEN
    ALTER TABLE public.patient_attendance
      ADD CONSTRAINT patient_attendance_patient_staff_date_key
      UNIQUE (patient_id, staff_id, attendance_date);
  END IF;
END $$;

-- Supporting index for the new composite unique (also used by markAttended queries).
CREATE INDEX IF NOT EXISTS idx_patient_attendance_patient_staff_date
  ON public.patient_attendance(patient_id, staff_id, attendance_date);

-- ─── 2. Add today-scoped staff SELECT policy ─────────────────────────────────
-- Allows active staff to read ALL attendance records for today.
-- Purpose: staff UI can show "patient already attended by [someone]" even if
--          it was a different staff member who marked it.
-- Scope: read-only, limited to current calendar date (no historical leakage).
-- This does NOT weaken the existing "Staff can insert own patient attendance"
-- policy — inserts still require auth.uid() == staff_id AND is_active staff.

DROP POLICY IF EXISTS "Staff can read today patient attendance"
  ON public.patient_attendance;

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

-- ─── 3. Ensure admin policy still covers all dates ───────────────────────────
-- The existing admin "FOR ALL" policy already covers SELECT for all dates.
-- No change needed for admin; documenting here for clarity.
-- "Admins have full access to patient attendance" (FOR ALL, USING is_admin()).
