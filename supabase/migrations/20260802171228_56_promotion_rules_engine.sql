-- EduMU :: 56 Promotion rules engine (BLUEPRINT §15.4).
--
-- Specified in the blueprint and never built. Without it the Manual's
-- second-attempt rule, Lower VI entry and Upper VI entry are all decisions the
-- system has no opinion on, and year rollover has nothing to act on.
--
-- Shape, deliberately:
--   facts   — computed once per pupil per year by SQL, from marks and attendance
--   rules   — DATA, stored per academic year, ordered by priority, first match wins
--   verdict — pure evaluation of conditions against facts
--
-- Splitting facts from evaluation is what makes the TypeScript mirror in
-- packages/domain testable against this one: same facts in, same outcome out,
-- with no need to reimplement the SQL that gathers them. A rules engine whose
-- two implementations disagree is worse than having one.
--
-- Rules are data because promotion thresholds are a school and Ministry matter
-- that changes between years, and a threshold in code is a threshold nobody can
-- correct without a deploy.

create type promotion_outcome as enum
  ('promote', 'conditional_promote', 'repeat', 'leave', 'refer');

-- How many times has this pupil already repeated? The Manual's one-repeat rule
-- needs this and nothing was counting it.
alter table student add column if not exists times_repeated smallint not null default 0;

comment on column student.times_repeated is
  'Incremented by rpc_rollover_year when the outcome is repeat. The Manual '
  'generally allows one repeat, so this is load-bearing, not statistical.';

-- ── rules ─────────────────────────────────────────────────────────────────
create table promotion_rule (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references school on delete cascade,
  academic_year_id uuid not null references academic_year on delete cascade,
  grade            smallint not null,
  stream           stream_type,           -- null = applies to every stream
  name             text not null,
  outcome          promotion_outcome not null,
  priority         smallint not null,     -- lower runs first; first match wins
  conditions       jsonb not null default '[]'::jsonb,  -- ALL must hold
  is_active        boolean not null default true,
  note             text,
  created_at       timestamptz not null default now(),
  unique (academic_year_id, grade, stream, priority)
);
create index on promotion_rule (school_id, academic_year_id, grade);

comment on table promotion_rule is
  'Promotion rules as data, per academic year. First matching rule by priority '
  'wins; a pupil matching nothing falls through to the engine default of repeat, '
  'which is the safe direction — a wrongly-held pupil is visible and appealable, '
  'a wrongly-promoted one surfaces a year later.';

alter table promotion_rule enable row level security;
alter table promotion_rule force  row level security;

create policy prule_read on promotion_rule for select to authenticated
using (school_id = app.school_id());

create policy prule_write on promotion_rule for all to authenticated
using (school_id = app.school_id() and app.has_cap('school.manage'))
with check (school_id = app.school_id() and app.has_cap('school.manage'));

create trigger audit_promotion_rule
  after insert or update or delete on promotion_rule
  for each row execute function app.audit_row();

-- ── decisions ─────────────────────────────────────────────────────────────
create table promotion_decision (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references school on delete cascade,
  academic_year_id  uuid not null references academic_year on delete cascade,
  student_id        uuid not null references student on delete cascade,
  outcome           promotion_outcome not null,
  matched_rule_id   uuid references promotion_rule on delete set null,
  facts             jsonb not null default '{}'::jsonb,
  computed_at       timestamptz not null default now(),
  -- The Rector can overrule the engine. That is not a workaround; it is the
  -- actual authority. The engine advises.
  override_outcome  promotion_outcome,
  override_reason   text,
  override_by       uuid references staff,
  override_at       timestamptz,
  confirmed_at      timestamptz,
  confirmed_by      uuid references staff,
  unique (academic_year_id, student_id),
  constraint override_needs_a_reason
    check (override_outcome is null or nullif(trim(override_reason), '') is not null)
);
create index on promotion_decision (school_id, academic_year_id);

comment on column promotion_decision.facts is
  'The evidence the verdict was reached on, frozen at computation. Kept because '
  'an appeal in November is about the figures as they stood in July, and marks '
  'get amended.';

alter table promotion_decision enable row level security;
alter table promotion_decision force  row level security;

