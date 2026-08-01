-- EduMU :: End-to-end test of the attendance-card loop.
--
-- Educator prefills a lesson from the morning register → marks a pupil absent →
-- the trigger detects the mismatch → it appears on the Usher's board.
-- This is the digitised version of the physical attendance card the Usher
-- issues to Class Captains each morning.
--
-- Run against a Supabase branch. Every row must read PASS.

create temp table if not exists lp(test text, expected text, got text, pass boolean);
truncate lp;

do $$
declare
  v_school uuid; v_p uuid; v_other uuid; v_caps jsonb;
  v_slot uuid; v_set uuid; v_student uuid; n int; before_n int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_p     from person where email='a.ramdin@demo-sss.mu';
  select id into v_other from person where email='d.callychurn@demo-sss.mu';

  -- Always build capabilities from role_capability, never by hand.
  select coalesce(jsonb_agg(distinct rc.capability_code),'[]'::jsonb) into v_caps
  from staff_role_assignment sra join role_capability rc on rc.role_code=sra.role_code
  where sra.staff_id = v_p;

  select ts.id, ts.subject_set_id into v_slot, v_set
  from timetable_slot ts
  join subject_set ss on ss.id = ts.subject_set_id
  join subject s on s.id = ss.subject_id
  join period_definition pd on pd.id = ts.period_id
  where ts.cycle_day = 2 and s.code = 'BIO' and pd.name = 'P2';

  select count(*) into before_n from attendance_discrepancy;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  v_caps)::text, true);

  set local role authenticated;
  select rpc_prefill_period(v_slot, v_set, '2026-01-13') into n;
  reset role;
  insert into lp values ('Prefill creates one row per enrolled pupil','5',n::text,n=5);

  -- A teacher tapping twice must not duplicate the lesson register.
  set local role authenticated;
  select rpc_prefill_period(v_slot, v_set, '2026-01-13') into n;
  reset role;
  insert into lp values ('Prefill is idempotent','0',n::text,n=0);

  -- Carrying the register forward must generate no false alerts, or the
  -- Usher's board becomes noise and stops being read.
  select count(*) into n from attendance_discrepancy;
  insert into lp values ('Prefill alone raises no discrepancy', before_n::text, n::text, n = before_n);

  -- A pupil present this morning leaves the lesson.
  select ce.student_id into v_student from class_enrolment ce where ce.roll_number = 2 limit 1;
  set local role authenticated;
  update period_attendance set status = 'absent_unauth'
   where subject_set_id = v_set and timetable_slot_id = v_slot
     and date = '2026-01-13' and student_id = v_student;
  reset role;

  select count(*) into n from attendance_discrepancy
   where student_id = v_student and kind = 'present_on_register_absent_in_class'
     and subject_set_id = v_set;
  insert into lp values ('Absent in lesson raises a discrepancy','1',n::text,n=1);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  select count(*) into n from discrepancy_feed
   where student_id = v_student and subject_name = 'Biology' and resolved_at is null;
  reset role;
  insert into lp values ('Discrepancy reaches the Usher board','1',n::text,n=1);

  -- Set ownership is enforced server-side, not by hiding the button.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_other,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  jsonb_build_array('attendance.mark','marks.enter'))::text, true);
  set local role authenticated;
  begin
    select rpc_prefill_period(v_slot, v_set, '2026-01-13') into n;
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into lp values ('Educator prefills a set they do not teach','raises (1)',n::text,n=1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from lp;
