-- ============================================================
-- MKES CARE+ - SPRINT 5.2 PATCH: EYE SURGERY APPOINTMENT REMOVAL
-- ============================================================
-- Safe/idempotent migration to remove Eye Surgery appointment linking.
-- Does NOT modify public.appointments or its RLS/indexes.
--
-- Changes:
-- 1. Drop the appointment validation trigger on eye_surgeries
-- 2. Drop the appointment validation function
-- 3. Drop the appointment_id index on eye_surgeries
-- 4. Make appointment_id nullable and drop the FK (if not already)
-- 5. Set all existing appointment_id values to NULL

-- 1. Drop appointment validation trigger
DROP TRIGGER IF EXISTS trg_validate_eye_surgery_appointment ON public.eye_surgeries;

-- 2. Drop appointment validation function
DROP FUNCTION IF EXISTS public.validate_eye_surgery_appointment();

-- 3. Drop appointment_id index on eye_surgeries
DROP INDEX IF EXISTS public.idx_eye_surgeries_appointment_id;

-- 4. Drop the FK constraint on appointment_id
-- The constraint name may vary; try the most common patterns.
DO $$
BEGIN
  -- Try dropping by the standard auto-generated name
  ALTER TABLE public.eye_surgeries
    DROP CONSTRAINT IF EXISTS eye_surgeries_appointment_id_fkey;
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

-- 5. Null out existing appointment links so the column can be dropped later
UPDATE public.eye_surgeries
SET appointment_id = NULL
WHERE appointment_id IS NOT NULL;

-- 6. Remove the locked-fields check for appointment_id changes.
-- Re-create the validate_eye_surgery_locked_fields function WITHOUT
-- the appointment_id check.
CREATE OR REPLACE FUNCTION public.validate_eye_surgery_locked_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_consumed_at TIMESTAMPTZ;
BEGIN
  SELECT consumed_at INTO v_consumed_at
  FROM public.eye_surgery_inventory_consumptions
  WHERE eye_surgery_id = OLD.id;

  IF NEW.inventory_consumed_at IS DISTINCT FROM OLD.inventory_consumed_at
    AND NEW.inventory_consumed_at IS NOT NULL
    AND v_consumed_at IS NULL THEN
    RAISE EXCEPTION 'Inventory consumption can only be recorded by the stock RPC';
  END IF;

  IF v_consumed_at IS NOT NULL THEN
    NEW.inventory_consumed_at := v_consumed_at;
  END IF;

  IF v_consumed_at IS NOT NULL AND (
    NEW.patient_id IS DISTINCT FROM OLD.patient_id
    OR NEW.surgery_type IS DISTINCT FROM OLD.surgery_type
    OR NEW.surgery_type_category IS DISTINCT FROM OLD.surgery_type_category
    OR NEW.custom_surgery_type IS DISTINCT FROM OLD.custom_surgery_type
    OR NEW.eye_side IS DISTINCT FROM OLD.eye_side
    OR NEW.assigned_staff_id IS DISTINCT FROM OLD.assigned_staff_id
    OR NEW.pre_op_date IS DISTINCT FROM OLD.pre_op_date
    OR NEW.surgery_date IS DISTINCT FROM OLD.surgery_date
    OR NEW.surgery_time IS DISTINCT FROM OLD.surgery_time
  ) THEN
    RAISE EXCEPTION 'Surgery scheduling details are locked after inventory is consumed';
  END IF;
  RETURN NEW;
END;
$$;

-- Recreate the trigger (idempotent)
DROP TRIGGER IF EXISTS trg_validate_eye_surgery_locked_fields ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_locked_fields
BEFORE UPDATE ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_locked_fields();

-- 7. Drop the appointment_id column entirely
ALTER TABLE public.eye_surgeries
  DROP COLUMN IF EXISTS appointment_id;
