-- ============================================================================
-- MKES CARE+ — Shift/Attendance/Leave/Surgery Comprehensive Fix
-- Migration: 20261010140000_shift_attendance_leave_surgery_fix.sql
-- 
-- This migration fixes:
--   1. shift_configurations: Dart code references 'shift' column but DB has 'name'.
--      Solution: Rename 'night' → 'afternoon', update constraints, ensure Dart reads 'name'.
--   2. profiles.assigned_shift: Update from morning/night to morning/afternoon/both.
--   3. staff_attendance: Add 'shift' column for separate Morning/Afternoon sessions.
--   4. leave_requests: Add 'duty_period' column for partial-day leave.
--   5. Eye Surgery: Add allocation tracking and atomic scheduling RPC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FIX shift_configurations: rename 'night' to 'afternoon', update CHECK
-- ----------------------------------------------------------------------------

-- A. Drop ALL existing CHECK constraints on shift_configurations.name FIRST
ALTER TABLE public.shift_configurations
  DROP CONSTRAINT IF EXISTS shift_configurations_name_check;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.shift_configurations'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%name%'
  ) LOOP
    EXECUTE 'ALTER TABLE public.shift_configurations DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

-- B. Now update existing 'night' row to 'afternoon' with appropriate times
UPDATE public.shift_configurations
SET name = 'afternoon',
    start_time = '13:00:00',
    end_time = '21:00:00',
    updated_at = now()
WHERE name = 'night';

-- Update the morning shift to have proper default times
UPDATE public.shift_configurations
SET start_time = '08:00:00',
    end_time = '13:00:00',
    updated_at = now()
WHERE name = 'morning';

-- C. Re-add the CHECK constraint on shift_configurations.name
ALTER TABLE public.shift_configurations
  ADD CONSTRAINT shift_configurations_name_check
  CHECK (name IN ('morning', 'afternoon'));

-- Ensure seed data exists for both shifts
INSERT INTO public.shift_configurations (name, start_time, end_time, grace_period_minutes)
VALUES
  ('morning', '08:00:00', '13:00:00', 15),
  ('afternoon', '13:00:00', '21:00:00', 15)
ON CONFLICT (name) DO UPDATE SET
  start_time = EXCLUDED.start_time,
  end_time = EXCLUDED.end_time,
  grace_period_minutes = EXCLUDED.grace_period_minutes,
  updated_at = now();

-- ----------------------------------------------------------------------------
-- 2. FIX profiles.assigned_shift: support morning/afternoon/both
-- ----------------------------------------------------------------------------

-- A. Drop old constraint on profiles.assigned_shift FIRST
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_assigned_shift_check;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%assigned_shift%'
  ) LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

-- B. Update any 'night' assignments to 'afternoon'
UPDATE public.profiles
SET assigned_shift = 'afternoon'
WHERE assigned_shift = 'night';

-- Set default to 'morning' for any NULLs
UPDATE public.profiles
SET assigned_shift = 'morning'
WHERE assigned_shift IS NULL;

-- C. Re-add constraint with 'morning', 'afternoon', 'both'
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_assigned_shift_check
  CHECK (assigned_shift IN ('morning', 'afternoon', 'both'));

-- ----------------------------------------------------------------------------
-- 3. ADD shift column to staff_attendance (for separate morning/afternoon records)
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'staff_attendance' AND column_name = 'shift'
  ) THEN
    ALTER TABLE public.staff_attendance
      ADD COLUMN shift TEXT NOT NULL DEFAULT 'morning';
  END IF;
END $$;

-- Drop old check constraint if exists
ALTER TABLE public.staff_attendance
  DROP CONSTRAINT IF EXISTS staff_attendance_shift_check;

-- Migrate any legacy 'night' attendance records to 'afternoon'
UPDATE public.staff_attendance
SET shift = 'afternoon'
WHERE shift = 'night';

-- Add CHECK constraint for shift values
ALTER TABLE public.staff_attendance
  ADD CONSTRAINT staff_attendance_shift_check
  CHECK (shift IN ('morning', 'afternoon'));

-- Drop the old unique constraint on (staff_id, record_date) since we now need
-- separate records per shift per day
ALTER TABLE public.staff_attendance
  DROP CONSTRAINT IF EXISTS staff_attendance_staff_id_record_date_key;

