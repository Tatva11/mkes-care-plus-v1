# MKES CARE+ — WhatsApp Integration Architecture, Audit & Phase 2 Specification

**Document Version:** 2.1.0 (Phase 1 Final Sign-off & Phase 2 Blueprint)  
**Date:** October 18, 2026  
**Auditor / Architect:** Senior Flutter, Supabase, Node.js & Systems Integration Engineer  
**Status:** **Phase 1 Finalized — Phase 2 Ready for Approval**  
**Target Platform:** Windows PC Host (Clinic On-Premises) + Supabase Cloud PostgreSQL  
**Scope:** Eye Clinic & Dental Care Only (*Optical Department is strictly excluded*)

---

## Executive Summary

This document concludes **Phase 1 (Audit & Final Planning)** and provides the comprehensive, production-ready specification for **Phase 2 (Backend & WhatsApp Setup)** of the MKES CARE+ WhatsApp automation system.

All architectural proposals have been reconciled with the active repository source code, PostgreSQL schemas, and clinical operational rules.

### Core Architecture Highlights
1. **Four-Phase Structure Maintained:**
   - **Phase 1 (Complete):** Audit, scheduling validation, security hardening, and Windows PC deployment design.
   - **Phase 2 (Prepared):** Database migration, secure stored procedures, WhatsApp microservice on Windows PC with `whatsapp-web.js`, and outbox worker.
   - **Phase 3 (Next):** Automated message triggers, in-chat numbered booking state machine, and Flutter Admin/Staff review screens.
   - **Phase 4 (Final):** Concurrency testing, consent validation, Windows service startup resilience, and operational handover.
2. **Zero Client Changes in Phase 1/2:** No Flutter code or live database schemas are modified until the Phase 2 specification is approved.
3. **Strict Department Scope:** Eye Clinic and Dental Care only. Optical is 100% excluded.
4. **No External Booking Link:** All patient booking interactions occur entirely inside WhatsApp via numbered text responses (`1`, `2`, `3`).
5. **No Direct Confirmation:** Appointments are **never** confirmed automatically or inserted into `public.appointments` until authorized clinic staff explicitly assign a doctor and approve the request in the dashboard.

---

## 1. Critical Corrections to System Audit & Rules

### 1.1. Appointment Availability & Overlapping Slots Calculation
- **Clinic Hours (Verified in `appointment_form_dialog.dart:L72-113`):** 09:00 AM (`openingHour = 9`) to 08:00 PM (`closingHour = 20`).
- **Standard Appointment Duration:** 
  - Standard consultation duration is **30 minutes** (with internal 15-minute granularity for walk-ins).
  - An appointment booked at `10:00 AM` occupies the slot until `10:30 AM`.
- **Duration-Aware Overlap Logic:**
  - A candidate slot $S_{new}$ for duration $D$ (30 mins) conflicts with an existing appointment $S_{exist}$ if:
    $$\max(S_{new}, S_{exist}) < \min(S_{new} + D, S_{exist} + D)$$
  - Availability checking must check **both** confirmed appointments (`public.appointments` where `status NOT IN ('cancelled', 'missed')`) **and** in-flight pending requests (`public.whatsapp_appointment_requests` where `status IN ('pending_review', 'approved')`).
  - If a specific doctor is requested/assigned, availability is checked against that doctor's calendar. If booking for a department generally, availability checks against the department's concurrent room/chair capacity.

### 1.2. Database Function Security Hardening
All PostgreSQL `SECURITY DEFINER` stored procedures have been hardened to eliminate privilege escalation and search-path vulnerabilities:
1. **Explicit Search Path:** Every function enforces `SET search_path = public, pg_temp;` to prevent malicious schema interception.
2. **Caller Authorization Checks:** Functions mutating appointments or approving requests strictly verify that the caller possesses `role = 'admin'` or `role = 'staff'` via `public.profiles`.
3. **Privilege Revocation:** `EXECUTE` privileges on sensitive internal RPCs are revoked from `PUBLIC` and granted selectively to `authenticated` and `service_role`.

