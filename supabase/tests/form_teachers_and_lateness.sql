-- EduMU :: Two Form Teachers per class, and the late-arrival rule.
--
-- These rules came from watching a school, not from the Manual, and they
-- corrected an assumption baked into the original design.
--
--   * A class has TWO Form Teachers: one takes the morning register, one the
--     afternoon. Either may READ both registers — the afternoon teacher needs
--     to know what happened that morning — but each may only MARK their own.
--
--   * A pupil who arrives after the morning register has closed stands as
--     absent for the morning, and is marked LATE on the afternoon register.
--     If the morning register is still open, the lateness is recorded there
--     instead and no absence is created.
--
-- ⚠️ The first rule costs that pupil half a session for a day they largely
-- attended. Over a term, habitual lateness alone can drift a pupil toward the
-- 80% examination threshold. That is what the school does on paper, so it is
-- what this does — but `late_arrival` keeps the true arrival time so a Rector
-- can tell "absent all morning" from "arrived 08:15" before debarring anyone.
--
-- Every row must read PASS.

create temp table if not exists ft(test text, expected text, got text, pass boolean);
truncate ft;

do $$
declare
  sch uuid; anj uuid; dev uuid; c7a uuid; ush_caps jsonb; ed_caps jsonb;
  d date := '2026-05-05'; s1 uuid; n int; res jsonb; v_status text; roll int;
begin
  select s.id into sch from school s where s.code='DEMO-SSS';
  select p.id into anj from person p where p.email='a.ramdin@demo-sss.mu';
  select p.id into dev from person p where p.email='d.callychurn@demo-sss.mu';
  select cg.id into c7a from class_group cg
    join academic_year y on y.id = cg.academic_year_id
   where y.name='2026' and cg.name='7A';
  select ce.student_id into s1 from class_enrolment ce where ce.roll_number=1 limit 1;
  select count(*) into roll from class_enrolment ce where ce.class_group_id = c7a;
  select coalesce(jsonb_agg(distinct rc.capability_code),'[]') into ed_caps
   from role_capability rc where rc.role_code='educator';
  select coalesce(jsonb_agg(distinct rc.capability_code),'[]') into ush_caps
   from role_capability rc where rc.role_code='usher';

  -- Self-contained: clear the day being tested.
  delete from attendance_record ar using attendance_session s
   where s.id = ar.attendance_session_id and s.class_group_id = c7a and s.date = d;
  delete from attendance_session where class_group_id = c7a and date = d;
  delete from late_arrival where date = d;

  -- ── each teacher owns one register ──────────────────────────────────
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',anj,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object(
      'c','form_teacher','s','class','id',c7a,'sess','am')),
    'caps',ed_caps)::text, true);

  set local role authenticated;
  begin perform rpc_open_register(c7a, d, 'am'); n := 1;
  exception when others then n := 0; end;
  reset role;
  insert into ft values ('AM teacher opens the AM register','allowed (1)',n::text,n=1);

  set local role authenticated;
  begin perform rpc_open_register(c7a, d, 'pm'); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into ft values ('AM teacher cannot open the PM register','raises (1)',n::text,n=1);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',dev,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object(
      'c','form_teacher','s','class','id',c7a,'sess','pm')),
    'caps',ed_caps)::text, true);
  set local role authenticated;
  begin perform rpc_open_register(c7a, d, 'pm'); n := 1;
  exception when others then n := 0; end;
  reset role;
  insert into ft values ('PM teacher opens the PM register','allowed (1)',n::text,n=1);

  -- Reading is class-wide: the afternoon teacher must see the morning.
  set local role authenticated;
  select count(*) into n from attendance_record ar
   join attendance_session s on s.id = ar.attendance_session_id
   where s.class_group_id = c7a and s.date = d and s.session='am';
  reset role;
  insert into ft values ('PM teacher can read the AM register', roll::text, n::text, n = roll);

  -- ── late after the morning register has closed ──────────────────────
  update attendance_record ar set status='absent_unauth'
    from attendance_session s
   where s.id = ar.attendance_session_id and s.class_group_id = c7a
     and s.date = d and s.session='am' and ar.student_id = s1;
  update attendance_session set status='closed'
   where class_group_id = c7a and date = d and session='am';

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',anj,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','usher','s','school')),
    'caps',ush_caps)::text, true);
  set local role authenticated;
  select rpc_record_late_arrival(s1, d, time '08:15', 'Missed the bus') into res;
  reset role;
  insert into ft values ('Late after AM register carries to PM','carried_to_pm',
    res->>'outcome', res->>'outcome' = 'carried_to_pm');

  select ar.status::text into v_status from attendance_record ar
   join attendance_session s on s.id = ar.attendance_session_id
   where s.class_group_id=c7a and s.date=d and s.session='pm' and ar.student_id=s1;
  insert into ft values ('PM register reads late','late',v_status,v_status='late');

  select ar.status::text into v_status from attendance_record ar
   join attendance_session s on s.id = ar.attendance_session_id
   where s.class_group_id=c7a and s.date=d and s.session='am' and ar.student_id=s1;
  insert into ft values ('AM register still reads absent','absent_unauth',
    v_status, v_status='absent_unauth');

  -- The arrival time is what distinguishes this from a genuine absence.
  select count(*) into n from late_arrivals_report lr
   where lr.student_id=s1 and lr.date=d and lr.arrived_at = time '08:15'
     and lr.after_am_register;
  insert into ft values ('Arrival time recorded beside the absence','1',n::text,n=1);

  -- ── late while the morning register is still open ───────────────────
  delete from late_arrival where date = d;
  update attendance_session set status='open'
   where class_group_id=c7a and date=d and session='am';
  update attendance_record ar set status='absent_unauth'
    from attendance_session s
   where s.id=ar.attendance_session_id and s.class_group_id=c7a
     and s.date=d and s.session='am' and ar.student_id=s1;

  set local role authenticated;
  select rpc_record_late_arrival(s1, d, time '07:50') into res;
  reset role;
  insert into ft values ('Late while AM open marks the AM register',
    'marked_late_in_am', res->>'outcome', res->>'outcome'='marked_late_in_am');

  select ar.status::text into v_status from attendance_record ar
   join attendance_session s on s.id=ar.attendance_session_id
   where s.class_group_id=c7a and s.date=d and s.session='am' and ar.student_id=s1;
  insert into ft values ('AM register reads late','late',v_status,v_status='late');

  -- Recording lateness is the Usher's duty, not an Educator's.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',dev,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',ed_caps)::text, true);
  set local role authenticated;
  begin perform rpc_record_late_arrival(s1, d, time '08:30'); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into ft values ('Educator cannot record a late arrival','raises (1)',n::text,n=1);

  -- Clean up so the suite can be run again.
  delete from attendance_record ar using attendance_session s
   where s.id = ar.attendance_session_id and s.class_group_id = c7a and s.date = d;
  delete from attendance_session where class_group_id = c7a and date = d;
  delete from late_arrival where date = d;
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from ft;
