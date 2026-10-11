-- ============================================================
-- MKES CARE+ — SPRINT 5.1: DENTAL LAB TRACKING MIGRATION
-- ============================================================
-- HOW TO APPLY:
-- 1. Open Supabase Dashboard: SQL Editor -> "New query"
-- 2. Paste this entire file and click "Run"
-- Safe and idempotent to run multiple times.
-- ============================================================

-- 1. Ensure public.dental_lab table exists with all required columns
CREATE TABLE IF NOT EXISTS public.dental_lab (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id      UUID REFERENCES public.patients(id) ON DELETE RESTRICT,
  case_number     TEXT NOT NULL,
  case_type       TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'processing',
  sent_date       DATE NOT NULL DEFAULT CURRENT_DATE,
  ready_date      DATE,
  delivered_date  DATE,
  remarks         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ensure unique constraint on case_number
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'dental_lab_case_number_key'
      AND conrelid = 'public.dental_lab'::regclass
  ) THEN
    ALTER TABLE public.dental_lab ADD CONSTRAINT dental_lab_case_number_key UNIQUE (case_number);
  END IF;
END $$;

-- Ensure check constraint on status: only 'processing', 'ready', 'delivered'
ALTER TABLE public.dental_lab DROP CONSTRAINT IF EXISTS dental_lab_status_check;
ALTER TABLE public.dental_lab
  ADD CONSTRAINT dental_lab_status_check
  CHECK (status IN ('processing', 'ready', 'delivered'));

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_dental_lab_patient_id ON public.dental_lab(patient_id);
CREATE INDEX IF NOT EXISTS idx_dental_lab_status ON public.dental_lab(status);
CREATE INDEX IF NOT EXISTS idx_dental_lab_sent_date ON public.dental_lab(sent_date DESC);
CREATE INDEX IF NOT EXISTS idx_dental_lab_created_at ON public.dental_lab(created_at DESC);

-- ============================================================
-- 2. STATUS & DATES TRIGGER
-- ============================================================
-- Automatically sets ready_date when status moves to 'ready',
-- and delivered_date when status moves to 'delivered',
-- while preventing created_at mutations.
CREATE OR REPLACE FUNCTION public.handle_dental_lab_status_dates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Prevent modification of created_at
  NEW.created_at := OLD.created_at;

  -- Auto-populate ready_date if not explicitly provided
  IF NEW.status = 'ready' AND NEW.ready_date IS NULL THEN
    NEW.ready_date := CURRENT_DATE;
  END IF;

  -- Auto-populate delivered_date if not explicitly provided
  IF NEW.status = 'delivered' THEN
    IF NEW.delivered_date IS NULL THEN
      NEW.delivered_date := CURRENT_DATE;
    END IF;
    -- Also ensure ready_date is not null when delivered
    IF NEW.ready_date IS NULL THEN
      NEW.ready_date := COALESCE(OLD.ready_date, NEW.sent_date);
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dental_lab_status_dates ON public.dental_lab;
CREATE TRIGGER trg_dental_lab_status_dates
BEFORE UPDATE ON public.dental_lab
FOR EACH ROW EXECUTE FUNCTION public.handle_dental_lab_status_dates();

-- Also ensure updated_at trigger exists for basic updates
DROP TRIGGER IF EXISTS dental_lab_updated_at ON public.dental_lab;
CREATE TRIGGER dental_lab_updated_at
BEFORE UPDATE ON public.dental_lab
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 3. RLS POLICIES (Admin + Staff Full Parity)
-- ============================================================
ALTER TABLE public.dental_lab ENABLE ROW LEVEL SECURITY;

-- Set replica identity to full so Realtime changes broadcast full row data
ALTER TABLE public.dental_lab REPLICA IDENTITY FULL;

-- Drop old policies to avoid duplicates
DROP POLICY IF EXISTS "Admins can manage dental lab" ON public.dental_lab;
DROP POLICY IF EXISTS "Authenticated users can view dental lab" ON public.dental_lab;
DROP POLICY IF EXISTS "Admins and Staff have full access to dental lab" ON public.dental_lab;

-- 1. All authenticated users (Admin, Staff, Clinical Doctors) can view dental lab cases
CREATE POLICY "Authenticated users can view dental lab" ON public.dental_lab
  FOR SELECT TO authenticated
  USING (true);

-- 2. Active Admins and Staff have full INSERT, UPDATE, DELETE permissions
CREATE POLICY "Admins and Staff have full access to dental lab" ON public.dental_lab
  FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

-- ============================================================
-- 4. GRANTS
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.dental_lab TO authenticated;
GRANT ALL ON TABLE public.dental_lab TO service_role;

-- ============================================================
-- 5. REALTIME PUBLICATION
-- ============================================================
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dental_lab;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END;
$$;
