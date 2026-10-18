-- ============================================================================
-- Migration: 20261017182000_add_doctor_name_to_appointments.sql
-- Description:
--   Adds an optional doctor_name text column to public.appointments to store
--   static display doctor names without requiring Supabase Auth / profile accounts.
-- ============================================================================

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS doctor_name TEXT;

-- Backfill doctor_name from notes if present
UPDATE public.appointments
SET doctor_name = substring(notes from 'Doctor:\s*([^\n\r]+)')
WHERE doctor_name IS NULL
  AND notes ~* 'Doctor:\s*([^\n\r]+)';

NOTIFY pgrst, 'reload schema';
