-- EduMU :: RLS and behaviour tests for the Usher's discrepancy board.
-- Run against a Supabase branch. Every row must read PASS.
--
-- NOTE on capability sets: build them from role_capability rather than by hand.
-- discrepancy_feed is security_invoker and inner-joins person and student, so a
-- caller with attendance.read.all but without person.read.all / student.read.all
-- sees an EMPTY board rather than an error. Hand-written caps in a test will
-- produce a false failure — this is exactly how it was found.

create temp table if not exists dr(test text, expected text, got text, pass boolean);
truncate dr;

do $$
declare
  v_school uuid; v_usher uuid; v_student uuid; v_caps jsonb; n int; v_total int;
begin
  select id into v_school  from school where code='DEMO-SSS';
  select id into v_usher   from person where email='a.ramdin@demo-sss.mu';
  select student_id into v_student from class_enrolment where roll_number=1 limit 1;
  select count(*) into v_total from attendance_discrepancy;

  select coalesce(jsonb_agg(capability_code),'[]'::jsonb) into v_caps
  from role_capability where role_code='usher';

  -- The Usher, with the capabilities the role actually grants, sees the board.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_usher,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  select count(*) into n from discrepancy_feed;
  reset role;
  insert into dr values ('Usher sees the discrepancy board', v_total::text, n::text, n = v_total);

  -- attendance.read.all on its own is not sufficient — see the note above.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_usher,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',  jsonb_build_array('attendance.read.all','attendance.resolve'))::text, true);
  set local role authenticated;
  select count(*) into n from discrepancy_feed;
  reset role;
  insert into dr values ('attendance.read.all alone yields an empty board','0',n::text,n=0);

  -- A pupil must never see the board.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_student,'person_type','student',
    'roles', jsonb_build_array(jsonb_build_object('c','student','s','self')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from discrepancy_feed;
  reset role;
  insert into dr values ('Student reads the discrepancy board','0',n::text,n=0);

  -- A plain Educator must not see it either.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_usher,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  jsonb_build_array('marks.enter','attendance.mark'))::text, true);
  set local role authenticated;
  select count(*) into n from discrepancy_feed;
  reset role;
  insert into dr values ('Educator reads the discrepancy board','0',n::text,n=0);

  -- Resolving requires attendance.resolve.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_usher,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  jsonb_build_array('marks.enter'))::text, true);
  set local role authenticated;
  begin
    perform rpc_resolve_discrepancy(
      (select id from attendance_discrepancy limit 1), 'found_on_premises');
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into dr values ('Resolve without attendance.resolve','raises (1)',n::text,n=1);

  -- Outcomes are a closed set.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_usher,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  begin
    perform rpc_resolve_discrepancy(
      (select id from attendance_discrepancy limit 1), 'went_home_early');
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into dr values ('Invalid outcome rejected','raises (1)',n::text,n=1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from dr;