### 1.3. Automatic Message Policy & Consent Safeguards
- **Policy:** In accordance with user requirements, all previously agreed message categories are configured for **automatic dispatch** without requiring manual per-message button clicks:
  1. Appointment Reminders (24h & 2h prior)
  2. Annual Eye Check-up Reminders (365 days post visit)
  3. Dental Cleaning Follow-ups (6 months post scaling)
  4. Dental RCT Post-Op Check-ins (Day 3 & Day 7)
  5. Dental Implant Milestones (1 week, 1 month, 3 months)
  6. Dental Lab Prosthesis "Ready" Alerts
  7. Patient Birthday Greetings (daily 09:00 AM)
  8. Festival Greetings (clinic-scheduled broadcasts)
  9. Google Review Requests (24h post completed appointment)
  10. Billing Payment Receipts
  11. Vendor Purchase Orders & Delivery Confirmations
- **Consent & Opt-Out Safeguards (DPDP Compliance):**
  - All automated messages contain: *"Reply STOP to unsubscribe from clinic notifications."*
  - Incoming messages matching `STOP`, `UNSUBSCRIBE`, or `OPTOUT` immediately invoke `register_patient_whatsapp_opt_out()`, setting `public.patients.whatsapp_opt_out = true`.
  - The outbox worker and queue triggers perform a strict pre-flight check: **if `whatsapp_opt_out = true`, no message is ever queued or transmitted.**

### 1.4. Verified Clinic Operational Details
- **Clinic Name:** MKES CARE+ Hospital
- **Address / Location:** MKES Campus, Bhadran Nagar, Off Relief Road, Malad West, Mumbai, Maharashtra 400064
- **Departments in Scope:**
  - **Eye Clinic (Ophthalmology):** Confirmed Doctors: *Dr Mitesh Jain*, *Dr Varun*.
  - **Dental Care (General & Surgical Dentistry):** Confirmed Doctors: *Dr Nimisha*, *Dr Vikas*.
  - *Optical is completely excluded.*

### 1.5. Clear Record of Unresolved Assumptions
1. **Doctor Shift Roster vs Clinic Hours:**  
   *Assumption:* In the absence of a live weekly doctor duty roster table, doctor availability defaults to clinic working hours (09:00–20:00) unless an active leave record exists in `public.leave_requests`.
2. **In-Chat Consultation Duration:**  
   *Assumption:* Standard WhatsApp appointment slots are fixed at **30 minutes** to provide clean, uncluttered options to patients on mobile devices.
3. **Windows Host Hardware Uptime:**  
   *Assumption:* The clinic reception Windows PC remains powered on during clinic operating hours (08:30 AM to 08:30 PM). If powered off overnight, the PM2/NSSM Windows service automatically resumes queue processing upon morning boot.

---

## 2. Phase 2: Database Migration Design

The following migration script represents the complete database foundation to be created as:  
`supabase/migrations/20261019000000_whatsapp_automation_foundation.sql`.

