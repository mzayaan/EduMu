-- report_card_attendance was SECURITY DEFINER with no authorisation of its own.
-- Any signed-in user could POST /rest/v1/rpc/report_card_attendance with any
-- pupil's uuid and read that child's absence and lateness record, across
-- families and across tenants.
--
-- The rule for who may read a pupil's attendance already exists, stated once,
-- as the RLS policy on attendance_summary and late_arrival:
--   same school AND (attendance.read.all | form teacher | guardian | the pupil)
-- The bug was bypassing it, so the fix is to stop bypassing it rather than to
-- restate it here and have two copies that can drift apart.
--
-- SECURITY INVOKER is safe for the callers this has: report_card_data is
-- SECURITY DEFINER, but RLS is FORCEd on every table, so even the owner is
-- subject to policy, and app.school_id()/app.person_id() read the request JWT,
-- which a definer context does not alter. The policy therefore still evaluates
-- against the real end user.
--
-- term is tenant-read and late_arrival carries the identical read policy, so
-- all three tables admit exactly the same set of callers.

create or replace function public.report_card_attendance(p_term uuid, p_student uuid)
returns jsonb
language sql
stable
security invoker
set search_path to 'public', 'app', 'pg_temp'
as $function$
  select jsonb_build_object(
    'sessions_possible',    sm.sessions_possible,
    'sessions_present',     sm.sessions_present,
    'absent_authorised',    sm.sessions_absent_auth,
    'absent_unauthorised',  sm.sessions_absent_unauth,
    'absent_total',         sm.sessions_absent_auth + sm.sessions_absent_unauth,
    'times_late',           sm.times_late,
    'late_arrivals',        (select count(*)::int from late_arrival la
                             join term t on t.id = p_term
                             where la.student_id = p_student
                               and la.date between t.starts_on and t.ends_on),
    'pct_present',          sm.pct_present)
  from attendance_summary sm
  where sm.term_id = p_term and sm.student_id = p_student
$function$;

comment on function public.report_card_attendance(uuid, uuid) is
  'Attendance counts for one pupil in one term. SECURITY INVOKER on purpose: '
  'the RLS policies on attendance_summary and late_arrival are the single '
  'statement of who may read this. Do not make it DEFINER.';
