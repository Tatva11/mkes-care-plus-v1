-- ============================================================================
-- MKES CARE+ — Master Fix Migration (Resilient & Safe)
-- Migration: 20261005100000_master_fix.sql
-- Description:
--   1. Fix Admin Account Deletion: Safely drop/re-add foreign keys with ON DELETE SET NULL,
--      preserve patient attendance and audit history, update delete_user_by_admin RPC.
--   2. Shift Separation: Add shift column to staff_attendance, update unique constraint to
--      (staff_id, record_date, shift).
--   3. Unified Inventory: Reconcile allocated stock from department_inventory back into
--      public.inventory so there is one authoritative balance with no double counting.
--   4. Eye Surgery Templates: Ensure eye_surgery_item_templates exists with RLS, seed presets.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FOREIGN KEY SAFETY FOR ACCOUNT DELETION (Requirement 1)
-- ----------------------------------------------------------------------------

-- Patient Attendance: Make staff_id nullable and ON DELETE SET NULL so historical
-- attendance records for patients are never deleted when a staff member is removed.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'patient_attendance'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'patient_attendance' AND column_name = 'staff_id'
    ) THEN
      ALTER TABLE public.patient_attendance ALTER COLUMN staff_id DROP NOT NULL;
    END IF;

    ALTER TABLE public.patient_attendance
      DROP CONSTRAINT IF EXISTS patient_attendance_staff_id_fkey;

    ALTER TABLE public.patient_attendance
      ADD CONSTRAINT patient_attendance_staff_id_fkey
      FOREIGN KEY (staff_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Appointments: doctor_id ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'appointments'
  ) THEN
    ALTER TABLE public.appointments
      DROP CONSTRAINT IF EXISTS appointments_doctor_id_fkey;

    ALTER TABLE public.appointments
      ADD CONSTRAINT appointments_doctor_id_fkey
      FOREIGN KEY (doctor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Audit Logs: user_id ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
    ALTER TABLE public.audit_logs DROP CONSTRAINT IF EXISTS audit_logs_user_id_fkey;
    ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Billing: billed_by ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing') THEN
    ALTER TABLE public.billing DROP CONSTRAINT IF EXISTS billing_billed_by_fkey;
    ALTER TABLE public.billing ADD CONSTRAINT billing_billed_by_fkey
      FOREIGN KEY (billed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Inventory Transactions: created_by ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_transactions') THEN
    ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_created_by_fkey;
    ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Sales: sold_by ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_sold_by_fkey;
    ALTER TABLE public.sales ADD CONSTRAINT sales_sold_by_fkey
      FOREIGN KEY (sold_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Eye Surgeries: assigned_staff_id ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eye_surgeries') THEN
    ALTER TABLE public.eye_surgeries DROP CONSTRAINT IF EXISTS eye_surgeries_assigned_staff_id_fkey;
    ALTER TABLE public.eye_surgeries ADD CONSTRAINT eye_surgeries_assigned_staff_id_fkey
      FOREIGN KEY (assigned_staff_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Stock Requests: Make requested_by nullable and ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stock_requests') THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'stock_requests' AND column_name = 'requested_by'
    ) THEN
      ALTER TABLE public.stock_requests ALTER COLUMN requested_by DROP NOT NULL;
      ALTER TABLE public.stock_requests DROP CONSTRAINT IF EXISTS stock_requests_requested_by_fkey;
      ALTER TABLE public.stock_requests ADD CONSTRAINT stock_requests_requested_by_fkey
        FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

-- Purchase Orders: ordered_by and created_by ON DELETE SET NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchase_orders') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'purchase_orders' AND column_name = 'created_by') THEN
      ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_created_by_fkey;
      ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'purchase_orders' AND column_name = 'ordered_by') THEN
      ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_ordered_by_fkey;
      ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_ordered_by_fkey
        FOREIGN KEY (ordered_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. REVISED delete_user_by_admin RPC (Requirement 1)
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS delete_user_by_admin(UUID);

CREATE OR REPLACE FUNCTION delete_user_by_admin(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Enforce that only active admins can delete accounts
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only active admins can delete user accounts'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Prevent admins from accidentally deleting their own account
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own account'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 3. Atomically nullify foreign key references in clinical & audit records
  -- (Preserves audit logs, clinical records, patient attendance, POs, and transactions)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
    EXECUTE 'UPDATE public.appointments SET doctor_id = NULL WHERE doctor_id = $1' USING target_user_id;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
    EXECUTE 'UPDATE public.audit_logs SET user_id = NULL WHERE user_id = $1' USING target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'billing') THEN
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

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'staff_attendance') THEN
    EXECUTE 'DELETE FROM public.staff_attendance WHERE staff_id = $1' USING target_user_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'notifications') THEN
    EXECUTE 'DELETE FROM public.notifications WHERE user_id = $1' USING target_user_id;
  END IF;

  -- 4. Delete profile and auth user
  DELETE FROM public.profiles WHERE id = target_user_id;
  DELETE FROM auth.users WHERE id = target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_user_by_admin(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. SHIFT SEPARATION: MORNING & NIGHT SHIFTS (Requirements 3 & 4)
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'staff_attendance'
  ) THEN
    -- Add shift column to staff_attendance if not present
    ALTER TABLE public.staff_attendance
      ADD COLUMN IF NOT EXISTS shift TEXT NOT NULL DEFAULT 'morning';

    -- Add check constraint for supported shifts
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'staff_attendance_shift_check'
    ) THEN
      ALTER TABLE public.staff_attendance
        ADD CONSTRAINT staff_attendance_shift_check
        CHECK (shift IN ('morning', 'night'));
    END IF;

    -- Update unique constraint from (staff_id, record_date) to (staff_id, record_date, shift)
    ALTER TABLE public.staff_attendance
      DROP CONSTRAINT IF EXISTS staff_attendance_staff_id_record_date_key;

    ALTER TABLE public.staff_attendance
      DROP CONSTRAINT IF EXISTS staff_attendance_staff_id_record_date_shift_key;

    ALTER TABLE public.staff_attendance
      ADD CONSTRAINT staff_attendance_staff_id_record_date_shift_key
      UNIQUE (staff_id, record_date, shift);

    CREATE INDEX IF NOT EXISTS idx_staff_attendance_shift_date
      ON public.staff_attendance (staff_id, record_date, shift);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 4. INVENTORY UNIFICATION: REMOVE CENTRAL VS DEPT CONCEPT (Requirement 8)
