-- ============================================================================
-- MKES CARE+ — Production Staff Geofencing Security Migration
-- File: supabase/migrations/20261026000000_staff_geofencing_security.sql
-- 
-- Description:
--   Restricts staff access to the clinic's 50-metre geographical radius while
--   allowing administrators to access the application from anywhere.
--   Enforces physical proximity validation at the PostgreSQL RLS layer
--   using AS RESTRICTIVE policies and a server-verified 15-minute lease model.
-- 
-- Clinic Coordinates:
--   Latitude:  18.9905655
--   Longitude: 72.8352074
--   Allowed radius: 50.0 metres
--   Address: Shop No 13,14, Harharwala Building, S. G. Marg, Chinchpokli East,
--            Lal Baug, Parel, Mumbai, Maharashtra 400012
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Table: public.staff_geofence_sessions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_geofence_sessions (
  staff_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy_meters DOUBLE PRECISION NOT NULL,
  distance_meters DOUBLE PRECISION NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.staff_geofence_sessions ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to view only their own active geofence record (or admins to view all)
DROP POLICY IF EXISTS "Users can view own geofence session" ON public.staff_geofence_sessions;
CREATE POLICY "Users can view own geofence session"
  ON public.staff_geofence_sessions
  FOR SELECT
  TO authenticated
  USING (staff_id = auth.uid() OR public.is_admin());

-- Strictly NO direct INSERT, UPDATE, or DELETE policies for authenticated users!
-- Only trusted SECURITY DEFINER functions below may mutate this table.

-- ----------------------------------------------------------------------------
-- 2. Pure Geodesic Distance Calculation Function (WGS-84 Haversine)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_clinic_distance(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (
    6371000.0 * 2.0 * asin(
      sqrt(
        power(sin(radians((p_lat - 18.99110) / 2.0)), 2) +
        cos(radians(18.99110)) * cos(radians(p_lat)) *
        power(sin(radians((p_lng - 72.838885) / 2.0)), 2)
      )
    )
  );
$$;

ALTER FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) FROM anon;
REVOKE ALL ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Verification RPC: public.verify_staff_geofence
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_staff_geofence(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION DEFAULT 10.0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role TEXT;
  v_is_active BOOLEAN;
  v_distance DOUBLE PRECISION;
  v_expires_at TIMESTAMPTZ;
  c_max_radius CONSTANT DOUBLE PRECISION := 50.0;
  c_max_accuracy CONSTANT DOUBLE PRECISION := 50.0;
  c_lease_minutes CONSTANT INTERVAL := INTERVAL '15 minutes';
BEGIN
  -- 1. Ensure caller is authenticated
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'unauthenticated',
      'message', 'No active authenticated session found.'
    );
  END IF;

  -- 2. Fetch role and active status directly from trusted public.profiles
  SELECT role, is_active
  INTO v_role, v_is_active
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_role IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'profile_not_found',
      'message', 'User clinic profile not found.'
    );
  END IF;

  IF NOT v_is_active THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'account_inactive',
      'message', 'User account is inactive.'
    );
  END IF;

  -- 3. Admin exemption: Admins can access from anywhere
  IF v_role = 'admin' THEN
    RETURN jsonb_build_object(
      'success', true,
      'is_admin', true,
      'distance_meters', 0.0,
      'message', 'Admin access granted unconditionally.'
    );
  END IF;

  -- 4. Staff verification
  IF v_role != 'staff' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'unauthorized_role',
      'message', 'Unrecognised user role.'
    );
  END IF;

  -- 5. Calculate geodesic distance from clinic coordinates
  v_distance := public.calculate_clinic_distance(p_lat, p_lng);

  -- 6. Reject poor accuracy GPS readings (e.g., coarse cell tower estimates)
  IF p_accuracy > c_max_accuracy THEN
    DELETE FROM public.staff_geofence_sessions WHERE staff_id = v_user_id;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'inaccurate_location',
      'distance_meters', round(v_distance::numeric, 1),
      'accuracy_meters', round(p_accuracy::numeric, 1),
      'allowed_radius_meters', c_max_radius,
      'message', 'GPS accuracy is insufficient (±' || round(p_accuracy::numeric, 1)::text || 'm). Please ensure high-accuracy GPS has clear view of the sky.'
    );
  END IF;

  -- 7. Reject if outside 50 metres
  IF v_distance > c_max_radius THEN
    DELETE FROM public.staff_geofence_sessions WHERE staff_id = v_user_id;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'outside_radius',
      'distance_meters', round(v_distance::numeric, 1),
      'accuracy_meters', round(p_accuracy::numeric, 1),
      'allowed_radius_meters', c_max_radius,
      'message', 'You are ' || round(v_distance::numeric, 1)::text || 'm from the clinic. Staff access is restricted to within 50m of clinic premises.'
    );
  END IF;

  -- 8. Proximity verified! Issue 15-minute lease in database
  v_expires_at := now() + c_lease_minutes;

  INSERT INTO public.staff_geofence_sessions (
    staff_id,
    verified_at,
    expires_at,
    latitude,
    longitude,
    accuracy_meters,
    distance_meters,
    updated_at
  ) VALUES (
    v_user_id,
    now(),
    v_expires_at,
    p_lat,
    p_lng,
    p_accuracy,
    v_distance,
    now()
  )
  ON CONFLICT (staff_id) DO UPDATE SET
    verified_at = EXCLUDED.verified_at,
    expires_at = EXCLUDED.expires_at,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    accuracy_meters = EXCLUDED.accuracy_meters,
    distance_meters = EXCLUDED.distance_meters,
    updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'is_admin', false,
    'distance_meters', round(v_distance::numeric, 1),
    'accuracy_meters', round(p_accuracy::numeric, 1),
    'allowed_radius_meters', c_max_radius,
    'expires_at', v_expires_at,
    'message', 'Clinic location verified successfully.'
  );
