-- MKES CARE+ — Migration: Excel Synchronization Foundation (Sprint 9.2)
-- File: supabase/migrations/20261013000000_excel_sync_foundation.sql
--
-- Creates the metadata tracking infrastructure for central Excel synchronization:
-- 1. Table: public.excel_sync_state (audit log of synchronization runs)
-- 2. Table: public.excel_sync_checkpoints (per-worksheet high-water mark tracking)
-- 3. Storage bucket initialization: clinic-excel-sync
-- 4. Row-Level Security policies restricting access strictly to active administrators.

-- 1. Create table public.excel_sync_state
CREATE TABLE IF NOT EXISTS public.excel_sync_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sync_type TEXT NOT NULL DEFAULT 'scheduled',
  status TEXT NOT NULL DEFAULT 'pending',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  records_upserted INTEGER NOT NULL DEFAULT 0,
  file_size_bytes BIGINT NOT NULL DEFAULT 0,
  storage_path TEXT NOT NULL DEFAULT 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
  worksheets_synced TEXT[] NOT NULL DEFAULT '{}',
  error_message TEXT,
  triggered_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT excel_sync_type_check CHECK (sync_type IN ('initial', 'scheduled', 'manual')),
  CONSTRAINT excel_sync_status_check CHECK (status IN ('pending', 'in_progress', 'success', 'failed'))
);

-- Index for fast status/last run lookups
CREATE INDEX IF NOT EXISTS idx_excel_sync_state_created_at
  ON public.excel_sync_state (created_at DESC);

-- 2. Create table public.excel_sync_checkpoints
CREATE TABLE IF NOT EXISTS public.excel_sync_checkpoints (
  worksheet_name TEXT PRIMARY KEY,
  source_table TEXT NOT NULL,
  last_sync_timestamp TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  record_count INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed all 21 normalized worksheets with initial checkpoints
INSERT INTO public.excel_sync_checkpoints (worksheet_name, source_table, last_sync_timestamp, record_count)
VALUES
  ('Patients', 'patients', '1970-01-01 00:00:00+00', 0),
  ('Staff_Directory', 'profiles', '1970-01-01 00:00:00+00', 0),
  ('Staff_Attendance', 'staff_attendance', '1970-01-01 00:00:00+00', 0),
  ('Leave_Requests', 'leave_requests', '1970-01-01 00:00:00+00', 0),
  ('Tasks', 'tasks', '1970-01-01 00:00:00+00', 0),
  ('Task_History', 'task_history', '1970-01-01 00:00:00+00', 0),
  ('Appointments', 'appointments', '1970-01-01 00:00:00+00', 0),
  ('Inventory_Catalog', 'inventory', '1970-01-01 00:00:00+00', 0),
  ('Inventory_Batches', 'inventory_batches', '1970-01-01 00:00:00+00', 0),
  ('Stock_Transactions', 'inventory_transactions', '1970-01-01 00:00:00+00', 0),
  ('Department_Stock', 'department_inventory', '1970-01-01 00:00:00+00', 0),
  ('Stock_Requests', 'stock_requests', '1970-01-01 00:00:00+00', 0),
  ('Vendors', 'vendors', '1970-01-01 00:00:00+00', 0),
  ('Purchase_Orders', 'purchase_orders', '1970-01-01 00:00:00+00', 0),
  ('Purchase_Order_Items', 'purchase_order_items', '1970-01-01 00:00:00+00', 0),
  ('Optical_Sales', 'sales', '1970-01-01 00:00:00+00', 0),
  ('Optical_Orders', 'optical_orders', '1970-01-01 00:00:00+00', 0),
  ('Dental_Lab_Cases', 'dental_lab', '1970-01-01 00:00:00+00', 0),
  ('Billing_Invoices', 'billing', '1970-01-01 00:00:00+00', 0),
  ('Billing_Line_Items', 'billing_items', '1970-01-01 00:00:00+00', 0),
  ('Billing_Payments', 'billing_payments', '1970-01-01 00:00:00+00', 0)
ON CONFLICT (worksheet_name) DO NOTHING;

-- 3. Enable Row-Level Security
ALTER TABLE public.excel_sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.excel_sync_checkpoints ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies: Admin-Only Full Management, Staff View Denied
DROP POLICY IF EXISTS "Admins can manage excel sync state" ON public.excel_sync_state;
CREATE POLICY "Admins can manage excel sync state"
  ON public.excel_sync_state
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

DROP POLICY IF EXISTS "Admins can manage excel sync checkpoints" ON public.excel_sync_checkpoints;
CREATE POLICY "Admins can manage excel sync checkpoints"
  ON public.excel_sync_checkpoints
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND is_active = true
    )
  );

-- Service role bypass for Edge Functions
GRANT ALL ON TABLE public.excel_sync_state TO service_role;
GRANT ALL ON TABLE public.excel_sync_checkpoints TO service_role;

-- 5. Initialize private storage bucket for clinic-excel-sync if storage schema is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES (
      'clinic-excel-sync',
      'clinic-excel-sync',
      false,
      52428800, -- 50 MB
      ARRAY['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/octet-stream']
    )
    ON CONFLICT (id) DO UPDATE
      SET public = false,
          file_size_limit = 52428800;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage bucket initialization skipped or handled by dashboard: %', SQLERRM;
END $$;

-- 6. Storage RLS Policy for clinic-excel-sync bucket
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
    DROP POLICY IF EXISTS "Admins can manage clinic excel sync files" ON storage.objects;
    CREATE POLICY "Admins can manage clinic excel sync files"
      ON storage.objects
      FOR ALL
      TO authenticated
      USING (
        bucket_id = 'clinic-excel-sync'
        AND EXISTS (
          SELECT 1 FROM public.profiles
          WHERE id = auth.uid() AND role = 'admin' AND is_active = true
        )
      )
      WITH CHECK (
        bucket_id = 'clinic-excel-sync'
        AND EXISTS (
          SELECT 1 FROM public.profiles
          WHERE id = auth.uid() AND role = 'admin' AND is_active = true
        )
      );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage RLS configuration handled by dashboard or permissions: %', SQLERRM;
END $$;
