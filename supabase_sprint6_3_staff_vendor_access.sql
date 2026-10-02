-- ============================================================
-- SPRINT 6.3 ENHANCEMENT: STAFF FULL VENDOR MANAGEMENT ACCESS
-- ============================================================
-- Gives Staff users full access to Vendor Management:
-- SELECT, INSERT, UPDATE, DELETE on public.vendors.
-- Preserves Admin access.
-- ============================================================

-- 1. Helper function: Checks if authenticated user is active Admin or Staff
CREATE OR REPLACE FUNCTION public.is_admin_or_staff()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('admin', 'staff')
      AND is_active = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_admin_or_staff() TO authenticated;

-- 2. Clean up previous policies on vendors
DROP POLICY IF EXISTS "Admins have full access to vendors" ON public.vendors;
DROP POLICY IF EXISTS "Admins can manage vendors" ON public.vendors;
DROP POLICY IF EXISTS "Admins and Staff have full access to vendors" ON public.vendors;
DROP POLICY IF EXISTS "Authenticated users can view vendors" ON public.vendors;

-- 3. Policy: Admin and Staff have full CRUD access
CREATE POLICY "Admins and Staff have full access to vendors" ON public.vendors
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- 4. Policy: Authenticated users can view active vendors (e.g. for supplier dropdowns)
CREATE POLICY "Authenticated users can view vendors" ON public.vendors
  FOR SELECT TO authenticated
  USING (true);

-- 5. Table Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.vendors TO authenticated;
GRANT ALL ON TABLE public.vendors TO service_role;
