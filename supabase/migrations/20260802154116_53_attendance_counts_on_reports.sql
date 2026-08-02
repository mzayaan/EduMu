-- EduMU :: 53 Lateness and absence as counts on the report book and results.
--
-- A percentage is not what a parent reads. "92%" means little; "absent 7
-- sessions, late 4 times" is a fact they can act on. Both go on the report, and
-- the counts also join the term results so a Form Teacher discussing a subject
-- can see the attendance behind it.

alter table report_card
  add column if not exists sessions_possible      int,
  add column if not exists sessions_present       int,
  add column if not exists sessions_absent_unauth int,
  add column if not exists sessions_absent_auth   int,
  add column if not exists late_arrivals          int;

comment on column report_card.late_arrivals is
  'Late arrivals recorded at the gate, which is not the same as attendance_record '
  'entries marked late — a pupil who arrived after the morning register is absent '
  'in the AM and late in the PM.';

-- Build now stores the counts, not only the percentage.
create or replace function public.rpc_build_report_cards(p_term uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_rows int; v_from date; v_to date;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Not authorised to build report cards';
  end if;
  select school_id, starts_on, ends_on into v_school, v_from, v_to
  from term where id = p_term;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown term';
  end if;

  with overall as (
    select tr.student_id, round(avg(tr.aggregate_score), 2) as overall_score
    from term_result tr where tr.term_id = p_term group by tr.student_id
  ),
  placed as (
    select o.student_id, o.overall_score, ce.class_group_id,
           dense_rank() over (partition by ce.class_group_id
                              order by o.overall_score desc nulls last) as rank_in_class,
           count(*) over (partition by ce.class_group_id) as class_size
    from overall o
    join class_enrolment ce on ce.student_id = o.student_id and ce.effective_to is null
  )
  insert into report_card (
    school_id, term_id, student_id, overall_score, overall_rank, class_size,
    attendance_pct, times_late, sessions_possible, sessions_present,
    sessions_absent_unauth, sessions_absent_auth, late_arrivals)
  select v_school, p_term, p.student_id, p.overall_score,
         p.rank_in_class, p.class_size,
         sm.pct_present, sm.times_late,
         sm.sessions_possible, sm.sessions_present,
         sm.sessions_absent_unauth, sm.sessions_absent_auth,
         (select count(*)::int from late_arrival la
          where la.student_id = p.student_id and la.date between v_from and v_to)
  from placed p
  left join attendance_summary sm
         on sm.student_id = p.student_id and sm.term_id = p_term
  on conflict (term_id, student_id) do update set
    overall_score          = excluded.overall_score,
    overall_rank           = excluded.overall_rank,
    class_size             = excluded.class_size,
    attendance_pct         = excluded.attendance_pct,
    times_late             = excluded.times_late,
    sessions_possible      = excluded.sessions_possible,
    sessions_present       = excluded.sessions_present,
    sessions_absent_unauth = excluded.sessions_absent_unauth,
    sessions_absent_auth   = excluded.sessions_absent_auth,
    late_arrivals          = excluded.late_arrivals;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

-- The report book payload carries the counts and the late-arrival total.
--
-- NOTE: migration 55 changes this function to SECURITY INVOKER. It is DEFINER
-- here only because that is what was applied at the time; see 55 for why that
-- was a data leak.
create or replace function public.report_card_attendance(p_term uuid, p_student uuid)
returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
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
$$;

-- Term results gain the attendance behind them, so a subject conversation can
-- start from "they missed nine sessions" rather than only from the mark.
create or replace view term_results_with_attendance
with (security_invoker = true) as
select
  tr.*,
  sub.name_en                       as subject_name,
  p.first_name, p.last_name, s.admission_number,
  sm.pct_present,
  sm.sessions_absent_unauth + sm.sessions_absent_auth as sessions_absent,
  sm.sessions_absent_unauth,
  sm.times_late
from term_result tr
join subject sub on sub.id = tr.subject_id
join student s on s.id = tr.student_id
join person  p on p.id = s.id
left join attendance_summary sm
       on sm.student_id = tr.student_id and sm.term_id = tr.term_id;

grant select on term_results_with_attendance to authenticated;

revoke all on function public.report_card_attendance(uuid, uuid) from public, anon;
grant execute on function public.report_card_attendance(uuid, uuid) to authenticated;
