BEGIN;

DROP POLICY IF EXISTS "Staff can insert own task history"
  ON public.task_history;

CREATE POLICY "Staff can insert own task history"
  ON public.task_history
  FOR INSERT
  TO authenticated
  WITH CHECK (
    changed_by = auth.uid()
    AND (
      (
        old_status IN ('pending', 'in_progress', 'overdue')
        AND new_status = 'completed'
      )
      OR (
        old_status = 'completed'
        AND new_status = 'pending'
      )
    )
    AND EXISTS (
      SELECT 1
      FROM public.tasks
      WHERE tasks.id = task_history.task_id
        AND tasks.assigned_to = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Staff can update assigned task status"
  ON public.tasks;

CREATE POLICY "Staff can update assigned task status"
  ON public.tasks
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = assigned_to
    AND status IN ('pending', 'in_progress', 'overdue', 'completed')
  )
  WITH CHECK (
    auth.uid() = assigned_to
    AND status IN ('pending', 'completed')
  );

COMMIT;
