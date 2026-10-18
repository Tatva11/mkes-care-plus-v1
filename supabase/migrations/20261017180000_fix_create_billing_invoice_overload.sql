-- =============================================================================
-- MKES CARE+ — Fix create_billing_invoice Function Overload Ambiguity
-- Migration: 20261017180000_fix_create_billing_invoice_overload.sql
--
-- Problem (PGRST203):
-- PostgREST could not choose between:
-- 1. public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text) [7 params]
-- 2. public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) [8 params]
--
-- Solution:
-- 1. Drop the legacy 7-parameter overload.
-- 2. Establish one canonical, unambiguous create_billing_invoice RPC.
-- 3. Provide an explicit create_surgery_billing_invoice RPC for surgery billing.
-- 4. Reload PostgREST schema cache.
-- =============================================================================

-- Step 1: Drop legacy overloads cleanly
DROP FUNCTION IF EXISTS public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text);
DROP FUNCTION IF EXISTS public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid);
DROP FUNCTION IF EXISTS public.create_surgery_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid);

-- Step 2: Canonical create_billing_invoice function
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

-- Step 3: Dedicated RPC for eye surgery billing (unambiguous endpoint)
CREATE OR REPLACE FUNCTION public.create_surgery_billing_invoice(
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
BEGIN
  IF p_eye_surgery_id IS NULL THEN
    RAISE EXCEPTION 'p_eye_surgery_id is required for surgery invoice creation.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  RETURN public.create_billing_invoice(
    p_patient_id := p_patient_id,
    p_department := p_department,
    p_discount := p_discount,
    p_items := p_items,
    p_payment := p_payment,
    p_invoice_date := p_invoice_date,
    p_notes := p_notes,
    p_eye_surgery_id := p_eye_surgery_id
  );
END;
$$;

-- Step 4: Permissions
REVOKE ALL ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_surgery_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_surgery_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text, uuid) TO authenticated, service_role;

-- Step 5: Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
