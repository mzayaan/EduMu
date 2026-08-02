-- EduMU :: 51 Two Form Teachers per class, one per session.
--
-- Corrects an assumption taken from the Manual rather than from practice. The
-- Manual says attendance is taken twice daily and names the Form Teacher; it
-- does not say that a class has TWO Form Teachers, one for the morning register
-- and one for the afternoon. Schools do.
--
-- Consequence for RLS: a Form Teacher may READ their class's register for both
-- sessions — they need to see what happened in the morning — but may only MARK
-- the session they are responsible for. Amending the other session goes through
-- rpc_amend_attendance, which demands a reason and is audited.

alter table staff_role_assignment
  add column if not exists session session_type;

comment on column staff_role_assignment.session is
  'For form_teacher only: which register this teacher takes. NULL means both, '
  'which is how a single-Form-Teacher class is represented.';

-- Two teachers for the same class and session would be ambiguous.
create unique index if not exists one_form_teacher_per_class_session
  on staff_role_assignment (academic_year_id, scope_id, session)
  where role_code = 'form_teacher' and scope_type = 'class' and valid_to is null;

-- ── claim helpers ───────────────────────────────────────────────────────
-- Reading: Form Teacher of the class, whichever session.
create or replace function app.form_teacher_of(p_class_group uuid) returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select exists (
    select 1
    from jsonb_array_elements(coalesce(app.claims() -> 'roles', '[]'::jsonb)) r
    where r ->> 'c' = 'form_teacher'
      and nullif(r ->> 'id','')::uuid = p_class_group
  )
$$;

-- Writing: only the session this teacher takes. A NULL session in the claim
-- means the class has one Form Teacher who takes both registers.
create or replace function app.form_teacher_of_session(
  p_class_group uuid, p_session session_type
) returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select exists (
    select 1
    from jsonb_array_elements(coalesce(app.claims() -> 'roles', '[]'::jsonb)) r
    where r ->> 'c' = 'form_teacher'
      and nullif(r ->> 'id','')::uuid = p_class_group
      and (r ->> 'sess' is null or r ->> 'sess' = p_session::text)
  )
$$;

