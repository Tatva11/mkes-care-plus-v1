begin;

do $$
begin
  if exists (
    select 1
    from public.patients
    where department not in ('eye', 'dental')
       or department is null
  ) then
    raise exception
      'Cannot migrate patient numbers: every patient must have eye or dental department';
  end if;
end;
$$;

-- Serialize this migration with patient creation in both departments.
select pg_advisory_xact_lock(
  hashtextextended('patients:eye', 0),
  hashtextextended('patients:dental', 0)
);

-- Use temporary values first so the existing UNIQUE constraint is never
-- violated while replacing legacy patient numbers.
update public.patients
set patient_number = '__migrating__' || id::text,
    updated_at = now()
where department in ('eye', 'dental');

with numbered as (
  select
    id,
    upper(left(department, 1)) || row_number() over (
      partition by department
      order by created_at, id
    )::text as new_patient_number
  from public.patients
  where department in ('eye', 'dental')
)
update public.patients as patients
set patient_number = numbered.new_patient_number,
    updated_at = now()
from numbered
where patients.id = numbered.id;

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

  perform pg_advisory_xact_lock(hashtextextended('patients:' || normalized_department, 0));

  select coalesce(max((substring(patient_number from 2))::integer), 0) + 1
  into next_number
  from public.patients
  where department = normalized_department
    and patient_number ~ ('^' || prefix || '[0-9]+$');

  insert into public.patients (
    patient_number,
    name,
    dob,
    address,
    mobile,
    department,
    reference,
    visit_date
  )
  values (
    prefix || next_number::text,
    trim(p_name),
    p_dob,
    nullif(trim(p_address), ''),
    nullif(trim(p_mobile), ''),
    normalized_department,
    nullif(trim(p_reference), ''),
    p_visit_date
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