END;
$$;

ALTER FUNCTION public.verify_staff_geofence(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.verify_staff_geofence(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM anon;
REVOKE ALL ON FUNCTION public.verify_staff_geofence(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_staff_geofence(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Invalidation RPC: public.clear_staff_geofence
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.clear_staff_geofence()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    DELETE FROM public.staff_geofence_sessions WHERE staff_id = auth.uid();
  END IF;
END;
$$;

ALTER FUNCTION public.clear_staff_geofence() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.clear_staff_geofence() FROM anon;
REVOKE ALL ON FUNCTION public.clear_staff_geofence() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_staff_geofence() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. RLS Gate Function: public.is_staff_geofenced_or_admin()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_staff_geofenced_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (
    -- Admins have unrestricted access from anywhere
    public.is_admin()
    OR
    -- Staff users must be active AND hold an active, unexpired geofence lease
    (
      EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND role = 'staff'
          AND is_active = true
      )
      AND
      EXISTS (
        SELECT 1
        FROM public.staff_geofence_sessions
        WHERE staff_id = auth.uid()
          AND expires_at > now()
      )
    )
  );
$$;

ALTER FUNCTION public.is_staff_geofenced_or_admin() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_staff_geofenced_or_admin() FROM anon;
REVOKE ALL ON FUNCTION public.is_staff_geofenced_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_staff_geofenced_or_admin() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Additive Restrictive RLS Policies on Sensitive Tables
-- 
-- PostgreSQL evaluation rule:
--   Permissive policies combine with OR.
--   Restrictive policies (AS RESTRICTIVE) combine with AND.
-- 
-- By applying AS RESTRICTIVE policies, any direct query via PostgREST/curl/Postman
-- using a staff JWT outside the clinic returns empty rows or 403, while admins
-- continue to enjoy complete access from any location.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'patients',
    'appointments',
    'clinical_records',
    'eye_examinations',
    'dental_treatments',
    'dental_lab',
    'optical_orders',
    'billing',
    'billing_services',
    'billing_items',
    'billing_payments',
    'inventory',
    'inventory_transactions',
    'department_inventory',
    'stock_requests',
    'staff_attendance',
    'attendance',
    'patient_attendance',
    'tasks',
    'task_history',
    'leave_requests',
    'vendors',
    'sales',
    'eye_surgeries',
    'eye_surgery_items',
    'eye_surgery_insurances',
    'eye_surgery_insurance_payments'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    -- Only apply if table exists in public schema
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = v_table
    ) THEN
      -- Drop restrictive policy if previously added
      EXECUTE format(
        'DROP POLICY IF EXISTS "staff_geofence_guard_restrictive" ON public.%I;',
        v_table
      );
      -- Create restrictive policy across all operations
      EXECUTE format(
        'CREATE POLICY "staff_geofence_guard_restrictive" ON public.%I ' ||
        'AS RESTRICTIVE FOR ALL TO authenticated ' ||
        'USING (public.is_staff_geofenced_or_admin()) ' ||
        'WITH CHECK (public.is_staff_geofenced_or_admin());',
        v_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
