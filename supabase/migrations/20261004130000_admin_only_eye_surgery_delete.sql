-- =====================================================================
-- MIGRATION: 20261004130000_admin_only_eye_surgery_delete.sql
-- DESCRIPTION: Enforce Admin-Only Deletion on public.eye_surgeries
--              Dual-layer security: RLS policy + BEFORE DELETE trigger.
--              Preserves inventory transactions, patient records, and appointments.
-- =====================================================================

-- 1. Ensure authenticated role has DELETE privilege at the table level so PostgreSQL evaluates RLS
GRANT DELETE ON TABLE public.eye_surgeries TO authenticated;
GRANT ALL ON TABLE public.eye_surgeries TO service_role;

-- 2. Drop any existing overlapping DELETE policies on public.eye_surgeries
DROP POLICY IF EXISTS "Admins can delete eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Staff can delete eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Admins and Staff can delete eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Anyone authenticated can delete eye surgeries" ON public.eye_surgeries;

-- 3. Create RLS DELETE policy strictly restricted to Admins using trusted public.is_admin()
CREATE POLICY "Admins can delete eye surgeries" ON public.eye_surgeries
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- 4. Create BEFORE DELETE trigger function to guarantee dual-layer security.
-- If an authenticated non-admin attempts deletion directly via SQL or PostgREST,
-- raise a permission error immediately.
CREATE OR REPLACE FUNCTION public.validate_eye_surgery_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When executed by an authenticated client, strictly require Admin role
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can delete eye surgeries';
  END IF;
  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_eye_surgery_deletion() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_eye_surgery_deletion() TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_eye_surgery_deletion() TO service_role;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_deletion ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_deletion
BEFORE DELETE ON public.eye_surgeries
FOR EACH ROW
EXECUTE FUNCTION public.validate_eye_surgery_deletion();
