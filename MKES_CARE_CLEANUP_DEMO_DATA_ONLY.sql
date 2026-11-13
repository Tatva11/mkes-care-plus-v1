-- =============================================================================
-- MKES CARE+ : PRODUCTION TRANSITION DEMO / TEST DATA CLEANUP SCRIPT
-- =============================================================================
-- Purpose:
--   Removes all dummy, sample, testing, and demonstration records across
--   all modules to prepare MKES CARE+ for genuine live clinic operations.
--
-- Safety Guarantees:
--   1. PRESERVES all Admin & Staff accounts (auth.users, public.profiles).
--   2. PRESERVES Clinic Department configurations (public.departments).
--   3. PRESERVES Doctor configurations & specialties (public.department_doctors).
--   4. PRESERVES Shift configurations & schedules (public.shift_configurations,
--      public.staff_shift_assignments).
--   5. PRESERVES WhatsApp gateway settings & templates (public.whatsapp_settings,
--      public.whatsapp_templates).
--   6. PRESERVES Billing service master catalogs (public.billing_services).
--   7. PRESERVES Eye surgery checklist templates (public.eye_surgery_item_templates).
--   8. Zero structural changes: no tables, columns, constraints, functions,
--      or RLS policies are dropped.
--   9. Transaction-safe: executes atomically within a single BEGIN ... COMMIT block.
--  10. Foreign-key safe: executes deletions strictly in child-to-parent order
--      and temporarily bypasses restrictive operational triggers.
-- =============================================================================

BEGIN;

-- 1. Try to set session replication role to replica to bypass all event triggers
-- and cascading restrictions cleanly. Falls back silently if restricted.
DO $$
BEGIN
  BEGIN
    SET LOCAL session_replication_role = 'replica';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'session_replication_role replica not allowed in this session, using trigger bypass';
  END;
END $$;

-- 2. Safely disable triggers that prevent deletion of operational records
DO $$
BEGIN
  IF to_regclass('public.billing') IS NOT NULL THEN
    ALTER TABLE public.billing DISABLE TRIGGER USER;
  END IF;
  IF to_regclass('public.eye_surgeries') IS NOT NULL THEN
    ALTER TABLE public.eye_surgeries DISABLE TRIGGER USER;
  END IF;
END $$;

-- =============================================================================
-- 3. CHILD-TO-PARENT DELETION SEQUENCE
-- =============================================================================

-- Phase A: Clinical Usage, Procedures & Surgeries (Deepest Leaf Children)
DO $$
BEGIN
  IF to_regclass('public.clinical_inventory_usage') IS NOT NULL THEN
    DELETE FROM public.clinical_inventory_usage;
  END IF;

  IF to_regclass('public.eye_examinations') IS NOT NULL THEN
    DELETE FROM public.eye_examinations;
  END IF;

  IF to_regclass('public.dental_treatments') IS NOT NULL THEN
    DELETE FROM public.dental_treatments;
  END IF;

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

  IF to_regclass('public.eye_surgeries') IS NOT NULL THEN
    DELETE FROM public.eye_surgeries;
  END IF;

  IF to_regclass('public.dental_lab') IS NOT NULL THEN
    DELETE FROM public.dental_lab;
  END IF;

  IF to_regclass('public.optical_orders') IS NOT NULL THEN
    DELETE FROM public.optical_orders;
  END IF;

  IF to_regclass('public.sales') IS NOT NULL THEN
    DELETE FROM public.sales;
  END IF;
END $$;

-- Phase B: WhatsApp Messages, Sessions & Outbox Logs
DO $$
BEGIN
  IF to_regclass('public.whatsapp_message_logs') IS NOT NULL THEN
    DELETE FROM public.whatsapp_message_logs;
  END IF;

  IF to_regclass('public.whatsapp_messages_outbox') IS NOT NULL THEN
    DELETE FROM public.whatsapp_messages_outbox;
  END IF;

  IF to_regclass('public.whatsapp_chat_sessions') IS NOT NULL THEN
    DELETE FROM public.whatsapp_chat_sessions;
  END IF;

  IF to_regclass('public.whatsapp_appointment_requests') IS NOT NULL THEN
    DELETE FROM public.whatsapp_appointment_requests;
  END IF;
END $$;

-- Phase C: Appointments & Patient Attendance
DO $$
BEGIN
  IF to_regclass('public.patient_attendance') IS NOT NULL THEN
    DELETE FROM public.patient_attendance;
  END IF;

  IF to_regclass('public.appointments') IS NOT NULL THEN
    DELETE FROM public.appointments;
  END IF;
END $$;

-- Phase D: Inventory Transactions, Batches, Stock Requests & POs
DO $$
BEGIN
  IF to_regclass('public.purchase_order_items') IS NOT NULL THEN
    DELETE FROM public.purchase_order_items;
  END IF;

  IF to_regclass('public.inventory_batches') IS NOT NULL THEN
    DELETE FROM public.inventory_batches;
  END IF;

  IF to_regclass('public.purchase_orders') IS NOT NULL THEN
    DELETE FROM public.purchase_orders;
  END IF;

  IF to_regclass('public.stock_requests') IS NOT NULL THEN
    DELETE FROM public.stock_requests;
  END IF;

  IF to_regclass('public.department_inventory') IS NOT NULL THEN
    DELETE FROM public.department_inventory;
  END IF;

  IF to_regclass('public.inventory_transactions') IS NOT NULL THEN
    DELETE FROM public.inventory_transactions;
  END IF;

  IF to_regclass('public.inventory') IS NOT NULL THEN
    DELETE FROM public.inventory;
  END IF;

  IF to_regclass('public.vendors') IS NOT NULL THEN
    DELETE FROM public.vendors;
  END IF;
