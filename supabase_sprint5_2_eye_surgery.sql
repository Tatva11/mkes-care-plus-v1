-- ============================================================
-- MKES CARE+ - SPRINT 5.2: EYE SURGERY WORKFLOW
-- ============================================================
-- Safe to run repeatedly. Requires the existing
-- public.is_admin_or_staff() and public.update_updated_at() helpers.

CREATE TABLE IF NOT EXISTS public.eye_surgeries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  surgery_type TEXT NOT NULL,
  surgery_type_category TEXT NOT NULL DEFAULT 'Other',
  custom_surgery_type TEXT,
  eye_side TEXT NOT NULL CHECK (eye_side IN ('left', 'right', 'both')),
  assigned_staff_id UUID REFERENCES public.profiles(id),
  pre_op_date DATE NOT NULL,
  surgery_date DATE NOT NULL,
  surgery_time TIME,
  discharged_at TIMESTAMPTZ,
  inventory_consumed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'pre_op', 'in_surgery', 'post_op', 'discharged', 'cancelled', 'missed')),
  pre_op_checklist JSONB NOT NULL DEFAULT '{}'::jsonb,
  iol_details TEXT,
  remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.eye_surgeries
  ADD COLUMN IF NOT EXISTS surgery_type_category TEXT NOT NULL DEFAULT 'Other',
  ADD COLUMN IF NOT EXISTS custom_surgery_type TEXT,
  ADD COLUMN IF NOT EXISTS assigned_staff_id UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS pre_op_date DATE,
  ADD COLUMN IF NOT EXISTS discharged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS inventory_consumed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS follow_up_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_eye_surgeries_follow_up_appointment_id
  ON public.eye_surgeries(follow_up_appointment_id);

CREATE INDEX IF NOT EXISTS idx_eye_surgeries_discharged_at
  ON public.eye_surgeries(discharged_at);

-- Drop obsolete pre-discharge appointment linking and slot blocking triggers
DROP TRIGGER IF EXISTS trg_validate_eye_surgery_follow_up_slot ON public.appointments;
DROP FUNCTION IF EXISTS public.validate_eye_surgery_follow_up_slot();
DROP INDEX IF EXISTS public.idx_appointments_eye_surgery_follow_up_marker;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_appointment ON public.eye_surgeries;
DROP FUNCTION IF EXISTS public.validate_eye_surgery_appointment();
DROP INDEX IF EXISTS public.idx_eye_surgeries_appointment_id;

DO $$
BEGIN
  ALTER TABLE public.eye_surgeries
    DROP CONSTRAINT IF EXISTS eye_surgeries_appointment_id_fkey;
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

ALTER TABLE public.eye_surgeries
  DROP COLUMN IF EXISTS appointment_id;

-- Follow-up appointment is allowed ONLY after surgery is discharged
CREATE OR REPLACE FUNCTION public.validate_eye_surgery_follow_up_appointment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_appt_patient_id UUID;
BEGIN
  IF NEW.follow_up_appointment_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status <> 'discharged' THEN
    RAISE EXCEPTION 'Follow-up appointments can only be linked after the surgery has been discharged';
  END IF;

  SELECT patient_id INTO v_appt_patient_id
  FROM public.appointments
  WHERE id = NEW.follow_up_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Linked follow-up appointment does not exist';
  END IF;

  IF v_appt_patient_id IS DISTINCT FROM NEW.patient_id THEN
    RAISE EXCEPTION 'Follow-up appointment patient must match surgery patient';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_follow_up_appointment ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_follow_up_appointment
BEFORE INSERT OR UPDATE OF follow_up_appointment_id, status ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_follow_up_appointment();

DO $$
DECLARE
  v_conflicting_assignments BOOLEAN;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'eye_surgeries'
      AND column_name = 'surgeon_id'
  ) THEN
    EXECUTE 'UPDATE public.eye_surgeries
      SET assigned_staff_id = surgeon_id
      WHERE assigned_staff_id IS NULL AND surgeon_id IS NOT NULL';

    SELECT EXISTS (
      SELECT 1 FROM public.eye_surgeries
      WHERE surgeon_id IS NOT NULL
        AND assigned_staff_id IS DISTINCT FROM surgeon_id
    ) INTO v_conflicting_assignments;

    IF NOT v_conflicting_assignments THEN
      EXECUTE 'ALTER TABLE public.eye_surgeries DROP COLUMN surgeon_id';
    END IF;
  END IF;
END;
$$;

UPDATE public.eye_surgeries
SET pre_op_date = surgery_date
WHERE pre_op_date IS DISTINCT FROM surgery_date;

