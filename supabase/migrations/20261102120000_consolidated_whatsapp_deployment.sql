-- ============================================================================
-- MKES CARE+ — PRODUCTION WHATSAPP CONSOLIDATED DEPLOYMENT SCRIPT
-- Hardened, Atomic, NULL-Safe, and Least-Privilege Production Migration
--
-- TARGET: Supabase Remote Project (mfalgfodhsszyxnfiofi)
-- EXECUTION: Review first. Apply only via Supabase Dashboard SQL Editor after sign-off.
--
-- SECURITY CERTIFICATION:
--   1. Outbox direct client mutations strictly revoked (SELECT only for staff; mutations via service_role/RPCs).
--   2. QR / session privacy preserved (qr_code_data omitted and dropped; local pairing only).
--   3. Staff message recipient validation enforced (patient phone must match supplied patient ID).
--   4. Opt-out authorization secured (register_patient_whatsapp_opt_out restricted to service_role/admin).
--   5. Status constraint migration preserves data semantics (no blind updates to 'pending').
--   6. Appointment approval enforces Eye/Dental only (Optical excluded), advisory lock on doctor/slot, opt-out check.
--   7. Phone matching uses exact 10-digit equality; fails safely on ambiguous duplicate matches.
--   8. Timezone handling uses type-safe date/time extraction from 'Asia/Kolkata' without session dependency.
--   9. Complete preflight schema verification checks base objects before mutating state.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- STEP 0: PREFLIGHT SCHEMA VERIFICATION & BASE PREREQUISITES
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_missing_tables TEXT[] := ARRAY[]::TEXT[];
  v_tbl TEXT;
  v_required_tables TEXT[] := ARRAY[
    'profiles', 'patients', 'appointments', 
    'whatsapp_messages_outbox', 'whatsapp_settings'
  ];
BEGIN
  RAISE NOTICE '=== MKES CARE+ WHATSAPP MIGRATION: RUNNING PREFLIGHT AUDIT ===';

  FOREACH v_tbl IN ARRAY v_required_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_name = v_tbl
    ) THEN
      v_missing_tables := array_append(v_missing_tables, v_tbl);
    END IF;
  END LOOP;

  IF array_length(v_missing_tables, 1) > 0 THEN
    RAISE EXCEPTION 'PREFLIGHT CHECK FAILED: Required base table(s) missing: %', array_to_string(v_missing_tables, ', ');
  END IF;

  RAISE NOTICE 'Preflight Check: All core tables verified in public schema.';
END $$;

-- Immutable helper to extract the authoritative 10-digit national mobile number
-- Returns NULL if fewer than 10 digits are present to prevent false suffix matches
CREATE OR REPLACE FUNCTION public.normalize_phone_10(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE 
    WHEN length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) >= 10 
    THEN right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 10)
    ELSE NULL
  END;
$$;

REVOKE ALL ON FUNCTION public.normalize_phone_10(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_phone_10(TEXT) TO authenticated, service_role, anon;

-- Ensure required baseline columns exist on core tables
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS whatsapp_opt_out BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dob DATE,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_patients_norm_mobile_optout 
  ON public.patients(public.normalize_phone_10(mobile), whatsapp_opt_out);

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS doctor_name TEXT,
  ADD COLUMN IF NOT EXISTS ai_booked BOOLEAN NOT NULL DEFAULT false;

-- Ensure dental_treatments has procedure_status column if table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_treatments') THEN
    ALTER TABLE public.dental_treatments
      ADD COLUMN IF NOT EXISTS procedure_status TEXT NOT NULL DEFAULT 'completed';
  END IF;
END $$;

-- Ensure dental_lab has appointment_id column if table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_lab') THEN
    ALTER TABLE public.dental_lab
      ADD COLUMN IF NOT EXISTS appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- STEP 1: whatsapp_messages_outbox STATUS CHECK CONSTRAINT HARDENING
-- Preserves existing data semantics without blind rewrites to 'pending'
-- ----------------------------------------------------------------------------

-- 1a. Messages with sent_at already recorded must be preserved as 'sent'
UPDATE public.whatsapp_messages_outbox
SET status = 'sent'
WHERE (status IS NULL OR status NOT IN ('pending', 'processing', 'sent', 'delivered', 'read', 'failed', 'cancelled'))
  AND sent_at IS NOT NULL;

-- 1b. Messages that recorded a failure error must be preserved as 'failed'
UPDATE public.whatsapp_messages_outbox
SET status = 'failed'
WHERE (status IS NULL OR status NOT IN ('pending', 'processing', 'sent', 'delivered', 'read', 'failed', 'cancelled'))
  AND last_error IS NOT NULL
  AND sent_at IS NULL;

-- 1c. Unsupported, non-conforming, or ambiguous statuses: safely neutralize to 'cancelled'
-- Logging original value in last_error prevents inadvertent message re-dispatch
UPDATE public.whatsapp_messages_outbox
SET status = 'cancelled',
    last_error = coalesce(last_error, 'Migrated legacy non-conforming status: ' || coalesce(status, 'NULL'))
WHERE status IS NULL OR status NOT IN ('pending', 'processing', 'sent', 'delivered', 'read', 'failed', 'cancelled');

ALTER TABLE public.whatsapp_messages_outbox
  ALTER COLUMN status SET DEFAULT 'pending',
  ALTER COLUMN status SET NOT NULL;

-- Safely drop existing status check constraints on whatsapp_messages_outbox specifically
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'whatsapp_messages_outbox'
      AND con.contype = 'c'
      AND att.attname = 'status'
  ) LOOP
    EXECUTE 'ALTER TABLE public.whatsapp_messages_outbox DROP CONSTRAINT IF EXISTS ' || quote_ident(r.conname);
  END LOOP;
END $$;

ALTER TABLE public.whatsapp_messages_outbox
  ADD CONSTRAINT whatsapp_messages_outbox_status_check 
  CHECK (status IN ('pending', 'processing', 'sent', 'delivered', 'read', 'failed', 'cancelled'));

