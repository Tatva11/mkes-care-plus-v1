-- ============================================================================
-- MKES CARE+ — Migration: Excel Sync Five-Minute Scheduler (Sprint 9)
-- Migration: 20261015220000_excel_sync_five_minute_scheduler.sql
-- Description:
--   1. Configuration table: public.excel_sync_config (RLS admin-only)
--   2. Scheduled trigger function: public.trigger_scheduled_excel_sync()
--      - Checks active baseline existence
--      - Checks lease concurrency (prevents overlapping worker executions)
--      - Checks pending outbox count (fast no-op exit if 0 changes)
--      - Prunes stale zero-record sync states (> 7 days) to prevent table bloat
--      - Reads credentials from Supabase Vault (decrypted_secrets) or config table
--      - Invokes Edge Function via pg_net (net.http_post) when mutations pending
--      - Logs observable failure status if credentials missing or HTTP error occurs
--   3. Registers 5-minute pg_cron schedule [mkes-care-excel-sync-every-5-minutes]
--   4. Administrative functions: pause, resume, and get_scheduler_status
-- ============================================================================

-- 1. Create Configuration Table for Excel Sync
CREATE TABLE IF NOT EXISTS public.excel_sync_config (
  config_key TEXT PRIMARY KEY,
  config_value TEXT NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default configuration keys if not present
INSERT INTO public.excel_sync_config (config_key, config_value, description)
VALUES
  ('edge_function_url', '', 'Base URL for Supabase Edge Functions (e.g. https://<project-ref>.supabase.co/functions/v1/sync-excel-workbook)'),
  ('service_role_key', '', 'Service-role key for authorized background execution of sync-excel-workbook'),
  ('scheduler_enabled', 'true', 'Master switch to enable or pause the 5-minute automatic sync scheduler')
ON CONFLICT (config_key) DO NOTHING;

ALTER TABLE public.excel_sync_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage excel sync config" ON public.excel_sync_config;
CREATE POLICY "Admins can manage excel sync config"
  ON public.excel_sync_config FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = true));

GRANT ALL ON TABLE public.excel_sync_config TO service_role;
GRANT SELECT ON TABLE public.excel_sync_config TO authenticated;

-- 2. Create the Scheduled Trigger Function
CREATE OR REPLACE FUNCTION public.trigger_scheduled_excel_sync()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_enabled TEXT;
  v_has_active_baseline BOOLEAN;
  v_pending_count INT;
  v_active_lease_exists BOOLEAN;
  v_sync_id UUID := gen_random_uuid();
  v_function_url TEXT;
  v_service_key TEXT;
  v_net_request_id BIGINT;
