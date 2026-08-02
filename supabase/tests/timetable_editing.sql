-- EduMU :: Manual timetable editing.
--
-- Migration 05 declared that student clashes "are checked by a trigger against
-- set_enrolment (can't be a unique index)". That trigger was never created.
-- The solver avoids pupil clashes and the UI validator catches them, so nothing
-- surfaced it — until drag-and-drop editing made a direct write possible.
-- Migration 48 finally adds it. These assertions exist so it cannot go missing
-- again.
--
-- The three hard constraints and where each lives:
--   room clash    tt_no_room_clash              unique index
--   staff clash   tt_no_staff_clash             unique index
--   pupil clash   timetable_slot_student_clash  trigger (needs enrolment overlap)
--
-- WRITING THESE TESTS — two traps this suite already fell into:
--
--   1. Do not hard-code a target slot. An earlier version moved a lesson to
--      "day 4, P8" and failed because a previous run had left a lesson there.
--      Search for a genuinely free slot instead. In this fixture every G7 set
--      shares all five pupils and one teacher, so ONLY a completely empty slot
--      can legally accept a move.
--   2. Assert deltas, not absolutes. An earlier version asserted the tray held
--      exactly one outstanding lesson; the set was over-placed from prior churn,
--      so the count was right and the assertion was wrong.
--
-- The suite restores what it changes, so it can be run repeatedly.
--
-- Every row must read PASS.

create temp table if not exists tt(test text, expected text, got text, pass boolean);
truncate tt;

do $$
declare
  sch uuid; p uuid; caps jsonb; v_ver uuid; v_prev text;
  v_slot uuid; v_other uuid; v_day smallint; v_period uuid; v_set uuid;
  free_day smallint; free_period uuid;
  required int; before_placed int; after_placed int; n int;
begin
  select id into sch from school where code='DEMO-SSS';
  select id into p   from person where email='a.ramdin@demo-sss.mu';
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps
   from role_capability where role_code='rector';

  select tv.id, tv.status into v_ver, v_prev
  from timetable_version tv join academic_year y on y.id = tv.academic_year_id
  where y.name='2026' order by tv.version desc limit 1;

  -- Editing needs a draft. The original status is restored at the end.
  update timetable_version set status='draft' where id = v_ver;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',p,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',caps)::text, true);

  select ts.id, ts.cycle_day, ts.period_id, ts.subject_set_id
    into v_slot, v_day, v_period, v_set
  from timetable_slot ts where ts.timetable_version_id = v_ver and ts.cycle_day = 1 limit 1;

  select ts.id into v_other from timetable_slot ts
  where ts.timetable_version_id = v_ver and ts.cycle_day = 2
    and ts.subject_set_id <> v_set limit 1;

  select d.day, pd.id into free_day, free_period
  from generate_series(1,5) d(day)
  cross join period_definition pd
  where pd.timetable_version_id = v_ver and pd.is_teaching
    and not exists (select 1 from timetable_slot ts
      where ts.timetable_version_id = v_ver
        and ts.cycle_day = d.day and ts.period_id = pd.id)
  limit 1;

  insert into tt values ('Fixture has a free slot to move into','found',
    coalesce(free_day::text,'none'), free_day is not null);

  -- The clash the trigger exists for.
  set local role authenticated;
  begin perform rpc_move_timetable_slot(v_other, v_day, v_period, null); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into tt values ('Pupil clash refused on a manual move','raises (1)',n::text,n=1);

  -- A refused move must not half-apply.
  select count(*) into n from timetable_slot
   where id = v_other and cycle_day = v_day and period_id = v_period;
  insert into tt values ('Refused move leaves the lesson untouched','0',n::text,n=0);

  set local role authenticated;
  begin perform rpc_move_timetable_slot(v_slot, free_day, free_period, null); n := 1;
  exception when others then n := 0; end;
  reset role;
  insert into tt values ('Legal move into a free slot succeeds','allowed (1)',n::text,n=1);

  -- Removing returns the requirement to the tray rather than discarding it.
  select ss.periods_per_cycle into required from subject_set ss where ss.id = v_set;
  select count(*) into before_placed from timetable_slot
   where timetable_version_id = v_ver and subject_set_id = v_set;

  set local role authenticated;
  perform rpc_remove_lesson(v_slot);
  reset role;

  select count(*) into after_placed from timetable_slot
   where timetable_version_id = v_ver and subject_set_id = v_set;
  insert into tt values ('Removing decrements the placed count',
    (before_placed-1)::text, after_placed::text, after_placed = before_placed - 1);

  select coalesce(max(outstanding),0) into n from unplaced_lessons(v_ver)
   where subject_set_id = v_set;
  insert into tt values ('Tray outstanding equals required minus placed',
    greatest(0, required - after_placed)::text, n::text,
    n = greatest(0, required - after_placed));

  -- ...and it can be placed again from there.
  set local role authenticated;
  begin perform rpc_place_lesson(v_ver, v_set, free_day, free_period, null); n := 1;
  exception when others then n := 0; end;
  reset role;
  insert into tt values ('Lesson can be placed from the tray','allowed (1)',n::text,n=1);

  select count(*) into n from timetable_slot
   where timetable_version_id = v_ver and subject_set_id = v_set;
  insert into tt values ('Fixture restored', before_placed::text, n::text, n = before_placed);

  -- Published timetables are immutable: historical lesson attendance resolves
  -- against the version in force on its own date.
  update timetable_version set status='published' where id = v_ver;
  set local role authenticated;
  begin perform rpc_move_timetable_slot(v_slot, 3::smallint, v_period, null); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into tt values ('Published timetable refuses edits','raises (1)',n::text,n=1);
  update timetable_version set status='draft' where id = v_ver;

  -- Timetabling is the Deputy Rector's job, not an Educator's.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',p,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',(select coalesce(jsonb_agg(distinct capability_code),'[]')
            from role_capability where role_code='educator'))::text, true);
  set local role authenticated;
  begin perform rpc_move_timetable_slot(v_slot, 5::smallint, v_period, null); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into tt values ('Educator cannot move a lesson','raises (1)',n::text,n=1);

  update timetable_version set status = v_prev where id = v_ver;
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from tt;
