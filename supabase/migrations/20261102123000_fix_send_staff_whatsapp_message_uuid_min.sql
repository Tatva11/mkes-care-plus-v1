-- Fix send_staff_whatsapp_message min(id) uuid aggregate issue
DROP FUNCTION IF EXISTS public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.send_staff_whatsapp_message(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID DEFAULT NULL,
  p_department TEXT DEFAULT 'general',
  p_message_text TEXT DEFAULT '',
  p_media_url TEXT DEFAULT NULL,
  p_template_key TEXT DEFAULT 'custom',
  p_message_type TEXT DEFAULT 'custom',
  p_scheduled_for TIMESTAMPTZ DEFAULT now(),
  p_appointment_id UUID DEFAULT NULL
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
  v_ten_digits TEXT;
  v_clean_dept TEXT;
  v_patient_record RECORD;
  v_patient_clean_mobile TEXT;
  v_match_count INT := 0;
  v_resolved_patient_id UUID := p_patient_id;
  v_is_opted_out BOOLEAN := false;
  v_outbox_id UUID;
BEGIN
  -- 1. Server-side identity & role guard (NULL-safe check)
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: User not authenticated.');
    END IF;

    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only clinic staff or administrators can send WhatsApp messages.');
    END IF;
  END IF;

  -- 2. Normalize recipient phone: extract 10-digit national number
  v_ten_digits := public.normalize_phone_10(p_recipient_phone);
  IF v_ten_digits IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid phone number format: must contain at least 10 valid digits.');
  END IF;
  v_clean_phone := regexp_replace(coalesce(p_recipient_phone, ''), '[^0-9]', '', 'g');

  IF trim(coalesce(p_message_text, '')) = '' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Message body cannot be empty.');
  END IF;

  v_clean_dept := lower(trim(coalesce(p_department, 'general')));
  IF v_clean_dept NOT IN ('eye', 'dental', 'general') THEN
    v_clean_dept := 'general';
  END IF;

  -- 3. Recipient Validation: If patient ID is explicitly provided, verify phone belongs to patient
  IF p_patient_id IS NOT NULL THEN
    SELECT * INTO v_patient_record FROM public.patients WHERE id = p_patient_id;
    IF v_patient_record IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Patient record not found for the specified patient ID.');
    END IF;

    v_patient_clean_mobile := public.normalize_phone_10(v_patient_record.mobile);
    IF v_patient_clean_mobile IS NULL OR v_patient_clean_mobile <> v_ten_digits THEN
      RETURN jsonb_build_object(
        'success', false, 
        'message', 'Recipient phone mismatch: The provided phone number does not match the registered mobile for this patient.'
      );
    END IF;

    IF v_patient_record.whatsapp_opt_out = true THEN
      RETURN jsonb_build_object('success', false, 'message', 'Patient has opted out of WhatsApp messages (STOP).');
    END IF;

    v_resolved_patient_id := p_patient_id;

  -- 4. Automatic binding if patient ID was NOT provided: exact 10-digit match with safe ambiguity failure
  ELSE
    SELECT count(*), min(id::text)::uuid, bool_or(whatsapp_opt_out)
    INTO v_match_count, v_resolved_patient_id, v_is_opted_out
    FROM public.patients
    WHERE public.normalize_phone_10(mobile) = v_ten_digits;

    IF v_match_count = 0 THEN
      -- Unknown recipient / inquiry: allow sending with patient_id = NULL without auto-creating patient record
      v_resolved_patient_id := NULL;
    ELSIF v_match_count > 1 THEN
      RETURN jsonb_build_object(
        'success', false, 
        'message', 'Ambiguous recipient: multiple registered patients share this phone number. Please specify the exact patient ID.'
      );
    END IF;

    IF coalesce(v_is_opted_out, false) THEN
      RETURN jsonb_build_object('success', false, 'message', 'Patient has opted out of WhatsApp messages (STOP).');
    END IF;
  END IF;

  -- 5. Additional check across all patient records with this 10-digit number for any STOP opt-out
  IF EXISTS (
    SELECT 1 FROM public.patients 
    WHERE public.normalize_phone_10(mobile) = v_ten_digits
      AND whatsapp_opt_out = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Patient has opted out of WhatsApp messages (STOP).');
  END IF;

  -- 6. Insert message into transactional outbox
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    appointment_id,
    department,
    message_type,
    template_key,
    media_url,
    message_text,
    status,
    scheduled_for,
    created_by
  ) VALUES (
    v_clean_phone,
    v_resolved_patient_id,
    p_appointment_id,
    v_clean_dept,
    coalesce(p_message_type, 'custom'),
    coalesce(p_template_key, 'custom'),
    p_media_url,
    trim(p_message_text),
    'pending',
    coalesce(p_scheduled_for, now()),
    v_caller_id
  ) RETURNING id INTO v_outbox_id;

  RETURN jsonb_build_object('success', true, 'outbox_id', v_outbox_id);
END;
$$;

-- Provide Flutter and staff with convenient 7-arg and 4-arg overloads
CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID,
  p_department TEXT,
  p_message_text TEXT,
  p_media_url TEXT,
  p_template_key TEXT,
  p_message_type TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.send_staff_whatsapp_message(
    p_recipient_phone,
    p_patient_id,
    p_department,
    p_message_text,
    p_media_url,
    p_template_key,
    p_message_type,
    now(),
    NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID,
  p_department TEXT,
  p_message_text TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.send_staff_whatsapp_message(
    p_recipient_phone,
    p_patient_id,
    p_department,
    p_message_text,
    NULL,
    'custom',
    'custom',
    now(),
    NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_message_text TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.send_staff_whatsapp_message(
    p_recipient_phone,
    NULL,
    'general',
    p_message_text,
    NULL,
    'custom',
    'custom',
    now(),
    NULL
  );
$$;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, TEXT) TO authenticated, service_role;
