-- ============================================================================
-- SPRINT 5.2 PATCH — FIX EYE SURGERY NOTIFICATIONS & RESCHEDULE BEHAVIOR
-- Migration: 20261004120000_fix_eye_surgery_notifications_and_reschedule.sql
-- ============================================================================

-- 1. Safely add 'eye_surgery_assigned' to notifications CHECK constraint
-- Preserves ALL existing notification types from previous sprints:
-- 'info', 'leave_request', 'leave_approved', 'leave_rejected',
-- 'task_assigned', 'task_updated', 'task_completed', 'task_overdue',
-- 'appointment', 'system', 'low_stock', 'expiry', 'purchase_order',
-- 'eye_surgery', 'eye_surgery_assigned'
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (type IN (
    'info', 'leave_request', 'leave_approved', 'leave_rejected',
    'task_assigned', 'task_updated', 'task_completed', 'task_overdue',
    'appointment', 'system', 'low_stock', 'expiry', 'purchase_order',
    'eye_surgery', 'eye_surgery_assigned'
  ));

-- 2. Update locked fields validation trigger:
-- - Staff can reschedule MISSED surgeries (either OLD.status = 'missed' OR scheduled date/time has passed)
-- - Rescheduling to a future date/time safely resets status to 'scheduled'
-- - Locked fields remain strictly guarded if inventory was already consumed
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

-- 3. Update status transition trigger to permit pre_op -> scheduled upon rescheduling
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

-- 4. Defensive Admin notification trigger
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
    IF NEW.status IS DISTINCT FROM OLD.status
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

-- 5. Defensive Shift task & Staff notification sync trigger:
-- - Upserts shift task on same related_surgery_id without duplicates
-- - Updates shift task due_date on reschedule
-- - Inserts 'eye_surgery_assigned' on assignment/reassignment
-- - Handles check_violation defensively with fallback
-- - Notification failure never breaks the surgery save transaction
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

  -- Due date calculation
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
