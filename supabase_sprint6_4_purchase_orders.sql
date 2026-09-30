-- ============================================================================
-- MKES CARE+ Sprint 6.4 Migration: Purchase Orders, Receiving & Vendor History
-- ============================================================================
-- Safe and idempotent migration for:
-- 1. public.purchase_orders table
-- 2. public.purchase_order_items table
-- 3. public.inventory_transactions purchase_order_id link
-- 4. RLS policies with Admin == Staff parity
-- 5. Atomic receive_purchase_order RPC function with full rollback guarantee
-- ============================================================================

-- 1. Ensure public.is_admin_or_staff helper exists
CREATE OR REPLACE FUNCTION public.is_admin_or_staff()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('admin', 'staff')
      AND is_active = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_admin_or_staff() TO authenticated;

-- ============================================================================
-- 2. CREATE TABLE public.purchase_orders
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_number   TEXT            NOT NULL,
  vendor_id               UUID            NOT NULL REFERENCES public.vendors(id) ON DELETE RESTRICT,
  order_date              DATE            NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery_date  DATE,
  actual_delivery_date    DATE,
  status                  TEXT            NOT NULL DEFAULT 'draft',
  subtotal                NUMERIC(12,2)   NOT NULL DEFAULT 0.00,
  total_amount            NUMERIC(12,2)   NOT NULL DEFAULT 0.00,
  notes                   TEXT,
  created_by              UUID            REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Unique constraint on purchase_order_number
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'purchase_orders_number_unique'
  ) THEN
    ALTER TABLE public.purchase_orders
      ADD CONSTRAINT purchase_orders_number_unique UNIQUE (purchase_order_number);
  END IF;
END $$;

-- Status constraint
ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_status_check;
ALTER TABLE public.purchase_orders
  ADD CONSTRAINT purchase_orders_status_check
  CHECK (status IN ('draft', 'ordered', 'partially_received', 'received', 'cancelled'));