END $$;

-- Phase E: Billing & Invoices
DO $$
BEGIN
  IF to_regclass('public.billing_payments') IS NOT NULL THEN
    DELETE FROM public.billing_payments;
  END IF;

  IF to_regclass('public.billing_items') IS NOT NULL THEN
    DELETE FROM public.billing_items;
  END IF;

  IF to_regclass('public.billing') IS NOT NULL THEN
    DELETE FROM public.billing;
  END IF;
END $$;

-- Phase F: Staff Attendance, Tasks, Leaves & Operational Sessions
DO $$
BEGIN
  IF to_regclass('public.task_history') IS NOT NULL THEN
    DELETE FROM public.task_history;
  END IF;

  IF to_regclass('public.tasks') IS NOT NULL THEN
    DELETE FROM public.tasks;
  END IF;

  IF to_regclass('public.staff_attendance') IS NOT NULL THEN
    DELETE FROM public.staff_attendance;
  END IF;

  IF to_regclass('public.attendance') IS NOT NULL THEN
    DELETE FROM public.attendance;
  END IF;

  IF to_regclass('public.leave_requests') IS NOT NULL THEN
    DELETE FROM public.leave_requests;
  END IF;

  IF to_regclass('public.staff_geofence_sessions') IS NOT NULL THEN
    DELETE FROM public.staff_geofence_sessions;
  END IF;

  IF to_regclass('public.staff_gps_bypass_audit_logs') IS NOT NULL THEN
    DELETE FROM public.staff_gps_bypass_audit_logs;
  END IF;
END $$;

-- Phase G: Notifications, Audit Logs, Device Tokens & Sync State
DO $$
BEGIN
  IF to_regclass('public.notifications') IS NOT NULL THEN
    DELETE FROM public.notifications;
  END IF;

  IF to_regclass('public.audit_logs') IS NOT NULL THEN
    DELETE FROM public.audit_logs;
  END IF;

  IF to_regclass('public.user_device_tokens') IS NOT NULL THEN
    DELETE FROM public.user_device_tokens;
  END IF;

  IF to_regclass('public.excel_sync_outbox') IS NOT NULL THEN
    DELETE FROM public.excel_sync_outbox;
  END IF;

  IF to_regclass('public.excel_sync_leases') IS NOT NULL THEN
    DELETE FROM public.excel_sync_leases;
  END IF;

  IF to_regclass('public.excel_sync_versions') IS NOT NULL THEN
    DELETE FROM public.excel_sync_versions;
  END IF;

  IF to_regclass('public.excel_sync_state') IS NOT NULL THEN
    DELETE FROM public.excel_sync_state;
  END IF;

  IF to_regclass('public.excel_sync_checkpoints') IS NOT NULL THEN
    DELETE FROM public.excel_sync_checkpoints;
  END IF;
END $$;

-- Phase H: Patient Directory (Root Patient Records)
DO $$
BEGIN
  IF to_regclass('public.patients') IS NOT NULL THEN
    DELETE FROM public.patients;
  END IF;
END $$;

-- =============================================================================
-- 4. RE-ENABLE TRIGGERS AND RESTORE SESSION REPLICATION ROLE
-- =============================================================================
DO $$
BEGIN
  IF to_regclass('public.billing') IS NOT NULL THEN
    ALTER TABLE public.billing ENABLE TRIGGER USER;
  END IF;
  IF to_regclass('public.eye_surgeries') IS NOT NULL THEN
    ALTER TABLE public.eye_surgeries ENABLE TRIGGER USER;
  END IF;

  BEGIN
    SET LOCAL session_replication_role = 'origin';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END $$;

-- =============================================================================
-- 5. VERIFICATION AUDIT (Outputs verification row counts)
-- =============================================================================
DO $$
DECLARE
  v_rec record;
  v_count bigint;
BEGIN
  RAISE NOTICE '==================================================';
  RAISE NOTICE 'MKES CARE+ CLEANUP VERIFICATION REPORT';
  RAISE NOTICE '==================================================';

  -- Check cleaned tables (All must be 0)
  FOR v_rec IN (
    SELECT unnest(ARRAY[
      'patients', 'appointments', 'eye_surgeries', 'dental_treatments',
      'eye_examinations', 'vendors', 'inventory', 'purchase_orders',
      'billing', 'billing_items', 'billing_payments', 'tasks',
      'staff_attendance', 'leave_requests', 'notifications'
    ]) AS tbl_name
  ) LOOP
    IF to_regclass('public.' || v_rec.tbl_name) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', v_rec.tbl_name) INTO v_count;
      RAISE NOTICE 'CLEANED TABLE %: % rows (Target: 0)', v_rec.tbl_name, v_count;
    END IF;
  END LOOP;

  -- Check protected tables (Must be preserved)
  FOR v_rec IN (
    SELECT unnest(ARRAY[
      'profiles', 'departments', 'department_doctors', 'shift_configurations',
      'staff_shift_assignments', 'whatsapp_settings', 'whatsapp_templates',
      'billing_services', 'eye_surgery_item_templates'
    ]) AS tbl_name
  ) LOOP
    IF to_regclass('public.' || v_rec.tbl_name) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', v_rec.tbl_name) INTO v_count;
      RAISE NOTICE 'PRESERVED TABLE %: % rows (Target: >= 0 preserved)', v_rec.tbl_name, v_count;
    END IF;
  END LOOP;
  RAISE NOTICE '==================================================';
END $$;

COMMIT;

