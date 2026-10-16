-- MKES CARE+ — Migration: Excel Incremental Synchronization, Outbox & Leases (Sprint 9.4)
-- File: supabase/migrations/20261014000000_excel_sync_incremental_outbox_leases.sql
--
-- Implements robust, transaction-safe incremental synchronization infrastructure:
-- 1. Table: public.excel_sync_outbox (Transactional change-capture for all 21 sheets + joins)
-- 2. Triggers on all 21 source tables + departments to capture I/U/D and hard deletions
-- 3. Table: public.excel_sync_leases (Distributed lease with monotonically increasing fencing tokens)
-- 4. Table: public.excel_sync_versions (Immutable workbook version catalog with single-active pointer)
-- 5. Foreign-key enhancement on public.excel_sync_checkpoints(last_sync_id)
-- 6. Atomic RPCs: claim_events, acquire_lease, renew_lease, release_lease, publish_version

-- ============================================================================
-- 0. PREREQUISITE BASELINE STRUCTURES (IF NOT ALREADY CREATED)
-- ============================================================================

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

CREATE INDEX IF NOT EXISTS idx_excel_sync_state_created_at
  ON public.excel_sync_state (created_at DESC);

CREATE TABLE IF NOT EXISTS public.excel_sync_checkpoints (
  worksheet_name TEXT PRIMARY KEY,
  source_table TEXT NOT NULL,
  last_sync_timestamp TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  record_count INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed initial 21 worksheet checkpoints if missing
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

ALTER TABLE public.excel_sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.excel_sync_checkpoints ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'excel_sync_state' 
      AND policyname = 'Admins can manage excel sync state'
  ) THEN
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
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'excel_sync_checkpoints' 
      AND policyname = 'Admins can manage excel sync checkpoints'
  ) THEN
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
  END IF;
END $$;

GRANT ALL ON TABLE public.excel_sync_state TO service_role;
GRANT ALL ON TABLE public.excel_sync_checkpoints TO service_role;

-- ============================================================================
-- 1. TRANSACTIONAL CHANGE-CAPTURE OUTBOX
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.excel_sync_outbox (
  id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'processed')),
  claim_id UUID REFERENCES public.excel_sync_state(id) ON DELETE SET NULL,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_excel_sync_outbox_status_id
  ON public.excel_sync_outbox (status, id ASC);

CREATE INDEX IF NOT EXISTS idx_excel_sync_outbox_claim_id
  ON public.excel_sync_outbox (claim_id)
  WHERE claim_id IS NOT NULL;

-- Generic outbox logging trigger function (never stores sensitive payloads or salary)
CREATE OR REPLACE FUNCTION public.log_excel_sync_mutation()
RETURNS TRIGGER AS $$
DECLARE
  v_rec_id TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_rec_id := OLD.id::text;
    INSERT INTO public.excel_sync_outbox (table_name, record_id, operation)
    VALUES (TG_TABLE_NAME, v_rec_id, 'DELETE');
    RETURN OLD;
  ELSE
    v_rec_id := NEW.id::text;
    INSERT INTO public.excel_sync_outbox (table_name, record_id, operation)
    VALUES (TG_TABLE_NAME, v_rec_id, TG_OP);
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 2. ATTACH OUTBOX TRIGGERS TO ALL 21 SOURCE TABLES & PARENT LOOKUPS
-- ============================================================================

-- 1. Patients
DROP TRIGGER IF EXISTS trg_outbox_patients ON public.patients;
CREATE TRIGGER trg_outbox_patients
AFTER INSERT OR UPDATE OR DELETE ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 2. Staff Profiles & Parent Departments
DROP TRIGGER IF EXISTS trg_outbox_profiles ON public.profiles;
CREATE TRIGGER trg_outbox_profiles
AFTER INSERT OR UPDATE OR DELETE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

