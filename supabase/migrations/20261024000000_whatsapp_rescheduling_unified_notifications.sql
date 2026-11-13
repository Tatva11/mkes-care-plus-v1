-- ============================================================================
-- MKES CARE+ — Migration: WhatsApp Automated Rescheduling & Unified Notifications
-- File: supabase/migrations/20261024000000_whatsapp_rescheduling_unified_notifications.sql
-- Description:
--   1. Push Notification Device Tokens (public.user_device_tokens)
--   2. Extended Notifications Check Constraint & Indexes
--   3. Atomic Appointment Rescheduling Stored Procedure (reschedule_appointment_via_whatsapp)
--   4. Staff WhatsApp Outbound Messaging Stored Procedure (send_staff_whatsapp_message)
--   5. Realtime Notification Dispatch for Patient Inbound WhatsApp Replies
--   6. Row Level Security & Least-Privilege Execution Grants
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. PUSH NOTIFICATION DEVICE REGISTRATION TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL,
  device_type TEXT NOT NULL DEFAULT 'android' CHECK (device_type IN ('android', 'ios', 'web')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_device_token UNIQUE (user_id, device_token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_active 
  ON public.user_device_tokens(user_id, is_active);

ALTER TABLE public.user_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own device tokens" ON public.user_device_tokens;
CREATE POLICY "Users manage own device tokens"
  ON public.user_device_tokens FOR ALL TO authenticated
  USING (user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ))
  WITH CHECK (user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  ));

-- ----------------------------------------------------------------------------
-- 2. EXTEND NOTIFICATIONS TYPE CHECK CONSTRAINT
-- ----------------------------------------------------------------------------
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN (
      'info',
      'leave_request',
      'leave_approved',
      'leave_rejected',
      'task_assigned',
      'task_updated',
      'task_completed',
      'task_overdue',
      'appointment',
      'system',
      'low_stock',
      'expiry',
      'purchase_order',
      'eye_surgery',
      'eye_surgery_assigned',
      'duty_assignment',
      'shift_change',
      'whatsapp_reply',
      'appointment_rescheduled',
      'lab_ready',
      'eye_lab_ready',
      'dental_lab_ready',
      'attendance_exception',
      'inventory_alert'
    )
  );

