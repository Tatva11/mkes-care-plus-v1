-- =============================================================================
-- Migration: 20260930140000_billing_database_foundation.sql
-- Description: Sprint 7 Phase 7.1 - Billing Database Foundation
--   - Extends public.billing as the invoice/header table
--   - Creates public.billing_services (catalogue of department services)
--   - Creates public.billing_items (line items with custom service support)
--   - Creates public.billing_payments (multi/partial payment tracking)
--   - Adds continuous financial-year invoice numbering RPCs (e.g., 1/26-27)
--   - Adds atomic invoice creation & payment RPCs
--   - Enforces business rules (no GST, subtotal - discount = total_amount)
--   - Restricts deletion of paid/cancelled financial records
--   - Sets up Row Level Security (RLS) policies and indexes
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: EXTEND AND NORMALIZE public.billing (INVOICE HEADER)
-- =============================================================================

-- Add department column (restricted to Eye and Dental only)
ALTER TABLE public.billing
  ADD COLUMN IF NOT EXISTS department text;

-- Safe backfill for any existing legacy billing rows
UPDATE public.billing AS b
SET department = COALESCE(p.department, 'eye')
FROM public.patients AS p
WHERE b.patient_id = p.id
  AND b.department IS NULL;

UPDATE public.billing
SET department = 'eye'
WHERE department IS NULL;

ALTER TABLE public.billing
  ALTER COLUMN department SET NOT NULL;

ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_department_check;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_department_check
  CHECK (department IN ('eye', 'dental'));

-- Add notes/remarks and updated_at columns
ALTER TABLE public.billing
  ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE public.billing
  ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL;

-- Migrate legacy payment_status ('partial' -> 'partially_paid')
UPDATE public.billing
SET payment_status = 'partially_paid'
WHERE payment_status = 'partial';

-- Update payment_status check constraint
ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_payment_status_check;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_payment_status_check
  CHECK (payment_status IN ('pending', 'partially_paid', 'paid', 'cancelled'));

-- Update payment_mode check constraint to support cash, upi, bank_transfer, other
ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_payment_mode_check;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_payment_mode_check
  CHECK (payment_mode IS NULL OR payment_mode IN ('cash', 'upi', 'bank_transfer', 'other'));

-- Align total_amount = subtotal - discount for any legacy rows
UPDATE public.billing
SET total_amount = subtotal - discount
WHERE total_amount != (subtotal - discount);

-- Enforce financial amounts integrity (no GST, subtotal - discount = total_amount)
ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_amounts_check;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_amounts_check
  CHECK (
    subtotal >= 0 AND
    discount >= 0 AND
    total_amount >= 0 AND
    amount_paid >= 0 AND
    discount <= subtotal AND
    total_amount = (subtotal - discount)
  );

-- Ensure patient_id foreign key has sensible action
ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_patient_id_fkey;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.patients(id)
  ON DELETE RESTRICT;

-- Ensure billed_by foreign key exists
ALTER TABLE public.billing
  DROP CONSTRAINT IF EXISTS billing_billed_by_fkey;

ALTER TABLE public.billing
  ADD CONSTRAINT billing_billed_by_fkey
  FOREIGN KEY (billed_by) REFERENCES public.profiles(id)
  ON DELETE SET NULL;

-- Trigger to maintain updated_at on public.billing
DROP TRIGGER IF EXISTS trg_billing_updated_at ON public.billing;
CREATE TRIGGER trg_billing_updated_at
BEFORE UPDATE ON public.billing
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Indexes for billing table
CREATE INDEX IF NOT EXISTS idx_billing_department
  ON public.billing(department);

CREATE INDEX IF NOT EXISTS idx_billing_patient_id
  ON public.billing(patient_id);

CREATE INDEX IF NOT EXISTS idx_billing_payment_status
  ON public.billing(payment_status);

CREATE INDEX IF NOT EXISTS idx_billing_created_at
  ON public.billing(created_at DESC);


-- =============================================================================
-- STEP 2: CREATE public.billing_services (SERVICE CATALOGUE)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.billing_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department text NOT NULL,
  name text NOT NULL,
  price numeric(12,2) NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT billing_services_department_check CHECK (department IN ('eye', 'dental')),
  CONSTRAINT billing_services_price_check CHECK (price >= 0),
  CONSTRAINT billing_services_dept_name_key UNIQUE (department, name)
);

ALTER TABLE public.billing_services OWNER TO postgres;

DROP TRIGGER IF EXISTS trg_billing_services_updated_at ON public.billing_services;
CREATE TRIGGER trg_billing_services_updated_at
BEFORE UPDATE ON public.billing_services
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

CREATE INDEX IF NOT EXISTS idx_billing_services_dept_active
  ON public.billing_services(department, is_active);


