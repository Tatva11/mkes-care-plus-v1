-- ============================================================
-- MKES CARE+ — Sprint 2 Database Schema (Staff Operations)
-- ============================================================

-- ============================================================
-- SECTION 1: ATTENDANCE
-- ============================================================
DROP TABLE IF EXISTS public.staff_attendance CASCADE;

CREATE TABLE IF NOT EXISTS public.staff_attendance (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  record_date    DATE        NOT NULL,
  check_in_time  TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  status         TEXT        NOT NULL CHECK (status IN ('present', 'late', 'absent', 'leave', 'holiday')),
  is_late        BOOLEAN     NOT NULL DEFAULT false,
  working_hours  DECIMAL(5,2),
  late_minutes   INTEGER     DEFAULT 0,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(staff_id, record_date)
);

CREATE INDEX IF NOT EXISTS idx_attendance_staff_id ON public.staff_attendance(staff_id);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON public.staff_attendance(record_date);

ALTER TABLE public.staff_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to attendance" ON public.staff_attendance;
DROP POLICY IF EXISTS "Staff can view own attendance" ON public.staff_attendance;
DROP POLICY IF EXISTS "Staff can insert own attendance" ON public.staff_attendance;
DROP POLICY IF EXISTS "Staff can update own attendance" ON public.staff_attendance;

-- Admins can do anything
CREATE POLICY "Admins have full access to attendance" ON public.staff_attendance
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Staff can SELECT their own attendance
CREATE POLICY "Staff can view own attendance" ON public.staff_attendance
FOR SELECT TO authenticated
USING (auth.uid() = staff_id);

-- Staff can INSERT their own attendance (check in)
CREATE POLICY "Staff can insert own attendance" ON public.staff_attendance
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = staff_id);

-- Staff can UPDATE their own attendance (check out, notes)
CREATE POLICY "Staff can update own attendance" ON public.staff_attendance
FOR UPDATE TO authenticated
USING (auth.uid() = staff_id)
WITH CHECK (auth.uid() = staff_id);


-- ============================================================
-- SECTION 2: LEAVE REQUESTS
-- ============================================================
DROP TABLE IF EXISTS public.leave_requests CASCADE;

CREATE TABLE IF NOT EXISTS public.leave_requests (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id         UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  start_date       DATE        NOT NULL,
  end_date         DATE        NOT NULL,
  leave_days       DECIMAL(5,1) NOT NULL,
  reason           TEXT        NOT NULL,
  status           TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by      UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at      TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT end_date_after_start_date CHECK (end_date >= start_date),
  CONSTRAINT valid_leave_days CHECK (leave_days > 0)
);

CREATE INDEX IF NOT EXISTS idx_leave_requests_staff_id ON public.leave_requests(staff_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON public.leave_requests(status);

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Staff can view own leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Staff can insert own leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Staff can update own pending leave requests" ON public.leave_requests;

-- Admins can do anything
CREATE POLICY "Admins have full access to leave requests" ON public.leave_requests
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Staff can SELECT their own requests
CREATE POLICY "Staff can view own leave requests" ON public.leave_requests
FOR SELECT TO authenticated
USING (auth.uid() = staff_id);

-- Staff can INSERT their own requests
CREATE POLICY "Staff can insert own leave requests" ON public.leave_requests
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = staff_id);

-- Staff can UPDATE their own requests ONLY if pending (to cancel them)
CREATE POLICY "Staff can update own pending leave requests" ON public.leave_requests
FOR UPDATE TO authenticated
USING (auth.uid() = staff_id AND status = 'pending')
WITH CHECK (auth.uid() = staff_id);


-- ============================================================
-- SECTION 3: TASKS
-- ============================================================
DROP TABLE IF EXISTS public.tasks CASCADE;

CREATE TABLE IF NOT EXISTS public.tasks (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL,
  description TEXT,
  assigned_to UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  assigned_by UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  due_date    TIMESTAMPTZ,
  priority    TEXT        NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
  status      TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'overdue', 'cancelled')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to ON public.tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON public.tasks(status);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to tasks" ON public.tasks;
DROP POLICY IF EXISTS "Staff can view assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "Staff can update assigned task status" ON public.tasks;

-- Admins can do anything
CREATE POLICY "Admins have full access to tasks" ON public.tasks
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Staff can SELECT tasks assigned to them
CREATE POLICY "Staff can view assigned tasks" ON public.tasks
FOR SELECT TO authenticated
USING (auth.uid() = assigned_to);

-- Staff can complete their own pending tasks only. Completed tasks are final.
CREATE POLICY "Staff can update assigned task status" ON public.tasks
FOR UPDATE TO authenticated
USING (auth.uid() = assigned_to AND status = 'pending')
WITH CHECK (auth.uid() = assigned_to AND status = 'completed');


-- ============================================================
-- SECTION 4: TASK HISTORY
-- ============================================================
DROP TABLE IF EXISTS public.task_history CASCADE;

CREATE TABLE IF NOT EXISTS public.task_history (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id     UUID        NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  changed_by  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  old_status  TEXT        NOT NULL,
  new_status  TEXT        NOT NULL,
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_history_task_id ON public.task_history(task_id);

ALTER TABLE public.task_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to task history" ON public.task_history;
DROP POLICY IF EXISTS "Staff can view own task history" ON public.task_history;
DROP POLICY IF EXISTS "Staff can insert own task history" ON public.task_history;

-- Admins can do anything
CREATE POLICY "Admins have full access to task history" ON public.task_history
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Staff can SELECT task history for tasks assigned to them
CREATE POLICY "Staff can view own task history" ON public.task_history
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.tasks
    WHERE tasks.id = task_history.task_id
    AND tasks.assigned_to = auth.uid()
  )
);

-- Staff can record only their own pending-to-completed transition.
CREATE POLICY "Staff can insert own task history" ON public.task_history
FOR INSERT TO authenticated
WITH CHECK (
  changed_by = auth.uid()
  AND old_status = 'pending'
  AND new_status = 'completed'
  AND
  EXISTS (
    SELECT 1 FROM public.tasks
    WHERE tasks.id = task_id
    AND tasks.assigned_to = auth.uid()
  )
);
