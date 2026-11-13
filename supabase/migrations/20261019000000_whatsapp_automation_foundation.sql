-- ============================================================================
-- MKES CARE+ — Migration: WhatsApp Automation Foundation (Phase 2 Final Hardened)
-- File: supabase/migrations/20261019000000_whatsapp_automation_foundation.sql
-- Description:
--   Phase 2 database infrastructure with full security, concurrency, schema-compatibility,
--   and reliability hardening:
--   1. Patients opt-out column (DPDP Act compliance) & normalize_phone_10 immutable helper
--   2. Appointments duration column (defaults to 15 min granularity)
--   3. Transactional WhatsApp Outbox (public.whatsapp_messages_outbox)
--   4. Communication Audit Logs (public.whatsapp_message_logs)
--   5. In-Chat Conversational Sessions (public.whatsapp_chat_sessions)
--   6. Appointment Requests Queue (public.whatsapp_appointment_requests)
--   7. Settings and complete 12 operational templates (public.whatsapp_settings, public.whatsapp_templates)
--   8. Real-time Database Triggers for Dental Lab Ready, Billing Payments, and Vendor POs
--   9. Direct Status Update Guard Trigger on whatsapp_appointment_requests
--   10. Row Level Security policies with strict least-privilege access
--   11. Hardened Stored Procedures:
--       - claim_whatsapp_outbox_batch (with expired lease crash recovery and retry limit)
--       - get_available_appointment_slots (input-validated, duration-aware, no double counting)
--       - approve_whatsapp_appointment_request (dual advisory locks, doctor eligibility, conflict detection, FK safety)
--       - reject_whatsapp_appointment_request (strict pending_review guard)
--       - register_patient_whatsapp_opt_out (service_role exclusive, cancels pending & processing)
--       - set_patient_whatsapp_opt_out (auth.uid() staff guarded, cancels pending & processing)
--   12. Batch Enqueue Functions for Scheduled Automation Categories:
--       - enqueue_appointment_reminders_batch (24h and 2h reminders)
--       - enqueue_annual_eye_reminders_batch (11 months post-visit)
--       - enqueue_dental_followups_batch (cleaning 6mo, RCT 7-14d, implant 7d)
--       - enqueue_birthday_greetings_batch (daily birthdays)
--       - enqueue_google_review_requests_batch (completed appointments 2h ago)
--       - enqueue_billing_payment_reminders_batch (pending balances)
--
-- IMPORTANT: This migration is kept local for independent review. Do not apply to production
-- without explicit administrator sign-off.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PHONE NORMALIZATION HELPER & SCHEMA ENHANCEMENTS
-- ----------------------------------------------------------------------------

-- Immutable helper to extract the authoritative 10-digit national number
-- Perfectly mirrors JavaScript PhoneNormalizer.extractTenDigits()
CREATE OR REPLACE FUNCTION public.normalize_phone_10(p_phone TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 10);
$$;

-- Add opt-out flag for DPDP patient consent compliance
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS whatsapp_opt_out BOOLEAN NOT NULL DEFAULT false;

-- Ensure patients has dob column matching existing patient schema
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS dob DATE;

-- Ensure patients has updated_at column for audit tracking
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_patients_norm_mobile_optout 
  ON public.patients(public.normalize_phone_10(mobile), whatsapp_opt_out);

-- Add optional duration_minutes to appointments (defaults to 15 min granularity)
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS duration_minutes INTEGER NOT NULL DEFAULT 15;

-- Ensure appointments has ai_booked flag
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS ai_booked BOOLEAN NOT NULL DEFAULT false;

-- Ensure dental_treatments has procedure_status column if table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'dental_treatments') THEN
    ALTER TABLE public.dental_treatments
      ADD COLUMN IF NOT EXISTS procedure_status TEXT NOT NULL DEFAULT 'completed';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. TRANSACTIONAL WHATSAPP OUTBOX TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_messages_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_phone TEXT NOT NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  department TEXT NOT NULL CHECK (department IN ('eye', 'dental', 'general')),
  message_type TEXT NOT NULL, 
  -- reminder_24h, reminder_2h, annual_eye, dental_cleaning, dental_rct, dental_implant, 
  -- lab_ready, birthday, festival, review_request, payment_receipt, payment_reminder, vendor_po, custom, confirmation, cancellation
  template_key TEXT,
  message_text TEXT NOT NULL,
  media_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending' 
         CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  scheduled_for TIMESTAMPTZ NOT NULL DEFAULT now(),
  retry_count INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 3,
  last_error TEXT,
  lease_id UUID,
  lease_expires_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_outbox_dequeue 
  ON public.whatsapp_messages_outbox(status, scheduled_for, lease_expires_at);

CREATE INDEX IF NOT EXISTS idx_wa_outbox_norm_phone 
  ON public.whatsapp_messages_outbox(public.normalize_phone_10(recipient_phone), status);

ALTER TABLE public.whatsapp_messages_outbox
  ADD COLUMN IF NOT EXISTS appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_wa_outbox_appointment_type_created 
  ON public.whatsapp_messages_outbox(appointment_id, message_type, created_at);

