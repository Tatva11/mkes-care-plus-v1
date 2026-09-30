BEGIN;

CREATE OR REPLACE FUNCTION public.get_active_department_staff_candidates(
  p_department_id uuid
)
RETURNS TABLE (id uuid, full_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT staff.id, staff.full_name
  FROM public.profiles AS staff
  JOIN public.departments AS department
    ON department.id = staff.department_id
  WHERE staff.department_id = $1
    AND staff.role = 'staff'
    AND staff.is_active
    AND department.is_active
    AND EXISTS (
      SELECT 1
      FROM public.profiles AS requester
      WHERE requester.id = auth.uid()
        AND requester.role IN ('admin', 'staff')
        AND requester.is_active
    )
  ORDER BY staff.full_name;
$function$;

REVOKE ALL
  ON FUNCTION public.get_active_department_staff_candidates(uuid)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION public.get_active_department_staff_candidates(uuid)
  TO authenticated;

COMMIT;