-- Expected delivery date constraint (expected_delivery_date must be >= order_date if provided)
ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_expected_delivery_date_check;
ALTER TABLE public.purchase_orders
  ADD CONSTRAINT purchase_orders_expected_delivery_date_check
  CHECK (expected_delivery_date IS NULL OR expected_delivery_date >= order_date);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_purchase_orders_vendor_id ON public.purchase_orders(vendor_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_order_date ON public.purchase_orders(order_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_created_at ON public.purchase_orders(created_at DESC);

-- ============================================================================
-- 3. CREATE TABLE public.purchase_order_items
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id   UUID            NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  inventory_id        UUID            NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
  quantity            NUMERIC(12,2)   NOT NULL CHECK (quantity > 0),
  unit_price          NUMERIC(12,2)   NOT NULL DEFAULT 0.00 CHECK (unit_price >= 0),
  total_amount        NUMERIC(12,2)   NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
  received_quantity   NUMERIC(12,2)   NOT NULL DEFAULT 0.00 CHECK (received_quantity >= 0),
  created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_po_items_po_id ON public.purchase_order_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_items_inventory_id ON public.purchase_order_items(inventory_id);

-- ============================================================================
-- 4. LINK INVENTORY TRANSACTIONS TO PURCHASE ORDERS
-- ============================================================================
ALTER TABLE public.inventory_transactions
  ADD COLUMN IF NOT EXISTS purchase_order_id UUID REFERENCES public.purchase_orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_po_id
  ON public.inventory_transactions(purchase_order_id);

-- ============================================================================
-- 5. ROW LEVEL SECURITY (RLS) FOR PURCHASE ORDERS & ITEMS
-- ============================================================================
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

-- Clean up existing policies
DROP POLICY IF EXISTS "Authenticated users can view purchase orders" ON public.purchase_orders;
DROP POLICY IF EXISTS "Admin and Staff can manage purchase orders" ON public.purchase_orders;
DROP POLICY IF EXISTS "Authenticated users can view purchase order items" ON public.purchase_order_items;
DROP POLICY IF EXISTS "Admin and Staff can manage purchase order items" ON public.purchase_order_items;

-- 5.1 purchase_orders RLS
CREATE POLICY "Authenticated users can view purchase orders" ON public.purchase_orders
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admin and Staff can manage purchase orders" ON public.purchase_orders
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- 5.2 purchase_order_items RLS
CREATE POLICY "Authenticated users can view purchase order items" ON public.purchase_order_items
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admin and Staff can manage purchase order items" ON public.purchase_order_items
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_orders TO authenticated;
GRANT ALL ON TABLE public.purchase_orders TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_order_items TO authenticated;
GRANT ALL ON TABLE public.purchase_order_items TO service_role;

-- ============================================================================
-- 6. ATOMIC PURCHASE ORDER RECEIVING RPC FUNCTION
-- ============================================================================
-- Receives quantities for items in a PO, atomically:
-- - Validates PO status (ordered or partially_received)
-- - Validates quantities (cannot receive more than remaining)
-- - Updates purchase_order_items.received_quantity
-- - Increases inventory.quantity (stock)
-- - Logs stock_in record in inventory_transactions
-- - Updates inventory vendor & pricing data (last_quantity_supplied, price, etc.)
-- - Updates vendor latest delivery info
-- - Updates purchase_orders status (partially_received or received)
-- - If any check fails, rolls back completely.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.receive_purchase_order(
  p_purchase_order_id UUID,
  p_items             JSONB -- Array of {"item_id": UUID, "receive_quantity": NUMERIC}
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id                 UUID;
  v_po                      RECORD;
  v_item_elem               JSONB;
  v_po_item_id              UUID;
  v_receive_qty             NUMERIC(12,2);
  v_po_item                 RECORD;
  v_new_received_qty        NUMERIC(12,2);
  v_inv_stock               NUMERIC(12,2);
  v_inv_new_stock           NUMERIC(12,2);
  v_inv_min_stock           NUMERIC(12,2);
  v_item_total_amount       NUMERIC(12,2);
  v_total_batch_qty         NUMERIC(12,2) := 0.00;
  v_total_batch_amount      NUMERIC(12,2) := 0.00;
  v_all_fully_received      BOOLEAN := true;
  v_any_items_received      BOOLEAN := false;
  v_new_po_status           TEXT;
  v_actual_delivery_date    DATE;
BEGIN
  -- 1. Check authenticated user and role
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to receive purchase orders.';
  END IF;

  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Only Admin and Staff can receive purchase orders.';
  END IF;

  -- 2. Lock and validate purchase order
  SELECT *
    INTO v_po
    FROM public.purchase_orders
    WHERE id = p_purchase_order_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase order not found.';
  END IF;

  IF v_po.status = 'draft' THEN
    RAISE EXCEPTION 'Cannot receive a draft purchase order. Please mark it as Ordered first.';
  END IF;

  IF v_po.status = 'cancelled' THEN
    RAISE EXCEPTION 'Cannot receive a cancelled purchase order.';
  END IF;

  IF v_po.status = 'received' THEN
    RAISE EXCEPTION 'Purchase order has already been fully received.';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items provided for receiving.';
  END IF;

  -- 3. Process each item in the batch
  FOR v_item_elem IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_po_item_id := (v_item_elem->>'item_id')::UUID;
    v_receive_qty := (v_item_elem->>'receive_quantity')::NUMERIC;

    -- Skip if receive quantity is 0 or negative
    IF v_receive_qty IS NULL OR v_receive_qty <= 0 THEN
      CONTINUE;
    END IF;

    -- Lock and validate purchase order item
    SELECT *
      INTO v_po_item
      FROM public.purchase_order_items
      WHERE id = v_po_item_id
        AND purchase_order_id = p_purchase_order_id
      FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Purchase order line item not found for ID: %', v_po_item_id;
    END IF;

    v_new_received_qty := v_po_item.received_quantity + v_receive_qty;
    IF v_new_received_qty > v_po_item.quantity THEN
      RAISE EXCEPTION 'Cannot receive % for item %. Remaining allowed: %',
        v_receive_qty, v_po_item_id, (v_po_item.quantity - v_po_item.received_quantity);
    END IF;

    -- Update line item received quantity
    UPDATE public.purchase_order_items
      SET received_quantity = v_new_received_qty,
          updated_at = now()
      WHERE id = v_po_item.id;

    -- Lock inventory item and compute new stock
    SELECT quantity, minimum_stock
      INTO v_inv_stock, v_inv_min_stock
      FROM public.inventory
      WHERE id = v_po_item.inventory_id
      FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Inventory item not found for ID: %', v_po_item.inventory_id;
    END IF;

    v_inv_new_stock := v_inv_stock + v_receive_qty;
    v_item_total_amount := ROUND(v_receive_qty * v_po_item.unit_price, 2);

    -- If stock rose above minimum, clear low_stock alerts
    IF v_inv_min_stock IS NOT NULL AND v_inv_stock <= v_inv_min_stock AND v_inv_new_stock > v_inv_min_stock THEN
      UPDATE public.notifications
        SET is_read = true
        WHERE related_id = v_po_item.inventory_id
          AND type = 'low_stock'
          AND is_read = false;
    END IF;

    -- Update inventory item with new stock, latest supplier and pricing info
    UPDATE public.inventory
      SET quantity = v_inv_new_stock,
          vendor_id = v_po.vendor_id,
          last_quantity_supplied = v_receive_qty,
          last_total_amount = v_item_total_amount,
          price = CASE WHEN v_po_item.unit_price > 0 THEN v_po_item.unit_price ELSE inventory.price END,
          updated_at = now()
      WHERE id = v_po_item.inventory_id;

    -- Insert stock_in transaction linked to purchase order
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
      vendor_id,
      purchase_order_id,
      total_amount,
      unit_price,
      created_at
    ) VALUES (
      gen_random_uuid(),
      v_po_item.inventory_id,
      'stock_in',
      v_receive_qty,
      v_inv_stock,
      v_inv_new_stock,
      'Purchase Order Delivery',
      'Received against PO #' || v_po.purchase_order_number,
      v_user_id,
      v_user_id,
      v_po.vendor_id,
      v_po.id,
      v_item_total_amount,
      v_po_item.unit_price,
      now()
    );

    v_total_batch_qty := v_total_batch_qty + v_receive_qty;
    v_total_batch_amount := v_total_batch_amount + v_item_total_amount;
    v_any_items_received := true;
  END LOOP;

  IF NOT v_any_items_received THEN
    RAISE EXCEPTION 'No valid positive quantities to receive.';
  END IF;

  -- 4. Check if entire PO is now fully received
  SELECT bool_and(received_quantity >= quantity)
    INTO v_all_fully_received
    FROM public.purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id;

  IF v_all_fully_received THEN
    v_new_po_status := 'received';
    v_actual_delivery_date := CURRENT_DATE;
  ELSE
    v_new_po_status := 'partially_received';
    v_actual_delivery_date := COALESCE(v_po.actual_delivery_date, CURRENT_DATE);
  END IF;

  -- 5. Update purchase order status
  UPDATE public.purchase_orders
    SET status = v_new_po_status,
        actual_delivery_date = v_actual_delivery_date,
        updated_at = now()
    WHERE id = p_purchase_order_id;

  -- 6. Update vendor latest supply record
  UPDATE public.vendors
    SET last_quantity = v_total_batch_qty,
        last_total_amount = v_total_batch_amount,
        last_delivery_date = CURRENT_DATE,
        updated_at = now()
    WHERE id = v_po.vendor_id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_order_id', p_purchase_order_id,
    'status', v_new_po_status,
    'received_items_count', jsonb_array_length(p_items),
    'total_batch_quantity', v_total_batch_qty,
    'total_batch_amount', v_total_batch_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.receive_purchase_order(UUID, JSONB) TO authenticated;
