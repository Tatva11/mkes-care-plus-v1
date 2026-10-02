-- ============================================================
-- SPRINT 6: STAFF FULL INVENTORY & DEPARTMENT ACCESS MIGRATION
-- ============================================================
-- Grants authenticated active Staff users the EXACT SAME permissions
-- as Admins for Inventory Management and Department Management.
--
-- ADMIN PERMISSIONS == STAFF PERMISSIONS (Inventory module)
--
-- 1. public.inventory: SELECT, INSERT, UPDATE, DELETE for Admin + Staff
-- 2. public.departments: SELECT, INSERT, UPDATE, DELETE for Admin + Staff
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

-- ============================================================
-- 2. INVENTORY RLS POLICIES (Admin + Staff Full Parity)
-- ============================================================
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Clean up any previous policies on public.inventory
DROP POLICY IF EXISTS "Admins and Staff have full access to inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins and Staff can insert inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can manage inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can update inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can delete inventory" ON public.inventory;
DROP POLICY IF EXISTS "Authenticated users can view inventory" ON public.inventory;

-- Allow all authenticated users (clinical staff, doctors, admins) to view inventory
CREATE POLICY "Authenticated users can view inventory" ON public.inventory
  FOR SELECT TO authenticated
  USING (true);

-- Allow Admins and Staff full INSERT, UPDATE, DELETE permissions on inventory
CREATE POLICY "Admins and Staff have full access to inventory" ON public.inventory
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- ============================================================
-- 3. DEPARTMENT RLS POLICIES (Admin + Staff Full Parity)
-- ============================================================
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

-- Clean up any previous policies on public.departments
DROP POLICY IF EXISTS "Admins and Staff have full access to departments" ON public.departments;
DROP POLICY IF EXISTS "Admins can manage departments" ON public.departments;
DROP POLICY IF EXISTS "Admins can insert departments" ON public.departments;
DROP POLICY IF EXISTS "Admins can update departments" ON public.departments;
DROP POLICY IF EXISTS "Admins can delete departments" ON public.departments;
DROP POLICY IF EXISTS "Anyone can view departments" ON public.departments;
DROP POLICY IF EXISTS "Authenticated users can view departments" ON public.departments;

-- Allow all authenticated users to read departments (needed for inventory selectors & filters)
CREATE POLICY "Authenticated users can view departments" ON public.departments
  FOR SELECT TO authenticated
  USING (true);

-- Allow Admins and Staff full INSERT, UPDATE, DELETE permissions on departments
CREATE POLICY "Admins and Staff have full access to departments" ON public.departments
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- ============================================================
-- 4. TABLE GRANTS
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory TO authenticated;
GRANT ALL ON TABLE public.inventory TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.departments TO authenticated;
GRANT ALL ON TABLE public.departments TO service_role;