-- ── the JWT must carry the session ──────────────────────────────────────
create or replace function app.build_claims(p_auth_user_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp
as $$
declare
  v_person record; v_year uuid; v_roles jsonb := '[]'::jsonb; v_caps jsonb := '[]'::jsonb;
begin
  select p.id, p.school_id, p.person_type into v_person
  from person p where p.auth_user_id = p_auth_user_id and p.is_active limit 1;
  if v_person.id is null then return '{}'::jsonb; end if;

  select y.id into v_year from academic_year y
  where y.school_id = v_person.school_id and y.status = 'active' limit 1;

  if v_person.person_type = 'staff' then
    select coalesce(jsonb_agg(distinct jsonb_strip_nulls(jsonb_build_object(
             'c', sra.role_code, 's', sra.scope_type::text,
             'id', sra.scope_id, 'sess', sra.session::text))), '[]'::jsonb)
    into v_roles
    from staff_role_assignment sra
    where sra.staff_id = v_person.id
      and (v_year is null or sra.academic_year_id = v_year)
      and sra.valid_from <= current_date
      and (sra.valid_to is null or sra.valid_to >= current_date);

    select coalesce(jsonb_agg(distinct rc.capability_code), '[]'::jsonb) into v_caps
    from staff_role_assignment sra
    join role_capability rc on rc.role_code = sra.role_code
    where sra.staff_id = v_person.id
      and (v_year is null or sra.academic_year_id = v_year)
      and sra.valid_from <= current_date
      and (sra.valid_to is null or sra.valid_to >= current_date);

  elsif v_person.person_type = 'student' then
    v_roles := jsonb_build_array(jsonb_build_object('c','student','s','self'));
    select coalesce(jsonb_agg(rc.capability_code), '[]'::jsonb) into v_caps
    from role_capability rc where rc.role_code = 'student';
  else
    v_roles := jsonb_build_array(jsonb_build_object('c','guardian','s','ward'));
    select coalesce(jsonb_agg(rc.capability_code), '[]'::jsonb) into v_caps
    from role_capability rc where rc.role_code = 'guardian';
  end if;

  return jsonb_build_object(
    'school_id', v_person.school_id, 'person_id', v_person.id,
    'person_type', v_person.person_type, 'year_id', v_year,
    'roles', v_roles, 'caps', v_caps);
end $$;

-- ── writes become session-scoped ────────────────────────────────────────
drop policy if exists asession_write  on attendance_session;
drop policy if exists arecord_insert  on attendance_record;
drop policy if exists arecord_update  on attendance_record;

create policy asession_write on attendance_session for all to authenticated
using (school_id = app.school_id()
       and app.year_is_open(academic_year_id)
       and (app.form_teacher_of_session(class_group_id, session)
            or app.has_cap('attendance.mark.any')))
with check (school_id = app.school_id()
       and app.year_is_open(academic_year_id)
       and (app.form_teacher_of_session(class_group_id, session)
            or app.has_cap('attendance.mark.any')));

create policy arecord_insert on attendance_record for insert to authenticated
with check (
  school_id = app.school_id() and app.has_cap('attendance.mark')
  and exists (select 1 from attendance_session s
              where s.id = attendance_session_id and s.status = 'open'
                and app.year_is_open(s.academic_year_id)
                and (app.form_teacher_of_session(s.class_group_id, s.session)
                     or app.has_cap('attendance.mark.any')))
);

create policy arecord_update on attendance_record for update to authenticated
using (
  school_id = app.school_id() and app.has_cap('attendance.mark')
  and exists (select 1 from attendance_session s
              where s.id = attendance_session_id and s.status = 'open'
                and app.year_is_open(s.academic_year_id)
                and (app.form_teacher_of_session(s.class_group_id, s.session)
                     or app.has_cap('attendance.mark.any')))
)
with check (school_id = app.school_id());

-- rpc_open_register must respect the session split too.
create or replace function public.rpc_open_register(
  p_class_group_id uuid, p_date date, p_session session_type
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_session uuid; v_school uuid; v_year uuid;
begin
  select cg.school_id, cg.academic_year_id into v_school, v_year
  from class_group cg where cg.id = p_class_group_id;

  if v_school is null then raise exception 'Unknown class group'; end if;
  if v_school <> app.school_id()
     or not (app.form_teacher_of_session(p_class_group_id, p_session)
             or app.has_cap('attendance.mark.any')) then
    raise exception 'You do not take the % register for this class',
      upper(p_session::text);
  end if;
  if not app.year_is_open(v_year) then raise exception 'Academic year is closed'; end if;
  if not exists (select 1 from calendar_day cd
                 where cd.academic_year_id = v_year and cd.date = p_date
                   and cd.day_type = 'teaching') then
    raise exception 'No school on % — register cannot be opened', p_date;
  end if;

  insert into attendance_session (school_id, academic_year_id, class_group_id,
                                  date, session, taken_by, taken_at)
  values (v_school, v_year, p_class_group_id, p_date, p_session, app.person_id(), now())
  on conflict (class_group_id, date, session)
    do update set taken_at = coalesce(attendance_session.taken_at, now())
  returning id into v_session;

  insert into attendance_record (school_id, attendance_session_id, student_id,
                                 status, recorded_by)
  select v_school, v_session, ce.student_id, 'present', app.person_id()
  from class_enrolment ce
  where ce.class_group_id = p_class_group_id
    and ce.effective_from <= p_date
    and (ce.effective_to is null or ce.effective_to >= p_date)
  on conflict (attendance_session_id, student_id) do nothing;

  return v_session;
end $$;

-- Which register does the caller take for a class? Drives the UI.
create or replace function public.my_registers(p_date date)
returns table (
  class_group_id uuid, class_name text, session session_type,
  is_mine boolean, taken boolean, on_roll int
)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select cg.id, cg.name, s.sess,
         app.form_teacher_of_session(cg.id, s.sess),
         exists (select 1 from attendance_session a
                 where a.class_group_id = cg.id and a.date = p_date
                   and a.session = s.sess and a.taken_at is not null),
         (select count(*)::int from class_enrolment ce
          where ce.class_group_id = cg.id and ce.effective_to is null)
  from class_group cg
  cross join (select unnest(array['am','pm']::session_type[]) as sess) s
  join academic_year y on y.id = cg.academic_year_id and y.status = 'active'
  where cg.school_id = app.school_id()
    and (app.form_teacher_of(cg.id) or app.has_cap('attendance.mark.any'))
  order by cg.name, s.sess;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_open_register(uuid, date, session_type)',
    'public.my_registers(date)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
