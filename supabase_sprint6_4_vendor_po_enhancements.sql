-- ============================================================================
-- MKES CARE+ Sprint 6.4: Vendor Products Supplied & Order Placed By Audit Schema
-- ============================================================================
-- 1. Ensure public.vendors has products_supplied TEXT[]
-- 2. Add ordered_by and ordered_at to public.purchase_orders
-- 3. Add trigger to automatically record ordered_by and ordered_at on transition to 'ordered'
-- 4. Preserve Admin and Staff access parity
-- ============================================================================

-- 1. Ensure vendors products_supplied column exists
ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS products_supplied TEXT[] DEFAULT '{}'::TEXT[];

-- 2. Add ordered_by and ordered_at columns to purchase_orders table
ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS ordered_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ordered_at TIMESTAMPTZ;

-- 3. Performance indexes for audit and ordering queries
CREATE INDEX IF NOT EXISTS idx_purchase_orders_ordered_by
  ON public.purchase_orders(ordered_by);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_ordered_at
  ON public.purchase_orders(ordered_at);

-- 4. Trigger Function: Automatically capture ordered_by and ordered_at server-side upon placement
CREATE OR REPLACE FUNCTION public.handle_purchase_order_placement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Trigger strictly when transitioning to 'ordered'
  -- (either newly inserted with status 'ordered' or updated from 'draft' to 'ordered')
  IF (TG_OP = 'INSERT' AND NEW.status = 'ordered') OR
     (TG_OP = 'UPDATE' AND (OLD.status IS NULL OR OLD.status = 'draft') AND NEW.status = 'ordered') THEN
    IF NEW.ordered_by IS NULL THEN
      NEW.ordered_by := auth.uid();
    END IF;
    IF NEW.ordered_at IS NULL THEN
      NEW.ordered_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_purchase_order_placement ON public.purchase_orders;
CREATE TRIGGER trg_purchase_order_placement
BEFORE INSERT OR UPDATE ON public.purchase_orders
FOR EACH ROW
EXECUTE FUNCTION public.handle_purchase_order_placement();