-- A pupil and their guardian may see their own outcome once confirmed. Before
-- confirmation it is a draft the school is still working on.
create policy pdec_read on promotion_decision for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('marks.read.all')
            or app.form_teacher_of_student(student_id)
            or ((confirmed_at is not null)
                and (app.is_guardian_of(student_id) or student_id = app.person_id()))));

create policy pdec_write on promotion_decision for all to authenticated
using (school_id = app.school_id() and app.has_cap('marks.moderate'))
with check (school_id = app.school_id() and app.has_cap('marks.moderate'));

create trigger audit_promotion_decision
  after insert or update or delete on promotion_decision
  for each row execute function app.audit_row();

-- ── facts ─────────────────────────────────────────────────────────────────
create or replace function app.promotion_facts(p_student uuid, p_year uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_final_term uuid; v_year_start date; f jsonb;
begin
  select t.id into v_final_term
  from term t where t.academic_year_id = p_year
  order by t.sequence desc limit 1;

  select make_date(extract(year from y.starts_on)::int, 1, 1) into v_year_start
  from academic_year y where y.id = p_year;

  select jsonb_build_object(
    -- Mean of subject aggregates across the whole year, not just the last term.
    'aggregate', (
      select round(avg(tr.aggregate_score), 2)
      from term_result tr join term t on t.id = tr.term_id
      where tr.student_id = p_student and t.academic_year_id = p_year),

    -- Credits and passes are judged on the FINAL term: they represent the
    -- year's standing, not an average of a pupil who improved.
    'credit_count', (
      select count(*) from term_result tr
      join grading_band gb on gb.label = tr.band_label
      where tr.student_id = p_student and tr.term_id = v_final_term and gb.is_credit),

    'pass_count', (
      select count(*) from term_result tr
      join grading_band gb on gb.label = tr.band_label
      where tr.student_id = p_student and tr.term_id = v_final_term and gb.is_pass),

    'pass_count_principal', (
      select count(*) from term_result tr
      join grading_band gb on gb.label = tr.band_label
      join subject_set ss on ss.id = tr.subject_set_id
      where tr.student_id = p_student and tr.term_id = v_final_term
        and gb.is_pass and ss.level = 'principal'),

    'pass_count_subsidiary', (
      select count(*) from term_result tr
      join grading_band gb on gb.label = tr.band_label
      join subject_set ss on ss.id = tr.subject_set_id
      where tr.student_id = p_student and tr.term_id = v_final_term
        and gb.is_pass and ss.level = 'subsidiary'),

    -- Two attendance figures, because the rules disagree about whether an
    -- authorised absence counts against a pupil. Both are recorded so a rule
    -- can say which it means rather than the engine deciding silently.
    'attendance_pct', (
      select round(avg(sm.pct_present), 2) from attendance_summary sm
      where sm.student_id = p_student and sm.academic_year_id = p_year),

    'attendance_pct_incl_authorised', (
      select case when sum(sm.sessions_possible) > 0
        then round(100.0 * (sum(sm.sessions_present) + sum(sm.sessions_absent_auth))
                   / sum(sm.sessions_possible), 2) end
      from attendance_summary sm
      where sm.student_id = p_student and sm.academic_year_id = p_year),

    'times_repeated', (select coalesce(s.times_repeated, 0) from student s where s.id = p_student),

    'age_at_jan_1', (
      select extract(year from age(v_year_start, p.date_of_birth::date))::int
      from person p where p.id = p_student),

    'has_medical_certificate_for_prolonged_absence', (
      select exists (
        select 1 from absence_note an
        where an.student_id = p_student
          and an.medical_certificate_path is not null
          and an.covers_to - an.covers_from >= 5)),

    -- Core subjects matched on code, so a school renaming "Mathematics" does
    -- not silently break the rule.
    'core_passed', (
      select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from (
        select lower(x.k) as k, exists (
          select 1 from term_result tr
          join grading_band gb on gb.label = tr.band_label
          join subject sub on sub.id = tr.subject_id
          where tr.student_id = p_student and tr.term_id = v_final_term
            and gb.is_pass and upper(sub.code) like x.pfx || '%') as v
        from (values ('english','ENG'), ('french','FRE'), ('maths','MAT')) x(k, pfx)
      ) z),

    'grade', (
      select gl.grade from class_enrolment ce
      join class_group cg on cg.id = ce.class_group_id
      join grade_level gl on gl.id = cg.grade_level_id
      where ce.student_id = p_student and ce.effective_to is null limit 1),

    'stream', (
      select cg.stream::text from class_enrolment ce
      join class_group cg on cg.id = ce.class_group_id
      where ce.student_id = p_student and ce.effective_to is null limit 1)
  ) into f;

  return f;
end $$;

-- ── evaluation ────────────────────────────────────────────────────────────
-- Pure: facts in, boolean out. Mirrored exactly by evaluateConditions() in
-- packages/domain/src/promotion.ts, and the two are compared by
-- supabase/tests/promotion_parity.sql.
--
-- An unknown condition kind returns FALSE, not TRUE. A rule nobody can evaluate
-- must not silently promote.
create or replace function app.promotion_condition_holds(p_facts jsonb, p_cond jsonb)
returns boolean
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare k text; v numeric; got numeric; lvl text;
begin
  k := p_cond ->> 'kind';
  v := nullif(p_cond ->> 'value', '')::numeric;

  case k
    when 'aggregate_gte' then
      got := nullif(p_facts ->> 'aggregate', '')::numeric;
      return got is not null and got >= v;

    when 'subject_pass_count_gte' then
      lvl := p_cond ->> 'level';
      got := case lvl
               when 'principal'  then nullif(p_facts ->> 'pass_count_principal', '')::numeric
               when 'subsidiary' then nullif(p_facts ->> 'pass_count_subsidiary', '')::numeric
               else nullif(p_facts ->> 'pass_count', '')::numeric end;
      return coalesce(got, 0) >= v;

    when 'credit_count_gte' then
      -- sameSitting is accepted and currently always true: the system records
      -- one sitting per year, so credits cannot be accumulated across sittings.
      -- If resits are ever recorded this must start filtering.
      got := nullif(p_facts ->> 'credit_count', '')::numeric;
      return coalesce(got, 0) >= v;

    when 'attendance_pct_gte' then
      got := case when coalesce((p_cond ->> 'countAuthorisedAsPresent')::boolean, false)
                  then nullif(p_facts ->> 'attendance_pct_incl_authorised', '')::numeric
                  else nullif(p_facts ->> 'attendance_pct', '')::numeric end;
      return got is not null and got >= v;

    when 'times_repeated_lte' then
      return coalesce(nullif(p_facts ->> 'times_repeated', '')::numeric, 0) <= v;

    when 'age_on_date_lte' then
      -- Only jan_1 is computed. exam_date would need the exam timetable and is
      -- rejected rather than silently answered with the wrong date.
      if coalesce(p_cond ->> 'asOf', 'jan_1') <> 'jan_1' then return false; end if;
      got := nullif(p_facts ->> 'age_at_jan_1', '')::numeric;
      return got is not null and got <= v;

    when 'has_medical_certificate_for_prolonged_absence' then
      return coalesce((p_facts ->> 'has_medical_certificate_for_prolonged_absence')::boolean, false);

    when 'core_subject_passed' then
      return coalesce(((p_facts -> 'core_passed') ->> (p_cond ->> 'subject'))::boolean, false);

    else
      return false;
  end case;
end $$;

create or replace function app.evaluate_promotion(p_student uuid, p_year uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  f jsonb; r record; c jsonb; all_hold boolean;
begin
  f := app.promotion_facts(p_student, p_year);

  for r in
    select pr.* from promotion_rule pr
    where pr.academic_year_id = p_year
      and pr.is_active
      and pr.grade = (f ->> 'grade')::smallint
      and (pr.stream is null or pr.stream::text = (f ->> 'stream'))
    order by pr.priority
  loop
    all_hold := true;
    for c in select * from jsonb_array_elements(r.conditions) loop
      if not app.promotion_condition_holds(f, c) then
        all_hold := false;
        exit;
      end if;
    end loop;

    if all_hold then
      return jsonb_build_object(
        'outcome', r.outcome, 'rule_id', r.id, 'rule_name', r.name, 'facts', f);
    end if;
  end loop;

  -- Nothing matched. Hold the pupil rather than promote them: a wrongly-held
  -- pupil is visible and appealable, a wrongly-promoted one is discovered a
  -- year later by a teacher wondering why they cannot cope.
  return jsonb_build_object(
    'outcome', 'repeat', 'rule_id', null, 'rule_name', 'no rule matched', 'facts', f);
end $$;

-- ── the batch the Rector runs ─────────────────────────────────────────────
create or replace function public.rpc_evaluate_promotions(p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_rows int := 0; s record; res jsonb;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Not authorised to evaluate promotions';
  end if;
  select y.school_id into v_school from academic_year y where y.id = p_year;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown academic year';
  end if;

  for s in
    select st.id from student st
    join class_enrolment ce on ce.student_id = st.id and ce.effective_to is null
    join class_group cg on cg.id = ce.class_group_id
    where st.school_id = v_school and cg.academic_year_id = p_year
      and st.status = 'enrolled'
  loop
    res := app.evaluate_promotion(s.id, p_year);

    insert into promotion_decision (school_id, academic_year_id, student_id,
                                    outcome, matched_rule_id, facts)
    values (v_school, p_year, s.id,
            (res ->> 'outcome')::promotion_outcome,
            nullif(res ->> 'rule_id', '')::uuid,
            res -> 'facts')
    on conflict (academic_year_id, student_id) do update set
      outcome         = excluded.outcome,
      matched_rule_id = excluded.matched_rule_id,
      facts           = excluded.facts,
      computed_at     = now()
    -- Never overwrite a decision a human has already confirmed. Re-running the
    -- batch must not quietly undo the Rector.
    where promotion_decision.confirmed_at is null;

    v_rows := v_rows + 1;
  end loop;

  return v_rows;
end $$;

create or replace function public.rpc_override_promotion(
  p_student uuid, p_year uuid, p_outcome promotion_outcome, p_reason text
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.has_cap('marks.publish') then
    raise exception 'Only the Rector may overrule a promotion decision';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'An override needs a reason';
  end if;

  update promotion_decision
     set override_outcome = p_outcome, override_reason = p_reason,
         override_by = app.person_id(), override_at = now()
   where student_id = p_student and academic_year_id = p_year
     and school_id = app.school_id();

  if not found then raise exception 'No promotion decision for this pupil'; end if;
end $$;

create or replace function public.rpc_confirm_promotions(p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_rows int;
begin
  if not app.has_cap('marks.publish') then
    raise exception 'Only the Rector may confirm promotions';
  end if;
  update promotion_decision
     set confirmed_at = now(), confirmed_by = app.person_id()
   where academic_year_id = p_year and school_id = app.school_id()
     and confirmed_at is null;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

-- What the Rector reads. The effective outcome is the override where one
-- exists, so no screen has to remember to apply that itself.
create or replace view promotion_screen
with (security_invoker = true) as
select
  pd.academic_year_id, pd.student_id, pd.school_id,
  p.first_name, p.last_name, s.admission_number,
  cg.name as class_name, gl.grade,
  pd.outcome as engine_outcome,
  pd.override_outcome,
  coalesce(pd.override_outcome, pd.outcome) as effective_outcome,
  pd.override_reason,
  pr.name as rule_name,
  (pd.facts ->> 'aggregate')::numeric      as aggregate,
  (pd.facts ->> 'attendance_pct')::numeric as attendance_pct,
  (pd.facts ->> 'credit_count')::int       as credit_count,
  (pd.facts ->> 'times_repeated')::int     as times_repeated,
  pd.facts, pd.confirmed_at, pd.computed_at
from promotion_decision pd
join student s on s.id = pd.student_id
join person  p on p.id = s.id
left join promotion_rule pr on pr.id = pd.matched_rule_id
left join class_enrolment ce on ce.student_id = s.id and ce.effective_to is null
left join class_group cg on cg.id = ce.class_group_id
left join grade_level gl on gl.id = cg.grade_level_id;

grant select on promotion_screen to authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_evaluate_promotions(uuid)',
    'public.rpc_override_promotion(uuid, uuid, promotion_outcome, text)',
    'public.rpc_confirm_promotions(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
