-- EduMU :: Report book payload completeness.
--
-- The report book is the artefact a school judges the whole system by, so this
-- asserts that every field the design depends on is actually present — not just
-- that the call succeeds.
--
-- Two traps worth knowing:
--   1. A report column is LOGICAL. Each subject runs its own "Class Test 1"
--      row, so keying columns by assessment id gives subjects × assessments
--      columns. Columns are keyed by kind|title instead.
--   2. `c->'attendance' is not null` is NOT a real assertion: `->` yields JSON
--      null, which is not SQL NULL, so it passes even when nothing is there.
--      Assert on a leaf value.
--
-- Every row must read PASS.

create temp table if not exists rb(test text, expected text, got text, pass boolean);
truncate rb;

do $$
declare
  v_school uuid; v_p uuid; v_t2 uuid; v_s uuid; v_caps jsonb;
  c jsonb; v_marks int; v_cols int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_p from person where email='a.ramdin@demo-sss.mu';
  select t.id into v_t2 from term t join academic_year y on y.id=t.academic_year_id
   where y.name='2026' and t.sequence=2;
  select student_id into v_s from class_enrolment where roll_number=1 limit 1;
  select coalesce(jsonb_agg(distinct capability_code),'[]'::jsonb) into v_caps
   from role_capability where role_code='rector';

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  select report_card_data(v_t2, v_s) into c;
  reset role;

  select count(*) into v_cols  from jsonb_array_elements(c->'columns');
  select count(*) into v_marks from jsonb_object_keys(c->'subjects'->0->'marks');

  -- Identity and context
  insert into rb values ('School named', 'not null', coalesce(c->'school'->>'name','∅'),
                         c->'school'->>'name' is not null);
  insert into rb values ('Pupil named', 'not null',
                         coalesce(c->'pupil'->>'last_name','∅'), c->'pupil'->>'last_name' is not null);
  insert into rb values ('Admission number', 'not null',
                         coalesce(c->'pupil'->>'admission_number','∅'),
                         c->'pupil'->>'admission_number' is not null);
  insert into rb values ('Date of birth', 'not null',
                         coalesce(c->'pupil'->>'date_of_birth','∅'),
                         c->'pupil'->>'date_of_birth' is not null);
  insert into rb values ('Class, grade and form', 'not null',
                         coalesce((c->'class'->>'name') || ' G' || (c->'class'->>'grade'), '∅'),
                         c->'class'->>'name' is not null and c->'class'->>'grade' is not null);
  insert into rb values ('Form Teacher named', 'not null',
                         coalesce(c->'class'->>'form_teacher','∅'),
                         c->'class'->>'form_teacher' is not null);
  insert into rb values ('Next term stated', 'not null',
                         coalesce(c->'next_term'->>'starts_on','∅'),
                         c->'next_term'->>'starts_on' is not null);

  -- Columns are logical, and the mock is one of them.
  insert into rb values ('Assessment columns are logical, not per-subject',
                         '4', v_cols::text, v_cols = 4);
  insert into rb values ('July mock is its own column', 'present',
    coalesce((select col->>'title' from jsonb_array_elements(c->'columns') col
              where col->>'kind'='mock'), '∅'),
    exists (select 1 from jsonb_array_elements(c->'columns') col where col->>'kind'='mock'));
  insert into rb values ('End-of-term paper is its own column', 'present',
    coalesce((select col->>'title' from jsonb_array_elements(c->'columns') col
              where col->>'kind'='end_of_term'), '∅'),
    exists (select 1 from jsonb_array_elements(c->'columns') col
            where col->>'kind'='end_of_term'));
  insert into rb values ('Every column has a mark for the first subject',
                         v_cols::text, v_marks::text, v_marks = v_cols);

  -- Subject lines
  insert into rb values ('Subjects listed', '>0',
                         jsonb_array_length(c->'subjects')::text,
                         jsonb_array_length(c->'subjects') > 0);
  insert into rb values ('Subject teacher named on every line', 'none missing',
    (select count(*)::text from jsonb_array_elements(c->'subjects') s
      where s->>'teacher' is null),
    not exists (select 1 from jsonb_array_elements(c->'subjects') s where s->>'teacher' is null));
  insert into rb values ('Subject aggregate and grade present', 'none missing',
    (select count(*)::text from jsonb_array_elements(c->'subjects') s
      where s->>'aggregate' is null or s->>'grade' is null),
    not exists (select 1 from jsonb_array_elements(c->'subjects') s
                where s->>'aggregate' is null or s->>'grade' is null));
  insert into rb values ('At least one subject remark', 'present',
    coalesce((select left(s->>'comment',30) from jsonb_array_elements(c->'subjects') s
              where s->>'comment' is not null limit 1),'∅'),
    exists (select 1 from jsonb_array_elements(c->'subjects') s where s->>'comment' is not null));

  -- Summary, remarks, attendance — assert on leaf values, never on `-> key`.
  insert into rb values ('Overall score and rank', 'not null',
    coalesce((c->'summary'->>'overall_score') || '/' || (c->'summary'->>'overall_rank'),'∅'),
    c->'summary'->>'overall_score' is not null and c->'summary'->>'overall_rank' is not null);
  insert into rb values ('Form Teacher remark', 'not null',
    coalesce(left(c->'summary'->>'form_teacher_comment',30),'∅'),
    c->'summary'->>'form_teacher_comment' is not null);
  insert into rb values ('Rector remark', 'not null',
    coalesce(left(c->'summary'->>'rector_comment',30),'∅'),
    c->'summary'->>'rector_comment' is not null);
  insert into rb values ('Attendance percentage present', 'not null',
    coalesce(c->'attendance'->>'pct_present','∅'),
    c->'attendance'->>'pct_present' is not null);
  insert into rb values ('Attendance split into authorised and unauthorised', 'not null',
    coalesce((c->'attendance'->>'absent_authorised') || '/' ||
             (c->'attendance'->>'absent_unauthorised'),'∅'),
    c->'attendance'->>'absent_authorised' is not null
      and c->'attendance'->>'absent_unauthorised' is not null);
  insert into rb values ('Conduct section present', 'array',
    jsonb_typeof(c->'conduct'->'merits'),
    jsonb_typeof(c->'conduct'->'merits') = 'array');
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from rb;
