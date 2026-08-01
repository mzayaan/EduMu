-- EduMU :: Message thread privacy.
--
-- Regression for a hole the Supabase advisor caught: thread_participant's write
-- policy was WITH CHECK (true), so any staff member could add themselves to a
-- conversation between another teacher and a parent about a third pupil, and
-- then read every message in it.
--
-- The fix also had to break an RLS recursion: a policy on thread_participant
-- that queries thread_participant re-enters its own policy. Membership is now
-- answered by app.in_thread(), a narrow SECURITY DEFINER helper.
--
-- Every row must read PASS.

create temp table if not exists tp(test text, expected text, got text, pass boolean);
truncate tp;

do $$
declare v_school uuid; v_a uuid; v_b uuid; v_g uuid; v_thread uuid; n int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_a from person where email='a.ramdin@demo-sss.mu';
  select id into v_b from person where email='d.callychurn@demo-sss.mu';
  select id into v_g from person where person_type='guardian' limit 1;

  insert into message_thread (school_id, subject, created_by)
  values (v_school, 'Attendance concern', v_a) returning id into v_thread;
  insert into thread_participant (thread_id, person_id) values (v_thread, v_a), (v_thread, v_g);
  insert into message (school_id, thread_id, sender_id, body)
  values (v_school, v_thread, v_a, 'Could we discuss last week''s absences?');

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_b,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  jsonb_build_array('attendance.mark'))::text, true);
  set local role authenticated;
  begin
    insert into thread_participant (thread_id, person_id) values (v_thread, v_b);
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into tp values ('Uninvolved staff adds self to a thread','denied (1)',n::text,n=1);

  set local role authenticated;
  select count(*) into n from message where thread_id = v_thread;
  reset role;
  insert into tp values ('Uninvolved staff reads the messages','0',n::text,n=0);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from message where thread_id = v_thread;
  reset role;
  insert into tp values ('Parent in the thread reads it','1',n::text,n=1);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_a,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  jsonb_build_array('attendance.mark'))::text, true);
  set local role authenticated;
  begin
    insert into thread_participant (thread_id, person_id) values (v_thread, v_b);
    n := 1;
  exception when others then n := 0; end;
  reset role;
  insert into tp values ('Existing participant may invite another','allowed (1)',n::text,n=1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from tp;
