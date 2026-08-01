-- EduMU :: Assessment — publication gating, mark history, aggregation.
--
-- The load-bearing rule: nothing reaches a pupil or a Responsible Party before
-- the Rector publishes. Premature leakage of marks is a real reputational risk
-- for a school, and it is enforced in RLS, not in the UI.
--
-- Run against a Supabase branch. Every row must read PASS.
-- NOTE: derive expected counts from the data, never hand-count. An earlier
-- version of this suite failed because the author assumed 5 assessments where
-- the fixture has 15 marks per ward across 5 sets.

create temp table if not exists mk(test text, expected text, got text, pass boolean);
truncate mk;

do $$
declare
  v_school uuid; v_p uuid; v_g uuid; v_s1 uuid; v_set uuid; v_t1 uuid;
  v_a uuid; v_mark uuid; v_caps jsonb; v_ed_caps jsonb;
  n int; n_before int; n_hidden int; v_calc numeric; v_agg numeric;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_p from person where email='a.ramdin@demo-sss.mu';
  select id into v_g from person where person_type='guardian' limit 1;
  select student_id into v_s1 from class_enrolment where roll_number=1 limit 1;
  select t.id into v_t1 from term t join academic_year y on y.id=t.academic_year_id
   where y.name='2026' and t.sequence=1;
  select ss.id into v_set from subject_set ss where ss.name='G7 Mathematics Set 1';

  select coalesce(jsonb_agg(distinct capability_code),'[]'::jsonb) into v_ed_caps
  from role_capability where role_code='educator';
  v_caps := v_ed_caps || jsonb_build_array('marks.moderate','marks.publish','marks.read.all');

  -- The weighted aggregate must match the documented formula exactly:
  --   Σ(score/max × weight) / Σ(weight) × 100
  select round(100.0 * sum((m.score / a.max_score) * a.weight) / sum(a.weight), 2)
    into v_calc
  from mark m join assessment a on a.id = m.assessment_id
  where a.term_id = v_t1 and a.subject_set_id = v_set and m.student_id = v_s1;
  select tr.aggregate_score into v_agg from term_result tr
   join subject s on s.id = tr.subject_id
   where tr.student_id = v_s1 and tr.term_id = v_t1 and s.code='MATH';
  insert into mk values ('Weighted aggregate matches the formula', v_calc::text, v_agg::text, v_agg = v_calc);

  -- Guardian visibility is driven entirely by assessment.status.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n_before from mark;
  reset role;

  select id into v_a from assessment
   where subject_set_id=v_set and term_id=v_t1 and kind='end_of_term';
  select count(*) into n_hidden from mark m
   join student_guardian sg on sg.student_id=m.student_id
   where m.assessment_id=v_a and sg.guardian_id=v_g;

  update assessment set status='moderated' where id=v_a;
  set local role authenticated;
  select count(*) into n from mark;
  reset role;
  insert into mk values ('Unpublishing hides exactly that assessment''s marks',
                         (n_before - n_hidden)::text, n::text, n = n_before - n_hidden);

  update assessment set status='published' where id=v_a;
  set local role authenticated;
  select count(*) into n from mark;
  reset role;
  insert into mk values ('Republishing restores visibility', n_before::text, n::text, n = n_before);

  -- Separation of duties: the teacher who marked cannot publish.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  v_ed_caps)::text, true);
  set local role authenticated;
  begin
    perform rpc_set_assessment_status(v_a, 'published');
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into mk values ('Educator publishes their own marks','raises (1)',n::text,n=1);

  -- Once submitted, marks are out of the teacher's hands.
  update assessment set status='submitted' where id=v_a;
  select m.id into v_mark from mark m where m.assessment_id=v_a limit 1;
  set local role authenticated;
  begin
    update mark set score = 1 where id = v_mark;
    get diagnostics n = row_count;
  exception when others then n := -1; end;
  reset role;
  insert into mk values ('Educator edits a submitted mark','0 rows',n::text,n=0);

  -- Amendment after submission is a recorded act.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  begin
    perform rpc_amend_mark(v_mark, 55, null, '');
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into mk values ('Amend a mark without a reason','raises (1)',n::text,n=1);

  set local role authenticated;
  perform rpc_amend_mark(v_mark, 55, null, 'Transcription error on the script');
  reset role;
  select count(*) into n from mark_history
   where mark_id = v_mark and reason = 'Transcription error on the script';
  insert into mk values ('Amendment is written to mark_history','1',n::text,n=1);

  update assessment set status='published' where id=v_a;
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from mk;
