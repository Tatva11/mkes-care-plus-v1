-- ============================================================================
-- MKES CARE+ — Patient Numbering, Patient Deletion, and Staff Deletion Migration
-- File: supabase/migrations/20261114160000_fix_patient_numbering_deletion_and_admin_security.sql
--
-- Description:
--   1. Implements read-only get_next_patient_number(department) to preview the next
--      patient number without consuming or reserving it.
--   2. Updates create_patient(...) to atomically allocate sequential department numbers
--      continuing from highest existing imported Excel records (E-001 / D-001 format),
--      locking concurrently with pg_advisory_xact_lock to prevent duplicates.
--   3. Implements delete_patient(uuid) with geofencing validation, department isolation
--      for staff, admin full-access, and safe child record cascade/cleanup.
--   4. Adds RLS DELETE policy on public.patients for authorized staff and admins.
--   5. Enhances delete_user_by_admin(uuid) to safely nullify foreign key references,
--      prevent self-deletion, and prevent deletion of the last admin account.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Read-Only Preview Function: public.get_next_patient_number
--    Calculates the next available patient number from existing records
--    without holding locks or incrementing sequences.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_next_patient_number(p_department TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $func$
DECLARE
  normalized_department TEXT := lower(trim(COALESCE(p_department, '')));
  v_prefix TEXT;
  max_num BIGINT;
  next_num BIGINT;
BEGIN
  IF normalized_department NOT IN ('eye', 'dental') THEN
    RAISE EXCEPTION 'Invalid department: %. Must be eye or dental.', p_department;
  END IF;

  v_prefix := CASE normalized_department
    WHEN 'eye' THEN 'E'
    ELSE 'D'
  END;

  -- Extract the maximum numeric value among all patient numbers in this department
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN regexp_replace(patient_number, '[^0-9]', '', 'g') <> '' 
        THEN regexp_replace(patient_number, '[^0-9]', '', 'g')::BIGINT 
        ELSE 0 
      END
    ), 
    0
  )
  INTO max_num
  FROM public.patients
  WHERE lower(department) = normalized_department;

  next_num := max_num + 1;

  -- Consistent formatting: E-001 or D-001 for <1000, unpadded full digits for >=1000
  RETURN v_prefix || '-' || CASE
    WHEN next_num < 1000 THEN lpad(next_num::TEXT, 3, '0')
    ELSE next_num::TEXT
  END;
END;
$func$;