UPDATE public.eye_surgeries
SET surgery_type_category = CASE surgery_type
      WHEN 'Cataract Surgery' THEN 'Cataract Surgery'
      WHEN 'LASIK / Refractive Surgery' THEN 'LASIK / Refractive Surgery'
      WHEN 'Glaucoma Surgery' THEN 'Glaucoma Surgery'
      WHEN 'Retinal Surgery' THEN 'Retinal Surgery'
      WHEN 'Corneal Surgery' THEN 'Corneal Surgery'
      ELSE 'Other'
    END,
    custom_surgery_type = CASE
      WHEN surgery_type IN (
        'Cataract Surgery', 'LASIK / Refractive Surgery', 'Glaucoma Surgery',
        'Retinal Surgery', 'Corneal Surgery'
      ) THEN custom_surgery_type
      ELSE COALESCE(custom_surgery_type, surgery_type)
    END
WHERE surgery_type_category = 'Other'
  AND custom_surgery_type IS NULL;

ALTER TABLE public.eye_surgeries
  ALTER COLUMN pre_op_date SET NOT NULL;

ALTER TABLE public.eye_surgeries
  DROP CONSTRAINT IF EXISTS eye_surgeries_surgery_type_category_check;
ALTER TABLE public.eye_surgeries
  ADD CONSTRAINT eye_surgeries_surgery_type_category_check
  CHECK (surgery_type_category IN (
    'Cataract Surgery', 'LASIK / Refractive Surgery', 'Glaucoma Surgery',
    'Retinal Surgery', 'Corneal Surgery', 'Other'
  ));

ALTER TABLE public.eye_surgeries
  DROP CONSTRAINT IF EXISTS eye_surgeries_pre_op_date_matches_surgery_date;
ALTER TABLE public.eye_surgeries
  ADD CONSTRAINT eye_surgeries_pre_op_date_matches_surgery_date
  CHECK (pre_op_date = surgery_date);

ALTER TABLE public.eye_surgeries
  DROP CONSTRAINT IF EXISTS eye_surgeries_status_check;
ALTER TABLE public.eye_surgeries
  ADD CONSTRAINT eye_surgeries_status_check
  CHECK (status IN ('scheduled', 'pre_op', 'in_surgery', 'post_op', 'discharged', 'cancelled', 'missed'));

CREATE INDEX IF NOT EXISTS idx_eye_surgeries_patient_id
  ON public.eye_surgeries(patient_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgeries_assigned_staff_id
  ON public.eye_surgeries(assigned_staff_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgeries_surgery_date
  ON public.eye_surgeries(surgery_date);
CREATE INDEX IF NOT EXISTS idx_eye_surgeries_status
  ON public.eye_surgeries(status);

CREATE TABLE IF NOT EXISTS public.eye_surgery_item_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  surgery_type TEXT NOT NULL,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
  default_quantity NUMERIC(12,2) NOT NULL CHECK (default_quantity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (surgery_type, inventory_item_id),
  CHECK (surgery_type IN (
    'Cataract Surgery', 'LASIK / Refractive Surgery', 'Glaucoma Surgery',
    'Retinal Surgery', 'Corneal Surgery', 'Other'
  ))
);

CREATE TABLE IF NOT EXISTS public.eye_surgery_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eye_surgery_id UUID NOT NULL REFERENCES public.eye_surgeries(id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
  planned_quantity NUMERIC(12,2) NOT NULL CHECK (planned_quantity > 0),
  actual_quantity NUMERIC(12,2) NOT NULL CHECK (actual_quantity > 0),
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('template', 'manual')),
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (eye_surgery_id, inventory_item_id)
);

CREATE INDEX IF NOT EXISTS idx_eye_surgery_items_surgery_id
  ON public.eye_surgery_items(eye_surgery_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgery_items_inventory_id
  ON public.eye_surgery_items(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgery_item_templates_surgery_type
  ON public.eye_surgery_item_templates(surgery_type, is_active);

ALTER TABLE public.eye_surgery_item_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eye_surgery_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins and Staff can view eye surgery templates" ON public.eye_surgery_item_templates;
DROP POLICY IF EXISTS "Admins can manage eye surgery templates" ON public.eye_surgery_item_templates;
CREATE POLICY "Admins and Staff can view eye surgery templates"
  ON public.eye_surgery_item_templates FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());
CREATE POLICY "Admins can manage eye surgery templates"
  ON public.eye_surgery_item_templates FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ));

DROP POLICY IF EXISTS "Admins and Staff can view eye surgery items" ON public.eye_surgery_items;
DROP POLICY IF EXISTS "Admins and Staff can manage eye surgery items" ON public.eye_surgery_items;
CREATE POLICY "Admins and Staff can view eye surgery items"
  ON public.eye_surgery_items FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());
CREATE POLICY "Admins and Staff can manage eye surgery items"
  ON public.eye_surgery_items FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_surgery_item_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_surgery_items TO authenticated;
GRANT ALL ON TABLE public.eye_surgery_item_templates TO service_role;
GRANT ALL ON TABLE public.eye_surgery_items TO service_role;

CREATE OR REPLACE FUNCTION public.set_eye_surgery_item_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS eye_surgery_item_templates_updated_at ON public.eye_surgery_item_templates;
CREATE TRIGGER eye_surgery_item_templates_updated_at
BEFORE UPDATE ON public.eye_surgery_item_templates
FOR EACH ROW EXECUTE FUNCTION public.set_eye_surgery_item_updated_at();

