-- EduMU :: Scheme of Work workflow.
--
-- "Request Educators to submit schemes of work through Heads of Departments by
--  the second week of the term" — School Management Manual 6.1.1. The HOD vets
--  before the Rector approves, so this is a three-party workflow and each hop
--  is enforced server-side rather than by hiding a button.
--
-- Every row must read PASS.

create temp table if not exists cw(test text, expected text, got text, pass boolean);
truncate cw;

do $$
declare
  v_school uuid; v_year uuid; v_t1 uuid; v_set uuid; v_ed uuid; v_hod uuid;
  v_scheme uuid; v_ed_caps jsonb; n int; v_status text;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_year from academic_year where school_id=v_school and name='2026';
  select id into v_t1 from term where academic_year_id=v_year and sequence=1;
  select id into v_set from subject_set where name='G7 Mathematics Set 1';
  select id into v_ed from person where email='a.ramdin@demo-sss.mu';
  select id into v_hod from person where email='d.callychurn@demo-sss.mu';
  select coalesce(jsonb_agg(distinct capability_code),'[]'::jsonb) into v_ed_caps
    from role_capability where role_code='educator';

  insert into scheme_of_work (school_id, academic_year_id, subject_set_id, staff_id, term_id, due_on)
  values (v_school, v_year, v_set, v_ed, v_t1, '2026-01-23')
  on conflict (subject_set_id, term_id) do update set status='draft'
  returning id into v_scheme;
  delete from scheme_week where scheme_of_work_id = v_scheme;

  -- A scheme with no weeks is not a plan.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ed,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  v_ed_caps)::text, true);
  set local role authenticated;
  begin perform rpc_submit_scheme(v_scheme); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into cw values ('Submit a scheme with no weeks','raises (1)',n::text,n=1);

  insert into scheme_week (school_id, scheme_of_work_id, week_no, objectives)
  values (v_school, v_scheme, 1, 'Number systems and place value'),
         (v_school, v_scheme, 2, 'Operations on integers');

  set local role authenticated;
  perform rpc_submit_scheme(v_scheme);
  reset role;
  select status::text into v_status from scheme_of_work where id=v_scheme;
  insert into cw values ('Educator submits to the HOD','submitted',v_status,v_status='submitted');

  -- The Rector cannot skip the Head of Department.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ed,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  jsonb_build_array('school.manage','marks.moderate'))::text, true);
  set local role authenticated;
  begin perform rpc_approve_scheme(v_scheme); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into cw values ('Rector approves before HOD vetting','raises (1)',n::text,n=1);

  -- Returning work demands something the educator can act on.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_hod,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','hod','s','department')),
    'caps',  jsonb_build_array('marks.moderate'))::text, true);
  set local role authenticated;
  begin perform rpc_review_scheme(v_scheme, false, '  '); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into cw values ('Return a scheme with no comment','raises (1)',n::text,n=1);

  set local role authenticated;
  perform rpc_review_scheme(v_scheme, true, 'Good coverage of the term');
  reset role;
  select status::text into v_status from scheme_of_work where id=v_scheme;
  insert into cw values ('HOD vets it','hod_approved',v_status,v_status='hod_approved');

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ed,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  jsonb_build_array('school.manage'))::text, true);
  set local role authenticated;
  perform rpc_approve_scheme(v_scheme);
  reset role;
  select status::text into v_status from scheme_of_work where id=v_scheme;
  insert into cw values ('Rector approves','rector_approved',v_status,v_status='rector_approved');

  -- Authorship matters: a colleague cannot submit your scheme.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_hod,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  v_ed_caps)::text, true);
  set local role authenticated;
  begin perform rpc_submit_scheme(v_scheme); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into cw values ('Another educator submits your scheme','raises (1)',n::text,n=1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from cw;
