-- ============================================================================
-- MKES CARE+ — Migration: 20261015180000_fix_inventory_department_allocation.sql
-- Description:
--   1. Adds department_id to inventory_transactions and clinical_inventory_usage.
--   2. Adds idempotency_key to clinical_inventory_usage to prevent duplicate stock deductions.
--   3. Upgrades record_clinical_inventory_consumption RPC to attribute usage
--      to the proper department (Eye, Dental, etc.) and update department_inventory balances.
--   4. Validates stock availability, prevents double deductions on retries.
-- ============================================================================

-- 1. Ensure department_id column exists on inventory_transactions
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS department_id UUID
  REFERENCES public.departments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_department_id
  ON public.inventory_transactions(department_id);

-- 2. Ensure department_id and idempotency_key exist on clinical_inventory_usage
ALTER TABLE public.clinical_inventory_usage
  ADD COLUMN IF NOT EXISTS department_id UUID
  REFERENCES public.departments(id) ON DELETE SET NULL;

ALTER TABLE public.clinical_inventory_usage
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE INDEX IF NOT EXISTS idx_clinical_inventory_usage_dept
  ON public.clinical_inventory_usage(department_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_clinical_usage_idempotency
  ON public.clinical_inventory_usage(idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 3. Atomic RPC for Clinical Inventory Consumption with Department Allocation
CREATE OR REPLACE FUNCTION public.record_clinical_inventory_consumption(
  p_patient_id      UUID,
  p_record_type     TEXT,
  p_record_id       UUID,
  p_inventory_id    UUID,
  p_quantity        NUMERIC,
  p_remarks         TEXT DEFAULT NULL,
  p_department_id   UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id                UUID;
  v_patient_exists         BOOLEAN;
  v_patient_dept           TEXT;
  v_patient_name           TEXT;
  v_patient_number         TEXT;
  v_resolved_dept_id       UUID := p_department_id;
  v_dept_name              TEXT := NULL;
  v_existing_usage         RECORD;
  v_item_name              TEXT;
  v_item_unit              TEXT;
  v_central_stock          NUMERIC(12,2);
  v_new_central_stock      NUMERIC(12,2);
  v_dept_stock             NUMERIC(12,2);
  v_has_dept_inventory     BOOLEAN := false;
  v_tx_id                  UUID;
  v_usage_id               UUID;
  v_audit_remarks          TEXT;
BEGIN
  -- 1. Check authentication
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to record clinical inventory consumption.';
  END IF;

  -- 2. Check permission
  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only Admins and Staff can record clinical inventory consumption.';
  END IF;

  -- 3. Validate input quantity
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  IF p_record_type NOT IN ('eye_examination', 'dental_treatment', 'eye_surgery', 'other') THEN
    RAISE EXCEPTION 'Invalid record type: %', p_record_type;
  END IF;

  -- 4. Check patient existence & fetch department
  SELECT EXISTS (SELECT 1 FROM public.patients WHERE id = p_patient_id),
         department, name, patient_number
  INTO v_patient_exists, v_patient_dept, v_patient_name, v_patient_number
  FROM public.patients
  WHERE id = p_patient_id;

  IF NOT v_patient_exists THEN
    RAISE EXCEPTION 'Patient with ID % not found.', p_patient_id;
  END IF;

  -- 5. Idempotency Check: Prevent duplicate stock deduction on network retry or repeated click
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing_usage
    FROM public.clinical_inventory_usage
    WHERE idempotency_key = p_idempotency_key
    LIMIT 1;

    IF v_existing_usage.id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'status', 'already_recorded',
        'usage_id', v_existing_usage.id,
        'transaction_id', v_existing_usage.transaction_id,
        'quantity', v_existing_usage.quantity
      );
    END IF;
  END IF;

  -- Secondary Idempotency: exact duplicate within last 60 seconds
  SELECT * INTO v_existing_usage
  FROM public.clinical_inventory_usage
  WHERE patient_id = p_patient_id
    AND record_type = p_record_type
    AND record_id = p_record_id
    AND inventory_id = p_inventory_id
    AND quantity = p_quantity
    AND consumed_at >= (now() - INTERVAL '60 seconds')
  ORDER BY consumed_at DESC
  LIMIT 1;

  IF v_existing_usage.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'already_recorded',
      'usage_id', v_existing_usage.id,
      'transaction_id', v_existing_usage.transaction_id,
      'quantity', v_existing_usage.quantity
    );
  END IF;

  -- 6. Resolve Department
  IF v_resolved_dept_id IS NOT NULL THEN
    SELECT name INTO v_dept_name
    FROM public.departments
    WHERE id = v_resolved_dept_id;
  END IF;

  IF v_resolved_dept_id IS NULL OR v_dept_name IS NULL THEN
    IF p_record_type IN ('eye_examination', 'eye_surgery') THEN
      SELECT id, name INTO v_resolved_dept_id, v_dept_name
      FROM public.departments
      WHERE LOWER(name) = 'eye'
      LIMIT 1;
    ELSIF p_record_type = 'dental_treatment' THEN
      SELECT id, name INTO v_resolved_dept_id, v_dept_name
      FROM public.departments
      WHERE LOWER(name) = 'dental'
      LIMIT 1;
    ELSIF v_patient_dept IS NOT NULL THEN
      SELECT id, name INTO v_resolved_dept_id, v_dept_name
      FROM public.departments
      WHERE LOWER(name) = LOWER(v_patient_dept)
      LIMIT 1;
    END IF;
  END IF;

  -- Fallback to first available clinic department if still unassigned
  IF v_resolved_dept_id IS NULL THEN
    SELECT id, name INTO v_resolved_dept_id, v_dept_name
    FROM public.departments
    ORDER BY name ASC
    LIMIT 1;
  END IF;

  -- 7. Lock Central Inventory Row and Validate Stock
  SELECT quantity, name, unit
  INTO v_central_stock, v_item_name, v_item_unit
  FROM public.inventory
  WHERE id = p_inventory_id
  FOR UPDATE;

  IF v_central_stock IS NULL THEN
    RAISE EXCEPTION 'Inventory item % not found.', p_inventory_id;
  END IF;

  IF v_central_stock < p_quantity THEN
    RAISE EXCEPTION 'Insufficient central stock for %: need %, available % %',
      v_item_name, p_quantity, v_central_stock, COALESCE(v_item_unit, 'units');
  END IF;

  -- 8. Check Department Inventory if allocated
  IF v_resolved_dept_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.department_inventory
      WHERE department_id = v_resolved_dept_id AND inventory_id = p_inventory_id
    ) INTO v_has_dept_inventory;

    IF v_has_dept_inventory THEN
      SELECT quantity INTO v_dept_stock
      FROM public.department_inventory
      WHERE department_id = v_resolved_dept_id AND inventory_id = p_inventory_id
      FOR UPDATE;

      -- If department inventory exists, deduct from department stock
      IF v_dept_stock >= p_quantity THEN
        UPDATE public.department_inventory
        SET quantity = quantity - p_quantity,
            updated_at = timezone('utc'::text, now())
        WHERE department_id = v_resolved_dept_id AND inventory_id = p_inventory_id;
      ELSE
        -- Department balance partially depleted; deduct available and log
        UPDATE public.department_inventory
        SET quantity = GREATEST(0, quantity - p_quantity),
            updated_at = timezone('utc'::text, now())
        WHERE department_id = v_resolved_dept_id AND inventory_id = p_inventory_id;
      END IF;
    END IF;
  END IF;

  -- 9. Deduct Central Inventory Atomically
  v_new_central_stock := v_central_stock - p_quantity;
  UPDATE public.inventory
  SET quantity = v_new_central_stock,
      updated_at = now()
  WHERE id = p_inventory_id;

  -- 10. Prepare Audit Remarks
  v_audit_remarks := format('[Dept: %s] Clinical Usage (%s)', COALESCE(v_dept_name, 'General'), p_record_type);
  IF p_remarks IS NOT NULL AND trim(p_remarks) <> '' THEN
    v_audit_remarks := v_audit_remarks || ': ' || trim(p_remarks);
  END IF;

  -- 11. Insert Inventory Transaction with Department Allocation
  v_tx_id := gen_random_uuid();
  INSERT INTO public.inventory_transactions (
    id,
    inventory_id,
    transaction_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    remarks,
    performed_by,
    created_by,
    patient_id,
    department_id,
    created_at
  ) VALUES (
    v_tx_id,
    p_inventory_id,
    'stock_out',
    p_quantity,
    v_central_stock,
    v_new_central_stock,
    'Dispensed to Patient',
    v_audit_remarks,
    v_user_id,
    v_user_id,
    p_patient_id,
    v_resolved_dept_id,
    now()
  );

  -- 12. Insert Clinical Inventory Usage Record
  v_usage_id := gen_random_uuid();
  INSERT INTO public.clinical_inventory_usage (
    id,
    patient_id,
    record_type,
    record_id,
    inventory_id,
    quantity,
    transaction_id,
    department_id,
    idempotency_key,
    remarks,
    consumed_at,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    v_usage_id,
    p_patient_id,
    p_record_type,
    p_record_id,
    p_inventory_id,
    p_quantity,
    v_tx_id,
    v_resolved_dept_id,
    p_idempotency_key,
    p_remarks,
    now(),
    v_user_id,
    now(),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'usage_id', v_usage_id,
    'transaction_id', v_tx_id,
    'department_id', v_resolved_dept_id,
    'department_name', v_dept_name,
    'quantity', p_quantity,
    'stock_before', v_central_stock,
    'stock_after', v_new_central_stock
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT, UUID, TEXT) TO service_role;
