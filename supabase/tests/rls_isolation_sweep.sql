-- EduMU :: Family isolation sweep.
--
-- The single question this asks, of every table holding personal data:
--   can a pupil, or a guardian, see a row belonging to another family?
--
-- It exists because a per-table assertion is easy to forget when a table is
-- added. This sweeps the whole sensitive surface at once, and asserts the
-- INVARIANT (zero foreign rows) rather than a row count — an earlier suite
-- asserted "the pupil sees exactly 1 row", which was true of a fixture with one
-- register and reported a false security failure the moment a term of
-- attendance was seeded.
--
-- Every row must read SECURE.

create temp table if not exists sweep(actor text, table_name text, foreign_rows int);
truncate sweep;

do $$
declare
  sch uuid; s1 uuid; g uuid; res jsonb := '[]'::jsonb; n int;
  claims_pupil text; claims_guardian text;
begin
  select id into sch from school where code='DEMO-SSS';
  select sg.student_id into s1 from student_guardian sg limit 1;
  select sg.guardian_id into g  from student_guardian sg limit 1;

  claims_pupil := jsonb_build_object('school_id',sch,'person_id',s1,'person_type','student',
    'roles',jsonb_build_array(jsonb_build_object('c','student','s','self')),
    'caps',jsonb_build_array())::text;
  claims_guardian := jsonb_build_object('school_id',sch,'person_id',g,'person_type','guardian',
    'roles',jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',jsonb_build_array())::text;

  perform set_config('request.jwt.claims', claims_pupil, true);
  set local role authenticated;
  select count(*) into n from attendance_record  where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','attendance_record','n',n);
  select count(*) into n from period_attendance  where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','period_attendance','n',n);
  select count(*) into n from mark               where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','mark','n',n);
  select count(*) into n from term_result        where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','term_result','n',n);
  select count(*) into n from report_card        where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','report_card','n',n);
  select count(*) into n from absence_note       where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','absence_note','n',n);
  select count(*) into n from sanction           where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','sanction','n',n);
  select count(*) into n from merit              where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','merit','n',n);
  select count(*) into n from health_record      where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','health_record','n',n);
  select count(*) into n from student_document   where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','student_document','n',n);
  select count(*) into n from attendance_summary where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','attendance_summary','n',n);
  select count(*) into n from exam_seat          where student_id <> s1;
  res := res || jsonb_build_object('a','pupil','t','exam_seat','n',n);
  -- Tables a pupil must not see AT ALL, not merely filtered.
  select count(*) into n from attendance_session;
  res := res || jsonb_build_object('a','pupil','t','attendance_session (any)','n',n);
  select count(*) into n from pastoral_case;
  res := res || jsonb_build_object('a','pupil','t','pastoral_case (any)','n',n);
  select count(*) into n from occurrence_log;
  res := res || jsonb_build_object('a','pupil','t','occurrence_log (any)','n',n);
  select count(*) into n from confidential_note;
  res := res || jsonb_build_object('a','pupil','t','confidential_note (any)','n',n);
  select count(*) into n from incident;
  res := res || jsonb_build_object('a','pupil','t','incident (any)','n',n);
  reset role;

  perform set_config('request.jwt.claims', claims_guardian, true);
  set local role authenticated;
  select count(*) into n from attendance_record where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','attendance_record','n',n);
  select count(*) into n from mark              where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','mark','n',n);
  select count(*) into n from report_card       where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','report_card','n',n);
  select count(*) into n from health_record     where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','health_record','n',n);
  select count(*) into n from student_document  where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','student_document','n',n);
  select count(*) into n from term_result       where student_id <> s1;
  res := res || jsonb_build_object('a','guardian','t','term_result','n',n);
  select count(*) into n from occurrence_log;
  res := res || jsonb_build_object('a','guardian','t','occurrence_log (any)','n',n);
  select count(*) into n from confidential_note;
  res := res || jsonb_build_object('a','guardian','t','confidential_note (any)','n',n);
  reset role;

  insert into sweep
  select x->>'a', x->>'t', (x->>'n')::int from jsonb_array_elements(res) x;
end $$;

-- Reported in the same four-column shape the runner expects.
select 'isolation' as suite,
       actor || ' → ' || table_name as test,
       '0' as expected,
       foreign_rows::text as got,
       case when foreign_rows = 0 then 'PASS' else 'FAIL' end as result
from sweep order by (foreign_rows > 0) desc, actor, table_name;