ALTER FUNCTION public.get_next_patient_number(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_next_patient_number(TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.get_next_patient_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_next_patient_number(TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_next_patient_number(TEXT) IS
  'Read-only calculation of the next sequential patient number for a department without reserving or incrementing sequences.';

-- ----------------------------------------------------------------------------
-- 2. Atomic Patient Registration: public.create_patient
--    Serializes registrations per department using pg_advisory_xact_lock to ensure
--    zero duplicate patient numbers, continuing from the highest existing Excel import.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_patient(
  p_name TEXT,
  p_department TEXT,
  p_dob DATE DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_mobile TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_visit_date DATE DEFAULT NULL
) RETURNS public.patients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $func$
DECLARE
  normalized_department TEXT := lower(trim(COALESCE(p_department, '')));
  v_prefix TEXT;
  max_num BIGINT;
  next_number BIGINT;
  assigned_patient_number TEXT;
  created_patient public.patients;
  v_user_dept TEXT;
BEGIN
  -- Security check: Require authenticated user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required to register a patient.';
  END IF;

  -- Security check: Geofence validation (staff must be within 200m or have admin bypass)
  IF NOT (public.is_admin() OR public.is_staff_geofenced_or_admin()) THEN
    RAISE EXCEPTION 'Access denied: Clinic presence or active GPS bypass required.';
  END IF;

  IF normalized_department NOT IN ('eye', 'dental') THEN
    RAISE EXCEPTION 'Invalid patient department: %. Must be eye or dental.', p_department;
  END IF;

  -- Staff department boundary: non-admins can only register patients for their own department
  IF NOT public.is_admin() THEN
    SELECT lower(trim(COALESCE(department, '')))
    INTO v_user_dept
    FROM public.profiles
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_dept IN ('eye', 'dental') AND v_user_dept <> normalized_department THEN
      RAISE EXCEPTION 'Access denied: Staff can only register patients in their assigned department.';
    END IF;
  END IF;

  v_prefix := CASE normalized_department
    WHEN 'eye' THEN 'E'
    ELSE 'D'
  END;

  -- Atomically serialize generation per department for the duration of this transaction
  PERFORM pg_advisory_xact_lock(hashtextextended('patients:' || normalized_department, 0));

  -- Query highest existing numeric value in this department across all formats
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN regexp_replace(patient_number, '[^0-9]', '', 'g') <> '' 
        THEN regexp_replace(patient_number, '[^0-9]', '', 'g')::BIGINT 
        ELSE 0 
      END
    ), 
    0
  )
  INTO max_num
  FROM public.patients
  WHERE lower(department) = normalized_department;

  next_number := max_num + 1;

  assigned_patient_number := v_prefix || '-' || CASE
    WHEN next_number < 1000 THEN lpad(next_number::TEXT, 3, '0')
    ELSE next_number::TEXT
  END;

  INSERT INTO public.patients (
    patient_number,
    name,
    dob,
    address,
    mobile,
    department,
    reference,
    visit_date,
    created_at,
    updated_at
  )
  VALUES (
    assigned_patient_number,
    trim(p_name),
    p_dob,
    nullif(trim(p_address), ''),
    nullif(trim(p_mobile), ''),
    normalized_department,
    nullif(trim(p_reference), ''),
    COALESCE(p_visit_date, current_date),
    now(),
    now()
  )
  RETURNING * INTO created_patient;

  RETURN created_patient;
END;
$func$;

ALTER FUNCTION public.create_patient(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, DATE) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_patient(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, DATE) FROM anon;
REVOKE ALL ON FUNCTION public.create_patient(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_patient(TEXT, TEXT, DATE, TEXT, TEXT, TEXT, DATE) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Patient Deletion Function: public.delete_patient
--    Validates geofencing, enforces department boundary for staff, and safely
--    removes dependent records before deleting the patient.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_patient(p_patient_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $func$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_user_dept TEXT;
  v_is_adm BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required to delete a patient record.';
  END IF;

  v_is_adm := public.is_admin();

  -- Security check: Geofence or admin validation
  IF NOT (v_is_adm OR public.is_staff_geofenced_or_admin()) THEN
    RAISE EXCEPTION 'Access denied: Clinic presence or active GPS bypass required.';
  END IF;

  SELECT * INTO v_patient
  FROM public.patients
  WHERE id = p_patient_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient record not found (ID: %).', p_patient_id;
  END IF;

  -- Staff department boundary: non-admins can only delete patients in their own department
  IF NOT v_is_adm THEN
    SELECT lower(trim(COALESCE(department, '')))
    INTO v_user_dept
    FROM public.profiles
    WHERE id = auth.uid() AND is_active = true;

    IF v_user_dept IS NULL OR v_user_dept NOT IN ('eye', 'dental') OR v_user_dept <> lower(trim(v_patient.department)) THEN
      RAISE EXCEPTION 'Access denied: Staff can only delete patients belonging to their assigned department.';
    END IF;
  END IF;

  -- Safely remove child records that may have foreign key RESTRICT constraints
  -- 1. Billing items & payments
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing_items') THEN
    DELETE FROM public.billing_items WHERE billing_id IN (SELECT id FROM public.billing WHERE patient_id = p_patient_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing_payments') THEN
    DELETE FROM public.billing_payments WHERE billing_id IN (SELECT id FROM public.billing WHERE patient_id = p_patient_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing') THEN
    DELETE FROM public.billing WHERE patient_id = p_patient_id;
  END IF;

  -- 2. Optical orders, dental lab cases, and sales
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'optical_orders') THEN
    DELETE FROM public.optical_orders WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_lab') THEN
    DELETE FROM public.dental_lab WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    DELETE FROM public.sales WHERE patient_id = p_patient_id;
  END IF;

  -- 3. Appointments & Attendance
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
    DELETE FROM public.appointments WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'patient_attendance') THEN
    DELETE FROM public.patient_attendance WHERE patient_id = p_patient_id;
  END IF;

  -- 4. Clinical records (eye examinations, dental treatments, surgery inventory, surgeries)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_inventory_usage') THEN
    DELETE FROM public.clinical_inventory_usage WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eye_examinations') THEN
    DELETE FROM public.eye_examinations WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_treatments') THEN
    DELETE FROM public.dental_treatments WHERE patient_id = p_patient_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eye_surgeries') THEN
    DELETE FROM public.eye_surgeries WHERE patient_id = p_patient_id;
  END IF;

  -- 5. Delete patient record
  DELETE FROM public.patients WHERE id = p_patient_id;

  RETURN TRUE;
END;
$func$;

ALTER FUNCTION public.delete_patient(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_patient(UUID) FROM anon;
REVOKE ALL ON FUNCTION public.delete_patient(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_patient(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION public.delete_patient(UUID) IS
  'Deletes a patient record with geofence validation, staff department boundary isolation, and child record cascade.';

-- ----------------------------------------------------------------------------
-- 4. RLS Policy for Patient Deletion
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Authorized staff and admins can delete patients" ON public.patients;

CREATE POLICY "Authorized staff and admins can delete patients"
  ON public.patients FOR DELETE TO authenticated
  USING (
    public.is_admin()
    OR (
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'staff', 'doctor', 'receptionist')
          AND profiles.is_active = true
          AND lower(trim(COALESCE(profiles.department, ''))) = lower(trim(COALESCE(patients.department, '')))
      )
    )
  );

-- ----------------------------------------------------------------------------
-- 5. Safe Admin Staff Deletion Helper: public.delete_user_by_admin
--    Pre-cleans foreign keys, prevents self-deletion, and prevents deleting last admin.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_user_by_admin(UUID);

CREATE OR REPLACE FUNCTION public.delete_user_by_admin(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $func$
DECLARE
  v_admin_count INT;
  v_target_role TEXT;
BEGIN
  -- 1. Enforce active admin
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only active admins can delete user accounts'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Prevent self-deletion
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own admin account'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 3. Prevent deleting the last admin account
  SELECT role INTO v_target_role
  FROM public.profiles
  WHERE id = target_user_id;

  IF v_target_role = 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.profiles
    WHERE role = 'admin' AND is_active = true;

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot delete the last remaining admin account'
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  -- 4. Nullify foreign key references in clinical & audit tables
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
    EXECUTE 'UPDATE public.appointments SET doctor_id = NULL WHERE doctor_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
    EXECUTE 'UPDATE public.audit_logs SET user_id = NULL WHERE user_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'billing') THEN
    EXECUTE 'UPDATE public.billing SET billed_by = NULL WHERE billed_by = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_transactions') THEN
    EXECUTE 'UPDATE public.inventory_transactions SET created_by = NULL WHERE created_by = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    EXECUTE 'UPDATE public.sales SET sold_by = NULL WHERE sold_by = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eye_surgeries') THEN
    EXECUTE 'UPDATE public.eye_surgeries SET assigned_staff_id = NULL WHERE assigned_staff_id = $1' USING target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stock_requests') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'stock_requests' AND column_name = 'requested_by') THEN
      EXECUTE 'UPDATE public.stock_requests SET requested_by = NULL WHERE requested_by = $1' USING target_user_id;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'stock_requests' AND column_name = 'reviewed_by') THEN
      EXECUTE 'UPDATE public.stock_requests SET reviewed_by = NULL WHERE reviewed_by = $1' USING target_user_id;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'stock_requests' AND column_name = 'fulfilled_by') THEN
      EXECUTE 'UPDATE public.stock_requests SET fulfilled_by = NULL WHERE fulfilled_by = $1' USING target_user_id;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchase_orders') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'purchase_orders' AND column_name = 'ordered_by') THEN
      EXECUTE 'UPDATE public.purchase_orders SET ordered_by = NULL WHERE ordered_by = $1' USING target_user_id;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'purchase_orders' AND column_name = 'created_by') THEN
      EXECUTE 'UPDATE public.purchase_orders SET created_by = NULL WHERE created_by = $1' USING target_user_id;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'patient_attendance') THEN
    EXECUTE 'UPDATE public.patient_attendance SET staff_id = NULL WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clinical_records') THEN
    EXECUTE 'UPDATE public.clinical_records SET created_by = NULL WHERE created_by = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eye_examinations') THEN
    EXECUTE 'UPDATE public.eye_examinations SET created_by = NULL WHERE created_by = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_treatments') THEN
    EXECUTE 'UPDATE public.dental_treatments SET created_by = NULL WHERE created_by = $1' USING target_user_id;
  END IF;

  -- 5. Delete user-specific records
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'leave_requests') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'leave_requests' AND column_name = 'approved_by') THEN
      EXECUTE 'UPDATE public.leave_requests SET approved_by = NULL WHERE approved_by = $1' USING target_user_id;
    END IF;
    EXECUTE 'DELETE FROM public.leave_requests WHERE staff_id = $1' USING target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tasks') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'assigned_by') THEN
      EXECUTE 'UPDATE public.tasks SET assigned_by = NULL WHERE assigned_by = $1' USING target_user_id;
    END IF;
    EXECUTE 'DELETE FROM public.tasks WHERE assigned_to = $1' USING target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'task_history') THEN
    EXECUTE 'DELETE FROM public.task_history WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_attendance') THEN
    EXECUTE 'DELETE FROM public.staff_attendance WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'notifications') THEN
    EXECUTE 'DELETE FROM public.notifications WHERE user_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_geofence_sessions') THEN
    EXECUTE 'DELETE FROM public.staff_geofence_sessions WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_device_tokens') THEN
    EXECUTE 'DELETE FROM public.staff_device_tokens WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_shift_assignments') THEN
    EXECUTE 'DELETE FROM public.staff_shift_assignments WHERE staff_id = $1' USING target_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_gps_bypass_audit') THEN
    EXECUTE 'UPDATE public.staff_gps_bypass_audit SET staff_id = NULL WHERE staff_id = $1' USING target_user_id;
  END IF;

  -- 6. Delete profile row
  DELETE FROM public.profiles WHERE id = target_user_id;
END;
$func$;

ALTER FUNCTION public.delete_user_by_admin(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.delete_user_by_admin(UUID) FROM anon;
REVOKE ALL ON FUNCTION public.delete_user_by_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user_by_admin(UUID) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6. Schema Reload Notification & Transaction Closure
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;
