-- ============================================================================
-- Migration: 20261011183000_staff_effective_shift_assignments.sql
-- Description: Supports effective-dated shift assignments and scheduled shift changes
--              taking effect from the next day (or explicit future date) without
--              overwriting the staff member's current-day shift or attendance records.
--              Preserves 100% backward compatibility with historical 'afternoon' values
--              while supporting 'evening' across checks.
-- ============================================================================

-- 1. Ensure profiles table supports scheduled future shift and effective date
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS next_shift TEXT,
  ADD COLUMN IF NOT EXISTS shift_effective_date DATE;

-- 2. Update profiles_assigned_shift_check constraint to allow 'morning', 'afternoon', 'evening', 'both'
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND pg_get_constraintdef(oid) LIKE '%assigned_shift%'
  ) LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_assigned_shift_check
  CHECK (assigned_shift IN ('morning', 'afternoon', 'evening', 'both'));

-- 3. Add constraint on next_shift
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND pg_get_constraintdef(oid) LIKE '%next_shift%'
  ) LOOP
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_next_shift_check
  CHECK (next_shift IS NULL OR next_shift IN ('morning', 'afternoon', 'evening', 'both'));

-- 4. Create staff_shift_assignments table for persistent historical and scheduled shift assignment records
CREATE TABLE IF NOT EXISTS public.staff_shift_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shift TEXT NOT NULL CHECK (shift IN ('morning', 'afternoon', 'evening', 'both')),
  effective_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES public.profiles(id),
  CONSTRAINT staff_shift_assignments_staff_effective_date_key UNIQUE (staff_id, effective_date)
);

CREATE INDEX IF NOT EXISTS idx_staff_shift_assignments_staff_date
  ON public.staff_shift_assignments(staff_id, effective_date DESC);

-- Enable RLS on staff_shift_assignments
ALTER TABLE public.staff_shift_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff_shift_assignments_read_authenticated" ON public.staff_shift_assignments;
CREATE POLICY "staff_shift_assignments_read_authenticated"
  ON public.staff_shift_assignments
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "staff_shift_assignments_admin_all" ON public.staff_shift_assignments;
CREATE POLICY "staff_shift_assignments_admin_all"
  ON public.staff_shift_assignments
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
  );

-- 5. Helper function to resolve effective shift for a given date in clinic timezone
CREATE OR REPLACE FUNCTION public.get_staff_effective_shift(
  p_staff_id UUID,
  p_target_date DATE DEFAULT (CURRENT_DATE AT TIME ZONE 'Asia/Kolkata')::DATE
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_assigned TEXT;
  v_next TEXT;
  v_eff_date DATE;
BEGIN
  SELECT assigned_shift, next_shift, shift_effective_date
  INTO v_assigned, v_next, v_eff_date
  FROM public.profiles
  WHERE id = p_staff_id;

  IF NOT FOUND THEN
    RETURN 'morning';
  END IF;

  IF v_next IS NOT NULL AND v_eff_date IS NOT NULL AND p_target_date >= v_eff_date THEN
    RETURN v_next;
  END IF;

  RETURN COALESCE(v_assigned, 'morning');
END;
$$;