DROP TRIGGER IF EXISTS eye_surgery_items_updated_at ON public.eye_surgery_items;
CREATE TRIGGER eye_surgery_items_updated_at
BEFORE UPDATE ON public.eye_surgery_items
FOR EACH ROW EXECUTE FUNCTION public.set_eye_surgery_item_updated_at();

CREATE OR REPLACE FUNCTION public.sync_eye_surgery_pre_op_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.pre_op_date := NEW.surgery_date;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_eye_surgery_pre_op_date ON public.eye_surgeries;
CREATE TRIGGER trg_sync_eye_surgery_pre_op_date
BEFORE INSERT OR UPDATE OF surgery_date, pre_op_date ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.sync_eye_surgery_pre_op_date();

-- Validate that surgery_time is mandatory for all created or scheduled surgeries
CREATE OR REPLACE FUNCTION public.validate_eye_surgery_required_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.surgery_time IS NULL THEN
    RAISE EXCEPTION 'Surgery time is required';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_required_fields ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_required_fields
BEFORE INSERT OR UPDATE OF surgery_time, status ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_required_fields();

-- Validate that assigned staff belongs to active staff profiles (excluding admin profiles)
-- and enforce that only administrators can assign or update assigned_staff_id.
CREATE OR REPLACE FUNCTION public.validate_eye_surgery_assigned_staff()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_active BOOLEAN;
BEGIN
  -- Admin-only permission enforcement for assigning or changing staff
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    IF TG_OP = 'INSERT' AND NEW.assigned_staff_id IS NOT NULL THEN
      RAISE EXCEPTION 'Only administrators can assign staff to a surgery';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.assigned_staff_id IS DISTINCT FROM OLD.assigned_staff_id THEN
      RAISE EXCEPTION 'Only administrators can assign or change assigned staff';
    END IF;
  END IF;

  IF NEW.assigned_staff_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT role, is_active INTO v_role, v_active
  FROM public.profiles
  WHERE id = NEW.assigned_staff_id;

  IF NOT FOUND OR NOT COALESCE(v_active, false) THEN
    RAISE EXCEPTION 'Assigned staff must be an active profile';
  END IF;

  IF v_role = 'admin' THEN
    RAISE EXCEPTION 'Admin accounts cannot be selected as assigned staff';
  END IF;

  IF v_role <> 'staff' THEN
    RAISE EXCEPTION 'Assigned staff must have the staff role';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_assigned_staff ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_assigned_staff
BEFORE INSERT OR UPDATE OF assigned_staff_id ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_assigned_staff();

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_item_editable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_consumed_at TIMESTAMPTZ;
BEGIN
  SELECT inventory_consumed_at INTO v_consumed_at
  FROM public.eye_surgeries
  WHERE id = COALESCE(NEW.eye_surgery_id, OLD.eye_surgery_id);

  IF v_consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Surgery items are locked after inventory is consumed';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_item_editable ON public.eye_surgery_items;
CREATE TRIGGER trg_validate_eye_surgery_item_editable
BEFORE INSERT OR UPDATE OR DELETE ON public.eye_surgery_items
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_item_editable();

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_item_in_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_stock NUMERIC;
BEGIN
  IF TG_OP = 'UPDATE'
    AND NEW.inventory_item_id IS NOT DISTINCT FROM OLD.inventory_item_id THEN
    RETURN NEW;
  END IF;

  SELECT quantity INTO v_current_stock
  FROM public.inventory
  WHERE id = NEW.inventory_item_id;
  IF NOT FOUND OR COALESCE(v_current_stock, 0) <= 0 THEN
    RAISE EXCEPTION 'Inventory item is Out of Stock and cannot be added to surgery';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_item_in_stock ON public.eye_surgery_items;
CREATE TRIGGER trg_validate_eye_surgery_item_in_stock
BEFORE INSERT OR UPDATE OF inventory_item_id ON public.eye_surgery_items
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_item_in_stock();