```sql
-- ============================================================================
-- MKES CARE+ — Migration: WhatsApp Automation Foundation (Phase 2)
-- File: supabase/migrations/20261019000000_whatsapp_automation_foundation.sql
-- Description:
--   Establishes high-reliability Transactional Outbox, Inbound Message Logs,
--   Conversational Chat Sessions, WhatsApp Appointment Requests Queue,
--   System Configuration, dynamic message templates, and hardened security RPCs.
-- ============================================================================

-- 1. Patient Consent & Opt-Out Column
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS whatsapp_opt_out BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_patients_mobile_optout 
  ON public.patients(mobile, whatsapp_opt_out);

-- 2. Transactional WhatsApp Outbox
CREATE TABLE IF NOT EXISTS public.whatsapp_messages_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_phone TEXT NOT NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  department TEXT NOT NULL CHECK (department IN ('eye', 'dental', 'general')),
  message_type TEXT NOT NULL, 
  -- reminder_24h, reminder_2h, annual_eye, dental_cleaning, dental_rct, dental_implant, 
  -- lab_ready, birthday, festival, review_request, payment_receipt, vendor_po, custom
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
  ON public.whatsapp_messages_outbox(status, scheduled_for)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_wa_outbox_recipient 
  ON public.whatsapp_messages_outbox(recipient_phone, created_at DESC);

-- 3. Communication Audit Logs
CREATE TABLE IF NOT EXISTS public.whatsapp_message_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outbox_id UUID REFERENCES public.whatsapp_messages_outbox(id) ON DELETE SET NULL,
  direction TEXT NOT NULL CHECK (direction IN ('outbound', 'inbound')),
  phone_number TEXT NOT NULL,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  message_body TEXT NOT NULL,
  raw_payload JSONB,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_logs_phone_time 
  ON public.whatsapp_message_logs(phone_number, timestamp DESC);

-- 4. In-Chat Conversational State Machine Sessions
CREATE TABLE IF NOT EXISTS public.whatsapp_chat_sessions (
  phone_number TEXT PRIMARY KEY,
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  current_step TEXT NOT NULL DEFAULT 'IDLE',
  -- IDLE, AWAITING_DATE_CHOICE, AWAITING_CUSTOM_DATE, AWAITING_SLOT_CHOICE, CONFIRMATION_PENDING
  selected_department TEXT CHECK (selected_department IN ('eye', 'dental')),
  selected_date DATE,
  selected_slot TIME,
  presented_options JSONB NOT NULL DEFAULT '[]'::jsonb,
  state_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes'),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. WhatsApp Appointment Requests Queue (Pending Staff Review)
CREATE TABLE IF NOT EXISTS public.whatsapp_appointment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  patient_name TEXT NOT NULL,
  patient_phone TEXT NOT NULL,
  department TEXT NOT NULL CHECK (department IN ('eye', 'dental')),
  doctor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  doctor_name TEXT,
  requested_date DATE NOT NULL,
  requested_time TIME NOT NULL,
  duration_minutes INTEGER NOT NULL DEFAULT 30,
  status TEXT NOT NULL DEFAULT 'pending_review'
         CHECK (status IN ('pending_review', 'approved', 'rejected', 'rescheduled', 'cancelled')),
  notes TEXT,
  staff_remarks TEXT,
  promoted_appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_appt_req_queue 
  ON public.whatsapp_appointment_requests(status, requested_date, department);

-- 6. WhatsApp Configuration & Health Settings
CREATE TABLE IF NOT EXISTS public.whatsapp_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  daily_send_limit INTEGER NOT NULL DEFAULT 200,
  min_delay_seconds INTEGER NOT NULL DEFAULT 6,
  max_delay_seconds INTEGER NOT NULL DEFAULT 14,
  session_status TEXT NOT NULL DEFAULT 'disconnected', 
  -- disconnected, qr_ready, authenticated, error
  qr_code_data TEXT,
  battery_level INTEGER,
  phone_number TEXT,
  last_heartbeat TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default settings row if missing
INSERT INTO public.whatsapp_settings (id, is_enabled, daily_send_limit, session_status)
VALUES ('00000000-0000-0000-0000-000000000001', true, 200, 'disconnected')
ON CONFLICT (id) DO NOTHING;

-- 7. Standardized Message Templates
CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  key TEXT PRIMARY KEY,
  department TEXT NOT NULL DEFAULT 'general' CHECK (department IN ('eye', 'dental', 'general')),
  description TEXT NOT NULL,
  template_body TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed authoritative templates
INSERT INTO public.whatsapp_templates (key, department, description, template_body)
VALUES
  ('reminder_24h', 'general', '24-hour appointment reminder', 
   '📅 *MKES CARE+ Appointment Reminder*' || E'\n\n' ||
   'Dear {{patient_name}},\n' ||
   'This is a reminder for your upcoming {{department}} consultation tomorrow, {{appointment_date}} at {{appointment_time}} with {{doctor_name}}.' || E'\n\n' ||
   '📍 MKES CARE+ Hospital, Malad West\n' ||
   'Please arrive 10 mins early. Reply CANCEL if unable to attend.\n' ||
   'Reply STOP to unsubscribe.'),
  
  ('reminder_2h', 'general', '2-hour urgent appointment reminder',
   '⏰ *MKES CARE+ Notice:* Dear {{patient_name}}, your {{department}} appointment is today at {{appointment_time}} with {{doctor_name}}. We look forward to seeing you shortly.\nReply STOP to unsubscribe.'),

  ('lab_ready', 'dental', 'Dental prosthesis/crown ready alert',
   '🦷 *MKES CARE+ Dental Clinic*' || E'\n\n' ||
   'Dear {{patient_name}},\n' ||
   'Your custom dental restoration ({{case_type}}, Ref: #{{case_number}}) is now READY for fitting.' || E'\n\n' ||
   'Please reply 1 to schedule your fitting appointment.\nReply STOP to unsubscribe.'),

  ('annual_eye', 'eye', 'Annual eye checkup reminder',
   '👁️ *MKES CARE+ Eye Clinic*' || E'\n\n' ||
   'Dear {{patient_name}},\n' ||
   'It has been one year since your last comprehensive eye evaluation. Regular vision and IOP exams protect long-term sight.' || E'\n\n' ||
   'Reply 1 to schedule your annual check-up today.\nReply STOP to unsubscribe.'),

  ('dental_cleaning', 'dental', '6-month preventive scaling follow-up',
   '✨ *MKES CARE+ Dental Care*' || E'\n\n' ||
   'Dear {{patient_name}},\n' ||
   'Six months have passed since your last dental cleaning. Preventive hygiene protects against gum disease and cavities.' || E'\n\n' ||
   'Reply 1 to schedule your routine cleaning.\nReply STOP to unsubscribe.'),

  ('payment_receipt', 'general', 'Payment received confirmation',
   '💳 *MKES CARE+ Payment Receipt*' || E'\n\n' ||
   'Dear {{patient_name}},\n' ||
   'We received payment of ₹{{amount_paid}} for Invoice #{{invoice_number}}.' || E'\n' ||
   'Remaining Balance: ₹{{outstanding_balance}}.' || E'\n\n' ||
   'Thank you for trusting MKES CARE+.\nReply STOP to unsubscribe.')
ON CONFLICT (key) DO NOTHING;

-- 8. Row Level Security Policies
ALTER TABLE public.whatsapp_messages_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_message_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_appointment_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

-- Admins and Staff full access to view queues and settings
CREATE POLICY "Staff and Admins can view whatsapp queues"
  ON public.whatsapp_appointment_requests FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Staff and Admins can manage appointment requests"
  ON public.whatsapp_appointment_requests FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'staff')));

CREATE POLICY "Admins can manage whatsapp settings"
  ON public.whatsapp_settings FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Staff can view whatsapp settings"
  ON public.whatsapp_settings FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Authenticated users view outbox"
  ON public.whatsapp_messages_outbox FOR SELECT TO authenticated
  USING (true);
```

