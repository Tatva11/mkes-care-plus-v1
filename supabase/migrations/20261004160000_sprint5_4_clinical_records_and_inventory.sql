-- =====================================================================
-- MIGRATION: 20261004160000_sprint5_4_clinical_records_and_inventory.sql
-- DESCRIPTION: Sprint 5.4 - Eye & Dental Clinical Records + Inventory Integration
--              1. Eye Clinical Examination Records (public.eye_examinations)
--              2. Dental Clinical Treatment Records (public.dental_treatments)
--              3. Clinical Inventory Usage (public.clinical_inventory_usage)
--              4. Atomic Inventory Consumption RPC (public.record_clinical_inventory_consumption)
--              5. Role-based RLS Policies (Admin & Staff access, Admin-only delete)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. EYE CLINICAL EXAMINATION RECORDS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.eye_examinations (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id              UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  appointment_id          UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  eye_surgery_id          UUID REFERENCES public.eye_surgeries(id) ON DELETE SET NULL,
  examination_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  examination_time        TIME,
  visual_acuity_od        TEXT, -- Oculus Dexter (Right Eye)
  visual_acuity_os        TEXT, -- Oculus Sinister (Left Eye)
  visual_acuity           TEXT, -- General / Combined VA notes
  intraocular_pressure_od TEXT, -- IOP Right Eye (mmHg)
  intraocular_pressure_os TEXT, -- IOP Left Eye (mmHg)
  intraocular_pressure    TEXT, -- General / Combined IOP notes
  slit_lamp_examination   TEXT, -- Anterior segment / slit-lamp notes
  diagnosis               TEXT, -- Clinical diagnosis
  clinical_notes          TEXT, -- Findings, management plan & clinical notes
  created_by              UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Performance & Query Indexes
CREATE INDEX IF NOT EXISTS idx_eye_examinations_patient_id
  ON public.eye_examinations(patient_id);

CREATE INDEX IF NOT EXISTS idx_eye_examinations_appointment_id
  ON public.eye_examinations(appointment_id);

CREATE INDEX IF NOT EXISTS idx_eye_examinations_surgery_id
  ON public.eye_examinations(eye_surgery_id);

CREATE INDEX IF NOT EXISTS idx_eye_examinations_date
  ON public.eye_examinations(examination_date DESC);

CREATE INDEX IF NOT EXISTS idx_eye_examinations_created_at
  ON public.eye_examinations(created_at DESC);

-- Canonical view / alias
CREATE OR REPLACE VIEW public.eye_examination_records AS
SELECT * FROM public.eye_examinations;

-- Trigger to maintain updated_at
DROP TRIGGER IF EXISTS trg_eye_examinations_updated_at ON public.eye_examinations;
CREATE TRIGGER trg_eye_examinations_updated_at
  BEFORE UPDATE ON public.eye_examinations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();

-- ---------------------------------------------------------------------
-- 2. DENTAL CLINICAL TREATMENT RECORDS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dental_treatments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id          UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  appointment_id      UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  dental_lab_case_id  UUID REFERENCES public.dental_lab(id) ON DELETE SET NULL,
  treatment_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  treatment_time      TIME,
  tooth_number        TEXT, -- Tooth number (e.g. "16", "21") or Quadrant ("UR", "Upper Right")
  procedure_performed TEXT NOT NULL,
  treatment_notes     TEXT,
  diagnosis           TEXT,
  procedure_status    TEXT NOT NULL DEFAULT 'completed'
                      CHECK (procedure_status IN ('planned', 'in_progress', 'completed', 'cancelled')),
  created_by          UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Performance & Query Indexes
CREATE INDEX IF NOT EXISTS idx_dental_treatments_patient_id
  ON public.dental_treatments(patient_id);

CREATE INDEX IF NOT EXISTS idx_dental_treatments_appointment_id
  ON public.dental_treatments(appointment_id);

CREATE INDEX IF NOT EXISTS idx_dental_treatments_lab_case_id
  ON public.dental_treatments(dental_lab_case_id);

CREATE INDEX IF NOT EXISTS idx_dental_treatments_date
  ON public.dental_treatments(treatment_date DESC);

CREATE INDEX IF NOT EXISTS idx_dental_treatments_created_at
  ON public.dental_treatments(created_at DESC);

-- Canonical view / alias
CREATE OR REPLACE VIEW public.dental_treatment_records AS
SELECT * FROM public.dental_treatments;

-- Trigger to maintain updated_at
DROP TRIGGER IF EXISTS trg_dental_treatments_updated_at ON public.dental_treatments;
CREATE TRIGGER trg_dental_treatments_updated_at
  BEFORE UPDATE ON public.dental_treatments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();

-- ---------------------------------------------------------------------
-- 3. CLINICAL INVENTORY USAGE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clinical_inventory_usage (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id      UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  record_type     TEXT NOT NULL CHECK (record_type IN ('eye_examination', 'dental_treatment', 'eye_surgery', 'other')),
  record_id       UUID NOT NULL,
  inventory_id    UUID NOT NULL REFERENCES public.inventory(id) ON DELETE RESTRICT,
  quantity        NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  transaction_id  UUID REFERENCES public.inventory_transactions(id) ON DELETE SET NULL,
  remarks         TEXT,
  consumed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Performance & Query Indexes
CREATE INDEX IF NOT EXISTS idx_clinical_inventory_usage_patient_id
  ON public.clinical_inventory_usage(patient_id);

CREATE INDEX IF NOT EXISTS idx_clinical_inventory_usage_record
  ON public.clinical_inventory_usage(record_type, record_id);

CREATE INDEX IF NOT EXISTS idx_clinical_inventory_usage_inventory_id
  ON public.clinical_inventory_usage(inventory_id);

CREATE INDEX IF NOT EXISTS idx_clinical_inventory_usage_transaction_id
  ON public.clinical_inventory_usage(transaction_id);

-- Trigger to maintain updated_at
DROP TRIGGER IF EXISTS trg_clinical_inventory_usage_updated_at ON public.clinical_inventory_usage;
CREATE TRIGGER trg_clinical_inventory_usage_updated_at
  BEFORE UPDATE ON public.clinical_inventory_usage
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();

-- ---------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ---------------------------------------------------------------------
ALTER TABLE public.eye_examinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dental_treatments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_inventory_usage ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.eye_examinations TO authenticated;
GRANT ALL ON TABLE public.eye_examinations TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.dental_treatments TO authenticated;
GRANT ALL ON TABLE public.dental_treatments TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.clinical_inventory_usage TO authenticated;
GRANT ALL ON TABLE public.clinical_inventory_usage TO service_role;

-- Eye Examinations RLS
DROP POLICY IF EXISTS "Admins and Staff can view eye examinations" ON public.eye_examinations;
CREATE POLICY "Admins and Staff can view eye examinations" ON public.eye_examinations
  FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can insert eye examinations" ON public.eye_examinations;
CREATE POLICY "Admins and Staff can insert eye examinations" ON public.eye_examinations
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can update eye examinations" ON public.eye_examinations;
CREATE POLICY "Admins and Staff can update eye examinations" ON public.eye_examinations
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins can delete eye examinations" ON public.eye_examinations;
CREATE POLICY "Admins can delete eye examinations" ON public.eye_examinations
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- Dental Treatments RLS
DROP POLICY IF EXISTS "Admins and Staff can view dental treatments" ON public.dental_treatments;
CREATE POLICY "Admins and Staff can view dental treatments" ON public.dental_treatments
  FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can insert dental treatments" ON public.dental_treatments;
CREATE POLICY "Admins and Staff can insert dental treatments" ON public.dental_treatments
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can update dental treatments" ON public.dental_treatments;
CREATE POLICY "Admins and Staff can update dental treatments" ON public.dental_treatments
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins can delete dental treatments" ON public.dental_treatments;
CREATE POLICY "Admins can delete dental treatments" ON public.dental_treatments
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- Clinical Inventory Usage RLS
DROP POLICY IF EXISTS "Admins and Staff can view clinical inventory usage" ON public.clinical_inventory_usage;
CREATE POLICY "Admins and Staff can view clinical inventory usage" ON public.clinical_inventory_usage
  FOR SELECT TO authenticated
  USING (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can insert clinical inventory usage" ON public.clinical_inventory_usage;
CREATE POLICY "Admins and Staff can insert clinical inventory usage" ON public.clinical_inventory_usage
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins and Staff can update clinical inventory usage" ON public.clinical_inventory_usage;
CREATE POLICY "Admins and Staff can update clinical inventory usage" ON public.clinical_inventory_usage
  FOR UPDATE TO authenticated
  USING (public.is_admin_or_staff())
  WITH CHECK (public.is_admin_or_staff());

DROP POLICY IF EXISTS "Admins can delete clinical inventory usage" ON public.clinical_inventory_usage;
CREATE POLICY "Admins can delete clinical inventory usage" ON public.clinical_inventory_usage
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- ---------------------------------------------------------------------
-- 5. ATOMIC CLINICAL INVENTORY CONSUMPTION RPC
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_clinical_inventory_consumption(
  p_patient_id    UUID,
  p_record_type   TEXT,
  p_record_id     UUID,
  p_inventory_id  UUID,
  p_quantity      NUMERIC,
  p_remarks       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID;
  v_patient_exists BOOLEAN;
  v_stock_result  JSONB;
  v_tx_id         UUID;
  v_usage_id      UUID;
  v_audit_remarks TEXT;
BEGIN
  -- 1. Check authentication
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to record clinical inventory consumption.';
  END IF;

  -- 2. Check permission
  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only Admins and Staff can record clinical inventory consumption.';
  END IF;

  -- 3. Validate inputs
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  IF p_record_type NOT IN ('eye_examination', 'dental_treatment', 'eye_surgery', 'other') THEN
    RAISE EXCEPTION 'Invalid record type: %', p_record_type;
  END IF;

  -- 4. Check patient existence
  SELECT EXISTS (SELECT 1 FROM public.patients WHERE id = p_patient_id) INTO v_patient_exists;
  IF NOT v_patient_exists THEN
    RAISE EXCEPTION 'Patient with ID % not found.', p_patient_id;
  END IF;

  -- 5. Prepare audit remarks
  v_audit_remarks := CASE 
    WHEN p_remarks IS NOT NULL AND trim(p_remarks) <> ''
      THEN 'Clinical Usage (' || p_record_type || '): ' || trim(p_remarks)
    ELSE 'Clinical Usage (' || p_record_type || ')'
  END;

  -- 6. Atomically deduct stock using existing perform_stock_operation RPC
  -- This coordinates SELECT FOR UPDATE on inventory, FEFO batch deduction, 
  -- updates inventory quantity, inserts into inventory_transactions with reason='Dispensed to Patient',
  -- and triggers low-stock alerts if needed. If stock is insufficient, it raises an exception 
  -- which aborts the entire transaction.
  v_stock_result := public.perform_stock_operation(
    p_inventory_id      := p_inventory_id,
    p_transaction_type  := 'stock_out',
    p_quantity          := p_quantity,
    p_reason            := 'Dispensed to Patient',
    p_remarks           := v_audit_remarks,
    p_patient_id        := p_patient_id
  );

  -- Extract transaction id from result
  v_tx_id := COALESCE(
    (v_stock_result->'transaction'->>'id')::UUID,
    (v_stock_result->>'transaction_id')::UUID,
    (v_stock_result->>'id')::UUID
  );

  -- 7. Insert clinical inventory usage record
  v_usage_id := gen_random_uuid();
  INSERT INTO public.clinical_inventory_usage (
    id,
    patient_id,
    record_type,
    record_id,
    inventory_id,
    quantity,
    transaction_id,
    remarks,
    consumed_at,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    v_usage_id,
    p_patient_id,
    p_record_type,
    p_record_id,
    p_inventory_id,
    p_quantity,
    v_tx_id,
    p_remarks,
    now(),
    v_user_id,
    now(),
    now()
  );

  -- Return combined result
  RETURN jsonb_build_object(
    'success', true,
    'usage_id', v_usage_id,
    'transaction_id', v_tx_id,
    'patient_id', p_patient_id,
    'record_type', p_record_type,
    'record_id', p_record_id,
    'inventory_id', p_inventory_id,
    'quantity', p_quantity,
    'stock_before', v_stock_result->>'stock_before',
    'stock_after', v_stock_result->>'stock_after'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_clinical_inventory_consumption(UUID, TEXT, UUID, UUID, NUMERIC, TEXT) TO service_role;
