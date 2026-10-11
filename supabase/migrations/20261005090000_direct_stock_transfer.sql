-- ============================================================================
-- MKES CARE+ — Direct Stock Transfer Migration
-- Migration: 20261005090000_direct_stock_transfer.sql
-- Description:
--   Replaces the 3-step approve/fulfill workflow with a direct atomic transfer.
--   1. New RPC `submit_and_transfer_stock` — validates, deducts central, credits
--      department, records audit, and creates a fulfilled stock_request in one call.
--   2. Updates `stock_requests.status` CHECK to include 'transferred'.
--   3. Updates RLS policies so staff can select a target department.
--   4. Preserves existing RPCs for backward compatibility (historical data).
-- ============================================================================

-- 1. Alter status CHECK constraint to include 'transferred'
ALTER TABLE public.stock_requests DROP CONSTRAINT IF EXISTS stock_requests_status_check;
ALTER TABLE public.stock_requests
  ADD CONSTRAINT stock_requests_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'fulfilled', 'cancelled', 'transferred'));

-- 2. New RPC: Submit and Transfer Stock (Atomic Direct Allocation)
CREATE OR REPLACE FUNCTION public.submit_and_transfer_stock(
  p_inventory_id       UUID,
  p_requested_quantity NUMERIC,
  p_target_dept_id     UUID,
  p_notes              TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_user_role      TEXT;
  v_user_dept_id   UUID;
  v_dept_name      TEXT;
  v_req_num        TEXT;
  v_new_req_id     UUID;
  v_item_name      TEXT;
  v_central_stock  NUMERIC(12,2);
  v_dept_after     NUMERIC(12,2);
  v_tx_id          UUID;
  v_created_at     TIMESTAMPTZ;
BEGIN
  -- Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to submit stock requests.';
  END IF;

  -- Input validation
  IF p_inventory_id IS NULL THEN
    RAISE EXCEPTION 'Inventory item ID is required.';
  END IF;

  IF p_target_dept_id IS NULL THEN
    RAISE EXCEPTION 'Target department is required.';
  END IF;

  IF p_requested_quantity IS NULL OR p_requested_quantity <= 0 THEN
    RAISE EXCEPTION 'Requested quantity must be greater than zero.';
  END IF;

  -- Verify user role and assigned department
  SELECT role, department_id INTO v_user_role, v_user_dept_id
  FROM public.profiles
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  -- Authorization: admin can target any department, staff can target their assigned department
  IF v_user_role != 'admin' THEN
    IF v_user_dept_id IS NULL THEN
      RAISE EXCEPTION 'You must have an assigned department to request stock.';
    END IF;
    IF v_user_dept_id != p_target_dept_id THEN
      RAISE EXCEPTION 'You are not authorized to request stock for this department.';
    END IF;
  END IF;

  -- Validate department exists and is active
  SELECT name INTO v_dept_name
  FROM public.departments
  WHERE id = p_target_dept_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target department does not exist.';
  END IF;

  -- Lock central inventory row and validate
  SELECT quantity, name INTO v_central_stock, v_item_name
  FROM public.inventory
  WHERE id = p_inventory_id AND is_active = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active inventory item not found.';
  END IF;

  -- Block items with zero central stock
  IF v_central_stock <= 0 THEN
    RAISE EXCEPTION 'This item is currently out of stock.';
  END IF;

  -- Block requests exceeding available stock
  IF v_central_stock < p_requested_quantity THEN
    RAISE EXCEPTION 'Insufficient central stock. Available: %, Requested: %', v_central_stock, p_requested_quantity;
  END IF;

  -- Generate human-readable request number: REQ-YYYYMM-XXXX
  v_req_num := 'REQ-' || to_char(now(), 'YYYYMM') || '-' || lpad(nextval('public.stock_request_seq')::text, 4, '0');

  -- Deduct from central stock
  UPDATE public.inventory
  SET
    quantity = quantity - p_requested_quantity,
    updated_at = timezone('utc'::text, now())
  WHERE id = p_inventory_id;

  -- Credit to department inventory (upsert)
  INSERT INTO public.department_inventory (
    department_id,
    inventory_id,
    quantity
  ) VALUES (
    p_target_dept_id,
    p_inventory_id,
    p_requested_quantity
  )
  ON CONFLICT (department_id, inventory_id)
  DO UPDATE SET
    quantity = public.department_inventory.quantity + EXCLUDED.quantity,
    updated_at = timezone('utc'::text, now())
  RETURNING quantity INTO v_dept_after;

  -- Record stock transfer in inventory_transactions audit history
  INSERT INTO public.inventory_transactions (
    inventory_id,
    transaction_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    remarks,
    performed_by
  ) VALUES (
    p_inventory_id,
    'stock_out',
    p_requested_quantity,
    v_central_stock,
    v_central_stock - p_requested_quantity,
    'Allocated to ' || COALESCE(v_dept_name, 'Department'),
    'Direct Transfer REQ#' || v_req_num || COALESCE(' - ' || p_notes, ''),
    v_user_id
  )
  RETURNING id INTO v_tx_id;

  -- Create stock request record with status 'transferred'
  INSERT INTO public.stock_requests (
    request_number,
    department_id,
    inventory_id,
    requested_quantity,
    approved_quantity,
    fulfilled_quantity,
    status,
    requested_by,
    reviewed_by,
    fulfilled_by,
    request_notes,
    reviewed_at,
    fulfilled_at
  ) VALUES (
    v_req_num,
    p_target_dept_id,
    p_inventory_id,
    p_requested_quantity,
    p_requested_quantity,
    p_requested_quantity,
    'transferred',
    v_user_id,
    v_user_id,
    v_user_id,
    p_notes,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
  )
  RETURNING id, created_at INTO v_new_req_id, v_created_at;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_new_req_id,
    'request_number', v_req_num,
    'department_id', p_target_dept_id,
    'department_name', v_dept_name,
    'inventory_id', p_inventory_id,
    'item_name', v_item_name,
    'requested_quantity', p_requested_quantity,
    'fulfilled_quantity', p_requested_quantity,
    'status', 'transferred',
    'central_stock_before', v_central_stock,
    'central_stock_after', v_central_stock - p_requested_quantity,
    'department_stock_after', v_dept_after,
    'transaction_id', v_tx_id,
    'created_at', v_created_at
  );