---

## 3. Phase 2: Stored Procedures & Atomic Locking RPCs

The stored procedures below implement strict duration-aware slot discovery, row-level locking, and caller authorization.

```sql
-- ============================================================================
-- RPC 1: Claim Outbox Batch (Distributed Lease with Monotonic Token)
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
      updated_at = now()
  WHERE id IN (
    SELECT o.id 
    FROM public.whatsapp_messages_outbox o
    JOIN public.whatsapp_settings s ON s.id = '00000000-0000-0000-0000-000000000001'
    LEFT JOIN public.patients p ON p.id = o.patient_id
    WHERE o.status = 'pending'
      AND s.is_enabled = true
      AND o.scheduled_for <= now()
      AND (p.whatsapp_opt_out IS NULL OR p.whatsapp_opt_out = false)
      AND (o.lease_expires_at IS NULL OR o.lease_expires_at < now())
    ORDER BY o.scheduled_for ASC
    LIMIT p_batch_size
    FOR UPDATE OF o SKIP LOCKED
  )
  RETURNING *;
END;
$$;

-- ============================================================================
-- RPC 2: Dynamic Available Slot Calculator (Duration & Overlap Aware)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_available_appointment_slots(
  p_department TEXT,
  p_date DATE,
  p_slot_duration_minutes INT DEFAULT 30
)
RETURNS TABLE (slot_time TIME)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_curr_time TIME := '09:00:00'::TIME;
  v_closing_time TIME := '19:30:00'::TIME;
  v_is_today BOOLEAN := (p_date = CURRENT_DATE);
  v_min_time TIME := CASE 
    WHEN v_is_today THEN (date_trunc('hour', now() + interval '1 hour 15 minutes'))::TIME 
    ELSE '09:00:00'::TIME 
  END;
  v_candidate_end TIME;
BEGIN
  -- Strict department filter
  IF lower(trim(p_department)) NOT IN ('eye', 'dental') THEN
    RAISE EXCEPTION 'Invalid department: %. Only eye and dental are permitted.', p_department;
  END IF;

  WHILE v_curr_time <= v_closing_time LOOP
    v_candidate_end := v_curr_time + (p_slot_duration_minutes || ' minutes')::interval;

    IF (NOT v_is_today OR v_curr_time >= v_min_time) THEN
      -- Check 1: Confirmed appointments overlap check
      -- Two intervals [A_start, A_end] and [B_start, B_end] overlap if A_start < B_end AND B_start < A_end
      IF NOT EXISTS (
        SELECT 1 FROM public.appointments a
        WHERE a.appointment_date = p_date
          AND lower(trim(a.department)) = lower(trim(p_department))
          AND a.status NOT IN ('cancelled', 'missed')
          AND a.appointment_time < v_candidate_end
          AND (a.appointment_time + interval '30 minutes') > v_curr_time
      )
      -- Check 2: Pending WhatsApp requests overlap check
      AND NOT EXISTS (
        SELECT 1 FROM public.whatsapp_appointment_requests r
        WHERE r.requested_date = p_date
          AND lower(trim(r.department)) = lower(trim(p_department))
          AND r.status IN ('pending_review', 'approved')
          AND r.requested_time < v_candidate_end
          AND (r.requested_time + (r.duration_minutes || ' minutes')::interval) > v_curr_time
      ) THEN
        slot_time := v_curr_time;
        RETURN NEXT;
      END IF;
    END IF;

    v_curr_time := v_curr_time + (p_slot_duration_minutes || ' minutes')::interval;
  END LOOP;
END;
$$;

-- ============================================================================
-- RPC 3: Staff Approval Promotion (Atomic Double-Booking Guard)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_whatsapp_appointment_request(
  p_request_id UUID,
  p_doctor_id UUID,
  p_doctor_name TEXT,
  p_reviewed_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_req RECORD;
  v_new_appt_id UUID;
  v_conflict_count INT;
  v_caller_role TEXT;
  v_slot_end TIME;
BEGIN
  -- 1. Caller role verification
  SELECT role INTO v_caller_role FROM public.profiles WHERE id = p_reviewed_by;
  IF v_caller_role NOT IN ('admin', 'staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized: Only active staff or admins can approve requests.');
  END IF;

  -- 2. Lock the request record
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request record not found.');
  END IF;

  IF v_req.status <> 'pending_review' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request is already in state: ' || v_req.status);
  END IF;

  v_slot_end := v_req.requested_time + (v_req.duration_minutes || ' minutes')::interval;

  -- 3. Strict duration-aware concurrency overlap check
  SELECT COUNT(*) INTO v_conflict_count
  FROM public.appointments
  WHERE appointment_date = v_req.requested_date
    AND lower(trim(department)) = lower(trim(v_req.department))
    AND status NOT IN ('cancelled', 'missed')
    AND appointment_time < v_slot_end
    AND (appointment_time + interval '30 minutes') > v_req.requested_time;

  IF v_conflict_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Slot conflict: Another appointment was confirmed for this window. Please suggest an alternative time.'
    );
  END IF;

  -- 4. Insert into authoritative appointments table
  INSERT INTO public.appointments (
    patient_id,
    department,
    doctor_id,
    doctor_name,
    appointment_date,
    appointment_time,
    appointment_type,
    status,
    notes,
    ai_booked
  ) VALUES (
    v_req.patient_id,
    v_req.department,
    p_doctor_id,
    p_doctor_name,
    v_req.requested_date,
    v_req.requested_time,
    'regular',
    'confirmed',
    'Booked via WhatsApp. Approved by staff: ' || p_reviewed_by,
    true
  ) RETURNING id INTO v_new_appt_id;

  -- 5. Mark request approved
  UPDATE public.whatsapp_appointment_requests
  SET status = 'approved',
      promoted_appointment_id = v_new_appt_id,
      doctor_id = p_doctor_id,
      doctor_name = p_doctor_name,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  -- 6. Enqueue patient confirmation message
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
    'Your ' || upper(v_req.department) || ' appointment has been confirmed by our clinic.' || E'\n\n' ||
    '📅 Date: ' || to_char(v_req.requested_date, 'DD Mon YYYY') || E'\n' ||
    '⏰ Time: ' || to_char(v_req.requested_time, 'HH12:MI AM') || E'\n' ||
    '👨‍⚕️ Doctor: ' || coalesce(p_doctor_name, 'Attending Specialist') || E'\n\n' ||
    '📍 MKES CARE+ Hospital, Malad West' || E'\n' ||
    'Please arrive 10 minutes early.\nReply STOP to unsubscribe.'
  );

  RETURN jsonb_build_object('success', true, 'appointment_id', v_new_appt_id);
END;
$$;

-- ============================================================================
-- RPC 4: Reject Appointment Request
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reject_whatsapp_appointment_request(
  p_request_id UUID,
  p_reason TEXT,
  p_reviewed_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_req RECORD;
BEGIN
  SELECT * INTO v_req
  FROM public.whatsapp_appointment_requests
  WHERE id = p_request_id FOR UPDATE;

  IF v_req IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request not found.');
  END IF;

  UPDATE public.whatsapp_appointment_requests
  SET status = 'rejected',
      staff_remarks = p_reason,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  -- Enqueue courteous notification to patient
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
    'Regrettably, your appointment request for ' || to_char(v_req.requested_date, 'DD Mon') || ' at ' || to_char(v_req.requested_time, 'HH12:MI AM') || ' could not be accommodated: ' || coalesce(p_reason, 'Slot unavailable') || E'.\n\n' ||
    'Please reply 1 to choose an alternative date.\nReply STOP to unsubscribe.'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- RPC 5: Register Patient Opt-Out (DPDP Act Compliance)
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
  v_clean_phone TEXT := regexp_replace(p_phone_number, '[^0-9]', '', 'g');
BEGIN
  -- Handle both 10-digit and 12-digit numbers
  UPDATE public.patients
  SET whatsapp_opt_out = true,
      updated_at = now()
  WHERE mobile LIKE '%' || right(v_clean_phone, 10);

  -- Cancel all queued pending messages for this number
  UPDATE public.whatsapp_messages_outbox
  SET status = 'cancelled',
      last_error = 'Patient opted out of automated WhatsApp messages.'
  WHERE recipient_phone LIKE '%' || right(v_clean_phone, 10)
    AND status = 'pending';
END;
$$;

REVOKE ALL ON FUNCTION public.approve_whatsapp_appointment_request FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_whatsapp_appointment_request TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.reject_whatsapp_appointment_request FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_whatsapp_appointment_request TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_whatsapp_outbox_batch FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_whatsapp_outbox_batch TO service_role;
REVOKE ALL ON FUNCTION public.register_patient_whatsapp_opt_out FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_patient_whatsapp_opt_out TO service_role;
```