-- ----------------------------------------------------------------------------
-- 3. ATOMIC APPOINTMENT RESCHEDULING STORED PROCEDURE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reschedule_appointment_via_whatsapp(
  p_appointment_id UUID,
  p_new_date DATE,
  p_new_time TIME,
  p_duration_minutes INT DEFAULT 15
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_appt RECORD;
  v_patient RECORD;
  v_doc RECORD;
  v_dept TEXT;
  v_duration INT;
  v_new_end TIME;
  v_clinic_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
  v_clinic_today DATE := v_clinic_now::DATE;
  v_is_today BOOLEAN := (p_new_date = v_clinic_today);
  v_min_time TIME;
  v_opening TIME := '09:00:00'::TIME;
  v_closing TIME := '20:00:00'::TIME;
  v_active_doc_count INT;
  v_doc_conflict INT := 0;
  v_pending_doc_conflict INT := 0;
  v_total_dept_commitments INT := 0;
  v_reschedule_msg TEXT;
  v_admin_profile RECORD;
BEGIN
  -- 1. Lock existing appointment
  SELECT * INTO v_appt
  FROM public.appointments
  WHERE id = p_appointment_id FOR UPDATE;

  IF v_appt IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'APPOINTMENT_NOT_FOUND',
      'message', 'The requested appointment record does not exist.'
    );
  END IF;

  -- 2. Validate current appointment status
  IF v_appt.status NOT IN ('scheduled', 'confirmed') THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'INVALID_STATUS',
      'message', 'Appointment cannot be rescheduled because its current status is: ' || v_appt.status
    );
  END IF;

  v_dept := lower(trim(v_appt.department));
  IF v_dept NOT IN ('eye', 'dental') THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'INVALID_DEPARTMENT',
      'message', 'Only Eye and Dental appointments can be rescheduled via WhatsApp.'
    );
  END IF;

  -- 3. Validate new date and operating hours
  IF p_new_date < v_clinic_today THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'PAST_DATE',
      'message', 'Cannot reschedule an appointment to a past date.'
    );
  END IF;

  v_duration := coalesce(p_duration_minutes, v_appt.duration_minutes, 15);
  v_new_end := p_new_time + (v_duration || ' minutes')::interval;

  -- Fetch operating hours from settings
  SELECT coalesce(operating_hours_start, '09:00:00'::TIME), coalesce(operating_hours_end, '20:00:00'::TIME)
  INTO v_opening, v_closing
  FROM public.whatsapp_settings
  WHERE id = '00000000-0000-0000-0000-000000000001'::UUID;

  -- Ensure fallback defaults if settings table is empty or row does not exist
  v_opening := coalesce(v_opening, '09:00:00'::TIME);
  v_closing := coalesce(v_closing, '20:00:00'::TIME);

  IF p_new_time < v_opening OR v_new_end > v_closing THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'OUTSIDE_HOURS',
      'message', 'The requested slot falls outside clinic operating hours (' || to_char(v_opening, 'HH12:MI AM') || ' - ' || to_char(v_closing, 'HH12:MI AM') || ').'
    );
  END IF;

  IF v_is_today THEN
    v_min_time := (v_clinic_now + interval '1 hour 15 minutes')::TIME;
    IF p_new_time < v_min_time THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'INSUFFICIENT_LEAD_TIME',
        'message', 'Same-day appointments require at least 1 hour 15 minutes lead time.'
      );
    END IF;
  END IF;

  -- 4. Transactional Advisory Locks
  PERFORM pg_advisory_xact_lock(hashtext('appt_dept_lock_' || v_dept || '_' || p_new_date::text));
  IF v_appt.doctor_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('appt_doc_lock_' || v_appt.doctor_id::text || '_' || p_new_date::text));
  END IF;

  -- 5. Doctor & Department Availability Check (Excluding the appointment itself)
  SELECT COUNT(*) INTO v_active_doc_count
  FROM public.department_doctors
  WHERE lower(trim(department)) = v_dept AND is_active = true;

  IF v_active_doc_count = 0 THEN
    v_active_doc_count := 1;
  END IF;

  IF v_appt.doctor_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_doc_conflict
    FROM public.appointments
    WHERE appointment_date = p_new_date
      AND id <> p_appointment_id
      AND doctor_id = v_appt.doctor_id
      AND status NOT IN ('cancelled', 'missed')
      AND appointment_time < v_new_end
      AND (appointment_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > p_new_time;

    SELECT COUNT(*) INTO v_pending_doc_conflict
    FROM public.whatsapp_appointment_requests
    WHERE requested_date = p_new_date
      AND doctor_id = v_appt.doctor_id
      AND status = 'pending_review'
      AND promoted_appointment_id IS NULL
      AND requested_time < v_new_end
      AND (requested_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > p_new_time;

    IF (v_doc_conflict + v_pending_doc_conflict) > 0 THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'SLOT_UNAVAILABLE',
        'message', 'The requested slot is already booked for this doctor. Please choose another time.'
      );
    END IF;
  ELSE
    SELECT (
      (SELECT COUNT(*) FROM public.appointments WHERE appointment_date = p_new_date AND id <> p_appointment_id AND lower(trim(department)) = v_dept AND status NOT IN ('cancelled', 'missed') AND appointment_time < v_new_end AND (appointment_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > p_new_time)
      +
      (SELECT COUNT(*) FROM public.whatsapp_appointment_requests WHERE requested_date = p_new_date AND lower(trim(department)) = v_dept AND status = 'pending_review' AND promoted_appointment_id IS NULL AND requested_time < v_new_end AND (requested_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > p_new_time)
    ) INTO v_total_dept_commitments;

    IF v_total_dept_commitments >= v_active_doc_count THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'SLOT_UNAVAILABLE',
        'message', 'Department capacity reached for this window. Please select another time.'
      );
    END IF;
  END IF;

  -- 6. Fetch patient record for notification & messaging
  SELECT * INTO v_patient FROM public.patients WHERE id = v_appt.patient_id;

  -- 7. Update appointment atomically
  UPDATE public.appointments
  SET appointment_date = p_new_date,
      appointment_time = p_new_time,
      duration_minutes = v_duration,
      status = 'confirmed',
      notes = coalesce(notes || ' ', '') || '[Rescheduled via WhatsApp on ' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ' from ' || to_char(v_appt.appointment_date, 'YYYY-MM-DD') || ' ' || to_char(v_appt.appointment_time, 'HH24:MI') || ']',
      updated_at = now()
  WHERE id = p_appointment_id;

  -- 8. Enqueue WhatsApp confirmation message to patient
  IF v_patient IS NOT NULL AND v_patient.mobile IS NOT NULL AND v_patient.whatsapp_opt_out = false THEN
    v_reschedule_msg := '🔄 *MKES CARE+ Appointment Rescheduled!*' || E'\n\n' ||
      'Dear ' || coalesce(v_patient.name, 'Valued Patient') || E',\n' ||
      'Your ' || upper(v_dept) || ' appointment has been successfully rescheduled.' || E'\n\n' ||
      '📅 *New Date:* ' || to_char(p_new_date, 'DD Mon YYYY') || E'\n' ||
      '⏰ *New Time:* ' || to_char(p_new_time, 'HH12:MI AM') || E'\n' ||
      '👨‍⚕️ *Doctor:* ' || coalesce(v_appt.doctor_name, 'Attending Specialist') || E'\n\n' ||
      '📍 *Location:* MKES Hospital, Malad West.\n' ||
      'Please arrive 10 minutes early.\nReply STOP to unsubscribe.';

    INSERT INTO public.whatsapp_messages_outbox (
      recipient_phone,
      patient_id,
      appointment_id,
      department,
      message_type,
      template_key,
      message_text
    ) VALUES (
      v_patient.mobile,
      v_patient.id,
      p_appointment_id,
      v_dept,
      'rescheduled',
      'rescheduled',
      v_reschedule_msg
    );
  END IF;

  -- 9. Generate in-app notifications for clinic staff & admins
  FOR v_admin_profile IN 
    SELECT id FROM public.profiles WHERE is_active = true AND role IN ('admin', 'staff')
  LOOP
    INSERT INTO public.notifications (
      user_id,
      title,
      message,
      type,
      related_id,
      is_read,
      created_at
    ) VALUES (
      v_admin_profile.id,
      'Appointment Rescheduled via WhatsApp',
      coalesce(v_patient.name, 'Patient') || ' rescheduled their ' || upper(v_dept) || ' appointment to ' || to_char(p_new_date, 'DD Mon') || ' at ' || to_char(p_new_time, 'HH12:MI AM') || '.',
      'appointment_rescheduled',
      p_appointment_id,
      false,
      now()
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', p_appointment_id,
    'new_date', p_new_date,
    'new_time', p_new_time
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. STAFF WHATSAPP OUTBOUND MESSAGING STORED PROCEDURE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID,
  p_department TEXT,
  p_message_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_clean_phone TEXT;
  v_clean_dept TEXT;
  v_is_opted_out BOOLEAN := false;
  v_outbox_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: User not authenticated.');
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only clinic staff or administrators can send WhatsApp messages.');
  END IF;

  v_clean_phone := trim(p_recipient_phone);
  IF length(v_clean_phone) < 10 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid phone number format.');
  END IF;

  IF trim(p_message_text) = '' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Message body cannot be empty.');
  END IF;

  v_clean_dept := lower(trim(coalesce(p_department, 'general')));
  IF v_clean_dept NOT IN ('eye', 'dental', 'general') THEN
    v_clean_dept := 'general';
  END IF;

  -- Check opt-out status
  IF p_patient_id IS NOT NULL THEN
    SELECT whatsapp_opt_out INTO v_is_opted_out FROM public.patients WHERE id = p_patient_id;
  END IF;

  IF v_is_opted_out THEN
    RETURN jsonb_build_object('success', false, 'message', 'Patient has opted out of WhatsApp messages (STOP).');
  END IF;

  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    template_key,
    message_text,
    status
  ) VALUES (
    v_clean_phone,
    p_patient_id,
    v_clean_dept,
    'custom',
    'custom',
    trim(p_message_text),
    'pending'
  ) RETURNING id INTO v_outbox_id;

  RETURN jsonb_build_object('success', true, 'outbox_id', v_outbox_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. EYE SURGERY POST-OPERATIVE FOLLOW-UPS BATCH ENQUEUE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_eye_surgery_followups_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enqueued_count INT := 0;
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_eye_followups')) THEN
    RETURN 0;
  END IF;

  -- Day 1 Post-Op Check (Discharged yesterday)
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    template_key,
    message_text
  )
  SELECT 
    p.mobile,
    p.id,
    'eye',
    'eye_postop',
    'eye_postop',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', this is your Day-1 recovery follow-up from MKES Eye Clinic.\n\nPlease remember to administer your prescribed post-operative eye drops and wear your protective eye shield as instructed by your surgeon. If you experience severe redness, sudden loss of vision, or sharp pain, please contact our clinic immediately.\nReply STOP to unsubscribe.'
  FROM public.eye_surgeries s
  JOIN public.patients p ON p.id = s.patient_id
  WHERE p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
    AND length(trim(p.mobile)) >= 10
    AND s.status = 'discharged'
    AND (s.discharged_at AT TIME ZONE 'Asia/Kolkata')::DATE = (v_clinic_today - interval '1 day')::DATE
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'eye_postop' AND o.created_at >= (now() - interval '3 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. EYE LAB NOTIFICATIONS BATCH ENQUEUE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_eye_lab_notifications_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enqueued_count INT := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_eye_lab')) THEN
    RETURN 0;
  END IF;

  -- Eye Lab / Custom IOL ready for scheduled surgery
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    template_key,
    message_text
  )
  SELECT 
    p.mobile,
    p.id,
    'eye',
    'eye_lab_ready',
    'eye_lab_ready',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', your custom intraocular lens / ophthalmic appliance for your upcoming procedure has arrived at MKES Eye Clinic and is prepared for your scheduled surgery.\n\nPlease contact our desk if you have any questions.\nReply STOP to unsubscribe.'
  FROM public.eye_surgeries s
  JOIN public.patients p ON p.id = s.patient_id
  WHERE p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
    AND length(trim(p.mobile)) >= 10
    AND s.iol_details IS NOT NULL
    AND s.iol_details ~* '(ready|received|in stock|prepared)'
    AND s.status IN ('scheduled', 'pre_op')
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'eye_lab_ready' AND o.created_at >= (now() - interval '14 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. PERMISSIONS (LEAST PRIVILEGE)
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.user_device_tokens FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_device_tokens TO authenticated;
GRANT ALL ON TABLE public.user_device_tokens TO service_role;

REVOKE ALL ON FUNCTION public.reschedule_appointment_via_whatsapp(UUID, DATE, TIME, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment_via_whatsapp(UUID, DATE, TIME, INT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.enqueue_eye_surgery_followups_batch() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_eye_surgery_followups_batch() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_eye_surgery_followups_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_eye_lab_notifications_batch() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_eye_lab_notifications_batch() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_eye_lab_notifications_batch() TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';


