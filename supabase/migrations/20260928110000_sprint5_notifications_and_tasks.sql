-- ============================================================
-- MKES CARE+ — Migration: Sprint 5 Notifications & Tasks
-- ============================================================

-- 1. Ensure columns exist on profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS salary DECIMAL(10,2),
  ADD COLUMN IF NOT EXISTS joining_date DATE;

-- 2. Ensure notifications table exists with proper structure
CREATE TABLE IF NOT EXISTS public.notifications (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  message     TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'info',
  is_read     BOOLEAN     NOT NULL DEFAULT false,
  related_id  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ensure check constraint allows all notification types used by the app
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
      'system'
    )
  );

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_is_read
  ON public.notifications(user_id, is_read);

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
  ON public.notifications(created_at DESC);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Set replica identity to full so Realtime changes broadcast full row data
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- Drop old policies to avoid duplicates
DROP POLICY IF EXISTS "Admins have full access to notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;

-- 1. Admins have full access
CREATE POLICY "Admins have full access to notifications" ON public.notifications
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 2. Users can view their own notifications (and Admins can view all)
CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- 3. Users can update their own notifications (e.g. mark read)
CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR public.is_admin())
WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- 4. Users can delete their own notifications (e.g. dismiss, clear all)
CREATE POLICY "Users can delete own notifications" ON public.notifications
FOR DELETE TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- 5. Authenticated users can insert notifications (e.g. staff notifying admins, admin notifying staff)
CREATE POLICY "Authenticated users can insert notifications" ON public.notifications
FOR INSERT TO authenticated
WITH CHECK (auth.role() = 'authenticated');

-- 6. Also allow authenticated users to view active admin profiles (so staff can lookup admin IDs)
DROP POLICY IF EXISTS "Authenticated users can view admin profiles" ON public.profiles;
CREATE POLICY "Authenticated users can view admin profiles" ON public.profiles
FOR SELECT TO authenticated
USING (role = 'admin' AND is_active = true);


-- ============================================================
-- RPC: notify_user (SECURITY DEFINER)
-- ============================================================
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
    p_type,
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


-- ============================================================
-- RPC: notify_all_admins (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_all_admins(
  p_title      TEXT,
  p_message    TEXT,
  p_type       TEXT DEFAULT 'info',
  p_related_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' AND is_active = true LOOP
    INSERT INTO public.notifications (user_id, title, message, type, related_id)
    VALUES (
      v_admin.id,
      p_title,
      p_message,
      p_type,
      p_related_id
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_all_admins(TEXT, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_all_admins(TEXT, TEXT, TEXT, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.notify_all_admins(TEXT, TEXT, TEXT, UUID) TO service_role;


-- ============================================================
-- TRIGGER: notify_admins_on_new_leave_request (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_admins_on_new_leave_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_name TEXT;
  v_admin RECORD;
BEGIN
  SELECT full_name INTO v_staff_name FROM public.profiles WHERE id = NEW.staff_id;
  IF v_staff_name IS NULL OR v_staff_name = '' THEN
    v_staff_name := 'A staff member';
  END IF;

  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' AND is_active = true LOOP
    INSERT INTO public.notifications (user_id, title, message, type, related_id)
    VALUES (
      v_admin.id,
      'New Leave Request',
      v_staff_name || ' has requested leave from ' || NEW.start_date || ' to ' || NEW.end_date || '.',
      'leave_request',
      NEW.id
    );
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_leave_request_notification ON public.leave_requests;
CREATE TRIGGER trg_leave_request_notification
AFTER INSERT ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_admins_on_new_leave_request();


-- ============================================================
-- REALTIME PUBLICATION
-- ============================================================
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.leave_requests;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END;
$$;