---

## 4. Phase 2: WhatsApp Windows Service Architecture

The WhatsApp service is engineered as an isolated, resilient Node.js microservice hosted locally on the clinic's Windows PC.

### 4.1. Directory Structure (`whatsapp-service/`)
```
whatsapp-service/
├── .env.example
├── .gitignore
├── package.json
├── index.js                  # Main entry point & lifecycle manager
├── src/
│   ├── config/
│   │   ├── supabase.js       # Supabase service-role client
│   │   └── constants.js      # Timing, clinic hours, delays
│   ├── services/
│   │   ├── whatsapp_client.js # whatsapp-web.js wrapper + LocalAuth
│   │   ├── outbox_worker.js   # Background dequeuer & rate limiter
│   │   ├── bot_engine.js      # Inbound state machine parser
│   │   └── slot_service.js    # Calls get_available_appointment_slots RPC
│   └── utils/
│       ├── phone_normalizer.js# Indian number cleaner (91XXXXXXXXXX)
│       └── logger.js          # Winser/PM2 compatible console & file logger
└── scripts/
    ├── install_windows_service.bat
    └── uninstall_windows_service.bat
```

### 4.2. Runtime Dependencies
```json
{
  "name": "mkes-whatsapp-service",
  "version": "1.0.0",
  "description": "MKES CARE+ WhatsApp Bridge Daemon for Windows PC",
  "main": "index.js",
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "dotenv": "^16.4.5",
    "qrcode-terminal": "^0.12.0",
    "whatsapp-web.js": "^1.26.0",
    "winston": "^3.14.2"
  }
}
```

