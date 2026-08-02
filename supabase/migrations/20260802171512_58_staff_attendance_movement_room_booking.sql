-- EduMU :: 58 Staff attendance, staff movement, and room booking.
-- All three named in the blueprint and never built.

-- Postgres ships range types for numeric, date and timestamp, but not for
-- `time`. Room bookings and period definitions are both wall-clock times within
-- a day, so we need one to express overlap.
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where t.typname = 'timerange' and n.nspname = 'public') then
    create type public.timerange as range (subtype = time without time zone);
  end if;
end $$;

-- ── staff attendance ──────────────────────────────────────────────────────
-- The Manual makes the staff register a Rector duty. Deliberately NOT modelled
-- on pupil attendance: staff have leave types, arrive late without being
-- absent, and are covered by a substitute. One row per member per day.
create table staff_attendance (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references school on delete cascade,
  staff_id     uuid not null references staff on delete cascade,
  date         date not null,
  status       text not null default 'present'
    check (status in ('present','absent','late','on_leave','off_site','training')),
  arrived_at   time,
  departed_at  time,
  minutes_late smallint,
  -- Points at the approved leave, so "absent" and "on approved leave" are never
  -- confused. An absence with no note and no leave is the one worth chasing.
  leave_id     uuid references staff_leave on delete set null,
  note         text,
  recorded_by  uuid references staff,
  recorded_at  timestamptz not null default now(),
  unique (staff_id, date)
);
create index on staff_attendance (school_id, date);

alter table staff_attendance enable row level security;
alter table staff_attendance force  row level security;

-- A member of staff may always see their own record.
create policy sattend_read on staff_attendance for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('staff.manage') or staff_id = app.person_id()));

create policy sattend_write on staff_attendance for all to authenticated
using (school_id = app.school_id() and app.has_cap('staff.manage'))
with check (school_id = app.school_id() and app.has_cap('staff.manage'));

create trigger audit_staff_attendance
  after insert or update or delete on staff_attendance
  for each row execute function app.audit_row();

-- ── staff movement ────────────────────────────────────────────────────────
-- Signing out during the day. Distinct from attendance: a teacher at a Ministry
-- meeting is present for the day and off site for two hours, and if a parent
-- arrives asking for them somebody must be able to say where they are.
create table staff_movement (
  id            uuid primary key default gen_random_uuid(),
  school_id     uuid not null references school on delete cascade,
  staff_id      uuid not null references staff on delete cascade,
  date          date not null,
  out_at        time not null,
  in_at         time,
  reason        text not null,
  destination   text,
  authorised_by uuid references staff,
  recorded_at   timestamptz not null default now()
);
create index on staff_movement (school_id, date);

alter table staff_movement enable row level security;
alter table staff_movement force  row level security;

create policy smove_read on staff_movement for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('staff.manage') or staff_id = app.person_id()));

create policy smove_write on staff_movement for all to authenticated
using (school_id = app.school_id() and app.has_cap('staff.manage'))
with check (school_id = app.school_id() and app.has_cap('staff.manage'));

create trigger audit_staff_movement
  after insert or update or delete on staff_movement
  for each row execute function app.audit_row();

-- ── room booking ──────────────────────────────────────────────────────────
-- Ad-hoc use of the hall or a lab outside the timetable. The timetable owns
-- teaching; this owns everything else, and the two must not collide.
create table room_booking (
  id            uuid primary key default gen_random_uuid(),
  school_id     uuid not null references school on delete cascade,
  room_id       uuid not null references room on delete cascade,
  date          date not null,
  starts_at     time not null,
  ends_at       time not null,
  purpose       text not null,
  requested_by  uuid not null references staff,
  approved_by   uuid references staff,
  status        text not null default 'requested'
    check (status in ('requested','approved','declined','cancelled')),
  note          text,
  created_at    timestamptz not null default now(),
  constraint booking_ends_after_it_starts check (ends_at > starts_at)
);
create index on room_booking (school_id, date);

-- Two approved bookings cannot overlap in the same room. An exclusion
-- constraint rather than a trigger, because the database should refuse this
-- rather than a code path remembering to check — the same reasoning as the
-- timetable clash indexes.
create extension if not exists btree_gist;
alter table room_booking add constraint no_overlapping_approved_bookings
  exclude using gist (
    room_id with =,
    date with =,
    public.timerange(starts_at, ends_at) with &&
  ) where (status = 'approved');

alter table room_booking enable row level security;
alter table room_booking force  row level security;

-- Any member of staff can see and request; only a manager approves.
create policy rbook_read on room_booking for select to authenticated
using (school_id = app.school_id());

create policy rbook_request on room_booking for insert to authenticated
with check (school_id = app.school_id()
            and requested_by = app.person_id()
            and status = 'requested');

create policy rbook_own_cancel on room_booking for update to authenticated
using (school_id = app.school_id() and requested_by = app.person_id()
       and status in ('requested','approved'))