BEGIN
  -- 0. Check if scheduler is enabled
  SELECT config_value INTO v_enabled
  FROM public.excel_sync_config
  WHERE config_key = 'scheduler_enabled'
  LIMIT 1;

  IF v_enabled = 'false' THEN
    RETURN jsonb_build_object(
      'status', 'skipped',
      'reason', 'scheduler_disabled',
      'message', 'Automatic 5-minute synchronization is paused via config.'
    );
  END IF;

  -- 1. Check if an active baseline workbook exists
  SELECT EXISTS (
    SELECT 1 FROM public.excel_sync_versions WHERE is_active = true
  ) INTO v_has_active_baseline;

  IF NOT v_has_active_baseline THEN
    RETURN jsonb_build_object(
      'status', 'skipped',
      'reason', 'no_active_baseline',
      'message', 'No active baseline published yet. Waiting for manual initial historical export.'
    );
  END IF;

  -- 2. Check if another synchronization worker is currently executing
  SELECT EXISTS (
    SELECT 1 FROM public.excel_sync_leases
    WHERE lease_key = 'master_sync'
      AND status = 'acquired'
      AND expires_at > now()
  ) INTO v_active_lease_exists;

  IF v_active_lease_exists THEN
    RETURN jsonb_build_object(
      'status', 'skipped',
      'reason', 'already_running',
      'message', 'Another synchronization worker is holding an active lease.'
    );
  END IF;

  -- 3. Check pending mutations count in the transactional outbox
  SELECT COUNT(*) INTO v_pending_count
  FROM public.excel_sync_outbox
  WHERE status = 'pending';

  -- 4. Fast No-Op Exit: If 0 mutations pending, record a lightweight success state without waking up Edge Function
  IF v_pending_count = 0 THEN
    -- Housekeeping: Prune zero-mutation scheduled state logs older than 7 days
    DELETE FROM public.excel_sync_state
    WHERE sync_type = 'scheduled'
      AND status = 'success'
      AND records_upserted = 0
      AND created_at < now() - INTERVAL '7 days';

    INSERT INTO public.excel_sync_state (
      id, sync_type, status, started_at, completed_at,
      records_upserted, file_size_bytes, storage_path, worksheets_synced, error_message
    )
    SELECT
      v_sync_id, 'scheduled', 'success', now(), now(),
      0, v.file_size_bytes, v.storage_path, '{}', NULL
    FROM public.excel_sync_versions v
    WHERE v.is_active = true
    LIMIT 1;

    RETURN jsonb_build_object(
      'status', 'no_op',
      'pending_mutations', 0,
      'message', 'Zero pending changes. Master workbook is already up-to-date.'
    );
  END IF;

  -- 5. Retrieve Edge Function URL and Service Role Key
  -- Priority 1: Supabase Vault (decrypted_secrets view)
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname IN ('vault', 'supabase_vault')) THEN
    BEGIN
      SELECT decrypted_secret INTO v_function_url
      FROM vault.decrypted_secrets
      WHERE name = 'edge_function_url'
      LIMIT 1;

      SELECT decrypted_secret INTO v_service_key
      FROM vault.decrypted_secrets
      WHERE name = 'service_role_key'
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_function_url := NULL;
      v_service_key := NULL;
    END;
  END IF;

  -- Priority 2: public.excel_sync_config table fallback
  IF v_function_url IS NULL OR v_function_url = '' THEN
    SELECT config_value INTO v_function_url
    FROM public.excel_sync_config
    WHERE config_key = 'edge_function_url'
    LIMIT 1;
  END IF;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    SELECT config_value INTO v_service_key
    FROM public.excel_sync_config
    WHERE config_key = 'service_role_key'
    LIMIT 1;
  END IF;

  -- Diagnostic guard: If URL or key is missing, record diagnostic failure state
  IF v_function_url IS NULL OR v_function_url = '' OR v_service_key IS NULL OR v_service_key = '' THEN
    INSERT INTO public.excel_sync_state (
      id, sync_type, status, started_at, completed_at,
      records_upserted, file_size_bytes, storage_path, worksheets_synced, error_message
    ) VALUES (
      v_sync_id, 'scheduled', 'failed', now(), now(),
      0, 0, 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx', '{}',
      'Automatic sync scheduler: edge_function_url or service_role_key is not configured in Supabase Vault or excel_sync_config.'
    );

    RETURN jsonb_build_object(
      'status', 'error',
      'reason', 'missing_credentials',
      'pending_mutations', v_pending_count,
      'message', 'edge_function_url or service_role_key not configured in Vault or excel_sync_config.'
    );
  END IF;

  -- Clean and sanitize credentials (strip whitespace, quotes, and all leading 'Bearer ' prefixes)
  v_service_key := trim(both E'\r\n "\'\t' from v_service_key);
  WHILE v_service_key ILIKE 'bearer %' LOOP
    v_service_key := trim(both E'\r\n "\'\t' from substring(v_service_key from 8));
  END LOOP;

  v_function_url := trim(both E'\r\n "\'\t' from v_function_url);

  -- 6. Invoke the deployed Edge Function via pg_net
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    BEGIN
      SELECT net.http_post(
        url := v_function_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key,
          'apikey', v_service_key
        ),
        body := jsonb_build_object(
          'action', 'sync-incremental',
          'sync_type', 'scheduled'
        ),
        timeout_milliseconds := 60000
      ) INTO v_net_request_id;

      RETURN jsonb_build_object(
        'status', 'triggered',
        'pending_mutations', v_pending_count,
        'net_request_id', v_net_request_id,
        'message', 'Incremental synchronization dispatched to Edge Function via pg_net.'
      );
    EXCEPTION WHEN OTHERS THEN
      -- Record failure in audit log, preserve outbox mutations
      INSERT INTO public.excel_sync_state (
        id, sync_type, status, started_at, completed_at,
        records_upserted, file_size_bytes, storage_path, worksheets_synced, error_message
      ) VALUES (
        v_sync_id, 'scheduled', 'failed', now(), now(),
        0, 0, 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx', '{}',
        'pg_net invocation error: ' || SQLERRM
      );

      RETURN jsonb_build_object(
        'status', 'error',
        'error', SQLERRM,
        'pending_mutations', v_pending_count
      );
    END;
  ELSE
    RETURN jsonb_build_object(
      'status', 'error',
      'reason', 'pg_net_not_installed',
      'pending_mutations', v_pending_count,
      'message', 'pg_net extension is required for HTTP Edge Function invocation.'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_scheduled_excel_sync() TO authenticated, service_role, anon;

-- 3. Register 5-Minute pg_cron Schedule (Job Name: mkes-care-excel-sync-every-5-minutes)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedule existing job by current or legacy name to ensure idempotency
    BEGIN
      PERFORM cron.unschedule('mkes-care-excel-sync-every-5-minutes');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      PERFORM cron.unschedule('sync_excel_workbook_5min_job');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    PERFORM cron.schedule(
      'mkes-care-excel-sync-every-5-minutes',
      '*/5 * * * *',
      'SELECT public.trigger_scheduled_excel_sync();'
    );
    RAISE NOTICE 'Scheduled job [mkes-care-excel-sync-every-5-minutes] registered in pg_cron.';
  ELSE
    RAISE NOTICE 'pg_cron extension not installed on this database. Scheduled trigger function is ready for dashboard cron.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Non-fatal: pg_cron schedule registration caught: %', SQLERRM;
END $$;

-- 4. Administrative Control & Inspection Helper Functions

-- Helper 1: Pause Scheduler
CREATE OR REPLACE FUNCTION public.pause_excel_sync_scheduler()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.excel_sync_config
  SET config_value = 'false', updated_at = now()
  WHERE config_key = 'scheduler_enabled';

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      UPDATE cron.job
      SET active = false
      WHERE jobname = 'mkes-care-excel-sync-every-5-minutes';
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'scheduler_enabled', false, 'message', '5-minute Excel sync scheduler paused.');
END;
$$;

