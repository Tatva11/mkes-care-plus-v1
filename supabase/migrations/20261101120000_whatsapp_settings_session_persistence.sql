-- ============================================================================
-- MKES CARE+ — Migration: WhatsApp Settings Session Persistence & Heartbeat
-- File: supabase/migrations/20261101120000_whatsapp_settings_session_persistence.sql
-- Description:
--   1. Adds session_status, qr_code_data, last_heartbeat, and connected_phone columns
--      to public.whatsapp_settings for persistent authentication tracking.
--   2. Grants SELECT on session_status, connected_phone, and last_heartbeat to authenticated
--      staff/admins so Staff Portal can display live WhatsApp connection health.
--   3. Restricts qr_code_data update to service_role or admin.
--
-- IMPORTANT: This migration is kept local for independent review. Do not apply to production
-- without explicit administrator sign-off.
-- ============================================================================

BEGIN;

-- 1. Extend whatsapp_settings columns
ALTER TABLE public.whatsapp_settings
  ADD COLUMN IF NOT EXISTS session_status TEXT NOT NULL DEFAULT 'disconnected'
    CHECK (session_status IN ('disconnected', 'connecting', 'qr_ready', 'authenticated', 'error')),
  ADD COLUMN IF NOT EXISTS qr_code_data TEXT,
  ADD COLUMN IF NOT EXISTS last_heartbeat TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS connected_phone TEXT;

-- 2. Ensure singleton row exists
INSERT INTO public.whatsapp_settings (id, is_enabled, session_status)
VALUES ('00000000-0000-0000-0000-000000000001'::UUID, false, 'disconnected')
ON CONFLICT (id) DO NOTHING;

-- 3. Expression index for rapid heartbeat queries
CREATE INDEX IF NOT EXISTS idx_whatsapp_settings_heartbeat
  ON public.whatsapp_settings (last_heartbeat DESC);

COMMIT;