-- =============================================================================
-- STEP 3: CREATE public.billing_items (INVOICE LINE ITEMS)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.billing_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  billing_id uuid NOT NULL,
  service_id uuid,
  service_name text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  unit_price numeric(12,2) NOT NULL DEFAULT 0,
  total_amount numeric(12,2) NOT NULL DEFAULT 0,
  is_custom boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT billing_items_billing_id_fkey FOREIGN KEY (billing_id) REFERENCES public.billing(id) ON DELETE CASCADE,
  CONSTRAINT billing_items_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.billing_services(id) ON DELETE SET NULL,
  CONSTRAINT billing_items_quantity_check CHECK (quantity > 0),
  CONSTRAINT billing_items_unit_price_check CHECK (unit_price >= 0),
  CONSTRAINT billing_items_total_amount_check CHECK (total_amount = (quantity * unit_price))
);

ALTER TABLE public.billing_items OWNER TO postgres;

CREATE INDEX IF NOT EXISTS idx_billing_items_billing_id
  ON public.billing_items(billing_id);

CREATE INDEX IF NOT EXISTS idx_billing_items_service_id
  ON public.billing_items(service_id);


-- =============================================================================
-- STEP 4: CREATE public.billing_payments (PARTIAL & MULTIPLE PAYMENTS)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.billing_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  billing_id uuid NOT NULL,
  amount numeric(12,2) NOT NULL,
  payment_mode text NOT NULL,
  payment_reference text,
  paid_at timestamp with time zone DEFAULT now() NOT NULL,
  recorded_by uuid,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT billing_payments_billing_id_fkey FOREIGN KEY (billing_id) REFERENCES public.billing(id) ON DELETE RESTRICT,
  CONSTRAINT billing_payments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT billing_payments_amount_check CHECK (amount > 0),
  CONSTRAINT billing_payments_mode_check CHECK (payment_mode IN ('cash', 'upi', 'bank_transfer', 'other'))
);

ALTER TABLE public.billing_payments OWNER TO postgres;

CREATE INDEX IF NOT EXISTS idx_billing_payments_billing_id
  ON public.billing_payments(billing_id);

CREATE INDEX IF NOT EXISTS idx_billing_payments_paid_at
  ON public.billing_payments(paid_at DESC);

CREATE INDEX IF NOT EXISTS idx_billing_payments_recorded_by
  ON public.billing_payments(recorded_by);


-- =============================================================================
-- STEP 5: FINANCIAL YEAR INVOICE NUMBERING & RPC FUNCTIONS
-- =============================================================================

