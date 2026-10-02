-- ============================================================================
-- MKES CARE+ Sprint 6.3: Vendor Management CRUD Schema & RLS
-- Authoritative Sprint Reference: Sprint 6.3 — Vendor Management CRUD
-- ============================================================================

-- 1. Create Vendors Table if not exists
CREATE TABLE IF NOT EXISTS public.vendors (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                TEXT NOT NULL,
  contact_person      TEXT,
  phone               TEXT,
  email               TEXT,
  address             TEXT,
  products_supplied   TEXT[] DEFAULT '{}'::TEXT[],
  last_order_date     DATE,
  last_delivery_date  DATE,
  last_quantity       NUMERIC(12,2),
  remarks             TEXT,
  is_active           BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Alter columns in case table was created from an older minimal migration
ALTER TABLE public.vendors
  ADD COLUMN IF NOT EXISTS contact_person     TEXT,
  ADD COLUMN IF NOT EXISTS phone              TEXT,
  ADD COLUMN IF NOT EXISTS email              TEXT,
  ADD COLUMN IF NOT EXISTS address            TEXT,
  ADD COLUMN IF NOT EXISTS products_supplied  TEXT[] DEFAULT '{}'::TEXT[],
  ADD COLUMN IF NOT EXISTS last_order_date    DATE,
  ADD COLUMN IF NOT EXISTS last_delivery_date DATE,
  ADD COLUMN IF NOT EXISTS last_quantity      NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS remarks            TEXT,
  ADD COLUMN IF NOT EXISTS is_active          BOOLEAN NOT NULL DEFAULT true;

-- 3. Indexes for fast search, filter and audit queries
CREATE INDEX IF NOT EXISTS idx_vendors_name
  ON public.vendors(name);

CREATE INDEX IF NOT EXISTS idx_vendors_contact_person
  ON public.vendors(contact_person);

CREATE INDEX IF NOT EXISTS idx_vendors_phone
  ON public.vendors(phone);

CREATE INDEX IF NOT EXISTS idx_vendors_email
  ON public.vendors(email);

CREATE INDEX IF NOT EXISTS idx_vendors_is_active
  ON public.vendors(is_active);

CREATE INDEX IF NOT EXISTS idx_vendors_created_at
  ON public.vendors(created_at DESC);

-- 4. Automatic updated_at trigger
CREATE OR REPLACE FUNCTION public.set_vendors_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at
  BEFORE UPDATE ON public.vendors
  FOR EACH ROW
  EXECUTE FUNCTION public.set_vendors_updated_at();

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors REPLICA IDENTITY FULL;

-- 6. RLS Policies
-- Drop existing policies to prevent conflicts
DROP POLICY IF EXISTS "Admins have full access to vendors" ON public.vendors;
DROP POLICY IF EXISTS "Admins can manage vendors" ON public.vendors;
DROP POLICY IF EXISTS "Authenticated users can view vendors" ON public.vendors;

-- Admin: full vendor CRUD
CREATE POLICY "Admins have full access to vendors" ON public.vendors
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Staff: read/view access only
CREATE POLICY "Authenticated users can view vendors" ON public.vendors
  FOR SELECT TO authenticated
  USING (true);