DROP TRIGGER IF EXISTS trg_outbox_departments ON public.departments;
CREATE TRIGGER trg_outbox_departments
AFTER INSERT OR UPDATE OR DELETE ON public.departments
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 3. Staff Attendance
DROP TRIGGER IF EXISTS trg_outbox_staff_attendance ON public.staff_attendance;
CREATE TRIGGER trg_outbox_staff_attendance
AFTER INSERT OR UPDATE OR DELETE ON public.staff_attendance
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 4. Leave Requests
DROP TRIGGER IF EXISTS trg_outbox_leave_requests ON public.leave_requests;
CREATE TRIGGER trg_outbox_leave_requests
AFTER INSERT OR UPDATE OR DELETE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 5. Tasks
DROP TRIGGER IF EXISTS trg_outbox_tasks ON public.tasks;
CREATE TRIGGER trg_outbox_tasks
AFTER INSERT OR UPDATE OR DELETE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 6. Task History (append-only)
DROP TRIGGER IF EXISTS trg_outbox_task_history ON public.task_history;
CREATE TRIGGER trg_outbox_task_history
AFTER INSERT ON public.task_history
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 7. Appointments
DROP TRIGGER IF EXISTS trg_outbox_appointments ON public.appointments;
CREATE TRIGGER trg_outbox_appointments
AFTER INSERT OR UPDATE OR DELETE ON public.appointments
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 8. Inventory Catalog
DROP TRIGGER IF EXISTS trg_outbox_inventory ON public.inventory;
CREATE TRIGGER trg_outbox_inventory
AFTER INSERT OR UPDATE OR DELETE ON public.inventory
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 9. Inventory Batches
DROP TRIGGER IF EXISTS trg_outbox_inventory_batches ON public.inventory_batches;
CREATE TRIGGER trg_outbox_inventory_batches
AFTER INSERT OR UPDATE OR DELETE ON public.inventory_batches
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 10. Stock Transactions (append-only)
DROP TRIGGER IF EXISTS trg_outbox_inventory_transactions ON public.inventory_transactions;
CREATE TRIGGER trg_outbox_inventory_transactions
AFTER INSERT ON public.inventory_transactions
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 11. Department Stock
DROP TRIGGER IF EXISTS trg_outbox_department_inventory ON public.department_inventory;
CREATE TRIGGER trg_outbox_department_inventory
AFTER INSERT OR UPDATE OR DELETE ON public.department_inventory
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 12. Stock Requests
DROP TRIGGER IF EXISTS trg_outbox_stock_requests ON public.stock_requests;
CREATE TRIGGER trg_outbox_stock_requests
AFTER INSERT OR UPDATE OR DELETE ON public.stock_requests
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 13. Vendors
DROP TRIGGER IF EXISTS trg_outbox_vendors ON public.vendors;
CREATE TRIGGER trg_outbox_vendors
AFTER INSERT OR UPDATE OR DELETE ON public.vendors
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 14. Purchase Orders
DROP TRIGGER IF EXISTS trg_outbox_purchase_orders ON public.purchase_orders;
CREATE TRIGGER trg_outbox_purchase_orders
AFTER INSERT OR UPDATE OR DELETE ON public.purchase_orders
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 15. Purchase Order Items
DROP TRIGGER IF EXISTS trg_outbox_purchase_order_items ON public.purchase_order_items;
CREATE TRIGGER trg_outbox_purchase_order_items
AFTER INSERT OR UPDATE OR DELETE ON public.purchase_order_items
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 16. Optical Sales
DROP TRIGGER IF EXISTS trg_outbox_sales ON public.sales;
CREATE TRIGGER trg_outbox_sales
AFTER INSERT OR UPDATE OR DELETE ON public.sales
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 17. Optical Orders
DROP TRIGGER IF EXISTS trg_outbox_optical_orders ON public.optical_orders;
CREATE TRIGGER trg_outbox_optical_orders
AFTER INSERT OR UPDATE OR DELETE ON public.optical_orders
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 18. Dental Lab Cases
DROP TRIGGER IF EXISTS trg_outbox_dental_lab ON public.dental_lab;
CREATE TRIGGER trg_outbox_dental_lab
AFTER INSERT OR UPDATE OR DELETE ON public.dental_lab
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 19. Billing Invoices
DROP TRIGGER IF EXISTS trg_outbox_billing ON public.billing;
CREATE TRIGGER trg_outbox_billing
AFTER INSERT OR UPDATE OR DELETE ON public.billing
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 20. Billing Line Items
DROP TRIGGER IF EXISTS trg_outbox_billing_items ON public.billing_items;
CREATE TRIGGER trg_outbox_billing_items
AFTER INSERT OR UPDATE OR DELETE ON public.billing_items
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- 21. Billing Payments
DROP TRIGGER IF EXISTS trg_outbox_billing_payments ON public.billing_payments;
CREATE TRIGGER trg_outbox_billing_payments
AFTER INSERT OR UPDATE OR DELETE ON public.billing_payments
FOR EACH ROW EXECUTE FUNCTION public.log_excel_sync_mutation();