-- Helper: Computes Indian Financial Year code (e.g., '26-27' for 2026-04-01 to 2027-03-31)
CREATE OR REPLACE FUNCTION public.get_financial_year_code(p_date date DEFAULT current_date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 
    to_char(
      (CASE 
        WHEN extract(month FROM COALESCE(p_date, current_date)) >= 4 
        THEN extract(year FROM COALESCE(p_date, current_date))
        ELSE extract(year FROM COALESCE(p_date, current_date)) - 1
      END)::integer % 100,
      'FM00'
    ) || '-' ||
    to_char(
      (CASE 
        WHEN extract(month FROM COALESCE(p_date, current_date)) >= 4 
        THEN extract(year FROM COALESCE(p_date, current_date)) + 1
        ELSE extract(year FROM COALESCE(p_date, current_date))
      END)::integer % 100,
      'FM00'
    );
$$;

-- Function: Generates next sequential invoice number within transaction lock (e.g. '1/26-27')
CREATE OR REPLACE FUNCTION public.get_next_invoice_number(
  p_date date DEFAULT current_date
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_date date := COALESCE(p_date, current_date);
  v_fy_code text;
  v_next_seq integer;
BEGIN
  v_fy_code := public.get_financial_year_code(v_target_date);

  -- Concurrency control: acquire an advisory transaction lock for this financial year
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

  RETURN v_next_seq::text || '/' || v_fy_code;
END;
$$;


-- =============================================================================
-- STEP 6: AUTOMATIC PAYMENT SYNC TRIGGER & DELETE PROTECTION
-- =============================================================================

-- Trigger Function: Synchronizes amount_paid and payment_status from billing_payments
CREATE OR REPLACE FUNCTION public.sync_billing_payment_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_billing_id uuid;
  v_total_paid numeric(12,2);
  v_total_amount numeric(12,2);
  v_current_status text;
  v_new_status text;
BEGIN
  v_billing_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.billing_id ELSE NEW.billing_id END;

  SELECT total_amount, payment_status
  INTO v_total_amount, v_current_status
  FROM public.billing
  WHERE id = v_billing_id;

  IF FOUND THEN
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_paid
    FROM public.billing_payments
    WHERE billing_id = v_billing_id;

    IF v_current_status = 'cancelled' THEN
      v_new_status := 'cancelled';
    ELSIF v_total_paid >= v_total_amount AND v_total_amount > 0 THEN
      v_new_status := 'paid';
    ELSIF v_total_paid > 0 THEN
      v_new_status := 'partially_paid';
    ELSE
      v_new_status := 'pending';
    END IF;

    UPDATE public.billing
    SET amount_paid = v_total_paid,
        payment_status = v_new_status,
        updated_at = now()
    WHERE id = v_billing_id;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_billing_payment_totals ON public.billing_payments;
CREATE TRIGGER trg_sync_billing_payment_totals
AFTER INSERT OR UPDATE OR DELETE ON public.billing_payments
FOR EACH ROW
EXECUTE FUNCTION public.sync_billing_payment_totals();

-- Trigger Function: Prevents deleting invoices that have financial activity or are paid/cancelled
CREATE OR REPLACE FUNCTION public.prevent_billing_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.payment_status IN ('paid', 'partially_paid', 'cancelled') OR OLD.amount_paid > 0 THEN
    RAISE EXCEPTION 'Financial records cannot be deleted. Invoice % has status % with amount paid %.',
      OLD.invoice_number, OLD.payment_status, OLD.amount_paid
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_billing_delete ON public.billing;
CREATE TRIGGER trg_prevent_billing_delete
BEFORE DELETE ON public.billing
FOR EACH ROW
EXECUTE FUNCTION public.prevent_billing_delete();


-- =============================================================================
-- STEP 7: ATOMIC INVOICE & PAYMENT MANAGEMENT RPCs
-- =============================================================================

-- RPC: Atomic invoice creation with line items and optional initial payment
CREATE OR REPLACE FUNCTION public.create_billing_invoice(
  p_patient_id uuid,
  p_department text,
  p_discount numeric DEFAULT 0,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_payment jsonb DEFAULT null,
  p_invoice_date date DEFAULT current_date,
  p_notes text DEFAULT null
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

-- RPC: Record payment against an existing invoice
CREATE OR REPLACE FUNCTION public.record_billing_payment(
  p_billing_id uuid,
  p_amount numeric,
  p_payment_mode text,
  p_payment_reference text DEFAULT null,
  p_paid_at timestamp with time zone DEFAULT now(),
  p_notes text DEFAULT null
)
RETURNS public.billing_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_billing public.billing;
  v_payment_mode text := lower(trim(p_payment_mode));
  v_payment public.billing_payments;
  v_total_paid numeric(12,2);
  v_new_total_paid numeric(12,2);
BEGIN
  -- Lock the billing row for consistent calculation
  SELECT * INTO v_billing
  FROM public.billing
  WHERE id = p_billing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice with ID % not found.', p_billing_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_billing.payment_status = 'cancelled' THEN
    RAISE EXCEPTION 'Cannot record payment for a cancelled invoice.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero: %', p_amount
      USING ERRCODE = 'numeric_value_out_of_range';
  END IF;

  IF v_payment_mode NOT IN ('cash', 'upi', 'bank_transfer', 'other') THEN
    RAISE EXCEPTION 'Invalid payment mode: %. Must be cash, upi, bank_transfer, or other.', p_payment_mode
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_paid
  FROM public.billing_payments
  WHERE billing_id = p_billing_id;

  v_new_total_paid := v_total_paid + p_amount;

  IF v_new_total_paid > v_billing.total_amount THEN
    RAISE EXCEPTION 'Payment of % exceeds outstanding balance of % (Total: %, Already Paid: %).',
      p_amount, (v_billing.total_amount - v_total_paid), v_billing.total_amount, v_total_paid
      USING ERRCODE = 'numeric_value_out_of_range';
  END IF;

  -- Insert payment record (trigger trg_sync_billing_payment_totals will sync billing totals)
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
    p_billing_id,
    p_amount,
    v_payment_mode,
    NULLIF(trim(p_payment_reference), ''),
    COALESCE(p_paid_at, now()),
    auth.uid(),
    p_notes
  )
  RETURNING * INTO v_payment;

  -- Update payment_mode snapshot on invoice header to reflect latest payment mode
  UPDATE public.billing
  SET payment_mode = v_payment_mode
  WHERE id = p_billing_id;

  RETURN v_payment;
END;
$$;

-- RPC: Cancel an invoice
CREATE OR REPLACE FUNCTION public.cancel_billing_invoice(
  p_billing_id uuid,
  p_reason text DEFAULT null
)
RETURNS public.billing
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_billing public.billing;
BEGIN
  SELECT * INTO v_billing
  FROM public.billing
  WHERE id = p_billing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice with ID % not found.', p_billing_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_billing.payment_status = 'cancelled' THEN
    RAISE EXCEPTION 'Invoice % is already cancelled.', v_billing.invoice_number
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.billing
  SET payment_status = 'cancelled',
      notes = CONCAT_WS(E'\n', notes, 'Cancelled: ' || COALESCE(p_reason, 'No reason specified') || ' (at ' || now()::text || ')'),
      updated_at = now()
  WHERE id = p_billing_id
  RETURNING * INTO v_billing;

  RETURN v_billing;
END;
$$;


-- =============================================================================
-- STEP 8: ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

-- Enable RLS on all billing tables
ALTER TABLE public.billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_payments ENABLE ROW LEVEL SECURITY;

-- 8.1 public.billing policies
DROP POLICY IF EXISTS "Admins can manage billing" ON public.billing;
CREATE POLICY "Admins can manage billing"
  ON public.billing
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users can view billing" ON public.billing;
CREATE POLICY "Authenticated users can view billing"
  ON public.billing
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Active staff can create billing invoices" ON public.billing;
CREATE POLICY "Active staff can create billing invoices"
  ON public.billing
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.is_active = true
    )
  );

