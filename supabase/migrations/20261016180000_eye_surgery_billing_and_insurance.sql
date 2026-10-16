-- =============================================================================
-- Migration: 20261016180000_eye_surgery_billing_and_insurance.sql
-- Description: Eye Surgery Billing & Insurance Feature
--   1. Updates eye_surgeries status constraint and transition trigger to add 'billing'
--      Workflow: scheduled -> pre_op -> in_surgery -> post_op -> billing -> discharged
--   2. Links public.billing (invoices) to public.eye_surgeries (eye_surgery_id)
--   3. Updates create_billing_invoice RPC to accept p_eye_surgery_id
--   4. Creates public.eye_surgery_insurances (cashless & reimbursement tracking)
--   5. Creates public.eye_surgery_insurance_payments (multiple payments & audit trail)
--   6. Enforces strict RLS policies: only admin and staff can manage
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: ADD 'billing' STATUS TO public.eye_surgeries
-- =============================================================================

ALTER TABLE public.eye_surgeries
  DROP CONSTRAINT IF EXISTS eye_surgeries_status_check;

ALTER TABLE public.eye_surgeries
  ADD CONSTRAINT eye_surgeries_status_check
  CHECK (status IN ('scheduled', 'pre_op', 'in_surgery', 'post_op', 'billing', 'discharged', 'cancelled', 'missed'));

-- Update status transition trigger to permit:
--   post_op -> billing (or discharged for backwards compat, or cancelled)
--   billing -> discharged (or cancelled)
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
      OR (OLD.status = 'post_op' AND NEW.status IN ('billing', 'discharged', 'cancelled'))
      OR (OLD.status = 'billing' AND NEW.status IN ('discharged', 'cancelled'))
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


-- =============================================================================
-- STEP 2: LINK public.billing TO public.eye_surgeries
-- =============================================================================