-- Helper 2: Resume Scheduler
CREATE OR REPLACE FUNCTION public.resume_excel_sync_scheduler()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.excel_sync_config
  SET config_value = 'true', updated_at = now()
  WHERE config_key = 'scheduler_enabled';

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      UPDATE cron.job
      SET active = true
      WHERE jobname = 'mkes-care-excel-sync-every-5-minutes';
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'scheduler_enabled', true, 'message', '5-minute Excel sync scheduler resumed.');
END;
$$;

-- Helper 3: Comprehensive Diagnostic & Status Inspection
CREATE OR REPLACE FUNCTION public.get_excel_sync_scheduler_status()
RETURNS TABLE (
  scheduler_enabled BOOLEAN,
  active_version_number BIGINT,
  active_version_records INT,
  pending_mutations_count INT,
  active_lease_held BOOLEAN,
  cron_job_exists BOOLEAN,
  cron_job_active BOOLEAN,
  cron_job_schedule TEXT,
  last_cron_run_status TEXT,
  last_cron_run_time TIMESTAMPTZ,
  has_edge_function_url BOOLEAN,
  has_service_role_key BOOLEAN,
  config_source TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_url TEXT;
  v_key TEXT;
  v_src TEXT := 'unconfigured';
  v_cron_exists BOOLEAN := false;
  v_cron_active BOOLEAN := false;
  v_cron_sched TEXT := '*/5 * * * *';
  v_last_cron_status TEXT := 'none';
  v_last_cron_time TIMESTAMPTZ := NULL;
  v_job_id BIGINT;
BEGIN
  -- Determine config source and credentials existence
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname IN ('vault', 'supabase_vault')) THEN
    BEGIN
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'edge_function_url' LIMIT 1;
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        v_src := 'vault';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  IF v_src = 'unconfigured' THEN
    SELECT config_value INTO v_url FROM public.excel_sync_config WHERE config_key = 'edge_function_url' LIMIT 1;
    SELECT config_value INTO v_key FROM public.excel_sync_config WHERE config_key = 'service_role_key' LIMIT 1;
    IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
      v_src := 'config_table';
    END IF;
  END IF;

  -- Check cron status
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      SELECT jobid, active, schedule INTO v_job_id, v_cron_active, v_cron_sched
      FROM cron.job
      WHERE jobname = 'mkes-care-excel-sync-every-5-minutes'
      LIMIT 1;

      IF v_job_id IS NOT NULL THEN
        v_cron_exists := true;
        SELECT status, start_time INTO v_last_cron_status, v_last_cron_time
        FROM cron.job_run_details
        WHERE jobid = v_job_id
        ORDER BY start_time DESC
        LIMIT 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE((SELECT config_value = 'true' FROM public.excel_sync_config WHERE config_key = 'scheduler_enabled'), true),
    v.version_number,
    v.total_records,
    (SELECT count(*)::INT FROM public.excel_sync_outbox WHERE status = 'pending'),
    EXISTS (SELECT 1 FROM public.excel_sync_leases WHERE lease_key = 'master_sync' AND status = 'active' AND expires_at > now()),
    v_cron_exists,
    v_cron_active,
    v_cron_sched,
    v_last_cron_status,
    v_last_cron_time,
    (v_url IS NOT NULL AND v_url <> ''),
    (v_key IS NOT NULL AND v_key <> ''),
    v_src
  FROM (SELECT 1) _
  LEFT JOIN public.excel_sync_versions v ON v.is_active = true
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pause_excel_sync_scheduler() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resume_excel_sync_scheduler() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_excel_sync_scheduler_status() TO authenticated, service_role;

