-- ============================================================================
-- MKES CARE+ — Sprint 5.4 Extension: Department-Wise Inventory & Stock Requests
-- Migration: 20261004180000_department_inventory_and_stock_requests.sql
-- Description:
--   1. Sequence for human-readable stock request numbers.
--   2. Table `public.department_inventory` for separate department stock balances.
--   3. Table `public.stock_requests` for staff request -> admin approve/fulfill workflow.
--   4. Views: `public.stock_request_records` and `public.department_inventory_records`.
--   5. RPC `public.submit_stock_request` (Staff requests stock for own assigned department).
--   6. RPC `public.approve_stock_request` (Admin approves requested quantity).
--   7. RPC `public.reject_stock_request` (Admin rejects request with reason).
--   8. RPC `public.fulfill_stock_request` (Admin atomically transfers central stock to department).
--   9. RPC `public.record_department_stock_consumption` (Deducts from department balance).
--  10. Row Level Security policies enforcing department isolation and role constraints.
-- ============================================================================

-- 1. Create Sequence for Stock Request Numbers
CREATE SEQUENCE IF NOT EXISTS public.stock_request_seq START WITH 1001;

-- 2. Create Table: Department Inventory
CREATE TABLE IF NOT EXISTS public.department_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  inventory_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
  quantity NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (quantity >= 0),
  minimum_stock NUMERIC(12,2) NOT NULL DEFAULT 5.00 CHECK (minimum_stock >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT uq_department_inventory_dept_item UNIQUE(department_id, inventory_id)
);

CREATE INDEX IF NOT EXISTS idx_dept_inventory_department ON public.department_inventory(department_id);
CREATE INDEX IF NOT EXISTS idx_dept_inventory_item ON public.department_inventory(inventory_id);

-- 3. Create Table: Stock Requests
CREATE TABLE IF NOT EXISTS public.stock_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number TEXT NOT NULL UNIQUE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  inventory_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
  requested_quantity NUMERIC(12,2) NOT NULL CHECK (requested_quantity > 0),
  approved_quantity NUMERIC(12,2) CHECK (approved_quantity >= 0),
  fulfilled_quantity NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (fulfilled_quantity >= 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'fulfilled', 'cancelled')),
  requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  fulfilled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  request_notes TEXT,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  reviewed_at TIMESTAMPTZ,
  fulfilled_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_stock_requests_dept ON public.stock_requests(department_id);
CREATE INDEX IF NOT EXISTS idx_stock_requests_item ON public.stock_requests(inventory_id);
CREATE INDEX IF NOT EXISTS idx_stock_requests_status ON public.stock_requests(status);
CREATE INDEX IF NOT EXISTS idx_stock_requests_requester ON public.stock_requests(requested_by);

-- 4. Triggers for updated_at
CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_department_inventory_updated_at ON public.department_inventory;
CREATE TRIGGER trg_department_inventory_updated_at
  BEFORE UPDATE ON public.department_inventory
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

DROP TRIGGER IF EXISTS trg_stock_requests_updated_at ON public.stock_requests;
CREATE TRIGGER trg_stock_requests_updated_at
  BEFORE UPDATE ON public.stock_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- 5. Views
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

CREATE OR REPLACE VIEW public.department_inventory_records AS
SELECT
  di.id,
  di.department_id,
  d.name AS department_name,
  di.inventory_id,
  i.name AS item_name,
  i.sku AS item_sku,
  i.unit AS item_unit,
  i.category AS item_category,
  i.brand AS item_brand,
  i.is_active AS item_is_active,
  di.quantity,
  di.minimum_stock,
  (di.quantity <= di.minimum_stock) AS is_low_stock,
  di.created_at,
  di.updated_at
FROM public.department_inventory di
JOIN public.departments d ON d.id = di.department_id
JOIN public.inventory i ON i.id = di.inventory_id;