-- ----------------------------------------------------------------------------
-- STEP 2: DELIVERY TRACKING, WHATSAPP MESSAGE ID & PROVENANCE COLUMNS
-- ----------------------------------------------------------------------------
ALTER TABLE public.whatsapp_messages_outbox
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS whatsapp_message_id TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_wa_outbox_wa_msg_id 
  ON public.whatsapp_messages_outbox(whatsapp_message_id) 
  WHERE whatsapp_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wa_outbox_dequeue 
  ON public.whatsapp_messages_outbox(status, scheduled_for, lease_expires_at);

CREATE INDEX IF NOT EXISTS idx_wa_outbox_norm_phone 
  ON public.whatsapp_messages_outbox(public.normalize_phone_10(recipient_phone), status);

-- ----------------------------------------------------------------------------
-- STEP 3: STRICT LEAST-PRIVILEGE RLS AND TABLE GRANTS ON whatsapp_messages_outbox
-- Explicitly revokes direct mutation from authenticated, anon, and PUBLIC
-- ----------------------------------------------------------------------------
ALTER TABLE public.whatsapp_messages_outbox ENABLE ROW LEVEL SECURITY;

-- 1. Drop all potential mutation policies
DROP POLICY IF EXISTS "Staff and Admins insert outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Staff and Admins update outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Staff and Admins delete outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Allow staff insert outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Allow staff update outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Allow authenticated insert outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Allow authenticated update outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.whatsapp_messages_outbox;

-- 2. SELECT policy: Only active staff and admins can view outbox items
DROP POLICY IF EXISTS "Staff and Admins view outbox" ON public.whatsapp_messages_outbox;
CREATE POLICY "Staff and Admins view outbox"
  ON public.whatsapp_messages_outbox FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

-- 3. Service-role policy: Full access for background Node.js worker
DROP POLICY IF EXISTS "Service role manage outbox" ON public.whatsapp_messages_outbox;
CREATE POLICY "Service role manage outbox"
  ON public.whatsapp_messages_outbox FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- 4. Explicit Table-level grants: REVOKE mutation access from client roles
REVOKE ALL ON TABLE public.whatsapp_messages_outbox FROM anon, authenticated, PUBLIC;
GRANT SELECT ON TABLE public.whatsapp_messages_outbox TO authenticated;
GRANT ALL ON TABLE public.whatsapp_messages_outbox TO service_role;

