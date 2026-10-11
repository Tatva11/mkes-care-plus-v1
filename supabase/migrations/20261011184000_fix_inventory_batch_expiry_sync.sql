-- ============================================================================
-- Migration: 20261011184000_fix_inventory_batch_expiry_sync.sql
-- Description: Fixes the inventory earliest expiry calculation bug where receiving
--              new batches/consignments with future expiry dates (e.g. 12 October 2027)
--              failed to update inventory.expiry_date because of a stale earlier/expired date.
--              Also provides an idempotent data repair for existing records without modifying
--              stock balances or legitimate transaction history.
-- ============================================================================

-- 1. Helper function to recompute an item's earliest active expiry date
CREATE OR REPLACE FUNCTION public.recalculate_inventory_expiry(p_inventory_id UUID)
RETURNS DATE
LANGUAGE plpgsql
AS $$
DECLARE
  v_new_expiry DATE;
BEGIN
  -- 1a. Prioritize active remaining batches that have NOT expired (expiry_date >= CURRENT_DATE)
  SELECT MIN(b.expiry_date)
  INTO v_new_expiry
  FROM public.inventory_batches b
  WHERE b.inventory_id = p_inventory_id
    AND b.remaining_quantity > 0
    AND b.expiry_date IS NOT NULL
    AND b.expiry_date >= CURRENT_DATE;

  -- 1b. If all active remaining batches are in the past, take the earliest remaining batch
  IF v_new_expiry IS NULL THEN
    SELECT MIN(b.expiry_date)
    INTO v_new_expiry
    FROM public.inventory_batches b
    WHERE b.inventory_id = p_inventory_id
      AND b.remaining_quantity > 0
      AND b.expiry_date IS NOT NULL;
  END IF;

  RETURN v_new_expiry;
END;
$$;

-- 2. Repair existing inventory records whose expiry_date was frozen to a stale expired date
UPDATE public.inventory inv
SET expiry_date = COALESCE(
      public.recalculate_inventory_expiry(inv.id),
      inv.expiry_date
    ),
    updated_at = now()
WHERE EXISTS (
  SELECT 1
  FROM public.inventory_batches b
  WHERE b.inventory_id = inv.id
    AND b.remaining_quantity > 0
    AND b.expiry_date IS NOT NULL
    AND (
      -- Has an active valid future batch while inventory.expiry_date was in the past
      (inv.expiry_date < CURRENT_DATE AND b.expiry_date >= CURRENT_DATE)
      OR
      -- Or the stored expiry_date does not match any active batch
      (inv.expiry_date <> b.expiry_date AND b.expiry_date = public.recalculate_inventory_expiry(inv.id))
    )
);

-- 3. Trigger on inventory_batches to keep inventory.expiry_date automatically synchronized
CREATE OR REPLACE FUNCTION public.sync_inventory_batch_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_inv_id UUID;
  v_resolved_expiry DATE;
BEGIN
  v_inv_id := COALESCE(NEW.inventory_id, OLD.inventory_id);
  v_resolved_expiry := public.recalculate_inventory_expiry(v_inv_id);

  IF v_resolved_expiry IS NOT NULL THEN
    UPDATE public.inventory
    SET expiry_date = v_resolved_expiry,
        updated_at = now()
    WHERE id = v_inv_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_inventory_batch_expiry ON public.inventory_batches;
CREATE TRIGGER trg_sync_inventory_batch_expiry
  AFTER INSERT OR UPDATE OF remaining_quantity, expiry_date OR DELETE
  ON public.inventory_batches
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_inventory_batch_expiry();