-- Auto-seed default templates only if no items have been provided for this new surgery
CREATE OR REPLACE FUNCTION public.seed_eye_surgery_items_from_template()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.eye_surgery_items WHERE eye_surgery_id = NEW.id
  ) THEN
    INSERT INTO public.eye_surgery_items (
      eye_surgery_id, inventory_item_id, planned_quantity, actual_quantity, source
    )
    SELECT NEW.id, inventory_item_id, default_quantity, default_quantity, 'template'
    FROM public.eye_surgery_item_templates
    WHERE surgery_type = NEW.surgery_type_category AND is_active = true
    ON CONFLICT (eye_surgery_id, inventory_item_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seed_eye_surgery_items_from_template ON public.eye_surgeries;
CREATE TRIGGER trg_seed_eye_surgery_items_from_template
AFTER INSERT ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.seed_eye_surgery_items_from_template();

-- Saved surgeries must NOT have their existing items silently replaced on surgery type update
DROP TRIGGER IF EXISTS trg_refresh_eye_surgery_items_for_type ON public.eye_surgeries;
DROP FUNCTION IF EXISTS public.refresh_eye_surgery_items_for_type();

CREATE TABLE IF NOT EXISTS public.eye_surgery_inventory_consumptions (
  eye_surgery_id UUID PRIMARY KEY
    REFERENCES public.eye_surgeries(id) ON DELETE CASCADE,
  consumed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  item_count INTEGER NOT NULL CHECK (item_count >= 0)
);

ALTER TABLE public.eye_surgery_inventory_consumptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.eye_surgery_inventory_consumptions FROM anon, authenticated;
GRANT ALL ON TABLE public.eye_surgery_inventory_consumptions TO service_role;

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_locked_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_consumed_at TIMESTAMPTZ;
  v_is_missed BOOLEAN := FALSE;
  v_old_scheduled_at TIMESTAMPTZ;
BEGIN
  -- Rescheduling permission check (Admin or Staff can reschedule MISSED surgeries)
  IF (NEW.surgery_date IS DISTINCT FROM OLD.surgery_date
      OR NEW.surgery_time IS DISTINCT FROM OLD.surgery_time) THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin_or_staff() THEN
      RAISE EXCEPTION 'Only administrators and staff can reschedule surgeries';
    END IF;

    -- Non-admin staff can only reschedule missed surgeries
    IF NOT public.is_admin() THEN
      IF OLD.status = 'missed' THEN
        v_is_missed := TRUE;
      ELSIF OLD.status IN ('scheduled', 'pre_op') THEN
        IF OLD.surgery_time IS NOT NULL AND TRIM(OLD.surgery_time::text) <> '' THEN
          BEGIN
            v_old_scheduled_at := (OLD.surgery_date::text || ' ' || OLD.surgery_time::text)::timestamptz;
          EXCEPTION WHEN OTHERS THEN
            v_old_scheduled_at := (OLD.surgery_date::text || ' 23:59:59')::timestamptz;
          END;
        ELSE
          v_old_scheduled_at := (OLD.surgery_date::text || ' 23:59:59')::timestamptz;
        END IF;
        v_is_missed := (v_old_scheduled_at < now());
      END IF;

      IF NOT v_is_missed THEN
        RAISE EXCEPTION 'Only missed surgeries can be rescheduled by staff';
      END IF;
    END IF;

    IF NEW.surgery_time IS NULL THEN
      RAISE EXCEPTION 'Surgery time is required';
    END IF;

    -- If a missed surgery is rescheduled to a future time, ensure status becomes 'scheduled'
    IF OLD.status = 'missed' AND NEW.status = 'missed' THEN
      DECLARE
        v_new_scheduled_at TIMESTAMPTZ;
      BEGIN
        IF NEW.surgery_time IS NOT NULL AND TRIM(NEW.surgery_time::text) <> '' THEN
          BEGIN
            v_new_scheduled_at := (NEW.surgery_date::text || ' ' || NEW.surgery_time::text)::timestamptz;
          EXCEPTION WHEN OTHERS THEN
            v_new_scheduled_at := (NEW.surgery_date::text || ' 23:59:59')::timestamptz;
          END;
        ELSE
          v_new_scheduled_at := (NEW.surgery_date::text || ' 23:59:59')::timestamptz;
        END IF;
        IF v_new_scheduled_at >= now() THEN
          NEW.status := 'scheduled';
        END IF;
      END;
    END IF;
  END IF;

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

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_locked_fields ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_locked_fields
BEFORE UPDATE ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_locked_fields();

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_status_transition()
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
  WHERE eye_surgery_id = NEW.id;

  IF NEW.inventory_consumed_at IS DISTINCT FROM OLD.inventory_consumed_at
    AND NEW.inventory_consumed_at IS NOT NULL
    AND v_consumed_at IS NULL THEN
    RAISE EXCEPTION 'Inventory consumption can only be recorded by the stock RPC';
  END IF;

  IF v_consumed_at IS NOT NULL THEN
    NEW.inventory_consumed_at := v_consumed_at;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
    AND NOT (
      (OLD.status = 'scheduled' AND NEW.status IN ('pre_op', 'cancelled', 'missed'))
      OR (OLD.status = 'pre_op' AND NEW.status IN ('scheduled', 'in_surgery', 'cancelled', 'missed'))
      OR (OLD.status = 'missed' AND NEW.status IN ('scheduled', 'cancelled'))
      OR (OLD.status = 'in_surgery' AND NEW.status IN ('post_op', 'cancelled'))
      OR (OLD.status = 'post_op' AND NEW.status IN ('discharged', 'cancelled'))
    ) THEN
    RAISE EXCEPTION 'Invalid Eye Surgery status transition: % -> %', OLD.status, NEW.status;
  END IF;

  IF NEW.status = 'discharged' AND OLD.status IS DISTINCT FROM 'discharged' THEN
    IF NEW.discharged_at IS NULL THEN
      NEW.discharged_at := now();
    END IF;
  END IF;

  IF OLD.status = 'scheduled' AND NEW.status = 'pre_op' THEN
    IF NEW.assigned_staff_id IS NULL THEN
      RAISE EXCEPTION 'An Admin must assign staff to this surgery before starting Pre-op.';
    END IF;
    DECLARE
      v_staff_role TEXT;
      v_staff_active BOOLEAN;
    BEGIN
      SELECT role, COALESCE(is_active, true) INTO v_staff_role, v_staff_active
      FROM public.profiles
      WHERE id = NEW.assigned_staff_id;

      IF NOT FOUND OR LOWER(COALESCE(v_staff_role, '')) <> 'staff' OR NOT v_staff_active THEN
        RAISE EXCEPTION 'An Admin must assign staff to this surgery before starting Pre-op.';
      END IF;
    END;
  END IF;

  IF NEW.status = 'in_surgery'
    AND OLD.status IS DISTINCT FROM 'in_surgery' THEN
    IF NEW.pre_op_checklist->'identity_verified' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'consent_confirmed' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'correct_eye_confirmed' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'pre_op_exam_completed' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'investigations_reviewed' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'allergies_checked' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'assigned_staff_confirmed' IS DISTINCT FROM 'true'::jsonb
      OR NEW.pre_op_checklist->'procedure_confirmed' IS DISTINCT FROM 'true'::jsonb THEN
      RAISE EXCEPTION 'Complete the pre-op checklist before entering surgery.';
    END IF;
    IF v_consumed_at IS NULL THEN
      RAISE EXCEPTION 'Inventory must be consumed atomically before entering In Surgery';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_status ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_status
BEFORE UPDATE OF status ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_status_transition();

CREATE TABLE IF NOT EXISTS public.eye_surgery_notification_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eye_surgery_id UUID NOT NULL REFERENCES public.eye_surgeries(id) ON DELETE CASCADE,
  event_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (eye_surgery_id, event_key)
);