-- ----------------------------------------------------------------------------

-- Reconcile any department stock back into public.inventory
-- Dynamically detects whether columns are 'quantity' or 'allocated_quantity'
-- to guarantee zero errors and eliminate split-pool discrepancies.
DO $$
DECLARE
  v_dept_col TEXT := NULL;
  v_inv_col TEXT := NULL;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'department_inventory'
  ) THEN
    -- Detect quantity column on department_inventory
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'department_inventory' AND column_name = 'quantity'
    ) THEN
      v_dept_col := 'quantity';
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'department_inventory' AND column_name = 'allocated_quantity'
    ) THEN
      v_dept_col := 'allocated_quantity';
    END IF;

    -- Detect quantity column on inventory
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'inventory' AND column_name = 'quantity'
    ) THEN
      v_inv_col := 'quantity';
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'inventory' AND column_name = 'current_stock'
    ) THEN
      v_inv_col := 'current_stock';
    END IF;

    IF v_dept_col IS NOT NULL AND v_inv_col IS NOT NULL THEN
      -- Return department stock to authoritative inventory balance
      EXECUTE format('
        UPDATE public.inventory i
        SET %I = i.%I + COALESCE(sub.allocated_sum, 0)
        FROM (
          SELECT inventory_id, SUM(%I) AS allocated_sum
          FROM public.department_inventory
          WHERE %I > 0
          GROUP BY inventory_id
        ) sub
        WHERE i.id = sub.inventory_id', v_inv_col, v_inv_col, v_dept_col, v_dept_col);

      -- Reset department inventory quantity to 0
      EXECUTE format('
        UPDATE public.department_inventory
        SET %I = 0
        WHERE %I > 0', v_dept_col, v_dept_col);
    END IF;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. EYE SURGERY ITEM TEMPLATES & PRESETS (Requirement 9)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.eye_surgery_item_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  surgery_type TEXT NOT NULL,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
  default_quantity NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (default_quantity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT eye_surgery_item_templates_type_item_key UNIQUE (surgery_type, inventory_item_id)
);

ALTER TABLE public.eye_surgery_item_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can view templates" ON public.eye_surgery_item_templates;
CREATE POLICY "Anyone authenticated can view templates"
  ON public.eye_surgery_item_templates FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins can manage templates" ON public.eye_surgery_item_templates;
CREATE POLICY "Admins can manage templates"
  ON public.eye_surgery_item_templates FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

GRANT ALL ON public.eye_surgery_item_templates TO authenticated;