-- Add new unique constraint including shift
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'staff_attendance_staff_shift_date_key'
  ) THEN
    ALTER TABLE public.staff_attendance
      ADD CONSTRAINT staff_attendance_staff_shift_date_key
      UNIQUE (staff_id, record_date, shift);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 4. ADD duty_period column to leave_requests
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'leave_requests' AND column_name = 'duty_period'
  ) THEN
    ALTER TABLE public.leave_requests
      ADD COLUMN duty_period TEXT NOT NULL DEFAULT 'full_day';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'leave_requests_duty_period_check'
  ) THEN
    ALTER TABLE public.leave_requests
      ADD CONSTRAINT leave_requests_duty_period_check
      CHECK (duty_period IN ('morning', 'afternoon', 'full_day'));
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. EYE SURGERY: allocation tracking columns
-- ----------------------------------------------------------------------------

-- Add allocation_status to eye_surgery_items to track inventory deduction state
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eye_surgery_items' AND column_name = 'allocation_status'
  ) THEN
    ALTER TABLE public.eye_surgery_items
      ADD COLUMN allocation_status TEXT NOT NULL DEFAULT 'pending';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'eye_surgery_items_allocation_status_check'
  ) THEN
    ALTER TABLE public.eye_surgery_items
      ADD CONSTRAINT eye_surgery_items_allocation_status_check
      CHECK (allocation_status IN ('pending', 'allocated', 'consumed', 'returned'));
  END IF;
END $$;

-- Add idempotency_key to eye_surgery_items to prevent duplicate allocations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eye_surgery_items' AND column_name = 'idempotency_key'
  ) THEN
    ALTER TABLE public.eye_surgery_items
      ADD COLUMN idempotency_key TEXT;
  END IF;
END $$;

-- Add surgery_allocation and surgery_return transaction types to inventory_transactions
ALTER TABLE public.inventory_transactions
  DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;

DO $$
BEGIN
  ALTER TABLE public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_transaction_type_check
    CHECK (transaction_type IN (
      'stock_in', 'stock_out', 'purchase', 'sale', 'usage', 'adjustment', 'return',
      'transfer', 'dispense', 'waste',
      'surgery_allocation', 'surgery_return', 'surgery_consumption'
    ));
