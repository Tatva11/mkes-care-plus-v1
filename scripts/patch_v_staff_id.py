with open('scripts/generate_final_reset_and_seed.py', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Step 2: Drop stray v_staff_id and Affirm ENABLE ROW LEVEL SECURITY instead of disabling it
old_step_2_rls = """-- Explicitly disable RLS on tables being cleared so no records are hidden from DELETE
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
END $$;"""

new_step_2_rls = """-- Safety Cleanup: Ensure no accidental table or view named v_staff_id exists
DROP VIEW IF EXISTS public.v_staff_id CASCADE;
DROP TABLE IF EXISTS public.v_staff_id CASCADE;

-- Affirm Row Level Security is strictly ENABLED on all operational tables
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
    'patients',
    'profiles',
    'staff_attendance'
  ];
BEGIN
  FOREACH t IN ARRAY rls_tables LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE 'ALTER TABLE public.' || quote_ident(t) || ' ENABLE ROW LEVEL SECURITY;';
    END IF;
  END LOOP;
END $$;"""

assert old_step_2_rls in text, "old_step_2_rls not found in text!"
text = text.replace(old_step_2_rls, new_step_2_rls)

# 2. Fix Step 10 DO $$ and END $$;
old_step_10_head = """-- STEP 10: FRESH BILLING & PAYMENT DATA
-- ============================================================================

DO 
DECLARE
  v_staff_id UUID;"""

new_step_10_head = """-- STEP 10: FRESH BILLING & PAYMENT DATA
-- ============================================================================

DO $$
DECLARE
  -- Ephemeral in-memory PL/pgSQL local variable (not a table)
  v_staff_id UUID;"""

assert old_step_10_head in text, "old_step_10_head not found in text!"
text = text.replace(old_step_10_head, new_step_10_head)

old_step_10_tail = """  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv5_id, 1200.00, 'other', 'POS/HDFC/TXN-492102', CURRENT_DATE, v_staff_id, 'Settled in full via Debit Card POS', CURRENT_DATE);

END ;"""

new_step_10_tail = """  INSERT INTO public.billing_payments (id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at)
  VALUES (gen_random_uuid(), v_inv5_id, 1200.00, 'other', 'POS/HDFC/TXN-492102', CURRENT_DATE, v_staff_id, 'Settled in full via Debit Card POS', CURRENT_DATE);

END $$;"""

assert old_step_10_tail in text, "old_step_10_tail not found in text!"
text = text.replace(old_step_10_tail, new_step_10_tail)

with open('scripts/generate_final_reset_and_seed.py', 'w', encoding='utf-8') as f:
    f.write(text)

print("Patched scripts/generate_final_reset_and_seed.py successfully!")

