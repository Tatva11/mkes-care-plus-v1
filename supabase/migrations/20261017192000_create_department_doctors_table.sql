-- ============================================================================
-- Migration: Create Department Doctors Table for Static Doctor Management
-- Date: 2026-10-17
-- Description:
--   Creates public.department_doctors table to allow administrators to add,
--   edit, and deactivate doctor names by clinical department without creating
--   Supabase Auth accounts, staff records, or doctor profiles.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.department_doctors (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    full_name TEXT NOT NULL,
    department TEXT NOT NULL CHECK (department IN ('eye', 'dental')),
    specialty TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for case-insensitive duplicate prevention per department
CREATE UNIQUE INDEX IF NOT EXISTS idx_dept_doctors_name_dept
  ON public.department_doctors (lower(trim(full_name)), lower(trim(department)));

-- Seed the initial Sprint 11 confirmed doctor roster if empty
INSERT INTO public.department_doctors (full_name, department, specialty, is_active)
VALUES
  ('Dr Mitesh Jain', 'eye', 'Ophthalmology', true),
  ('Dr Varun', 'eye', 'Ophthalmology', true),
  ('Dr Nimisha', 'dental', 'General Dentistry', true),
  ('Dr Vikas', 'dental', 'Dental Surgery', true)
ON CONFLICT (lower(trim(full_name)), lower(trim(department))) DO NOTHING;

-- Enable Row Level Security
ALTER TABLE public.department_doctors ENABLE ROW LEVEL SECURITY;

-- Policy 1: Authenticated users (staff and admins) can view all department doctors
DROP POLICY IF EXISTS "Authenticated users can view department doctors" ON public.department_doctors;
CREATE POLICY "Authenticated users can view department doctors"
  ON public.department_doctors FOR SELECT TO authenticated
  USING (true);

-- Policy 2: Admins can insert, update, and manage department doctors
DROP POLICY IF EXISTS "Admins can manage department doctors" ON public.department_doctors;
CREATE POLICY "Admins can manage department doctors"
  ON public.department_doctors FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

NOTIFY pgrst, 'reload schema';