EXCEPTION WHEN check_violation THEN
  -- If table has existing unlisted legacy transaction_types, keep constraint relaxed
  NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 6. RPC: Atomic surgery scheduling with inventory deduction
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.schedule_surgery_with_inventory(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.schedule_surgery_with_inventory(
  p_surgery_id UUID,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item RECORD;
  v_current_stock NUMERIC;
  v_errors TEXT[] := '{}';
  v_surgery_status TEXT;
  v_result JSONB;
BEGIN
  -- Check surgery exists and is in valid state
  SELECT status INTO v_surgery_status
  FROM public.eye_surgeries
  WHERE id = p_surgery_id
  FOR UPDATE;

  IF v_surgery_status IS NULL THEN
    RAISE EXCEPTION 'Surgery not found: %', p_surgery_id;
  END IF;

  -- Check idempotency: if items are already allocated, skip
  IF EXISTS (
    SELECT 1 FROM public.eye_surgery_items
    WHERE eye_surgery_id = p_surgery_id
      AND allocation_status = 'allocated'
  ) THEN
    RETURN jsonb_build_object('status', 'already_allocated', 'surgery_id', p_surgery_id);
  END IF;

  -- Validate sufficient stock for ALL items first
  FOR v_item IN
    SELECT esi.id AS item_id, esi.inventory_item_id, esi.planned_quantity,
           i.quantity AS current_stock, i.name AS item_name
    FROM public.eye_surgery_items esi
    JOIN public.inventory i ON i.id = esi.inventory_item_id
    WHERE esi.eye_surgery_id = p_surgery_id
      AND esi.allocation_status = 'pending'
    FOR UPDATE OF i
  LOOP
    IF v_item.current_stock < v_item.planned_quantity THEN
      v_errors := array_append(v_errors,
        format('Insufficient stock for %s: need %s, have %s',
          v_item.item_name, v_item.planned_quantity, v_item.current_stock));
    END IF;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'Insufficient stock: %', array_to_string(v_errors, '; ');
  END IF;

  -- Deduct stock and record transactions atomically
  FOR v_item IN
    SELECT esi.id AS item_id, esi.inventory_item_id, esi.planned_quantity,
           i.quantity AS current_stock
    FROM public.eye_surgery_items esi
    JOIN public.inventory i ON i.id = esi.inventory_item_id
    WHERE esi.eye_surgery_id = p_surgery_id
      AND esi.allocation_status = 'pending'
    FOR UPDATE OF i
  LOOP
    -- Deduct from central inventory
    UPDATE public.inventory
    SET quantity = quantity - v_item.planned_quantity
    WHERE id = v_item.inventory_item_id;

    -- Record transaction
    INSERT INTO public.inventory_transactions (
      inventory_id, transaction_type, quantity, stock_before, stock_after, reference_id, remarks, created_by
    ) VALUES (
      v_item.inventory_item_id,
      'surgery_allocation',
      v_item.planned_quantity,
      v_item.current_stock,
      v_item.current_stock - v_item.planned_quantity,
      p_surgery_id,
      format('Surgery scheduling allocation for surgery %s', p_surgery_id),
      auth.uid()
    );

    -- Mark item as allocated
    UPDATE public.eye_surgery_items
    SET allocation_status = 'allocated',
        idempotency_key = COALESCE(p_idempotency_key, gen_random_uuid()::text)
    WHERE id = v_item.item_id;
  END LOOP;

  RETURN jsonb_build_object('status', 'allocated', 'surgery_id', p_surgery_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. RPC: Restore surgery inventory on cancellation/deletion
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.restore_surgery_inventory(UUID);

CREATE OR REPLACE FUNCTION public.restore_surgery_inventory(
  p_surgery_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item RECORD;
  v_restored_count INT := 0;
BEGIN
  FOR v_item IN
    SELECT esi.id AS item_id, esi.inventory_item_id, esi.planned_quantity,
           esi.allocation_status, i.quantity AS current_stock
    FROM public.eye_surgery_items esi
    JOIN public.inventory i ON i.id = esi.inventory_item_id
    WHERE esi.eye_surgery_id = p_surgery_id
      AND esi.allocation_status = 'allocated'
    FOR UPDATE OF esi, i
  LOOP
    -- Return stock to central inventory
    UPDATE public.inventory
    SET quantity = quantity + v_item.planned_quantity
    WHERE id = v_item.inventory_item_id;

    -- Record return transaction
    INSERT INTO public.inventory_transactions (
      inventory_id, transaction_type, quantity, stock_before, stock_after, reference_id, remarks, created_by
    ) VALUES (
      v_item.inventory_item_id,
      'surgery_return',
      v_item.planned_quantity,
      v_item.current_stock,
      v_item.current_stock + v_item.planned_quantity,
      p_surgery_id,
      format('Surgery cancellation return for surgery %s', p_surgery_id),
      auth.uid()
    );

    -- Mark as returned
    UPDATE public.eye_surgery_items
    SET allocation_status = 'returned'
    WHERE id = v_item.item_id;

    v_restored_count := v_restored_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'restored',
    'surgery_id', p_surgery_id,
    'items_restored', v_restored_count
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: Reconcile surgery inventory on item edit
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.reconcile_surgery_item_inventory(UUID, NUMERIC);

CREATE OR REPLACE FUNCTION public.reconcile_surgery_item_inventory(
  p_surgery_item_id UUID,
  p_new_quantity NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item RECORD;
  v_diff NUMERIC;
BEGIN
  SELECT esi.id, esi.inventory_item_id, esi.planned_quantity,
         esi.allocation_status, esi.eye_surgery_id,
         i.quantity AS current_stock, i.name AS item_name
  INTO v_item
  FROM public.eye_surgery_items esi
  JOIN public.inventory i ON i.id = esi.inventory_item_id
  WHERE esi.id = p_surgery_item_id
  FOR UPDATE OF esi, i;

  IF v_item IS NULL THEN
    RAISE EXCEPTION 'Surgery item not found: %', p_surgery_item_id;
  END IF;

  IF v_item.allocation_status != 'allocated' THEN
    -- Not yet allocated, just update the quantity
    UPDATE public.eye_surgery_items
    SET planned_quantity = p_new_quantity,
        actual_quantity = p_new_quantity
    WHERE id = p_surgery_item_id;

    RETURN jsonb_build_object('status', 'updated', 'allocated', false);
  END IF;

  v_diff := p_new_quantity - v_item.planned_quantity;

  IF v_diff > 0 THEN
    -- Need more stock: check availability
    IF v_item.current_stock < v_diff THEN
      RAISE EXCEPTION 'Insufficient stock for %: need additional %s, have %s',
        v_item.item_name, v_diff, v_item.current_stock;
    END IF;

    -- Deduct additional
    UPDATE public.inventory
    SET quantity = quantity - v_diff
    WHERE id = v_item.inventory_item_id;

    INSERT INTO public.inventory_transactions (
      inventory_id, transaction_type, quantity, stock_before, stock_after, reference_id, remarks, created_by
    ) VALUES (
      v_item.inventory_item_id,
      'surgery_allocation',
      v_diff,
      v_item.current_stock,
      v_item.current_stock - v_diff,
      v_item.eye_surgery_id,
      format('Additional allocation for surgery %s', v_item.eye_surgery_id),
      auth.uid()
    );

  ELSIF v_diff < 0 THEN
    -- Return excess stock
    UPDATE public.inventory
    SET quantity = quantity + abs(v_diff)
    WHERE id = v_item.inventory_item_id;

    INSERT INTO public.inventory_transactions (
      inventory_id, transaction_type, quantity, stock_before, stock_after, reference_id, remarks, created_by
    ) VALUES (
      v_item.inventory_item_id,
      'surgery_return',
      abs(v_diff),
      v_item.current_stock,
      v_item.current_stock + abs(v_diff),
      v_item.eye_surgery_id,
      format('Reduced allocation for surgery %s', v_item.eye_surgery_id),
      auth.uid()
    );
  END IF;

  -- Update the item quantities
  UPDATE public.eye_surgery_items
  SET planned_quantity = p_new_quantity,
      actual_quantity = p_new_quantity
  WHERE id = p_surgery_item_id;

  RETURN jsonb_build_object('status', 'reconciled', 'diff', v_diff);
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Update consume_eye_surgery_inventory to NOT re-deduct allocated items
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.consume_eye_surgery_inventory(UUID);

CREATE OR REPLACE FUNCTION public.consume_eye_surgery_inventory(
  p_eye_surgery_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_item RECORD;
  v_consumed_count INT := 0;
BEGIN
  -- Only consume items that are pending (not yet allocated at scheduling)
  -- Items already allocated at scheduling time should just be marked consumed
  FOR v_item IN
    SELECT esi.id, esi.inventory_item_id, esi.planned_quantity,
           esi.actual_quantity, esi.allocation_status
    FROM public.eye_surgery_items esi
    WHERE esi.eye_surgery_id = p_eye_surgery_id
  LOOP
    IF v_item.allocation_status = 'allocated' THEN
      -- Already deducted at scheduling — just mark as consumed
      UPDATE public.eye_surgery_items
      SET allocation_status = 'consumed',
          consumed_at = now()
      WHERE id = v_item.id;
      v_consumed_count := v_consumed_count + 1;
    ELSIF v_item.allocation_status = 'pending' THEN
      -- Legacy: deduct now for items that weren't allocated at scheduling
      PERFORM deduct_inventory_for_item(v_item.inventory_item_id, v_item.actual_quantity, p_eye_surgery_id);
      
      UPDATE public.eye_surgery_items
      SET allocation_status = 'consumed',
          consumed_at = now()
      WHERE id = v_item.id;
      v_consumed_count := v_consumed_count + 1;
    END IF;
    -- 'consumed' and 'returned' items are skipped — no double deduction
  END LOOP;

  -- Mark surgery as in_surgery
  UPDATE public.eye_surgeries
  SET status = 'in_surgery',
      inventory_consumed_at = now()
  WHERE id = p_eye_surgery_id;

  RETURN jsonb_build_object(
    'status', 'in_surgery',
    'surgery_id', p_eye_surgery_id,
    'items_consumed', v_consumed_count
  );
END;
$$;

-- Helper to deduct inventory for a single item (used by legacy path)
DROP FUNCTION IF EXISTS public.deduct_inventory_for_item(UUID, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION public.deduct_inventory_for_item(
  p_inventory_id UUID,
  p_quantity NUMERIC,
  p_surgery_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_current NUMERIC;
BEGIN
  SELECT quantity INTO v_current
  FROM public.inventory
  WHERE id = p_inventory_id
  FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found';
  END IF;

  IF v_current < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for inventory item %', p_inventory_id;
  END IF;

  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE id = p_inventory_id;

  INSERT INTO public.inventory_transactions (
    inventory_id, transaction_type, quantity, stock_before, stock_after, reference_id, remarks, created_by
  ) VALUES (
    p_inventory_id,
    'surgery_consumption',
    p_quantity,
    v_current,
    v_current - p_quantity,
    p_surgery_id,
    format('Surgery consumption for surgery %s', p_surgery_id),
    auth.uid()
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.schedule_surgery_with_inventory(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_surgery_inventory(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_surgery_item_inventory(UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_eye_surgery_inventory(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deduct_inventory_for_item(UUID, NUMERIC, UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. Notify schema cache to reload (PostgREST)
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