-- ============================================================================
-- 3. DISTRIBUTED LEASES (CONCURRENCY CONTROL & FENCING GENERATIONS)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.excel_sync_leases (
  lease_key TEXT PRIMARY KEY DEFAULT 'master_sync',
  holder_id UUID NOT NULL,
  fencing_token BIGINT NOT NULL DEFAULT 1,
  acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'expired'))
);

-- Seed master lease row if missing
INSERT INTO public.excel_sync_leases (lease_key, holder_id, fencing_token, acquired_at, expires_at, status)
VALUES ('master_sync', '00000000-0000-0000-0000-000000000000'::uuid, 0, '1970-01-01 00:00:00+00', '1970-01-01 00:00:00+00', 'released')
ON CONFLICT (lease_key) DO NOTHING;

-- ============================================================================
-- 4. IMMUTABLE WORKBOOK VERSION CATALOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.excel_sync_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sync_id UUID REFERENCES public.excel_sync_state(id) ON DELETE CASCADE,
  fencing_token BIGINT NOT NULL,
  version_number BIGSERIAL,
  storage_path TEXT NOT NULL,
  file_size_bytes BIGINT NOT NULL,
  total_records INT NOT NULL,
  worksheets_summary JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT false,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enforce exactly one active version pointer in the database
CREATE UNIQUE INDEX IF NOT EXISTS idx_excel_sync_versions_single_active
  ON public.excel_sync_versions (is_active)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_excel_sync_versions_created_at
  ON public.excel_sync_versions (created_at DESC);

-- Extend excel_sync_checkpoints to record last_sync_id link
ALTER TABLE public.excel_sync_checkpoints
  ADD COLUMN IF NOT EXISTS last_sync_id UUID REFERENCES public.excel_sync_state(id) ON DELETE SET NULL;

-- ============================================================================
-- 5. TRANSACTIONAL RPCS (LEASES, CLAIMS & PUBLICATION)
-- ============================================================================

