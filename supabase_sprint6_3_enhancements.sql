-- ============================================================================
-- MKES CARE+ Sprint 6: Inventory & Vendor Enhancements
-- (Last Supplied Vendor, Phone, Total Payment, & Auto Price Per Piece)
-- ============================================================================

-- 1. Vendors Table: Add total payment amount for latest supply/purchase
ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS last_total_amount NUMERIC(12,2);

-- 2. Inventory Table: Add vendor association and latest restock pricing columns
ALTER TABLE public.inventory
  ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS last_quantity_supplied NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS last_total_amount NUMERIC(12,2);

CREATE INDEX IF NOT EXISTS idx_inventory_vendor_id
  ON public.inventory(vendor_id);

-- 3. Inventory Transactions Table: Add vendor and financial auditing columns
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC(12,2);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_vendor_id
  ON public.inventory_transactions(vendor_id);

-- 4. Update Atomic Stock Operation RPC Function to Support Restock & Supplier Delivery Pricing
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID);

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
  v_current_stock      NUMERIC(12,2);
  v_new_stock          NUMERIC(12,2);
  v_min_stock          NUMERIC(12,2);
  v_item_name          TEXT;
  v_unit               TEXT;
  v_transaction_id     UUID;
  v_created_at         TIMESTAMPTZ;
  v_user_name          TEXT;
  v_entered_low_stock  BOOLEAN := false;
  v_final_patient_id   UUID := NULL;
  v_patient_name       TEXT := NULL;
  v_patient_number     TEXT := NULL;
  v_unit_price         NUMERIC(12,2) := NULL;
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

  -- 6. Lock inventory row with SELECT FOR UPDATE to prevent race conditions
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

  ELSIF p_transaction_type = 'stock_out' THEN
    IF v_current_stock < p_quantity THEN
      RAISE EXCEPTION 'Insufficient stock. Available: %, Requested: %', v_current_stock, p_quantity;
    END IF;
    v_new_stock := v_current_stock - p_quantity;

    -- Check if item entered low-stock territory
    IF v_min_stock IS NOT NULL AND v_min_stock > 0 THEN
      IF v_current_stock > v_min_stock AND v_new_stock <= v_min_stock THEN
        v_entered_low_stock := true;
      END IF;
    END IF;
  END IF;

  -- 8. Update inventory item quantity and optionally latest restock info
  UPDATE public.inventory
    SET quantity = v_new_stock,
        vendor_id = COALESCE(p_vendor_id, inventory.vendor_id),
        last_quantity_supplied = CASE WHEN p_transaction_type = 'stock_in' THEN p_quantity ELSE inventory.last_quantity_supplied END,
        last_total_amount = CASE WHEN p_transaction_type = 'stock_in' AND p_total_amount IS NOT NULL THEN p_total_amount ELSE inventory.last_total_amount END,
        price = CASE WHEN v_unit_price IS NOT NULL THEN v_unit_price ELSE inventory.price END,
        updated_at = now()
    WHERE id = p_inventory_id;

  -- 9. If vendor is provided for stock_in, update vendor's latest delivery info
  IF p_transaction_type = 'stock_in' AND p_vendor_id IS NOT NULL THEN
    UPDATE public.vendors
      SET last_quantity = p_quantity,
          last_total_amount = COALESCE(p_total_amount, vendors.last_total_amount),
          last_delivery_date = CURRENT_DATE,
          updated_at = now()
      WHERE id = p_vendor_id;
  END IF;

  -- 10. Insert audit transaction
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
    p_remarks,
    v_user_id,
    v_user_id,
    v_final_patient_id,
    p_vendor_id,
    p_total_amount,
    v_unit_price,
    v_created_at
  );

  -- 11. Fetch user name for response
  SELECT full_name INTO v_user_name FROM public.profiles WHERE id = v_user_id;

  -- 12. If item entered low-stock territory, generate alert notification
  IF v_entered_low_stock THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE related_id = p_inventory_id
        AND type = 'low_stock'
        AND is_read = false
    ) THEN
      INSERT INTO public.notifications (user_id, title, message, type, related_id, created_at)
      SELECT p.id,
             'Low Stock Alert: ' || v_item_name,
             v_item_name || ' stock dropped to ' || v_new_stock || ' ' || COALESCE(v_unit, 'units') || ' (Minimum: ' || v_min_stock || ').',
             'low_stock',
             p_inventory_id,
             v_created_at
      FROM public.profiles p
      WHERE p.role IN ('admin', 'staff');
    END IF;
  END IF;

  -- 13. Return structured JSON matching Dart model expectations
  RETURN jsonb_build_object(
    'success', true,
    'current_stock', v_new_stock,
    'stock_before', v_current_stock,
    'transaction', jsonb_build_object(
      'id', v_transaction_id,
      'inventory_id', p_inventory_id,
      'transaction_type', p_transaction_type,
      'quantity', p_quantity,
      'stock_before', v_current_stock,
      'stock_after', v_new_stock,
      'reason', p_reason,
      'remarks', p_remarks,
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

-- 5. Grant permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID, NUMERIC, UUID) TO service_role;
