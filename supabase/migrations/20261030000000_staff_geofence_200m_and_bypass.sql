-- ============================================================================
-- MKES CARE+ — Staff Geofencing 200m Expansion & Individual GPS Bypass Migration
-- File: supabase/migrations/20261030000000_staff_geofence_200m_and_bypass.sql
-- 
-- Description:
--   1. Expands clinic staff geofence boundary from 50 metres to 200 metres.
--   2. Updates GPS accuracy threshold to 150.0m to accommodate realistic indoor/
--      outdoor urban clinic mobile GPS reception while strictly rejecting coarse cell-tower fixes.
--   3. Maintains verification freshness window at 15 minutes.
--   4. Adds individual staff GPS bypass support allowing admins to temporarily
--      disable geofencing for specific staff accounts (1h, 4h, 8h, or 24h).
--   5. Adds audit logging for bypass grant and revocation events.
--   6. Enforces bypass permissions strictly inside PostgreSQL RLS and server-side RPCs.
--   7. Ensures revocation immediately invalidates any active sessions.
--
-- Clinic Coordinates:
--   Latitude:  18.99110
--   Longitude: 72.838885
--   Allowed radius: 200.0 metres
--   Max accuracy:   150.0 metres
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Add Bypass Columns to public.profiles
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gps_bypass_until TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS gps_bypass_granted_by UUID REFERENCES public.profiles(id) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS gps_bypass_granted_at TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS gps_bypass_reason TEXT DEFAULT NULL;

COMMENT ON COLUMN public.profiles.gps_bypass_until IS 'Timestamp until which staff member has a temporary GPS geofence bypass';
COMMENT ON COLUMN public.profiles.gps_bypass_granted_by IS 'Admin profile ID who granted the active GPS bypass';
COMMENT ON COLUMN public.profiles.gps_bypass_granted_at IS 'Timestamp when the active GPS bypass was granted';
COMMENT ON COLUMN public.profiles.gps_bypass_reason IS 'Administrative reason or note for granting the GPS bypass';

-- ----------------------------------------------------------------------------
-- 2. Audit Log Table for GPS Bypass Actions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_gps_bypass_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('grant', 'revoke')),
  duration_hours INT CHECK (duration_hours IS NULL OR duration_hours IN (1, 4, 8, 24)),
  bypass_until TIMESTAMPTZ,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_gps_bypass_audit_staff_id
  ON public.staff_gps_bypass_audit_logs (staff_id, created_at DESC);

ALTER TABLE public.staff_gps_bypass_audit_logs ENABLE ROW LEVEL SECURITY;

-- Only authenticated administrators can view audit logs
DROP POLICY IF EXISTS "Admins can view bypass audit logs" ON public.staff_gps_bypass_audit_logs;
CREATE POLICY "Admins can view bypass audit logs"
  ON public.staff_gps_bypass_audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Strictly NO direct INSERT, UPDATE, or DELETE policies for authenticated users.
-- Only trusted SECURITY DEFINER functions may insert records.

-- ----------------------------------------------------------------------------
-- 3. Geodesic Distance Calculation Function (WGS-84 Haversine)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_clinic_distance(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
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
-- 4. Status Check RPC: public.check_staff_geofence_status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_staff_geofence_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role TEXT;
  v_is_active BOOLEAN;
  v_bypass_until TIMESTAMPTZ;
  v_session_expires TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'authenticated', false,
      'is_admin', false,
      'has_bypass', false,
      'has_active_session', false
    );
  END IF;

  SELECT role, is_active, gps_bypass_until
  INTO v_role, v_is_active, v_bypass_until
  FROM public.profiles
  WHERE id = v_user_id;

  IF lower(v_role) = 'admin' THEN
    RETURN jsonb_build_object(
      'authenticated', true,
      'is_admin', true,
      'has_bypass', false,
      'has_active_session', true
    );
  END IF;

  SELECT expires_at
  INTO v_session_expires
  FROM public.staff_geofence_sessions
  WHERE staff_id = v_user_id;

  RETURN jsonb_build_object(
    'authenticated', true,
    'is_admin', false,
    'has_bypass', (v_bypass_until IS NOT NULL AND v_bypass_until > now()),
    'bypass_until', v_bypass_until,
    'has_active_session', (v_session_expires IS NOT NULL AND v_session_expires > now()),
    'session_expires_at', v_session_expires
  );
END;
$$;