-- ----------------------------------------------------------------------------
-- 3. COMMUNICATION AUDIT LOGS TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_message_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outbox_id UUID REFERENCES public.whatsapp_messages_outbox(id) ON DELETE SET NULL,
  direction TEXT NOT NULL CHECK (direction IN ('outbound', 'inbound')),
  phone_number TEXT NOT NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  message_body TEXT NOT NULL,
  raw_payload JSONB,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_logs_norm_phone 
  ON public.whatsapp_message_logs(public.normalize_phone_10(phone_number), timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_wa_logs_outbox_dir
  ON public.whatsapp_message_logs(outbox_id, direction);

-- ----------------------------------------------------------------------------
-- 4. CONVERSATIONAL CHAT SESSIONS TABLE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_chat_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number TEXT UNIQUE NOT NULL,
  current_state TEXT NOT NULL DEFAULT 'IDLE',
  session_data JSONB NOT NULL DEFAULT '{}'::JSONB,
  last_interaction TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_sessions_norm_phone 
  ON public.whatsapp_chat_sessions(public.normalize_phone_10(phone_number));

-- ----------------------------------------------------------------------------
-- 5. APPOINTMENT REQUESTS QUEUE (FOR STAFF APPROVAL)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_appointment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_phone TEXT NOT NULL,
  patient_name TEXT NOT NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  department TEXT NOT NULL CHECK (department IN ('eye', 'dental')),
  doctor_id UUID REFERENCES public.department_doctors(id) ON DELETE SET NULL,
  doctor_name TEXT,
  requested_date DATE NOT NULL,
  requested_time TIME NOT NULL,
  duration_minutes INTEGER NOT NULL DEFAULT 15,
  status TEXT NOT NULL DEFAULT 'pending_review' 
         CHECK (status IN ('pending_review', 'approved', 'rejected', 'expired')),
  promoted_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  staff_remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_requests_queue 
  ON public.whatsapp_appointment_requests(status, requested_date, requested_time);

-- Trigger: Prevent direct status update on whatsapp_appointment_requests from bypassing approval RPCs
CREATE OR REPLACE FUNCTION public.trg_fn_guard_appointment_request_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF current_setting('mkes.rpc_status_update', true) IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION 'Direct status updates on public.whatsapp_appointment_requests are prohibited. Use approve_whatsapp_appointment_request() or reject_whatsapp_appointment_request().';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_appointment_request_status ON public.whatsapp_appointment_requests;
CREATE TRIGGER trg_guard_appointment_request_status
  BEFORE UPDATE ON public.whatsapp_appointment_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_guard_appointment_request_status();

-- ----------------------------------------------------------------------------
-- 6. SETTINGS & TEMPLATES TABLES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.whatsapp_settings (
  id UUID PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::UUID,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  daily_send_limit INTEGER NOT NULL DEFAULT 500,
  operating_hours_start TIME NOT NULL DEFAULT '09:00:00',
  operating_hours_end TIME NOT NULL DEFAULT '20:00:00',
  cooldown_seconds INTEGER NOT NULL DEFAULT 4,
  auto_reply_enabled BOOLEAN NOT NULL DEFAULT true,
  emergency_notice TEXT NOT NULL DEFAULT '⚠️ For immediate medical emergencies, please visit the MKES Hospital Casualty ward or call 108.',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.whatsapp_settings (id, is_enabled)
VALUES ('00000000-0000-0000-0000-000000000001'::UUID, false)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key TEXT UNIQUE NOT NULL,
  department TEXT NOT NULL CHECK (department IN ('eye', 'dental', 'all', 'general')),
  title TEXT NOT NULL,
  body_template TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed all 12 operational templates
INSERT INTO public.whatsapp_templates (template_key, department, title, body_template)
VALUES
  ('reminder_24h', 'all', '24-Hour Appointment Reminder', 
   'Hello {{patient_name}}, this is a reminder of your {{department}} appointment at MKES CARE+ on {{appointment_date}} at {{appointment_time}} with {{doctor_name}}.' || E'\n\n' || '📍 Location: MKES Hospital, Malad West.' || E'\n' || 'To reschedule, please reply to this message. Reply STOP to unsubscribe.'),
  
  ('reminder_2h', 'all', '2-Hour Same-Day Reminder', 
   'Dear {{patient_name}}, your {{department}} appointment is today at {{appointment_time}} (Doctor: {{doctor_name}}).' || E'\n\n' || 'Please arrive 10 minutes early at MKES CARE+, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('annual_eye', 'eye', 'Annual Eye Checkup Due', 
   'Dear {{patient_name}}, it has been a year since your comprehensive eye checkup at MKES Eye Clinic.' || E'\n\n' || 'Regular vision screenings help maintain healthy eyes and clear vision. Reply 1 to request an appointment.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('dental_cleaning', 'dental', 'Dental Cleaning 6-Month Reminder', 
   'Dear {{patient_name}}, your 6-month routine dental cleaning and scaling is due at MKES Dental Care.' || E'\n\n' || 'Keep your teeth healthy and plaque-free! Reply 1 to book your preferred visit.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('dental_rct', 'dental', 'Dental RCT Post-Procedure Follow-Up', 
   'Dear {{patient_name}}, how are you feeling after your Root Canal Treatment at MKES Dental Care?' || E'\n\n' || 'If you experience mild soreness, please take your prescribed medications. For high pain or permanent crown fitting, reply to this message.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('dental_implant', 'dental', 'Dental Implant Healing Follow-Up', 
   'Dear {{patient_name}}, we are following up on your dental implant healing progress at MKES Dental Care.' || E'\n\n' || 'Please ensure you are following the post-surgical oral hygiene instructions. Reply to this chat if you have any questions.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('lab_ready', 'dental', 'Lab / Prosthesis Ready Notification', 
   'Good news, {{patient_name}}! Your dental prosthesis / appliance ({{prosthesis_type}}) has arrived from the lab and is ready at MKES Dental Care.' || E'\n\n' || 'Please reply 1 to schedule your trial or fitting session.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('birthday', 'all', 'Patient Birthday Greeting', 
   '🎂 Wishing you a very Happy Birthday from all of us at MKES CARE+!' || E'\n\n' || 'May you enjoy robust health, happiness, and clear smiles throughout the year.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('festival', 'all', 'Festival Greeting', 
   '✨ Warm greetings and best wishes from the management, doctors, and staff at MKES CARE+ Hospital!' || E'\n\n' || 'Wishing you and your loved ones good health and prosperity.' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('review_request', 'all', 'Google Review Feedback Request', 
   'Dear {{patient_name}}, thank you for visiting MKES CARE+ today.' || E'\n\n' || 'Your feedback helps us continuously improve our community healthcare services. Would you take 30 seconds to share your experience on Google?' || E'\n' || '👉 https://g.page/r/mkes-care-plus/review' || E'\n' || 'Reply STOP to unsubscribe.'),
  
  ('payment_receipt', 'all', 'Billing Payment Receipt', 
   'Dear {{patient_name}}, we have received your payment of Rs. {{amount}} (Invoice #{{invoice_number}}) for your {{department}} consultation at MKES CARE+.' || E'\n\n' || 'Thank you for choosing MKES Hospital.' || E'\n' || 'Reply STOP to unsubscribe.'),

  ('payment_reminder', 'all', 'Pending Balance Reminder', 
   'Dear {{patient_name}}, this is a friendly reminder that a balance of Rs. {{balance_due}} remains pending for Invoice #{{invoice_number}} at MKES CARE+.' || E'\n\n' || 'Please settle this at the hospital billing desk at your earliest convenience.' || E'\n' || 'Reply STOP to unsubscribe.'),

  ('vendor_po', 'general', 'Vendor Purchase Order Dispatch', 
   'Dear {{vendor_name}}, Purchase Order {{po_number}} from MKES CARE+ has been ordered for Rs. {{total_amount}}.' || E'\n\n' || 'Please process delivery to the Central Store, MKES Hospital, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.')
ON CONFLICT (template_key) DO UPDATE 
SET body_template = EXCLUDED.body_template,
    updated_at = now();

-- ----------------------------------------------------------------------------
-- 7. REAL-TIME DATABASE TRIGGERS (MATCHED TO ACTUAL REPO SCHEMA)
-- ----------------------------------------------------------------------------

-- Trigger A: Dental Lab Ready Notification (Matches public.dental_lab schema)
CREATE OR REPLACE FUNCTION public.trg_fn_dental_lab_ready_wa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_patient RECORD;
BEGIN
  IF NEW.status = 'ready' AND (OLD.status IS DISTINCT FROM 'ready') THEN
    SELECT * INTO v_patient FROM public.patients WHERE id = NEW.patient_id;
    
    IF v_patient IS NOT NULL AND v_patient.mobile IS NOT NULL AND v_patient.whatsapp_opt_out = false THEN
      INSERT INTO public.whatsapp_messages_outbox (
        recipient_phone,
        patient_id,
        department,
        message_type,
        template_key,
        message_text
      ) VALUES (
        v_patient.mobile,
        v_patient.id,
        'dental',
        'lab_ready',
        'lab_ready',
        '🦷 *MKES CARE+ Dental Clinic*' || E'\n\n' ||
        'Dear ' || coalesce(v_patient.name, 'Valued Patient') || E',\n' ||
        'Your custom dental restoration (' || coalesce(NEW.case_type, 'Restoration') || ', Ref: #' || coalesce(NEW.case_number, 'N/A') || ') is now READY for fitting at MKES CARE+ Dental Clinic.' || E'\n\n' ||
        'Please reply 1 to schedule your fitting appointment.\nReply STOP to unsubscribe.'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dental_lab_ready_wa ON public.dental_lab;
CREATE TRIGGER trg_dental_lab_ready_wa
  AFTER UPDATE OF status ON public.dental_lab
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_dental_lab_ready_wa();

-- Trigger B: Billing Payment Receipt Notification (Matches public.billing_payments & public.billing schema)
CREATE OR REPLACE FUNCTION public.trg_fn_billing_payment_wa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice RECORD;
  v_patient RECORD;
BEGIN
  SELECT * INTO v_invoice FROM public.billing WHERE id = NEW.billing_id;
  IF v_invoice IS NOT NULL THEN
    SELECT * INTO v_patient FROM public.patients WHERE id = v_invoice.patient_id;
    IF v_patient IS NOT NULL AND v_patient.mobile IS NOT NULL AND v_patient.whatsapp_opt_out = false THEN
      INSERT INTO public.whatsapp_messages_outbox (
        recipient_phone,
        patient_id,
        department,
        message_type,
        template_key,
        message_text
      ) VALUES (
        v_patient.mobile,
        v_patient.id,
        coalesce(v_invoice.department, 'general'),
        'payment_receipt',
        'payment_receipt',
        '💳 *MKES CARE+ Payment Receipt*' || E'\n\n' ||
        'Dear ' || coalesce(v_patient.name, 'Valued Patient') || E',\n' ||
        'We received your payment of ₹' || NEW.amount::text || ' for Invoice #' || coalesce(v_invoice.invoice_number, 'N/A') || '.' || E'\n' ||
        'Remaining Balance: ₹' || coalesce((v_invoice.total_amount - v_invoice.amount_paid)::text, '0') || '.' || E'\n\n' ||
        'Thank you for choosing MKES Hospital.\nReply STOP to unsubscribe.'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_billing_payment_wa ON public.billing_payments;
CREATE TRIGGER trg_billing_payment_wa
  AFTER INSERT ON public.billing_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_billing_payment_wa();

-- Trigger C: Vendor Purchase Order & Delivery Notification (Matches public.purchase_orders & public.vendors schema)
CREATE OR REPLACE FUNCTION public.trg_fn_vendor_po_wa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_vendor RECORD;
BEGIN
  -- 1. Order Placed Dispatch Notification
  IF NEW.status = 'ordered' AND (OLD.status IS DISTINCT FROM 'ordered') THEN
    SELECT * INTO v_vendor FROM public.vendors WHERE id = NEW.vendor_id;
    IF v_vendor IS NOT NULL AND v_vendor.phone IS NOT NULL THEN
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

  -- 2. Delivery Arrival & Goods Receipt Acknowledgement
  ELSIF NEW.status IN ('received', 'partially_received') AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT * INTO v_vendor FROM public.vendors WHERE id = NEW.vendor_id;
    IF v_vendor IS NOT NULL AND v_vendor.phone IS NOT NULL THEN
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

DROP TRIGGER IF EXISTS trg_vendor_po_wa ON public.purchase_orders;
CREATE TRIGGER trg_vendor_po_wa
  AFTER UPDATE OF status ON public.purchase_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_vendor_po_wa();

-- ----------------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY POLICIES (STRICT LEAST PRIVILEGE)
-- ----------------------------------------------------------------------------
ALTER TABLE public.whatsapp_messages_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_message_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_appointment_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

-- 1. Appointment Requests: Active Staff and Admins can view and create, but status changes go through RPCs
DROP POLICY IF EXISTS "Staff and Admins manage appointment requests" ON public.whatsapp_appointment_requests;
DROP POLICY IF EXISTS "Staff and Admins view appointment requests" ON public.whatsapp_appointment_requests;
DROP POLICY IF EXISTS "Staff and Admins insert appointment requests" ON public.whatsapp_appointment_requests;
DROP POLICY IF EXISTS "Staff and Admins update non-status appointment requests" ON public.whatsapp_appointment_requests;

CREATE POLICY "Staff and Admins view appointment requests"
  ON public.whatsapp_appointment_requests FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

CREATE POLICY "Staff and Admins insert appointment requests"
  ON public.whatsapp_appointment_requests FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

CREATE POLICY "Staff and Admins update non-status appointment requests"
  ON public.whatsapp_appointment_requests FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

-- 2. Chat Sessions: Active Staff and Admins view only
DROP POLICY IF EXISTS "Staff and Admins view chat sessions" ON public.whatsapp_chat_sessions;
CREATE POLICY "Staff and Admins view chat sessions"
  ON public.whatsapp_chat_sessions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

-- 3. Settings: Admins can update, Staff can only read
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
  ON public.whatsapp_settings FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

-- 4. Templates: Active Staff and Admins view, Admins manage
DROP POLICY IF EXISTS "Staff and Admins view templates" ON public.whatsapp_templates;
CREATE POLICY "Staff and Admins view templates"
  ON public.whatsapp_templates FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

DROP POLICY IF EXISTS "Admins manage templates" ON public.whatsapp_templates;
CREATE POLICY "Admins manage templates"
  ON public.whatsapp_templates FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

-- 5. Outbox & Logs: Active Staff and Admins view only
DROP POLICY IF EXISTS "Staff and Admins view outbox" ON public.whatsapp_messages_outbox;
CREATE POLICY "Staff and Admins view outbox"
  ON public.whatsapp_messages_outbox FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

DROP POLICY IF EXISTS "Staff and Admins view logs" ON public.whatsapp_message_logs;
CREATE POLICY "Staff and Admins view logs"
  ON public.whatsapp_message_logs FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'staff') AND is_active = true
    )
  );

-- ----------------------------------------------------------------------------
-- 9. HARDENED STORED PROCEDURES
-- ----------------------------------------------------------------------------

-- ============================================================================
-- RPC 1: Claim Outbox Batch (With Expired-Lease Crash Recovery)
-- ============================================================================
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
      -- If reclaiming an expired processing lease after a worker crash, increment retry
      retry_count = CASE WHEN status = 'processing' THEN retry_count + 1 ELSE retry_count END,
      last_error = CASE WHEN status = 'processing' THEN 'Reclaimed after expired lease by worker ' || p_worker_id ELSE last_error END,
      updated_at = now()
  WHERE id IN (
    SELECT o.id 
    FROM public.whatsapp_messages_outbox o
    JOIN public.whatsapp_settings s ON s.id = '00000000-0000-0000-0000-000000000001'
    WHERE s.is_enabled = true
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
            OR public.normalize_phone_10(p.mobile) = public.normalize_phone_10(o.recipient_phone)
          )
      )
    ORDER BY o.scheduled_for ASC
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  )
  RETURNING *;
