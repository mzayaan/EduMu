-- EduMU :: promotion engine, year rollover, staff attendance, room booking.
--
-- Covers migrations 56–58, which closed the four subsystems BLUEPRINT-AUDIT.md
-- found specified and unbuilt.
--
-- The rollover section builds a throwaway next year, rolls into it, asserts,
-- and then puts everything back. It has to: rollover closes the active year and
-- opens another, which would break every other suite that assumes 2026 is
-- active. The teardown is not tidiness, it is a precondition.

create temp table if not exists t(area text, check_name text, got text, want text, verdict text);
truncate t;

-- Several assertions are made while `set local role authenticated` is still in
-- force — that is the point of them. The temp table is owned by postgres, so
-- without this grant the recording of a result fails rather than the thing
-- being tested, and the whole suite reports one misleading error.
grant all on t to authenticated;

create or replace function pg_temp.chk(a text, c text, got text, want text) returns void
language sql as $$
  insert into t values (a, c, got, want, case when got = want then 'ok' else 'FAIL' end);
$$;

do $$
declare
  sch uuid; rector uuid; usher uuid; teacher uuid; yr uuid; nxt uuid;
  n int; res jsonb; v_room uuid; v_book uuid; v_staff uuid; pupil uuid;
  outcome text; before_repeats int; after_repeats int; err text;