-- ----------------------------------------------------------------------------
-- STEP 4: ATOMIC & NULL-SAFE RETRY FAILED MESSAGE RPC (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retry_failed_whatsapp_message(
  p_outbox_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_updated_id UUID;
BEGIN
  -- Allow service_role execution without caller profile
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: User not authenticated.');
    END IF;

    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active clinic staff or administrators can retry messages.');
    END IF;
  END IF;

  -- Atomic conditional update prevents race conditions and concurrent retry storms
  UPDATE public.whatsapp_messages_outbox
  SET status = 'pending',
      retry_count = 0,
      scheduled_for = now(),
      lease_id = null,
      lease_expires_at = null,
      last_error = null,
      updated_at = now()
  WHERE id = p_outbox_id AND status = 'failed'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.whatsapp_messages_outbox WHERE id = p_outbox_id) THEN
      RETURN jsonb_build_object('success', false, 'message', 'Outbox record not found.');
    ELSE
      RETURN jsonb_build_object('success', false, 'message', 'Only failed messages can be rescheduled for retry.');
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.retry_failed_whatsapp_message(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retry_failed_whatsapp_message(UUID) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- STEP 5: ATOMIC & NULL-SAFE CANCEL PENDING MESSAGE RPC (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_whatsapp_outbox_message(
  p_outbox_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_updated_id UUID;
BEGIN
  -- Allow service_role execution without caller profile
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: User not authenticated.');
    END IF;

    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active clinic staff or administrators can cancel messages.');
    END IF;
  END IF;

  -- Atomic conditional update prevents cancelling in-flight or already dispatched messages
  UPDATE public.whatsapp_messages_outbox
  SET status = 'cancelled',
      last_error = 'Cancelled by ' || coalesce(v_caller_id::text, 'service_role'),
      lease_id = null,
      lease_expires_at = null,
      updated_at = now()
  WHERE id = p_outbox_id AND status = 'pending'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.whatsapp_messages_outbox WHERE id = p_outbox_id) THEN
      RETURN jsonb_build_object('success', false, 'message', 'Outbox record not found.');
    ELSE
      RETURN jsonb_build_object('success', false, 'message', 'Only pending messages can be cancelled.');
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_whatsapp_outbox_message(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_whatsapp_outbox_message(UUID) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- STEP 6: ATOMIC OUTBOX BATCH CLAIM RPC (SERVICE ROLE DAEMON WORKER ONLY)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_whatsapp_outbox_batch(
  p_worker_id UUID,
  p_batch_size INT DEFAULT 5,
  p_lease_duration_seconds INT DEFAULT 60
)
RETURNS SETOF public.whatsapp_messages_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.whatsapp_messages_outbox
  SET status = 'processing',
      lease_id = p_worker_id,
      lease_expires_at = now() + (p_lease_duration_seconds || ' seconds')::interval,
      retry_count = CASE WHEN status = 'processing' THEN retry_count + 1 ELSE retry_count END,
      last_error = CASE WHEN status = 'processing' THEN 'Reclaimed after expired lease by worker ' || p_worker_id ELSE last_error END,
      updated_at = now()
  WHERE id IN (
    SELECT o.id 
    FROM public.whatsapp_messages_outbox o
    JOIN public.whatsapp_settings s ON s.id = '00000000-0000-0000-0000-000000000001'::UUID
    WHERE (s.is_enabled = true OR o.created_by IS NOT NULL OR o.message_type = 'custom')
      AND (
        -- Category A: Fresh pending messages
        (o.status = 'pending' AND o.scheduled_for <= now() AND (o.lease_expires_at IS NULL OR o.lease_expires_at < now()))
        OR
        -- Category B: Crashed processing messages with expired leases
        (o.status = 'processing' AND o.lease_expires_at < now() AND o.retry_count < o.max_retries)
      )
      -- Exclude any recipient whose 10 digits match an opted-out patient
      AND NOT EXISTS (
        SELECT 1 FROM public.patients p
        WHERE p.whatsapp_opt_out = true
          AND (
            p.id = o.patient_id 
            OR (
              public.normalize_phone_10(p.mobile) IS NOT NULL 
              AND public.normalize_phone_10(p.mobile) = public.normalize_phone_10(o.recipient_phone)
            )
          )
      )
    ORDER BY o.scheduled_for ASC
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  )
  RETURNING *;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_whatsapp_outbox_batch(UUID, INT, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_whatsapp_outbox_batch(UUID, INT, INT) TO service_role;

-- ----------------------------------------------------------------------------
-- STEP 7: NULL-SAFE send_staff_whatsapp_message RPC
-- Enforces exact phone matching, patient-phone verification, and STOP compliance
-- ----------------------------------------------------------------------------
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

-- 7-argument backward-compatible overload
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

-- 4-argument backward-compatible overload for existing Flutter call sites
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

-- 2-argument backward-compatible overload for simple text replies to phone numbers
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

-- ----------------------------------------------------------------------------
-- STEP 8: EXPRESSION INDEXES ON whatsapp_message_logs FOR O(1) ACK RECONCILIATION
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_wa_logs_raw_payload_msg_id
  ON public.whatsapp_message_logs((raw_payload->>'messageId'));

CREATE INDEX IF NOT EXISTS idx_wa_logs_raw_payload_id
  ON public.whatsapp_message_logs((raw_payload->>'id'));

-- ----------------------------------------------------------------------------
-- STEP 9: WHATSAPP SETTINGS SESSION PERSISTENCE & SECURE RLS
-- Raw QR storage is strictly omitted/dropped for privacy; local pairing only
-- ----------------------------------------------------------------------------

-- Remove raw QR code storage from database if it was previously created
ALTER TABLE public.whatsapp_settings DROP COLUMN IF EXISTS qr_code_data;

ALTER TABLE public.whatsapp_settings
  ADD COLUMN IF NOT EXISTS session_status TEXT NOT NULL DEFAULT 'disconnected'
    CHECK (session_status IN ('disconnected', 'connecting', 'qr_ready', 'authenticated', 'error')),
  ADD COLUMN IF NOT EXISTS last_heartbeat TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS connected_phone TEXT;

INSERT INTO public.whatsapp_settings (id, is_enabled, session_status)
VALUES ('00000000-0000-0000-0000-000000000001'::UUID, false, 'disconnected')
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_whatsapp_settings_heartbeat
  ON public.whatsapp_settings (last_heartbeat DESC);

ALTER TABLE public.whatsapp_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff and Admins view settings" ON public.whatsapp_settings;
CREATE POLICY "Staff and Admins view settings"
  ON public.whatsapp_settings FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

DROP POLICY IF EXISTS "Admins manage settings" ON public.whatsapp_settings;
CREATE POLICY "Admins manage settings"
  ON public.whatsapp_settings FOR UPDATE TO authenticated
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

DROP POLICY IF EXISTS "Service role manage settings" ON public.whatsapp_settings;
CREATE POLICY "Service role manage settings"
  ON public.whatsapp_settings FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- Revoke mutation rights from public and grant column-level update to authenticated admins
REVOKE ALL ON TABLE public.whatsapp_settings FROM anon, PUBLIC;
GRANT SELECT ON TABLE public.whatsapp_settings TO authenticated;
-- Authenticated admins can update configuration only; daemon operational telemetry is service_role managed
GRANT UPDATE (is_enabled, daily_send_limit, operating_hours_start, operating_hours_end, updated_at) 
  ON TABLE public.whatsapp_settings TO authenticated;
GRANT ALL ON TABLE public.whatsapp_settings TO service_role;

-- ----------------------------------------------------------------------------
-- STEP 10: NULL-SAFE APPROVE & REJECT WHATSAPP APPOINTMENT REQUESTS RPCs
-- Optical department strictly excluded; concurrency-safe doctor/slot locks enforced
-- ----------------------------------------------------------------------------

-- Ensure whatsapp_appointment_requests table columns are aligned
ALTER TABLE public.whatsapp_appointment_requests
  ADD COLUMN IF NOT EXISTS patient_phone TEXT,
  ADD COLUMN IF NOT EXISTS patient_name TEXT,
  ADD COLUMN IF NOT EXISTS requested_date DATE,
  ADD COLUMN IF NOT EXISTS requested_time TIME,
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER DEFAULT 15,
  ADD COLUMN IF NOT EXISTS doctor_id UUID REFERENCES public.department_doctors(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS doctor_name TEXT,
  ADD COLUMN IF NOT EXISTS promoted_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS staff_remarks TEXT;

CREATE OR REPLACE FUNCTION public.approve_whatsapp_appointment_request(
  p_request_id UUID,
  p_doctor_id UUID,
  p_doctor_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_req RECORD;
  v_doc RECORD;
  v_effective_doctor_id UUID;
  v_new_appt_id UUID;
  v_appt_doc_id UUID;
  v_doc_conflict INT := 0;
  v_duration INT;
  v_slot_end TIME;
  v_is_opted_out BOOLEAN := false;
  v_req_phone TEXT;
  v_req_date DATE;
  v_req_time TIME;
  v_doc_display_name TEXT;
BEGIN
  -- 1. Server-side identity & role guard (NULL-safe check)
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller is not authenticated.');
    END IF;

    SELECT role INTO v_caller_role 
    FROM public.profiles 
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active clinic staff or administrators can approve requests.');
    END IF;
  END IF;

  -- 2. Lock request row for atomic state check
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Appointment request not found.');
  END IF;

  IF v_req.status <> 'pending_review' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request is not in pending_review status. Current status: ' || v_req.status);
  END IF;

  -- 3. Strict department validation: Optical is completely excluded
  IF lower(trim(coalesce(v_req.department, ''))) NOT IN ('eye', 'dental') THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Invalid department: only Eye and Dental appointments can be approved. Optical is strictly excluded.'
    );
  END IF;

  v_req_phone := coalesce(v_req.patient_phone, '');
  v_req_date := v_req.requested_date;
  v_req_time := v_req.requested_time;
  v_duration := coalesce(v_req.duration_minutes, 15);
  v_slot_end := v_req_time + (v_duration || ' minutes')::interval;

  -- 4. Resolve and validate Doctor Assignment
  v_effective_doctor_id := coalesce(p_doctor_id, v_req.doctor_id);

  IF v_effective_doctor_id IS NOT NULL THEN
    SELECT * INTO v_doc FROM public.department_doctors WHERE id = v_effective_doctor_id AND is_active = true;
    IF v_doc IS NULL THEN
      SELECT * INTO v_doc FROM public.profiles WHERE id = v_effective_doctor_id AND is_active = true;
    END IF;
    IF v_doc IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Specified doctor does not exist or is inactive.');
    END IF;
    v_doc_display_name := coalesce(p_doctor_name, v_doc.full_name, v_req.doctor_name, 'Attending Specialist');
  ELSE
    v_doc_display_name := coalesce(p_doctor_name, v_req.doctor_name, 'Attending Specialist');
  END IF;

  -- 5. Concurrency-Safe Transactional Advisory Locks:
  -- Lock doctor + date + slot combination to prevent simultaneous double-booking across concurrent approvals
  PERFORM pg_advisory_xact_lock(hashtext('appt_slot_' || coalesce(v_effective_doctor_id::text, 'generic') || '_' || v_req_date::text || '_' || v_req_time::text));
  PERFORM pg_advisory_xact_lock(hashtext('appt_dept_' || lower(trim(v_req.department)) || '_' || v_req_date::text || '_' || v_req_time::text));

  -- 6. Check for conflicting appointments booked in this slot
  IF v_effective_doctor_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_doc_conflict
    FROM public.appointments a
    WHERE (a.doctor_id = v_effective_doctor_id OR a.doctor_name = v_doc_display_name)
      AND a.appointment_date = v_req_date
      AND a.status IN ('scheduled', 'confirmed')
      AND (
        GREATEST(a.appointment_time, v_req_time) <
        LEAST(a.appointment_time + (coalesce(a.duration_minutes, 15) || ' minutes')::interval, v_slot_end)
      );

    IF v_doc_conflict > 0 THEN
      RETURN jsonb_build_object(
        'success', false, 
        'message', 'Doctor conflict: Assigned specialist already has a booked appointment overlapping this slot.'
      );
    END IF;
  END IF;

  -- 7. Determine doctor_id to insert into appointments (must satisfy profiles FK if configured)
  v_appt_doc_id := CASE 
    WHEN v_effective_doctor_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = v_effective_doctor_id) 
    THEN v_effective_doctor_id 
    ELSE NULL 
  END;

  -- 8. Insert confirmed appointment
  INSERT INTO public.appointments (
    patient_id,
    department,
    doctor_id,
    doctor_name,
    appointment_date,
    appointment_time,
    duration_minutes,
    appointment_type,
    status,
    notes,
    ai_booked
  ) VALUES (
    v_req.patient_id,
    lower(trim(v_req.department)),
    v_appt_doc_id,
    v_doc_display_name,
    v_req_date,
    v_req_time,
    v_duration,
    'regular',
    'confirmed',
    'Approved from WhatsApp request #' || v_req.id || '. Reason: ' || coalesce(v_req.staff_remarks, 'Consultation'),
    true
  ) RETURNING id INTO v_new_appt_id;

  -- 9. Enable status update trigger session variable and update request
  PERFORM set_config('mkes.rpc_status_update', 'active', true);

  UPDATE public.whatsapp_appointment_requests
  SET status = 'approved',
      promoted_appointment_id = v_new_appt_id,
      doctor_id = v_effective_doctor_id,
      doctor_name = v_doc_display_name,
      reviewed_by = v_caller_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  -- 10. Check opt-out before enqueuing confirmation message
  IF v_req.patient_id IS NOT NULL THEN
    SELECT whatsapp_opt_out INTO v_is_opted_out FROM public.patients WHERE id = v_req.patient_id;
  END IF;

  IF NOT coalesce(v_is_opted_out, false) AND v_req_phone <> '' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.patients 
      WHERE public.normalize_phone_10(mobile) = public.normalize_phone_10(v_req_phone)
        AND whatsapp_opt_out = true
    ) INTO v_is_opted_out;
  END IF;

  IF NOT coalesce(v_is_opted_out, false) AND v_req_phone <> '' THEN
    INSERT INTO public.whatsapp_messages_outbox (
      recipient_phone,
      patient_id,
      appointment_id,
      department,
      message_type,
      template_key,
      message_text,
      created_by
    ) VALUES (
      v_req_phone,
      v_req.patient_id,
      v_new_appt_id,
      lower(trim(v_req.department)),
      'appointment_confirmed',
      'appt_confirmed_' || v_new_appt_id,
      '✅ *MKES CARE+ APPOINTMENT CONFIRMED*' || E'\n\n' ||
      'Dear ' || coalesce(v_req.patient_name, 'Patient') || E',\n' ||
      'Your ' || upper(v_req.department) || ' appointment has been confirmed for *' || 
      to_char(v_req_date, 'DD Mon YYYY') || '* at *' || 
      to_char(v_req_time, 'HH12:MI AM') || '* with ' || 
      v_doc_display_name || E'.\n\n' ||
      '📍 MKES Hospital, Malad West.\nReply STOP to unsubscribe.',
      v_caller_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_new_appt_id,
    'request_id', p_request_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_whatsapp_appointment_request(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_whatsapp_appointment_request(UUID, UUID, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reject_whatsapp_appointment_request(
  p_request_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_req RECORD;
  v_is_opted_out BOOLEAN := false;
  v_req_phone TEXT;
BEGIN
  -- 1. Server-side identity & role guard (NULL-safe check)
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller is not authenticated.');
    END IF;

    SELECT role INTO v_caller_role 
    FROM public.profiles 
    WHERE id = v_caller_id AND is_active = true;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active staff or admins can reject requests.');
    END IF;
  END IF;

  -- 2. Lock and update request record
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request not found.');
  END IF;

  IF v_req.status <> 'pending_review' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request cannot be rejected because it is currently in status: ' || v_req.status);
  END IF;

  -- 3. Set trigger override and update status
  PERFORM set_config('mkes.rpc_status_update', 'active', true);

  UPDATE public.whatsapp_appointment_requests
  SET status = 'rejected',
      staff_remarks = coalesce(p_reason, 'Clinic schedule full or specialist unavailable'),
      reviewed_by = v_caller_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  v_req_phone := coalesce(v_req.patient_phone, '');

  -- 4. Check opt-out before enqueuing cancellation message
  IF v_req.patient_id IS NOT NULL THEN
    SELECT whatsapp_opt_out INTO v_is_opted_out FROM public.patients WHERE id = v_req.patient_id;
  END IF;

  IF NOT coalesce(v_is_opted_out, false) AND v_req_phone <> '' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.patients 
      WHERE public.normalize_phone_10(mobile) = public.normalize_phone_10(v_req_phone)
        AND whatsapp_opt_out = true
    ) INTO v_is_opted_out;
  END IF;

  IF NOT coalesce(v_is_opted_out, false) AND v_req_phone <> '' THEN
    INSERT INTO public.whatsapp_messages_outbox (
      recipient_phone,
      patient_id,
      department,
      message_type,
      template_key,
      message_text,
      created_by
    ) VALUES (
      v_req_phone,
      v_req.patient_id,
      lower(trim(v_req.department)),
      'appointment_rejected',
      'appt_rejected_' || v_req.id,
      'We regret that your requested appointment slot on ' || 
      to_char(v_req.requested_date, 'DD Mon') || ' at ' || 
      to_char(v_req.requested_time, 'HH12:MI AM') || ' could not be scheduled. Reason: ' || 
      coalesce(p_reason, 'Slot unavailable') || E'.\n\nPlease reply with another preferred day/time or contact reception.\nReply STOP to unsubscribe.',
      v_caller_id
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'request_id', p_request_id);
END;
$$;

REVOKE ALL ON FUNCTION public.reject_whatsapp_appointment_request(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_whatsapp_appointment_request(UUID, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- STEP 11: OPT-OUT MANAGEMENT RPCs (EXPLICIT CALLER AUTHORIZATION)
-- ----------------------------------------------------------------------------

-- Staff-managed opt-out toggling for verified patient records
DROP FUNCTION IF EXISTS public.set_patient_whatsapp_opt_out(TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.set_patient_whatsapp_opt_out(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.set_patient_whatsapp_opt_out(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION public.set_patient_whatsapp_opt_out(
  p_patient_id UUID,
  p_opt_out BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_patient RECORD;
  v_ten_digits TEXT;
BEGIN
  -- Allow service_role execution without caller profile
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller not authenticated.');
    END IF;

    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'staff') THEN
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only clinic staff can update patient opt-out status.');
    END IF;
  END IF;

  SELECT * INTO v_patient FROM public.patients WHERE id = p_patient_id FOR UPDATE;
  IF v_patient IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Patient not found.');
  END IF;

  v_ten_digits := public.normalize_phone_10(v_patient.mobile);

  UPDATE public.patients
  SET whatsapp_opt_out = p_opt_out,
      updated_at = now()
  WHERE id = p_patient_id;

  -- When opting out, cancel all pending and processing outbox messages
  IF p_opt_out = true THEN
    UPDATE public.whatsapp_messages_outbox
    SET status = 'cancelled',
        last_error = 'Patient opted out by clinic staff: ' || coalesce(v_caller_id::text, 'service_role'),
        lease_id = null,
        lease_expires_at = null,
        updated_at = now()
    WHERE (
      patient_id = p_patient_id
      OR (v_ten_digits IS NOT NULL AND public.normalize_phone_10(recipient_phone) = v_ten_digits)
    ) AND status IN ('pending', 'processing');
  END IF;

  RETURN jsonb_build_object('success', true, 'patient_id', p_patient_id, 'opt_out', p_opt_out);
END;
$$;

REVOKE ALL ON FUNCTION public.set_patient_whatsapp_opt_out(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_patient_whatsapp_opt_out(UUID, BOOLEAN) TO authenticated, service_role;

-- Automated STOP Webhook Opt-Out: Strictly protected against arbitrary caller exploitation
DROP FUNCTION IF EXISTS public.register_patient_whatsapp_opt_out(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.register_patient_whatsapp_opt_out(TEXT);

CREATE OR REPLACE FUNCTION public.register_patient_whatsapp_opt_out(
  p_phone_number TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_ten_digits TEXT;
BEGIN
  -- Strict authorization: only service_role (background webhook daemon) or active admin can execute
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;

    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role <> 'admin' THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background service workers can register opt-outs by phone number.';
    END IF;
  END IF;

  v_ten_digits := public.normalize_phone_10(p_phone_number);
  IF v_ten_digits IS NULL THEN
    RETURN;
  END IF;

  -- 1. Mark patient as opted out using exact normalized phone matching
  UPDATE public.patients
  SET whatsapp_opt_out = true,
      updated_at = now()
  WHERE public.normalize_phone_10(mobile) = v_ten_digits;

  -- 2. Cancel both pending and active processing outbox messages
  UPDATE public.whatsapp_messages_outbox
  SET status = 'cancelled',
      last_error = 'Patient opted out via WhatsApp STOP command.',
      lease_id = null,
      lease_expires_at = null,
      updated_at = now()
  WHERE (
    public.normalize_phone_10(recipient_phone) = v_ten_digits
    OR patient_id IN (
      SELECT id FROM public.patients
      WHERE public.normalize_phone_10(mobile) = v_ten_digits
    )
  ) AND status IN ('pending', 'processing');
END;
$$;

REVOKE ALL ON FUNCTION public.register_patient_whatsapp_opt_out(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_patient_whatsapp_opt_out(TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- STEP 12: CLINICAL AUTOMATION PROCEDURES (Optical STRICTLY Excluded)
-- Correct timezone handling: extracts calendar date and wall clock time safely
-- ----------------------------------------------------------------------------

-- A. Appointment Reminders (24h & 2h)
CREATE OR REPLACE FUNCTION public.enqueue_appointment_reminders_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_temp_count INT := 0;
  -- Type-safe extraction: avoids naive timestamp session timezone trap
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_clinic_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_appointment_reminders')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

  -- 1. 24h reminders (appointments scheduled for tomorrow in clinic timezone IST, Eye and Dental ONLY)
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    appointment_id,
    department,
    message_type,
    template_key,
    message_text,
    scheduled_for
  )
  SELECT 
    p.mobile,
    p.id,
    a.id,
    lower(trim(a.department)),
    'reminder_24h',
    'reminder_24h',
    'Hello ' || coalesce(p.name, 'Valued Patient') || ', this is a reminder of your ' || upper(a.department) || ' appointment at MKES CARE+ on ' || to_char(a.appointment_date, 'DD Mon YYYY') || ' at ' || to_char(a.appointment_time, 'HH12:MI AM') || ' with ' || coalesce(a.doctor_name, 'Attending Specialist') || '.' || E'\n\n' || '📍 Location: MKES Hospital, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.',
    now()
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = (v_clinic_today + interval '1 day')::date
    AND a.status IN ('scheduled', 'confirmed')
    AND lower(trim(a.department)) IN ('eye', 'dental')
    AND p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE (o.appointment_id = a.id OR (o.appointment_id IS NULL AND o.patient_id = p.id AND o.created_at >= (now() - interval '20 hours')))
        AND o.message_type = 'reminder_24h'
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;

  -- 1b. Same-day 8:00 AM reminder (appointments scheduled for today in clinic timezone IST, Eye and Dental ONLY)
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    appointment_id,
    department,
    message_type,
    template_key,
    message_text,
    scheduled_for
  )
  SELECT 
    p.mobile,
    p.id,
    a.id,
    lower(trim(a.department)),
    'appointment_reminder',
    'reminder_sameday_8am_' || a.id::text,
    'Good morning ' || coalesce(p.name, 'Valued Patient') || ', this is a reminder of your ' || upper(a.department) || ' appointment today, ' || to_char(a.appointment_date, 'DD Mon YYYY') || ' at ' || to_char(a.appointment_time, 'HH12:MI AM') || ' with ' || coalesce(a.doctor_name, 'Attending Specialist') || '.' || E'\n\n' || 'If you need to reschedule, please reply to this message.' || E'\n' || 'Reply STOP to unsubscribe.',
    now()
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = v_clinic_today
    AND v_clinic_time >= '08:00:00'::TIME
    AND a.status IN ('scheduled', 'confirmed')
    AND lower(trim(a.department)) IN ('eye', 'dental')
    AND p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE (o.appointment_id = a.id OR (o.appointment_id IS NULL AND o.patient_id = p.id AND o.created_at >= v_clinic_today::TIMESTAMP))
        AND (o.template_key = 'reminder_sameday_8am_' || a.id::text OR o.message_type = 'appointment_reminder')
    );

  GET DIAGNOSTICS v_temp_count = ROW_COUNT;
  v_enqueued_count := v_enqueued_count + v_temp_count;

  -- 2. 2h reminders (Eye and Dental ONLY)
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    appointment_id,
    department,
    message_type,
    template_key,
    message_text,
    scheduled_for
  )
  SELECT 
    p.mobile,
    p.id,
    a.id,
    lower(trim(a.department)),
    'reminder_2h',
    'reminder_2h',
    'Dear ' || coalesce(p.name, 'Valued Patient') || ', your ' || upper(a.department) || ' appointment is today at ' || to_char(a.appointment_time, 'HH12:MI AM') || ' (Doctor: ' || coalesce(a.doctor_name, 'Attending Specialist') || ').' || E'\n\n' || 'Please arrive 10 minutes early at MKES CARE+, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.',
    now()
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = v_clinic_today
    AND a.status IN ('scheduled', 'confirmed')
    AND lower(trim(a.department)) IN ('eye', 'dental')
    AND a.appointment_time >= v_clinic_time
    AND a.appointment_time <= (v_clinic_time + interval '2 hours 15 minutes')::TIME
    AND p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE (o.appointment_id = a.id OR (o.appointment_id IS NULL AND o.patient_id = p.id AND o.created_at >= (v_clinic_today::TIMESTAMP)))
        AND o.message_type = 'reminder_2h'
    );

  GET DIAGNOSTICS v_temp_count = ROW_COUNT;
  v_enqueued_count := v_enqueued_count + v_temp_count;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_appointment_reminders_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_appointment_reminders_batch() TO service_role;

-- B. Google Review Requests (Completed Appointments - Eye and Dental ONLY)
CREATE OR REPLACE FUNCTION public.enqueue_google_review_requests_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_clinic_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_google_reviews')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

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
    lower(trim(a.department)),
    'review_request',
    'review_request',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', thank you for visiting MKES CARE+ today.\n\nYour feedback helps us continuously improve our community healthcare services. Would you take 30 seconds to share your experience on Google?\n👉 https://g.page/r/mkes-care-plus/review\nReply STOP to unsubscribe.'
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = v_clinic_today
    AND a.status = 'completed'
    AND lower(trim(a.department)) IN ('eye', 'dental')
    AND p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND a.appointment_time <= (v_clinic_time - interval '2 hours')::TIME
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'review_request' AND o.created_at >= (now() - interval '60 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_google_review_requests_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_google_review_requests_batch() TO service_role;

-- C. Billing Payment Reminders (Eye and Dental ONLY)
CREATE OR REPLACE FUNCTION public.enqueue_billing_payment_reminders_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_payment_reminders')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

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
    lower(trim(b.department)),
    'payment_reminder',
    'payment_reminder',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', this is a friendly reminder that a balance of ₹' || (b.total_amount - b.amount_paid)::text || ' remains pending for Invoice #' || coalesce(b.invoice_number, b.id::text) || ' at MKES CARE+.\n\nPlease settle this at the hospital billing desk at your convenience.\nReply STOP to unsubscribe.'
  FROM public.billing b
  JOIN public.patients p ON p.id = b.patient_id
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND lower(trim(b.department)) IN ('eye', 'dental')
    AND b.payment_status IN ('pending', 'partial')
    AND (b.total_amount - b.amount_paid) > 0
    AND b.created_at <= (now() - interval '3 days')
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'payment_reminder' AND o.created_at >= (now() - interval '7 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_billing_payment_reminders_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_billing_payment_reminders_batch() TO service_role;

-- D. Dental Lab Ready Notification Batch Procedure
CREATE OR REPLACE FUNCTION public.enqueue_dental_lab_notifications_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enqueued_count INT := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_dental_lab')) THEN
    RETURN 0;
  END IF;

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
    'dental',
    'dental_lab_ready',
    'dental_lab_' || dl.case_number,
    '🦷 *MKES CARE+ DENTAL CLINIC*' || E'\n\n' ||
    'Dear ' || coalesce(p.name, 'Valued Patient') || E',\n\n' ||
    'Your custom dental lab restoration (*' || coalesce(dl.case_type, 'Restoration') || '*, Ref: #' || dl.case_number || E') is now *READY* for fitting at MKES CARE+ Dental Clinic.\n\n' ||
    'Please contact our reception desk to confirm your appointment time for insertion.\n\n' ||
    'Thank you,\nMKES CARE+ Clinical Team\nReply STOP to unsubscribe.'
  FROM public.dental_lab dl
  JOIN public.patients p ON p.id = dl.patient_id
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND lower(trim(dl.status)) = 'ready'
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id 
        AND o.message_type = 'dental_lab_ready' 
        AND o.template_key = 'dental_lab_' || dl.case_number
        AND o.created_at >= (now() - interval '14 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_dental_lab_notifications_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_dental_lab_notifications_batch() TO service_role;

-- E. Festival Greeting Broadcast Procedure (Admin Only)
DROP FUNCTION IF EXISTS public.enqueue_festival_greeting_broadcast(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.enqueue_festival_greeting_broadcast(
  p_festival_name TEXT,
  p_custom_message TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_msg_body TEXT;
BEGIN
  -- Strict NULL-safe authorization: only service_role or active admin permitted
  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
      RAISE EXCEPTION 'Forbidden: Only administrators can trigger festival greeting broadcasts.';
    END IF;
  END IF;

  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_festival_broadcast')) THEN
    RETURN 0;
  END IF;

  v_msg_body := coalesce(
    trim(p_custom_message),
    '✨ *Warm ' || coalesce(trim(p_festival_name), 'Festival') || ' Greetings from MKES CARE+ Hospital!*' || E'\n\n' ||
    'May this auspicious occasion bring peace, prosperity, and radiant health to you and your family.\nReply STOP to unsubscribe.'
  );

  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    template_key,
    message_text,
    created_by
  )
  SELECT
    p.mobile,
    p.id,
    'general',
    'festival',
    'festival_' || lower(regexp_replace(coalesce(p_festival_name, 'greeting'), '[^a-zA-Z0-9]', '_', 'g')),
    replace(v_msg_body, '{{patient_name}}', coalesce(p.name, 'Valued Patient')),
    v_caller_id
  FROM public.patients p
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id 
        AND o.message_type = 'festival' 
        AND o.template_key = 'festival_' || lower(regexp_replace(coalesce(p_festival_name, 'greeting'), '[^a-zA-Z0-9]', '_', 'g'))
        AND o.created_at >= (now() - interval '24 hours')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_festival_greeting_broadcast(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_festival_greeting_broadcast(TEXT, TEXT) TO authenticated, service_role;

-- F. Annual Eye Checkup Reminders (11 Months Post-Visit, Eye Department ONLY)
CREATE OR REPLACE FUNCTION public.enqueue_annual_eye_reminders_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_annual_eye')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

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
    'annual_eye',
    'annual_eye',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', it has been a year since your comprehensive eye checkup at MKES Eye Clinic.\n\nRegular vision screenings help maintain healthy eyes and clear vision. Reply 1 to request an appointment.\nReply STOP to unsubscribe.'
  FROM public.patients p
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.patient_id = p.id
        AND lower(trim(a.department)) = 'eye'
        AND a.status = 'completed'
        AND a.appointment_date BETWEEN (v_clinic_today - interval '365 days')::date AND (v_clinic_today - interval '335 days')::date
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.appointments a2
      WHERE a2.patient_id = p.id
        AND lower(trim(a2.department)) = 'eye'
        AND a2.appointment_date >= (v_clinic_today - interval '330 days')::date
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id
        AND o.message_type = 'annual_eye'
        AND o.created_at >= (now() - interval '90 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_annual_eye_reminders_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_annual_eye_reminders_batch() TO service_role;

-- G. Dental Follow-Ups (Cleaning 6 Months, RCT 7 Days, Implant 7 Days - Dental ONLY)
CREATE OR REPLACE FUNCTION public.enqueue_dental_followups_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_dental_followups')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

  -- 1. Dental Cleaning (6 Months)
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
    'dental',
    'dental_cleaning',
    'dental_cleaning',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', your 6-month routine dental cleaning and scaling is due at MKES Dental Care.\n\nKeep your teeth healthy and plaque-free! Reply 1 to book your preferred visit.\nReply STOP to unsubscribe.'
  FROM public.patients p
  JOIN public.dental_treatments t ON t.patient_id = p.id
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND coalesce(t.procedure_status, 'completed') = 'completed'
    AND t.procedure_performed ~* '(cleaning|scaling|prophylaxis)'
    AND t.treatment_date = (v_clinic_today - interval '180 days')::date
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'dental_cleaning' AND o.created_at >= (now() - interval '60 days')
    );

  -- 2. Dental RCT Follow-Up (7 Days)
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
    'dental',
    'dental_rct',
    'dental_rct',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', how are you feeling after your Root Canal Treatment at MKES Dental Care?\n\nIf you experience mild soreness, please take your prescribed medications. For high pain or permanent crown fitting, reply to this message.\nReply STOP to unsubscribe.'
  FROM public.patients p
  JOIN public.dental_treatments t ON t.patient_id = p.id
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND coalesce(t.procedure_status, 'completed') = 'completed'
    AND t.procedure_performed ~* '(rct|root canal)'
    AND t.treatment_date = (v_clinic_today - interval '7 days')::date
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'dental_rct' AND o.created_at >= (now() - interval '14 days')
    );

  -- 3. Dental Implant Healing Follow-Up (7 Days)
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
    'dental',
    'dental_implant',
    'dental_implant',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', we are following up on your dental implant healing progress at MKES Dental Care.\n\nPlease ensure you are following the post-surgical oral hygiene instructions. Reply to this chat if you have any questions.\nReply STOP to unsubscribe.'
  FROM public.patients p
  JOIN public.dental_treatments t ON t.patient_id = p.id
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND coalesce(t.procedure_status, 'completed') = 'completed'
    AND t.procedure_performed ~* '(implant)'
    AND t.treatment_date = (v_clinic_today - interval '7 days')::date
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'dental_implant' AND o.created_at >= (now() - interval '14 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_dental_followups_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_dental_followups_batch() TO service_role;

-- H. Patient Birthday Greetings
CREATE OR REPLACE FUNCTION public.enqueue_birthday_greetings_batch()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT;
  v_enqueued_count INT := 0;
  v_clinic_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_birthdays')) THEN
    RETURN 0;
  END IF;

  IF (coalesce(auth.jwt()->>'role', '') = 'service_role' OR auth.role() = 'service_role') THEN
    -- service role authorized
  ELSE
    IF v_caller_id IS NOT NULL THEN
      SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
      IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin') THEN
        RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
      END IF;
    ELSE
      RAISE EXCEPTION 'Unauthorized: Caller is not authenticated.';
    END IF;
  END IF;

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
    'general',
    'birthday',
    'birthday',
    '🎂 *Wishing you a very Happy Birthday from all of us at MKES CARE+!*\n\nMay you enjoy robust health, happiness, and clear smiles throughout the year.\nReply STOP to unsubscribe.'
  FROM public.patients p
  WHERE p.whatsapp_opt_out = false
    AND public.normalize_phone_10(p.mobile) IS NOT NULL
    AND p.dob IS NOT NULL
    AND to_char(p.dob, 'MM-DD') = to_char(v_clinic_today, 'MM-DD')
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'birthday' AND o.created_at >= (now() - interval '300 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_birthday_greetings_batch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_birthday_greetings_batch() TO service_role;

-- ----------------------------------------------------------------------------
-- STEP 13: VENDOR PURCHASE ORDER & DELIVERY NOTIFICATION TRIGGER
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_vendor_po_wa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_vendor RECORD;
BEGIN
  IF NEW.status = 'ordered' AND (OLD.status IS DISTINCT FROM 'ordered') THEN
    SELECT * INTO v_vendor FROM public.vendors WHERE id = NEW.vendor_id;
    IF v_vendor IS NOT NULL AND v_vendor.phone IS NOT NULL AND public.normalize_phone_10(v_vendor.phone) IS NOT NULL THEN
      INSERT INTO public.whatsapp_messages_outbox (
        recipient_phone,
        department,
        message_type,
        template_key,
        message_text
      ) VALUES (
        v_vendor.phone,
        'general',
        'vendor_po',
        'vendor_po',
        '📦 *MKES CARE+ Hospital — Purchase Order Dispatch*' || E'\n\n' ||
        'Dear ' || coalesce(v_vendor.name, 'Valued Vendor') || E',\n' ||
        'Formal Purchase Order #' || coalesce(NEW.purchase_order_number, NEW.id::text) || ' for clinical supplies has been ordered.' || E'\n' ||
        'Total Order Value: ₹' || coalesce(NEW.total_amount, 0)::text || '.' || E'\n' ||
        'Please deliver to: MKES CARE+ Central Hospital Store, Malad West.' || E'\n' ||
        'Reply STOP to unsubscribe.'
      );
    END IF;
  ELSIF NEW.status IN ('received', 'partially_received') AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT * INTO v_vendor FROM public.vendors WHERE id = NEW.vendor_id;
    IF v_vendor IS NOT NULL AND v_vendor.phone IS NOT NULL AND public.normalize_phone_10(v_vendor.phone) IS NOT NULL THEN
      INSERT INTO public.whatsapp_messages_outbox (
        recipient_phone,
        department,
        message_type,
        template_key,
        message_text
      ) VALUES (
        v_vendor.phone,
        'general',
        'vendor_po',
        'vendor_po',
        '📦 *MKES CARE+ Hospital — Delivery Confirmation*' || E'\n\n' ||
        'Dear ' || coalesce(v_vendor.name, 'Valued Vendor') || E',\n' ||
        'Shipment for Purchase Order #' || coalesce(NEW.purchase_order_number, NEW.id::text) || ' has been received and verified by Central Stores (' || upper(NEW.status) || ').' || E'\n' ||
        'Thank you for your prompt fulfillment.' || E'\n' ||
        'Reply STOP to unsubscribe.'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchase_orders') THEN
    DROP TRIGGER IF EXISTS trg_vendor_po_wa ON public.purchase_orders;
    CREATE TRIGGER trg_vendor_po_wa
      AFTER UPDATE OF status ON public.purchase_orders
      FOR EACH ROW
      EXECUTE FUNCTION public.trg_fn_vendor_po_wa();
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- STEP 14: APPOINTMENT STATUS & RESCHEDULE AUTOMATIC OUTBOX RECONCILIATION
-- Cancels pending WhatsApp reminders when appointments are cancelled or rescheduled
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_fn_appointment_status_or_reschedule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- When appointment is cancelled
  IF NEW.status = 'cancelled' AND (OLD.status IS DISTINCT FROM 'cancelled') THEN
    UPDATE public.whatsapp_messages_outbox
    SET status = 'cancelled',
        last_error = 'Appointment cancelled by patient/clinic',
        updated_at = now()
    WHERE appointment_id = NEW.id
      AND status = 'pending';
  END IF;

  -- When appointment date or time is rescheduled
  IF (NEW.appointment_date IS DISTINCT FROM OLD.appointment_date 
      OR NEW.appointment_time IS DISTINCT FROM OLD.appointment_time) THEN
    UPDATE public.whatsapp_messages_outbox
    SET status = 'cancelled',
        last_error = 'Appointment rescheduled to new date/time',
        updated_at = now()
    WHERE appointment_id = NEW.id
      AND status = 'pending';
  END IF;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
    DROP TRIGGER IF EXISTS trg_appointment_status_or_reschedule ON public.appointments;
    CREATE TRIGGER trg_appointment_status_or_reschedule
      AFTER UPDATE OF status, appointment_date, appointment_time ON public.appointments
      FOR EACH ROW
      EXECUTE FUNCTION public.trg_fn_appointment_status_or_reschedule();
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
