-- MKES CARE+ Sprint 3 Phase 1: patient attendance
-- Run this migration after confirming the existing patient IDs are the values used by the app.

CREATE TABLE IF NOT EXISTS public.patient_attendance (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id      TEXT NOT NULL,
  staff_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  attended_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  status          TEXT NOT NULL DEFAULT 'attended' CHECK (status IN ('attended')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (patient_id, attendance_date)
);

CREATE INDEX IF NOT EXISTS idx_patient_attendance_staff_date
  ON public.patient_attendance(staff_id, attendance_date);

ALTER TABLE public.patient_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to patient attendance" ON public.patient_attendance;
DROP POLICY IF EXISTS "Staff can view own patient attendance" ON public.patient_attendance;
DROP POLICY IF EXISTS "Staff can insert own patient attendance" ON public.patient_attendance;

CREATE POLICY "Admins have full access to patient attendance"
ON public.patient_attendance
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY "Staff can view own patient attendance"
ON public.patient_attendance
FOR SELECT TO authenticated
USING (auth.uid() = staff_id);

CREATE POLICY "Staff can insert own patient attendance"
ON public.patient_attendance
FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = staff_id
  AND EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = 'staff'
      AND profiles.is_active = true
  )
);