begin
  select id into sch from school where code = 'DEMO-SSS';
  -- Any serving staff member. Authorisation comes from the caps array below,
  -- not from this person's real assignments, so the identity only needs to be a
  -- staff row that foreign keys will accept. Looking up an actual 'rector'
  -- assignment returned NULL on the demo tenant, and because an exception
  -- rolls the whole DO block back, that one NULL discarded every result the
  -- suite had already recorded and reported as a single unrelated error.
  select id into rector from staff where school_id = sch order by staff_number limit 1;
  select id into yr from academic_year
    where school_id = sch order by (status = 'active') desc, starts_on desc limit 1;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id', sch, 'person_id', rector, 'person_type', 'staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps', jsonb_build_array('marks.moderate','marks.publish','school.manage',
                              'staff.manage','attendance.resolve')
  )::text, true);

  -- ── promotion ─────────────────────────────────────────────────────────
  perform pg_temp.chk('promotion', 'default rules seeded for every grade 7-13',
    (select count(distinct grade)::text from promotion_rule where academic_year_id = yr), '7');

  set local role authenticated;
  n := rpc_evaluate_promotions(yr);
  reset role;

  perform pg_temp.chk('promotion', 'every enrolled pupil got a decision',
    (select count(*)::text from promotion_decision where academic_year_id = yr),
    (select count(*)::text from student st
      join class_enrolment ce on ce.student_id = st.id and ce.effective_to is null
      join class_group cg on cg.id = ce.class_group_id
      where st.school_id = sch and cg.academic_year_id = yr and st.status = 'enrolled'));

  perform pg_temp.chk('promotion', 'facts were frozen with the decision',
    (select case when count(*) = 0 then 'all have facts' else 'some empty' end::text
     from promotion_decision where academic_year_id = yr and facts = '{}'::jsonb),
    'all have facts');

  -- An override needs a reason. The constraint, not the UI, is what enforces it.
  begin
    insert into promotion_decision (school_id, academic_year_id, student_id,
                                    outcome, override_outcome, override_reason)
    select sch, yr, gen_random_uuid(), 'promote', 'repeat', '   ';
    perform pg_temp.chk('promotion', 'blank override reason refused', 'accepted', 'refused');
  exception when others then
    perform pg_temp.chk('promotion', 'blank override reason refused', 'refused', 'refused');
  end;

  -- The override is what rollover must act on, not the engine's verdict.
  select student_id into pupil from promotion_decision where academic_year_id = yr limit 1;
  set local role authenticated;
  perform rpc_override_promotion(pupil, yr, 'repeat', 'Rector: pupil was ill for most of term 3');
  reset role;

  perform pg_temp.chk('promotion', 'effective outcome follows the override',
    (select effective_outcome::text from promotion_screen
      where student_id = pupil and academic_year_id = yr), 'repeat');

  -- ── rollover ──────────────────────────────────────────────────────────
  insert into academic_year (school_id, name, starts_on, ends_on, status)
  values (sch, '__rollover_test__', date '2099-01-11', date '2099-12-03', 'planning')
  returning id into nxt;

  set local role authenticated;

  -- Must refuse while anything is unconfirmed.
  begin
    res := rpc_rollover_year(yr, nxt, false);
    perform pg_temp.chk('rollover', 'refuses unconfirmed decisions', 'ran', 'refused');
  exception when others then
    perform pg_temp.chk('rollover', 'refuses unconfirmed decisions', 'refused', 'refused');
  end;

  perform rpc_confirm_promotions(yr);

  -- Confirmed decisions must survive a re-evaluation.
  n := rpc_evaluate_promotions(yr);
  reset role;
  perform pg_temp.chk('promotion', 're-evaluating does not overwrite a confirmed decision',
    (select effective_outcome::text from promotion_screen
      where student_id = pupil and academic_year_id = yr), 'repeat');

  set local role authenticated;

  -- Nowhere to place anyone yet: next year has no classes.
  res := rpc_rollover_year(yr, nxt, false);
  perform pg_temp.chk('rollover', 'reports pupils it cannot place',
    case when (res ->> 'unplaced_count')::int > 0 then 'reported' else 'silent' end, 'reported');

  reset role;
  insert into class_group (school_id, academic_year_id, grade_level_id, name, stream)
  select distinct sch, nxt, gl2.id, '__rt__' || gl2.grade, cg.stream
  from class_enrolment ce
  join class_group cg on cg.id = ce.class_group_id
  join grade_level gl on gl.id = cg.grade_level_id
  join grade_level gl2 on gl2.school_id = sch and gl2.grade in (gl.grade, gl.grade + 1)
  where ce.effective_to is null and cg.academic_year_id = yr;

  set local role authenticated;
  res := rpc_rollover_year(yr, nxt, false);
  perform pg_temp.chk('rollover', 'dry run places everyone once classes exist',
    (res ->> 'unplaced_count'), '0');

  -- A dry run must not touch anything.
  reset role;
  perform pg_temp.chk('rollover', 'dry run changes nothing',
    (select count(*)::text from class_enrolment ce
      join class_group cg on cg.id = ce.class_group_id where cg.academic_year_id = nxt), '0');

  select coalesce(sum(times_repeated), 0) into before_repeats from student where school_id = sch;

  set local role authenticated;
  res := rpc_rollover_year(yr, nxt, true);
  reset role;

  perform pg_temp.chk('rollover', 'commit moved everyone into the next year',
    (select count(distinct ce.student_id)::text from class_enrolment ce
      join class_group cg on cg.id = ce.class_group_id
      where cg.academic_year_id = nxt and ce.effective_to is null),
    ((res ->> 'promoted')::int + (res ->> 'repeated')::int)::text);

  perform pg_temp.chk('rollover', 'old year was closed',
    (select status::text from academic_year where id = yr), 'closed');
  perform pg_temp.chk('rollover', 'new year was opened',
    (select status::text from academic_year where id = nxt), 'active');

  select coalesce(sum(times_repeated), 0) into after_repeats from student where school_id = sch;
  perform pg_temp.chk('rollover', 'repeaters had times_repeated incremented',
    (after_repeats - before_repeats)::text, (res ->> 'repeated'));

  perform pg_temp.chk('rollover', 'next year got its own promotion rules',
    case when exists (select 1 from promotion_rule where academic_year_id = nxt)
         then 'seeded' else 'missing' end, 'seeded');

  -- ── teardown, before the operations checks ────────────────────────────
  delete from academic_year where id = nxt;      -- cascades classes + enrolments
  update class_enrolment ce set effective_to = null
    from class_group cg
   where cg.id = ce.class_group_id and cg.academic_year_id = yr
     and ce.effective_to is not null;
  update academic_year set status = 'active' where id = yr;
  update student set times_repeated = 0 where school_id = sch;
  update promotion_decision set confirmed_at = null, confirmed_by = null,
         override_outcome = null, override_reason = null, override_by = null,
         override_at = null
   where academic_year_id = yr;

  perform pg_temp.chk('rollover', 'teardown restored the active year',
    (select status::text from academic_year where id = yr), 'active');

  -- ── staff attendance ──────────────────────────────────────────────────
  set local role authenticated;
  n := rpc_open_staff_register(date '2026-03-02');
  reset role;

  perform pg_temp.chk('staff', 'register opened for every serving member',
    (select count(*)::text from staff_attendance where date = date '2026-03-02'),
    (select count(*)::text from staff where school_id = sch and exited_on is null));

  select id into v_staff from staff where school_id = sch limit 1;
  set local role authenticated;
  perform rpc_mark_staff_attendance(v_staff, date '2026-03-02', 'late', time '08:20');
  reset role;

  perform pg_temp.chk('staff', 'lateness computed from the start of the day',
    (select minutes_late::text from staff_attendance
      where staff_id = v_staff and date = date '2026-03-02'), '40');

  set local role authenticated;
  v_book := rpc_sign_staff_out(v_staff, date '2026-03-02', time '10:00', 'Ministry meeting');
  perform rpc_sign_staff_in(v_book, time '12:30');
  reset role;

  perform pg_temp.chk('staff', 'movement records a return time',
    (select to_char(in_at, 'HH24:MI') from staff_movement where id = v_book), '12:30');

  -- ── room booking ──────────────────────────────────────────────────────
  select id into v_room from room where school_id = sch limit 1;

  insert into room_booking (school_id, room_id, date, starts_at, ends_at,
                            purpose, requested_by, status)
  values (sch, v_room, date '2099-06-01', time '14:00', time '15:00',
          'Test booking A', rector, 'approved')
  returning id into v_book;

  -- The exclusion constraint, not a trigger and not the client, is what refuses
  -- a double booking.
  begin
    insert into room_booking (school_id, room_id, date, starts_at, ends_at,
                              purpose, requested_by, status)
    values (sch, v_room, date '2099-06-01', time '14:30', time '15:30',
            'Overlapping B', rector, 'approved');
    perform pg_temp.chk('rooms', 'overlapping approved booking refused', 'accepted', 'refused');
  exception when others then
    perform pg_temp.chk('rooms', 'overlapping approved booking refused', 'refused', 'refused');
  end;

  -- A merely requested booking may overlap; only approval is exclusive.
  begin
    insert into room_booking (school_id, room_id, date, starts_at, ends_at,
                              purpose, requested_by, status)
    values (sch, v_room, date '2099-06-01', time '14:30', time '15:30',
            'Requested overlap', rector, 'requested');
    perform pg_temp.chk('rooms', 'requested booking may overlap', 'accepted', 'accepted');
  exception when others then
    perform pg_temp.chk('rooms', 'requested booking may overlap', 'refused', 'accepted');
  end;

  begin
    insert into room_booking (school_id, room_id, date, starts_at, ends_at,
                              purpose, requested_by)
    values (sch, v_room, date '2099-06-02', time '15:00', time '14:00',
            'Backwards', rector);
    perform pg_temp.chk('rooms', 'end before start refused', 'accepted', 'refused');
  exception when others then
    perform pg_temp.chk('rooms', 'end before start refused', 'refused', 'refused');
  end;

  delete from room_booking where date between date '2099-06-01' and date '2099-06-02';
  delete from staff_attendance where date = date '2026-03-02';
  delete from staff_movement where date = date '2026-03-02';

