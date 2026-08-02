-- EduMU :: 52 A pupil who arrives after the morning register has closed.
--
-- The school's convention: the morning register is already taken, so the pupil
-- stands as absent for it; the lateness is recorded on the AFTERNOON register,
-- where they are marked late rather than present.
--
-- ⚠️ CONSEQUENCE, DELIBERATELY NOT HIDDEN
-- That pupil attended most of the day but scores 1 of 2 sessions. Across a term
-- a habitually-late pupil drifts toward the 80% examination threshold on
-- lateness alone. That is what the school does on paper, so it is what this
-- does — but `late_arrival` records the true arrival time alongside it, so the
-- Rector can see the difference between "absent all morning" and "arrived at
-- 08:15" when a debarment decision is being made. See `late_arrivals_report`.

create table late_arrival (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references school on delete cascade,
  student_id     uuid not null references student on delete cascade,
  date           date not null,
  arrived_at     time not null,
  minutes_late   smallint,
  reason         text,
  recorded_by    uuid references staff,
  recorded_at    timestamptz not null default now(),
  -- Was the morning register already closed when they walked in?
  after_am_register boolean not null default true,
  unique (student_id, date)
);
create index on late_arrival (school_id, date);

alter table late_arrival enable row level security;
alter table late_arrival force  row level security;

create policy la_read on late_arrival for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('attendance.read.all')
            or app.form_teacher_of_student(student_id)
            or app.is_guardian_of(student_id)
            or student_id = app.person_id()));

create policy la_write on late_arrival for all to authenticated
using (school_id = app.school_id() and app.has_cap('attendance.resolve'))
with check (school_id = app.school_id() and app.has_cap('attendance.resolve'));

create trigger audit_late_arrival
  after insert or update or delete on late_arrival
  for each row execute function app.audit_row();

/*
 * Record a late arrival at the gate.
 *
 * The Usher does this — the Manual makes monitoring lateness their duty.
 *
 *   AM register still open  → mark them late in the morning register itself.
 *   AM register closed      → leave the morning as it stands, and carry the
 *                             lateness into the afternoon register.
 *
 * The afternoon entry is pre-set rather than merely suggested, because the PM
 * Form Teacher would otherwise mark a pupil sitting in front of them present,
 * and the lateness would vanish.
 */
create or replace function public.rpc_record_late_arrival(
  p_student uuid, p_date date, p_arrived_at time, p_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_school uuid; v_class uuid; v_am record; v_pm_session uuid;
  v_after_am boolean; v_minutes smallint; v_start time; v_outcome text;
begin
  if not app.has_cap('attendance.resolve') then
    raise exception 'Not authorised to record late arrivals';
  end if;

  select s.school_id into v_school from student s where s.id = p_student;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown pupil';
  end if;

  select ce.class_group_id into v_class from class_enrolment ce
   where ce.student_id = p_student and ce.effective_to is null;
  if v_class is null then raise exception 'Pupil is not in a class'; end if;

  -- Minutes late measured from the first teaching period of the day.
  select min(pd.starts_at) into v_start
  from period_definition pd
  join timetable_version tv on tv.id = pd.timetable_version_id
  where pd.is_teaching and tv.school_id = v_school;
  v_minutes := greatest(0, extract(epoch from (p_arrived_at - coalesce(v_start, time '07:40')))/60)::smallint;

  select a.id, a.status into v_am
  from attendance_session s
  join attendance_record a on a.attendance_session_id = s.id
  where s.class_group_id = v_class and s.date = p_date and s.session = 'am'
    and a.student_id = p_student;

  select s.status = 'open' into v_after_am
  from attendance_session s
  where s.class_group_id = v_class and s.date = p_date and s.session = 'am';
  v_after_am := not coalesce(v_after_am, false);

  insert into late_arrival (school_id, student_id, date, arrived_at,
                            minutes_late, reason, recorded_by, after_am_register)
  values (v_school, p_student, p_date, p_arrived_at, v_minutes, p_reason,
          app.person_id(), v_after_am)
  on conflict (student_id, date) do update set
    arrived_at = excluded.arrived_at, minutes_late = excluded.minutes_late,
    reason = excluded.reason, recorded_by = excluded.recorded_by,
    after_am_register = excluded.after_am_register;

  if not v_after_am and v_am.id is not null then
    -- Still open: the morning register itself records the lateness.
    update attendance_record
       set status = 'late', minutes_late = v_minutes
     where id = v_am.id;
    v_outcome := 'marked_late_in_am';
  else
    -- Closed: the morning stands, the afternoon carries the lateness.
    select s.id into v_pm_session from attendance_session s
     where s.class_group_id = v_class and s.date = p_date and s.session = 'pm';

    if v_pm_session is null then
      insert into attendance_session (school_id, academic_year_id, class_group_id,
                                      date, session, status)
      select v_school, cg.academic_year_id, v_class, p_date, 'pm', 'open'
      from class_group cg where cg.id = v_class
      returning id into v_pm_session;
    end if;

    insert into attendance_record (school_id, attendance_session_id, student_id,
                                   status, minutes_late, note, recorded_by)
    values (v_school, v_pm_session, p_student, 'late', v_minutes,
            format('Arrived %s, after the morning register', p_arrived_at),
            app.person_id())
    on conflict (attendance_session_id, student_id) do update set
      status = 'late', minutes_late = v_minutes,
      note = format('Arrived %s, after the morning register', p_arrived_at);

    v_outcome := 'carried_to_pm';
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'minutes_late', v_minutes,
    'am_status', coalesce(v_am.status::text, 'no am register'),
    'after_am_register', v_after_am);
end $$;

/*
 * Lateness alongside the absence it produced.
 *
 * A pupil marked absent in the morning who actually arrived at 08:15 looks
 * identical to one who never came, until you put the arrival time beside it.
 * This is what the Rector should have in front of them before debarring anyone
 * on an attendance percentage.
 */
create or replace view late_arrivals_report
with (security_invoker = true) as
select
  la.school_id, la.student_id, la.date, la.arrived_at, la.minutes_late,
  la.after_am_register, la.reason,
  p.first_name, p.last_name, s.admission_number, cg.name as class_name,
  (select ar.status from attendance_record ar
   join attendance_session sess on sess.id = ar.attendance_session_id
   where ar.student_id = la.student_id and sess.date = la.date and sess.session='am')
    as am_status,
  (select ar.status from attendance_record ar
   join attendance_session sess on sess.id = ar.attendance_session_id
   where ar.student_id = la.student_id and sess.date = la.date and sess.session='pm')
    as pm_status
from late_arrival la
join student s on s.id = la.student_id
join person  p on p.id = s.id
left join class_enrolment ce on ce.student_id = s.id and ce.effective_to is null
left join class_group cg on cg.id = ce.class_group_id;

grant select on late_arrivals_report to authenticated;

revoke all on function public.rpc_record_late_arrival(uuid, date, time, text)
  from public, anon;
grant execute on function public.rpc_record_late_arrival(uuid, date, time, text)
  to authenticated;