ALTER TABLE public.billing
  ADD COLUMN IF NOT EXISTS eye_surgery_id UUID REFERENCES public.eye_surgeries(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_billing_eye_surgery_id
  ON public.billing(eye_surgery_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_unique_active_eye_surgery
  ON public.billing (eye_surgery_id)
  WHERE eye_surgery_id IS NOT NULL AND payment_status != 'cancelled';


-- =============================================================================
-- STEP 3: UPDATE create_billing_invoice RPC TO SUPPORT p_eye_surgery_id
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_billing_invoice(
  p_patient_id uuid,
  p_department text,
  p_discount numeric DEFAULT 0,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_payment jsonb DEFAULT null,
  p_invoice_date date DEFAULT current_date,
  p_notes text DEFAULT null,
  p_eye_surgery_id uuid DEFAULT null
)
RETURNS public.billing
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_department text := lower(trim(p_department));
  v_fy_code text;
  v_next_seq integer;
  v_invoice_number text;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := COALESCE(p_discount, 0);
  v_total_amount numeric(12,2) := 0;
  v_item jsonb;
  v_item_service_id uuid;
  v_item_service_name text;
  v_item_qty integer;
  v_item_price numeric(12,2);
  v_item_total numeric(12,2);
  v_item_is_custom boolean;
  v_billing public.billing;
  v_payment_mode text;
  v_payment_amount numeric(12,2) := 0;
  v_payment_ref text;
  v_payment_status text := 'pending';
BEGIN
  -- Department validation (Eye + Dental only)
  IF v_department NOT IN ('eye', 'dental') THEN
    RAISE EXCEPTION 'Invalid billing department: %. Must be eye or dental.', p_department
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Patient validation
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = p_patient_id) THEN
    RAISE EXCEPTION 'Patient with ID % does not exist.', p_patient_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- If eye_surgery_id provided, validate existence and patient match
  IF p_eye_surgery_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.eye_surgeries
      WHERE id = p_eye_surgery_id AND patient_id = p_patient_id
    ) THEN
      RAISE EXCEPTION 'Eye surgery with ID % does not belong to patient %.', p_eye_surgery_id, p_patient_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Duplicate prevention: prevent duplicate active invoice for the same surgery
    IF EXISTS (
      SELECT 1 FROM public.billing
      WHERE eye_surgery_id = p_eye_surgery_id AND payment_status != 'cancelled'
    ) THEN
      RAISE EXCEPTION 'An active invoice is already linked to eye surgery %.', p_eye_surgery_id
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  IF v_discount < 0 THEN
    RAISE EXCEPTION 'Discount cannot be negative: %', v_discount
      USING ERRCODE = 'numeric_value_out_of_range';
  END IF;

  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invoice must contain at least one line item.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Concurrency-safe invoice sequence generation for the financial year
  v_fy_code := public.get_financial_year_code(COALESCE(p_invoice_date, current_date));
  PERFORM pg_advisory_xact_lock(hashtextextended('billing_invoice:' || v_fy_code, 0));

  SELECT COALESCE(
    MAX(
      SUBSTRING(invoice_number FROM '^([0-9]+)/' || v_fy_code || '$')::integer
    ),
    0
  ) + 1
  INTO v_next_seq
  FROM public.billing
  WHERE invoice_number ~ ('^[0-9]+/' || v_fy_code || '$');

  v_invoice_number := v_next_seq::text || '/' || v_fy_code;

  -- Calculate subtotal from items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_qty := COALESCE((v_item->>'quantity')::integer, 1);
    v_item_price := COALESCE((v_item->>'unit_price')::numeric, 0);
    
    IF v_item_qty <= 0 THEN
      RAISE EXCEPTION 'Line item quantity must be greater than zero.'
        USING ERRCODE = 'numeric_value_out_of_range';
    END IF;
    IF v_item_price < 0 THEN
      RAISE EXCEPTION 'Line item unit price cannot be negative.'
        USING ERRCODE = 'numeric_value_out_of_range';
    END IF;

    v_subtotal := v_subtotal + (v_item_qty * v_item_price);
  END LOOP;

  IF v_discount > v_subtotal THEN
    RAISE EXCEPTION 'Discount (%) cannot exceed subtotal (%).', v_discount, v_subtotal
      USING ERRCODE = 'numeric_value_out_of_range';
  END IF;

  v_total_amount := v_subtotal - v_discount;

  -- Validate initial payment if provided
  IF p_payment IS NOT NULL AND (p_payment->>'amount') IS NOT NULL AND (p_payment->>'amount')::numeric > 0 THEN
    v_payment_amount := (p_payment->>'amount')::numeric;
    v_payment_mode := lower(trim(p_payment->>'payment_mode'));
    v_payment_ref := trim(COALESCE(p_payment->>'payment_reference', ''));

    IF v_payment_mode NOT IN ('cash', 'upi', 'bank_transfer', 'other') THEN
      RAISE EXCEPTION 'Invalid payment mode: %. Must be cash, upi, bank_transfer, or other.', v_payment_mode
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF v_payment_amount > v_total_amount THEN
      RAISE EXCEPTION 'Payment amount (%) cannot exceed invoice total (%).', v_payment_amount, v_total_amount
        USING ERRCODE = 'numeric_value_out_of_range';
    END IF;

    IF v_payment_amount >= v_total_amount AND v_total_amount > 0 THEN
      v_payment_status := 'paid';
    ELSE
      v_payment_status := 'partially_paid';
    END IF;
  ELSE
    v_payment_amount := 0;
    v_payment_status := 'pending';
    v_payment_mode := NULL;
    v_payment_ref := NULL;
  END IF;

  -- Insert invoice header
  INSERT INTO public.billing (
    invoice_number,
    patient_id,
    department,
    subtotal,
    discount,
    total_amount,
    payment_status,
    payment_mode,
    amount_paid,
    billed_by,
    notes,
    eye_surgery_id,
    created_at,
    updated_at
  )
  VALUES (
    v_invoice_number,
    p_patient_id,
    v_department,
    v_subtotal,
    v_discount,
    v_total_amount,
    v_payment_status,
    v_payment_mode,
    v_payment_amount,
    auth.uid(),
    p_notes,
    p_eye_surgery_id,
    COALESCE(p_invoice_date::timestamp with time zone, now()),
    now()
  )
  RETURNING * INTO v_billing;

  -- Insert line items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_service_id := NULL;
    IF (v_item->>'service_id') IS NOT NULL AND (v_item->>'service_id') != '' THEN
      v_item_service_id := (v_item->>'service_id')::uuid;
    END IF;

    v_item_service_name := trim(COALESCE(v_item->>'service_name', ''));
    IF v_item_service_name = '' THEN
      IF v_item_service_id IS NOT NULL THEN
        SELECT name INTO v_item_service_name FROM public.billing_services WHERE id = v_item_service_id;
      ELSE
        RAISE EXCEPTION 'Service name must be provided for invoice item.'
          USING ERRCODE = 'invalid_parameter_value';
      END IF;
    END IF;

    v_item_qty := COALESCE((v_item->>'quantity')::integer, 1);
    v_item_price := COALESCE((v_item->>'unit_price')::numeric, 0);
    v_item_total := v_item_qty * v_item_price;
    v_item_is_custom := COALESCE((v_item->>'is_custom')::boolean, (v_item_service_id IS NULL));

    INSERT INTO public.billing_items (
      billing_id,
      service_id,
      service_name,
      quantity,
      unit_price,
      total_amount,
      is_custom
    )
    VALUES (
      v_billing.id,
      v_item_service_id,
      v_item_service_name,
      v_item_qty,
      v_item_price,
      v_item_total,
      v_item_is_custom
    );
  END LOOP;

  -- Insert initial payment record if provided
  IF v_payment_amount > 0 THEN
    INSERT INTO public.billing_payments (
      billing_id,
      amount,
      payment_mode,
      payment_reference,
      paid_at,
      recorded_by,
      notes
    )
    VALUES (
      v_billing.id,
      v_payment_amount,
      v_payment_mode,
      NULLIF(v_payment_ref, ''),
      COALESCE(p_invoice_date::timestamp with time zone, now()),
      auth.uid(),
      'Initial payment on invoice creation'
    );
  END IF;

  RETURN v_billing;
END;
$$;

REVOKE ALL ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) TO authenticated;


