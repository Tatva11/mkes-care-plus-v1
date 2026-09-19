-- ============================================================
-- MKES CARE+ — Fix: create_user_by_admin (Sprint 1 patch)
-- ============================================================
-- ROOT CAUSE:
--   The original create_user_by_admin RPC inserted directly into
--   auth.users using extensions.crypt() (pgcrypto). GoTrue cannot
--   verify passwords hashed by pgcrypto — it uses its own Go-side
--   bcrypt implementation. As a result, every staff account created
--   via that RPC would ALWAYS fail signInWithPassword.
--
-- FIX:
--   User creation now goes through the Edge Function
--   `create-staff-user` which calls the GoTrue Admin API
--   (supabase.auth.admin.createUser). The Edge Function handles
--   auth user creation; this SQL provides a SECURITY DEFINER
--   helper that the Edge Function uses to insert the profiles row.
--
-- HOW TO APPLY:
--   Run this file in Supabase → SQL Editor → New Query.
--   Safe to run multiple times (idempotent).
-- ============================================================


-- ============================================================
-- STEP 1: Drop the broken create_user_by_admin RPC
-- ============================================================
-- We drop both known signatures so neither can be called accidentally.
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, DECIMAL, DATE);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DECIMAL, DATE);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);


-- ============================================================
-- STEP 2: Create a profile-only helper for the Edge Function
-- ============================================================
-- The Edge Function creates the auth.users row via GoTrue Admin API,
-- then calls this RPC (as service role — bypasses RLS) to insert
-- the matching profiles row.
--
-- NOTE: The Edge Function uses the service-role key and can insert
-- directly into profiles without this function. However, this helper
-- is provided as an alternative in case you want the profile logic
-- in SQL. If you are calling profiles.insert() directly from the
-- Edge Function (which the current index.ts does), you do NOT need
-- to call this function — it is here for reference and future use.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_staff_profile(
  p_user_id      UUID,
  p_email        TEXT,
  p_full_name    TEXT,
  p_phone_number TEXT    DEFAULT NULL,
  p_department_id UUID   DEFAULT NULL,
  p_designation  TEXT    DEFAULT NULL,
  p_role         TEXT    DEFAULT 'staff',
  p_salary       DECIMAL DEFAULT NULL,
  p_joining_date DATE    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Role value guard
  IF p_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Invalid role: must be admin or staff'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

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
    p_user_id,
    p_full_name,
    p_email,
    p_phone_number,
    p_department_id,
    p_designation,
    p_role,
    true,
    p_salary,
    p_joining_date
  )
  ON CONFLICT (id) DO NOTHING;  -- idempotent: skip if profile already exists
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_staff_profile(UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, DECIMAL, DATE) TO service_role;


-- ============================================================
-- STEP 3: Keep delete_user_by_admin (no change needed)
-- ============================================================
-- delete_user_by_admin still works correctly because it only
-- DELETEs from auth.users — it does not create any credentials.
-- No changes required to that function.


-- ============================================================
-- STEP 4: Fix any existing broken staff accounts
-- ============================================================
-- Staff accounts created before this fix have an auth.users row
-- whose password GoTrue cannot verify. They must be re-created.
--
-- Option A (recommended): Delete the broken auth user from the
--   Supabase Dashboard → Authentication → Users, then use the
--   Admin Portal "Add Staff" screen to re-create the account.
--   The new Edge Function will create a valid auth user.
--
-- Option B: Use this query to identify which accounts are affected.
--   Run in SQL Editor to see staff emails whose auth users were
--   created directly (these have no identity rows, which GoTrue
--   normally creates for email-signup users):
--
--   SELECT p.email, p.full_name, p.role, u.created_at
--   FROM auth.users u
--   JOIN public.profiles p ON p.id = u.id
--   WHERE p.role = 'staff'
--     AND NOT EXISTS (
--       SELECT 1 FROM auth.identities i WHERE i.user_id = u.id
--     )
--   ORDER BY u.created_at DESC;
--
-- Accounts returned by the query above were created by the broken
-- RPC and cannot log in. Delete them and re-create via Add Staff.
-- ============================================================


-- ============================================================
-- DIAGNOSTIC QUERY: Verify staff account status
-- ============================================================
-- Run this after applying the fix to see the state of all
-- staff accounts:
--
-- SELECT
--   p.email,
--   p.full_name,
--   p.role,
--   p.is_active,
--   u.email_confirmed_at IS NOT NULL AS email_confirmed,
--   u.banned_until IS NULL            AS not_banned,
--   EXISTS (
--     SELECT 1 FROM auth.identities i WHERE i.user_id = u.id
--   )                                  AS has_identity,
--   u.created_at                       AS auth_created_at
-- FROM auth.users u
-- JOIN public.profiles p ON p.id = u.id
-- ORDER BY u.created_at DESC;
-- ============================================================
