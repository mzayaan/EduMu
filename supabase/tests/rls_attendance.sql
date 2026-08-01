-- EduMU :: RLS behaviour tests for attendance.
--
-- These impersonate each role by setting request.jwt.claims and switching to the
-- `authenticated` database role, exactly as PostgREST does. Run against a
-- Supabase branch, never production. Requires the demo seed (migration 10) plus
-- the fixtures it references.
--
-- Every row of the result must read PASS. This suite should gate CI: no
-- migration merges until it is green.

create temp table if not exists rls_results(test text, expected text, got text, pass boolean);
truncate rls_results;

do $$
declare
  v_school uuid; v_year uuid; v_7a uuid; v_7b uuid;
  v_ft_a uuid; v_ft_b uuid; v_g uuid; v_s1 uuid; v_s2 uuid; n int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_year   from academic_year where school_id=v_school and name='2026';
  select id into v_7a     from class_group where academic_year_id=v_year and name='7A';
  select id into v_7b     from class_group where academic_year_id=v_year and name='7B';
  select id into v_ft_a   from person where email='a.ramdin@demo-sss.mu';
  select id into v_ft_b   from person where email='d.callychurn@demo-sss.mu';
  select id into v_g      from person where person_type='guardian' limit 1;
  select student_id into v_s1 from class_enrolment where roll_number=1 limit 1;
  select student_id into v_s2 from class_enrolment where roll_number=2 limit 1;

  -- A Form Teacher sees their own class register in full.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ft_a,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','form_teacher','s','class','id',v_7a)),
    'caps',  jsonb_build_array('attendance.mark'))::text, true);
  set local role authenticated;
  select count(*) into n from attendance_record;
  reset role;
  insert into rls_results values ('Form Teacher of 7A reads own class register','5',n::text,n=5);

  -- ...and nothing of any other class.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ft_b,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','form_teacher','s','class','id',v_7b)),
    'caps',  jsonb_build_array('attendance.mark'))::text, true);
  set local role authenticated;
  select count(*) into n from attendance_record;
  reset role;
  insert into rls_results values ('Form Teacher of 7B reads another class register','0',n::text,n=0);

  -- The School Management Manual (4.5.2) is explicit that students must not have
  -- access to attendance registers. The read is row-shaped: a pupil sees their
  -- own records and nothing else.
  --
  -- Assert the INVARIANT (zero rows belonging to anyone else), never a row
  -- count. An earlier version asserted `n = 1`, which was true when the fixture
  -- held one register and failed the moment a term of attendance was seeded —
  -- reporting a security failure where there was none.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_s1,'person_type','student',
    'roles', jsonb_build_array(jsonb_build_object('c','student','s','self')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from attendance_record where student_id <> v_s1;
  reset role;
  insert into rls_results values ('Pupil sees no other pupil''s attendance','0',n::text,n=0);

  -- Nor can they enumerate the registers themselves.
  set local role authenticated;
  select count(*) into n from attendance_session;
  reset role;
  insert into rls_results values ('Pupil cannot enumerate registers','0',n::text,n=0);

  -- A Responsible Party sees their ward and no one else's child.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from attendance_record;
  reset role;
  insert into rls_results values ('Guardian reads attendance','1 (own ward only)',n::text,n=1);

  -- A student cannot mark anyone present, including themselves.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_s1,'person_type','student',
    'roles', jsonb_build_array(jsonb_build_object('c','student','s','self')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  begin
    update attendance_record set status='present' where student_id=v_s2;
    get diagnostics n = row_count;
  exception when others then n := -1; end;
  reset role;
  insert into rls_results values ('Student amends another pupil''s attendance','0 rows',n::text,n=0);

  -- Attendance is evidential. Nobody deletes it — not even the Rector.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_ft_a,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  jsonb_build_array('attendance.read.all','attendance.mark','attendance.mark.any'))::text, true);
  set local role authenticated;
  begin
    delete from attendance_record where student_id=v_s2;
    get diagnostics n = row_count;
  exception when insufficient_privilege then n := -1; when others then n := -2; end;
  reset role;
  insert into rls_results values ('Rector deletes an attendance record','denied (-1)',n::text,n=-1);

  -- Tenant isolation holds even for a caller carrying every capability.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id', gen_random_uuid(), 'person_id', v_ft_a, 'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  jsonb_build_array('attendance.read.all','student.read.all'))::text, true);
  set local role authenticated;
  select count(*) into n from attendance_record;
  reset role;
  insert into rls_results values ('Rector of another school reads this school','0',n::text,n=0);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result
from rls_results;