END;
$$;

-- ============================================================================
-- RPC 2: Dynamic Available Slot Calculator (No Double-Counting, Strict Input Validation)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_available_appointment_slots(
  p_department TEXT,
  p_date DATE,
  p_slot_duration_minutes INT DEFAULT 15,
  p_interval_minutes INT DEFAULT 15,
  p_doctor_id UUID DEFAULT NULL
)
RETURNS TABLE (slot_time TIME)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dept TEXT := lower(trim(p_department));
  v_opening_time TIME;
  v_closing_time TIME;
  v_curr_time TIME;
  v_clinic_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
  v_clinic_today DATE := v_clinic_now::DATE;
  v_is_today BOOLEAN := (p_date = v_clinic_today);
  v_min_time TIME;
  v_candidate_end TIME;
  v_active_doc_count INT;
BEGIN
  -- 1. Strict department filter (Optical completely rejected)
  IF v_dept NOT IN ('eye', 'dental') THEN
    RAISE EXCEPTION 'Invalid department: %. Only "eye" and "dental" are supported.', p_department;
  END IF;

  -- 2. Input validation for date and intervals in clinic timezone
  IF p_date < v_clinic_today THEN
    RAISE EXCEPTION 'Cannot query appointment slots for past date: %', p_date;
  END IF;

  IF p_slot_duration_minutes <= 0 OR p_slot_duration_minutes > 240 OR (p_slot_duration_minutes % 15 <> 0) THEN
    RAISE EXCEPTION 'Slot duration must be a positive multiple of 15 min up to 240 min.';
  END IF;

  IF p_interval_minutes <= 0 OR p_interval_minutes > 60 OR (p_interval_minutes % 15 <> 0) THEN
    RAISE EXCEPTION 'Interval must be a positive multiple of 15 min.';
  END IF;

  -- 3. Dynamic active doctor count for concurrent department chair capacity
  SELECT COUNT(*) INTO v_active_doc_count
  FROM public.department_doctors
  WHERE lower(trim(department)) = v_dept AND is_active = true;

  -- If no active doctors exist for department, no slots are available
  IF v_active_doc_count = 0 THEN
    RETURN;
  END IF;

  -- 4. Dynamic clinic operating hours from whatsapp_settings
  SELECT coalesce(operating_hours_start, '09:00:00'::TIME), coalesce(operating_hours_end, '20:00:00'::TIME)
  INTO v_opening_time, v_closing_time
  FROM public.whatsapp_settings
  WHERE id = '00000000-0000-0000-0000-000000000001'::UUID;

  IF v_opening_time IS NULL THEN
    v_opening_time := '09:00:00'::TIME;
    v_closing_time := '20:00:00'::TIME;
  END IF;

  v_curr_time := v_opening_time;

  -- Same-day buffer: must be at least 1 hour 15 minutes into future from current clinic time (IST)
  IF v_is_today THEN
    v_min_time := (v_clinic_now + interval '1 hour 15 minutes')::TIME;
  ELSE
    v_min_time := v_opening_time;
  END IF;

  -- Enforce clinic operating hours dynamically from settings
  WHILE (v_curr_time + (p_slot_duration_minutes || ' minutes')::interval) <= v_closing_time LOOP
    v_candidate_end := v_curr_time + (p_slot_duration_minutes || ' minutes')::interval;

    IF (NOT v_is_today OR v_curr_time >= v_min_time) THEN
      -- Case A: Doctor-specific check (if specific doctor requested)
      IF p_doctor_id IS NOT NULL THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.appointments a
          WHERE a.appointment_date = p_date
            AND a.doctor_id = p_doctor_id
            AND a.status NOT IN ('cancelled', 'missed')
            AND a.appointment_time < v_candidate_end
            AND (a.appointment_time + (coalesce(a.duration_minutes, 15) || ' minutes')::interval) > v_curr_time
        ) AND NOT EXISTS (
          -- IMPORTANT: Only check UNPROMOTED pending requests to prevent double-counting!
          SELECT 1 FROM public.whatsapp_appointment_requests r
          WHERE r.requested_date = p_date
            AND r.doctor_id = p_doctor_id
            AND r.status = 'pending_review'
            AND r.promoted_appointment_id IS NULL
            AND r.requested_time < v_candidate_end
            AND (r.requested_time + (coalesce(r.duration_minutes, 15) || ' minutes')::interval) > v_curr_time
        ) THEN
          slot_time := v_curr_time;
          RETURN NEXT;
        END IF;

      -- Case B: Department-wide check (capacity = number of active doctors)
      ELSE
        IF (
          (
            SELECT COUNT(*) FROM public.appointments a
            WHERE a.appointment_date = p_date
              AND lower(trim(a.department)) = v_dept
              AND a.status NOT IN ('cancelled', 'missed')
              AND a.appointment_time < v_candidate_end
              AND (a.appointment_time + (coalesce(a.duration_minutes, 15) || ' minutes')::interval) > v_curr_time
          ) + (
            -- IMPORTANT: Only check UNPROMOTED pending requests to prevent double-counting!
            SELECT COUNT(*) FROM public.whatsapp_appointment_requests r
            WHERE r.requested_date = p_date
              AND lower(trim(r.department)) = v_dept
              AND r.status = 'pending_review'
              AND r.promoted_appointment_id IS NULL
              AND r.requested_time < v_candidate_end
              AND (r.requested_time + (coalesce(r.duration_minutes, 15) || ' minutes')::interval) > v_curr_time
          )
        ) < v_active_doc_count THEN
          slot_time := v_curr_time;
          RETURN NEXT;
        END IF;
      END IF;
    END IF;

    v_curr_time := v_curr_time + (p_interval_minutes || ' minutes')::interval;
  END LOOP;
