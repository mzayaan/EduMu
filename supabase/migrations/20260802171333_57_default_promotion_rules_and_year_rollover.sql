-- EduMU :: 57 The shipped rule set, and academic year rollover.

-- ── default rules ─────────────────────────────────────────────────────────
-- The set from BLUEPRINT §15.4. Seeded per year and fully editable afterwards:
-- these are a starting point a school corrects, not policy this system asserts.
-- Thresholds here are the common Mauritian defaults and MUST be checked against
-- the school's own reckoning before a live rollover.
create or replace function app.seed_promotion_rules(p_school uuid, p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_rows int := 0; g smallint;
begin
  -- Lower and middle school, Grades 7–10: pass the aggregate, or qualify for
  -- the Manual's second-attempt relief.
  foreach g in array array[7,8,9,10]::smallint[] loop
    insert into promotion_rule (school_id, academic_year_id, grade, name, outcome, priority, conditions, note)
    values
      (p_school, p_year, g, 'Standard promotion', 'promote', 10,
       '[{"kind":"aggregate_gte","value":40}]'::jsonb,
       'Aggregate at or above the school threshold.'),
      (p_school, p_year, g, 'Second-attempt relief', 'conditional_promote', 20,
       '[{"kind":"times_repeated_lte","value":1},
         {"kind":"aggregate_gte","value":35},
         {"kind":"attendance_pct_gte","value":75,"countAuthorisedAsPresent":true}]'::jsonb,
       'School Management Manual: a pupil who has repeated at most once, is '
       'close to the threshold and has attended may go up conditionally rather '
       'than repeat twice.')
    on conflict (academic_year_id, grade, stream, priority) do nothing;
    v_rows := v_rows + 2;
  end loop;

  -- Grade 11 → Lower VI. SC with at least four credits at one and the same
  -- sitting. credit_count comes from the final term, which is the single
  -- sitting this system records.
  insert into promotion_rule (school_id, academic_year_id, grade, name, outcome, priority, conditions, note)
  values
    (p_school, p_year, 11, 'Lower VI entry — 4 credits', 'promote', 10,
     '[{"kind":"credit_count_gte","value":4,"sameSitting":true}]'::jsonb,
     'SC with >= 4 credits at one and the same sitting.'),
    (p_school, p_year, 11, 'Lower VI entry — age relief', 'conditional_promote', 20,
     '[{"kind":"credit_count_gte","value":3,"sameSitting":true},
       {"kind":"times_repeated_lte","value":1},
       {"kind":"age_on_date_lte","value":19,"asOf":"jan_1"}]'::jsonb,
     'A pupil who cannot repeat Form V under the one-repeat rule, or would be '
     'disqualified by age, and is close to the credit requirement.'),
    (p_school, p_year, 11, 'Repeat Form V', 'repeat', 30,
     '[{"kind":"times_repeated_lte","value":0}]'::jsonb,
     'One repeat permitted.'),
    (p_school, p_year, 11, 'Leave after SC', 'leave', 40, '[]'::jsonb,
     'Neither qualifies for Lower VI nor may repeat again.')
  on conflict (academic_year_id, grade, stream, priority) do nothing;
  v_rows := v_rows + 4;

  -- Grade 12 → Upper VI. The Lower VI end-of-year exam is mandatory; passes at
  -- Principal and Subsidiary are counted separately.
  insert into promotion_rule (school_id, academic_year_id, grade, name, outcome, priority, conditions, note)
  values
    (p_school, p_year, 12, 'Upper VI entry', 'promote', 10,
     '[{"kind":"subject_pass_count_gte","value":2,"level":"principal"},
       {"kind":"subject_pass_count_gte","value":2,"level":"subsidiary"}]'::jsonb,
     '>= 2 passes at Principal and >= 2 at Subsidiary.'),
    (p_school, p_year, 12, 'Repeat Lower VI', 'repeat', 20,
     '[{"kind":"times_repeated_lte","value":0}]'::jsonb, null),
    (p_school, p_year, 12, 'Refer for guidance', 'refer', 30, '[]'::jsonb,
     'Neither qualifies nor may repeat: needs a conversation, not an algorithm.')
  on conflict (academic_year_id, grade, stream, priority) do nothing;
  v_rows := v_rows + 3;

  -- Grade 13 completes school. 'leave' here means finishing, not failing.
  insert into promotion_rule (school_id, academic_year_id, grade, name, outcome, priority, conditions, note)
  values (p_school, p_year, 13, 'Completes secondary schooling', 'leave', 10, '[]'::jsonb,
          'Upper VI is the end of secondary school; the outcome is leaving, not promotion.')
  on conflict (academic_year_id, grade, stream, priority) do nothing;
  v_rows := v_rows + 1;

  return v_rows;
end $$;