-- RPC: Claim Outbox Events (Transaction-Safe, skips locked rows, reclaims abandoned claims)
CREATE OR REPLACE FUNCTION public.claim_excel_sync_outbox_events(
  p_sync_id UUID,
  p_limit INT DEFAULT 1000
)
RETURNS TABLE (
  claimed_count INT,
  distinct_tables TEXT[],
  oldest_created_at TIMESTAMPTZ,
  newest_created_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claimed_ids BIGINT[];
BEGIN
  -- Reclaim stale abandoned claims (crashed worker > 10 mins ago) or unconsumed pending
  WITH candidates AS (
    SELECT id
    FROM public.excel_sync_outbox
    WHERE status = 'pending'
       OR (status = 'claimed' AND claimed_at < now() - INTERVAL '10 minutes')
    ORDER BY id ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  SELECT array_agg(id) INTO v_claimed_ids FROM candidates;

  IF v_claimed_ids IS NULL OR array_length(v_claimed_ids, 1) = 0 THEN
    RETURN QUERY SELECT 0, ARRAY[]::TEXT[], NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ;
    RETURN;
  END IF;

  UPDATE public.excel_sync_outbox
  SET status = 'claimed',
      claim_id = p_sync_id,
      claimed_at = now()
  WHERE id = ANY(v_claimed_ids);

  RETURN QUERY
  SELECT
    array_length(v_claimed_ids, 1)::INT,
    array_agg(DISTINCT table_name),
    min(created_at),
    max(created_at)
  FROM public.excel_sync_outbox
  WHERE id = ANY(v_claimed_ids);
END;
$$;

-- RPC: Atomic Lease Acquisition
CREATE OR REPLACE FUNCTION public.acquire_excel_sync_lease(
  p_holder_id UUID,
  p_ttl_seconds INT DEFAULT 300
)
RETURNS TABLE (
  acquired BOOLEAN,
  fencing_token BIGINT,
  current_holder UUID,
  expires_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lease public.excel_sync_leases%ROWTYPE;
BEGIN
  SELECT * INTO v_lease
  FROM public.excel_sync_leases
  WHERE lease_key = 'master_sync'
  FOR UPDATE;

  -- If lease is released or expired, allow immediate acquisition with incremented fencing token
  IF v_lease.status = 'released' OR v_lease.expires_at < now() THEN
    UPDATE public.excel_sync_leases
    SET holder_id = p_holder_id,
        fencing_token = v_lease.fencing_token + 1,
        acquired_at = now(),
        expires_at = now() + (p_ttl_seconds || ' seconds')::INTERVAL,
        status = 'active'
    WHERE lease_key = 'master_sync'
    RETURNING true, excel_sync_leases.fencing_token, p_holder_id, excel_sync_leases.expires_at
    INTO acquired, fencing_token, current_holder, expires_at;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Lease is actively held by an unexpired worker
  RETURN QUERY SELECT false, v_lease.fencing_token, v_lease.holder_id, v_lease.expires_at;
END;
$$;

-- RPC: Atomic Lease Renewal
CREATE OR REPLACE FUNCTION public.renew_excel_sync_lease(
  p_holder_id UUID,
  p_fencing_token BIGINT,
  p_extension_seconds INT DEFAULT 180
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated INT;
BEGIN
  UPDATE public.excel_sync_leases
  SET expires_at = now() + (p_extension_seconds || ' seconds')::INTERVAL
  WHERE lease_key = 'master_sync'
    AND holder_id = p_holder_id
    AND fencing_token = p_fencing_token
    AND status = 'active'
    AND expires_at >= now();

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

-- RPC: Atomic Lease Release
CREATE OR REPLACE FUNCTION public.release_excel_sync_lease(
  p_holder_id UUID,
  p_fencing_token BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated INT;
BEGIN
  UPDATE public.excel_sync_leases
  SET status = 'released'
  WHERE lease_key = 'master_sync'
    AND holder_id = p_holder_id
    AND fencing_token = p_fencing_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

-- RPC: Atomic Version Publication & Checkpoint Commitment
CREATE OR REPLACE FUNCTION public.publish_excel_sync_version(
  p_holder_id UUID,
  p_fencing_token BIGINT,
  p_sync_id UUID,
  p_version_id UUID,
  p_storage_path TEXT,
  p_file_size_bytes BIGINT,
  p_total_records INT,
  p_worksheets_summary JSONB,
  p_checkpoints JSONB,
  p_claim_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lease public.excel_sync_leases%ROWTYPE;
  v_chk RECORD;
  v_res JSONB;
  v_ver_num BIGINT;
BEGIN
  -- 1. Verify lease holder, fencing token, and active expiry inside publication transaction
  SELECT * INTO v_lease
  FROM public.excel_sync_leases
  WHERE lease_key = 'master_sync'
  FOR UPDATE;

  IF v_lease.holder_id <> p_holder_id OR v_lease.fencing_token <> p_fencing_token OR v_lease.status <> 'active' OR v_lease.expires_at < now() THEN
    RAISE EXCEPTION 'Publication rejected: worker lease expired or superseded (fencing token mismatch).';
  END IF;

  -- 2. Idempotency check: if version is already published, return existing record
  IF EXISTS (SELECT 1 FROM public.excel_sync_versions WHERE id = p_version_id AND is_active = true) THEN
    SELECT jsonb_build_object('success', true, 'version_id', id, 'version_number', version_number, 'already_published', true)
    INTO v_res
    FROM public.excel_sync_versions WHERE id = p_version_id;
    RETURN v_res;
  END IF;

  -- 3. Deactivate previous version and activate new one
  UPDATE public.excel_sync_versions
  SET is_active = false
  WHERE is_active = true;

  INSERT INTO public.excel_sync_versions (
    id, sync_id, fencing_token, storage_path, file_size_bytes, total_records,
    worksheets_summary, is_active, published_at
  ) VALUES (
    p_version_id, p_sync_id, p_fencing_token, p_storage_path, p_file_size_bytes, p_total_records,
    p_worksheets_summary, true, now()
  ) RETURNING version_number INTO v_ver_num;

  -- 4. Atomically commit per-worksheet checkpoints
  FOR v_chk IN
    SELECT
      (item->>'worksheetName')::TEXT AS ws_name,
      (item->>'sourceTable')::TEXT AS src_tbl,
      COALESCE((item->>'highWaterMark')::TIMESTAMPTZ, now()) AS hw_mark,
      COALESCE((item->>'recordCount')::INT, 0) AS rec_cnt
    FROM jsonb_array_elements(p_checkpoints) AS item
  LOOP
    INSERT INTO public.excel_sync_checkpoints (
      worksheet_name, source_table, last_sync_timestamp, record_count, last_sync_id, updated_at
    ) VALUES (
      v_chk.ws_name, v_chk.src_tbl, v_chk.hw_mark, v_chk.rec_cnt, p_sync_id, now()
    )
    ON CONFLICT (worksheet_name) DO UPDATE
      SET source_table = EXCLUDED.source_table,
          last_sync_timestamp = EXCLUDED.last_sync_timestamp,
          record_count = EXCLUDED.record_count,
          last_sync_id = EXCLUDED.last_sync_id,
          updated_at = now();
  END LOOP;

  -- 5. Acknowledge and purge claimed outbox events for this sync run
  IF p_claim_id IS NOT NULL THEN
    DELETE FROM public.excel_sync_outbox
    WHERE claim_id = p_claim_id AND status = 'claimed';
  END IF;

  -- 6. Finalize excel_sync_state
  UPDATE public.excel_sync_state
  SET status = 'success',
      completed_at = now(),
      records_upserted = p_total_records,
      file_size_bytes = p_file_size_bytes,
      storage_path = p_storage_path,
      error_message = NULL
  WHERE id = p_sync_id;

  -- 7. Release lease
  UPDATE public.excel_sync_leases
  SET status = 'released'
  WHERE lease_key = 'master_sync'
    AND holder_id = p_holder_id
    AND fencing_token = p_fencing_token;

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'version_number', v_ver_num,
    'sync_id', p_sync_id,
    'total_records', p_total_records,
    'file_size_bytes', p_file_size_bytes,
    'storage_path', p_storage_path,
    'published_at', now()
  );
END;
$$;

-- RPC: Get Current Active Workbook Version
CREATE OR REPLACE FUNCTION public.get_excel_sync_active_version()
RETURNS TABLE (
  version_id UUID,
  version_number BIGINT,
  storage_path TEXT,
  file_size_bytes BIGINT,
  total_records INT,
  worksheets_summary JSONB,
  published_at TIMESTAMPTZ,
  sync_id UUID
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    id AS version_id,
    version_number,
    storage_path,
    file_size_bytes,
    total_records,
    worksheets_summary,
    published_at,
    sync_id
  FROM public.excel_sync_versions
  WHERE is_active = true
  LIMIT 1;
$$;

-- ============================================================================
-- 6. ROW-LEVEL SECURITY & PERMISSIONS
-- ============================================================================

ALTER TABLE public.excel_sync_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.excel_sync_leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.excel_sync_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage excel sync outbox" ON public.excel_sync_outbox;
CREATE POLICY "Admins can manage excel sync outbox"
  ON public.excel_sync_outbox FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true));

DROP POLICY IF EXISTS "Admins can manage excel sync leases" ON public.excel_sync_leases;
CREATE POLICY "Admins can manage excel sync leases"
  ON public.excel_sync_leases FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true));

DROP POLICY IF EXISTS "Admins can view excel sync versions" ON public.excel_sync_versions;
CREATE POLICY "Admins can view excel sync versions"
  ON public.excel_sync_versions FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true));

-- Grants
GRANT ALL ON TABLE public.excel_sync_outbox TO service_role;
GRANT ALL ON TABLE public.excel_sync_leases TO service_role;
GRANT ALL ON TABLE public.excel_sync_versions TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.excel_sync_outbox TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.excel_sync_leases TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.excel_sync_versions TO authenticated;

GRANT EXECUTE ON FUNCTION public.claim_excel_sync_outbox_events(UUID, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.acquire_excel_sync_lease(UUID, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.renew_excel_sync_lease(UUID, BIGINT, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_excel_sync_lease(UUID, BIGINT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.publish_excel_sync_version(UUID, BIGINT, UUID, UUID, TEXT, BIGINT, INT, JSONB, JSONB, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_excel_sync_active_version() TO authenticated, service_role;