exception when others then
  reset role;
  insert into t values ('SUITE', 'ran to completion', sqlerrm, 'no error', 'FAIL');
end $$;

-- ── RLS: a teacher must not read another member's attendance ─────────────
do $$
declare sch uuid; a uuid; b uuid; seen int;
begin
  select id into sch from school where code = 'DEMO-SSS';
  select id into a from staff where school_id = sch order by staff_number limit 1;
  select id into b from staff where school_id = sch and id <> a order by staff_number limit 1;

  insert into staff_attendance (school_id, staff_id, date, status)
  values (sch, a, date '2026-03-03', 'present'), (sch, b, date '2026-03-03', 'absent')
  on conflict do nothing;

  -- A teacher with no staff.manage capability.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id', sch, 'person_id', a, 'person_type', 'staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps', jsonb_build_array('marks.enter')
  )::text, true);
  set local role authenticated;
  select count(*) into seen from staff_attendance where date = date '2026-03-03';
  reset role;

  insert into t values ('staff', 'teacher sees only their own attendance',
    seen::text, '1', case when seen = 1 then 'ok' else 'FAIL' end);

  delete from staff_attendance where date = date '2026-03-03';
end $$;

select area, check_name, got, want, verdict from t order by verdict desc, area, check_name;

select case
         when exists (select 1 from t where verdict <> 'ok')
         then 'FAIL — ' || (select count(*) from t where verdict <> 'ok')::text || ' check(s) failed'
         else 'PASS — ' || (select count(*) from t)::text || ' checks'
       end as result;