create or replace function public.rpc_seed_promotion_rules(p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to seed promotion rules';
  end if;
  select y.school_id into v_school from academic_year y where y.id = p_year;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown academic year';
  end if;
  return app.seed_promotion_rules(v_school, p_year);
end $$;

-- Backfill every existing year so the engine has something to evaluate.
do $$
declare y record;
begin
  for y in select id, school_id from academic_year loop
    perform app.seed_promotion_rules(y.school_id, y.id);
  end loop;
end $$;

-- ── rollover ──────────────────────────────────────────────────────────────
/*
 * Carry a school from one academic year into the next.
 *
 * This did not exist. The system worked within a year and had never been asked
 * to cross a boundary, so in January somebody would have re-enrolled every
 * pupil by hand.
 *
 * Refuses to run unless promotion decisions are CONFIRMED. Rollover acts on a
 * human decision; it does not make one.
 *
 * Dry run by default. The first thing anyone should see is what it would do.
 */
create or replace function public.rpc_rollover_year(
  p_from_year uuid, p_to_year uuid, p_commit boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_school uuid; v_to_school uuid; v_from_end date;
  v_promoted int := 0; v_repeated int := 0; v_left int := 0; v_referred int := 0;
  v_unplaced jsonb := '[]'::jsonb; v_pending int;
  d record; v_target_class uuid; v_next_grade smallint; v_cur_grade smallint;
  v_cur_stream stream_type; v_effective promotion_outcome;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to roll over the academic year';
  end if;

  select y.school_id, y.ends_on into v_school, v_from_end
  from academic_year y where y.id = p_from_year;
  select y.school_id into v_to_school from academic_year y where y.id = p_to_year;

  if v_school is null or v_to_school is null then
    raise exception 'Unknown academic year';
  end if;
  if v_school <> app.school_id() or v_to_school <> v_school then
    raise exception 'Both years must belong to your school';
  end if;
  if p_from_year = p_to_year then
    raise exception 'Cannot roll a year into itself';
  end if;

  -- Unconfirmed decisions mean the Rector has not finished. Rolling over now
  -- would act on a draft.
  select count(*) into v_pending from promotion_decision
   where academic_year_id = p_from_year and confirmed_at is null;
  if v_pending > 0 then
    raise exception '% promotion decision(s) are not confirmed — confirm them first', v_pending;
  end if;

  for d in
    select pd.student_id,
           coalesce(pd.override_outcome, pd.outcome) as outcome,
           ce.class_group_id, cg.stream, gl.grade
    from promotion_decision pd
    join class_enrolment ce on ce.student_id = pd.student_id and ce.effective_to is null
    join class_group cg on cg.id = ce.class_group_id
    join grade_level gl on gl.id = cg.grade_level_id
    where pd.academic_year_id = p_from_year and pd.school_id = v_school
  loop
    v_effective := d.outcome;
    v_cur_grade := d.grade;
    v_cur_stream := d.stream;

    if v_effective in ('promote', 'conditional_promote') then
      v_next_grade := v_cur_grade + 1;
    elsif v_effective = 'repeat' then
      v_next_grade := v_cur_grade;
    else
      -- leave / refer: no class next year.
      if v_effective = 'leave' then v_left := v_left + 1;
      else v_referred := v_referred + 1; end if;

      if p_commit then
        update class_enrolment set effective_to = v_from_end
         where student_id = d.student_id and effective_to is null;
        if v_effective = 'leave' then
          update student set status = 'left', left_on = v_from_end
           where id = d.student_id;
        end if;
      end if;
      continue;
    end if;

    -- Prefer the same stream in the target grade; fall back to any class of
    -- that grade. A school that has not built next year's classes yet gets a
    -- named list back rather than a silent drop.
    select cg2.id into v_target_class
    from class_group cg2 join grade_level gl2 on gl2.id = cg2.grade_level_id
    where cg2.academic_year_id = p_to_year and gl2.grade = v_next_grade
    order by (cg2.stream is not distinct from v_cur_stream) desc, cg2.name
    limit 1;

    if v_target_class is null then
      v_unplaced := v_unplaced || jsonb_build_object(
        'student_id', d.student_id, 'from_grade', v_cur_grade,
        'needs_grade', v_next_grade, 'outcome', v_effective);
      continue;
    end if;

    if v_effective = 'repeat' then
      v_repeated := v_repeated + 1;
    else
      v_promoted := v_promoted + 1;
    end if;

    if p_commit then
      update class_enrolment set effective_to = v_from_end
       where student_id = d.student_id and effective_to is null;

      insert into class_enrolment (school_id, class_group_id, student_id, effective_from)
      values (v_school, v_target_class, d.student_id, v_from_end + 1)
      on conflict do nothing;

      if v_effective = 'repeat' then
        update student set times_repeated = coalesce(times_repeated, 0) + 1
         where id = d.student_id;
      end if;
    end if;
  end loop;

  if p_commit then
    update academic_year set status = 'closed' where id = p_from_year;
    update academic_year set status = 'active'  where id = p_to_year;
    perform app.seed_promotion_rules(v_school, p_to_year);
  end if;

  return jsonb_build_object(
    'committed',  p_commit,
    'promoted',   v_promoted,
    'repeated',   v_repeated,
    'left',       v_left,
    'referred',   v_referred,
    'unplaced',   v_unplaced,
    'unplaced_count', jsonb_array_length(v_unplaced));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_seed_promotion_rules(uuid)',
    'public.rpc_rollover_year(uuid, uuid, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
