-- ============================================================================
-- FIX: DROP AMBIGUOUS OVERLOADED perform_stock_operation FUNCTIONS
-- AND INSTALL UNIFIED 8-PARAMETER FUNCTION WITH FEFO & PRICING
-- ============================================================================

-- 1. Drop all prior ambiguous overloaded signatures
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID);

-- 2. Create single unified perform_stock_operation function
CREATE OR REPLACE FUNCTION public.perform_stock_operation(
  p_inventory_id      UUID,
  p_transaction_type  TEXT,
  p_quantity          NUMERIC,
  p_reason            TEXT DEFAULT NULL,
  p_remarks           TEXT DEFAULT NULL,
  p_patient_id        UUID DEFAULT NULL,
  p_total_amount      NUMERIC DEFAULT NULL,
  p_vendor_id         UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id            UUID;
  v_user_name          TEXT;
  v_current_stock      NUMERIC(12,2);
  v_new_stock          NUMERIC(12,2);
  v_min_stock          NUMERIC(12,2);
  v_item_name          TEXT;
  v_unit               TEXT;
  v_entered_low_stock  BOOLEAN := false;
  v_admin_recipient    RECORD;
  v_transaction_id     UUID;
  v_created_at         TIMESTAMPTZ;
  v_final_patient_id   UUID := NULL;
  v_patient_name       TEXT := NULL;
  v_patient_number     TEXT := NULL;
  v_unit_price         NUMERIC(12,2) := NULL;
  -- FEFO variables
  v_batch              RECORD;
  v_remaining_deduct   NUMERIC(12,2);
  v_batch_deduct       NUMERIC(12,2);
  v_batches_summary    TEXT := '';
  v_final_remarks      TEXT;
  v_next_expiry        DATE;
BEGIN
  -- 1. Derive performed_by strictly from authenticated user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to perform stock operations.';
  END IF;

  -- 2. Validate quantity
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Stock quantity must be greater than zero.';
  END IF;

  -- 3. Validate transaction type
  IF p_transaction_type NOT IN ('stock_in', 'stock_out') THEN
    RAISE EXCEPTION 'Invalid transaction type: %. Must be stock_in or stock_out.', p_transaction_type;
  END IF;

  -- 4. Calculate unit price if total amount paid is provided for Stock In
  IF p_transaction_type = 'stock_in' AND p_total_amount IS NOT NULL AND p_total_amount >= 0 THEN
    IF p_quantity > 0 THEN
      v_unit_price := ROUND((p_total_amount / p_quantity), 2);
    END IF;
  END IF;

  -- 5. Validate patient selection strictly for "Dispensed to Patient"
  IF p_transaction_type = 'stock_out' AND p_reason = 'Dispensed to Patient' THEN
    IF p_patient_id IS NULL THEN
      RAISE EXCEPTION 'Please select a patient.';
    END IF;
    -- Verify patient exists in database
    SELECT name, patient_number INTO v_patient_name, v_patient_number
      FROM public.patients
      WHERE id = p_patient_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selected patient does not exist.';
    END IF;
    v_final_patient_id := p_patient_id;
  ELSE
    v_final_patient_id := NULL;
  END IF;

  -- 6. Lock row with SELECT FOR UPDATE to prevent race conditions
  SELECT quantity, minimum_stock, name, unit
    INTO v_current_stock, v_min_stock, v_item_name, v_unit
    FROM public.inventory
    WHERE id = p_inventory_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item not found.';
  END IF;

  -- 7. Calculate new stock atomically
  IF p_transaction_type = 'stock_in' THEN
    v_new_stock := v_current_stock + p_quantity;

    -- If stock rose above minimum, mark past low_stock alerts as read
    IF v_min_stock IS NOT NULL AND v_current_stock <= v_min_stock AND v_new_stock > v_min_stock THEN
      UPDATE public.notifications
        SET is_read = true
        WHERE related_id = p_inventory_id
          AND type = 'low_stock'
          AND is_read = false;
    END IF;

    v_final_remarks := p_remarks;

  ELSIF p_transaction_type = 'stock_out' THEN
    IF v_current_stock < p_quantity THEN
      RAISE EXCEPTION 'Insufficient stock. Available: %, Requested: %', v_current_stock, p_quantity;
    END IF;
    v_new_stock := v_current_stock - p_quantity;

    -- FEFO: First Expiry First Out batch deduction
    v_remaining_deduct := p_quantity;
    FOR v_batch IN
      SELECT id, batch_number, remaining_quantity, expiry_date
      FROM public.inventory_batches
      WHERE inventory_id = p_inventory_id
        AND remaining_quantity > 0
      ORDER BY
        expiry_date ASC NULLS LAST,
        received_date ASC,
        created_at ASC
      FOR UPDATE
    LOOP
      v_batch_deduct := LEAST(v_batch.remaining_quantity, v_remaining_deduct);

      UPDATE public.inventory_batches
      SET remaining_quantity = remaining_quantity - v_batch_deduct,
          updated_at = now()
      WHERE id = v_batch.id;

      v_batches_summary := v_batches_summary ||
        (CASE WHEN v_batches_summary = '' THEN '' ELSE ', ' END) ||
        v_batch.batch_number || ' (' || v_batch_deduct::text || ' units)';

      v_remaining_deduct := v_remaining_deduct - v_batch_deduct;
      EXIT WHEN v_remaining_deduct <= 0;
    END LOOP;

    -- Construct audit remarks with consumed batches
    IF v_batches_summary <> '' THEN
      v_final_remarks := CASE
        WHEN p_remarks IS NOT NULL AND trim(p_remarks) <> ''
          THEN p_remarks || ' [Batches Consumed: ' || v_batches_summary || ']'
        ELSE 'Batches Consumed: ' || v_batches_summary
      END;
    ELSE
      v_final_remarks := p_remarks;
    END IF;

    -- Check if this stock out caused item to enter low-stock state
    IF v_min_stock IS NOT NULL AND v_min_stock > 0 THEN
      IF v_current_stock > v_min_stock AND v_new_stock <= v_min_stock THEN
        v_entered_low_stock := true;
      END IF;
    END IF;
  END IF;

  -- 8. Compute next earliest expiry date from remaining active batches
  SELECT MIN(expiry_date)
  INTO v_next_expiry
  FROM public.inventory_batches
  WHERE inventory_id = p_inventory_id
    AND remaining_quantity > 0
    AND expiry_date IS NOT NULL;

  -- 9. Update inventory quantity, effective earliest expiry, and restock info
  UPDATE public.inventory
    SET quantity = v_new_stock,
        expiry_date = COALESCE(v_next_expiry, inventory.expiry_date),
        vendor_id = COALESCE(p_vendor_id, inventory.vendor_id),
        last_quantity_supplied = CASE WHEN p_transaction_type = 'stock_in' THEN p_quantity ELSE inventory.last_quantity_supplied END,
        last_total_amount = CASE WHEN p_transaction_type = 'stock_in' AND p_total_amount IS NOT NULL THEN p_total_amount ELSE inventory.last_total_amount END,
        price = CASE WHEN v_unit_price IS NOT NULL THEN v_unit_price ELSE inventory.price END,
        updated_at = now()
    WHERE id = p_inventory_id;

  -- 10. If vendor is provided for stock_in, update vendor's latest delivery info
  IF p_transaction_type = 'stock_in' AND p_vendor_id IS NOT NULL THEN
    UPDATE public.vendors
      SET last_quantity = p_quantity,
          last_total_amount = COALESCE(p_total_amount, vendors.last_total_amount),
          last_delivery_date = CURRENT_DATE,
          updated_at = now()
      WHERE id = p_vendor_id;
  END IF;

  -- 11. Insert audit transaction
  v_transaction_id := gen_random_uuid();
  v_created_at := now();

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
    vendor_id,
    total_amount,
    unit_price,
    created_at
  ) VALUES (
    v_transaction_id,
    p_inventory_id,
    p_transaction_type,
    p_quantity,
    v_current_stock,
    v_new_stock,
    p_reason,
    v_final_remarks,
    v_user_id,
    v_user_id,
    v_final_patient_id,
    p_vendor_id,
    p_total_amount,
    v_unit_price,
    v_created_at
  );

  -- 12. Fetch user name for response
  SELECT full_name INTO v_user_name FROM public.profiles WHERE id = v_user_id;

  -- 13. If item entered low-stock territory, generate deduplicated notification for all active Staff and Admin users
  IF v_entered_low_stock THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE related_id = p_inventory_id
        AND type = 'low_stock'
        AND is_read = false
    ) THEN
      FOR v_admin_recipient IN
        SELECT id FROM public.profiles
        WHERE role IN ('admin', 'staff') AND is_active = true
      LOOP
        INSERT INTO public.notifications (
          user_id,
          title,
          message,
          type,
          related_id,
          created_at
        ) VALUES (
          v_admin_recipient.id,
          'Low Stock Alert: ' || v_item_name,
          'Item "' || v_item_name || '" has fallen to ' || v_new_stock::text || ' ' || COALESCE(v_unit, 'units') ||
            ' (minimum required: ' || v_min_stock::text || ' ' || COALESCE(v_unit, 'units') || '). Restock recommended.',
          'low_stock',
          p_inventory_id,
          v_created_at
        );
      END LOOP;
    END IF;
  END IF;

  -- 14. Return structured JSON supporting both flat keys and nested 'transaction' object
  RETURN jsonb_build_object(
    'success', true,
    'current_stock', v_new_stock,
    'stock_before', v_current_stock,
    'transaction_id', v_transaction_id,
    'inventory_id', p_inventory_id,
    'item_name', v_item_name,
    'transaction_type', p_transaction_type,
    'quantity', p_quantity,
    'reason', p_reason,
    'remarks', v_final_remarks,
    'performed_by', v_user_name,
    'patient_id', v_final_patient_id,
    'patient_name', v_patient_name,
    'patient_number', v_patient_number,
    'vendor_id', p_vendor_id,
    'total_amount', p_total_amount,
    'unit_price', v_unit_price,
    'created_at', v_created_at,
    'transaction', jsonb_build_object(
      'id', v_transaction_id,
      'inventory_id', p_inventory_id,
      'transaction_type', p_transaction_type,
      'quantity', p_quantity,
      'stock_before', v_current_stock,
      'stock_after', v_new_stock,
      'reason', p_reason,
      'remarks', v_final_remarks,
      'performed_by', v_user_id,
      'performed_by_name', v_user_name,
      'patient_id', v_final_patient_id,
      'patient_name', v_patient_name,
      'patient_number', v_patient_number,
      'vendor_id', p_vendor_id,
      'total_amount', p_total_amount,
      'unit_price', v_unit_price,
      'created_at', v_created_at
    )
  );
END;
$$;

-- 3. Grant execute permissions
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID) TO service_role;