-- 8.2 public.billing_services policies
DROP POLICY IF EXISTS "Admins can manage billing services" ON public.billing_services;
CREATE POLICY "Admins can manage billing services"
  ON public.billing_services
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users can view billing services" ON public.billing_services;
CREATE POLICY "Authenticated users can view billing services"
  ON public.billing_services
  FOR SELECT
  TO authenticated
  USING (true);

-- 8.3 public.billing_items policies
DROP POLICY IF EXISTS "Admins can manage billing items" ON public.billing_items;
CREATE POLICY "Admins can manage billing items"
  ON public.billing_items
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users can view billing items" ON public.billing_items;
CREATE POLICY "Authenticated users can view billing items"
  ON public.billing_items
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Active staff can insert billing items" ON public.billing_items;
CREATE POLICY "Active staff can insert billing items"
  ON public.billing_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.is_active = true
    )
  );

-- 8.4 public.billing_payments policies
DROP POLICY IF EXISTS "Admins can manage billing payments" ON public.billing_payments;
CREATE POLICY "Admins can manage billing payments"
  ON public.billing_payments
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users can view billing payments" ON public.billing_payments;
CREATE POLICY "Authenticated users can view billing payments"
  ON public.billing_payments
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Active staff can record billing payments" ON public.billing_payments;
CREATE POLICY "Active staff can record billing payments"
  ON public.billing_payments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND profiles.is_active = true
    )
  );


-- =============================================================================
-- STEP 9: FUNCTION PERMISSIONS
-- =============================================================================

REVOKE ALL ON FUNCTION public.get_financial_year_code(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_financial_year_code(date) TO authenticated;

REVOKE ALL ON FUNCTION public.get_next_invoice_number(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_next_invoice_number(date) TO authenticated;

REVOKE ALL ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_billing_invoice(uuid, text, numeric, jsonb, jsonb, date, text) TO authenticated;

REVOKE ALL ON FUNCTION public.record_billing_payment(uuid, numeric, text, text, timestamp with time zone, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_billing_payment(uuid, numeric, text, text, timestamp with time zone, text) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_billing_invoice(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_billing_invoice(uuid, text) TO authenticated;


-- =============================================================================
-- STEP 10: SEED DEFAULT SERVICES FOR EYE & DENTAL
-- =============================================================================

INSERT INTO public.billing_services (department, name, price, is_active)
VALUES
  -- Eye Department Services
  ('eye', 'General Eye Consultation', 100.00, true),
  ('eye', 'Vision & Refraction Test', 150.00, true),
  ('eye', 'Cataract Assessment', 300.00, true),
  ('eye', 'Tonometry / IOP Check', 100.00, true),
  ('eye', 'Fundus / Retina Examination', 250.00, true),
  ('eye', 'Foreign Body Removal', 350.00, true),
  ('eye', 'Minor Eye Procedure', 500.00, true),

  -- Dental Department Services
  ('dental', 'Dental Consultation', 100.00, true),
  ('dental', 'Dental X-Ray (IOPA)', 150.00, true),
  ('dental', 'Scaling & Polishing (Cleaning)', 600.00, true),
  ('dental', 'Composite / Tooth Filling', 500.00, true),
  ('dental', 'Root Canal Treatment (RCT)', 2000.00, true),
  ('dental', 'Tooth Extraction', 400.00, true),
  ('dental', 'Surgical Extraction', 1200.00, true),
  ('dental', 'Ceramic / Metal Crown', 2500.00, true),
  ('dental', 'Complete / Partial Denture', 3500.00, true)
ON CONFLICT (department, name) DO UPDATE
SET price = EXCLUDED.price,
    is_active = EXCLUDED.is_active,
    updated_at = now();

COMMIT;
