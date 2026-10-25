-- ============================================================================
-- MKES CARE+ — Migration: Harden Service-Role Only RPCs against Anon Execution
-- File: supabase/migrations/20261024000001_harden_anon_grants.sql
-- Description:
--   Explicitly revokes execution from the Supabase 'anon' role for internal
--   batch enqueue procedures and rescheduling RPC to ensure strict authorization.
-- ============================================================================

BEGIN;

-- 1. Batch procedures (strictly service_role only)
REVOKE ALL ON FUNCTION public.enqueue_eye_surgery_followups_batch() FROM anon;
REVOKE ALL ON FUNCTION public.enqueue_eye_surgery_followups_batch() FROM authenticated;
REVOKE ALL ON FUNCTION public.enqueue_eye_surgery_followups_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_eye_surgery_followups_batch() TO service_role;

REVOKE ALL ON FUNCTION public.enqueue_eye_lab_notifications_batch() FROM anon;
REVOKE ALL ON FUNCTION public.enqueue_eye_lab_notifications_batch() FROM authenticated;
REVOKE ALL ON FUNCTION public.enqueue_eye_lab_notifications_batch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_eye_lab_notifications_batch() TO service_role;

-- 2. Staff messaging & rescheduling RPCs (authenticated + service_role only)
REVOKE ALL ON FUNCTION public.reschedule_appointment_via_whatsapp(UUID, DATE, TIME, INT) FROM anon;
REVOKE ALL ON FUNCTION public.reschedule_appointment_via_whatsapp(UUID, DATE, TIME, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment_via_whatsapp(UUID, DATE, TIME, INT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_staff_whatsapp_message(TEXT, UUID, TEXT, TEXT) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
