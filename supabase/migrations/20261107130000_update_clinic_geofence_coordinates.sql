-- ============================================================================
-- MKES CARE+ — Update Clinic Geofencing Location Coordinates
-- File: supabase/migrations/20261107130000_update_clinic_geofence_coordinates.sql
--
-- Description:
--   Updates the MKES CARE+ physical clinic geofence location to new coordinates:
--     - New Latitude:  18.990374
--     - New Longitude: 72.835143
--     - Preserves 200.0 metres allowed radius
--     - Preserves 150.0 metres GPS accuracy threshold
--     - Preserves 15 minutes verification freshness window
--     - Preserves unconditional Admin login from anywhere
--     - Preserves individual Staff GPS bypass functionality
--     - Invalidates active staff geofence leases so staff re-verify at new site
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Update Geodesic Distance Calculation Function (WGS-84 Haversine)
--    Replaces old coordinates (18.99110, 72.838885) with new coordinates
--    Latitude: 18.990374, Longitude: 72.835143
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
        power(sin(radians((p_lat - 18.990374) / 2.0)), 2) +
        cos(radians(18.990374)) * cos(radians(p_lat)) *
        power(sin(radians((p_lng - 72.835143) / 2.0)), 2)
      )
    )
  );
$$;

ALTER FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) FROM anon;
REVOKE ALL ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, service_role;

COMMENT ON FUNCTION public.calculate_clinic_distance(DOUBLE PRECISION, DOUBLE PRECISION) IS
  'Computes geodesic distance in metres from the MKES CARE+ clinic coordinates (18.990374, 72.835143) using WGS-84 Haversine formula';

-- ----------------------------------------------------------------------------
-- 2. Invalidate Active Staff Geofence Sessions
--    Any active lease granted at the previous coordinates is purged so staff
--    are immediately required to verify at the new clinic location.
-- ----------------------------------------------------------------------------
DELETE FROM public.staff_geofence_sessions;

COMMIT;

NOTIFY pgrst, 'reload schema';