END;
$$;

-- ============================================================================
-- RPC 3: Staff Approval Promotion (Dual Advisory Lock, Eligibility & Capacity Guard)
-- ============================================================================
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
  v_pending_doc_conflict INT := 0;
  v_total_dept_commitments INT := 0;
  v_duration INT;
  v_slot_end TIME;
  v_dept_capacity INT;
BEGIN
  -- 1. Server-side identity & role guard (Do NOT trust client-supplied reviewer)
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller is not authenticated.');
  END IF;

  SELECT role INTO v_caller_role 
  FROM public.profiles 
  WHERE id = v_caller_id AND is_active = true;

  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active clinic staff or administrators can approve requests.');
  END IF;

  -- 2. Lock the specific request record
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request record not found.');
  END IF;

  IF v_req.status <> 'pending_review' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request cannot be approved because it is currently in status: ' || v_req.status);
  END IF;

  -- 3. Validate requested duration
  v_duration := coalesce(v_req.duration_minutes, 15);
  IF v_duration <= 0 OR v_duration > 240 OR (v_duration % 15 <> 0) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid appointment duration: ' || v_duration || ' min.');
  END IF;

  -- 4. Effective Doctor ID Resolution (Fallback to request doctor if staff omitted)
  v_effective_doctor_id := coalesce(p_doctor_id, v_req.doctor_id);

  -- Validate doctor eligibility
  IF v_effective_doctor_id IS NOT NULL THEN
    SELECT id, full_name, department, is_active INTO v_doc
    FROM public.department_doctors
    WHERE id = v_effective_doctor_id;

    IF v_doc IS NULL THEN
      SELECT id, full_name, department, is_active INTO v_doc
      FROM public.profiles
      WHERE id = v_effective_doctor_id;
    END IF;

    IF v_doc IS NULL OR v_doc.is_active = false OR lower(trim(v_doc.department)) <> lower(trim(v_req.department)) THEN
      RETURN jsonb_build_object('success', false, 'message', 'Selected doctor is not eligible or active for ' || upper(v_req.department) || ' department.');
    END IF;
  END IF;

  -- 5. CRITICAL: Transactional Advisory Locks
  -- Department lock guarantees serialization between department-wide and doctor-specific bookings
  PERFORM pg_advisory_xact_lock(hashtext('appt_dept_lock_' || lower(trim(v_req.department)) || '_' || v_req.requested_date::text));
  IF v_effective_doctor_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('appt_doc_lock_' || v_effective_doctor_id::text || '_' || v_req.requested_date::text));
  END IF;

  v_slot_end := v_req.requested_time + (v_duration || ' minutes')::interval;

  -- 6. Dynamic department capacity calculation
  SELECT COUNT(*) INTO v_dept_capacity
  FROM public.department_doctors
  WHERE lower(trim(department)) = lower(trim(v_req.department)) AND is_active = true;

  IF v_dept_capacity = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'No active doctors configured for department: ' || upper(v_req.department));
  END IF;

  -- 7. Conflict detection (Appointments + Other Unpromoted Pending Requests)
  IF v_effective_doctor_id IS NOT NULL THEN
    -- Check doctor overlapping appointments
    SELECT COUNT(*) INTO v_doc_conflict
    FROM public.appointments
    WHERE appointment_date = v_req.requested_date
      AND (doctor_id = v_effective_doctor_id OR doctor_name = v_doc.full_name)
      AND status NOT IN ('cancelled', 'missed')
      AND appointment_time < v_slot_end
      AND (appointment_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > v_req.requested_time;

    -- Check other pending requests assigned to this doctor
    SELECT COUNT(*) INTO v_pending_doc_conflict
    FROM public.whatsapp_appointment_requests
    WHERE id <> p_request_id
      AND requested_date = v_req.requested_date
      AND doctor_id = v_effective_doctor_id
      AND status = 'pending_review'
      AND promoted_appointment_id IS NULL
      AND requested_time < v_slot_end
      AND (requested_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > v_req.requested_time;

    IF (v_doc_conflict + v_pending_doc_conflict) > 0 THEN
      RETURN jsonb_build_object(
        'success', false, 
        'message', 'Doctor conflict: ' || coalesce(v_doc.full_name, p_doctor_name, 'Selected doctor') || ' already has an overlapping commitment in this time window.'
      );
    END IF;
  END IF;

  -- Check overall department capacity
  SELECT (
    (SELECT COUNT(*) FROM public.appointments WHERE appointment_date = v_req.requested_date AND lower(trim(department)) = lower(trim(v_req.department)) AND status NOT IN ('cancelled', 'missed') AND appointment_time < v_slot_end AND (appointment_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > v_req.requested_time)
    +
    (SELECT COUNT(*) FROM public.whatsapp_appointment_requests WHERE id <> p_request_id AND requested_date = v_req.requested_date AND lower(trim(department)) = lower(trim(v_req.department)) AND status = 'pending_review' AND promoted_appointment_id IS NULL AND requested_time < v_slot_end AND (requested_time + (coalesce(duration_minutes, 15) || ' minutes')::interval) > v_req.requested_time)
  ) INTO v_total_dept_commitments;

  IF v_total_dept_commitments >= v_dept_capacity THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Department capacity reached: All consultation chairs in ' || upper(v_req.department) || ' are booked for this window.'
    );
  END IF;

  -- 8. Safe Doctor ID assignment (Only store in doctor_id if it exists in profiles to satisfy FK)
  v_appt_doc_id := CASE 
    WHEN v_effective_doctor_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id = v_effective_doctor_id) THEN v_effective_doctor_id
    ELSE NULL
  END;

  -- 9. Atomically insert into authoritative appointments table
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
    v_req.department,
    v_appt_doc_id,
    coalesce(p_doctor_name, v_doc.full_name, 'Attending Specialist'),
    v_req.requested_date,
    v_req.requested_time,
    v_duration,
    'regular',
    'confirmed',
    'Booked via WhatsApp. Approved by staff: ' || v_caller_id,
    true
  ) RETURNING id INTO v_new_appt_id;

  -- 10. Enable status update trigger session variable and promote request
  PERFORM set_config('mkes.rpc_status_update', 'active', true);

  UPDATE public.whatsapp_appointment_requests
  SET status = 'approved',
      promoted_appointment_id = v_new_appt_id,
      doctor_id = p_doctor_id,
      doctor_name = coalesce(p_doctor_name, v_doc.full_name),
      reviewed_by = v_caller_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  -- 11. Enqueue patient confirmation message
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    message_text
  ) VALUES (
    v_req.patient_phone,
    v_req.patient_id,
    v_req.department,
    'confirmation',
    '✅ *MKES CARE+ Appointment Confirmed!*' || E'\n\n' ||
    'Dear ' || v_req.patient_name || E',\n' ||
    'Your ' || upper(v_req.department) || ' appointment has been confirmed by our clinic team.' || E'\n\n' ||
    '📅 Date: ' || to_char(v_req.requested_date, 'DD Mon YYYY') || E'\n' ||
    '⏰ Time: ' || to_char(v_req.requested_time, 'HH12:MI AM') || E'\n' ||
    '👨‍⚕️ Doctor: ' || coalesce(p_doctor_name, v_doc.full_name, 'Attending Specialist') || E'\n\n' ||
    '📍 MKES CARE+ Hospital, Malad West\n' ||
    'Please arrive 10 minutes early.\nReply STOP to unsubscribe.'
  );

  RETURN jsonb_build_object('success', true, 'appointment_id', v_new_appt_id);
