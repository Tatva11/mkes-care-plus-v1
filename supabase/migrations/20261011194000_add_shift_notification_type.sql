-- MKES CARE+ — Migration: Add Duty Assignment / Shift Change Notification Types
-- File: supabase/migrations/20261011194000_add_shift_notification_type.sql

-- 1. Safely update notifications_type_check to allow 'duty_assignment' and 'shift_change'
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IN (
      'info',
      'leave_request',
      'leave_approved',
      'leave_rejected',
      'task_assigned',
      'task_updated',
      'task_completed',
      'task_overdue',
      'appointment',
      'system',
      'low_stock',
      'expiry',
      'purchase_order',
      'eye_surgery',
      'eye_surgery_assigned',
      'duty_assignment',
      'shift_change'
    )
  );

-- 2. Ensure RLS allows authenticated users to insert notifications
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users can insert notifications" ON public.notifications
FOR INSERT TO authenticated
WITH CHECK (auth.role() = 'authenticated');

-- 3. Update SECURITY DEFINER RPC notify_user with automatic graceful fallback
DROP FUNCTION IF EXISTS public.notify_user(UUID, TEXT, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.notify_user;

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id    UUID,
  p_title      TEXT,
  p_message    TEXT,
  p_type       TEXT DEFAULT 'info',
  p_related_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id UUID;
  v_target_type TEXT := COALESCE(NULLIF(TRIM(p_type), ''), 'info');
BEGIN
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    related_id,
    is_read,
    created_at
  )
  VALUES (
    p_user_id,
    p_title,
    p_message,
    v_target_type,
    p_related_id,
    false,
    now()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
EXCEPTION WHEN check_violation THEN
  -- If check constraint on notifications table rejects the type, fallback to 'system'
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    related_id,
    is_read,
    created_at
  )
  VALUES (
    p_user_id,
    p_title,
    p_message,
    'system',
    p_related_id,
    false,
    now()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.notify_user(UUID, TEXT, TEXT, TEXT, UUID) TO service_role;
