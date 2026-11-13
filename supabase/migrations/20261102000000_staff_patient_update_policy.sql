-- ============================================================================
-- MKES CARE+ — Migration: Staff and Admin Patient Update Policy
-- File: supabase/migrations/20261102000000_staff_patient_update_policy.sql
-- Description:
--   Enforces least-privilege RLS for patient updates:
--   Permits authenticated users with roles 'admin', 'staff', 'doctor', or 'receptionist'
--   to update patient demographic and contact details (name, mobile, address, dob, etc.).
--   Strictly prevents anonymous or unauthorized updates.
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'patients' AND policyname = 'Staff and Admins can update patients'
  ) THEN
    DROP POLICY "Staff and Admins can update patients" ON public.patients;
  END IF;

  CREATE POLICY "Staff and Admins can update patients"
    ON public.patients FOR UPDATE TO authenticated
    USING (
      public.is_admin() OR
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'staff', 'doctor', 'receptionist')
          AND profiles.is_active = true
      )
    )
    WITH CHECK (
      public.is_admin() OR
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'staff', 'doctor', 'receptionist')
          AND profiles.is_active = true
      )
    );
END $$;

