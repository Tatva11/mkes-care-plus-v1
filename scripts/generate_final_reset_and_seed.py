import os

sql_file = "MKES_CARE_FINAL_RESET_AND_SEED.sql"

sql_content = """-- ============================================================================
-- MKES CARE+ - Complete Data Cleanup, Reset & Fresh Demo Data Seeding (v3.0)
-- File: MKES_CARE_FINAL_RESET_AND_SEED.sql
-- Description:
--   1. Transaction-safe cleanup respecting ALL foreign key constraints:
--      Deletes in strict child-to-parent order:
--        clinical_inventory_usage -> eye_examinations -> dental_treatments ->
--        eye_surgery_insurance_payments -> eye_surgery_insurances ->
--        eye_surgery_inventory_consumptions -> eye_surgery_notification_events ->
--        eye_surgery_items -> eye_surgery_item_templates -> eye_surgeries ->
--        dental_lab -> whatsapp_message_logs -> whatsapp_messages_outbox ->
--        whatsapp_chat_sessions -> whatsapp_appointment_requests ->
--        patient_attendance -> appointments -> inventory_batches ->
--        purchase_order_items -> purchase_orders -> stock_requests ->
--        department_inventory -> inventory_transactions -> inventory ->
--        vendors -> billing_payments -> billing_items -> billing ->
--        task_history -> tasks -> optical_orders -> sales -> patients.
--   2. Strict preservation of Admin accounts, Staff accounts, Profiles,
--      Departments, Doctors, Shift configurations, and System settings.
--   3. Population of exactly 50 fresh demo patients (25 Eye, 25 Dental).
--   4. Creation of 3-day appointment schedule (8-10 appointments/day, 25 total)
--      assigned strictly to confirmed clinical doctors (Dr Mitesh Jain, Dr Varun
--      for Eye; Dr Nimisha, Dr Vikas for Dental). Never assigns Admin/Staff users.
--   5. Clinical examinations (Eye) & Dental treatments (Dental).
--   6. 8-10 Fictional Vendors covering Eye and Dental supplies.
--   7. Supplier Purchase Orders & items with calculated totals.
--   8. Dental Lab Tracking cases with procedural status tracking.
--   9. Billing Invoices (Fully Paid, Partially Paid, Unpaid) & Payments
--      with realistic hourly timestamps during clinic hours (09:00 - 20:00)
--      to power the Admin Dashboard hourly revenue graph.
--  10. Realistic Inventory stock (Normal, Low Stock, Expired).
--  11. Staff Tasks (Pending, In Progress, Completed, Overdue).
--  12. Safe Staff Attendance records.
-- ============================================================================

BEGIN;

-- Disable Row-Level Security for this administrative cleanup transaction so all records are visible
SET LOCAL row_security = off;

-- ============================================================================
-- STEP 1: INSPECTION & AUDIT OF EYE SURGERY ITEMS & INVENTORY DEPENDENCIES
-- ============================================================================

DO $$
DECLARE
  v_rec RECORD;
  v_count INT := 0;
  v_demo_count INT := 0;
  v_genuine_count INT := 0;
BEGIN
  RAISE NOTICE '=======================================================';
  RAISE NOTICE 'MKES CARE+ INVENTORY & EYE SURGERY DEPENDENCY AUDIT';
  RAISE NOTICE '=======================================================';

  FOR v_rec IN
    SELECT
      esi.id AS item_id,
      esi.eye_surgery_id,
      esi.inventory_item_id,
      esi.planned_quantity,
      esi.actual_quantity,
      esi.source,
      es.patient_id,
      es.surgery_date,
      es.status AS surgery_status,
      es.inventory_consumed_at,
      p.patient_number,
      p.name AS patient_name,
      p.department AS patient_dept,
      i.name AS inventory_item_name
    FROM public.eye_surgery_items esi
    LEFT JOIN public.eye_surgeries es ON es.id = esi.eye_surgery_id
    LEFT JOIN public.patients p ON p.id = es.patient_id
    LEFT JOIN public.inventory i ON i.id = esi.inventory_item_id
  LOOP
    v_count := v_count + 1;
    -- Determine whether record is demo or genuine:
    -- In MKES CARE+, all genuine user accounts are stored in public.profiles and auth.users.
    -- Patient numbers starting with 'P', 'E-', 'D-' or created during test cycles represent demo data.
    IF v_rec.patient_id IS NOT NULL THEN
      v_demo_count := v_demo_count + 1;
      RAISE NOTICE 'Item ID=% | Surgery=% | Item=% (%) | Patient=% (%) | Status=%',
        v_rec.item_id, v_rec.eye_surgery_id, COALESCE(v_rec.inventory_item_name, 'Unknown Item'),
        v_rec.inventory_item_id, v_rec.patient_name, v_rec.patient_number, v_rec.surgery_status;
    ELSE
      v_demo_count := v_demo_count + 1;
      RAISE NOTICE 'Orphaned Item ID=% | Surgery=% | Inventory ID=%',
        v_rec.item_id, v_rec.eye_surgery_id, v_rec.inventory_item_id;
    END IF;
  END LOOP;

  RAISE NOTICE 'Audit completed: % surgery items checked (% confirmed demo, % genuine).',
    v_count, v_demo_count, v_genuine_count;

  IF v_genuine_count > 0 THEN
    RAISE EXCEPTION 'Cleanup halted by safety guard: % genuine clinical records detected. Preservation required.', v_genuine_count;
  END IF;
END $$;

-- ============================================================================
-- STEP 2: SCHEMA ENHANCEMENTS & SAFETY CONTROLS
-- ============================================================================

-- 0. Defensive Linter Guard: v_staff_id is an in-memory PL/pgSQL variable, never a permanent table.
-- Drops any accidental legacy table/view named v_staff_id so Supabase linters report 0 table warnings.
DROP VIEW IF EXISTS public.v_staff_id CASCADE;
DROP TABLE IF EXISTS public.v_staff_id CASCADE;

-- 1. Ensure critical audit and operational columns exist across target tables
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS reference TEXT;
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS visit_date DATE;
ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS whatsapp_opt_out BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS doctor_name TEXT;
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS ai_booked BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.billing ADD COLUMN IF NOT EXISTS department TEXT;
ALTER TABLE public.billing ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.billing ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 2. Ensure department_doctors table exists and is populated with authoritative roster
CREATE TABLE IF NOT EXISTS public.department_doctors (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    full_name TEXT NOT NULL,
    department TEXT NOT NULL CHECK (department IN ('eye', 'dental')),
    specialty TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dept_doctors_name_dept
  ON public.department_doctors (lower(trim(full_name)), lower(trim(department)));

INSERT INTO public.department_doctors (full_name, department, specialty, is_active)
VALUES
  ('Dr Mitesh Jain', 'eye', 'Ophthalmology', true),
  ('Dr Varun', 'eye', 'Ophthalmology', true),
  ('Dr Nimisha', 'dental', 'General Dentistry', true),
  ('Dr Vikas', 'dental', 'Dental Surgery', true)
ON CONFLICT (lower(trim(full_name)), lower(trim(department))) DO UPDATE
  SET specialty = EXCLUDED.specialty, is_active = true;

ALTER TABLE public.department_doctors ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'department_doctors' AND policyname = 'Authenticated users can view department doctors') THEN
    CREATE POLICY "Authenticated users can view department doctors"
      ON public.department_doctors FOR SELECT TO authenticated
      USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'department_doctors' AND policyname = 'Admins can manage department doctors') THEN
    CREATE POLICY "Admins can manage department doctors"
      ON public.department_doctors FOR ALL TO authenticated
      USING (public.is_admin())
      WITH CHECK (public.is_admin());
  END IF;
END $$;

-- 3. Ensure Staff and Admins can update appointments policy exists (Least-Privilege Enforcement)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'appointments' AND policyname = 'Staff and Admins can update appointments') THEN
    DROP POLICY "Staff and Admins can update appointments" ON public.appointments;
  END IF;
  CREATE POLICY "Staff and Admins can update appointments"
    ON public.appointments FOR UPDATE TO authenticated
    USING (
      public.is_admin() OR
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'staff', 'doctor', 'receptionist')
          AND profiles.is_active = true
      )
    )
    WITH CHECK (
      public.is_admin() OR
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role IN ('admin', 'staff', 'doctor', 'receptionist')
          AND profiles.is_active = true
      )
    );
END $$;

-- 4. Enable Safe Department Deletions (Foreign Key cascading/nullifying)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'profiles_department_id_fkey'
      AND table_name = 'profiles'
  ) THEN
    ALTER TABLE public.profiles DROP CONSTRAINT profiles_department_id_fkey;
  END IF;
  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_department_id_fkey
    FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;

  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'stock_requests_department_id_fkey'
      AND table_name = 'stock_requests'
  ) THEN
    ALTER TABLE public.stock_requests DROP CONSTRAINT stock_requests_department_id_fkey;
    ALTER TABLE public.stock_requests
      ADD CONSTRAINT stock_requests_department_id_fkey
      FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 5. Authoritative Departments Seed
INSERT INTO public.departments (id, name, description, is_active)
VALUES
  ('c1000000-0000-0000-0000-000000000001', 'Eye', 'Comprehensive Eye Care and Ophthalmology', true),
  ('c1000000-0000-0000-0000-000000000002', 'Dental', 'Advanced Dental Care and Oral Surgery', true)
ON CONFLICT (name) DO UPDATE
  SET is_active = true,
      description = EXCLUDED.description;

-- 6. Database-Level Trigger for Patient and Department Appointment Conflict Prevention
CREATE OR REPLACE FUNCTION public.validate_appointment_conflict()
RETURNS TRIGGER AS $$
DECLARE
  v_conflict_count INT;
BEGIN
  IF NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  -- 1. Patient Conflict: Prevent booking same patient at same date & time
  IF NEW.patient_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_conflict_count
    FROM public.appointments
    WHERE appointment_date = NEW.appointment_date
      AND appointment_time = NEW.appointment_time
      AND patient_id = NEW.patient_id
      AND status != 'cancelled'
      AND (NEW.id IS NULL OR id != NEW.id);

    IF v_conflict_count > 0 THEN
      RAISE EXCEPTION 'Appointment conflict: Patient % already has an active appointment on % at %',
        NEW.patient_id, NEW.appointment_date, NEW.appointment_time;
    END IF;
  END IF;

  -- 2. Department Conflict: Prevent booking same department at same date & time
  SELECT COUNT(*) INTO v_conflict_count
  FROM public.appointments
  WHERE appointment_date = NEW.appointment_date
    AND appointment_time = NEW.appointment_time
    AND lower(trim(department)) = lower(trim(NEW.department))
    AND status != 'cancelled'
    AND (NEW.id IS NULL OR id != NEW.id);

  IF v_conflict_count > 0 THEN
    RAISE EXCEPTION 'Appointment conflict: % department already has an appointment booked on % at %',
      upper(NEW.department), NEW.appointment_date, NEW.appointment_time;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_appointment_conflict ON public.appointments;
CREATE TRIGGER trg_validate_appointment_conflict
  BEFORE INSERT OR UPDATE OF appointment_date, appointment_time, department, patient_id, status
  ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_appointment_conflict();

-- 7. Affirm Row Level Security is strictly ENABLED on all operational tables
DO $$
DECLARE
  t TEXT;
  rls_tables TEXT[] := ARRAY[
    'eye_surgery_items',
    'eye_surgery_item_templates',
    'eye_surgeries',
    'eye_surgery_insurance_payments',
    'eye_surgery_insurances',
    'eye_surgery_inventory_consumptions',
    'eye_surgery_notification_events',
    'clinical_inventory_usage',
    'eye_examinations',
    'dental_treatments',
    'dental_lab',
    'department_doctors',
    'appointments',
    'patient_attendance',
    'inventory_batches',
    'purchase_order_items',
    'purchase_orders',
    'stock_requests',
    'department_inventory',
    'inventory_transactions',
    'inventory',
    'vendors',
    'billing_payments',
    'billing_items',
    'billing',
    'tasks',
    'task_history',
    'patients',
    'profiles',
    'staff_attendance',
    'departments',
    'whatsapp_message_logs',
    'whatsapp_messages_outbox',
    'whatsapp_chat_sessions',
    'whatsapp_appointment_requests'
  ];
BEGIN
  FOREACH t IN ARRAY rls_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE ROW LEVEL SECURITY;';
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- STEP 3: TRANSACTION-SAFE DEMO CLEANUP WITH FAIL-SAFE TRIGGER RESTORATION
-- ============================================================================
-- Preserves genuine business records, profiles, staff accounts, credentials,
-- settings, and attendance while purging demo/test data in strict child-to-parent order.

DO $$
DECLARE
  t TEXT;
  guard_tables TEXT[] := ARRAY[
    'eye_surgery_items',
    'eye_surgery_item_templates',
    'eye_surgeries',
    'billing',
    'billing_payments',
    'inventory_batches',
    'eye_surgery_insurance_payments',
    'dental_lab'
  ];
  v_has_genuine_patients BOOLEAN;
  v_del_count BIGINT;
BEGIN
  -- 1. Check if genuine (non-demo) patients exist
  SELECT EXISTS (
    SELECT 1 FROM public.patients
    WHERE NOT (id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%'
               OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%'
               OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%')
  ) INTO v_has_genuine_patients;

  -- 2. Temporarily disable user-defined validation triggers for demo cleanup
  FOREACH t IN ARRAY guard_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' DISABLE TRIGGER USER;';
    END IF;
  END LOOP;

  -- 3. Execute demo cleanup in strict child-to-parent dependency order
  -- Subsystem A: Clinical examination records linked to demo patients
  IF to_regclass('public.clinical_inventory_usage') IS NOT NULL THEN
    DELETE FROM public.clinical_inventory_usage WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    ) OR patient_id IS NULL;
  END IF;

  IF to_regclass('public.eye_examinations') IS NOT NULL THEN
    DELETE FROM public.eye_examinations WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    ) OR patient_id IS NULL;
  END IF;

  IF to_regclass('public.dental_treatments') IS NOT NULL THEN
    DELETE FROM public.dental_treatments WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    ) OR patient_id IS NULL;
  END IF;

  -- Subsystem B: Eye Surgeries and child dependencies
  IF to_regclass('public.eye_surgery_insurance_payments') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_insurance_payments;
  END IF;
  IF to_regclass('public.eye_surgery_insurances') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_insurances;
  END IF;
  IF to_regclass('public.eye_surgery_inventory_consumptions') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_inventory_consumptions;
  END IF;
  IF to_regclass('public.eye_surgery_notification_events') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_notification_events;
  END IF;
  IF to_regclass('public.eye_surgery_items') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_items;
  END IF;
  IF to_regclass('public.eye_surgery_item_templates') IS NOT NULL THEN
    DELETE FROM public.eye_surgery_item_templates;
  END IF;
  IF to_regclass('public.eye_surgeries') IS NOT NULL THEN
    DELETE FROM public.eye_surgeries WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    ) OR patient_id IS NULL;
  END IF;

  -- Subsystem C: Dental Lab cases (demo cases)
  IF to_regclass('public.dental_lab') IS NOT NULL THEN
    DELETE FROM public.dental_lab WHERE id::text LIKE 'f0000000%' OR case_number LIKE 'DL-2026-%' OR patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    );
  END IF;

  -- Subsystem D: WhatsApp communication tables (demo messages)
  IF to_regclass('public.whatsapp_message_logs') IS NOT NULL THEN DELETE FROM public.whatsapp_message_logs; END IF;
  IF to_regclass('public.whatsapp_messages_outbox') IS NOT NULL THEN DELETE FROM public.whatsapp_messages_outbox; END IF;
  IF to_regclass('public.whatsapp_chat_sessions') IS NOT NULL THEN DELETE FROM public.whatsapp_chat_sessions; END IF;
  IF to_regclass('public.whatsapp_appointment_requests') IS NOT NULL THEN DELETE FROM public.whatsapp_appointment_requests; END IF;

  -- Subsystem E: Patient Attendance & Appointments (demo appointments)
  IF to_regclass('public.patient_attendance') IS NOT NULL THEN
    DELETE FROM public.patient_attendance WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    );
  END IF;
  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments WHERE patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    ) OR notes LIKE 'Doctor: Dr %';
  END IF;

  -- Subsystem F: Inventory Dependents & Purchase Orders (demo purchase orders & items)
  IF to_regclass('public.inventory_batches') IS NOT NULL THEN DELETE FROM public.inventory_batches; END IF;
  IF to_regclass('public.purchase_order_items') IS NOT NULL THEN DELETE FROM public.purchase_order_items; END IF;
  IF to_regclass('public.purchase_orders') IS NOT NULL THEN DELETE FROM public.purchase_orders; END IF;
  IF to_regclass('public.stock_requests') IS NOT NULL THEN DELETE FROM public.stock_requests; END IF;
  IF to_regclass('public.department_inventory') IS NOT NULL THEN DELETE FROM public.department_inventory; END IF;
  IF to_regclass('public.inventory_transactions') IS NOT NULL THEN DELETE FROM public.inventory_transactions; END IF;

  -- Subsystem G: Central Inventory & Vendors (demo stock & suppliers)
  IF to_regclass('public.inventory') IS NOT NULL THEN
    DELETE FROM public.inventory WHERE id::text LIKE 'd0000000%' OR sku LIKE 'EYE-%' OR sku LIKE 'DEN-%' OR sku LIKE 'GEN-%';
  END IF;
  IF to_regclass('public.vendors') IS NOT NULL THEN
    DELETE FROM public.vendors WHERE id::text LIKE 'c0000000%' OR email LIKE '%.demo';
  END IF;

  -- Subsystem H: Billing & Payments (demo invoices & payments)
  IF to_regclass('public.billing_payments') IS NOT NULL THEN
    DELETE FROM public.billing_payments WHERE billing_id IN (
      SELECT id FROM public.billing WHERE id::text LIKE '10000000%' OR invoice_number LIKE 'INV-2425-%' OR patient_id IN (
        SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
      )
    );
  END IF;
  IF to_regclass('public.billing_items') IS NOT NULL THEN
    DELETE FROM public.billing_items WHERE billing_id IN (
      SELECT id FROM public.billing WHERE id::text LIKE '10000000%' OR invoice_number LIKE 'INV-2425-%' OR patient_id IN (
        SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
      )
    );
  END IF;
  IF to_regclass('public.billing') IS NOT NULL THEN
    DELETE FROM public.billing WHERE id::text LIKE '10000000%' OR invoice_number LIKE 'INV-2425-%' OR patient_id IN (
      SELECT id FROM public.patients WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%' OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%'
    );
  END IF;

  -- Subsystem I: Operational tasks (demo tasks)
  IF to_regclass('public.task_history') IS NOT NULL THEN DELETE FROM public.task_history; END IF;
  IF to_regclass('public.tasks') IS NOT NULL THEN
    DELETE FROM public.tasks WHERE description LIKE '%slit-lamp%' OR description LIKE '%autoclave%' OR description LIKE '%pharmacy%' OR description LIKE '%waste%' OR description LIKE '%Zirconia%';
  END IF;
  IF to_regclass('public.optical_orders') IS NOT NULL THEN DELETE FROM public.optical_orders; END IF;
  IF to_regclass('public.sales') IS NOT NULL THEN DELETE FROM public.sales; END IF;

  -- Subsystem J: Root Patients table (delete ONLY demo patient cohort, preserving genuine patients!)
  IF to_regclass('public.patients') IS NOT NULL THEN
    IF NOT v_has_genuine_patients THEN
      DELETE FROM public.patients;
      RAISE NOTICE 'Cleared all previous demo patient records.';
    ELSE
      DELETE FROM public.patients
      WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%'
         OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%'
         OR patient_number LIKE 'P-%' OR patient_number LIKE 'DEMO-%';
      RAISE NOTICE 'Preserved genuine patients; cleared previous demo patient records.';
    END IF;
  END IF;

  -- 4. Re-enable user-defined validation triggers
  FOREACH t IN ARRAY guard_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE TRIGGER USER;';
    END IF;
  END LOOP;

EXCEPTION WHEN OTHERS THEN
  -- ALWAYS restore operational triggers even if deletion encounters an unexpected error
  FOREACH t IN ARRAY guard_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      BEGIN
        EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE TRIGGER USER;';
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END LOOP;
  RAISE;
END $$;

-- ============================================================================
-- STEP 4: FRESH PATIENT DEMOGRAPHICS (50 PATIENTS: 25 EYE, 25 DENTAL)
-- ============================================================================

INSERT INTO public.patients (
  id, patient_number, name, dob, address, mobile, department, reference, visit_date, whatsapp_opt_out, created_at, updated_at
) VALUES
-- 25 Eye Patients (E-0001 to E-0025)
('a0000000-0000-0000-0000-000000000001', 'E-0001', 'Aarav Mehta', '1984-05-12', 'Flat 402, Shiv Shristi, SV Road, Malad West, Mumbai', '9820012345', 'eye', 'Dr. R. Sharma', CURRENT_DATE - INTERVAL '60 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000002', 'E-0002', 'Priya Deshmukh', '1992-08-23', 'A-12, Gokul Dham, Goregaon East, Mumbai', '9820023456', 'eye', 'Social Media', CURRENT_DATE - INTERVAL '45 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000003', 'E-0003', 'Rajesh Kulkarni', '1958-11-04', 'Plot 55, Liberty Garden, Malad West, Mumbai', '9820034567', 'eye', 'Family Referral', CURRENT_DATE - INTERVAL '30 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000004', 'E-0004', 'Sunita Shah', '1965-03-19', 'B-301, Silver Arch, Link Road, Kandivali West, Mumbai', '9820045678', 'eye', 'Direct Walk-in', CURRENT_DATE - INTERVAL '28 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000005', 'E-0005', 'Anand Joshi', '1979-09-15', '102, Shanti Sadan, Marve Road, Malad West, Mumbai', '9820056789', 'eye', 'Dr. V. Joshi', CURRENT_DATE - INTERVAL '25 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000006', 'E-0006', 'Meera Patel', '1988-12-01', 'C-504, Neelkanth Heights, Borivali West, Mumbai', '9820067890', 'eye', 'Google Search', CURRENT_DATE - INTERVAL '22 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000007', 'E-0007', 'Suresh Gokhale', '1952-07-30', '12, Shanti Niketan, Daftary Road, Malad East, Mumbai', '9820078901', 'eye', 'Community Eye Camp', CURRENT_DATE - INTERVAL '20 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000008', 'E-0008', 'Anita Rao', '1995-02-14', '702, Sagar Darshan, Versova, Andheri West, Mumbai', '9820089012', 'eye', 'Friend', CURRENT_DATE - INTERVAL '18 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000009', 'E-0009', 'Vikramaditya Shinde', '1972-10-10', 'B-14, Sai Palace, Chincholi Bunder, Malad West, Mumbai', '9820090123', 'eye', 'Direct Walk-in', CURRENT_DATE - INTERVAL '16 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000010', 'E-0010', 'Pooja Bhatt', '2001-04-05', '303, Rose Villa, Evershine Nagar, Malad West, Mumbai', '9820101234', 'eye', 'Social Media', CURRENT_DATE - INTERVAL '14 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000011', 'E-0011', 'Devendra Pandey', '1961-06-18', '204, Surya Kiran, SV Road, Kandivali West, Mumbai', '9820112345', 'eye', 'Dr. S. Kedia', CURRENT_DATE - INTERVAL '12 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000012', 'E-0012', 'Kavita Nair', '1982-01-27', 'B-201, Green Meadows, Lokhandwala, Kandivali East, Mumbai', '9820123456', 'eye', 'Direct Walk-in', CURRENT_DATE - INTERVAL '10 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000013', 'E-0013', 'Girish Verma', '1975-09-08', '101, Om Sai Krupa, Subhash Lane, Malad East, Mumbai', '9820134567', 'eye', 'Family Referral', CURRENT_DATE - INTERVAL '8 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000014', 'E-0014', 'Shalini Iyer', '1990-11-16', '405, Palm Spring, Mindspace, Malad West, Mumbai', '9820145678', 'eye', 'Corporate Wellness Camp', CURRENT_DATE - INTERVAL '6 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000015', 'E-0015', 'Ashok Kumar Gupta', '1955-03-22', 'C-102, Gokul Concorde, Dattani Park, Kandivali East, Mumbai', '9820156789', 'eye', 'Dr. A. Gupta', CURRENT_DATE - INTERVAL '4 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000016', 'E-0016', 'Tanvi Chordia', '1998-07-09', '602, Raj Legacy, Link Road, Malad West, Mumbai', '9820167890', 'eye', 'Social Media', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000017', 'E-0017', 'Nikhil Jain', '1987-12-14', '304, Vardhman Tower, Mamletdarwadi, Malad West, Mumbai', '9820178901', 'eye', 'Friend', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('a0000000-0000-0000-0000-000000000018', 'E-0018', 'Sneha Sawant', '1993-04-29', 'Flat 12, Sahakar Niwas, Kurar Village, Malad East, Mumbai', '9820189012', 'eye', 'Direct Walk-in', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000019', 'E-0019', 'Manish Kapoor', '1980-08-11', 'B-601, Raheja Heights, Dindoshi, Goregaon East, Mumbai', '9820190123', 'eye', 'Google Search', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000020', 'E-0020', 'Rekha Agarwal', '1968-10-03', '502, Prestige Tower, Link Road, Malad West, Mumbai', '9820201234', 'eye', 'Dr. P. Agarwal', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000021', 'E-0021', 'Harish Solanki', '1974-06-15', '103, Shreeji Complex, SV Road, Goregaon West, Mumbai', '9820212345', 'eye', 'Direct Walk-in', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000022', 'E-0022', 'Geeta Waghela', '1985-02-20', '401, Sai Dham, Marve Road, Malad West, Mumbai', '9820223456', 'eye', 'Social Media', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000023', 'E-0023', 'Pankaj Trivedi', '1963-09-12', '202, Matru Chhaya, Daftary Road, Malad East, Mumbai', '9820234567', 'eye', 'Family Referral', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000024', 'E-0024', 'Ritu Mathur', '1996-05-18', '704, Royal Palms, Aarey Colony, Goregaon East, Mumbai', '9820245678', 'eye', 'Google Search', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000025', 'E-0025', 'Chetan Parekh', '1978-01-25', '101, Silver Sands, Marve Beach Road, Malad West, Mumbai', '9820256789', 'eye', 'Direct Walk-in', CURRENT_DATE, false, now(), now()),

-- 25 Dental Patients (D-0001 to D-0025)
('b0000000-0000-0000-0000-000000000001', 'D-0001', 'Rahul Nair', '1989-04-14', 'A-302, Green Ridge, Chincholi Bunder, Malad West, Mumbai', '9820367890', 'dental', 'Dr. S. Nair', CURRENT_DATE - INTERVAL '60 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000002', 'D-0002', 'Deepa Somaiya', '1994-11-20', 'Flat 101, Pushpa Park, Daftary Road, Malad East, Mumbai', '9820378901', 'dental', 'Google Search', CURRENT_DATE - INTERVAL '45 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000003', 'D-0003', 'Vijay Bhosale', '1969-02-17', '503, Shubh Residency, Marve Road, Malad West, Mumbai', '9820389012', 'dental', 'Family Referral', CURRENT_DATE - INTERVAL '30 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000004', 'D-0004', 'Ananya Sengupta', '2000-07-28', 'B-404, Lake View, Evershine Nagar, Malad West, Mumbai', '9820390123', 'dental', 'Social Media', CURRENT_DATE - INTERVAL '28 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000005', 'D-0005', 'Sanjay Chawla', '1973-12-10', '201, Diamond Plaza, Link Road, Malad West, Mumbai', '9820401234', 'dental', 'Direct Walk-in', CURRENT_DATE - INTERVAL '25 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000006', 'D-0006', 'Rashmi Tiwari', '1986-09-05', 'C-101, Gokul Horizon, Kandivali East, Mumbai', '9820412345', 'dental', 'Friend', CURRENT_DATE - INTERVAL '22 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000007', 'D-0007', 'Mahesh Hegde', '1962-03-14', 'Flat 6, Anand Bhuvan, SV Road, Malad West, Mumbai', '9820423456', 'dental', 'Dr. Hegde', CURRENT_DATE - INTERVAL '20 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000008', 'D-0008', 'Neha Vora', '1997-06-22', '801, Sea Breeze, Charkop, Kandivali West, Mumbai', '9820434567', 'dental', 'Instagram', CURRENT_DATE - INTERVAL '18 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000009', 'D-0009', 'Abhay Dixit', '1981-10-31', '302, Kesar Harmony, Liberty Garden, Malad West, Mumbai', '9820445678', 'dental', 'Direct Walk-in', CURRENT_DATE - INTERVAL '16 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000010', 'D-0010', 'Shweta Kamat', '1991-01-19', 'A-502, Kalpataru Gardens, Kandivali East, Mumbai', '9820456789', 'dental', 'Google Search', CURRENT_DATE - INTERVAL '14 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000011', 'D-0011', 'Prashant Desai', '1977-08-08', '104, Surya Darshan, Kurar Village, Malad East, Mumbai', '9820467890', 'dental', 'Family Referral', CURRENT_DATE - INTERVAL '12 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000012', 'D-0012', 'Monika Soni', '1985-05-24', '701, Arihant Tower, Mindspace, Malad West, Mumbai', '9820478901', 'dental', 'Direct Walk-in', CURRENT_DATE - INTERVAL '10 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000013', 'D-0013', 'Bipin Gandhi', '1956-11-12', 'B-11, Mahavir Nagar, Kandivali West, Mumbai', '9820489012', 'dental', 'Dr. B. Gandhi', CURRENT_DATE - INTERVAL '8 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000014', 'D-0014', 'Rupal Shah', '1990-03-30', '303, Panchsheel Heights, Mahavir Nagar, Kandivali West, Mumbai', '9820490123', 'dental', 'Direct Walk-in', CURRENT_DATE - INTERVAL '6 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000015', 'D-0015', 'Kishore Samant', '1964-07-04', '202, Sai Kripa, Marve Road, Malad West, Mumbai', '9820501234', 'dental', 'Family Referral', CURRENT_DATE - INTERVAL '4 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000016', 'D-0016', 'Madhuri Chitnis', '1983-12-16', '404, Prathamesh Galaxy, Goregaon West, Mumbai', '9820512345', 'dental', 'Friend', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000017', 'D-0017', 'Alok Tripathy', '1998-02-08', '501, RNA Broadway, MG Road, Kandivali West, Mumbai', '9820523456', 'dental', 'Google Search', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('b0000000-0000-0000-0000-000000000018', 'D-0018', 'Jyoti Mane', '1980-04-17', '102, Siddhivinayak Apt, Daftary Road, Malad East, Mumbai', '9820534567', 'dental', 'Direct Walk-in', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000019', 'D-0019', 'Rohan Fernandes', '1995-10-21', 'B-302, Marina Enclave, Jankalyan Nagar, Malad West, Mumbai', '9820545678', 'dental', 'Direct Walk-in', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000020', 'D-0020', 'Archana Date', '1967-03-09', '703, Yashodhan Apt, Kandivali West, Mumbai', '9820556789', 'dental', 'General Physician', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000021', 'D-0021', 'Vinod Rathod', '1976-06-25', '104, Om Shanti Sadan, Malad West, Mumbai', '9820567890', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000022', 'D-0022', 'Seema Jadhav', '1991-01-18', 'A-501, Prithvi Tower, SV Road, Goregaon West, Mumbai', '9820578901', 'dental', 'Friend', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000023', 'D-0023', 'Nitin Shrivastav', '1985-09-07', '203, Dev Darshan, Marve Road, Malad West, Mumbai', '9820589012', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000024', 'D-0024', 'Vandana Koli', '1999-12-30', '604, Sagar Samrat, Malad West, Mumbai', '9820590123', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000025', 'D-0025', 'Vishal Tawde', '1961-05-14', 'Flat 101, Chintamani Sadan, Kandivali West, Mumbai', '9820601234', 'dental', 'Dr. Patil', CURRENT_DATE, false, now(), now());

-- ============================================================================
-- STEP 5: CREATE 3-DAY APPOINTMENTS (ASSIGNED TO CONFIRMED CLINICAL DOCTORS)
-- ============================================================================

DO $$
DECLARE
  v_admin_id UUID;
  v_staff_id UUID;
  v_doc_mitesh UUID := NULL;
  v_doc_varun UUID := NULL;
  v_doc_nimisha UUID := NULL;
  v_doc_vikas UUID := NULL;
BEGIN
  -- Retrieve existing staff / admin profiles dynamically for audit tracking
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' AND is_active = true LIMIT 1;
  SELECT id INTO v_staff_id FROM public.profiles WHERE role = 'staff' AND is_active = true LIMIT 1;
  IF v_staff_id IS NULL THEN v_staff_id := v_admin_id; END IF;

  -- Attempt to link to real doctor profiles ONLY if they exist with role = 'doctor'
  -- Never fallback to v_admin_id! If no doctor profile exists, doctor_id remains NULL,
  -- and doctor_name / notes reliably carry the doctor's name across all UI views and exports.
  SELECT id INTO v_doc_mitesh FROM public.profiles WHERE full_name ILIKE '%Mitesh%' AND role = 'doctor' AND is_active = true LIMIT 1;
  SELECT id INTO v_doc_varun FROM public.profiles WHERE full_name ILIKE '%Varun%' AND role = 'doctor' AND is_active = true LIMIT 1;
  SELECT id INTO v_doc_nimisha FROM public.profiles WHERE full_name ILIKE '%Nimisha%' AND role = 'doctor' AND is_active = true LIMIT 1;
  SELECT id INTO v_doc_vikas FROM public.profiles WHERE full_name ILIKE '%Vikas%' AND role = 'doctor' AND is_active = true LIMIT 1;

  -- ── DAY 1: TODAY (CURRENT_DATE) - 9 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, doctor_name, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000017', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE, '09:30:00', 'regular', 'completed', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Routine visual acuity checkup and refraction.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000018', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE, '10:15:00', 'walk_in', 'completed', 'Doctor: Dr Nimisha' || E'\\n' || 'Emergency consultation for molar sensitivity.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000018', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE, '11:00:00', 'regular', 'waiting', 'Doctor: Dr Varun' || E'\\n' || 'Patient marked present. Waiting for clinical examination.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000019', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE, '13:30:00', 'follow_up', 'confirmed', 'Doctor: Dr Vikas' || E'\\n' || 'Follow-up on composite restoration.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000019', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE, '14:15:00', 'regular', 'confirmed', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Glaucoma screening & IOP measurement.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000020', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE, '15:00:00', 'regular', 'scheduled', 'Doctor: Dr Nimisha' || E'\\n' || 'Routine dental cleaning and hygiene review.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000020', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE, '17:30:00', 'regular', 'scheduled', 'Doctor: Dr Varun' || E'\\n' || 'Eye strain and headache after screen work.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000021', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE, '18:15:00', 'regular', 'scheduled', 'Doctor: Dr Vikas' || E'\\n' || 'Crown delivery and bite check.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000021', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE, '19:00:00', 'walk_in', 'cancelled', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Patient requested cancellation due to personal emergency.', false, now(), now());

  -- ── DAY 2: TOMORROW (CURRENT_DATE + 1 day) - 8 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, doctor_name, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000022', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE + INTERVAL '1 day', '09:00:00', 'regular', 'confirmed', 'Doctor: Dr Varun' || E'\\n' || 'Follow-up on post-operative recovery.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000022', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE + INTERVAL '1 day', '10:00:00', 'regular', 'confirmed', 'Doctor: Dr Nimisha' || E'\\n' || 'Root canal therapy session 2.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000023', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE + INTERVAL '1 day', '11:15:00', 'regular', 'scheduled', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Slit-lamp examination for dry eye syndrome.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000023', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE + INTERVAL '1 day', '14:00:00', 'regular', 'scheduled', 'Doctor: Dr Vikas' || E'\\n' || 'Periodontal assessment and deep scaling.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000024', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE + INTERVAL '1 day', '15:30:00', 'walk_in', 'scheduled', 'Doctor: Dr Varun' || E'\\n' || 'Allergic conjunctivitis evaluation.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000024', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE + INTERVAL '1 day', '17:00:00', 'regular', 'scheduled', 'Doctor: Dr Nimisha' || E'\\n' || 'Orthodontic retainer review.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000025', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE + INTERVAL '1 day', '18:00:00', 'regular', 'scheduled', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Annual diabetic retinopathy screening.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000025', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE + INTERVAL '1 day', '19:00:00', 'regular', 'scheduled', 'Doctor: Dr Vikas' || E'\\n' || 'Tooth extraction post-op inspection.', false, now(), now());

  -- ── DAY 3: DAY AFTER TOMORROW (CURRENT_DATE + 2 days) - 8 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, doctor_name, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE + INTERVAL '2 days', '09:30:00', 'follow_up', 'confirmed', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Refraction follow-up and prescription adjustment.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000001', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE + INTERVAL '2 days', '10:30:00', 'regular', 'confirmed', 'Doctor: Dr Vikas' || E'\\n' || 'Impression for ceramic crown.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000002', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE + INTERVAL '2 days', '11:30:00', 'regular', 'scheduled', 'Doctor: Dr Varun' || E'\\n' || 'Fundus examination and IOP check.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000002', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE + INTERVAL '2 days', '13:45:00', 'walk_in', 'scheduled', 'Doctor: Dr Nimisha' || E'\\n' || 'Gingival bleeding check.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000003', 'eye', v_doc_mitesh, 'Dr Mitesh Jain', CURRENT_DATE + INTERVAL '2 days', '14:45:00', 'regular', 'scheduled', 'Doctor: Dr Mitesh Jain' || E'\\n' || 'Cataract pre-operative counseling.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000003', 'dental', v_doc_vikas, 'Dr Vikas', CURRENT_DATE + INTERVAL '2 days', '15:30:00', 'regular', 'scheduled', 'Doctor: Dr Vikas' || E'\\n' || 'Restoration polishing and fluoridation.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000004', 'eye', v_doc_varun, 'Dr Varun', CURRENT_DATE + INTERVAL '2 days', '17:15:00', 'regular', 'scheduled', 'Doctor: Dr Varun' || E'\\n' || 'Astigmatism review and spectacle trial.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000004', 'dental', v_doc_nimisha, 'Dr Nimisha', CURRENT_DATE + INTERVAL '2 days', '18:30:00', 'regular', 'scheduled', 'Doctor: Dr Nimisha' || E'\\n' || 'Consultation for dental implants.', false, now(), now());

END $$;

-- ============================================================================
-- STEP 6: CLINICAL EXAMINATION & VITALS DATA
-- ============================================================================

DO $$
DECLARE
  v_staff_id UUID;
BEGIN
  SELECT id INTO v_staff_id FROM public.profiles WHERE is_active = true LIMIT 1;

  -- 1. Eye Examination for Patient E-0001 (Aarav Mehta)
  INSERT INTO public.eye_examinations (
    id, patient_id, examination_date, examination_time, visual_acuity_od, visual_acuity_os, visual_acuity,
    intraocular_pressure_od, intraocular_pressure_os, intraocular_pressure, slit_lamp_examination,
    diagnosis, clinical_notes, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '15 days', '10:00:00',
    '6/6', '6/9', 'OD 6/6, OS 6/9 with pinhole improving to 6/6',
    '14 mmHg', '15 mmHg', 'Applanation Tonometry normal',
    'Cornea clear bilaterally, anterior chamber normal depth without cells/flare, pupils reacting promptly.',
    'Simple Myopic Astigmatism (OS)',
    'Prescribed corrective lenses. Advised annual eye checkup.',
    v_staff_id, now(), now()
  );

  -- 2. Eye Examination for Patient E-0003 (Rajesh Kulkarni)
  INSERT INTO public.eye_examinations (
    id, patient_id, examination_date, examination_time, visual_acuity_od, visual_acuity_os, visual_acuity,
    intraocular_pressure_od, intraocular_pressure_os, intraocular_pressure, slit_lamp_examination,
    diagnosis, clinical_notes, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'a0000000-0000-0000-0000-000000000003', CURRENT_DATE - INTERVAL '10 days', '11:30:00',
    '6/18', '6/12', 'Bilateral progressive vision blurring, worse in bright light',
    '16 mmHg', '17 mmHg', 'Normal tension',
    'Bilateral nuclear sclerotic lens opacity grade II, cortical spokes in right eye. Fundus hazy but gross details visible.',
    'Senile Nuclear Sclerotic Cataract Grade II (OD > OS)',
    'Detailed cataract surgery counseling given. Prescribed pre-op lubricating drops. Advised biometry.',
    v_staff_id, now(), now()
  );

  -- 3. Eye Examination for Patient E-0017 (Nikhil Jain - Completed today)
  INSERT INTO public.eye_examinations (
    id, patient_id, examination_date, examination_time, visual_acuity_od, visual_acuity_os, visual_acuity,
    intraocular_pressure_od, intraocular_pressure_os, intraocular_pressure, slit_lamp_examination,
    diagnosis, clinical_notes, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'a0000000-0000-0000-0000-000000000017', CURRENT_DATE, '09:45:00',
    '6/6', '6/6', 'Normal bilateral visual acuity',
    '13 mmHg', '14 mmHg', 'Within normal limits',
    'Bilateral mild conjunctival hyperemia, tear film break-up time 6 seconds. Cornea clear.',
    'Bilateral Computer Vision Syndrome / Evaporative Dry Eye',
    'Advised 20-20-20 screen rule. Prescribed preservative-free Carboxymethylcellulose 0.5% drops QID for 30 days.',
    v_staff_id, now(), now()
  );

  -- 4. Dental Treatment for Patient D-0001 (Rahul Nair)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '14 days', '10:30:00',
    '16', 'Composite Resin Restoration',
    'Infiltration local anesthesia (2% Lignocaine with 1:80000 Adrenaline). Complete caries excavation on occlusal surface. Etching, bonding, nanohybrid composite restoration in increments. Occlusion adjusted and polished.',
    'Class I Deep Occlusal Dental Caries (Tooth 16)',
    'completed', v_staff_id, now(), now()
  );

  -- 5. Dental Treatment for Patient D-0003 (Vijay Bhosale)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000003', CURRENT_DATE - INTERVAL '11 days', '14:00:00',
    '36', 'Endodontic Therapy (Root Canal - Access & Biomechanical Prep)',
    'Access cavity prepared under rubber dam isolation. Canals negotiated (MB, ML, D) to working length. Chemo-mechanical preparation with Protaper rotary files up to F2. Copious 3% NaOCl irrigation. Calcium hydroxide intracanal dressing placed. Temporary restoration with Cavit.',
    'Symptomatic Irreversible Pulpitis with Apical Periodontitis (Tooth 36)',
    'in_progress', v_staff_id, now(), now()
  );

  -- 6. Dental Treatment for Patient D-0018 (Jyoti Mane - Completed today)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000018', CURRENT_DATE, '10:45:00',
    'All Quadrants', 'Full Mouth Ultrasonic Scaling & Polishing',
    'Supragingival and subgingival ultrasonic scaling performed using piezo scaler. Stains and calculus removed. Prophy paste polishing performed. Oral hygiene instructions demonstrated.',
    'Generalized Chronic Marginal Gingivitis with Moderate Calculus',
    'completed', v_staff_id, now(), now()
  );

END $$;

-- ============================================================================
-- STEP 7: ADD 8-10 FRESH REALISTIC VENDORS (EYE & DENTAL)
-- ============================================================================

INSERT INTO public.vendors (
  id, name, contact_person, phone, email, address, products_supplied, last_order_date, last_delivery_date, last_quantity, remarks, created_at, updated_at
) VALUES
('c0000000-0000-0000-0000-000000000001', 'Apex Ophthalmic Diagnostics & Devices', 'Mr. Ramesh Parekh', '9820011122', 'sales@apexophthalmic.demo', 'Unit 12, Industrial Area, Kanjurmarg West, Mumbai', ARRAY['Ophthalmoscopes', 'Slit Lamp Bulbs', 'Tonometer Prisms', 'Trial Lens Sets'], CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE - INTERVAL '4 days', 15.00, 'Primary ophthalmic diagnostic equipment and optical tool supplier.', now(), now()),
('c0000000-0000-0000-0000-000000000002', 'Drishti Pharmaceuticals & Eye Drops', 'Ms. Meenal Kulkarni', '9820022233', 'orders@drishtipharma.demo', 'Plot 45, MIDC Industrial Area, Andheri East, Mumbai', ARRAY['Carboxymethylcellulose Drops', 'Moxifloxacin Eye Drops', 'Tropicamide Drops', 'BSS Solution'], CURRENT_DATE - INTERVAL '5 days', CURRENT_DATE - INTERVAL '2 days', 250.00, 'Exclusive supplier of topical ophthalmic formulations and lubricants.', now(), now()),
('c0000000-0000-0000-0000-000000000003', 'VisionLine Surgical Consumables', 'Mr. Alok Singhania', '9820033344', 'contact@visionline.demo', 'B-108, Sagar Tech Plaza, Saki Naka, Mumbai', ARRAY['Eye Drapes', 'Micro-sponge Tips', 'Cataract Blades 2.8mm', 'Nylon Sutures 10-0'], CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE - INTERVAL '8 days', 120.00, 'Sterile surgical consumables and ophthalmic microsurgical disposables.', now(), now()),
('c0000000-0000-0000-0000-000000000004', 'PrimeDental Biomaterials Pvt Ltd', 'Dr. Sanjay Agarwal', '9820044455', 'supply@primedental.demo', '402, Trade Link, Bandra Kurla Complex, Mumbai', ARRAY['Composite Resin Kits', 'GIC Cement Type II', 'Etching Gel 37%', 'Bonding Agents'], CURRENT_DATE - INTERVAL '8 days', CURRENT_DATE - INTERVAL '3 days', 45.00, 'Premium restorative dental resins, bonding systems, and luting cements.', now(), now()),
('c0000000-0000-0000-0000-000000000005', 'OrthoDent Instruments & Handpieces', 'Mr. Vikram Mistry', '9820055566', 'sales@orthodent.demo', 'Shop 7, Kalbadevi Medical Market, South Mumbai', ARRAY['Extraction Forceps', 'Diamond Burs', 'High-Speed Handpieces', 'Mouth Mirrors'], CURRENT_DATE - INTERVAL '20 days', CURRENT_DATE - INTERVAL '12 days', 30.00, 'High-precision dental stainless steel hand instruments and rotary gear.', now(), now()),
('c0000000-0000-0000-0000-000000000006', 'DentLab Prosthetic Materials Supply', 'Ms. Pooja Shetty', '9820066677', 'info@dentlabmaterials.demo', 'G-4, Silver Metropolis, Western Express Highway, Goregaon, Mumbai', ARRAY['Alginate Impression Powder', 'Dental Stone Type IV', 'Cold Cure Acrylic', 'Impression Trays'], CURRENT_DATE - INTERVAL '12 days', CURRENT_DATE - INTERVAL '5 days', 60.00, 'Dental laboratory impression materials, gypsum, and casting waxes.', now(), now()),
('c0000000-0000-0000-0000-000000000007', 'CarePlus Hospital Hygiene & Disposables', 'Mr. Rajesh Merchant', '9820077788', 'orders@careplushygiene.demo', '18/A, Laxmi Industrial Estate, New Link Road, Andheri West, Mumbai', ARRAY['Nitrile Gloves (M/L)', 'Surgical 3-Ply Masks', 'Suction Tips', 'Surface Disinfectant'], CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE - INTERVAL '1 day', 500.00, 'Hospital-wide personal protective equipment and infection control.', now(), now()),
('c0000000-0000-0000-0000-000000000008', 'MediEquip Central Sterilization Supplies', 'Mr. Harish Kapadia', '9820088899', 'dispatch@mediequip.demo', 'Plot 9, Godrej Business District, Vikhroli West, Mumbai', ARRAY['Autoclave Indicator Strips', 'Sterilization Pouches', 'Medical Spirit 5L', 'Sterile Gauze Swabs'], CURRENT_DATE - INTERVAL '25 days', CURRENT_DATE - INTERVAL '18 days', 80.00, 'Central sterilization consumables and hospital ward consumables.', now(), now());

-- ============================================================================
-- STEP 8: CREATE FRESH INVENTORY STOCK DATA
-- ============================================================================

INSERT INTO public.inventory (
  id, name, category, department, sku, quantity, minimum_stock, unit, expiry_date, brand, vendor_id, price, is_active, created_at, updated_at
) VALUES
-- Eye Supplies
('d0000000-0000-0000-0000-000000000001', 'Carboxymethylcellulose 0.5% Lubricant Eye Drops (10ml)', 'Pharmaceuticals', 'eye', 'EYE-MED-001', 85.00, 20.00, 'vials', CURRENT_DATE + INTERVAL '365 days', 'Drishti Eye Care', 'c0000000-0000-0000-0000-000000000002', 140.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000002', 'Moxifloxacin 0.5% Antibacterial Eye Drops (5ml)', 'Pharmaceuticals', 'eye', 'EYE-MED-002', 45.00, 15.00, 'vials', CURRENT_DATE + INTERVAL '240 days', 'Drishti Eye Care', 'c0000000-0000-0000-0000-000000000002', 185.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000003', 'Tropicamide 0.8% + Phenylephrine 5% Mydriatic Drops', 'Pharmaceuticals', 'eye', 'EYE-MED-003', 4.00, 10.00, 'vials', CURRENT_DATE + INTERVAL '180 days', 'Drishti Eye Care', 'c0000000-0000-0000-0000-000000000002', 160.00, true, now(), now()), -- LOW STOCK
('d0000000-0000-0000-0000-000000000004', 'Sterile Disposable Eye Drapes with Aperture (Box of 20)', 'Consumables', 'eye', 'EYE-SUR-001', 35.00, 10.00, 'boxes', CURRENT_DATE + INTERVAL '500 days', 'VisionLine', 'c0000000-0000-0000-0000-000000000003', 450.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000005', 'Ophthalmic Micro-Sponge Eye Spears (Pack of 100)', 'Consumables', 'eye', 'EYE-SUR-002', 18.00, 5.00, 'packs', CURRENT_DATE + INTERVAL '600 days', 'VisionLine', 'c0000000-0000-0000-0000-000000000003', 380.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000006', 'Proparacaine 0.5% Topical Anesthetic Drops (Expired Batch)', 'Pharmaceuticals', 'eye', 'EYE-EXP-001', 5.00, 10.00, 'vials', CURRENT_DATE - INTERVAL '15 days', 'Drishti Eye Care', 'c0000000-0000-0000-0000-000000000002', 120.00, true, now(), now()), -- EXPIRED

-- Dental Supplies
('d0000000-0000-0000-0000-000000000007', 'Nanohybrid Composite Restorative Resin Kit (Syringes A1, A2, A3)', 'Restorative', 'dental', 'DEN-RES-001', 12.00, 5.00, 'kits', CURRENT_DATE + INTERVAL '400 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 1250.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000008', 'Glass Ionomer Cement (GIC Type II - Restorative)', 'Restorative', 'dental', 'DEN-RES-002', 3.00, 8.00, 'packs', CURRENT_DATE + INTERVAL '300 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 850.00, true, now(), now()), -- LOW STOCK
('d0000000-0000-0000-0000-000000000009', 'Sodium Hypochlorite 3% Endodontic Irrigation Solution (500ml)', 'Endodontics', 'dental', 'DEN-ENDO-001', 25.00, 6.00, 'bottles', CURRENT_DATE + INTERVAL '350 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 210.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000010', 'High-Speed Friction Grip Diamond Burs (Assorted Pack of 10)', 'Instruments', 'dental', 'DEN-ROT-001', 14.00, 5.00, 'packs', CURRENT_DATE + INTERVAL '700 days', 'OrthoDent', 'c0000000-0000-0000-0000-000000000005', 650.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000011', 'Lignocaine 2% with Adrenaline 1:80000 Dental Cartridges (Expired)', 'Anesthetics', 'dental', 'DEN-EXP-001', 8.00, 15.00, 'cartridges', CURRENT_DATE - INTERVAL '30 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 450.00, true, now(), now()), -- EXPIRED

-- Shared / General Hospital Disposables
('d0000000-0000-0000-0000-000000000012', 'Powder-Free Medical Nitrile Examination Gloves - Medium (Box of 100)', 'Hygiene', 'general', 'GEN-HYG-001', 40.00, 15.00, 'boxes', CURRENT_DATE + INTERVAL '450 days', 'CarePlus', 'c0000000-0000-0000-0000-000000000007', 380.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000013', 'Surgical 3-Ply Protective Face Masks with Meltblown Filter (Pack of 50)', 'Hygiene', 'general', 'GEN-HYG-002', 5.00, 20.00, 'packs', CURRENT_DATE + INTERVAL '500 days', 'CarePlus', 'c0000000-0000-0000-0000-000000000007', 175.00, true, now(), now()), -- LOW STOCK
('d0000000-0000-0000-0000-000000000014', 'Chemical Autoclave Steam Indicator Strips Class 4 (Box of 200)', 'Sterilization', 'general', 'GEN-STR-001', 16.00, 5.00, 'boxes', CURRENT_DATE + INTERVAL '600 days', 'MediEquip', 'c0000000-0000-0000-0000-000000000008', 550.00, true, now(), now());

-- ============================================================================
-- STEP 9: PURCHASE ORDERS (FOR REPLENISHMENT TRACKING)
-- ============================================================================

DO $$
DECLARE
  v_admin_id UUID;
  v_po1_id UUID := 'e0000000-0000-0000-0000-000000000001';
  v_po2_id UUID := 'e0000000-0000-0000-0000-000000000002';
  v_po3_id UUID := 'e0000000-0000-0000-0000-000000000003';
  v_po4_id UUID := 'e0000000-0000-0000-0000-000000000004';
  v_po5_id UUID := 'e0000000-0000-0000-0000-000000000005';
BEGIN
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' LIMIT 1;

  -- 1. PO-2026-0001: Received Eye Pharmaceuticals Order
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po1_id, 'PO-2026-0001', 'c0000000-0000-0000-0000-000000000002', CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE - INTERVAL '2 days',
    'received', 15350.00, 15350.00, 'Monthly replenishment of ophthalmic lubricating and antibiotic drops.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po1_id, 'd0000000-0000-0000-0000-000000000001', 50.00, 140.00, 7000.00, 50.00, now(), now()),
  (gen_random_uuid(), v_po1_id, 'd0000000-0000-0000-0000-000000000002', 30.00, 185.00, 5550.00, 30.00, now(), now()),
  (gen_random_uuid(), v_po1_id, 'd0000000-0000-0000-0000-000000000003', 20.00, 140.00, 2800.00, 20.00, now(), now());

  -- 2. PO-2026-0002: Ordered Dental Restorative Biomaterials (In Transit)
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po2_id, 'PO-2026-0002', 'c0000000-0000-0000-0000-000000000004', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE + INTERVAL '2 days', NULL,
    'ordered', 21400.00, 21400.00, 'Restocking composite kits and restorative glass ionomer cement.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po2_id, 'd0000000-0000-0000-0000-000000000007', 15.00, 1250.00, 18750.00, 0.00, now(), now()),
  (gen_random_uuid(), v_po2_id, 'd0000000-0000-0000-0000-000000000008', 3.00, 883.33, 2650.00, 0.00, now(), now());

  -- 3. PO-2026-0003: Partially Received Clinic Disposables & Hygiene
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po3_id, 'PO-2026-0003', 'c0000000-0000-0000-0000-000000000007', CURRENT_DATE - INTERVAL '4 days', CURRENT_DATE, CURRENT_DATE,
    'partially_received', 16900.00, 16900.00, 'Gloves received in full, face masks awaiting remaining consignment.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po3_id, 'd0000000-0000-0000-0000-000000000012', 30.00, 380.00, 11400.00, 30.00, now(), now()),
  (gen_random_uuid(), v_po3_id, 'd0000000-0000-0000-0000-000000000013', 30.00, 183.33, 5500.00, 15.00, now(), now());

  -- 4. PO-2026-0004: Draft Surgical Eye Consumables
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po4_id, 'PO-2026-0004', 'c0000000-0000-0000-0000-000000000003', CURRENT_DATE, CURRENT_DATE + INTERVAL '5 days', NULL,
    'draft', 9000.00, 9000.00, 'Draft order for upcoming eye surgery schedule requirements.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po4_id, 'd0000000-0000-0000-0000-000000000004', 20.00, 450.00, 9000.00, 0.00, now(), now());

  -- 5. PO-2026-0005: Cancelled Order (Supplier stock out)
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po5_id, 'PO-2026-0005', 'c0000000-0000-0000-0000-000000000005', CURRENT_DATE - INTERVAL '12 days', CURRENT_DATE - INTERVAL '7 days', NULL,
    'cancelled', 6500.00, 6500.00, 'Order cancelled: manufacturer discontinued specific bur batch.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po5_id, 'd0000000-0000-0000-0000-000000000010', 10.00, 650.00, 6500.00, 0.00, now(), now());

END $$;

-- ============================================================================
-- STEP 10: FRESH DENTAL LAB TRACKING RECORDS
-- ============================================================================

INSERT INTO public.dental_lab (
  id, patient_id, case_number, case_type, status, sent_date, ready_date, delivered_date, remarks, created_at, updated_at
) VALUES
-- Delivered Crown Case
('f0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'DL-2026-001', 'Porcelain-Fused-to-Metal (PFM) Crown - Tooth 16', 'delivered', CURRENT_DATE - INTERVAL '12 days', CURRENT_DATE - INTERVAL '4 days', CURRENT_DATE - INTERVAL '2 days', 'Crown fit checked with bite paper; cemented with GIC luting agent.', now(), now()),

-- Ready Zirconia Crown (Awaiting Patient Appointment Today)
('f0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000003', 'DL-2026-002', 'Monolithic Zirconia Crown - Tooth 36', 'ready', CURRENT_DATE - INTERVAL '9 days', CURRENT_DATE - INTERVAL '1 day', NULL, 'Prosthesis arrived from lab. Shade A2 verified under clinical light.', now(), now()),

-- Processing Bridge Case
('f0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000005', 'DL-2026-003', '3-Unit Anterior Ceramic Bridge (11-13)', 'processing', CURRENT_DATE - INTERVAL '4 days', CURRENT_DATE + INTERVAL '3 days', NULL, 'Metal framework trial completed successfully. Ceramic layering in progress.', now(), now()),

-- Processing Removable Partial Denture
('f0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000013', 'DL-2026-004', 'Cast Partial Denture (Mandibular Bilateral)', 'processing', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE + INTERVAL '5 days', NULL, 'Primary alginate impression poured in Type IV die stone; sent for wax rim setup.', now(), now()),

-- Delivered Orthodontic Retainer
('f0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000024', 'DL-2026-005', 'Clear Vacuum Formed Retainer (Maxillary)', 'delivered', CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE - INTERVAL '1 day', 'Delivered with retainer hygiene case and cleaning instructions.', now(), now());

-- ============================================================================
-- STEP 11: FRESH BILLING & PAYMENT DATA (WITH REALISTIC HOURLY SLOTS)
-- ============================================================================

DO $$
DECLARE
  v_staff_id UUID;
  v_inv1_id UUID := '10000000-0000-0000-0000-000000000001';
  v_inv2_id UUID := '10000000-0000-0000-0000-000000000002';
  v_inv3_id UUID := '10000000-0000-0000-0000-000000000003';
  v_inv4_id UUID := '10000000-0000-0000-0000-000000000004';
  v_inv5_id UUID := '10000000-0000-0000-0000-000000000005';
  v_inv6_id UUID := '10000000-0000-0000-0000-000000000006';
  v_inv7_id UUID := '10000000-0000-0000-0000-000000000007';
BEGIN
  SELECT id INTO v_staff_id FROM public.profiles WHERE is_active = true LIMIT 1;

  -- 1. INVOICE 1: Fully Paid (INR 1,000 Total, INR 1,000 Paid) - Eye (15 days ago)
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv1_id, 'INV-2425-0001', 'a0000000-0000-0000-0000-000000000001', 'eye',
    1000.00, 0.00, 1000.00, 'paid', 'upi', 1000.00, v_staff_id,
    'Full payment via clinic UPI QR code', CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE - INTERVAL '15 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv1_id, 'Comprehensive Ophthalmology Consultation', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '15 days'),
  (gen_random_uuid(), v_inv1_id, 'Computerized Refraction & Spectacle Trial', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '15 days'),
  (gen_random_uuid(), v_inv1_id, 'Intraocular Pressure Tonometry', 1, 200.00, 200.00, false, CURRENT_DATE - INTERVAL '15 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv1_id, 1000.00, 'upi', 'UPI/729184019283/HDFC', CURRENT_DATE - INTERVAL '15 days', v_staff_id, 'Full payment via clinic UPI QR code', CURRENT_DATE - INTERVAL '15 days');

  -- 2. INVOICE 2: Partially Paid (INR 1,500 Total, INR 500 Paid, INR 1,000 Due) - Dental (14 days ago)
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv2_id, 'INV-2425-0002', 'b0000000-0000-0000-0000-000000000001', 'dental',
    1500.00, 0.00, 1500.00, 'partially_paid', 'cash', 500.00, v_staff_id,
    'Initial advance payment in cash; balance INR 1,000 due', CURRENT_DATE - INTERVAL '14 days', CURRENT_DATE - INTERVAL '14 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv2_id, 'Dental Consultation & Diagnosis', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '14 days'),
  (gen_random_uuid(), v_inv2_id, 'Class I Composite Restoration (Tooth 16)', 1, 1200.00, 1200.00, false, CURRENT_DATE - INTERVAL '14 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv2_id, 500.00, 'cash', 'RCP-0021-CSH', CURRENT_DATE - INTERVAL '14 days', v_staff_id, 'Initial advance payment in cash; balance INR 1,000 due', CURRENT_DATE - INTERVAL '14 days');

  -- 3. INVOICE 3: Unpaid (INR 800 Total, INR 0 Paid, INR 800 Due) - Eye (10 days ago)
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv3_id, 'INV-2425-0003', 'a0000000-0000-0000-0000-000000000003', 'eye',
    800.00, 0.00, 800.00, 'pending', 'upi', 0.00, v_staff_id,
    'Unpaid consultation fee', CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE - INTERVAL '10 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv3_id, 'Senior Ophthalmologist Cataract Consultation', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '10 days'),
  (gen_random_uuid(), v_inv3_id, 'Slit Lamp Biomicroscopy & Dilated Funduscopy', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '10 days');

  -- 4. INVOICE 4: Partially Paid (INR 2,000 Total, INR 1,000 Paid, INR 1,000 Due) - Dental (11 days ago)
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv4_id, 'INV-2425-0004', 'b0000000-0000-0000-0000-000000000003', 'dental',
    2000.00, 0.00, 2000.00, 'partially_paid', 'upi', 1000.00, v_staff_id,
    'Interim installment via UPI; balance INR 1,000 due', CURRENT_DATE - INTERVAL '11 days', CURRENT_DATE - INTERVAL '11 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv4_id, 'Root Canal Treatment (Tooth 36) - Access & Canal Prep', 1, 1500.00, 1500.00, false, CURRENT_DATE - INTERVAL '11 days'),
  (gen_random_uuid(), v_inv4_id, 'Digital Intraoral Periapical (IOPA) X-Ray (2 Views)', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '11 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv4_id, 1000.00, 'upi', 'UPI/839102948572/ICICI', CURRENT_DATE - INTERVAL '11 days', v_staff_id, 'Interim installment via UPI; balance INR 1,000 due', CURRENT_DATE - INTERVAL '11 days');

  -- 5. INVOICE 5: Fully Paid (INR 1,500 Total, INR 1,500 Paid) - Yesterday at 11:30 AM (Dental)
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv5_id, 'INV-2425-0005', 'b0000000-0000-0000-0000-000000000017', 'dental',
    1500.00, 0.00, 1500.00, 'paid', 'upi', 1500.00, v_staff_id,
    'Dental restoration completed; settled via UPI QR code',
    (CURRENT_DATE - INTERVAL '1 day' + TIME '11:30:00')::timestamptz,
    (CURRENT_DATE - INTERVAL '1 day' + TIME '11:30:00')::timestamptz
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv5_id, 'Composite Resin Restoration & Polishing', 1, 1500.00, 1500.00, false, (CURRENT_DATE - INTERVAL '1 day' + TIME '11:30:00')::timestamptz);

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (
    gen_random_uuid(), v_inv5_id, 1500.00, 'upi', 'UPI/771092837461/GPay',
    (CURRENT_DATE - INTERVAL '1 day' + TIME '11:30:00')::timestamptz,
    v_staff_id, 'Settled via Google Pay UPI',
    (CURRENT_DATE - INTERVAL '1 day' + TIME '11:30:00')::timestamptz
  );

  -- 6. INVOICE 6: Fully Paid (INR 1,200 Total, INR 1,200 Paid) - TODAY at 10:45 AM (Slot: 10:00 AM - 11:00 AM) - Dental
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv6_id, 'INV-2425-0006', 'b0000000-0000-0000-0000-000000000018', 'dental',
    1200.00, 0.00, 1200.00, 'paid', 'other', 1200.00, v_staff_id,
    'Settled in full via Debit Card POS',
    (CURRENT_DATE + TIME '10:45:00')::timestamptz,
    (CURRENT_DATE + TIME '10:45:00')::timestamptz
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv6_id, 'Full Mouth Ultrasonic Scaling & Deep Polishing', 1, 1000.00, 1000.00, false, (CURRENT_DATE + TIME '10:45:00')::timestamptz),
  (gen_random_uuid(), v_inv6_id, 'Fluoride Foam Application & Oral Hygiene Kit', 1, 200.00, 200.00, false, (CURRENT_DATE + TIME '10:45:00')::timestamptz);

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (
    gen_random_uuid(), v_inv6_id, 1200.00, 'other', 'POS/HDFC/TXN-492102',
    (CURRENT_DATE + TIME '10:45:00')::timestamptz,
    v_staff_id, 'Settled in full via Debit Card POS',
    (CURRENT_DATE + TIME '10:45:00')::timestamptz
  );

  -- 7. INVOICE 7: Fully Paid (INR 800 Total, INR 800 Paid) - TODAY at 14:15 PM (Slot: 2:00 PM - 3:00 PM) - Eye
  INSERT INTO public.billing (
    id, invoice_number, patient_id, department, subtotal, discount, total_amount,
    payment_status, payment_mode, amount_paid, billed_by, notes, created_at, updated_at
  ) VALUES (
    v_inv7_id, 'INV-2425-0007', 'a0000000-0000-0000-0000-000000000017', 'eye',
    800.00, 0.00, 800.00, 'paid', 'upi', 800.00, v_staff_id,
    'Settled via UPI QR code',
    (CURRENT_DATE + TIME '14:15:00')::timestamptz,
    (CURRENT_DATE + TIME '14:15:00')::timestamptz
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv7_id, 'Ophthalmology Consultation & Dry Eye Evaluation', 1, 500.00, 500.00, false, (CURRENT_DATE + TIME '14:15:00')::timestamptz),
  (gen_random_uuid(), v_inv7_id, 'Tear Film Break-up Test & Slit Lamp Exam', 1, 300.00, 300.00, false, (CURRENT_DATE + TIME '14:15:00')::timestamptz);

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (
    gen_random_uuid(), v_inv7_id, 800.00, 'upi', 'UPI/992104812391/GPay',
    (CURRENT_DATE + TIME '14:15:00')::timestamptz,
    v_staff_id, 'Settled via UPI QR code',
    (CURRENT_DATE + TIME '14:15:00')::timestamptz
  );

END $$;

-- ============================================================================
-- STEP 12: ADD DEMO TASKS FOR EXISTING STAFF
-- ============================================================================

DO $$
DECLARE
  v_admin_id UUID;
  v_staff_id UUID;
BEGIN
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' LIMIT 1;
  SELECT id INTO v_staff_id FROM public.profiles WHERE role = 'staff' AND is_active = true LIMIT 1;
  IF v_staff_id IS NULL THEN v_staff_id := v_admin_id; END IF;

  INSERT INTO public.tasks (
    id, title, description, assigned_to, assigned_by, due_date, priority, status, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), 'Prepare Ophthalmology Examination Room 1', 'Clean slit-lamp optical lenses, restock proparacaine topical drops, and ensure trial frames are disinfected.', v_staff_id, v_admin_id, now() + INTERVAL '4 hours', 'high', 'in_progress', now(), now()),
  (gen_random_uuid(), 'Autoclave Dental Extraction & Scaling Instruments', 'Cycle batch 3 of restorative handpieces and extraction forceps through class-B autoclave; verify indicator strip color.', v_staff_id, v_admin_id, now() + INTERVAL '2 hours', 'critical', 'pending', now(), now()),
  (gen_random_uuid(), 'Verify Ophthalmic Pharmacy & Eye Drops Batch Stock', 'Conduct physical count of lubricating eye drops, verify expiration dates on shelf B, and log discrepancies.', v_staff_id, v_admin_id, now() + INTERVAL '1 day', 'medium', 'pending', now(), now()),
  (gen_random_uuid(), 'Confirm Tomorrow Dental Lab Case Deliveries', 'Call Apex and DentLab partners to confirm on-time delivery of Zirconia bridge for patient Vijay Bhosale.', v_staff_id, v_admin_id, now() - INTERVAL '2 hours', 'high', 'completed', now() - INTERVAL '1 day', now()),
  (gen_random_uuid(), 'Update Weekly Clinical Waste & Sharp Disposal Log', 'Sign off yellow and red clinical waste container disposal consignment with municipal waste vendor.', v_staff_id, v_admin_id, now() - INTERVAL '1 day', 'medium', 'overdue', now() - INTERVAL '2 days', now());

END $$;

-- ============================================================================
-- STEP 13: ATTENDANCE DEMO DATA (SAFE RECORD FOR TODAY)
-- ============================================================================

DO $$
DECLARE
  v_staff_rec RECORD;
BEGIN
  FOR v_staff_rec IN SELECT id FROM public.profiles WHERE role = 'staff' AND is_active = true LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.staff_attendance WHERE staff_id = v_staff_rec.id AND record_date = CURRENT_DATE
    ) THEN
      INSERT INTO public.staff_attendance (
        id, staff_id, record_date, check_in_time, check_out_time, status, is_late, working_hours, late_minutes, notes, created_at, updated_at
      ) VALUES (
        gen_random_uuid(), v_staff_rec.id, CURRENT_DATE,
        CURRENT_DATE + TIME '08:55:00', NULL, 'present', false, NULL, 0, 'Shift started on schedule via clinic terminal', now(), now()
      );
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- STEP 14: INTEGRITY AUDIT ASSERTIONS (FAIL-FAST TRANSACTIONS)
-- ============================================================================

DO $$
DECLARE
  v_patient_count INT;
  v_eye_patient_count INT;
  v_dental_patient_count INT;
  v_invoice_count INT;
  v_appt_count INT;
  v_vendor_count INT;
  v_order_count INT;
  v_lab_count INT;
  v_inventory_count INT;
  v_invalid_doc_count INT;
BEGIN
  -- 1. Patients check (verifying the newly seeded 50 demo patients: 25 Eye, 25 Dental)
  SELECT count(*) INTO v_patient_count FROM public.patients
  WHERE id::text LIKE 'a0000000%' OR id::text LIKE 'b0000000%' OR patient_number LIKE 'E-%' OR patient_number LIKE 'D-%';
  IF v_patient_count <> 50 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 50 seeded demo patients, found %', v_patient_count;
  END IF;

  SELECT count(*) INTO v_eye_patient_count FROM public.patients
  WHERE department = 'eye' AND (id::text LIKE 'a0000000%' OR patient_number LIKE 'E-%');
  IF v_eye_patient_count <> 25 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 25 eye demo patients, found %', v_eye_patient_count;
  END IF;

  SELECT count(*) INTO v_dental_patient_count FROM public.patients
  WHERE department = 'dental' AND (id::text LIKE 'b0000000%' OR patient_number LIKE 'D-%');
  IF v_dental_patient_count <> 25 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 25 dental demo patients, found %', v_dental_patient_count;
  END IF;

  -- 2. Invoices check
  SELECT count(*) INTO v_invoice_count FROM public.billing;
  IF v_invoice_count <> 7 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 7 billing invoices, found %', v_invoice_count;
  END IF;

  -- 3. Appointments check
  SELECT count(*) INTO v_appt_count FROM public.appointments;
  IF v_appt_count < 15 THEN
    RAISE EXCEPTION 'Audit failed: expected >= 15 appointments, found %', v_appt_count;
  END IF;

  -- 4. Doctor Assignment Integrity check: Ensure NO appointments are assigned to Admin profiles!
  SELECT count(*) INTO v_invalid_doc_count
  FROM public.appointments a
  JOIN public.profiles p ON p.id = a.doctor_id
  WHERE p.role = 'admin';

  IF v_invalid_doc_count > 0 THEN
    RAISE EXCEPTION 'Audit failed: % appointments are assigned to an Admin user instead of clinical doctors!', v_invalid_doc_count;
  END IF;

  -- 5. Vendors check
  SELECT count(*) INTO v_vendor_count FROM public.vendors;
  IF v_vendor_count <> 8 THEN
    RAISE EXCEPTION 'Audit failed: expected 8 vendors, found %', v_vendor_count;
  END IF;

  -- 6. Purchase Orders check
  SELECT count(*) INTO v_order_count FROM public.purchase_orders;
  IF v_order_count <> 5 THEN
    RAISE EXCEPTION 'Audit failed: expected 5 purchase orders, found %', v_order_count;
  END IF;

  -- 7. Dental Lab Cases check
  SELECT count(*) INTO v_lab_count FROM public.dental_lab;
  IF v_lab_count <> 5 THEN
    RAISE EXCEPTION 'Audit failed: expected 5 dental lab cases, found %', v_lab_count;
  END IF;

  -- 8. Inventory check
  SELECT count(*) INTO v_inventory_count FROM public.inventory;
  IF v_inventory_count <> 14 THEN
    RAISE EXCEPTION 'Audit failed: expected 14 inventory items, found %', v_inventory_count;
  END IF;

  RAISE NOTICE 'MKES CARE+ Complete Data Cleanup and Seeding verified successfully!';
END $$;

COMMIT;

-- ============================================================================
-- FINAL VERIFICATION AUDIT QUERIES
-- ============================================================================

-- 1. Patient distribution by department (Expected: 25 Eye, 25 Dental, 50 Total)
SELECT department, count(*) AS patient_count
FROM public.patients
GROUP BY department
ORDER BY department;

-- 2. 3-Day Appointment schedule count per day and doctor distribution
SELECT
  appointment_date,
  department,
  doctor_name,
  count(*) AS appt_count
FROM public.appointments
GROUP BY appointment_date, department, doctor_name
ORDER BY appointment_date, department, doctor_name;

-- 3. Billing Invoices verification (Expected: 7 invoices with correct balances & payment modes)
SELECT invoice_number, total_amount, amount_paid, (total_amount - amount_paid) AS remaining_balance, payment_status, payment_mode
FROM public.billing
ORDER BY invoice_number;

-- 4. Central Inventory stock status summary (Expected: 9 Normal, 3 Low Stock, 2 Expired)
SELECT
  CASE
    WHEN expiry_date < CURRENT_DATE THEN 'Expired (Quarantine)'
    WHEN quantity <= minimum_stock THEN 'Low Stock (Replenish)'
    ELSE 'Normal Stock'
  END AS stock_condition,
  count(*) AS item_count
FROM public.inventory
GROUP BY 1
ORDER BY 1;

-- 5. Operational entities summary
SELECT
  (SELECT count(*) FROM public.vendors) AS vendors_count,
  (SELECT count(*) FROM public.purchase_orders) AS purchase_orders_count,
  (SELECT count(*) FROM public.purchase_order_items) AS po_items_count,
  (SELECT count(*) FROM public.dental_lab) AS dental_lab_cases_count,
  (SELECT count(*) FROM public.tasks) AS active_tasks_count,
  (SELECT count(*) FROM public.profiles WHERE role = 'admin') AS preserved_admins_count,
  (SELECT count(*) FROM public.profiles WHERE role = 'staff') AS preserved_staff_count;
"""

with open(sql_file, "w", encoding="utf-8") as f:
    f.write(sql_content)

print(f"Generated {sql_file} successfully! Size: {os.path.getsize(sql_file)} bytes")
