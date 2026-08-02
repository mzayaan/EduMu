-- EduMU :: every SECURITY DEFINER RPC must authorise itself.
--
-- A SECURITY DEFINER function in `public` is reachable by any signed-in user at
-- /rest/v1/rpc/<name>, and RLS does not apply inside it. So the function is the
-- only thing standing between a caller and the whole table. RLS being correct
-- on all 102 tables buys nothing on that path.
--
-- Found by this check: report_card_attendance(p_term, p_student) was DEFINER
-- with no guard and an unconstrained pupil uuid, so any authenticated user —
-- including a parent, or a teacher at another school — could read any child's
-- absence and lateness record. Migration 55 made it SECURITY INVOKER so the
-- existing attendance_summary policy governs it.
--
-- Two assertions:
--   1. Structural — no DEFINER function in the exposed schema lacks a guard.
--   2. Behavioural — a guardian cannot read a pupil outside their own family
--      through the specific RPC that leaked.

create temp table if not exists rpc_guard(check_name text, detail text, verdict text);
truncate rpc_guard;

-- 1 ────────────────────────────────────────────────────────────────────────
-- Structural. A guard means the body mentions one of the app.* authorisation
-- helpers or the caller's identity. This cannot prove the guard is *correct*,
-- only that authorisation was considered. A new DEFINER RPC that forgets it
-- entirely fails here.
insert into rpc_guard
select 'definer rpc without any guard',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       'INSECURE'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef
  and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  and pg_get_functiondef(p.oid) !~*
      '(app\.(has_cap|has_role|is_guardian_of|form_teacher_of_student|teaches_set|school_id|person_id))|auth\.uid\(\)';

insert into rpc_guard
select 'definer rpc without any guard', 'none found', 'SECURE'
where not exists (select 1 from rpc_guard where check_name = 'definer rpc without any guard');

-- Every DEFINER function must also pin search_path, or a caller who can create
-- objects in a schema earlier on the path can hijack what the body resolves to.
insert into rpc_guard
select 'definer rpc without pinned search_path', p.proname, 'INSECURE'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public','app')
  and p.prosecdef
  and not exists (
    select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%');

insert into rpc_guard
select 'definer rpc without pinned search_path', 'none found', 'SECURE'
where not exists (select 1 from rpc_guard where check_name = 'definer rpc without pinned search_path');

-- 2 ────────────────────────────────────────────────────────────────────────
-- Behavioural regression for the leak itself. Sign in as a guardian, then ask
-- report_card_attendance for a pupil that is not their ward. An empty result is
-- the pass: RLS filters the underlying row, so the function returns no row.
do $$
declare
  sch uuid; guardian uuid; own_ward uuid; other_pupil uuid; a_term uuid;
  got jsonb; leaked boolean;
begin
  select id into sch from school where code = 'DEMO-SSS';
  select sg.guardian_id, sg.student_id into guardian, own_ward
    from student_guardian sg
    join student s on s.id = sg.student_id and s.school_id = sch
   limit 1;

  -- A pupil in the same school who is NOT this guardian's ward. Same school on
  -- purpose: a cross-tenant miss would also be caught by the isolation sweep,
  -- whereas same-school cross-family is the case only this guard covers.
  select s.id into other_pupil
    from student s
   where s.school_id = sch
     and s.id <> own_ward
     and not exists (select 1 from student_guardian sg2
                      where sg2.guardian_id = guardian and sg2.student_id = s.id)
   limit 1;

  select t.id into a_term
    from term t join academic_year ay on ay.id = t.academic_year_id
   where ay.school_id = sch
   order by t.starts_on desc limit 1;

  if other_pupil is null or a_term is null then
    insert into rpc_guard values
      ('guardian cannot read another family via rpc', 'fixture missing', 'SKIPPED');
    return;
  end if;

  perform set_config('request.jwt.claims',
    jsonb_build_object(
      'school_id', sch, 'person_id', guardian, 'person_type', 'guardian',
      'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
      'caps',  jsonb_build_array()
    )::text, true);
  set local role authenticated;

  select report_card_attendance(a_term, other_pupil) into got;

  -- jsonb_build_object over an empty row set yields no row at all, so `got` is
  -- NULL when RLS did its job. A populated object means the row came through.
  leaked := got is not null;

  reset role;
  insert into rpc_guard values (
    'guardian cannot read another family via rpc',
    coalesce(got::text, '(no row — filtered by RLS)'),
    case when leaked then 'INSECURE' else 'SECURE' end);
exception when others then
  reset role;
  insert into rpc_guard values
    ('guardian cannot read another family via rpc', sqlerrm, 'SECURE (raised)');
end $$;

select check_name, detail, verdict from rpc_guard order by check_name, detail;

-- Any INSECURE row is a failure.
select case
         when exists (select 1 from rpc_guard where verdict = 'INSECURE')
         then 'FAIL — see rows above'
         else 'PASS — all DEFINER RPCs guarded, no cross-family read'
       end as result;
