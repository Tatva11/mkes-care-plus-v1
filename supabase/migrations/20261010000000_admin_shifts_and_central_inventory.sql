-- ============================================================================
-- MKES CARE+ — Admin Shifts and Central Inventory Unification
-- Migration: 20261010000000_admin_shifts_and_central_inventory.sql
-- Description:
--   1. Admin-Controlled Shifts:
--      - Create shift_configurations table with start_time, end_time, grace_period_minutes.
--      - Seed Morning (08:00 - 16:00) and Night (20:00 - 04:00 overnight) shifts.
--      - Add assigned_shift column to profiles table with 'morning' default and check constraint.
--      - Configure RLS: authenticated users can read; only admins can update/insert.
--   2. One Central Inventory Only:
--      - Reconcile any remaining departmental stock allocations back to public.inventory.
--      - Maintain public.inventory as the single authoritative stock balance.
--   3. Eye Surgery Presets:
--      - Ensure eye_surgery_item_templates exists with appropriate RLS and constraints.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SHIFT CONFIGURATIONS & STAFF SHIFT ASSIGNMENT
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.shift_configurations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE CHECK (name IN ('morning', 'night')),
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  grace_period_minutes INT NOT NULL DEFAULT 15,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- Seed Morning & Night shifts if not already present
INSERT INTO public.shift_configurations (name, start_time, end_time, grace_period_minutes)
VALUES
  ('morning', '08:00:00', '16:00:00', 15),
  ('night', '20:00:00', '04:00:00', 15)
ON CONFLICT (name) DO UPDATE
SET updated_at = now();

-- Enable RLS
ALTER TABLE public.shift_configurations ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read shift configurations
DROP POLICY IF EXISTS "shift_configurations_read_authenticated" ON public.shift_configurations;
CREATE POLICY "shift_configurations_read_authenticated"
  ON public.shift_configurations
  FOR SELECT
  TO authenticated
  USING (true);

-- Restrict insert/update/delete to Admins
DROP POLICY IF EXISTS "shift_configurations_admin_write" ON public.shift_configurations;
CREATE POLICY "shift_configurations_admin_write"
  ON public.shift_configurations
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

-- Add assigned_shift column to profiles table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'assigned_shift'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN assigned_shift TEXT NOT NULL DEFAULT 'morning';
  END IF;

  -- Add check constraint for supported shifts
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_assigned_shift_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_assigned_shift_check
      CHECK (assigned_shift IN ('morning', 'night'));
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. ONE CENTRAL INVENTORY ONLY (SAFE RECONCILIATION)
-- ----------------------------------------------------------------------------

-- Reconcile any remaining balances from department_inventory back into public.inventory
DO $$
DECLARE
  v_dept_col TEXT := NULL;
  v_inv_col TEXT := NULL;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'department_inventory'
  ) THEN
    -- Detect quantity column on department_inventory
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'department_inventory' AND column_name = 'quantity'
    ) THEN
      v_dept_col := 'quantity';
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'department_inventory' AND column_name = 'allocated_quantity'
    ) THEN
      v_dept_col := 'allocated_quantity';
    END IF;

    -- Detect quantity column on inventory
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'inventory' AND column_name = 'quantity'
    ) THEN
      v_inv_col := 'quantity';
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'inventory' AND column_name = 'current_stock'
    ) THEN
      v_inv_col := 'current_stock';
    END IF;

    IF v_dept_col IS NOT NULL AND v_inv_col IS NOT NULL THEN
      -- Reconcile any remaining positive balance into central inventory
      EXECUTE format('
        UPDATE public.inventory i
        SET %I = i.%I + COALESCE(sub.allocated_sum, 0)
        FROM (
          SELECT inventory_id, SUM(%I) AS allocated_sum
          FROM public.department_inventory
          WHERE %I > 0
          GROUP BY inventory_id
        ) sub
        WHERE i.id = sub.inventory_id
      ', v_inv_col, v_inv_col, v_dept_col, v_dept_col);

      -- Reset department_inventory quantities to 0 to prevent parallel balances
      EXECUTE format('
        UPDATE public.department_inventory
        SET %I = 0
        WHERE %I > 0
      ', v_dept_col, v_dept_col);
    END IF;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. EYE SURGERY INVENTORY PRESETS (TEMPLATES)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.eye_surgery_item_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  surgery_type TEXT NOT NULL,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
  default_quantity NUMERIC(10, 2) NOT NULL DEFAULT 1.0 CHECK (default_quantity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT eye_surgery_item_templates_unique UNIQUE (surgery_type, inventory_item_id)
);

-- Enable RLS
ALTER TABLE public.eye_surgery_item_templates ENABLE ROW LEVEL SECURITY;

-- Read policy: all authenticated users
DROP POLICY IF EXISTS "eye_surgery_item_templates_read" ON public.eye_surgery_item_templates;
CREATE POLICY "eye_surgery_item_templates_read"
  ON public.eye_surgery_item_templates
  FOR SELECT
  TO authenticated
  USING (true);

-- Write policy: Admins only
DROP POLICY IF EXISTS "eye_surgery_item_templates_admin_write" ON public.eye_surgery_item_templates;
CREATE POLICY "eye_surgery_item_templates_admin_write"
  ON public.eye_surgery_item_templates
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );
