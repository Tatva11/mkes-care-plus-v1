-- MKES CARE+ Phase 1 department relationship migration.
-- Run manually in the Supabase SQL Editor after reviewing it.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS department_id UUID
  REFERENCES public.departments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_department_id
  ON public.profiles(department_id);

-- Preserve existing department text when the legacy column exists.
-- Some installations already use department_id only, so avoid referencing a
-- column that may not exist while parsing the migration.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'department'
  ) THEN
    EXECUTE $backfill$
      UPDATE public.profiles AS profiles
      SET department_id = departments.id
      FROM public.departments AS departments
      WHERE profiles.department_id IS NULL
        AND profiles.department IS NOT NULL
        AND lower(trim(profiles.department)) = lower(trim(departments.name))
    $backfill$;
  END IF;
END
$$;

DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DECIMAL, DATE);

CREATE OR REPLACE FUNCTION public.create_user_by_admin(
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_phone_number TEXT DEFAULT NULL,
  p_department_id UUID DEFAULT NULL,
  p_designation TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'staff',
  p_salary DECIMAL DEFAULT NULL,
  p_joining_date DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_user_id UUID;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only active admins can create users'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Invalid role: must be admin or staff'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO auth.users (
    email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role
  )
  VALUES (
    p_email, crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name),
    'authenticated', 'authenticated'
  )
  RETURNING id INTO new_user_id;

  INSERT INTO public.profiles (
    id, full_name, email, phone_number, department_id,
    designation, role, is_active, salary, joining_date
  )
  VALUES (
    new_user_id, p_full_name, p_email, p_phone_number, p_department_id,
    p_designation, p_role, true, p_salary, p_joining_date
  );

  RETURN new_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_user_by_admin(TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, DECIMAL, DATE)
  TO authenticated;