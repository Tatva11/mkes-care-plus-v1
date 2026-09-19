-- ============================================================
-- MKES CARE+ — Sprint 1 Database Schema
-- ============================================================
-- Compatible with: Supabase PostgreSQL 15+
-- Run this in the Supabase SQL Editor (Project → SQL Editor → New Query)
-- This script is idempotent: safe to run multiple times.
-- ============================================================

-- ============================================================
-- SECTION 1: DEPARTMENTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.departments (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL UNIQUE,
  description TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index on name for fast lookups
CREATE INDEX IF NOT EXISTS idx_departments_name ON public.departments(name);

-- Enable RLS
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- SECTION 2: PROFILES TABLE
-- ============================================================
-- profile.id MUST match the Supabase auth.users.id for the user.
-- The cascade delete ensures profile is removed when auth user is deleted.
CREATE TABLE IF NOT EXISTS public.profiles (
  id           UUID         NOT NULL PRIMARY KEY
                              REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name    TEXT         NOT NULL,
  email        TEXT         NOT NULL UNIQUE,
  phone_number TEXT,
  department   TEXT,         -- references department name (denormalised for simplicity)
  department_id UUID         REFERENCES public.departments(id) ON DELETE SET NULL,
  designation  TEXT,
  role         TEXT         NOT NULL CHECK (role IN ('admin', 'staff')),
  is_active    BOOLEAN      NOT NULL DEFAULT true,
  salary       DECIMAL(10,2),
  joining_date DATE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_profiles_role     ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_email    ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_active   ON public.profiles(is_active);
CREATE INDEX IF NOT EXISTS idx_profiles_dept     ON public.profiles(department);
CREATE INDEX IF NOT EXISTS idx_profiles_dept_id  ON public.profiles(department_id);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- SECTION 3: HELPER FUNCTION — is_admin()
-- ============================================================
-- SECURITY DEFINER so it runs with elevated privileges and does NOT
-- trigger the RLS policies on profiles (prevents infinite recursion).
-- SET search_path = public prevents search-path injection attacks.
-- ============================================================
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND is_active = true
  );
END;
$$;

-- ============================================================
-- SECTION 4: RLS POLICIES — PROFILES
-- ============================================================
-- Drop all existing policies first to ensure idempotency.
DROP POLICY IF EXISTS "Users can view own profile"    ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles"  ON public.profiles;
DROP POLICY IF EXISTS "Admins can insert profiles"    ON public.profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can delete profiles"    ON public.profiles;

-- Every authenticated user can read their own profile row.
-- Required for: Auth flow profile lookup after login.
CREATE POLICY "Users can view own profile"
ON public.profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);

-- Active admins can read ALL profiles (for user management).
CREATE POLICY "Admins can view all profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (is_admin());

-- Only active admins can INSERT new profile rows.
-- NOTE: The bootstrap problem (first admin) is handled separately —
-- see Section 6 below.
CREATE POLICY "Admins can insert profiles"
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (is_admin());

-- Only active admins can UPDATE any profile row.
CREATE POLICY "Admins can update all profiles"
ON public.profiles
FOR UPDATE
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- Only active admins can DELETE profile rows.
CREATE POLICY "Admins can delete profiles"
ON public.profiles
FOR DELETE
TO authenticated
USING (is_admin());

-- ============================================================
-- SECTION 5: RLS POLICIES — DEPARTMENTS
-- ============================================================
DROP POLICY IF EXISTS "Anyone can view departments"    ON public.departments;
DROP POLICY IF EXISTS "Admins can insert departments"  ON public.departments;
DROP POLICY IF EXISTS "Admins can update departments"  ON public.departments;
DROP POLICY IF EXISTS "Admins can delete departments"  ON public.departments;

-- Any authenticated user can read departments (needed for dropdowns).
CREATE POLICY "Anyone can view departments"
ON public.departments
FOR SELECT
TO authenticated
USING (true);

-- Only admins can manage departments.
CREATE POLICY "Admins can insert departments"
ON public.departments
FOR INSERT
TO authenticated
WITH CHECK (is_admin());

CREATE POLICY "Admins can update departments"
ON public.departments
FOR UPDATE
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

CREATE POLICY "Admins can delete departments"
ON public.departments
FOR DELETE
TO authenticated
USING (is_admin());

