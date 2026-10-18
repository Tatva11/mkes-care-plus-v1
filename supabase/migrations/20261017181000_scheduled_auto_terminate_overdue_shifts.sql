-- ============================================================================
-- MKES CARE+ — Authoritative Shift End Auto-Termination & Sign-Out
-- Migration: 20261017181000_scheduled_auto_terminate_overdue_shifts.sql
--
-- Requirements:
--   1. Automatically close open attendance entries at the scheduled shift-end time.
--   2. Calculate working duration from check-in to scheduled shift end (not processing time).
--   3. Do not overwrite earlier valid manual sign-out (WHERE check_out_time IS NULL).
--   4. Handle overnight shifts (end_time < start_time -> +1 day).
--   5. Idempotent: close each session once, no duplicate records.
--   6. Scheduled via pg_cron every 5 minutes if supported.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_terminate_overdue_shifts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_closed_count integer := 0;
  v_rec record;
  v_shift_end_time time;
  v_shift_end_tz timestamptz;
  v_working_hours numeric;
  v_clinic_tz text := 'Asia/Kolkata';
BEGIN
  -- Iterate through active unclosed records (ignoring leave/holiday/absent records)
  FOR v_rec IN (
    SELECT 
      sa.id,
      sa.staff_id,
      sa.record_date,
      sa.shift,
      sa.check_in_time,
      sa.notes,
      sc.end_time,
      sc.start_time
    FROM public.staff_attendance sa
    LEFT JOIN public.shift_configurations sc 
      ON sc.name = (
        CASE 
          WHEN lower(sa.shift) IN ('night', 'evening') THEN 'afternoon'
          ELSE lower(sa.shift)
        END
      )
    WHERE sa.check_in_time IS NOT NULL 
      AND sa.check_out_time IS NULL
      AND sa.status NOT IN ('leave', 'holiday', 'absent')
  ) LOOP
    -- Determine end time from saved shift config or safe default
    IF v_rec.end_time IS NOT NULL THEN
      v_shift_end_time := v_rec.end_time;
    ELSE
      IF lower(v_rec.shift) = 'morning' THEN
        v_shift_end_time := '13:00:00'::time;
      ELSE
        v_shift_end_time := '21:00:00'::time;
      END IF;
    END IF;

    -- Construct the scheduled shift end timestamp in the clinic's local timezone
    v_shift_end_tz := (v_rec.record_date || ' ' || v_shift_end_time::text)::timestamp AT TIME ZONE v_clinic_tz;

    -- If shift spans past midnight (end_time < start_time), add 1 day
    IF v_rec.start_time IS NOT NULL AND v_rec.end_time IS NOT NULL AND v_rec.end_time < v_rec.start_time THEN
      v_shift_end_tz := v_shift_end_tz + interval '1 day';
    END IF;

    -- Check if current time is past the scheduled shift end time
    IF now() >= v_shift_end_tz THEN
      -- Calculate duration clamped between 0 and 24 hours using scheduled end time
      v_working_hours := ROUND(
        GREATEST(0.0, LEAST(24.0, (EXTRACT(EPOCH FROM (v_shift_end_tz - v_rec.check_in_time)) / 3600.0)))::numeric,
        2
      );

      -- Idempotently update the unclosed session at scheduled shift end time
      UPDATE public.staff_attendance
      SET 
        check_out_time = v_shift_end_tz,
        working_hours = v_working_hours,
        notes = CASE
          WHEN notes IS NULL OR notes = '' THEN 'Auto-clocked out at configured shift end time'
          WHEN notes LIKE '%Auto-clocked out%' THEN notes
          ELSE notes || ' | Auto-clocked out at configured shift end time'
        END,
        updated_at = now()
      WHERE id = v_rec.id 
        AND check_out_time IS NULL;

      IF FOUND THEN
        v_closed_count := v_closed_count + 1;

        -- Send notification to affected staff member if table exists
        BEGIN
          IF EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = 'notifications'
          ) THEN
            INSERT INTO public.notifications (
              user_id,
              title,
              message,
              type,
              created_at
            ) VALUES (
              v_rec.staff_id,
              'Shift Automatically Closed',
              'Your ' || INITCAP(v_rec.shift) || ' Shift has reached its scheduled end time (' || TO_CHAR(v_shift_end_tz AT TIME ZONE v_clinic_tz, 'HH12:MI AM') || ') and was automatically clocked out.',
              'attendance',
              now()
            );
          END IF;
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      END IF;
    END IF;
  END LOOP;

  RETURN v_closed_count;
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.auto_terminate_overdue_shifts() TO authenticated, service_role, anon;

-- Configure scheduled job via pg_cron if available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('auto_terminate_shifts_job');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    PERFORM cron.schedule(
      'auto_terminate_shifts_job',
      '*/5 * * * *',
      'SELECT public.auto_terminate_overdue_shifts();'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
