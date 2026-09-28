begin;

drop function if exists public.create_patient(text, text, date, text, text, text, date);

create or replace function public.create_patient(
  p_name text,
  p_department text,
  p_dob date default null,
  p_address text default null,
  p_mobile text default null,
  p_reference text default null,
  p_visit_date date default null
) returns public.patients
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_department text := lower(trim(p_department));
  prefix text;
  next_number integer;
  created_patient public.patients;
begin
  if normalized_department not in ('eye', 'dental') then
    raise exception 'Invalid patient department: %', p_department;
  end if;

  prefix := case normalized_department
    when 'eye' then 'E'
    else 'D'
  end;

  perform pg_advisory_xact_lock(
    hashtextextended('patients:' || normalized_department, 0)
  );

  select coalesce(
    max(regexp_replace(patient_number, '^[ED]-?', '')::integer),
    0
  ) + 1
  into next_number
  from public.patients
  where department = normalized_department
    and patient_number ~ ('^' || prefix || '-?[0-9]+$');

  insert into public.patients (
    patient_number,
    name,
    dob,
    address,
    mobile,
    department,
    reference,
    visit_date,
    created_at,
    updated_at
  )
  values (
    prefix || '-' || case
      when next_number < 10000 then lpad(next_number::text, 4, '0')
      else next_number::text
    end,
    trim(p_name),
    p_dob,
    nullif(trim(p_address), ''),
    nullif(trim(p_mobile), ''),
    normalized_department,
    nullif(trim(p_reference), ''),
    coalesce(p_visit_date, current_date),
    now(),
    now()
  )
  returning * into created_patient;

  return created_patient;
end;
$$;

revoke all on function public.create_patient(text, text, date, text, text, text, date)
  from public;
grant execute on function public.create_patient(text, text, date, text, text, text, date)
  to authenticated;

commit;