END;
$$;

-- 3. Permissions for the new RPC
REVOKE ALL ON FUNCTION public.submit_and_transfer_stock(UUID, NUMERIC, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_and_transfer_stock(UUID, NUMERIC, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_and_transfer_stock(UUID, NUMERIC, UUID, TEXT) TO service_role;

-- 4. Update RLS policies for stock_requests to support direct transfers
-- Staff can now insert transferred requests (not just pending)
DROP POLICY IF EXISTS "stock_requests_insert_policy" ON public.stock_requests;
CREATE POLICY "stock_requests_insert_policy"
  ON public.stock_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin() OR
    (
      public.is_admin_or_staff() AND
      requested_by = auth.uid()
    )
  );

-- 5. Update stock_request_records view to include 'transferred' status
CREATE OR REPLACE VIEW public.stock_request_records AS
SELECT
  r.id,
  r.request_number,
  r.department_id,
  d.name AS department_name,
  r.inventory_id,
  i.name AS item_name,
  i.sku AS item_sku,
  i.unit AS item_unit,
  i.category AS item_category,
  i.quantity AS central_stock,
  r.requested_quantity,
  r.approved_quantity,
  r.fulfilled_quantity,
  r.status,
  r.requested_by,
  p_req.full_name AS requested_by_name,
  r.reviewed_by,
  p_rev.full_name AS reviewed_by_name,
  r.fulfilled_by,
  p_ful.full_name AS fulfilled_by_name,
  r.request_notes,
  r.rejection_reason,
  r.created_at,
  r.reviewed_at,
  r.fulfilled_at,
  r.updated_at
FROM public.stock_requests r
JOIN public.departments d ON d.id = r.department_id
JOIN public.inventory i ON i.id = r.inventory_id
LEFT JOIN public.profiles p_req ON p_req.id = r.requested_by
LEFT JOIN public.profiles p_rev ON p_rev.id = r.reviewed_by
LEFT JOIN public.profiles p_ful ON p_ful.id = r.fulfilled_by;

-- ============================================================================
-- MANUAL STEP REQUIRED:
-- Run this SQL in Supabase Dashboard -> SQL Editor to apply the migration.
-- The existing approve/reject/fulfill RPCs are preserved for historical data
-- but will no longer be called by the updated Flutter app.
-- ============================================================================