-- 6. RPC: Submit Stock Request (Staff for their own department)
CREATE OR REPLACE FUNCTION public.submit_stock_request(
  p_inventory_id       UUID,
  p_requested_quantity NUMERIC,
  p_notes              TEXT DEFAULT NULL,
  p_target_dept_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID;
  v_user_role    TEXT;
  v_dept_id      UUID;
  v_dept_name    TEXT;
  v_req_num      TEXT;
  v_new_req_id   UUID;
  v_item_name    TEXT;
  v_created_at   TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to submit stock requests.';
  END IF;

  IF p_requested_quantity IS NULL OR p_requested_quantity <= 0 THEN
    RAISE EXCEPTION 'Requested quantity must be greater than zero.';
  END IF;

  -- Verify user role and assigned department
  SELECT role, department_id INTO v_user_role, v_dept_id
  FROM public.profiles
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  -- Admin can specify target department if provided, otherwise staff must use their own assigned department
  IF v_user_role = 'admin' AND p_target_dept_id IS NOT NULL THEN
    v_dept_id := p_target_dept_id;
  END IF;

  IF v_dept_id IS NULL THEN
    RAISE EXCEPTION 'You must have an assigned department to request stock.';
  END IF;

  -- Validate department exists
  SELECT name INTO v_dept_name FROM public.departments WHERE id = v_dept_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assigned department does not exist.';
  END IF;

  -- Validate inventory item exists
  SELECT name INTO v_item_name FROM public.inventory WHERE id = p_inventory_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active inventory item not found.';
  END IF;

  -- Generate human-readable request number: REQ-YYYYMM-XXXX
  v_req_num := 'REQ-' || to_char(now(), 'YYYYMM') || '-' || lpad(nextval('public.stock_request_seq')::text, 4, '0');

  INSERT INTO public.stock_requests (
    request_number,
    department_id,
    inventory_id,
    requested_quantity,
    status,
    requested_by,
    request_notes
  ) VALUES (
    v_req_num,
    v_dept_id,
    p_inventory_id,
    p_requested_quantity,
    'pending',
    v_user_id,
    p_notes
  )
  RETURNING id, created_at INTO v_new_req_id, v_created_at;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_new_req_id,
    'request_number', v_req_num,
    'department_id', v_dept_id,
    'department_name', v_dept_name,
    'inventory_id', p_inventory_id,
    'item_name', v_item_name,
    'requested_quantity', p_requested_quantity,
    'status', 'pending',
    'created_at', v_created_at
  );
END;
$$;

-- 7. RPC: Approve Stock Request (Admin only)
CREATE OR REPLACE FUNCTION public.approve_stock_request(
  p_request_id         UUID,
  p_approved_quantity  NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id     UUID;
  v_req         RECORD;
  v_app_qty     NUMERIC(12,2);
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can approve stock requests.';
  END IF;

  SELECT * INTO v_req
  FROM public.stock_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found.';
  END IF;

  IF v_req.status != 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be approved. Current status: %', v_req.status;
  END IF;

  v_app_qty := COALESCE(p_approved_quantity, v_req.requested_quantity);
  IF v_app_qty <= 0 THEN
    RAISE EXCEPTION 'Approved quantity must be greater than zero.';
  END IF;

  UPDATE public.stock_requests
  SET
    status = 'approved',
    approved_quantity = v_app_qty,
    reviewed_by = v_user_id,
    reviewed_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now())
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'status', 'approved',
    'approved_quantity', v_app_qty
  );
END;
$$;

-- 8. RPC: Reject Stock Request (Admin only)
CREATE OR REPLACE FUNCTION public.reject_stock_request(
  p_request_id       UUID,
  p_rejection_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_req     RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can reject stock requests.';
  END IF;

  SELECT * INTO v_req
  FROM public.stock_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found.';
  END IF;

  IF v_req.status != 'pending' THEN
    RAISE EXCEPTION 'Only pending requests can be rejected. Current status: %', v_req.status;
  END IF;

  UPDATE public.stock_requests
  SET
    status = 'rejected',
    rejection_reason = p_rejection_reason,
    reviewed_by = v_user_id,
    reviewed_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now())
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'status', 'rejected',
    'rejection_reason', p_rejection_reason
  );
END;
$$;

