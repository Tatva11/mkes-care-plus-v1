-- ============================================================================
-- MKES CARE+ — Migration: WhatsApp Delivery Tracking & Strict RLS Security Hardening
-- File: supabase/migrations/20261031120000_whatsapp_delivery_tracking_and_rls_hardening.sql
-- Description:
--   1. Expands status constraint on whatsapp_messages_outbox to include 'delivered' and 'read'.
--   2. Adds delivered_at, read_at, and whatsapp_message_id columns to outbox.
--   3. Strictly enforces LEAST PRIVILEGE on whatsapp_messages_outbox:
--      - Table is SELECT-ONLY for authenticated staff and admins.
--      - Direct client-side INSERT and UPDATE are strictly DENIED to prevent arbitrary status forgery.
--   4. Creates SECURITY DEFINER RPC 'retry_failed_whatsapp_message' with strict state validation:
--      - Only active clinic staff or admins can invoke.
--      - Only messages currently in 'failed' status can be retried.
--   5. Creates SECURITY DEFINER RPC 'cancel_whatsapp_outbox_message':
--      - Only active clinic staff or admins can invoke.
--      - Only messages currently in 'pending' status can be cancelled.
--   6. Seeds singleton whatsapp_settings row if missing.
--   7. Creates expression indexes on whatsapp_message_logs raw_payload for fast ACK reconciliation.
-- ============================================================================

BEGIN;

-- 1. Safely drop any existing status check constraint (regardless of auto-generated name) and re-add hardened constraint
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

-- 2. Delivery Receipt, WhatsApp ID, and Provenance Columns
ALTER TABLE public.whatsapp_messages_outbox
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS whatsapp_message_id TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_wa_outbox_wa_msg_id 
  ON public.whatsapp_messages_outbox(whatsapp_message_id) 
  WHERE whatsapp_message_id IS NOT NULL;

-- 3. Strict Least-Privilege RLS Enforcement:
--    Drop any direct table INSERT or UPDATE policies for authenticated users.
--    Authenticated staff/admins have SELECT-ONLY access to inspect their queues.
--    All mutations MUST be performed through validated SECURITY DEFINER RPCs
--    or by the background daemon operating under the service_role key.
DROP POLICY IF EXISTS "Staff and Admins insert outbox" ON public.whatsapp_messages_outbox;
DROP POLICY IF EXISTS "Staff and Admins update outbox" ON public.whatsapp_messages_outbox;

-- Re-assert SELECT policy for authenticated staff and admins
DROP POLICY IF EXISTS "Staff and Admins view outbox" ON public.whatsapp_messages_outbox;
CREATE POLICY "Staff and Admins view outbox"
  ON public.whatsapp_messages_outbox FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

-- 4. Secure Stored Procedure: Retry Failed WhatsApp Message (Atomic & NULL-Safe)
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

-- 5. Secure Stored Procedure: Cancel Pending WhatsApp Message (Atomic & NULL-Safe)
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

-- 6. Stored Procedure: send_staff_whatsapp_message with provenance and complete STOP check
CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID,
  p_department TEXT,
  p_message_text TEXT,
  p_media_url TEXT DEFAULT NULL,
  p_template_key TEXT DEFAULT 'custom',
  p_message_type TEXT DEFAULT 'custom'
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
  v_is_opted_out BOOLEAN := false;
  v_resolved_patient_id UUID := p_patient_id;
  v_outbox_id UUID;
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
      RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only clinic staff or administrators can send WhatsApp messages.');
    END IF;
  END IF;

  v_clean_phone := regexp_replace(coalesce(p_recipient_phone, ''), '[^0-9]', '', 'g');
  IF length(v_clean_phone) < 10 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid phone number format: must contain at least 10 digits.');
  END IF;
  v_ten_digits := right(v_clean_phone, 10);

  IF trim(coalesce(p_message_text, '')) = '' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Message body cannot be empty.');
  END IF;

  v_clean_dept := lower(trim(coalesce(p_department, 'general')));
  IF v_clean_dept NOT IN ('eye', 'dental', 'general') THEN
    v_clean_dept := 'general';
  END IF;

  -- 1. Direct patient opt-out check if patient_id is provided
  IF v_resolved_patient_id IS NOT NULL THEN
    SELECT whatsapp_opt_out INTO v_is_opted_out FROM public.patients WHERE id = v_resolved_patient_id;
  END IF;

  -- 2. Complete STOP/opt-out check across national 10-digit phone match
  IF NOT coalesce(v_is_opted_out, false) THEN
    SELECT EXISTS (
      SELECT 1 FROM public.patients 
      WHERE regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g') LIKE '%' || v_ten_digits
        AND whatsapp_opt_out = true
    ) INTO v_is_opted_out;
  END IF;

  IF coalesce(v_is_opted_out, false) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Patient has opted out of WhatsApp messages (STOP).');
  END IF;

  -- 3. Automatic patient binding if not explicitly supplied
  IF v_resolved_patient_id IS NULL THEN
    SELECT id INTO v_resolved_patient_id FROM public.patients
    WHERE regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g') LIKE '%' || v_ten_digits
    ORDER BY created_at ASC LIMIT 1;
  END IF;

  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    template_key,
    media_url,
    message_text,
    status,
    created_by
  ) VALUES (
    v_clean_phone,
    v_resolved_patient_id,
    v_clean_dept,
    coalesce(p_message_type, 'custom'),
    coalesce(p_template_key, 'custom'),
    p_media_url,
    trim(p_message_text),
    'pending',
    v_caller_id
  ) RETURNING id INTO v_outbox_id;

  RETURN jsonb_build_object('success', true, 'outbox_id', v_outbox_id);
END;
$$;

-- 4-argument overload for strict backward compatibility
CREATE OR REPLACE FUNCTION public.send_staff_whatsapp_message(
  p_recipient_phone TEXT,
  p_patient_id UUID,
  p_department TEXT,
  p_message_text TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT public.send_staff_whatsapp_message(
    p_recipient_phone,
    p_patient_id,
    p_department,
    p_message_text,
    NULL,
    'custom',
    'custom'
  );
$$;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) TO authenticated, service_role;

-- 7. Seed singleton settings row if missing
INSERT INTO public.whatsapp_settings (id, is_enabled)
VALUES ('00000000-0000-0000-0000-000000000001'::UUID, false)
ON CONFLICT (id) DO NOTHING;

-- 8. Expression Indexes on Audit Logs for O(1) ACK reconciliation
CREATE INDEX IF NOT EXISTS idx_wa_logs_raw_payload_msg_id
  ON public.whatsapp_message_logs((raw_payload->>'messageId'));

CREATE INDEX IF NOT EXISTS idx_wa_logs_raw_payload_id
  ON public.whatsapp_message_logs((raw_payload->>'id'));

COMMIT;

NOTIFY pgrst, 'reload schema';