-- Helper 4: Safe Vault Credential Diagnostic Fingerprint (Never exposes secret key)
CREATE OR REPLACE FUNCTION public.get_excel_sync_vault_fingerprint()
RETURNS TABLE (
  secret_name TEXT,
  key_length INT,
  prefix_suffix TEXT,
  has_bearer_prefix BOOLEAN,
  has_whitespace BOOLEAN,
  sha256_hash TEXT
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_raw TEXT;
  v_trimmed TEXT;
  v_clean TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname IN ('vault', 'supabase_vault')) THEN
    BEGIN
      SELECT decrypted_secret INTO v_raw
      FROM vault.decrypted_secrets
      WHERE name = 'service_role_key'
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_raw := NULL;
    END;
  END IF;

  IF v_raw IS NULL THEN
    SELECT config_value INTO v_raw
    FROM public.excel_sync_config
    WHERE config_key = 'service_role_key'
    LIMIT 1;
  END IF;

  IF v_raw IS NULL OR v_raw = '' THEN
    RETURN QUERY SELECT 'service_role_key'::TEXT, 0, 'none'::TEXT, false, false, 'none'::TEXT;
    RETURN;
  END IF;

  v_trimmed := trim(both E'\r\n \t' from v_raw);
  v_clean := v_trimmed;
  WHILE v_clean ILIKE 'bearer %' LOOP
    v_clean := trim(both E'\r\n \t' from substring(v_clean from 8));
  END LOOP;

  RETURN QUERY
  SELECT
    'service_role_key'::TEXT,
    length(v_clean),
    (substring(v_clean from 1 for 6) || '...' || substring(v_clean from length(v_clean) - 3)),
    (v_trimmed ILIKE 'bearer %'),
    (length(v_raw) <> length(v_trimmed)),
    encode(digest(v_clean, 'sha256'), 'hex');
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_excel_sync_vault_fingerprint() TO authenticated, service_role;