-- 9. RPC: Fulfill Stock Request (Admin only - Atomic Stock Transfer)
CREATE OR REPLACE FUNCTION public.fulfill_stock_request(
  p_request_id        UUID,
  p_fulfill_quantity  NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id         UUID;
  v_req             RECORD;
  v_central_stock   NUMERIC(12,2);
  v_fulfill_qty     NUMERIC(12,2);
  v_dept_name       TEXT;
  v_item_name       TEXT;
  v_dept_after      NUMERIC(12,2);
  v_tx_id           UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can fulfill stock requests.';
  END IF;

  -- 1. Lock the request row
  SELECT * INTO v_req
  FROM public.stock_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock request not found.';
  END IF;

  IF v_req.status = 'fulfilled' THEN
    RAISE EXCEPTION 'Stock request has already been fulfilled.';
  END IF;

  IF v_req.status != 'approved' THEN
    RAISE EXCEPTION 'Request must be approved before fulfillment. Current status: %', v_req.status;
  END IF;

  -- 2. Determine fulfillment quantity
  v_fulfill_qty := COALESCE(p_fulfill_quantity, v_req.approved_quantity, v_req.requested_quantity);
  IF v_fulfill_qty <= 0 THEN
    RAISE EXCEPTION 'Fulfillment quantity must be greater than zero.';
  END IF;

  -- 3. Lock central inventory row
  SELECT quantity, name INTO v_central_stock, v_item_name
  FROM public.inventory
  WHERE id = v_req.inventory_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item not found.';
  END IF;

  -- 4. Validate sufficient central stock
  IF v_central_stock < v_fulfill_qty THEN
    RAISE EXCEPTION 'Insufficient central stock. Available: %, Requested fulfillment: %', v_central_stock, v_fulfill_qty;
  END IF;

  -- 5. Fetch department name for audit
  SELECT name INTO v_dept_name FROM public.departments WHERE id = v_req.department_id;

  -- 6. Deduct from central stock (Central stock before = Central stock after + v_fulfill_qty)
  UPDATE public.inventory
  SET
    quantity = quantity - v_fulfill_qty,
    updated_at = timezone('utc'::text, now())
  WHERE id = v_req.inventory_id;

  -- 7. Credit to department inventory (Department stock after = Department stock before + v_fulfill_qty)
  INSERT INTO public.department_inventory (
    department_id,
    inventory_id,
    quantity
  ) VALUES (
    v_req.department_id,
    v_req.inventory_id,
    v_fulfill_qty
  )
  ON CONFLICT (department_id, inventory_id)
  DO UPDATE SET
    quantity = public.department_inventory.quantity + EXCLUDED.quantity,
    updated_at = timezone('utc'::text, now())
  RETURNING quantity INTO v_dept_after;

  -- 8. Record stock transfer in inventory_transactions audit history
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
    v_req.inventory_id,
    'stock_out',
    v_fulfill_qty,
    v_central_stock,
    v_central_stock - v_fulfill_qty,
    'Allocated to ' || COALESCE(v_dept_name, 'Department'),
    'Stock Request #' || v_req.request_number || COALESCE(' - ' || v_req.request_notes, ''),
    v_user_id
  )
  RETURNING id INTO v_tx_id;

  -- 9. Update stock request record
  UPDATE public.stock_requests
  SET
    status = 'fulfilled',
    fulfilled_quantity = v_fulfill_qty,
    fulfilled_by = v_user_id,
    fulfilled_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now())
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'transaction_id', v_tx_id,
    'fulfilled_quantity', v_fulfill_qty,
    'central_stock_before', v_central_stock,
    'central_stock_after', v_central_stock - v_fulfill_qty,
    'department_stock_after', v_dept_after
  );
END;
$$;