ALTER TABLE public.eye_surgery_notification_events ENABLE ROW LEVEL SECURITY;
GRANT ALL ON TABLE public.eye_surgery_notification_events TO service_role;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (type IN (
    'info', 'leave_request', 'leave_approved', 'leave_rejected',
    'task_assigned', 'task_updated', 'task_completed', 'task_overdue',
    'appointment', 'system', 'low_stock', 'expiry', 'purchase_order',
    'eye_surgery', 'eye_surgery_assigned'
  ));

CREATE OR REPLACE FUNCTION public.notify_admins_eye_surgery_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_key TEXT;
  v_event_id UUID;
  v_patient_name TEXT;
  v_staff_name TEXT;
  v_status TEXT;
  v_title TEXT;
  v_message TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event_key := 'scheduled';
    v_status := 'scheduled';
    v_title := 'Eye Surgery Scheduled';
  ELSE
    IF NEW.status IS NOT DISTINCT FROM OLD.status
      OR NEW.status NOT IN ('in_surgery', 'post_op', 'discharged', 'cancelled') THEN
      RETURN NEW;
    END IF;
    v_event_key := 'status:' || NEW.status;
    v_status := NEW.status;
    v_title := 'Eye Surgery ' || initcap(replace(NEW.status, '_', ' '));
  END IF;

  INSERT INTO public.eye_surgery_notification_events (eye_surgery_id, event_key)
  VALUES (NEW.id, v_event_key)
  ON CONFLICT (eye_surgery_id, event_key) DO NOTHING
  RETURNING id INTO v_event_id;
  IF v_event_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.name, COALESCE(staff.full_name, 'Unassigned')
  INTO v_patient_name, v_staff_name
  FROM public.patients p
  LEFT JOIN public.profiles staff ON staff.id = NEW.assigned_staff_id
  WHERE p.id = NEW.patient_id;

  v_message := format(
    '%s | %s | %s eye | Assigned Staff: %s | %s %s | Status: %s',
    COALESCE(v_patient_name, 'Patient'),
    COALESCE(NEW.surgery_type, 'Eye Surgery'),
    NEW.eye_side,
    COALESCE(v_staff_name, 'Unassigned'),
    NEW.surgery_date::text,
    COALESCE(NEW.surgery_time::text, ''),
    v_status
  );

  BEGIN
    INSERT INTO public.notifications (user_id, title, message, type, related_id)
    SELECT id, v_title, v_message, 'eye_surgery', NEW.id
    FROM public.profiles
    WHERE role = 'admin' AND is_active = true;
  EXCEPTION
    WHEN OTHERS THEN
      NULL; -- Never allow notification error to break surgery save
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_eye_surgery_insert ON public.eye_surgeries;
CREATE TRIGGER trg_notify_admins_eye_surgery_insert
AFTER INSERT ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.notify_admins_eye_surgery_event();

DROP TRIGGER IF EXISTS trg_notify_admins_eye_surgery_status ON public.eye_surgeries;
CREATE TRIGGER trg_notify_admins_eye_surgery_status
AFTER UPDATE OF status ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.notify_admins_eye_surgery_event();