-- ============================================================
-- SECTION 6: RPC — create_user_by_admin  [DEPRECATED]
-- ============================================================
-- ⚠️  DEPRECATED: This RPC is NO LONGER called by the Flutter app.
--
-- Root-cause: pgcrypto.crypt() creates a bcrypt hash that GoTrue
-- cannot verify, so staff login always failed with
-- "Invalid login credentials".
--
-- Replacement: The Edge Function `create-staff-user` (see
-- supabase/functions/create-staff-user/index.ts) calls
-- supabase.auth.admin.createUser() which uses GoTrue's own bcrypt
-- path. The Flutter repository now calls
--   supabase.functions.invoke('create-staff-user', ...)
-- instead of this RPC.
--
-- This function definition is kept here only for:
--   • rollback reference
--   • Supabase dashboard compatibility (function must exist for GRANT)
-- It is safe to DROP it once the Edge Function has been in
-- production for a sprint without issues.
-- ============================================================
DROP FUNCTION IF EXISTS create_user_by_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DECIMAL, DATE);
DROP FUNCTION IF EXISTS create_user_by_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_user_by_admin(
  p_email        TEXT,
  p_password     TEXT,
  p_full_name    TEXT,
  p_phone_number TEXT    DEFAULT NULL,
  p_department_id UUID   DEFAULT NULL,
  p_designation  TEXT    DEFAULT NULL,
  p_role         TEXT    DEFAULT 'staff',
  p_salary       DECIMAL DEFAULT NULL,
  p_joining_date DATE    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_user_id UUID;
  auth_instance_id UUID;
BEGIN
  -- 1. Role enforcement: only an active admin may call this.
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only active admins can create users'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Role value validation.
  IF p_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Invalid role: must be admin or staff'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT instance_id
  INTO auth_instance_id
  FROM auth.users
  WHERE id = auth.uid();

  IF auth_instance_id IS NULL THEN
    RAISE EXCEPTION 'The current admin Auth account has no instance_id'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 3. Create the auth user.
  --    We use pgcrypto's crypt() which is available in Supabase's PostgreSQL.
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role
  )
  VALUES (
    gen_random_uuid(),
    auth_instance_id,
    p_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),                                -- Auto-confirm email
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name),
    'authenticated',
    'authenticated'
  )
  RETURNING id INTO new_user_id;

  -- 4. Insert the profile row.
  INSERT INTO public.profiles (
    id,
    full_name,
    email,
    phone_number,
    department_id,
    designation,
    role,
    is_active,
    salary,
    joining_date
  ) VALUES (
    new_user_id,
    p_full_name,
    p_email,
    p_phone_number,
    p_department_id,
    p_designation,
    p_role,
    true,
    p_salary,
    p_joining_date
  );

  RETURN new_user_id;
END;
$$;

-- ============================================================
-- SECTION 7: RPC — delete_user_by_admin
-- ============================================================
DROP FUNCTION IF EXISTS delete_user_by_admin(UUID);

CREATE OR REPLACE FUNCTION delete_user_by_admin(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only active admins can delete users'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Prevent admins from deleting themselves.
  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own account'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Delete from auth.users — profile is cascade-deleted.
  DELETE FROM auth.users WHERE id = target_user_id;
END;
$$;

-- ============================================================
-- SECTION 8: GRANT EXECUTE PERMISSIONS
-- ============================================================
GRANT EXECUTE ON FUNCTION create_user_by_admin(TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, DECIMAL, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_user_by_admin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;

-- ============================================================
-- SECTION 9: DEPARTMENT SEED DATA
-- ============================================================
-- These departments are inserted only if they don't already exist.
INSERT INTO public.departments (name, description)
VALUES
  ('Eye', 'Ophthalmology and eye care services'),
  ('Dental', 'Dental and oral health services'),
  ('Optical', 'Optical retail and dispensary operations'),
  ('Administration', 'Clinic administration and management')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- SECTION 10: BOOTSTRAP INSTRUCTIONS
-- ============================================================
-- The first admin user cannot be created via the Flutter UI because
-- the "Admins can insert profiles" RLS policy requires an existing admin.
-- 
-- BOOTSTRAP STEPS (one-time setup):
-- 
-- Step 1: Create the admin user in Supabase Auth Dashboard:
--   Authentication → Users → Invite User (or Add User)
--   Use the admin's actual email and a strong password.
--   Copy the resulting user UUID from the Users list.
--
-- Step 2: Run this SQL in the SQL Editor (replace values):
--
--   INSERT INTO public.profiles (id, full_name, email, role, is_active)
--   VALUES (
--     '<uuid-from-auth-users>',
--     'Super Admin',
--     'admin@yourdomain.com',
--     'admin',
--     true
--   );
--
-- After this one-time bootstrap, the admin can create further
-- users via the Admin Portal → Staff Management → Add User.
-- ============================================================
