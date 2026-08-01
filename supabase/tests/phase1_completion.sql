-- EduMU :: Phase 1 completion — absence notes, alerts, option blocks.
--
-- NOTE: derive expected values from the data. Two earlier versions of this
-- suite failed on hand-written expectations (a pupil who was present on the
-- chosen dates; a missing tenant claim), not on product defects.

create temp table if not exists ph1(test text, expected text, got text, pass boolean);
truncate ph1;

do $$
declare
  v_school uuid; v_g uuid; v_staff uuid; v_s uuid; v_date date;
  v_note uuid; n int; n_absent int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_g from person where person_type='guardian' limit 1;
  select id into v_staff from person where email='a.ramdin@demo-sss.mu';
  select sg.student_id into v_s from student_guardian sg where sg.guardian_id = v_g limit 1;

  -- Pick a date the pupil was actually absent, rather than assuming one.
  select s.date into v_date
  from attendance_record ar join attendance_session s on s.id = ar.attendance_session_id
  where ar.student_id = v_s and ar.status = 'absent_unauth'
  order by s.date limit 1;

  if v_date is null then
    insert into ph1 values ('fixture: pupil has an unauthorised absence','a date','none',false);
    return;
  end if;

  select count(*) into n_absent
  from attendance_record ar join attendance_session s on s.id = ar.attendance_session_id
  where ar.student_id = v_s and s.date = v_date and ar.status = 'absent_unauth';

  insert into absence_note (school_id, student_id, submitted_by, covers_from, covers_to, reason)
  values (v_school, v_s, v_g, v_date, v_date, 'Unwell — certificate attached')
  returning id into v_note;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_staff,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',  jsonb_build_array('attendance.resolve'))::text, true);
  set local role authenticated;
  select rpc_decide_absence_note(v_note, true, 'Certificate seen') into n;
  reset role;
  insert into ph1 values ('Accepted note rewrites exactly the covered absences',
                          n_absent::text, n::text, n = n_absent and n > 0);

  select count(*) into n
  from attendance_record ar join attendance_session s on s.id = ar.attendance_session_id
  where ar.student_id = v_s and s.date = v_date and ar.status = 'absent_auth';
  insert into ph1 values ('Register now reads authorised', n_absent::text, n::text, n = n_absent);

  -- Option-block validation requires a tenant claim, like everything else.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_staff,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  jsonb_build_array('student.manage','school.manage'))::text, true);
  set local role authenticated;
  select count(*) into n from validate_subject_choice(
    v_s,
    (select gl.id from grade_level gl where gl.grade=7 and gl.school_id=v_school),
    (select array_agg(ss.subject_id) from set_enrolment se
      join subject_set ss on ss.id=se.subject_set_id
     where se.student_id=v_s and se.effective_to is null));
  reset role;
  insert into ph1 values ('Option-block validation evaluates both Grade 7 blocks','2',n::text,n=2);

  perform set_config('request.jwt.claims', '{}', true);
  set local role authenticated;
  select count(*) into n from validate_subject_choice(
    v_s, (select gl.id from grade_level gl where gl.grade=7 limit 1), array[]::uuid[]);
  reset role;
  insert into ph1 values ('Validation without a tenant claim returns nothing','0',n::text,n=0);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from ph1;