CREATE OR REPLACE FUNCTION public.notify_eye_surgery_insufficient_stock(
  p_eye_surgery_id UUID,
  p_detail TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_surgery RECORD;
  v_event_id UUID;
BEGIN
  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Active Admin or Staff access required';
  END IF;

  SELECT s.*, p.name AS patient_name, staff.full_name AS staff_name
  INTO v_surgery
  FROM public.eye_surgeries s
  JOIN public.patients p ON p.id = s.patient_id
  LEFT JOIN public.profiles staff ON staff.id = s.assigned_staff_id
  WHERE s.id = p_eye_surgery_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eye Surgery not found';
  END IF;

  INSERT INTO public.eye_surgery_notification_events (eye_surgery_id, event_key)
  VALUES (p_eye_surgery_id, 'insufficient_stock')
  ON CONFLICT (eye_surgery_id, event_key) DO NOTHING
  RETURNING id INTO v_event_id;
  IF v_event_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications (user_id, title, message, type, related_id)
  SELECT id,
         'Eye Surgery Inventory Shortage',
         format('%s | %s | %s eye | Assigned Staff: %s | %s',
           v_surgery.patient_name, v_surgery.surgery_type, v_surgery.eye_side,
           COALESCE(v_surgery.staff_name, 'Unassigned'),
           COALESCE(p_detail, 'Insufficient stock prevented surgery start.')),
         'eye_surgery', p_eye_surgery_id
  FROM public.profiles
  WHERE role = 'admin' AND is_active = true;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_eye_surgery_insufficient_stock(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_eye_surgery_insufficient_stock(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.consume_eye_surgery_inventory(p_eye_surgery_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_surgery RECORD;
  v_item RECORD;
  v_count INTEGER := 0;
  v_consumed_at TIMESTAMPTZ;
BEGIN
  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Active Admin or Staff access required';
  END IF;

  SELECT * INTO v_surgery
  FROM public.eye_surgeries
  WHERE id = p_eye_surgery_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eye Surgery not found';
  END IF;

  IF v_surgery.inventory_consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('already_consumed', true, 'status', v_surgery.status);
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.eye_surgery_inventory_consumptions
    WHERE eye_surgery_id = p_eye_surgery_id
  ) THEN
    RAISE EXCEPTION 'Eye Surgery inventory consumption record is inconsistent';
  END IF;
  IF v_surgery.status <> 'pre_op' THEN
    RAISE EXCEPTION 'Surgery must be in Pre-op before inventory can be consumed';
  END IF;
  IF v_surgery.pre_op_checklist->'identity_verified' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'consent_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'correct_eye_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'pre_op_exam_completed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'investigations_reviewed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'allergies_checked' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'assigned_staff_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'procedure_confirmed' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'Complete the pre-op checklist before entering surgery.';
  END IF;

  FOR v_item IN
    SELECT si.inventory_item_id, si.actual_quantity, inventory.quantity,
           inventory.name
    FROM public.eye_surgery_items si
    JOIN public.inventory inventory ON inventory.id = si.inventory_item_id
    WHERE si.eye_surgery_id = p_eye_surgery_id
    ORDER BY si.inventory_item_id
    FOR UPDATE OF inventory
  LOOP
    v_count := v_count + 1;
    IF v_item.actual_quantity <= 0 THEN
      RAISE EXCEPTION 'Surgery item quantity must be greater than zero';
    END IF;
    IF v_item.quantity < v_item.actual_quantity THEN
      RAISE EXCEPTION 'Insufficient stock for %: available %, requested %',
        v_item.name, v_item.quantity, v_item.actual_quantity;
    END IF;
  END LOOP;

  FOR v_item IN
    SELECT si.inventory_item_id, si.actual_quantity, inventory.name
    FROM public.eye_surgery_items si
    JOIN public.inventory inventory ON inventory.id = si.inventory_item_id
    WHERE si.eye_surgery_id = p_eye_surgery_id
    ORDER BY si.inventory_item_id
  LOOP
    PERFORM public.perform_stock_operation(
      p_inventory_id := v_item.inventory_item_id,
      p_transaction_type := 'stock_out',
      p_quantity := v_item.actual_quantity,
      p_reason := 'Dispensed to Patient',
      p_remarks := format('Eye Surgery %s: %s', p_eye_surgery_id, v_item.name),
      p_patient_id := v_surgery.patient_id
    );

    UPDATE public.eye_surgery_items
    SET consumed_at = now(), updated_at = now()
    WHERE eye_surgery_id = p_eye_surgery_id
      AND inventory_item_id = v_item.inventory_item_id;
  END LOOP;

  v_consumed_at := now();
  INSERT INTO public.eye_surgery_inventory_consumptions (
    eye_surgery_id, consumed_at, item_count
  ) VALUES (p_eye_surgery_id, v_consumed_at, v_count);

  UPDATE public.eye_surgeries
  SET status = 'in_surgery',
      inventory_consumed_at = v_consumed_at,
      updated_at = now()
  WHERE id = p_eye_surgery_id;

  RETURN jsonb_build_object(
    'already_consumed', false,
    'status', 'in_surgery',
    'item_count', v_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.consume_eye_surgery_inventory(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_eye_surgery_inventory(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_patient()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_department TEXT;
BEGIN
  SELECT department INTO v_department
  FROM public.patients
  WHERE id = NEW.patient_id;

  IF NOT FOUND OR LOWER(COALESCE(v_department, '')) <> 'eye' THEN
    RAISE EXCEPTION 'Eye surgeries can only be linked to Eye department patients';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_patient ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_patient
BEFORE INSERT OR UPDATE OF patient_id ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.validate_eye_surgery_patient();

DROP TRIGGER IF EXISTS eye_surgeries_updated_at ON public.eye_surgeries;
CREATE TRIGGER eye_surgeries_updated_at
BEFORE UPDATE ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.eye_surgeries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eye_surgeries REPLICA IDENTITY FULL;

DROP POLICY IF EXISTS "Admins and Staff can view eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Admins and Staff can insert eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Admins and Staff can update eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Admins can delete eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Staff can delete eye surgeries" ON public.eye_surgeries;
DROP POLICY IF EXISTS "Admins and Staff can delete eye surgeries" ON public.eye_surgeries;

CREATE POLICY "Admins and Staff can view eye surgeries" ON public.eye_surgeries
  FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());
CREATE POLICY "Admins and Staff can insert eye surgeries" ON public.eye_surgeries
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_or_staff());
CREATE POLICY "Admins and Staff can update eye surgeries" ON public.eye_surgeries
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());
CREATE POLICY "Admins can delete eye surgeries" ON public.eye_surgeries
  FOR DELETE TO authenticated
  USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.validate_eye_surgery_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only administrators can delete eye surgeries';
  END IF;
  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_eye_surgery_deletion() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_eye_surgery_deletion() TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_eye_surgery_deletion() TO service_role;

DROP TRIGGER IF EXISTS trg_validate_eye_surgery_deletion ON public.eye_surgeries;
CREATE TRIGGER trg_validate_eye_surgery_deletion
BEFORE DELETE ON public.eye_surgeries
FOR EACH ROW
EXECUTE FUNCTION public.validate_eye_surgery_deletion();

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_surgeries TO authenticated;
GRANT ALL ON TABLE public.eye_surgeries TO service_role;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.eye_surgeries;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END;
$$;

-- ============================================================
-- SECTION 8: EYE SURGERY STAFF SHIFT TASKS & NOTIFICATIONS
-- ============================================================

ALTER TABLE public.tasks 
  ADD COLUMN IF NOT EXISTS related_surgery_id UUID REFERENCES public.eye_surgeries(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_unique_surgery 
  ON public.tasks(related_surgery_id) 
  WHERE related_surgery_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_eye_surgery_staff_task_and_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient_name TEXT;
  v_message TEXT;
  v_due_date TIMESTAMPTZ;
  v_task_title TEXT;
  v_task_desc TEXT;
  v_side TEXT;
  v_time_text TEXT;
BEGIN
  -- Patient details
  SELECT name INTO v_patient_name
  FROM public.patients
  WHERE id = NEW.patient_id;
  v_patient_name := COALESCE(v_patient_name, 'Patient');

  -- Safe time formatting (surgery_time is of type TIME)
  IF NEW.surgery_time IS NOT NULL AND TRIM(NEW.surgery_time::text) <> '' THEN
    v_time_text := to_char(NEW.surgery_time, 'HH12:MI AM');
  ELSE
    v_time_text := NULL;
  END IF;

  v_side := INITCAP(COALESCE(NEW.eye_side, 'eye'));
  v_task_title := 'Eye Surgery — ' || v_patient_name;
  IF v_time_text IS NOT NULL THEN
    v_task_desc := v_time_text || ' · ' || NEW.surgery_type || ' — ' || v_side || ' Eye';
  ELSE
    v_task_desc := NEW.surgery_type || ' — ' || v_side || ' Eye';
  END IF;

  -- Due date calculation:
  -- If surgery_time is NULL, use surgery_date only (do NOT concatenate/cast empty time string).
  -- If surgery_time exists, use surgery date + surgery time.
  IF NEW.surgery_time IS NOT NULL AND TRIM(NEW.surgery_time::text) <> '' THEN
    BEGIN
      v_due_date := (NEW.surgery_date::text || ' ' || NEW.surgery_time::text)::timestamptz;
    EXCEPTION WHEN OTHERS THEN
      v_due_date := (NEW.surgery_date::text || ' 00:00:00')::timestamptz;
    END;
  ELSE
    v_due_date := (NEW.surgery_date::text || ' 00:00:00')::timestamptz;
  END IF;

  -- 1. Shift Task Synchronization
  IF NEW.assigned_staff_id IS NOT NULL THEN
    IF TG_OP = 'INSERT' 
       OR (TG_OP = 'UPDATE' AND (
            OLD.assigned_staff_id IS DISTINCT FROM NEW.assigned_staff_id 
            OR OLD.surgery_date IS DISTINCT FROM NEW.surgery_date 
            OR OLD.surgery_time IS DISTINCT FROM NEW.surgery_time 
            OR OLD.status IS DISTINCT FROM NEW.status
          )) THEN
      INSERT INTO public.tasks (
        title,
        description,
        assigned_to,
        assigned_by,
        due_date,
        priority,
        status,
        related_surgery_id,
        created_at,
        updated_at,
        completed_at
      ) VALUES (
        v_task_title,
        v_task_desc,
        NEW.assigned_staff_id,
        auth.uid(),
        v_due_date,
        'high',
        CASE 
          WHEN NEW.status = 'discharged' THEN 'completed'
          WHEN NEW.status = 'cancelled' THEN 'cancelled'
          ELSE 'pending'
        END,
        NEW.id,
        now(),
        now(),
        CASE WHEN NEW.status = 'discharged' THEN now() ELSE NULL END
      )
      ON CONFLICT (related_surgery_id) WHERE related_surgery_id IS NOT NULL
      DO UPDATE SET
        title = EXCLUDED.title,
        description = EXCLUDED.description,
        assigned_to = EXCLUDED.assigned_to,
        due_date = EXCLUDED.due_date,
        status = EXCLUDED.status,
        updated_at = now(),
        completed_at = EXCLUDED.completed_at;
    END IF;

    -- 2. Staff Assignment Notification: ONLY when newly assigned or reassigned from Staff A -> Staff B
    IF (TG_OP = 'INSERT' AND NEW.assigned_staff_id IS NOT NULL)
       OR (TG_OP = 'UPDATE' AND (OLD.assigned_staff_id IS NULL OR OLD.assigned_staff_id IS DISTINCT FROM NEW.assigned_staff_id)) THEN
      v_message := 'Patient: ' || v_patient_name || E'\n' ||
                   'Surgery: ' || NEW.surgery_type || E'\n' ||
                   'Eye: ' || v_side || E'\n' ||
                   'Date: ' || to_char(NEW.surgery_date, 'DD/MM/YYYY');
      IF v_time_text IS NOT NULL THEN
        v_message := v_message || E'\nTime: ' || v_time_text;
      END IF;

      BEGIN
        INSERT INTO public.notifications (
          user_id,
          title,
          message,
          type,
          related_id,
          created_at
        ) VALUES (
          NEW.assigned_staff_id,
          'Eye Surgery Assigned',
          v_message,
          'eye_surgery_assigned',
          NEW.id,
          now()
        );
      EXCEPTION
        WHEN check_violation THEN
          -- Fallback safely to 'task_assigned' if constraint has not been updated yet
          BEGIN
            INSERT INTO public.notifications (
              user_id,
              title,
              message,
              type,
              related_id,
              created_at
            ) VALUES (
              NEW.assigned_staff_id,
              'Eye Surgery Assigned',
              v_message,
              'task_assigned',
              NEW.id,
              now()
            );
          EXCEPTION
            WHEN OTHERS THEN
              NULL; -- Notification error must never break surgery save
          END;
        WHEN OTHERS THEN
          NULL; -- Notification error must never break surgery save
      END;
    END IF;

    -- 3. Rescheduling Notification: when date or time changes on an already-assigned surgery
    IF TG_OP = 'UPDATE'
       AND OLD.assigned_staff_id IS NOT NULL
       AND OLD.assigned_staff_id = NEW.assigned_staff_id
       AND (OLD.surgery_date IS DISTINCT FROM NEW.surgery_date OR OLD.surgery_time IS DISTINCT FROM NEW.surgery_time) THEN
      v_message := 'Patient: ' || v_patient_name || E'\n' ||
                   'Surgery: ' || NEW.surgery_type || E'\n' ||
                   'Eye: ' || v_side || E'\n' ||
                   'New Date: ' || to_char(NEW.surgery_date, 'DD/MM/YYYY');
      IF v_time_text IS NOT NULL THEN
        v_message := v_message || E'\nNew Time: ' || v_time_text;
      END IF;

      BEGIN
        INSERT INTO public.notifications (
          user_id,
          title,
          message,
          type,
          related_id,
          created_at
        ) VALUES (
          NEW.assigned_staff_id,
          'Eye Surgery Rescheduled',
          v_message,
          'eye_surgery',
          NEW.id,
          now()
        );
      EXCEPTION
        WHEN OTHERS THEN
          NULL; -- Notification error must never break surgery save
      END;
    END IF;
  ELSE
    -- If staff was unassigned, remove the shift task
    IF TG_OP = 'UPDATE' AND OLD.assigned_staff_id IS NOT NULL AND NEW.assigned_staff_id IS NULL THEN
      DELETE FROM public.tasks WHERE related_surgery_id = NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_eye_surgery_staff_task ON public.eye_surgeries;
CREATE TRIGGER trg_sync_eye_surgery_staff_task
AFTER INSERT OR UPDATE ON public.eye_surgeries
FOR EACH ROW EXECUTE FUNCTION public.sync_eye_surgery_staff_task_and_notification();

