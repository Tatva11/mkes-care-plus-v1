-- ============================================================
-- MKES CARE+ — SPRINT 5.1 PATCH: DENTAL LAB TRACKING ENHANCEMENTS
-- ============================================================
-- 1. Adds appointment_id foreign key to public.dental_lab
-- 2. Adds check trigger to enforce that Dental Lab cases can only
--    be created for Dental department patients
-- 3. Adds atomic RPC mark_dental_lab_case_ready_with_appointment
-- Safe and idempotent to run multiple times.
-- ============================================================

-- 1. ADD APPOINTMENT_ID LINKAGE
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'dental_lab'
      AND column_name = 'appointment_id'
  ) THEN
    ALTER TABLE public.dental_lab
      ADD COLUMN appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_dental_lab_appointment_id
  ON public.dental_lab(appointment_id);

-- 2. SERVER-SIDE DENTAL PATIENT VALIDATION TRIGGER
-- Ensures dental_lab records can strictly only be associated with Dental department patients.
CREATE OR REPLACE FUNCTION public.check_dental_lab_patient_department()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_department TEXT;
BEGIN
  IF NEW.patient_id IS NOT NULL THEN
    SELECT department INTO v_department
    FROM public.patients
    WHERE id = NEW.patient_id;

    IF v_department IS NOT NULL AND LOWER(v_department) <> 'dental' THEN
      RAISE EXCEPTION 'Dental Lab cases can only be created for patients in the Dental department (patient belongs to "%")', v_department;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_dental_lab_patient_department ON public.dental_lab;
CREATE TRIGGER trg_check_dental_lab_patient_department
BEFORE INSERT OR UPDATE OF patient_id ON public.dental_lab
FOR EACH ROW
EXECUTE FUNCTION public.check_dental_lab_patient_department();

-- 3. ATOMIC RPC: MARK CASE READY AND SCHEDULE/LINK APPOINTMENT IDEMPOTENTLY
CREATE OR REPLACE FUNCTION public.mark_dental_lab_case_ready_with_appointment(
  p_case_id UUID,
  p_ready_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case RECORD;
  v_appt_id UUID;
  v_appt RECORD;
  v_target_date DATE;
  v_doctor_id UUID;
BEGIN
  -- 1. Fetch existing case
  SELECT * INTO v_case FROM public.dental_lab WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dental Lab case % not found', p_case_id;
  END IF;

  -- 2. Check if already has linked appointment (Idempotency)
  IF v_case.appointment_id IS NOT NULL THEN
    v_appt_id := v_case.appointment_id;
  ELSE
    -- Check for existing upcoming dental appointment for this patient
    SELECT id INTO v_appt_id
    FROM public.appointments
    WHERE patient_id = v_case.patient_id
      AND department = 'dental'
      AND status IN ('scheduled', 'confirmed', 'waiting')
      AND appointment_date >= CURRENT_DATE
    ORDER BY appointment_date ASC
    LIMIT 1;

    -- If no existing upcoming appointment, schedule one
    IF v_appt_id IS NULL THEN
      -- Target date: 2 days after ready date (skip Sunday if falls on Sunday)
      v_target_date := p_ready_date + INTERVAL '2 days';
      IF EXTRACT(DOW FROM v_target_date) = 0 THEN
        v_target_date := v_target_date + INTERVAL '1 day';
      END IF;

      -- Look for dental staff/doctor candidate
      SELECT id INTO v_doctor_id
      FROM public.profiles
      WHERE (LOWER(department) = 'dental' OR designation ILIKE '%dentist%')
        AND is_active = true
      LIMIT 1;

      INSERT INTO public.appointments (
        patient_id,
        department,
        doctor_id,
        appointment_date,
        appointment_time,
        appointment_type,
        status,
        notes
      ) VALUES (
        v_case.patient_id,
        'dental',
        v_doctor_id,
        v_target_date,
        '10:30:00'::TIME,
        'follow_up',
        'scheduled',
        'Follow-up fitting for Dental Lab Case #' || v_case.case_number || ' (' || v_case.case_type || ')'
      ) RETURNING id INTO v_appt_id;
    ELSE
      -- Update notes on existing appointment to include lab fitting note
      UPDATE public.appointments
      SET notes = COALESCE(notes || ' | ', '') || 'Fitting for Lab Case #' || v_case.case_number,
          updated_at = now()
      WHERE id = v_appt_id;
    END IF;
  END IF;

  -- 3. Update dental_lab record
  UPDATE public.dental_lab
  SET status = 'ready',
      ready_date = p_ready_date,
      appointment_id = v_appt_id,
      updated_at = now()
  WHERE id = p_case_id;

  -- 4. Retrieve appointment record to return
  SELECT a.*, p.name AS patient_name
  INTO v_appt
  FROM public.appointments a
  LEFT JOIN public.patients p ON p.id = a.patient_id
  WHERE a.id = v_appt_id;

  RETURN jsonb_build_object(
    'case_id', p_case_id,
    'status', 'ready',
    'ready_date', p_ready_date,
    'appointment_id', v_appt_id,
    'appointment_date', v_appt.appointment_date,
    'appointment_time', v_appt.appointment_time,
    'appointment_status', v_appt.status
  );
END;
$$;
