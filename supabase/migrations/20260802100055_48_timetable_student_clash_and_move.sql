-- EduMU :: 48 The student-clash guard migration 05 promised but never created.
--
-- tt_no_room_clash and tt_no_staff_clash have always existed. The third hard
-- constraint — no pupil in two lessons at once — cannot be a unique index
-- because it depends on set_enrolment overlap, and migration 05 said a trigger
-- would enforce it. It never did. The solver avoids these clashes and the UI
-- validator catches them, but until now a direct write could persist one, which
-- is precisely what drag-and-drop editing would allow.

create or replace function app.check_timetable_student_clash() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_other text; v_count int;
begin
  select count(*), min(ss.name) into v_count, v_other
  from timetable_slot ts
  join subject_set ss on ss.id = ts.subject_set_id
  where ts.timetable_version_id = new.timetable_version_id
    and ts.cycle_day = new.cycle_day
    and ts.period_id = new.period_id
    and ts.id <> new.id
    and exists (
      select 1
      from set_enrolment a
      join set_enrolment b on b.student_id = a.student_id
      where a.subject_set_id = new.subject_set_id
        and b.subject_set_id = ts.subject_set_id
        and a.effective_to is null
        and b.effective_to is null
    );

  if v_count > 0 then
    raise exception
      'Pupil clash: this set shares pupils with % at day % period %',
      v_other, new.cycle_day,
      (select pd.name from period_definition pd where pd.id = new.period_id)
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

create trigger timetable_slot_student_clash
  before insert or update of cycle_day, period_id, subject_set_id on timetable_slot
  for each row execute function app.check_timetable_student_clash();

-- Move one lesson. A targeted update rather than replacing the whole version,
-- so a drag costs one row and the three hard constraints do the arguing.
create or replace function public.rpc_move_timetable_slot(
  p_slot uuid, p_cycle_day smallint, p_period uuid, p_room uuid default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_status text; v_school uuid;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;

  select tv.status, ts.school_id into v_status, v_school
  from timetable_slot ts join timetable_version tv on tv.id = ts.timetable_version_id
  where ts.id = p_slot;

  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown lesson';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;

  update timetable_slot
     set cycle_day = p_cycle_day,
         period_id = p_period,
         room_id   = coalesce(p_room, room_id)
   where id = p_slot;
end $$;

-- Lessons a set still owes, so the editor can show an unplaced tray rather than
-- silently dropping what the solver could not place.
create or replace function public.unplaced_lessons(p_version uuid)
returns table (
  subject_set_id uuid, set_name text, subject_name text,
  required smallint, placed int, outstanding int,
  required_room_type room_type, size int
)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select
    ss.id, ss.name, sub.name_en,
    ss.periods_per_cycle,
    (select count(*)::int from timetable_slot ts
      where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id),
    ss.periods_per_cycle - (select count(*)::int from timetable_slot ts
      where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id),
    sub.requires_room_type,
    (select count(*)::int from set_enrolment se
      where se.subject_set_id = ss.id and se.effective_to is null)
  from subject_set ss
  join subject sub on sub.id = ss.subject_id
  join timetable_version tv on tv.id = p_version
  where ss.academic_year_id = tv.academic_year_id
    and ss.school_id = app.school_id()
    and app.has_cap('school.manage')
    and ss.periods_per_cycle > (select count(*) from timetable_slot ts
        where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id)
  order by ss.name;
$$;

-- Place a lesson that has no slot yet, from the unplaced tray.
create or replace function public.rpc_place_lesson(
  p_version uuid, p_set uuid, p_cycle_day smallint, p_period uuid, p_room uuid default null
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_staff uuid; v_id uuid; v_status text;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;
  select tv.status, tv.school_id into v_status, v_school
  from timetable_version tv where tv.id = p_version;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown timetable version';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;

  select se.staff_id into v_staff from set_educator se
   where se.subject_set_id = p_set and se.is_primary limit 1;

  insert into timetable_slot (school_id, timetable_version_id, cycle_day,
                              period_id, subject_set_id, room_id, staff_id)
  values (v_school, p_version, p_cycle_day, p_period, p_set, p_room, v_staff)
  returning id into v_id;

  return v_id;
end $$;

create or replace function public.rpc_remove_lesson(p_slot uuid)
returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_status text; v_school uuid;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;
  select tv.status, ts.school_id into v_status, v_school
  from timetable_slot ts join timetable_version tv on tv.id = ts.timetable_version_id
  where ts.id = p_slot;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown lesson';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;
  delete from timetable_slot where id = p_slot;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_move_timetable_slot(uuid, smallint, uuid, uuid)',
    'public.rpc_place_lesson(uuid, uuid, smallint, uuid, uuid)',
    'public.rpc_remove_lesson(uuid)',
    'public.unplaced_lessons(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