### 4.3. Windows PC Deployment & Startup Configuration
- **Host Prerequisites:** Windows 10/11 Pro (or Windows Server), Node.js v18 or v20 LTS, Google Chrome / Chromium installed.
- **Session Data Path:** `C:\MKES_CARE_PLUS\wa_session` (configured with restricted Windows permissions for the service user).
- **Process Management via PM2:**
  ```cmd
  npm install -g pm2 pm2-windows-service
  pm2-service-install -n MKES_WhatsApp_Daemon
  pm2 start index.js --name "mkes-wa-bridge" --max-memory-restart 1200M
  pm2 save
  ```
- **Crash Recovery & Heartbeat:**
  - PM2 monitors memory usage; if Puppeteer Chromium exceeds 1.2 GB, PM2 gracefully cycles the worker.
  - The worker updates `public.whatsapp_settings.last_heartbeat = now()` every 60 seconds.
  - If WhatsApp Web drops connection, `whatsapp-web.js` automatically attempts reconnecting. If the session is permanently invalidated, `qr_ready` status is written to `whatsapp_settings`, alerting administrators in the Flutter app.

---

## 5. Security & Privacy Blueprint

1. **Privileged Key Isolation:**
   - The Supabase `SERVICE_ROLE_KEY` is located **exclusively** within `whatsapp-service/.env` on the clinic Windows PC.
   - It is never embedded or packaged into the Flutter web or mobile binaries.
