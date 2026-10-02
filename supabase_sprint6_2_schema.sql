-- ============================================================
-- MKES CARE+ — Sprint 6.2 Migration: Stock Operations, Low Stock & Expiry
-- ============================================================
-- HOW TO APPLY:
-- 1. Open Supabase Dashboard: https://supabase.com/dashboard/project/mfalgfodhsszyxnfiofi
-- 2. Go to: SQL Editor -> "New query"
-- 3. Paste this entire file and click "Run"
-- Safe and idempotent to run multiple times.
-- ============================================================

-- 1. Ensure inventory_transactions table exists with complete structure
CREATE TABLE IF NOT EXISTS public.inventory_transactions (
  id                UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id      UUID            NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
  transaction_type  TEXT            NOT NULL,
  quantity          NUMERIC(12,2)   NOT NULL,
  stock_before      NUMERIC(12,2),
  stock_after       NUMERIC(12,2),
  reason            TEXT,
  remarks           TEXT,
  performed_by      UUID            REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by        UUID            REFERENCES public.profiles(id) ON DELETE SET NULL,
  reference_id      UUID,
  created_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- 2. Add columns if table already existed from earlier schema
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS stock_before NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS stock_after  NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS reason       TEXT,
  ADD COLUMN IF NOT EXISTS remarks      TEXT,
  ADD COLUMN IF NOT EXISTS performed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS patient_id   UUID REFERENCES public.patients(id) ON DELETE SET NULL;

-- 3. Update check constraint to support stock_in and stock_out alongside existing legacy types
ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;
ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_transaction_type_check CHECK (
    transaction_type IN ('stock_in', 'stock_out', 'purchase', 'sale', 'usage', 'adjustment', 'return')
  );

-- 4. Positive transaction quantity constraint
ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_quantity_check;
ALTER TABLE public.inventory_transactions
  ADD CONSTRAINT inventory_transactions_quantity_check CHECK (quantity > 0);

-- 5. Indexes for fast transaction queries and audit reporting
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_inventory_id
  ON public.inventory_transactions(inventory_id);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_created_at
  ON public.inventory_transactions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_type
  ON public.inventory_transactions(transaction_type);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_performed_by
  ON public.inventory_transactions(performed_by);

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_patient_id
  ON public.inventory_transactions(patient_id);

-- 6. Ensure notifications check constraint supports low_stock and expiry alert types
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN (
      'info',
      'leave_request',
      'leave_approved',
      'leave_rejected',
      'task_assigned',
      'task_updated',
      'task_completed',
      'task_overdue',
      'appointment',
      'system',
      'low_stock',
      'expiry'
    )
  );

-- 7. Enable Row Level Security (RLS) on transactions
ALTER TABLE public.inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transactions REPLICA IDENTITY FULL;

-- Drop old policies to prevent duplicates
DROP POLICY IF EXISTS "Admins have full access to transactions" ON public.inventory_transactions;
DROP POLICY IF EXISTS "Authenticated users can view transactions" ON public.inventory_transactions;
DROP POLICY IF EXISTS "Authenticated staff can insert transactions" ON public.inventory_transactions;

-- Admins can view, insert, update, or delete transactions
CREATE POLICY "Admins have full access to transactions" ON public.inventory_transactions
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Authenticated staff can view transaction history
CREATE POLICY "Authenticated users can view transactions" ON public.inventory_transactions
  FOR SELECT TO authenticated
  USING (true);

-- Authenticated users can insert transactions for their own operations
CREATE POLICY "Authenticated staff can insert transactions" ON public.inventory_transactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.role() = 'authenticated' AND
    (performed_by IS NULL OR performed_by = auth.uid())
  );

-- 8. Atomic Stock Operation RPC Function (Handles locking, validation, patient assignment, update & history)
DROP FUNCTION IF EXISTS public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.perform_stock_operation(
  p_inventory_id      UUID,
  p_transaction_type  TEXT,
  p_quantity          NUMERIC,
  p_reason            TEXT DEFAULT NULL,
  p_remarks           TEXT DEFAULT NULL,
  p_patient_id        UUID DEFAULT NULL
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

  -- 4. Validate patient selection strictly for "Dispensed to Patient"
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
    -- Any other reason or Stock In MUST have NULL patient_id
    v_final_patient_id := NULL;
  END IF;

  -- 5. Lock row with SELECT FOR UPDATE to prevent race conditions
  SELECT quantity, minimum_stock, name, unit
    INTO v_current_stock, v_min_stock, v_item_name, v_unit
    FROM public.inventory
    WHERE id = p_inventory_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item not found.';
  END IF;

  -- 6. Calculate new stock atomically
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

    -- Check if this stock out caused item to enter low-stock state
    IF v_min_stock IS NOT NULL AND v_min_stock > 0 THEN
      IF v_current_stock > v_min_stock AND v_new_stock <= v_min_stock THEN
        v_entered_low_stock := true;
      END IF;
    END IF;
  END IF;

  -- 7. Update inventory quantity
  UPDATE public.inventory
    SET quantity = v_new_stock,
        updated_at = now()
    WHERE id = p_inventory_id;

  -- 8. Insert audit transaction
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
    v_created_at
  );

  -- 9. Fetch user name for response
  SELECT full_name INTO v_user_name FROM public.profiles WHERE id = v_user_id;

  -- 10. If item entered low-stock territory, generate deduplicated notification for all active Staff and Admin users
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
             now()
      FROM public.profiles p
      WHERE p.role IN ('admin', 'staff') AND p.is_active = true;
    END IF;
  END IF;

  -- 11. Return complete JSON object
  RETURN jsonb_build_object(
    'success', true,
    'new_stock', v_new_stock,
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
      'performed_by_name', COALESCE(v_user_name, 'Staff Member'),
      'patient_id', v_final_patient_id,
      'patient_name', v_patient_name,
      'patient_number', v_patient_number,
      'created_at', v_created_at
    )
  );
END;
$$;

-- 9. Table and RPC Grants
GRANT ALL ON TABLE public.inventory_transactions TO authenticated;
GRANT ALL ON TABLE public.inventory_transactions TO service_role;
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.perform_stock_operation(UUID, TEXT, NUMERIC, TEXT, TEXT, UUID) TO service_role;