-- 10. RPC: Record Department Stock Consumption (Clinical / Department-level)
CREATE OR REPLACE FUNCTION public.record_department_stock_consumption(
  p_department_id UUID,
  p_inventory_id  UUID,
  p_quantity      NUMERIC,
  p_patient_id    UUID DEFAULT NULL,
  p_record_type   TEXT DEFAULT NULL,
  p_record_id     UUID DEFAULT NULL,
  p_remarks       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        UUID;
  v_current_stock  NUMERIC(12,2);
  v_new_stock      NUMERIC(12,2);
  v_dept_name      TEXT;
  v_patient_name   TEXT := NULL;
  v_patient_num    TEXT := NULL;
  v_tx_id          UUID;
  v_usage_id       UUID := NULL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Consumption quantity must be greater than zero.';
  END IF;

  -- 1. Lock department inventory row
  SELECT quantity INTO v_current_stock
  FROM public.department_inventory
  WHERE department_id = p_department_id AND inventory_id = p_inventory_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No stock allocated to this department for the selected item.';
  END IF;

  -- 2. Validate sufficient department stock
  IF v_current_stock < p_quantity THEN
    RAISE EXCEPTION 'Insufficient department stock. Available: %, Requested: %', v_current_stock, p_quantity;
  END IF;

  v_new_stock := v_current_stock - p_quantity;

  -- 3. Deduct department stock
  UPDATE public.department_inventory
  SET
    quantity = v_new_stock,
    updated_at = timezone('utc'::text, now())
  WHERE department_id = p_department_id AND inventory_id = p_inventory_id;

  -- 4. Get department and patient info for audit
  SELECT name INTO v_dept_name FROM public.departments WHERE id = p_department_id;

  IF p_patient_id IS NOT NULL THEN
    SELECT name, patient_number INTO v_patient_name, v_patient_num
    FROM public.patients WHERE id = p_patient_id;
  END IF;

  -- 5. Record clinical usage entry if patient/clinical record linked
  IF p_patient_id IS NOT NULL AND p_record_type IS NOT NULL AND p_record_id IS NOT NULL THEN
    INSERT INTO public.clinical_inventory_usage (
      patient_id,
      record_type,
      record_id,
      inventory_id,
      quantity,
      transaction_id,
      remarks,
      consumed_at,
      created_by
    ) VALUES (
      p_patient_id,
      p_record_type,
      p_record_id,
      p_inventory_id,
      p_quantity,
      NULL,
      p_remarks,
      timezone('utc'::text, now()),
      v_user_id
    )
    RETURNING id INTO v_usage_id;
  END IF;

  -- 6. Record transaction audit
  INSERT INTO public.inventory_transactions (
    inventory_id,
    transaction_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    remarks,
    patient_id,
    performed_by
  ) VALUES (
    p_inventory_id,
    'stock_out',
    p_quantity,
    v_current_stock,
    v_new_stock,
    CASE WHEN p_patient_id IS NOT NULL THEN 'Dispensed to Patient' ELSE 'Department Usage' END,
    COALESCE(p_remarks, 'Department: ' || COALESCE(v_dept_name, '')),
    p_patient_id,
    v_user_id
  )
  RETURNING id INTO v_tx_id;

  IF v_usage_id IS NOT NULL THEN
    UPDATE public.clinical_inventory_usage SET transaction_id = v_tx_id WHERE id = v_usage_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'department_id', p_department_id,
    'inventory_id', p_inventory_id,
    'quantity_consumed', p_quantity,
    'department_stock_before', v_current_stock,
    'department_stock_after', v_new_stock,
    'transaction_id', v_tx_id,
    'usage_id', v_usage_id
  );
END;
$$;

-- 11. Row Level Security Policies

ALTER TABLE public.department_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_requests ENABLE ROW LEVEL SECURITY;

-- Department Inventory Policies
DROP POLICY IF EXISTS "department_inventory_select_policy" ON public.department_inventory;
CREATE POLICY "department_inventory_select_policy"
  ON public.department_inventory
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin() OR
    department_id = (SELECT department_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "department_inventory_admin_write" ON public.department_inventory;
CREATE POLICY "department_inventory_admin_write"
  ON public.department_inventory
  FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Stock Requests Policies
DROP POLICY IF EXISTS "stock_requests_select_policy" ON public.stock_requests;
CREATE POLICY "stock_requests_select_policy"
  ON public.stock_requests
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin() OR
    department_id = (SELECT department_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "stock_requests_insert_policy" ON public.stock_requests;
CREATE POLICY "stock_requests_insert_policy"
  ON public.stock_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin() OR
    (
      public.is_admin_or_staff() AND
      department_id = (SELECT department_id FROM public.profiles WHERE id = auth.uid()) AND
      requested_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "stock_requests_admin_update" ON public.stock_requests;
CREATE POLICY "stock_requests_admin_update"
  ON public.stock_requests
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "stock_requests_no_delete" ON public.stock_requests;
CREATE POLICY "stock_requests_no_delete"
  ON public.stock_requests
  FOR DELETE
  TO authenticated
  USING (false);

-- 12. Permissions
REVOKE ALL ON FUNCTION public.submit_stock_request(UUID, NUMERIC, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_stock_request(UUID, NUMERIC, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_stock_request(UUID, NUMERIC, TEXT, UUID) TO service_role;

REVOKE ALL ON FUNCTION public.approve_stock_request(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_stock_request(UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_stock_request(UUID, NUMERIC) TO service_role;

REVOKE ALL ON FUNCTION public.reject_stock_request(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_stock_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_stock_request(UUID, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.fulfill_stock_request(UUID, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fulfill_stock_request(UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_stock_request(UUID, NUMERIC) TO service_role;

REVOKE ALL ON FUNCTION public.record_department_stock_consumption(UUID, UUID, NUMERIC, UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_department_stock_consumption(UUID, UUID, NUMERIC, UUID, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_department_stock_consumption(UUID, UUID, NUMERIC, UUID, TEXT, UUID, TEXT) TO service_role;