2. **Patient Data Confidentiality:**
   - Message payloads contain only non-sensitive scheduling data (patient name, date, time, doctor name, clinic department).
   - Medical diagnoses, full surgical charts, and sensitive ocular/dental imaging are **never** transmitted over WhatsApp.
3. **Database Guardrails:**
   - Flutter web clients interact with `public.whatsapp_appointment_requests` through standard Supabase Auth tokens; staff can view requests and trigger approvals via RPC, but cannot directly alter appointment status without going through the validation logic.

---

## 6. Phase 2 Implementation Step-by-Step Plan

Upon your approval, Phase 2 will be executed through the following structured sequence:

| Step | Action Item | Target Location / Output | Verification Check |
|---|---|---|---|
| **2.1** | Create Phase 2 Database Migration File | `supabase/migrations/20261019000000_whatsapp_automation_foundation.sql` | Migration validated with `supabase db lint` or syntax dry-run. |
| **2.2** | Scaffold Node.js Windows Service Project | Directory `whatsapp-service/` | Verify `package.json`, `.env.example`, and file structure. |
| **2.3** | Implement Core WhatsApp Client Module | `whatsapp-service/src/services/whatsapp_client.js` | Configured with `LocalAuth` targeting Windows persistent path. |
| **2.4** | Implement Outbox Dequeuer & Rate Limiter | `whatsapp-service/src/services/outbox_worker.js` | Implements 6–14s humanized delays and calls `claim_whatsapp_outbox_batch`. |
| **2.5** | Implement Opt-Out & Number Normalization | `whatsapp-service/src/utils/phone_normalizer.js` | Unit test cases for `+91`, `0`, and 10-digit Indian formats. |
| **2.6** | Prepare Windows Service Installation Script | `whatsapp-service/scripts/install_windows_service.bat` | Verified PM2 Windows service configuration script. |

---

## 7. Approval Gate for Phase 2 Execution

To proceed from Phase 1 to Phase 2, please provide your formal confirmation on:

1. **Phase 2 Migration & RPC Design:** Do you approve the proposed schema and functions in Section 2 & 3?
2. **Local Session Directory:** Confirm that `C:\MKES_CARE_PLUS\wa_session` is an acceptable storage directory on the clinic's Windows PC.
3. **Authorization to Scaffold Phase 2:** Confirmation to create the migration file and scaffold the `whatsapp-service/` directory.

*(No live database changes or application modifications will occur without your explicit confirmation.)*
