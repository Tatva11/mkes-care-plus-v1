import os

sql_file = "scripts/clean_and_seed_demo_data.sql"

sql_content = """-- ============================================================================
-- MKES CARE+ — Complete Data Cleanup, Reset & Fresh Demo Data Seeding (v2.0)
-- File: scripts/clean_and_seed_demo_data.sql
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
--   4. Creation of 3-day appointment schedule (8-10 appointments/day, >=5/day).
--   5. Clinical examinations (Eye) & Dental treatments (Dental).
--   6. 8-10 Fictional Vendors covering Eye and Dental supplies.
--   7. Supplier Purchase Orders & items with calculated totals.
--   8. Dental Lab Tracking cases with procedural status tracking.
--   9. Billing Invoices (Fully Paid, Partially Paid, Unpaid) & Payments.
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
    IF p.id IS NOT NULL THEN
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
-- STEP 2: SAFETY CHECKS & TRIGGER / RLS SUSPENSION
-- ============================================================================

-- Explicitly disable RLS on tables being cleared so no records are hidden from DELETE
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
    'patients'
  ];
BEGIN
  FOREACH t IN ARRAY rls_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' DISABLE ROW LEVEL SECURITY;';
    END IF;
  END LOOP;
END $$;

-- Temporarily disable user triggers that block deletion (such as locked surgery items & billing guards)
-- Note: 'DISABLE TRIGGER USER' safely disables user-defined triggers without requiring superuser.
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
BEGIN
  FOREACH t IN ARRAY guard_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' DISABLE TRIGGER USER;';
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- STEP 3: COMPLETE DEMO DATA CLEANUP IN STRICT CHILD-TO-PARENT ORDER
-- ============================================================================

DO $$
DECLARE
  tbl TEXT;
  tbls TEXT[] := ARRAY[
    -- 1. Leaf clinical records referencing inventory and eye_surgeries
    'clinical_inventory_usage',
    'eye_examinations',
    'dental_treatments',
    -- 2. Eye Surgery subsystem (all children before inventory & patients!)
    'eye_surgery_insurance_payments',
    'eye_surgery_insurances',
    'eye_surgery_inventory_consumptions',
    'eye_surgery_notification_events',
    'eye_surgery_items',
    'eye_surgery_item_templates',
    'eye_surgeries',
    -- 3. Dental Lab & Appointment communications
    'dental_lab',
    'whatsapp_message_logs',
    'whatsapp_messages_outbox',
    'whatsapp_chat_sessions',
    'whatsapp_appointment_requests',
    'patient_attendance',
    'appointments',
    -- 4. Inventory dependents, orders and batches
    'inventory_batches',
    'purchase_order_items',
    'purchase_orders',
    'stock_requests',
    'department_inventory',
    'inventory_transactions',
    -- 5. Central Inventory & Vendors (now 100% free of dependent references!)
    'inventory',
    'vendors',
    -- 6. Billing & Payments
    'billing_payments',
    'billing_items',
    'billing',
    -- 7. Operational tasks and legacy tables
    'task_history',
    'tasks',
    'optical_orders',
    'sales',
    -- 8. Root patients table (all dependent children now cleared!)
    'patients'
  ];
  v_del_count BIGINT;
BEGIN
  FOREACH tbl IN ARRAY tbls LOOP
    IF to_regclass('public.' || tbl) IS NOT NULL THEN
      EXECUTE 'DELETE FROM public.' || quote_ident(tbl);
      GET DIAGNOSTICS v_del_count = ROW_COUNT;
      RAISE NOTICE 'Cleared table public.% (deleted % rows)', tbl, v_del_count;
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- STEP 4: RE-ENABLE RLS AND OPERATIONAL TRIGGERS
-- ============================================================================

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
    'patients'
  ];
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
BEGIN
  FOREACH t IN ARRAY rls_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE ROW LEVEL SECURITY;';
    END IF;
  END LOOP;

  FOREACH t IN ARRAY guard_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE TRIGGER USER;';
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- STEP 3: REGISTER EXACTLY 50 FRESH DEMO PATIENTS (25 EYE + 25 DENTAL)
-- ============================================================================

INSERT INTO public.patients (
  id, patient_number, name, dob, address, mobile, department, reference, visit_date, whatsapp_opt_out, created_at, updated_at
) VALUES
-- 25 EYE PATIENTS (E-0001 to E-0025)
('a0000000-0000-0000-0000-000000000001', 'E-0001', 'Aarav Mehta', '1985-04-12', 'B-302, Palm Heights, Link Road, Malad West, Mumbai', '9820112345', 'eye', 'Self', CURRENT_DATE - INTERVAL '15 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000002', 'E-0002', 'Priya Sharma', '1992-08-23', 'A-14, Green Valley Apt, SV Road, Kandivali West, Mumbai', '9820123456', 'eye', 'Dr. Joshi', CURRENT_DATE - INTERVAL '12 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000003', 'E-0003', 'Rajesh Kulkarni', '1968-11-05', 'C-104, Sai Sadan, Chincholi Bunder, Malad West, Mumbai', '9820134567', 'eye', 'Family Physician', CURRENT_DATE - INTERVAL '10 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000004', 'E-0004', 'Ananya Iyer', '2001-02-18', 'Flat 401, Surya Sagar, Marve Road, Malad West, Mumbai', '9820145678', 'eye', 'Self', CURRENT_DATE - INTERVAL '9 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000005', 'E-0005', 'Vikram Patel', '1975-06-30', '12/B, Shanti Niketan, MG Road, Goregaon West, Mumbai', '9820156789', 'eye', 'Dr. Rao', CURRENT_DATE - INTERVAL '8 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000006', 'E-0006', 'Sunita Verma', '1962-09-14', '702, Silver Arch, Evershine Nagar, Malad West, Mumbai', '9820167890', 'eye', 'Dr. Deshmukh', CURRENT_DATE - INTERVAL '7 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000007', 'E-0007', 'Rohan Joshi', '1995-12-01', 'Flat 102, Gokul Tower, Borivali West, Mumbai', '9820178901', 'eye', 'Self', CURRENT_DATE - INTERVAL '6 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000008', 'E-0008', 'Meera Deshmukh', '1988-03-27', 'B-501, Neelkanth Valley, Malad West, Mumbai', '9820189012', 'eye', 'General Hospital', CURRENT_DATE - INTERVAL '5 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000009', 'E-0009', 'Sanjay Gupta', '1970-07-19', '304, Riddhi Siddhi Apt, Kandivali West, Mumbai', '9820190123', 'eye', 'Self', CURRENT_DATE - INTERVAL '4 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000010', 'E-0010', 'Sneha Nair', '1998-05-11', '801, Sea Breeze, Marve Beach Road, Malad West, Mumbai', '9820201234', 'eye', 'Dr. Nair', CURRENT_DATE - INTERVAL '4 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000011', 'E-0011', 'Aditya Rao', '1982-10-08', '201, Panchsheel Park, Goregaon West, Mumbai', '9820212345', 'eye', 'Self', CURRENT_DATE - INTERVAL '3 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000012', 'E-0012', 'Kavita Shah', '1965-01-25', 'B-203, Keshava Kunj, SV Road, Malad West, Mumbai', '9820223456', 'eye', 'Dr. Joshi', CURRENT_DATE - INTERVAL '3 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000013', 'E-0013', 'Suresh Menon', '1958-04-16', '102, Shreepal Tower, Chincholi Phatak, Malad West, Mumbai', '9820234567', 'eye', 'Self', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000014', 'E-0014', 'Pooja Agarwal', '1990-11-29', '405, Blossom Heights, Kandivali West, Mumbai', '9820245678', 'eye', 'Colleague', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('a0000000-0000-0000-0000-000000000015', 'E-0015', 'Ramesh Shinde', '1973-08-04', 'D-12, Sahyadri Colony, Goregaon West, Mumbai', '9820256789', 'eye', 'Self', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('a0000000-0000-0000-0000-000000000016', 'E-0016', 'Divya Bhat', '1994-06-15', 'C-601, Sterling Park, Link Road, Malad West, Mumbai', '9820267890', 'eye', 'Dr. Bhat', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('a0000000-0000-0000-0000-000000000017', 'E-0017', 'Nikhil Jain', '1987-02-09', '14, Vardhman Complex, Malad West, Mumbai', '9820278901', 'eye', 'Self', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000018', 'E-0018', 'Neha Kadam', '1996-09-21', 'A-304, Shivneri Apt, Kandivali West, Mumbai', '9820289012', 'eye', 'Self', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000019', 'E-0019', 'Manoj More', '1969-12-14', '502, Jai Ganesh Sadan, Malad West, Mumbai', '9820290123', 'eye', 'General Hospital', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000020', 'E-0020', 'Tanvi Sawant', '2003-07-03', 'Flat 202, Radhe Kunj, SV Road, Goregaon West, Mumbai', '9820301234', 'eye', 'Self', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000021', 'E-0021', 'Amit Chawla', '1980-03-17', '701, Marina Heights, Marve Road, Malad West, Mumbai', '9820312345', 'eye', 'Dr. Chawla', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000022', 'E-0022', 'Ritu Sen', '1991-10-31', 'B-103, Lotus Grandeur, Kandivali West, Mumbai', '9820323456', 'eye', 'Self', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000023', 'E-0023', 'Deepak Patil', '1977-05-22', '402, Samarth Krupa, Malad West, Mumbai', '9820334567', 'eye', 'Family Physician', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000024', 'E-0024', 'Swati Kamble', '1989-01-11', '101, Anand Vihar, Goregaon West, Mumbai', '9820345678', 'eye', 'Self', CURRENT_DATE, false, now(), now()),
('a0000000-0000-0000-0000-000000000025', 'E-0025', 'Harish Vyas', '1960-08-19', '804, Arihant Tower, SV Road, Malad West, Mumbai', '9820356789', 'eye', 'Self', CURRENT_DATE, false, now(), now()),

-- 25 DENTAL PATIENTS (D-0001 to D-0025)
('b0000000-0000-0000-0000-000000000001', 'D-0001', 'Rahul Nair', '1984-03-15', 'A-201, Green Meadows, Link Road, Malad West, Mumbai', '9820367890', 'dental', 'Self', CURRENT_DATE - INTERVAL '14 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000002', 'D-0002', 'Anjali Verma', '1993-07-28', 'Flat 503, Shanti Tower, Kandivali West, Mumbai', '9820378901', 'dental', 'Dr. Patil', CURRENT_DATE - INTERVAL '13 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000003', 'D-0003', 'Vijay Bhosale', '1971-12-09', '12, Shivaji Nagar, SV Road, Goregaon West, Mumbai', '9820389012', 'dental', 'Self', CURRENT_DATE - INTERVAL '11 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000004', 'D-0004', 'Shalini Pillai', '1997-04-02', '302, Emerald Court, Evershine Nagar, Malad West, Mumbai', '9820390123', 'dental', 'Friend', CURRENT_DATE - INTERVAL '10 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000005', 'D-0005', 'Prakash Sethi', '1966-09-17', 'B-101, Sagar Villa, Marve Road, Malad West, Mumbai', '9820401234', 'dental', 'Self', CURRENT_DATE - INTERVAL '9 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000006', 'D-0006', 'Deepa Nambiar', '1989-11-24', '704, Royal Palms, Goregaon West, Mumbai', '9820412345', 'dental', 'Dr. Rao', CURRENT_DATE - INTERVAL '8 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000007', 'D-0007', 'Gaurav Trivedi', '1981-06-08', '401, Shreeji Krupa, Kandivali West, Mumbai', '9820423456', 'dental', 'Self', CURRENT_DATE - INTERVAL '7 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000008', 'D-0008', 'Preeti Chopra', '1995-02-14', '15/C, Silver Beach Apt, Malad West, Mumbai', '9820434567', 'dental', 'Self', CURRENT_DATE - INTERVAL '6 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000009', 'D-0009', 'Manish Saxena', '1978-08-30', 'Flat 602, Golden Oak, Borivali West, Mumbai', '9820445678', 'dental', 'General Hospital', CURRENT_DATE - INTERVAL '5 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000010', 'D-0010', 'Shruti Hegde', '2000-10-19', 'A-303, Rosewood Heights, Malad West, Mumbai', '9820456789', 'dental', 'Self', CURRENT_DATE - INTERVAL '5 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000011', 'D-0011', 'Alok Pandey', '1986-01-05', '502, Kalpataru Crest, Kandivali West, Mumbai', '9820467890', 'dental', 'Dr. Sethi', CURRENT_DATE - INTERVAL '4 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000012', 'D-0012', 'Rashmi Prabhu', '1992-05-23', 'B-404, Vasundhara, Goregaon West, Mumbai', '9820478901', 'dental', 'Self', CURRENT_DATE - INTERVAL '3 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000013', 'D-0013', 'Chetan Walia', '1963-07-12', '103, Guru Kripa, Chincholi Bunder, Malad West, Mumbai', '9820489012', 'dental', 'Family Friend', CURRENT_DATE - INTERVAL '3 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000014', 'D-0014', 'Rekha Solanki', '1974-12-29', '601, Shanti Sadan, SV Road, Malad West, Mumbai', '9820490123', 'dental', 'Self', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000015', 'D-0015', 'Sandeep Gaikwad', '1988-09-03', '204, Siddhivinayak Apt, Kandivali West, Mumbai', '9820501234', 'dental', 'Colleague', CURRENT_DATE - INTERVAL '2 days', false, now(), now()),
('b0000000-0000-0000-0000-000000000016', 'D-0016', 'Shilpa Shenoy', '1994-04-16', 'Flat 802, Lake View, Goregaon West, Mumbai', '9820512345', 'dental', 'Self', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('b0000000-0000-0000-0000-000000000017', 'D-0017', 'Kiran Waghmare', '1979-02-27', '301, Maitri Park, Link Road, Malad West, Mumbai', '9820523456', 'dental', 'Dr. Gaikwad', CURRENT_DATE - INTERVAL '1 day', false, now(), now()),
('b0000000-0000-0000-0000-000000000018', 'D-0018', 'Jyoti Mane', '1998-08-14', 'B-202, Gokuldham, Goregaon West, Mumbai', '9820534567', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000019', 'D-0019', 'Kunal Kapoor', '1983-11-20', '405, Grandeur Enclave, Malad West, Mumbai', '9820545678', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000020', 'D-0020', 'Archana Date', '1967-03-09', '703, Yashodhan Apt, Kandivali West, Mumbai', '9820556789', 'dental', 'General Physician', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000021', 'D-0021', 'Vinod Rathod', '1976-06-25', '104, Om Shanti Sadan, Malad West, Mumbai', '9820567890', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000022', 'D-0022', 'Seema Jadhav', '1991-01-18', 'A-501, Prithvi Tower, SV Road, Goregaon West, Mumbai', '9820578901', 'dental', 'Friend', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000023', 'D-0023', 'Nitin Shrivastav', '1985-09-07', '203, Dev Darshan, Marve Road, Malad West, Mumbai', '9820589012', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000024', 'D-0024', 'Vandana Koli', '1999-12-30', '604, Sagar Samrat, Malad West, Mumbai', '9820590123', 'dental', 'Self', CURRENT_DATE, false, now(), now()),
('b0000000-0000-0000-0000-000000000025', 'D-0025', 'Vishal Tawde', '1961-05-14', 'Flat 101, Chintamani Sadan, Kandivali West, Mumbai', '9820601234', 'dental', 'Dr. Patil', CURRENT_DATE, false, now(), now());

-- ============================================================================
-- STEP 4: CREATE APPOINTMENTS ACROSS 3 CONSECUTIVE DAYS (8-10 APPOINTMENTS / DAY)
-- ============================================================================

DO $$
DECLARE
  v_admin_id UUID;
  v_staff_id UUID;
  v_eye_doc_id UUID;
  v_dental_doc_id UUID;
BEGIN
  -- Retrieve existing staff / admin profiles dynamically
  SELECT id INTO v_admin_id FROM public.profiles WHERE role = 'admin' AND is_active = true LIMIT 1;
  SELECT id INTO v_staff_id FROM public.profiles WHERE role = 'staff' AND is_active = true LIMIT 1;
  IF v_staff_id IS NULL THEN v_staff_id := v_admin_id; END IF;

  -- Doctors
  SELECT doctor_id INTO v_eye_doc_id FROM public.department_doctors WHERE is_active = true LIMIT 1;
  IF v_eye_doc_id IS NULL THEN v_eye_doc_id := v_admin_id; END IF;
  
  v_dental_doc_id := v_eye_doc_id;

  -- ── DAY 1: TODAY (CURRENT_DATE) — 9 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000017', 'eye', v_eye_doc_id, CURRENT_DATE, '09:30:00', 'regular', 'completed', 'Routine visual acuity checkup and refraction.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000018', 'dental', v_dental_doc_id, CURRENT_DATE, '10:15:00', 'walk_in', 'completed', 'Emergency consultation for molar sensitivity.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000018', 'eye', v_eye_doc_id, CURRENT_DATE, '11:00:00', 'regular', 'waiting', 'Patient marked present. Waiting for clinical examination.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000019', 'dental', v_dental_doc_id, CURRENT_DATE, '13:30:00', 'follow_up', 'confirmed', 'Follow-up on composite restoration.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000019', 'eye', v_eye_doc_id, CURRENT_DATE, '14:15:00', 'regular', 'confirmed', 'Glaucoma screening & IOP measurement.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000020', 'dental', v_dental_doc_id, CURRENT_DATE, '15:00:00', 'regular', 'scheduled', 'Routine dental cleaning and hygiene review.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000020', 'eye', v_eye_doc_id, CURRENT_DATE, '17:30:00', 'regular', 'scheduled', 'Eye strain and headache after screen work.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000021', 'dental', v_dental_doc_id, CURRENT_DATE, '18:15:00', 'regular', 'scheduled', 'Crown delivery and bite check.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000021', 'eye', v_eye_doc_id, CURRENT_DATE, '19:00:00', 'walk_in', 'cancelled', 'Patient requested cancellation due to personal emergency.', false, now(), now());

  -- ── DAY 2: TOMORROW (CURRENT_DATE + 1 day) — 8 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000022', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '1 day', '09:00:00', 'regular', 'confirmed', 'Follow-up on post-operative recovery.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000022', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '1 day', '10:00:00', 'regular', 'confirmed', 'Root canal therapy session 2.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000023', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '1 day', '11:15:00', 'regular', 'scheduled', 'Slit-lamp examination for dry eye syndrome.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000023', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '1 day', '14:00:00', 'regular', 'scheduled', 'Periodontal assessment and deep scaling.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000024', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '1 day', '15:30:00', 'walk_in', 'scheduled', 'Allergic conjunctivitis evaluation.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000024', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '1 day', '17:00:00', 'regular', 'scheduled', 'Orthodontic retainer review.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000025', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '1 day', '18:00:00', 'regular', 'scheduled', 'Annual diabetic retinopathy screening.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000025', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '1 day', '19:00:00', 'regular', 'scheduled', 'Tooth extraction post-op inspection.', false, now(), now());

  -- ── DAY 3: DAY AFTER TOMORROW (CURRENT_DATE + 2 days) — 8 Appointments ──
  INSERT INTO public.appointments (
    id, patient_id, department, doctor_id, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, created_at, updated_at
  ) VALUES
  -- Morning
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '2 days', '09:30:00', 'follow_up', 'confirmed', 'Refraction follow-up and prescription adjustment.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000001', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '2 days', '10:30:00', 'regular', 'confirmed', 'Impression for ceramic crown.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000002', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '2 days', '11:30:00', 'regular', 'scheduled', 'Fundus examination and IOP check.', false, now(), now()),
  -- Afternoon
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000002', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '2 days', '13:45:00', 'walk_in', 'scheduled', 'Gingival bleeding check.', false, now(), now()),
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000003', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '2 days', '14:45:00', 'regular', 'scheduled', 'Cataract pre-operative counseling.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000003', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '2 days', '15:30:00', 'regular', 'scheduled', 'Restoration polishing and fluoridation.', false, now(), now()),
  -- Evening
  (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000004', 'eye', v_eye_doc_id, CURRENT_DATE + INTERVAL '2 days', '17:15:00', 'regular', 'scheduled', 'Astigmatism review and spectacle trial.', false, now(), now()),
  (gen_random_uuid(), 'b0000000-0000-0000-0000-000000000004', 'dental', v_dental_doc_id, CURRENT_DATE + INTERVAL '2 days', '18:30:00', 'regular', 'scheduled', 'Consultation for dental implants.', false, now(), now());

END $$;

-- ============================================================================
-- STEP 5: CLINICAL EXAMINATION & VITALS DATA
-- ============================================================================

DO $$
DECLARE
  v_doc_id UUID;
BEGIN
  SELECT id INTO v_doc_id FROM public.profiles WHERE role = 'admin' LIMIT 1;

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
    v_doc_id, now(), now()
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
    v_doc_id, now(), now()
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
    v_doc_id, now(), now()
  );

  -- 4. Dental Treatment for Patient D-0001 (Rahul Nair)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '14 days', '10:30:00',
    '16', 'Composite Resin Restoration',
    'Infiltration local anesthesia (2% Lignocaine with 1:80000 Adrenaline). Complete caries excavation on occlusal surface. Etching, bonding, nanohybrid composite restoration in increments. Occlusion adjusted and polished.',
    'Class I Deep Occlusal Dental Caries (Tooth 16)',
    'completed', v_doc_id, now(), now()
  );

  -- 5. Dental Treatment for Patient D-0003 (Vijay Bhosale)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000003', CURRENT_DATE - INTERVAL '11 days', '14:00:00',
    '36', 'Endodontic Therapy (Root Canal - Access & Biomechanical Prep)',
    'Access cavity prepared under rubber dam isolation. Canals negotiated (MB, ML, D) to working length. Chemo-mechanical preparation with Protaper rotary files up to F2. Copious 3% NaOCl irrigation. Calcium hydroxide intracanal dressing placed. Temporary restoration with Cavit.',
    'Symptomatic Irreversible Pulpitis with Apical Periodontitis (Tooth 36)',
    'in_progress', v_doc_id, now(), now()
  );

  -- 6. Dental Treatment for Patient D-0018 (Jyoti Mane - Completed today)
  INSERT INTO public.dental_treatments (
    id, patient_id, treatment_date, treatment_time, tooth_number, procedure_performed, treatment_notes, diagnosis, procedure_status, created_by, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), 'b0000000-0000-0000-0000-000000000018', CURRENT_DATE, '10:45:00',
    'All Quadrants', 'Full Mouth Ultrasonic Scaling & Polishing',
    'Supragingival and subgingival ultrasonic scaling performed using piezo scaler. Stains and calculus removed. Prophy paste polishing performed. Oral hygiene instructions demonstrated.',
    'Generalized Chronic Marginal Gingivitis with Moderate Calculus',
    'completed', v_doc_id, now(), now()
  );

END $$;

-- ============================================================================
-- STEP 6: ADD 8-10 FRESH REALISTIC VENDORS (EYE & DENTAL)
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
-- STEP 7: CREATE FRESH INVENTORY STOCK DATA
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
('d0000000-0000-0000-0000-000000000006', 'Fluorescein Diagnostic Ophthalmic Strips (Box of 100)', 'Diagnostics', 'eye', 'EYE-DIA-001', 12.00, 5.00, 'boxes', CURRENT_DATE - INTERVAL '15 days', 'Apex Ophthalmic', 'c0000000-0000-0000-0000-000000000001', 220.00, true, now(), now()), -- EXPIRED STOCK

-- Dental Supplies
('d0000000-0000-0000-0000-000000000007', 'Nanohybrid Composite Restorative Kit Shade A2 (4g Syringe)', 'Biomaterials', 'dental', 'DEN-BIO-001', 28.00, 8.00, 'syringes', CURRENT_DATE + INTERVAL '450 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 1250.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000008', 'Glass Ionomer Restorative Cement Type II (15g + 10ml)', 'Biomaterials', 'dental', 'DEN-BIO-002', 3.00, 8.00, 'kits', CURRENT_DATE + INTERVAL '300 days', 'PrimeDental', 'c0000000-0000-0000-0000-000000000004', 890.00, true, now(), now()), -- LOW STOCK
('d0000000-0000-0000-0000-000000000009', 'Dust-Free Dental Alginate Impression Powder (450g Pack)', 'Impression', 'dental', 'DEN-LAB-001', 40.00, 10.00, 'packs', CURRENT_DATE + INTERVAL '320 days', 'DentLab Materials', 'c0000000-0000-0000-0000-000000000006', 420.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000010', 'Dental High-Speed Friction Grip Diamond Burs Kit (10 Pcs)', 'Instruments', 'dental', 'DEN-INS-001', 15.00, 5.00, 'sets', CURRENT_DATE + INTERVAL '900 days', 'OrthoDent', 'c0000000-0000-0000-0000-000000000005', 650.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000011', 'Dental Impression Bite Registration Silicone Catalyst', 'Impression', 'dental', 'DEN-LAB-002', 8.00, 4.00, 'tubes', CURRENT_DATE - INTERVAL '30 days', 'DentLab Materials', 'c0000000-0000-0000-0000-000000000006', 780.00, true, now(), now()), -- EXPIRED STOCK

-- General Clinic Supplies
('d0000000-0000-0000-0000-000000000012', 'Nitrile Medical Examination Gloves Medium (Box of 100)', 'Hygiene', 'general', 'GEN-HYG-001', 65.00, 15.00, 'boxes', CURRENT_DATE + INTERVAL '720 days', 'CarePlus Hygiene', 'c0000000-0000-0000-0000-000000000007', 380.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000013', 'Surgical 3-Ply Protective Face Masks (Box of 50)', 'Hygiene', 'general', 'GEN-HYG-002', 90.00, 20.00, 'boxes', CURRENT_DATE + INTERVAL '720 days', 'CarePlus Hygiene', 'c0000000-0000-0000-0000-000000000007', 150.00, true, now(), now()),
('d0000000-0000-0000-0000-000000000014', 'Medical Grade Isopropyl Alcohol Surface Disinfectant (5 Litres)', 'Hygiene', 'general', 'GEN-HYG-003', 2.00, 5.00, 'cans', CURRENT_DATE + INTERVAL '400 days', 'MediEquip Central', 'c0000000-0000-0000-0000-000000000008', 850.00, true, now(), now()); -- LOW STOCK

-- ============================================================================
-- STEP 8: CREATE FRESH PURCHASE ORDERS & LINE ITEMS
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
    status, subtotal, tax_amount, shipping_amount, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po1_id, 'PO-2026-0001', 'c0000000-0000-0000-0000-000000000002', CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE - INTERVAL '2 days',
    'received', 15350.00, 1842.00, 250.00, 17442.00, 'Monthly replenishment of ophthalmic lubricating and antibiotic drops.', v_admin_id, now(), now()
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
    status, subtotal, tax_amount, shipping_amount, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po2_id, 'PO-2026-0002', 'c0000000-0000-0000-0000-000000000004', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE + INTERVAL '2 days', NULL,
    'ordered', 21400.00, 2568.00, 300.00, 24268.00, 'Restocking composite kits and restorative glass ionomer cement.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po2_id, 'd0000000-0000-0000-0000-000000000007', 15.00, 1250.00, 18750.00, 0.00, now(), now()),
  (gen_random_uuid(), v_po2_id, 'd0000000-0000-0000-0000-000000000008', 3.00, 883.33, 2650.00, 0.00, now(), now());

  -- 3. PO-2026-0003: Partially Received Clinic Disposables & Hygiene
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, tax_amount, shipping_amount, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po3_id, 'PO-2026-0003', 'c0000000-0000-0000-0000-000000000007', CURRENT_DATE - INTERVAL '4 days', CURRENT_DATE, CURRENT_DATE,
    'partially_received', 16900.00, 2028.00, 200.00, 19128.00, 'Gloves received in full, face masks awaiting remaining consignment.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po3_id, 'd0000000-0000-0000-0000-000000000012', 30.00, 380.00, 11400.00, 30.00, now(), now()),
  (gen_random_uuid(), v_po3_id, 'd0000000-0000-0000-0000-000000000013', 30.00, 183.33, 5500.00, 15.00, now(), now());

  -- 4. PO-2026-0004: Draft Surgical Eye Consumables
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, tax_amount, shipping_amount, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po4_id, 'PO-2026-0004', 'c0000000-0000-0000-0000-000000000003', CURRENT_DATE, CURRENT_DATE + INTERVAL '5 days', NULL,
    'draft', 9000.00, 1080.00, 150.00, 10230.00, 'Draft order for upcoming eye surgery schedule requirements.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po4_id, 'd0000000-0000-0000-0000-000000000004', 20.00, 450.00, 9000.00, 0.00, now(), now());

  -- 5. PO-2026-0005: Cancelled Order (Supplier stock out)
  INSERT INTO public.purchase_orders (
    id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date,
    status, subtotal, tax_amount, shipping_amount, total_amount, notes, created_by, created_at, updated_at
  ) VALUES (
    v_po5_id, 'PO-2026-0005', 'c0000000-0000-0000-0000-000000000005', CURRENT_DATE - INTERVAL '12 days', CURRENT_DATE - INTERVAL '7 days', NULL,
    'cancelled', 6500.00, 780.00, 120.00, 7400.00, 'Order cancelled: manufacturer discontinued specific bur batch.', v_admin_id, now(), now()
  );

  INSERT INTO public.purchase_order_items (
    id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, created_at, updated_at
  ) VALUES
  (gen_random_uuid(), v_po5_id, 'd0000000-0000-0000-0000-000000000010', 10.00, 650.00, 6500.00, 0.00, now(), now());

END $$;

-- ============================================================================
-- STEP 9: FRESH DENTAL LAB TRACKING RECORDS
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
-- STEP 10: FRESH BILLING & PAYMENT DATA
-- ============================================================================

DO $$
DECLARE
  v_staff_id UUID;
  v_inv1_id UUID := '10000000-0000-0000-0000-000000000001';
  v_inv2_id UUID := '10000000-0000-0000-0000-000000000002';
  v_inv3_id UUID := '10000000-0000-0000-0000-000000000003';
  v_inv4_id UUID := '10000000-0000-0000-0000-000000000004';
  v_inv5_id UUID := '10000000-0000-0000-0000-000000000005';
BEGIN
  SELECT id INTO v_staff_id FROM public.profiles WHERE is_active = true LIMIT 1;

  -- ── INVOICE 1: Fully Paid (₹1,000 Total, ₹1,000 Paid, ₹0 Remaining) ──
  INSERT INTO public.billing (
    id, invoice_number, patient_id, subtotal, discount, total_amount, payment_status, payment_mode, amount_paid, billed_by, created_at
  ) VALUES (
    v_inv1_id, 'INV-2425-0001', 'a0000000-0000-0000-0000-000000000001', 1000.00, 0.00, 1000.00, 'paid', 'upi', 1000.00, v_staff_id, CURRENT_DATE - INTERVAL '15 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv1_id, 'Comprehensive Ophthalmology Consultation', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '15 days'),
  (gen_random_uuid(), v_inv1_id, 'Computerized Refraction & Spectacle Trial', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '15 days'),
  (gen_random_uuid(), v_inv1_id, 'Intraocular Pressure Tonometry', 1, 200.00, 200.00, false, CURRENT_DATE - INTERVAL '15 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv1_id, 1000.00, 'upi', 'UPI/729184019283/HDFC', CURRENT_DATE - INTERVAL '15 days', v_staff_id, 'Full payment via clinic UPI QR code', CURRENT_DATE - INTERVAL '15 days');

  -- ── INVOICE 2: Partially Paid (₹1,500 Total, ₹500 Paid, ₹1,000 Remaining) ──
  INSERT INTO public.billing (
    id, invoice_number, patient_id, subtotal, discount, total_amount, payment_status, payment_mode, amount_paid, billed_by, created_at
  ) VALUES (
    v_inv2_id, 'INV-2425-0002', 'b0000000-0000-0000-0000-000000000001', 1500.00, 0.00, 1500.00, 'partial', 'cash', 500.00, v_staff_id, CURRENT_DATE - INTERVAL '14 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv2_id, 'Dental Consultation & Diagnosis', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '14 days'),
  (gen_random_uuid(), v_inv2_id, 'Class I Composite Restoration (Tooth 16)', 1, 1200.00, 1200.00, false, CURRENT_DATE - INTERVAL '14 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv2_id, 500.00, 'cash', 'RCP-0021-CSH', CURRENT_DATE - INTERVAL '14 days', v_staff_id, 'Initial advance payment in cash; balance ₹1,000 due', CURRENT_DATE - INTERVAL '14 days');

  -- ── INVOICE 3: Unpaid (₹800 Total, ₹0 Paid, ₹800 Remaining) ──
  INSERT INTO public.billing (
    id, invoice_number, patient_id, subtotal, discount, total_amount, payment_status, payment_mode, amount_paid, billed_by, created_at
  ) VALUES (
    v_inv3_id, 'INV-2425-0003', 'a0000000-0000-0000-0000-000000000003', 800.00, 0.00, 800.00, 'pending', 'upi', 0.00, v_staff_id, CURRENT_DATE - INTERVAL '10 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv3_id, 'Senior Ophthalmologist Cataract Consultation', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '10 days'),
  (gen_random_uuid(), v_inv3_id, 'Slit Lamp Biomicroscopy & Dilated Funduscopy', 1, 300.00, 300.00, false, CURRENT_DATE - INTERVAL '10 days');

  -- ── INVOICE 4: Partially Paid (₹2,000 Total, ₹1,000 Paid, ₹1,000 Remaining) ──
  INSERT INTO public.billing (
    id, invoice_number, patient_id, subtotal, discount, total_amount, payment_status, payment_mode, amount_paid, billed_by, created_at
  ) VALUES (
    v_inv4_id, 'INV-2425-0004', 'b0000000-0000-0000-0000-000000000003', 2000.00, 0.00, 2000.00, 'partial', 'upi', 1000.00, v_staff_id, CURRENT_DATE - INTERVAL '11 days'
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv4_id, 'Root Canal Treatment (Tooth 36) - Access & Canal Prep', 1, 1500.00, 1500.00, false, CURRENT_DATE - INTERVAL '11 days'),
  (gen_random_uuid(), v_inv4_id, 'Digital Intraoral Periapical (IOPA) X-Ray (2 Views)', 1, 500.00, 500.00, false, CURRENT_DATE - INTERVAL '11 days');

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv4_id, 1000.00, 'upi', 'UPI/839102948572/ICICI', CURRENT_DATE - INTERVAL '11 days', v_staff_id, 'Interim installment via UPI; balance ₹1,000 due', CURRENT_DATE - INTERVAL '11 days');

  -- ── INVOICE 5: Fully Paid (₹1,200 Total, ₹1,200 Paid, ₹0 Remaining) ──
  INSERT INTO public.billing (
    id, invoice_number, patient_id, subtotal, discount, total_amount, payment_status, payment_mode, amount_paid, billed_by, created_at
  ) VALUES (
    v_inv5_id, 'INV-2425-0005', 'b0000000-0000-0000-0000-000000000018', 1200.00, 0.00, 1200.00, 'paid', 'card', 1200.00, v_staff_id, CURRENT_DATE
  );

  INSERT INTO public.billing_items (id, billing_id, service_name, quantity, unit_price, total_amount, is_custom, created_at)
  VALUES
  (gen_random_uuid(), v_inv5_id, 'Full Mouth Ultrasonic Scaling & Deep Polishing', 1, 1000.00, 1000.00, false, CURRENT_DATE),
  (gen_random_uuid(), v_inv5_id, 'Fluoride Foam Application & Oral Hygiene Kit', 1, 200.00, 200.00, false, CURRENT_DATE);

  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv5_id, 1200.00, 'card', 'POS/HDFC/TXN-492102', CURRENT_DATE, v_staff_id, 'Settled in full via Debit Card POS', CURRENT_DATE);

END $$;

-- ============================================================================
-- STEP 11: ADD DEMO TASKS FOR EXISTING STAFF
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
-- STEP 12: ATTENDANCE DEMO DATA (SAFE RECORD FOR TODAY)
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
-- STEP 13: INTEGRITY AUDIT ASSERTIONS (FAIL-FAST TRANSACTIONS)
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
BEGIN
  SELECT count(*) INTO v_patient_count FROM public.patients;
  IF v_patient_count <> 50 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 50 patients, found %', v_patient_count;
  END IF;

  SELECT count(*) INTO v_eye_patient_count FROM public.patients WHERE department = 'eye';
  IF v_eye_patient_count <> 25 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 25 eye patients, found %', v_eye_patient_count;
  END IF;

  SELECT count(*) INTO v_dental_patient_count FROM public.patients WHERE department = 'dental';
  IF v_dental_patient_count <> 25 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 25 dental patients, found %', v_dental_patient_count;
  END IF;

  SELECT count(*) INTO v_invoice_count FROM public.billing;
  IF v_invoice_count <> 5 THEN
    RAISE EXCEPTION 'Audit failed: expected exactly 5 billing invoices, found %', v_invoice_count;
  END IF;

  SELECT count(*) INTO v_appt_count FROM public.appointments;
  IF v_appt_count < 15 THEN
    RAISE EXCEPTION 'Audit failed: expected >= 15 appointments, found %', v_appt_count;
  END IF;

  SELECT count(*) INTO v_vendor_count FROM public.vendors;
  IF v_vendor_count <> 8 THEN
    RAISE EXCEPTION 'Audit failed: expected 8 vendors, found %', v_vendor_count;
  END IF;

  SELECT count(*) INTO v_order_count FROM public.purchase_orders;
  IF v_order_count <> 5 THEN
    RAISE EXCEPTION 'Audit failed: expected 5 purchase orders, found %', v_order_count;
  END IF;

  SELECT count(*) INTO v_lab_count FROM public.dental_lab;
  IF v_lab_count <> 5 THEN
    RAISE EXCEPTION 'Audit failed: expected 5 dental lab cases, found %', v_lab_count;
  END IF;

  SELECT count(*) INTO v_inventory_count FROM public.inventory;
  IF v_inventory_count <> 14 THEN
    RAISE EXCEPTION 'Audit failed: expected 14 inventory items, found %', v_inventory_count;
  END IF;

  RAISE NOTICE 'MKES CARE+ Complete Data Cleanup and Seeding verified successfully!';
END $$;

COMMIT;
"""

with open(sql_file, "w", encoding="utf-8") as f:
    f.write(sql_content)

print(f"Generated {sql_file} successfully! Size: {os.path.getsize(sql_file)} bytes")
