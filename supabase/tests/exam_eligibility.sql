-- EduMU :: Attendance summaries and exam eligibility screening.
--
-- "The school should insist on at least 80% attendance from students prior to
--  July mock examinations, end of year internal examinations and during the
--  third term." — School Management Manual 4.5.3
--
-- Run against a Supabase branch. Every row must read PASS.
-- NOTE: this suite mutates demo data (it debars a pupil and amends one
-- register). Run it on a branch you can throw away.

create temp table if not exists el(test text, expected text, got text, pass boolean);
truncate el;

do $$
declare
  v_school uuid; v_p uuid; v_g uuid; v_caps jsonb; v_sess uuid;
  v_s4 uuid; v_s5 uuid; n int; v_pct numeric; v_calc numeric; v_rec text;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_p from person where email='a.ramdin@demo-sss.mu';
  select id into v_g from person where person_type='guardian' limit 1;
  select id into v_sess from exam_session where kind='end_of_term' limit 1;
  select coalesce(jsonb_agg(distinct rc.capability_code),'[]'::jsonb) into v_caps
  from staff_role_assignment sra join role_capability rc on rc.role_code=sra.role_code
  where sra.staff_id=v_p;

  select ce.student_id into v_s4 from class_enrolment ce where ce.roll_number=4 limit 1;
  select ce.student_id into v_s5 from class_enrolment ce where ce.roll_number=5 limit 1;

  -- The stored percentage must match the definition the rules rely on.
  select sm.pct_present, round(100.0*sm.sessions_present/sm.sessions_possible, 2)
    into v_pct, v_calc
  from attendance_summary sm join term t on t.id=sm.term_id and t.sequence=1
  where sm.student_id = v_s4;
  insert into el values ('pct_present = present / possible', v_calc::text, v_pct::text, v_pct = v_calc);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  v_caps)::text, true);

  -- Debarring a candidate is serious: no silent debarment without a reason.
  set local role authenticated;
  begin
    perform rpc_decide_eligibility(v_sess, v_s4, 'debar', '   ');
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into el values ('Debar without a reason','raises (1)',n::text,n=1);

  -- The decision snapshots the figure it was based on, so a later amendment
  -- cannot retrospectively change what the Rector was looking at.
  set local role authenticated;
  perform rpc_decide_eligibility(v_sess, v_s4, 'debar', 'Repeated unauthorised absence');
  reset role;
  select d.attendance_pct into v_pct from exam_eligibility_decision d
   where d.exam_session_id=v_sess and d.student_id=v_s4;
  insert into el values ('Debar snapshots the attendance figure', v_calc::text, v_pct::text, v_pct = v_calc);

  -- The threshold is school policy stored as data, never a constant in code.
  update school set settings = jsonb_set(settings,'{exam_eligibility_pct}','95')
   where id = v_school;
  set local role authenticated;
  select recommended into v_rec from exam_eligibility_screen(v_sess) where student_id = v_s5;
  select count(*) into n from exam_eligibility_screen(v_sess) where recommended='review';
  reset role;
  insert into el values ('Pupil above the raised threshold still allowed','allow',v_rec,v_rec='allow');
  insert into el values ('Raising the threshold reflags pupils','4',n::text,n=4);
  update school set settings = jsonb_set(settings,'{exam_eligibility_pct}','80')
   where id = v_school;

  -- Guardians see decisions about their own ward and nothing else. The
  -- screening function filters to zero rather than erroring — the same safe
  -- failure mode as discrepancy_feed.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from exam_eligibility_screen(v_sess);
  reset role;
  insert into el values ('Guardian runs the screening','0 rows',n::text,n=0);

  -- The maintenance trigger keeps the summary live between nightly rebuilds.
  select sm.sessions_present into n from attendance_summary sm
   join term t on t.id=sm.term_id and t.sequence=1 where sm.student_id=v_s5;
  update attendance_record ar set status='absent_unauth'
   from attendance_session s
  where s.id=ar.attendance_session_id and ar.student_id=v_s5
    and s.date='2026-02-03' and s.session='am';
  select sm.sessions_present into v_calc from attendance_summary sm
   join term t on t.id=sm.term_id and t.sequence=1 where sm.student_id=v_s5;
  insert into el values ('Trigger decrements the summary on amendment',(n-1)::text,v_calc::text,v_calc=n-1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from el;