END;
$$;

-- ============================================================================
-- RPC 4: Staff Rejection Promotion (Strict pending_review Status Guard)
-- ============================================================================
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
BEGIN
  -- 1. Server-side identity & role guard
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller is not authenticated.');
  END IF;

  SELECT role INTO v_caller_role 
  FROM public.profiles 
  WHERE id = v_caller_id AND is_active = true;

  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only active staff or admins can reject requests.');
  END IF;

  -- 2. Lock and update request record
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request not found.');
  END IF;

  -- Allow rejection ONLY for requests in pending_review status
  IF v_req.status <> 'pending_review' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request cannot be rejected because it is currently in status: ' || v_req.status);
  END IF;

  -- 3. Set trigger override and update status
  PERFORM set_config('mkes.rpc_status_update', 'active', true);

  UPDATE public.whatsapp_appointment_requests
  SET status = 'rejected',
      staff_remarks = p_reason,
      reviewed_by = v_caller_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  -- 4. Enqueue courteous rejection notification to patient
  INSERT INTO public.whatsapp_messages_outbox (
    recipient_phone,
    patient_id,
    department,
    message_type,
    message_text
  ) VALUES (
    v_req.patient_phone,
    v_req.patient_id,
    v_req.department,
    'cancellation',
    'Dear ' || v_req.patient_name || E',\n' ||
    'Your appointment request for ' || to_char(v_req.requested_date, 'DD Mon') || ' at ' || to_char(v_req.requested_time, 'HH12:MI AM') || ' could not be accommodated: ' || coalesce(p_reason, 'Doctor unavailable') || E'.\n\n' ||
    'Please reply 1 to choose an alternative date.\nReply STOP to unsubscribe.'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- RPC 5: Automated Inbound Opt-Out (Service Role Exclusive, Cancels Pending & Processing)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.register_patient_whatsapp_opt_out(
  p_phone_number TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_digits TEXT := public.normalize_phone_10(p_phone_number);
BEGIN
  IF length(v_digits) < 10 THEN
    RETURN;
  END IF;

  -- 1. Mark patient as opted out
  UPDATE public.patients
  SET whatsapp_opt_out = true,
      updated_at = now()
  WHERE public.normalize_phone_10(mobile) = v_digits;

  -- 2. Cancel both pending and active processing outbox messages for this recipient
  UPDATE public.whatsapp_messages_outbox
  SET status = 'cancelled',
      last_error = 'Patient opted out via WhatsApp STOP command.',
      updated_at = now()
  WHERE public.normalize_phone_10(recipient_phone) = v_digits
    AND status IN ('pending', 'processing');
END;
$$;

-- ============================================================================
-- RPC 6: Staff-Initiated Opt-Out/Opt-In (Authenticated Staff & Admins Only)
-- ============================================================================
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
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Caller not authenticated.');
  END IF;

  SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Forbidden: Only clinic staff can update patient opt-out status.');
  END IF;

  SELECT * INTO v_patient FROM public.patients WHERE id = p_patient_id FOR UPDATE;
  IF v_patient IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Patient not found.');
  END IF;

  UPDATE public.patients
  SET whatsapp_opt_out = p_opt_out,
      updated_at = now()
  WHERE id = p_patient_id;

  IF p_opt_out = true THEN
    UPDATE public.whatsapp_messages_outbox
    SET status = 'cancelled',
        last_error = 'Patient opted out by clinic staff: ' || v_caller_id,
        updated_at = now()
    WHERE (patient_id = p_patient_id OR public.normalize_phone_10(recipient_phone) = public.normalize_phone_10(v_patient.mobile))
      AND status IN ('pending', 'processing');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. BATCH ENQUEUE FUNCTIONS FOR SCHEDULED AUTOMATION CATEGORIES
-- ----------------------------------------------------------------------------

-- A. Enqueue 24h & 2h Appointment Reminders
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
  v_clinic_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
  v_clinic_today DATE := v_clinic_now::DATE;
BEGIN
  -- Mutual exclusion: prevent concurrent execution between pg_cron and host scheduler
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_appointment_reminders')) THEN
    RETURN 0;
  END IF;

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
    END IF;
  END IF;

  -- 1. 24h reminders (appointments scheduled for tomorrow in clinic timezone IST)
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
    a.department,
    'reminder_24h',
    'reminder_24h',
    'Hello ' || coalesce(p.name, 'Valued Patient') || ', this is a reminder of your ' || upper(a.department) || ' appointment at MKES CARE+ on ' || to_char(a.appointment_date, 'DD Mon YYYY') || ' at ' || to_char(a.appointment_time, 'HH12:MI AM') || ' with ' || coalesce(a.doctor_name, 'Attending Specialist') || '.' || E'\n\n' || '📍 Location: MKES Hospital, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.',
    now()
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = (v_clinic_today + interval '1 day')::date
    AND a.status IN ('scheduled', 'confirmed')
    AND p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE (o.appointment_id = a.id OR (o.appointment_id IS NULL AND o.patient_id = p.id AND o.created_at >= (now() - interval '20 hours')))
        AND o.message_type = 'reminder_24h'
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;

  -- 2. 2h reminders (appointments scheduled for today approaching in next ~2 hours in clinic timezone IST)
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
    a.department,
    'reminder_2h',
    'reminder_2h',
    'Dear ' || coalesce(p.name, 'Valued Patient') || ', your ' || upper(a.department) || ' appointment is today at ' || to_char(a.appointment_time, 'HH12:MI AM') || ' (Doctor: ' || coalesce(a.doctor_name, 'Attending Specialist') || ').' || E'\n\n' || 'Please arrive 10 minutes early at MKES CARE+, Malad West.' || E'\n' || 'Reply STOP to unsubscribe.',
    now()
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = v_clinic_today
    AND a.status IN ('scheduled', 'confirmed')
    AND a.appointment_time >= v_clinic_now::TIME
    AND a.appointment_time <= (v_clinic_now + interval '2 hours 15 minutes')::TIME
    AND p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
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

-- B. Enqueue Annual Eye Checkup Reminders (11 Months Post-Visit)
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

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
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
    AND p.mobile IS NOT NULL
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

-- C. Enqueue Dental Follow-Ups (Cleaning 6 Months, RCT 7-14 Days, Implant 7 Days)
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

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
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
    AND p.mobile IS NOT NULL
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
    AND p.mobile IS NOT NULL
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
    AND p.mobile IS NOT NULL
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

-- D. Enqueue Patient Birthday Greetings
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

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
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
    AND p.mobile IS NOT NULL
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

-- E. Enqueue Google Review Requests (Completed Appointments 2 Hours Ago)
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
  v_clinic_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
  v_clinic_today DATE := v_clinic_now::DATE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_google_reviews')) THEN
    RETURN 0;
  END IF;

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
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
    a.department,
    'review_request',
    'review_request',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', thank you for visiting MKES CARE+ today.\n\nYour feedback helps us continuously improve our community healthcare services. Would you take 30 seconds to share your experience on Google?\n👉 https://g.page/r/mkes-care-plus/review\nReply STOP to unsubscribe.'
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  WHERE a.appointment_date = v_clinic_today
    AND a.status = 'completed'
    AND p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
    AND a.appointment_time <= (v_clinic_now - interval '2 hours')::TIME
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'review_request' AND o.created_at >= (now() - interval '60 days')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

-- F. Enqueue Billing Payment Reminders (Outstanding Balance)
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

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators or background workers can execute batch enqueue procedures.';
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
    b.department,
    'payment_reminder',
    'payment_reminder',
    'Dear ' || coalesce(p.name, 'Valued Patient') || E', this is a friendly reminder that a balance of ₹' || (b.total_amount - b.amount_paid)::text || ' remains pending for Invoice #' || coalesce(b.invoice_number, b.id::text) || ' at MKES CARE+.\n\nPlease settle this at the hospital billing desk at your convenience.\nReply STOP to unsubscribe.'
  FROM public.billing b
  JOIN public.patients p ON p.id = b.patient_id
  WHERE p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
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

-- G. Enqueue Festival Greeting Broadcast (Admin Initiated)
CREATE OR REPLACE FUNCTION public.enqueue_festival_greeting_broadcast(
  p_festival_name TEXT,
  p_custom_greeting TEXT DEFAULT NULL
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
  v_body TEXT;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('mkes_wa_batch_festival_broadcast')) THEN
    RETURN 0;
  END IF;

  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id AND is_active = true;
    IF v_caller_role NOT IN ('admin') THEN
      RAISE EXCEPTION 'Forbidden: Only administrators can trigger festival greeting broadcasts.';
    END IF;
  END IF;

  v_body := coalesce(
    p_custom_greeting,
    '✨ *Warm ' || coalesce(p_festival_name, 'Festival') || ' Greetings from MKES CARE+ Hospital!*\n\nMay this auspicious occasion bring peace, prosperity, and radiant health to you and your family.\nReply STOP to unsubscribe.'
  );

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
    'festival',
    'festival',
    v_body
  FROM public.patients p
  WHERE p.whatsapp_opt_out = false
    AND p.mobile IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.whatsapp_messages_outbox o
      WHERE o.patient_id = p.id AND o.message_type = 'festival' AND o.created_at >= (now() - interval '24 hours')
    );

  GET DIAGNOSTICS v_enqueued_count = ROW_COUNT;
  RETURN v_enqueued_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- 11. AUTOMATIC CRON SCHEDULING (INTENTIONALLY DISABLED)
-- Review timezone, schema compatibility, consent checks, and operational readiness
-- before scheduling any enqueue functions. Register jobs separately after approval.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 12. PERMISSION GRANTS (LEAST PRIVILEGE)
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.approve_whatsapp_appointment_request(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_whatsapp_appointment_request(UUID, UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.reject_whatsapp_appointment_request(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_whatsapp_appointment_request(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_available_appointment_slots(TEXT, DATE, INT, INT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_appointment_slots(TEXT, DATE, INT, INT, UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.claim_whatsapp_outbox_batch(UUID, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_whatsapp_outbox_batch(UUID, INT, INT) TO service_role;

-- Opt-out RPC is strictly restricted to service_role (cannot be called by arbitrary authenticated users)
REVOKE ALL ON FUNCTION public.register_patient_whatsapp_opt_out(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_patient_whatsapp_opt_out(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.register_patient_whatsapp_opt_out(TEXT) TO service_role;

-- Staff-managed opt-out is granted to authenticated staff
REVOKE ALL ON FUNCTION public.set_patient_whatsapp_opt_out(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_patient_whatsapp_opt_out(UUID, BOOLEAN) TO authenticated, service_role;

-- Batch enqueue functions granted to service_role and authenticated staff/admin
REVOKE ALL ON FUNCTION public.enqueue_appointment_reminders_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_appointment_reminders_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_annual_eye_reminders_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_annual_eye_reminders_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_dental_followups_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_dental_followups_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_birthday_greetings_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_birthday_greetings_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_google_review_requests_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_google_review_requests_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_billing_payment_reminders_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_billing_payment_reminders_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_festival_greeting_broadcast(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_festival_greeting_broadcast(TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