with check (school_id = app.school_id() and requested_by = app.person_id());

create policy rbook_manage on room_booking for all to authenticated
using (school_id = app.school_id() and app.has_cap('school.manage'))
with check (school_id = app.school_id() and app.has_cap('school.manage'));

create trigger audit_room_booking
  after insert or update or delete on room_booking
  for each row execute function app.audit_row();

-- ── RPCs ──────────────────────────────────────────────────────────────────

-- Open the staff register for a day, pre-filled present, with anyone on
-- approved leave already marked. Same shape as the pupil register: the common
-- case should need no typing.
create or replace function public.rpc_open_staff_register(p_date date)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_rows int;
begin
  if not app.has_cap('staff.manage') then
    raise exception 'Not authorised to take the staff register';
  end if;
  v_school := app.school_id();

  insert into staff_attendance (school_id, staff_id, date, status, leave_id, recorded_by)
  select v_school, st.id, p_date,
         case when sl.id is not null then 'on_leave' else 'present' end,
         sl.id, app.person_id()
  from staff st
  left join staff_leave sl
    on sl.staff_id = st.id
   and sl.status = 'approved'
   and p_date between sl.starts_on and sl.ends_on
  where st.school_id = v_school and st.exited_on is null
  on conflict (staff_id, date) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

create or replace function public.rpc_mark_staff_attendance(
  p_staff uuid, p_date date, p_status text,
  p_arrived_at time default null, p_note text default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_minutes smallint;
begin
  if not app.has_cap('staff.manage') then
    raise exception 'Not authorised to mark staff attendance';
  end if;
  v_school := app.school_id();
  if not exists (select 1 from staff where id = p_staff and school_id = v_school) then
    raise exception 'Unknown staff member';
  end if;

  if p_status = 'late' and p_arrived_at is not null then
    v_minutes := greatest(0,
      extract(epoch from (p_arrived_at - time '07:40')) / 60)::smallint;
  end if;

  insert into staff_attendance (school_id, staff_id, date, status, arrived_at,
                                minutes_late, note, recorded_by)
  values (v_school, p_staff, p_date, p_status, p_arrived_at, v_minutes, p_note, app.person_id())
  on conflict (staff_id, date) do update set
    status = excluded.status, arrived_at = excluded.arrived_at,
    minutes_late = excluded.minutes_late, note = excluded.note,
    recorded_by = excluded.recorded_by, recorded_at = now();
end $$;

create or replace function public.rpc_sign_staff_out(
  p_staff uuid, p_date date, p_out time, p_reason text, p_destination text default null
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id uuid;
begin
  if not app.has_cap('staff.manage') then
    raise exception 'Not authorised to record staff movement';
  end if;
  insert into staff_movement (school_id, staff_id, date, out_at, reason,
                              destination, authorised_by)
  values (app.school_id(), p_staff, p_date, p_out, p_reason, p_destination, app.person_id())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.rpc_sign_staff_in(p_movement uuid, p_in time)
returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.has_cap('staff.manage') then
    raise exception 'Not authorised to record staff movement';
  end if;
  update staff_movement set in_at = p_in
   where id = p_movement and school_id = app.school_id();
  if not found then raise exception 'Unknown movement record'; end if;
end $$;

-- Approving a booking is where a clash surfaces. The exclusion constraint
-- refuses an overlap with another booking; this also refuses one against the
-- published timetable, which the constraint cannot see.
create or replace function public.rpc_decide_room_booking(
  p_booking uuid, p_approve boolean, p_note text default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare b record; v_clash text;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to decide room bookings';
  end if;

  select * into b from room_booking
   where id = p_booking and school_id = app.school_id();
  if b.id is null then raise exception 'Unknown booking'; end if;

  if p_approve then
    select ss.name into v_clash
    from timetable_slot ts
    join timetable_version tv on tv.id = ts.timetable_version_id and tv.status = 'published'
    join period_definition pd on pd.id = ts.period_id
    join subject_set ss on ss.id = ts.subject_set_id
    join calendar_day cd on cd.date = b.date
                        and cd.academic_year_id = tv.academic_year_id
                        and cd.cycle_day = ts.cycle_day
    where ts.room_id = b.room_id
      and public.timerange(pd.starts_at, pd.ends_at)
          && public.timerange(b.starts_at, b.ends_at)
    limit 1;

    if v_clash is not null then
      raise exception 'That room is timetabled for % at this time', v_clash;
    end if;
  end if;

  update room_booking
     set status = case when p_approve then 'approved' else 'declined' end,
         approved_by = app.person_id(),
         note = coalesce(p_note, note)
   where id = p_booking;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_open_staff_register(date)',
    'public.rpc_mark_staff_attendance(uuid, date, text, time, text)',
    'public.rpc_sign_staff_out(uuid, date, time, text, text)',
    'public.rpc_sign_staff_in(uuid, time)',
    'public.rpc_decide_room_booking(uuid, boolean, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
