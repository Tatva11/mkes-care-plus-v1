  -- ============================================================
  -- MKES CARE+ — Sprint 6.1 Migration: Inventory Foundation & CRUD
  -- ============================================================
  -- HOW TO APPLY:
  -- 1. Open Supabase Dashboard: https://supabase.com/dashboard/project/mfalgfodhsszyxnfiofi
  -- 2. Go to: SQL Editor -> "New query"
  -- 3. Paste this entire file and click "Run"
  -- Safe and idempotent to run multiple times.
  -- ============================================================

  -- 1. Ensure table exists with complete columns
  CREATE TABLE IF NOT EXISTS public.inventory (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT            NOT NULL,
    category        TEXT            NOT NULL,
    department      TEXT,
    sku             TEXT,
    description     TEXT,
    quantity        NUMERIC(12,2)   NOT NULL DEFAULT 0,
    minimum_stock   NUMERIC(12,2)   NOT NULL DEFAULT 0,
    unit            TEXT            NOT NULL DEFAULT 'units',
    expiry_date     DATE,
    brand           TEXT,
    vendor_id       UUID,
    price           NUMERIC(12,2),
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
  );

  -- 2. Add columns if table already existed from earlier schema
  ALTER TABLE public.inventory
    ADD COLUMN IF NOT EXISTS description   TEXT,
    ADD COLUMN IF NOT EXISTS sku           TEXT,
    ADD COLUMN IF NOT EXISTS department    TEXT,
    ADD COLUMN IF NOT EXISTS minimum_stock NUMERIC(12,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS unit          TEXT DEFAULT 'units',
    ADD COLUMN IF NOT EXISTS expiry_date   DATE,
    ADD COLUMN IF NOT EXISTS brand         TEXT,
    ADD COLUMN IF NOT EXISTS vendor_id     UUID,
    ADD COLUMN IF NOT EXISTS price         NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS is_active     BOOLEAN DEFAULT true,
    ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ DEFAULT now();

  -- Ensure department check constraint allows standard clinic departments
  ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_department_check;
  ALTER TABLE public.inventory
    ADD CONSTRAINT inventory_department_check CHECK (
      department IS NULL OR department IN ('eye', 'dental', 'optical', 'general')
    );

  -- Ensure non-negative stock constraint
  ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_quantity_check;
  ALTER TABLE public.inventory
    ADD CONSTRAINT inventory_quantity_check CHECK (quantity >= 0);

  -- 3. Indexes for high-performance searching and filtering
  CREATE INDEX IF NOT EXISTS idx_inventory_category
    ON public.inventory(category);

  CREATE INDEX IF NOT EXISTS idx_inventory_name
    ON public.inventory(name);

  CREATE INDEX IF NOT EXISTS idx_inventory_quantity
    ON public.inventory(quantity);

  CREATE INDEX IF NOT EXISTS idx_inventory_department
    ON public.inventory(department);

  CREATE INDEX IF NOT EXISTS idx_inventory_created_at
    ON public.inventory(created_at DESC);

  -- 4. Automatic updated_at trigger
  CREATE OR REPLACE FUNCTION public.set_updated_at()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at = now();
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS trigger_inventory_updated_at ON public.inventory;
  CREATE TRIGGER trigger_inventory_updated_at
    BEFORE UPDATE ON public.inventory
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

  -- 5. Enable Row Level Security (RLS)
  ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

  -- Set replica identity to full for Supabase realtime
  ALTER TABLE public.inventory REPLICA IDENTITY FULL;

  -- 6. RLS Policies
  -- Drop existing policies to prevent conflicts
  DROP POLICY IF EXISTS "Admins can manage inventory" ON public.inventory;
  DROP POLICY IF EXISTS "Admins have full access to inventory" ON public.inventory;
  DROP POLICY IF EXISTS "Authenticated users can view inventory" ON public.inventory;

  -- Admins can create, read, update, and delete all inventory records
  CREATE POLICY "Admins have full access to inventory" ON public.inventory
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

  -- Authenticated staff can view inventory
  CREATE POLICY "Authenticated users can view inventory" ON public.inventory
    FOR SELECT TO authenticated
    USING (true);

  -- 7. Table Grants
  GRANT ALL ON TABLE public.inventory TO authenticated;
  GRANT ALL ON TABLE public.inventory TO service_role;
