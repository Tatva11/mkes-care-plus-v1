-- ============================================================
-- MKES CARE+ Sprint 3 Phase 2: use the existing public.patients table.
-- ============================================================
-- Existing columns: id, patient_number, name, dob, address, mobile,
-- department, reference, visit_date, created_at, updated_at.
--
-- FIX (Sprint 3 Phase 2):
--   The legacy patient INSERT previously set department = 'Unassigned',
--   which violates the existing patients_department_check constraint.
--   The allowed values are: 'Eye', 'Dental', 'Optical', 'Administration'.
--
--   FIX: The `department` column is now OMITTED from the legacy INSERT so
--   it defaults to NULL. In PostgreSQL, NULL always passes a CHECK constraint
--   (evaluates to UNKNOWN, not FALSE), so the existing constraint is fully
--   preserved and not weakened in any way.
--
-- Verification checklist (all confirmed before editing):
--   [1] patients_department_check allows: 'Eye','Dental','Optical','Administration'
--   [2] patient_attendance.patient_id is TEXT in Phase 1 (converted to UUID here)
--   [3] INSERT uses ON CONFLICT DO NOTHING to prevent duplicates
--   [4] Legacy reg numbers are mapped to patients.id via patient_number match
--   [5] patient_attendance.patient_id becomes UUID FK to patients(id)
--   [6] Existing RLS policies are dropped and re-created (idempotent)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_patients_patient_number ON public.patients(patient_number);
CREATE INDEX IF NOT EXISTS idx_patients_name ON public.patients(name);
CREATE INDEX IF NOT EXISTS idx_patients_mobile ON public.patients(mobile);

ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

-- Drop all known policy names so re-run is idempotent.
DROP POLICY IF EXISTS "Admins have full access to patients" ON public.patients;
DROP POLICY IF EXISTS "Admins can view patients" ON public.patients;
DROP POLICY IF EXISTS "Staff can view active patients" ON public.patients;
DROP POLICY IF EXISTS "Admins can insert patients" ON public.patients;
DROP POLICY IF EXISTS "Admins can update patients" ON public.patients;

CREATE POLICY "Admins can view patients" ON public.patients
FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY "Admins can insert patients" ON public.patients
FOR INSERT TO authenticated WITH CHECK (public.is_admin());

CREATE POLICY "Admins can update patients" ON public.patients
FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Staff can view active patients" ON public.patients
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = 'staff'
      AND profiles.is_active = true
  )
);

-- ============================================================
-- Phase 1 → Phase 2 migration:
-- Convert patient_attendance.patient_id from TEXT (legacy registration
-- number) to UUID (FK to patients.id).
-- Only runs when patient_id is still TEXT type (safe to re-run).
-- ============================================================
DO $$
DECLARE
  patient_id_type TEXT;
  unmatched_count INTEGER;
BEGIN
  -- [2] Detect current type of patient_attendance.patient_id.
  SELECT data_type INTO patient_id_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'patient_attendance'
    AND column_name = 'patient_id';

  IF patient_id_type = 'text' THEN
    -- --------------------------------------------------------
    -- [3] Create minimal stub patient rows for any attendance
    --     records whose registration number has no matching
    --     patient row yet.  ON CONFLICT DO NOTHING prevents
    --     duplicates if this block is ever re-entered.
    --
    --     IMPORTANT: `department` is intentionally OMITTED here.
    --     The existing patients_department_check constraint only
    --     allows: 'Eye', 'Dental', 'Optical', 'Administration'.
    --     'Unassigned' is NOT in that list and would violate it.
    --     NULL is safe: PostgreSQL CHECK constraints treat NULL
    --     as UNKNOWN (not FALSE), so the row is accepted.
    --     The constraint itself is NOT removed or altered.
    -- --------------------------------------------------------
    INSERT INTO public.patients (
      patient_number,
      name,
      mobile,
      reference
    )
    SELECT DISTINCT
      attendance.patient_id,
      'Legacy patient ' || attendance.patient_id,
      'Not provided',
      'Migrated from Sprint 3 Phase 1'
    FROM public.patient_attendance attendance
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.patients patients
      WHERE patients.patient_number = attendance.patient_id
    )
    ON CONFLICT (patient_number) DO NOTHING;

    -- [4] Map legacy registration numbers → patients.id (UUID).
    UPDATE public.patient_attendance attendance
    SET patient_id = patients.id::text
    FROM public.patients patients
    WHERE attendance.patient_id = patients.patient_number;

    -- Verify all patient_id values are now valid UUIDs.
    SELECT COUNT(*) INTO unmatched_count
    FROM public.patient_attendance
    WHERE patient_id IS NOT NULL
      AND patient_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

    IF unmatched_count > 0 THEN
      RAISE EXCEPTION
        'Sprint 3 Phase 2 migration: % patient_attendance row(s) could not be '
        'mapped to a patients.id UUID. Check for orphaned attendance records.',
        unmatched_count;
    END IF;

    -- [5] Promote patient_id column from TEXT to UUID.
    ALTER TABLE public.patient_attendance
      ALTER COLUMN patient_id TYPE UUID USING patient_id::uuid;
  END IF;
END $$;

-- [5] Add FK constraint if not already present (idempotent).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'patient_attendance_patient_id_fkey'
      AND conrelid = 'public.patient_attendance'::regclass
  ) THEN
    ALTER TABLE public.patient_attendance
      ADD CONSTRAINT patient_attendance_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;
  END IF;
END $$;
