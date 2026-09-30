-- ============================================================
-- SPRINT 6: STAFF ADD NEW INVENTORY PRODUCTS ACCESS
-- ============================================================
-- Allows authenticated active Staff users to INSERT new products
-- into public.inventory while preserving Admin-only UPDATE/DELETE
-- and maintaining authenticated SELECT.
-- ============================================================

-- 1. Ensure helper function exists
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

-- 2. Ensure RLS is active on public.inventory
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- 3. Policy: Authenticated users can view inventory
DROP POLICY IF EXISTS "Authenticated users can view inventory" ON public.inventory;
CREATE POLICY "Authenticated users can view inventory" ON public.inventory
  FOR SELECT TO authenticated
  USING (true);

-- 4. Clean up previous policies and create Insert Policy for Admin & Staff
DROP POLICY IF EXISTS "Admins and Staff can insert inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can manage inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can update inventory" ON public.inventory;
DROP POLICY IF EXISTS "Admins can delete inventory" ON public.inventory;

CREATE POLICY "Admins and Staff can insert inventory" ON public.inventory
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_or_staff());

-- 5. Policy: Only Admins can update inventory products
CREATE POLICY "Admins can update inventory" ON public.inventory
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 6. Policy: Only Admins can delete inventory products
CREATE POLICY "Admins can delete inventory" ON public.inventory
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- 7. Table Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory TO authenticated;
GRANT ALL ON TABLE public.inventory TO service_role;