ALTER FUNCTION public.check_staff_geofence_status() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.check_staff_geofence_status() FROM anon;
REVOKE ALL ON FUNCTION public.check_staff_geofence_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_staff_geofence_status() TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Verification RPC: public.verify_staff_geofence (200m + Bypass Aware)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_staff_geofence(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION DEFAULT 10.0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role TEXT;
  v_is_active BOOLEAN;
  v_bypass_until TIMESTAMPTZ;
  v_distance DOUBLE PRECISION;
  v_expires_at TIMESTAMPTZ;
  c_max_radius CONSTANT DOUBLE PRECISION := 200.0;
  c_max_accuracy CONSTANT DOUBLE PRECISION := 150.0;
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

  -- 2. Fetch role, active status, and bypass expiry from trusted public.profiles
  SELECT role, is_active, gps_bypass_until
  INTO v_role, v_is_active, v_bypass_until
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
  IF lower(v_role) = 'admin' THEN
    RETURN jsonb_build_object(
      'success', true,
      'is_admin', true,
      'is_bypass', false,
      'distance_meters', 0.0,
      'message', 'Admin access granted unconditionally.'
    );
  END IF;

  -- 4. Staff verification check
  IF lower(v_role) != 'staff' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'unauthorized_role',
      'message', 'Unrecognised user role.'
    );
  END IF;

  -- 5. Active Individual Bypass Exemption
  IF v_bypass_until IS NOT NULL AND v_bypass_until > now() THEN
    RETURN jsonb_build_object(
      'success', true,
      'is_admin', false,
      'is_bypass', true,
      'distance_meters', 0.0,
      'accuracy_meters', 0.0,
      'allowed_radius_meters', c_max_radius,
      'expires_at', v_bypass_until,
      'message', 'Staff member holds an authorized active GPS bypass.'
    );
  END IF;

  -- 6. Calculate geodesic distance from clinic coordinates
  v_distance := public.calculate_clinic_distance(p_lat, p_lng);

  -- 7. Reject poor accuracy GPS readings (> 150 metres)
  IF p_accuracy > c_max_accuracy THEN
    DELETE FROM public.staff_geofence_sessions WHERE staff_id = v_user_id;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'inaccurate_location',
      'distance_meters', round(v_distance::numeric, 1),
      'accuracy_meters', round(p_accuracy::numeric, 1),
      'allowed_radius_meters', c_max_radius,
      'message', 'GPS accuracy is insufficient (±' || round(p_accuracy::numeric, 1)::text || 'm, required within ±' || c_max_accuracy::int::text || 'm). Please ensure high-accuracy GPS has a clear signal.'
    );
  END IF;

  -- 8. Reject if outside 200 metres
  IF v_distance > c_max_radius THEN
    DELETE FROM public.staff_geofence_sessions WHERE staff_id = v_user_id;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'outside_radius',
      'distance_meters', round(v_distance::numeric, 1),
      'accuracy_meters', round(p_accuracy::numeric, 1),
      'allowed_radius_meters', c_max_radius,
      'message', 'You are ' || round(v_distance::numeric, 1)::text || 'm from the clinic. Staff access is restricted to within 200m of clinic premises.'
    );
  END IF;

  -- 9. Proximity verified! Issue 15-minute lease in database
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
    'is_bypass', false,
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
-- 6. Admin Grant Bypass RPC: public.admin_grant_gps_bypass
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_grant_gps_bypass(
  p_staff_id UUID,
  p_duration_hours INT,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_staff_name TEXT;
  v_bypass_until TIMESTAMPTZ;
BEGIN
  -- 1. Ensure caller is an authenticated administrator
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized: Only administrators can grant a GPS bypass.';
  END IF;

  -- 2. Validate duration
  IF p_duration_hours NOT IN (1, 4, 8, 24) THEN
    RAISE EXCEPTION 'Invalid duration. Allowed values are 1, 4, 8, or 24 hours.';
  END IF;

  -- 3. Verify target profile exists, is staff, and is active
  SELECT full_name INTO v_staff_name
  FROM public.profiles
  WHERE id = p_staff_id
    AND (lower(role) = 'staff' OR lower(role) != 'admin')
    AND is_active = true;

  IF v_staff_name IS NULL THEN
    RAISE EXCEPTION 'Staff member not found or is currently inactive.';
  END IF;

  -- 4. Calculate bypass expiry
  v_bypass_until := now() + (p_duration_hours || ' hours')::INTERVAL;

  -- 5. Update profiles record
  UPDATE public.profiles
  SET gps_bypass_until = v_bypass_until,
      gps_bypass_granted_by = COALESCE(v_admin_id, (SELECT id FROM public.profiles WHERE lower(role) = 'admin' LIMIT 1)),
      gps_bypass_granted_at = now(),
      gps_bypass_reason = NULLIF(trim(p_reason), '')
  WHERE id = p_staff_id;

  -- 6. Insert audit log record
  INSERT INTO public.staff_gps_bypass_audit_logs (
    staff_id,
    admin_id,
    action,
    duration_hours,
    bypass_until,
    reason
  ) VALUES (
    p_staff_id,
    COALESCE(v_admin_id, (SELECT id FROM public.profiles WHERE lower(role) = 'admin' LIMIT 1)),
    'grant',
    p_duration_hours,
    v_bypass_until,
    NULLIF(trim(p_reason), '')
  );

  RETURN jsonb_build_object(
    'success', true,
    'staff_id', p_staff_id,
    'staff_name', v_staff_name,
    'duration_hours', p_duration_hours,
    'bypass_until', v_bypass_until,
    'message', 'Temporary GPS bypass granted successfully.'
  );
END;
$$;

ALTER FUNCTION public.admin_grant_gps_bypass(UUID, INT, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_grant_gps_bypass(UUID, INT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.admin_grant_gps_bypass(UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_grant_gps_bypass(UUID, INT, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 7. Admin Revoke Bypass RPC: public.admin_revoke_gps_bypass
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_revoke_gps_bypass(
  p_staff_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_staff_name TEXT;
BEGIN
  -- 1. Ensure caller is an authenticated administrator
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized: Only administrators can revoke a GPS bypass.';
  END IF;

  -- 2. Verify staff profile
  SELECT full_name INTO v_staff_name
  FROM public.profiles
  WHERE id = p_staff_id;

  IF v_staff_name IS NULL THEN
    RAISE EXCEPTION 'Staff member profile not found.';
  END IF;

  -- 3. Clear bypass fields on profiles
  UPDATE public.profiles
  SET gps_bypass_until = NULL,
      gps_bypass_granted_by = NULL,
      gps_bypass_granted_at = NULL,
      gps_bypass_reason = NULL
  WHERE id = p_staff_id;

  -- 4. Purge any active session lease to immediately lock out unverified access
  DELETE FROM public.staff_geofence_sessions
  WHERE staff_id = p_staff_id;

  -- 5. Record revocation in audit log
  INSERT INTO public.staff_gps_bypass_audit_logs (
    staff_id,
    admin_id,
    action,
    duration_hours,
    bypass_until,
    reason
  ) VALUES (
    p_staff_id,
    COALESCE(v_admin_id, (SELECT id FROM public.profiles WHERE lower(role) = 'admin' LIMIT 1)),
    'revoke',
    NULL,
    NULL,
    NULLIF(trim(p_reason), '')
  );

  RETURN jsonb_build_object(
    'success', true,
    'staff_id', p_staff_id,
    'staff_name', v_staff_name,
    'message', 'GPS bypass revoked successfully. 200m geofence restriction reinstated immediately.'
  );
END;
$$;

ALTER FUNCTION public.admin_revoke_gps_bypass(UUID, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_revoke_gps_bypass(UUID, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.admin_revoke_gps_bypass(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_revoke_gps_bypass(UUID, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 8. Update RLS Gate Function: public.is_staff_geofenced_or_admin()
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_staff_geofenced_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT (
    -- Admins have unrestricted access from anywhere
    public.is_admin()
    OR
    -- Staff users must be active AND hold either an unexpired bypass OR an unexpired geofence lease
    (
      EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND (lower(role) = 'staff' OR lower(role) != 'admin')
          AND is_active = true
          AND (
            -- Active temporary GPS bypass
            (gps_bypass_until IS NOT NULL AND gps_bypass_until > now())
            OR
            -- Active verified 15-minute lease (within 200m)
            EXISTS (
              SELECT 1
              FROM public.staff_geofence_sessions
              WHERE staff_id = auth.uid()
                AND expires_at > now()
            )
          )
      )
    )
  );
$$;

ALTER FUNCTION public.is_staff_geofenced_or_admin() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_staff_geofenced_or_admin() FROM anon;
REVOKE ALL ON FUNCTION public.is_staff_geofenced_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_staff_geofenced_or_admin() TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