-- =============================================================================
-- STEP 4: CREATE public.eye_surgery_insurances TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.eye_surgery_insurances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  eye_surgery_id UUID NOT NULL REFERENCES public.eye_surgeries(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  insurance_provider TEXT NOT NULL,
  arrangement TEXT NOT NULL CHECK (arrangement IN ('cashless', 'reimbursement')),
  policy_number TEXT,
  member_id TEXT,
  claim_number TEXT,
  coverage_details TEXT,
  estimated_amount NUMERIC(12,2) NOT NULL DEFAULT 0.0 CHECK (estimated_amount >= 0),
  approved_amount NUMERIC(12,2) NOT NULL DEFAULT 0.0 CHECK (approved_amount >= 0),
  amount_received NUMERIC(12,2) NOT NULL DEFAULT 0.0 CHECK (amount_received >= 0),
  claim_submission_date DATE,
  claim_status TEXT NOT NULL DEFAULT 'not_submitted'
    CHECK (claim_status IN ('not_submitted', 'submitted', 'under_review', 'approved', 'partially_approved', 'rejected', 'settled')),
  notes TEXT,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT eye_surgery_insurances_surgery_key UNIQUE (eye_surgery_id)
);

CREATE INDEX IF NOT EXISTS idx_eye_surgery_insurances_patient_id
  ON public.eye_surgery_insurances(patient_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgery_insurances_surgery_id
  ON public.eye_surgery_insurances(eye_surgery_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgery_insurances_claim_status
  ON public.eye_surgery_insurances(claim_status);


-- =============================================================================
-- STEP 5: CREATE public.eye_surgery_insurance_payments TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.eye_surgery_insurance_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  insurance_id UUID NOT NULL REFERENCES public.eye_surgery_insurances(id) ON DELETE CASCADE,
  eye_surgery_id UUID NOT NULL REFERENCES public.eye_surgeries(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  payment_date DATE NOT NULL DEFAULT current_date,
  payment_reference TEXT,
  payment_destination TEXT NOT NULL DEFAULT 'clinic' CHECK (payment_destination IN ('clinic', 'patient')),
  payment_mode TEXT NOT NULL DEFAULT 'bank_transfer' CHECK (payment_mode IN ('bank_transfer', 'upi', 'cheque', 'other')),
  notes TEXT,
  recorded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eye_surgery_insurance_payments_insurance_id
  ON public.eye_surgery_insurance_payments(insurance_id);
CREATE INDEX IF NOT EXISTS idx_eye_surgery_insurance_payments_surgery_id
  ON public.eye_surgery_insurance_payments(eye_surgery_id);

-- Trigger to maintain amount_received on eye_surgery_insurances from clinic-directed payments
CREATE OR REPLACE FUNCTION public.sync_eye_surgery_insurance_received()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ins_id UUID;
  v_total_received NUMERIC(12,2);
BEGIN
  v_ins_id := COALESCE(NEW.insurance_id, OLD.insurance_id);

  SELECT COALESCE(SUM(amount), 0.0)
  INTO v_total_received
  FROM public.eye_surgery_insurance_payments
  WHERE insurance_id = v_ins_id
    AND payment_destination = 'clinic';

  UPDATE public.eye_surgery_insurances
  SET amount_received = v_total_received,
      updated_at = now()
  WHERE id = v_ins_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_eye_surgery_insurance_received ON public.eye_surgery_insurance_payments;
CREATE TRIGGER trg_sync_eye_surgery_insurance_received
AFTER INSERT OR UPDATE OR DELETE ON public.eye_surgery_insurance_payments
FOR EACH ROW
EXECUTE FUNCTION public.sync_eye_surgery_insurance_received();


-- =============================================================================
-- STEP 6: ROW LEVEL SECURITY & PERMISSIONS
-- =============================================================================

ALTER TABLE public.eye_surgery_insurances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eye_surgery_insurance_payments ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_surgery_insurances TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_surgery_insurance_payments TO authenticated;
GRANT ALL ON TABLE public.eye_surgery_insurances TO service_role;
GRANT ALL ON TABLE public.eye_surgery_insurance_payments TO service_role;

DROP POLICY IF EXISTS "Staff and Admin can view eye surgery insurance" ON public.eye_surgery_insurances;
DROP POLICY IF EXISTS "Staff and Admin can manage eye surgery insurance" ON public.eye_surgery_insurances;

CREATE POLICY "Staff and Admin can view eye surgery insurance"
  ON public.eye_surgery_insurances FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());

CREATE POLICY "Staff and Admin can manage eye surgery insurance"
  ON public.eye_surgery_insurances FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Staff and Admin can view eye surgery insurance payments" ON public.eye_surgery_insurance_payments;
DROP POLICY IF EXISTS "Staff and Admin can manage eye surgery insurance payments" ON public.eye_surgery_insurance_payments;

CREATE POLICY "Staff and Admin can view eye surgery insurance payments"
  ON public.eye_surgery_insurance_payments FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());

CREATE POLICY "Staff and Admin can manage eye surgery insurance payments"
  ON public.eye_surgery_insurance_payments FOR ALL TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

COMMIT;
