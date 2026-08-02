--
-- PostgreSQL database dump
--

\restrict ttlrgdcph9sIjuaADXaKhevHf1LeHE7P4PjTNPTpd8V011RQaQ2rAZkntyUGzip

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app;


--
-- Name: SCHEMA app; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA app IS 'EduMU helper functions used by RLS policies and RPCs.';


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: assessment_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.assessment_kind AS ENUM (
    'class_test',
    'homework',
    'project',
    'practical',
    'term_test',
    'end_of_term',
    'end_of_year',
    'mock',
    'sba',
    'external'
);


--
-- Name: assessment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.assessment_status AS ENUM (
    'draft',
    'open',
    'submitted',
    'moderated',
    'published'
);


--
-- Name: attendance_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attendance_status AS ENUM (
    'present',
    'absent_unauth',
    'absent_auth',
    'late',
    'on_leave',
    'excluded',
    'school_activity'
);


--
-- Name: case_stage; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.case_stage AS ENUM (
    'form_teacher',
    'parent_contact',
    'special_report',
    'pastoral',
    'disciplinary_committee',
    'closed'
);


--
-- Name: day_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.day_type AS ENUM (
    'teaching',
    'holiday',
    'weekend',
    'closure',
    'exam_only',
    'activity'
);


--
-- Name: document_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.document_kind AS ENUM (
    'birth_certificate',
    'admission_form',
    'psac_result',
    'medical_certificate',
    'photo',
    'absence_note',
    'leaving_certificate',
    'report_card',
    'consent',
    'id_document',
    'qualification',
    'cpd_certificate',
    'contract',
    'other'
);


--
-- Name: incident_severity; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.incident_severity AS ENUM (
    'minor',
    'moderate',
    'serious',
    'grave'
);


--
-- Name: person_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.person_type AS ENUM (
    'student',
    'staff',
    'guardian'
);


--
-- Name: plan_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.plan_status AS ENUM (
    'draft',
    'submitted',
    'hod_returned',
    'hod_approved',
    'rector_approved'
);


--
-- Name: role_scope; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.role_scope AS ENUM (
    'school',
    'department',
    'class',
    'subject_set',
    'committee',
    'self',
    'ward'
);


--
-- Name: room_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.room_type AS ENUM (
    'classroom',
    'science_lab',
    'computer_room',
    'workshop',
    'home_ec',
    'art_room',
    'library',
    'hall',
    'gym',
    'office',
    'other'
);


--
-- Name: school_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.school_type AS ENUM (
    'state',
    'grant_aided',
    'private',
    'academy'
);


--
-- Name: session_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.session_type AS ENUM (
    'am',
    'pm'
);


--
-- Name: set_level; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.set_level AS ENUM (
    'core',
    'extended',
    'principal',
    'subsidiary'
);


--
-- Name: sex_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sex_type AS ENUM (
    'male',
    'female',
    'other',
    'undisclosed'
);


--
-- Name: stream_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.stream_type AS ENUM (
    'regular',
    'extended',
    'technical',
    'general'
);


--
-- Name: student_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.student_status AS ENUM (
    'applicant',
    'enrolled',
    'on_leave',
    'transferred_out',
    'left',
    'struck_off',
    'alumnus'
);


--
-- Name: subject_strand; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.subject_strand AS ENUM (
    'core',
    'humanities',
    'science',
    'technical',
    'social_science',
    'other'
);


--
-- Name: year_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.year_status AS ENUM (
    'planning',
    'active',
    'closed'
);


--
-- Name: attendance_stats(public.attendance_status[], numeric); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.attendance_stats(p_statuses public.attendance_status[], p_threshold numeric DEFAULT 80) RETURNS TABLE(sessions_possible integer, sessions_present integer, absent_unauth integer, absent_auth integer, times_late integer, pct_present numeric, pct_excl_auth numeric, eligible boolean, shortfall_sessions integer)
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_temp'
    AS $$
  with s as (
    select unnest(p_statuses) as st
  ), c as (
    select
      count(*)::int as possible,
      count(*) filter (where st in ('present','late','school_activity'))::int as present,
      count(*) filter (where st = 'absent_unauth')::int as unauth,
      count(*) filter (where st in ('absent_auth','on_leave'))::int as auth,
      count(*) filter (where st = 'late')::int as late
    from s
  )
  select
    c.possible, c.present, c.unauth, c.auth, c.late,
    case when c.possible = 0 then null
         else round(100.0 * c.present / c.possible, 2) end,
    case when c.possible - c.auth <= 0 then null
         else round(100.0 * c.present / (c.possible - c.auth), 2) end,
    case when c.possible = 0 then false
         else round(100.0 * c.present / c.possible, 2) >= p_threshold end,
    greatest(0, ceil(p_threshold / 100.0 * c.possible)::int - c.present)
  from c;
$$;


--
-- Name: attendance_summary_trigger(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.attendance_summary_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_date date; v_student uuid;
begin
  v_student := coalesce(new.student_id, old.student_id);
  select sess.date into v_date from attendance_session sess
   where sess.id = coalesce(new.attendance_session_id, old.attendance_session_id);
  if v_date is not null then
    perform app.refresh_attendance_summary(v_student, v_date);
  end if;
  return coalesce(new, old);
end $$;


--
-- Name: audit_row(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.audit_row() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare v_id uuid;
begin
  v_id := case tg_op when 'DELETE' then (to_jsonb(old) ->> 'id')::uuid
                     else (to_jsonb(new) ->> 'id')::uuid end;
  insert into audit_log (school_id, actor_id, action, table_name, record_id, before, after)
  values (
    coalesce(app.school_id(),
             case tg_op when 'DELETE' then (to_jsonb(old) ->> 'school_id')::uuid
                        else (to_jsonb(new) ->> 'school_id')::uuid end),
    app.person_id(), tg_op, tg_table_name, v_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;


--
-- Name: band_for(uuid, numeric); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.band_for(p_scale uuid, p_pct numeric) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select b.label from grading_band b
  where b.grading_scale_id = p_scale
    and p_pct >= coalesce(b.min_score, -1e9)
    and p_pct <= coalesce(b.max_score,  1e9)
  order by b.sort_order
  limit 1
$$;


--
-- Name: build_claims(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.build_claims(p_auth_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_person   record;
  v_year     uuid;
  v_roles    jsonb := '[]'::jsonb;
  v_caps     jsonb := '[]'::jsonb;
begin
  select p.id, p.school_id, p.person_type
    into v_person
  from person p
  where p.auth_user_id = p_auth_user_id and p.is_active
  limit 1;

  if v_person.id is null then
    return '{}'::jsonb;
  end if;

  select y.id into v_year
  from academic_year y
  where y.school_id = v_person.school_id and y.status = 'active'
  limit 1;

  if v_person.person_type = 'staff' then
    select
      coalesce(jsonb_agg(distinct jsonb_strip_nulls(
        jsonb_build_object('c', sra.role_code, 's', sra.scope_type::text, 'id', sra.scope_id)
      )), '[]'::jsonb)
    into v_roles
    from staff_role_assignment sra
    where sra.staff_id = v_person.id
      and (v_year is null or sra.academic_year_id = v_year)
      and sra.valid_from <= current_date
      and (sra.valid_to is null or sra.valid_to >= current_date);

    select coalesce(jsonb_agg(distinct rc.capability_code), '[]'::jsonb)
    into v_caps
    from staff_role_assignment sra
    join role_capability rc on rc.role_code = sra.role_code
    where sra.staff_id = v_person.id
      and (v_year is null or sra.academic_year_id = v_year)
      and sra.valid_from <= current_date
      and (sra.valid_to is null or sra.valid_to >= current_date);

  elsif v_person.person_type = 'student' then
    v_roles := jsonb_build_array(jsonb_build_object('c','student','s','self'));
    select coalesce(jsonb_agg(rc.capability_code), '[]'::jsonb) into v_caps
    from role_capability rc where rc.role_code = 'student';

  else -- guardian
    v_roles := jsonb_build_array(jsonb_build_object('c','guardian','s','ward'));
    select coalesce(jsonb_agg(rc.capability_code), '[]'::jsonb) into v_caps
    from role_capability rc where rc.role_code = 'guardian';
  end if;

  return jsonb_build_object(
    'school_id',   v_person.school_id,
    'person_id',   v_person.id,
    'person_type', v_person.person_type,
    'year_id',     v_year,
    'roles',       v_roles,
    'caps',        v_caps
  );
end $$;


--
-- Name: check_option_blocks(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.check_option_blocks() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_grade uuid; v_school uuid; v_enforce boolean; v_subjects uuid[]; v_bad record;
begin
  select ss.grade_level_id, ss.school_id into v_grade, v_school
  from subject_set ss where ss.id = new.subject_set_id;

  select coalesce((settings ->> 'enforce_option_blocks')::boolean, false)
    into v_enforce from school where id = v_school;
  if not v_enforce then return new; end if;

  select array_agg(distinct s2.subject_id) into v_subjects
  from set_enrolment se
  join subject_set s2 on s2.id = se.subject_set_id
  where se.student_id = new.student_id
    and se.effective_to is null
    and s2.grade_level_id = v_grade;

  for v_bad in
    select * from public.validate_subject_choice(new.student_id, v_grade, v_subjects)
    where not ok and chosen > max_choices
  loop
    raise exception 'Invalid subject combination: %', v_bad.message;
  end loop;

  return new;
end $$;


--
-- Name: check_timetable_student_clash(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.check_timetable_student_clash() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_other text; v_count int;
begin
  select count(*), min(ss.name) into v_count, v_other
  from timetable_slot ts
  join subject_set ss on ss.id = ts.subject_set_id
  where ts.timetable_version_id = new.timetable_version_id
    and ts.cycle_day = new.cycle_day
    and ts.period_id = new.period_id
    and ts.id <> new.id
    and exists (
      select 1
      from set_enrolment a
      join set_enrolment b on b.student_id = a.student_id
      where a.subject_set_id = new.subject_set_id
        and b.subject_set_id = ts.subject_set_id
        and a.effective_to is null
        and b.effective_to is null
    );

  if v_count > 0 then
    raise exception
      'Pupil clash: this set shares pupils with % at day % period %',
      v_other, new.cycle_day,
      (select pd.name from period_definition pd where pd.id = new.period_id)
      using errcode = 'check_violation';
  end if;

  return new;
end $$;


--
-- Name: claims(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.claims() RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;


--
-- Name: custom_access_token_hook(jsonb); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.custom_access_token_hook(event jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_claims jsonb;
  v_extra  jsonb;
begin
  v_claims := coalesce(event -> 'claims', '{}'::jsonb);
  v_extra  := app.build_claims((event ->> 'user_id')::uuid);
  return jsonb_set(event, '{claims}', v_claims || v_extra);
exception when others then
  -- Never block sign-in because claim building failed. The user lands with an
  -- empty school and sees the "not linked to a school" screen instead of a 500.
  return event;
end $$;


--
-- Name: detect_attendance_discrepancy(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.detect_attendance_discrepancy() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare v_register_status attendance_status;
begin
  select ar.status into v_register_status
  from attendance_record ar
  join attendance_session s on s.id = ar.attendance_session_id
  where ar.student_id = new.student_id
    and s.date = new.date
  order by case s.session when 'am' then 0 else 1 end
  limit 1;

  if v_register_status is null then
    return new;
  end if;

  if v_register_status in ('present','late')
     and new.status in ('absent_unauth','absent_auth') then
    insert into attendance_discrepancy
      (school_id, student_id, date, kind, subject_set_id, timetable_slot_id)
    values (new.school_id, new.student_id, new.date,
            'present_on_register_absent_in_class', new.subject_set_id, new.timetable_slot_id);

  elsif v_register_status in ('absent_unauth','absent_auth')
        and new.status in ('present','late') then
    insert into attendance_discrepancy
      (school_id, student_id, date, kind, subject_set_id, timetable_slot_id)
    values (new.school_id, new.student_id, new.date,
            'absent_on_register_present_in_class', new.subject_set_id, new.timetable_slot_id);
  end if;

  return new;
end $$;


--
-- Name: eligibility_threshold(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.eligibility_threshold(p_school uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select coalesce((settings ->> 'exam_eligibility_pct')::numeric, 80)
  from school where id = p_school
$$;


--
-- Name: form_teacher_of(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.form_teacher_of(p_class_group uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$ select app.has_role('form_teacher', p_class_group) $$;


--
-- Name: form_teacher_of_student(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.form_teacher_of_student(p_student uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
  select exists (
    select 1 from class_enrolment ce
    where ce.student_id = p_student
      and ce.effective_to is null
      and app.form_teacher_of(ce.class_group_id)
  )
$$;


--
-- Name: has_cap(text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.has_cap(cap text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select coalesce((app.claims() -> 'caps') ? cap, false)
$$;


--
-- Name: has_role(text, uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.has_role(role_code text, scope_id uuid DEFAULT NULL::uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select exists (
    select 1
    from jsonb_array_elements(coalesce(app.claims() -> 'roles', '[]'::jsonb)) r
    where r ->> 'c' = role_code
      and (scope_id is null or nullif(r ->> 'id','')::uuid = scope_id)
  )
$$;


--
-- Name: hod_of(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.hod_of(p_department uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$ select app.has_role('hod', p_department) $$;


--
-- Name: in_thread(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.in_thread(p_thread uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select exists (
    select 1 from thread_participant tp
    where tp.thread_id = p_thread and tp.person_id = app.person_id()
  )
$$;


--
-- Name: is_guardian_of(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.is_guardian_of(p_student uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
  select exists (
    select 1 from student_guardian sg
    where sg.student_id = p_student and sg.guardian_id = app.person_id()
  )
$$;


--
-- Name: leave_approver_level(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.leave_approver_level() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  new.approver_level := case
    when (new.ends_on - new.starts_on) > 92 then 'director_school_management'
    else 'zone_director' end;
  return new;
end $$;


--
-- Name: person_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.person_id() RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select nullif(app.claims() ->> 'person_id', '')::uuid
$$;


--
-- Name: person_type(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.person_type() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select app.claims() ->> 'person_type'
$$;


--
-- Name: queue_absence_alert(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.queue_absence_alert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_date date; v_student record; g record;
begin
  if new.status <> 'absent_unauth' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'absent_unauth' then return new; end if;

  select s.date into v_date from attendance_session s where s.id = new.attendance_session_id;
  select p.first_name, p.last_name into v_student from person p where p.id = new.student_id;

  for g in
    select sg.guardian_id, pe.preferred_language, gu.preferred_channel
    from student_guardian sg
    join guardian gu on gu.id = sg.guardian_id
    join person pe on pe.id = sg.guardian_id
    where sg.student_id = new.student_id and sg.is_responsible_party
  loop
    insert into notification (school_id, person_id, channel, template, payload)
    values (new.school_id, g.guardian_id, g.preferred_channel, 'absence.unauthorised',
            jsonb_build_object(
              'student_id', new.student_id,
              'student_name', v_student.first_name || ' ' || v_student.last_name,
              'date', v_date,
              'language', g.preferred_language));
  end loop;

  return new;
end $$;


--
-- Name: rebuild_all_attendance_summaries(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.rebuild_all_attendance_summaries() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_rows integer := 0; v_term record;
begin
  for v_term in
    select t.* from term t
    join academic_year y on y.id = t.academic_year_id
    where y.status = 'active'
  loop
    delete from attendance_summary where term_id = v_term.id;

    insert into attendance_summary (
      school_id, academic_year_id, term_id, student_id,
      sessions_possible, sessions_present, sessions_absent_unauth,
      sessions_absent_auth, times_late)
    select
      v_term.school_id, v_term.academic_year_id, v_term.id, ar.student_id,
      count(*),
      count(*) filter (where ar.status in ('present','late','school_activity')),
      count(*) filter (where ar.status = 'absent_unauth'),
      count(*) filter (where ar.status in ('absent_auth','on_leave')),
      count(*) filter (where ar.status = 'late')
    from attendance_session sess
    join attendance_record ar on ar.attendance_session_id = sess.id
    where sess.academic_year_id = v_term.academic_year_id
      and sess.date between v_term.starts_on and v_term.ends_on
    group by ar.student_id;

    get diagnostics v_rows = row_count;
  end loop;
  return v_rows;
end $$;


--
-- Name: record_mark_change(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.record_mark_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  if tg_op = 'UPDATE'
     and (old.score is distinct from new.score or old.code is distinct from new.code) then
    insert into mark_history (school_id, mark_id, old_score, new_score,
                              old_code, new_code, changed_by)
    values (new.school_id, new.id, old.score, new.score, old.code, new.code, app.person_id());
  end if;
  return new;
end $$;


--
-- Name: refresh_attendance_summary(uuid, date); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.refresh_attendance_summary(p_student uuid, p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_term record;
begin
  select t.* into v_term from term t
   where p_date between t.starts_on and t.ends_on
   limit 1;
  if v_term.id is null then return; end if;

  insert into attendance_summary as s (
    school_id, academic_year_id, term_id, student_id,
    sessions_possible, sessions_present, sessions_absent_unauth,
    sessions_absent_auth, times_late, computed_at)
  select
    v_term.school_id, v_term.academic_year_id, v_term.id, p_student,
    count(*),
    count(*) filter (where ar.status in ('present','late','school_activity')),
    count(*) filter (where ar.status = 'absent_unauth'),
    count(*) filter (where ar.status in ('absent_auth','on_leave')),
    count(*) filter (where ar.status = 'late'),
    now()
  from attendance_session sess
  join attendance_record ar on ar.attendance_session_id = sess.id
  where ar.student_id = p_student
    and sess.academic_year_id = v_term.academic_year_id
    and sess.date between v_term.starts_on and v_term.ends_on
  on conflict (term_id, student_id) do update set
    sessions_possible      = excluded.sessions_possible,
    sessions_present       = excluded.sessions_present,
    sessions_absent_unauth = excluded.sessions_absent_unauth,
    sessions_absent_auth   = excluded.sessions_absent_auth,
    times_late             = excluded.times_late,
    computed_at            = excluded.computed_at;
end $$;


--
-- Name: school_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.school_id() RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select nullif(app.claims() ->> 'school_id', '')::uuid
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  new.updated_at := now();
  new.updated_by := app.person_id();
  return new;
end $$;


--
-- Name: storage_owner(text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.storage_owner(p_name text) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_temp'
    AS $$
  select nullif((string_to_array(p_name, '/'))[2], '')::uuid
$$;


--
-- Name: storage_school(text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.storage_school(p_name text) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_temp'
    AS $$
  select nullif((string_to_array(p_name, '/'))[1], '')::uuid
$$;


--
-- Name: teaches_set(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.teaches_set(p_set uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
  select exists (
    select 1 from set_educator se
    where se.subject_set_id = p_set and se.staff_id = app.person_id()
  )
$$;


--
-- Name: thread_owner(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.thread_owner(p_thread uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select exists (
    select 1 from message_thread mt
    where mt.id = p_thread
      and mt.school_id = app.school_id()
      and mt.created_by = app.person_id()
  )
$$;


--
-- Name: visible_schools(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.visible_schools() RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select s.id from school s
  where app.has_cap('platform.manage')                  -- the whole platform
     or (app.has_cap('zone.read')                       -- or one education zone
         and s.zone = (select z.zone from school z where z.id = app.school_id()))
  union
  select app.school_id()                                -- always your own
  where app.school_id() is not null
$$;


--
-- Name: year_is_open(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.year_is_open(p_year uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
  select exists (select 1 from academic_year y where y.id = p_year and y.status = 'active')
$$;


--
-- Name: exam_candidates(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exam_candidates(p_paper uuid) RETURNS TABLE(student_id uuid, first_name text, last_name text, admission_number text, class_name text, arrangement text, extra_minutes smallint, debarred boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with paper as (
    select ep.*, es.academic_year_id
    from exam_paper ep join exam_session es on es.id = ep.exam_session_id
    where ep.id = p_paper and ep.school_id = app.school_id()
  )
  select distinct
    s.id, p.first_name, p.last_name, s.admission_number, cg.name,
    (select string_agg(a.kind, ', ') from exam_arrangement a
      where a.student_id = s.id and a.academic_year_id = pa.academic_year_id),
    (select max(a.extra_minutes) from exam_arrangement a
      where a.student_id = s.id and a.academic_year_id = pa.academic_year_id),
    coalesce(d.decision = 'debar', false)
  from paper pa
  join subject_set ss on ss.subject_id = pa.subject_id
                     and ss.grade_level_id = pa.grade_level_id
                     and ss.academic_year_id = pa.academic_year_id
  join set_enrolment se on se.subject_set_id = ss.id and se.effective_to is null
  join student s on s.id = se.student_id and s.status = 'enrolled'
  join person p on p.id = s.id
  left join class_enrolment ce on ce.student_id = s.id and ce.effective_to is null
  left join class_group cg on cg.id = ce.class_group_id
  left join exam_eligibility_decision d
         on d.student_id = s.id and d.exam_session_id = pa.exam_session_id
  where app.has_cap('school.manage') or app.has_cap('attendance.read.all')
  order by p.last_name, p.first_name;
$$;


--
-- Name: exam_eligibility_screen(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exam_eligibility_screen(p_session uuid) RETURNS TABLE(student_id uuid, first_name text, last_name text, preferred_name text, admission_number text, class_name text, grade smallint, pct_present numeric, threshold numeric, sessions_possible integer, sessions_present integer, shortfall_sessions integer, absent_unauth integer, absent_auth integer, times_late integer, recommended text, decision text, decision_reason text, decided_at timestamp with time zone, guardian_notified_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with sess as (
    select es.*, app.eligibility_threshold(es.school_id) as thr
    from exam_session es
    where es.id = p_session and es.school_id = app.school_id()
  ),
  trm as (
    select t.id
    from term t join sess s on s.academic_year_id = t.academic_year_id
    where s.starts_on between t.starts_on and t.ends_on
    limit 1
  )
  select
    st.id, p.first_name, p.last_name, p.preferred_name, st.admission_number,
    cg.name, gl.grade,
    sm.pct_present, s.thr,
    coalesce(sm.sessions_possible, 0), coalesce(sm.sessions_present, 0),
    greatest(0, ceil(s.thr / 100.0 * coalesce(sm.sessions_possible, 0))::int
                - coalesce(sm.sessions_present, 0)),
    coalesce(sm.sessions_absent_unauth, 0),
    coalesce(sm.sessions_absent_auth, 0),
    coalesce(sm.times_late, 0),
    case when sm.pct_present is null      then 'no_data'
         when sm.pct_present >= s.thr     then 'allow'
         else 'review' end,
    d.decision, d.reason, d.decided_at, d.guardian_notified_at
  from sess s
  cross join trm
  join student st on st.school_id = s.school_id and st.status = 'enrolled'
  join person  p  on p.id = st.id
  left join class_enrolment ce on ce.student_id = st.id and ce.effective_to is null
  left join class_group  cg on cg.id = ce.class_group_id
  left join grade_level  gl on gl.id = cg.grade_level_id
  left join attendance_summary sm on sm.student_id = st.id and sm.term_id = trm.id
  left join exam_eligibility_decision d
         on d.exam_session_id = s.id and d.student_id = st.id
  where app.has_cap('attendance.read.all')
  order by sm.pct_present nulls last, p.last_name;
$$;


--
-- Name: ministry_return(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ministry_return(p_year uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with att as (
    select t.name as term_name,
           round(avg(sm.pct_present), 2) as mean_pct,
           count(*) filter (where sm.pct_present < 80) as below_80
    from attendance_summary sm join term t on t.id = sm.term_id
    where sm.academic_year_id = p_year
    group by t.name
  ),
  days as (
    select t.name as term_name,
           (select count(*) from calendar_day cd
            where cd.term_id = t.id and cd.day_type = 'teaching') as n
    from term t where t.academic_year_id = p_year
  ),
  posts as (
    select post, count(*)::int as n from staff
    where school_id = app.school_id() and exited_on is null
    group by post
  )
  select jsonb_build_object(
    'school', (select jsonb_build_object('code', code, 'name', name,
                        'type', type, 'zone', zone)
               from school where id = app.school_id()),
    'academic_year', (select name from academic_year where id = p_year),
    'generated_at', now(),
    'roll_by_grade', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'grade', grade, 'male', male, 'female', female, 'total', total)), '[]'::jsonb)
      from public.roll_return(current_date)),
    'teaching_days', (
      select coalesce(jsonb_agg(jsonb_build_object('term', term_name, 'days', n)), '[]'::jsonb)
      from days),
    'attendance_by_term', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'term', term_name, 'mean_pct', mean_pct, 'pupils_below_80', below_80)), '[]'::jsonb)
      from att),
    'staff', (
      select jsonb_build_object('total', (select count(*) from posts p2),
                                'by_post', coalesce(jsonb_object_agg(post, n), '{}'::jsonb))
      from posts),
    'results', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'subject', subject_name, 'grade', grade, 'term', term_name,
        'entries', entries, 'mean', mean_score, 'pass_rate', pass_rate)), '[]'::jsonb)
      from results_by_subject)
  )
  where app.has_cap('school.manage');
$$;


--
-- Name: my_lessons(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_lessons(p_date date) RETURNS TABLE(timetable_slot_id uuid, subject_set_id uuid, set_name text, subject_name text, class_hint text, period_id uuid, period_name text, starts_at time without time zone, ends_at time without time zone, room_code text, cycle_day smallint, marked_count bigint, roster_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with day as (
    select cd.cycle_day, cd.academic_year_id
    from calendar_day cd
    where cd.date = p_date
      and cd.school_id = app.school_id()
      and cd.day_type = 'teaching'
  ),
  version as (
    select tv.id
    from timetable_version tv, day d
    where tv.academic_year_id = d.academic_year_id
      and tv.effective_from <= p_date
      and (tv.effective_to is null or tv.effective_to >= p_date)
    order by tv.version desc
    limit 1
  )
  select
    ts.id, ss.id, ss.name, sub.name_en,
    (select string_agg(distinct cg.name, ', ' order by cg.name)
       from set_enrolment se2
       join class_enrolment ce2 on ce2.student_id = se2.student_id and ce2.effective_to is null
       join class_group cg on cg.id = ce2.class_group_id
      where se2.subject_set_id = ss.id and se2.effective_to is null),
    pd.id, pd.name, pd.starts_at, pd.ends_at, r.code, d.cycle_day,
    (select count(*) from period_attendance pa
      where pa.timetable_slot_id = ts.id and pa.date = p_date),
    (select count(*) from set_enrolment se3
      where se3.subject_set_id = ss.id
        and se3.effective_from <= p_date
        and (se3.effective_to is null or se3.effective_to >= p_date))
  from timetable_slot ts
  join version v on v.id = ts.timetable_version_id
  join day d on d.cycle_day = ts.cycle_day
  join subject_set ss on ss.id = ts.subject_set_id
  join subject sub on sub.id = ss.subject_id
  join period_definition pd on pd.id = ts.period_id
  left join room r on r.id = ts.room_id
  where ts.school_id = app.school_id()
    and (
      exists (select 1 from set_educator se
               where se.subject_set_id = ss.id and se.staff_id = app.person_id())
      or app.has_cap('attendance.mark.any')
    )
  order by pd.sequence;
$$;


--
-- Name: platform_overview(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.platform_overview() RETURNS TABLE(school_id uuid, code text, name text, type public.school_type, zone smallint, pupils integer, staff integer, classes integer, mean_attendance numeric, below_threshold integer, open_discrepancies integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    s.id, s.code, s.name, s.type, s.zone,
    (select count(*)::int from student st where st.school_id = s.id and st.status='enrolled'),
    (select count(*)::int from staff sf where sf.school_id = s.id and sf.exited_on is null),
    (select count(*)::int from class_group cg
      join academic_year y on y.id = cg.academic_year_id and y.status='active'
      where cg.school_id = s.id),
    (select round(avg(sm.pct_present),2) from attendance_summary sm where sm.school_id = s.id),
    (select count(distinct sm.student_id)::int from attendance_summary sm
      where sm.school_id = s.id and sm.pct_present < 80),
    (select count(*)::int from attendance_discrepancy ad
      where ad.school_id = s.id and ad.resolved_at is null)
  from school s
  where s.id in (select app.visible_schools())
    and app.has_cap('platform.read.all')
  order by s.zone nulls last, s.name;
$$;


--
-- Name: report_card_data(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.report_card_data(p_term uuid, p_student uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with term_info as (
    select t.*, y.name as year_name
    from term t join academic_year y on y.id = t.academic_year_id
    where t.id = p_term
  ),
  sat as (
    select a.id, a.title, a.kind, a.max_score, a.weight, a.scheduled_on,
           a.subject_set_id,
           a.kind::text || '|' || a.title as col_key,
           case a.kind
             when 'class_test'  then 1 when 'homework' then 1 when 'project' then 1
             when 'practical'   then 2 when 'term_test' then 3
             when 'mock'        then 4 when 'end_of_term' then 5
             when 'end_of_year' then 5 else 6 end as sort_group
    from assessment a
    join mark m on m.assessment_id = a.id and m.student_id = p_student
    where a.term_id = p_term and a.status = 'published'
  ),
  cols as (
    select col_key, kind, title,
           min(sort_group) as sort_group,
           min(scheduled_on) as first_on,
           -- The header shows a total only when every subject marks it the same.
           case when count(distinct max_score) = 1 then max(max_score) end as max_score,
           max(weight) as weight
    from sat
    group by col_key, kind, title
  ),
  subj as (
    select
      tr.subject_id, sub.name_en as subject_name, sub.code as subject_code,
      tr.subject_set_id, tr.aggregate_score, tr.band_label,
      tr.rank_in_set, tr.set_size, tr.educator_comment, tr.difficulties,
      (select string_agg(p2.first_name || ' ' || p2.last_name, ', ')
       from set_educator se join person p2 on p2.id = se.staff_id
       where se.subject_set_id = tr.subject_set_id and se.is_primary) as teacher
    from term_result tr
    join subject sub on sub.id = tr.subject_id
    where tr.term_id = p_term and tr.student_id = p_student
  )
  select jsonb_build_object(
    'school', (select jsonb_build_object(
                 'name', name, 'code', code, 'motto', motto,
                 'logo_path', logo_path, 'address', address, 'contact', contact,
                 'type', type, 'zone', zone)
               from school where id = app.school_id()),

    'term', (select jsonb_build_object(
               'name', name, 'sequence', sequence, 'year', year_name,
               'starts_on', starts_on, 'ends_on', ends_on)
             from term_info),

    'next_term', (select jsonb_build_object('name', t2.name, 'starts_on', t2.starts_on)
                  from term t2, term_info ti
                  where t2.academic_year_id = ti.academic_year_id
                    and t2.sequence = ti.sequence + 1),

    'pupil', (select jsonb_build_object(
                'first_name', p.first_name, 'last_name', p.last_name,
                'preferred_name', p.preferred_name,
                'admission_number', s.admission_number,
                'date_of_birth', p.date_of_birth, 'sex', p.sex,
                'house', s.house, 'extended_programme', s.is_extended_programme,
                'photo_path', p.photo_path)
              from student s join person p on p.id = s.id where s.id = p_student),

    'class', (select jsonb_build_object(
                'name', cg.name, 'stream', cg.stream,
                'grade', gl.grade, 'legacy_form', gl.legacy_form, 'room', r.code,
                'size', (select count(*) from class_enrolment c2
                         where c2.class_group_id = cg.id and c2.effective_to is null),
                'form_teacher', (
                  select string_agg(p3.first_name || ' ' || p3.last_name, ', ')
                  from staff_role_assignment sra join person p3 on p3.id = sra.staff_id
                  where sra.role_code = 'form_teacher' and sra.scope_id = cg.id))
              from class_enrolment ce
              join class_group cg on cg.id = ce.class_group_id
              join grade_level gl on gl.id = cg.grade_level_id
              left join room r on r.id = cg.home_room_id
              where ce.student_id = p_student and ce.effective_to is null),

    'columns', (select coalesce(jsonb_agg(jsonb_build_object(
                  'key', col_key, 'title', title, 'kind', kind,
                  'max_score', max_score, 'weight', weight)
                  order by sort_group, first_on nulls last, title), '[]'::jsonb)
                from cols),

    'subjects', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'subject', s.subject_name, 'code', s.subject_code, 'teacher', s.teacher,
        'aggregate', s.aggregate_score, 'grade', s.band_label,
        'rank_in_set', s.rank_in_set, 'set_size', s.set_size,
        'comment', s.educator_comment, 'difficulties', s.difficulties,
        'marks', (
          select coalesce(jsonb_object_agg(
            x.col_key,
            jsonb_build_object('score', x.score, 'code', x.code, 'max', x.max_score)),
            '{}'::jsonb)
          from (
            select sa.col_key, m.score, m.code, sa.max_score
            from sat sa join mark m on m.assessment_id = sa.id
            where m.student_id = p_student and sa.subject_set_id = s.subject_set_id
          ) x)
      ) order by s.subject_name), '[]'::jsonb)
      from subj s),

    'summary', (select jsonb_build_object(
                  'overall_score', rc.overall_score, 'overall_rank', rc.overall_rank,
                  'class_size', rc.class_size, 'attendance_pct', rc.attendance_pct,
                  'times_late', rc.times_late,
                  'form_teacher_comment', rc.form_teacher_comment,
                  'rector_comment', rc.rector_comment,
                  'status', rc.status, 'published_at', rc.published_at)
                from report_card rc
                where rc.term_id = p_term and rc.student_id = p_student),

    'attendance', (select jsonb_build_object(
                     'sessions_possible', sm.sessions_possible,
                     'sessions_present', sm.sessions_present,
                     'absent_authorised', sm.sessions_absent_auth,
                     'absent_unauthorised', sm.sessions_absent_unauth,
                     'times_late', sm.times_late, 'pct_present', sm.pct_present)
                   from attendance_summary sm
                   where sm.term_id = p_term and sm.student_id = p_student),

    'conduct', jsonb_build_object(
      'merits', (select coalesce(jsonb_agg(jsonb_build_object(
                   'kind', kind, 'reason', reason, 'awarded_on', awarded_on)
                   order by awarded_on desc), '[]'::jsonb)
                 from merit where student_id = p_student),
      'sanctions', (select count(*) from sanction where student_id = p_student),
      'open_cases', (select count(*) from disciplinary_case
                     where student_id = p_student and closed_on is null))
  )
  where app.has_cap('marks.read.all')
     or app.form_teacher_of_student(p_student)
     or p_student = app.person_id()
     or app.is_guardian_of(p_student);
$$;


--
-- Name: roll_return(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.roll_return(p_date date DEFAULT CURRENT_DATE) RETURNS TABLE(grade smallint, male integer, female integer, other integer, total integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select gl.grade,
         count(*) filter (where p.sex = 'male')::int,
         count(*) filter (where p.sex = 'female')::int,
         count(*) filter (where p.sex not in ('male','female') or p.sex is null)::int,
         count(*)::int
  from class_enrolment ce
  join class_group cg on cg.id = ce.class_group_id
  join grade_level gl on gl.id = cg.grade_level_id
  join student s on s.id = ce.student_id
  join person p on p.id = s.id
  where ce.school_id = app.school_id()
    and ce.effective_from <= p_date
    and (ce.effective_to is null or ce.effective_to >= p_date)
    and s.status = 'enrolled'
    and app.has_cap('student.read.all')
  group by gl.grade
  order by gl.grade;
$$;


--
-- Name: rpc_allocate_seats(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_allocate_seats(p_paper uuid, p_strategy text DEFAULT 'separate_class'::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_school uuid; v_rows int := 0;
  cand record; rm record;
  v_row int; v_col int; v_cols int; v_step int; v_seated int; v_left int;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to allocate examination seating';
  end if;
  select ep.school_id into v_school from exam_paper ep where ep.id = p_paper;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown examination paper';
  end if;

  delete from exam_seat where exam_paper_id = p_paper;

  v_step := case when p_strategy = 'spaced' then 2 else 1 end;

  for rm in
    select rms.id as room_id, rms.code as room_code,
           coalesce(rms.exam_capacity, rms.capacity) as cap
    from room rms
    where rms.school_id = v_school and rms.is_active
      and coalesce(rms.exam_capacity, rms.capacity) > 0
    order by coalesce(rms.exam_capacity, rms.capacity) desc
  loop
    v_cols := greatest(1, ceil(sqrt(rm.cap))::int);
    v_row := 1; v_col := 1; v_seated := 0;

    for cand in
      select c.student_id, c.class_name, c.admission_number
      from public.exam_candidates(p_paper) c
      where not c.debarred
        and not exists (select 1 from exam_seat s
                        where s.exam_paper_id = p_paper and s.student_id = c.student_id)
      -- Hashing on class scatters classmates so neighbours are rarely from the
      -- same class; ordering by admission number keeps a tight hall predictable.
      order by case when p_strategy = 'separate_class'
                    then md5(coalesce(c.class_name,'') || c.student_id::text)
                    else c.admission_number end
    loop
      exit when v_seated >= rm.cap;

      insert into exam_seat (school_id, exam_paper_id, student_id, room_id,
                             seat_label, row_no, col_no)
      values (v_school, p_paper, cand.student_id, rm.room_id,
              rm.room_code || '-' || v_row || chr(64 + v_col), v_row, v_col);
      v_rows := v_rows + 1;
      v_seated := v_seated + 1;

      v_col := v_col + v_step;
      if v_col > v_cols then v_col := 1; v_row := v_row + 1; end if;
    end loop;
  end loop;

  select count(*) into v_left
  from public.exam_candidates(p_paper) c
  where not c.debarred
    and not exists (select 1 from exam_seat s
                    where s.exam_paper_id = p_paper and s.student_id = c.student_id);

  if v_left > 0 then
    raise exception 'Not enough examination places: % candidate(s) unseated after seating %',
      v_left, v_rows;
  end if;

  return v_rows;
end $$;


--
-- Name: rpc_amend_attendance(uuid, public.attendance_status, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_amend_attendance(p_record_id uuid, p_status public.attendance_status, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare v_class uuid;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'A reason is required to amend a closed register';
  end if;

  select s.class_group_id into v_class
  from attendance_record ar join attendance_session s on s.id = ar.attendance_session_id
  where ar.id = p_record_id;

  if v_class is null then raise exception 'Unknown attendance record'; end if;
  if not (app.form_teacher_of(v_class) or app.has_cap('attendance.amend')) then
    raise exception 'Not authorised to amend this register';
  end if;

  update attendance_record
     set status = p_status, amended_by = app.person_id(),
         amended_at = now(), amend_reason = p_reason
   where id = p_record_id and school_id = app.school_id();

  update attendance_session s set status = 'amended'
   from attendance_record ar
  where ar.id = p_record_id and s.id = ar.attendance_session_id;
end $$;


--
-- Name: rpc_amend_mark(uuid, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_amend_mark(p_mark uuid, p_score numeric, p_code text, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Not authorised to amend a submitted mark';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required to amend a mark';
  end if;

  update mark set score = p_score, code = p_code, entered_by = app.person_id()
   where id = p_mark and school_id = app.school_id();
  if not found then raise exception 'Mark not found'; end if;

  update mark_history set reason = p_reason
   where mark_id = p_mark
     and changed_at = (select max(changed_at) from mark_history where mark_id = p_mark);
end $$;


--
-- Name: rpc_apply_timetable(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_apply_timetable(p_version uuid, p_placements jsonb) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_status text; v_rows int;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;
  select school_id, status into v_school, v_status from timetable_version
   where id = p_version and school_id = app.school_id();
  if v_school is null then raise exception 'Unknown timetable version'; end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;

  delete from timetable_slot where timetable_version_id = p_version;

  insert into timetable_slot (school_id, timetable_version_id, cycle_day, period_id,
                              subject_set_id, room_id, staff_id, is_double_start)
  select v_school, p_version,
         (p ->> 'cycleDay')::smallint,
         (p ->> 'periodId')::uuid,
         (p ->> 'setId')::uuid,
         nullif(p ->> 'roomId','')::uuid,
         nullif(p ->> 'educatorId','')::uuid,
         coalesce((p ->> 'isDoubleStart')::boolean, false)
  from jsonb_array_elements(p_placements) p;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_approve_scheme(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_approve_scheme(p_scheme uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare s record;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Only the Rector approves schemes of work';
  end if;
  select * into s from scheme_of_work where id = p_scheme and school_id = app.school_id();
  if s.status <> 'hod_approved' then
    raise exception 'The Head of Department must vet this first';
  end if;
  update scheme_of_work
     set status = 'rector_approved', rector_approved_by = app.person_id(),
         rector_approved_at = now()
   where id = p_scheme;
end $$;


--
-- Name: rpc_assign_invigilators(uuid, smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_assign_invigilators(p_paper uuid, p_per_room smallint DEFAULT 1) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_school uuid; v_session uuid; v_date date; v_rows int := 0;
  rm record; st record; i int;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to assign invigilation';
  end if;
  select ep.school_id, ep.exam_session_id, ep.date
    into v_school, v_session, v_date
  from exam_paper ep where ep.id = p_paper and ep.school_id = app.school_id();
  if v_school is null then raise exception 'Unknown examination paper'; end if;

  delete from invigilation_duty where exam_paper_id = p_paper;

  for rm in
    select distinct s.room_id from exam_seat s where s.exam_paper_id = p_paper
  loop
    i := 0;
    for st in
      select stf.id,
             (select count(*) from invigilation_duty d
              join exam_paper ep2 on ep2.id = d.exam_paper_id
              where d.staff_id = stf.id and ep2.exam_session_id = v_session) as load
      from staff stf
      where stf.school_id = v_school and stf.exited_on is null
        and stf.id not in (
          select sl.staff_id from staff_leave sl
          where v_date between sl.starts_on and sl.ends_on and sl.status = 'approved')
        and stf.id not in (
          select d2.staff_id from invigilation_duty d2 where d2.exam_paper_id = p_paper)
      order by load, random()
      limit p_per_room
    loop
      insert into invigilation_duty (school_id, exam_paper_id, room_id, staff_id, role)
      values (v_school, p_paper, rm.room_id, st.id,
              case when i = 0 then 'chief' else 'invigilator' end)
      on conflict do nothing;
      v_rows := v_rows + 1;
      i := i + 1;
    end loop;
  end loop;

  return v_rows;
end $$;


--
-- Name: rpc_build_report_cards(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_build_report_cards(p_term uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_year uuid; v_rows int;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Not authorised to build report cards';
  end if;
  select school_id, academic_year_id into v_school, v_year
  from term where id = p_term;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown term';
  end if;

  -- Overall aggregate across subjects, and rank within the pupil's own class.
  with overall as (
    select tr.student_id,
           round(avg(tr.aggregate_score), 2) as overall_score
    from term_result tr
    where tr.term_id = p_term
    group by tr.student_id
  ),
  placed as (
    select o.student_id, o.overall_score, ce.class_group_id,
           dense_rank() over (partition by ce.class_group_id
                              order by o.overall_score desc nulls last) as rank_in_class,
           count(*) over (partition by ce.class_group_id) as class_size
    from overall o
    join class_enrolment ce on ce.student_id = o.student_id and ce.effective_to is null
  )
  insert into report_card (school_id, term_id, student_id, overall_score,
                           overall_rank, class_size, attendance_pct, times_late)
  select v_school, p_term, p.student_id, p.overall_score,
         p.rank_in_class, p.class_size, sm.pct_present, sm.times_late
  from placed p
  left join attendance_summary sm
         on sm.student_id = p.student_id and sm.term_id = p_term
  on conflict (term_id, student_id) do update set
    overall_score  = excluded.overall_score,
    overall_rank   = excluded.overall_rank,
    class_size     = excluded.class_size,
    attendance_pct = excluded.attendance_pct,
    times_late     = excluded.times_late;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_close_register(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_close_register(p_session_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare v_class uuid;
begin
  select class_group_id into v_class from attendance_session where id = p_session_id;
  if v_class is null then raise exception 'Unknown session'; end if;
  if not (app.form_teacher_of(v_class) or app.has_cap('attendance.mark.any')) then
    raise exception 'Not authorised to close this register';
  end if;
  update attendance_session
     set status = 'closed', closed_at = now()
   where id = p_session_id and school_id = app.school_id();
end $$;


--
-- Name: rpc_compute_term_results(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_compute_term_results(p_term uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_rows integer; v_school uuid;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Not authorised to compute term results';
  end if;
  select school_id into v_school from term where id = p_term;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown term';
  end if;

  delete from term_result where term_id = p_term;

  with scored as (
    select
      m.student_id, a.subject_id, a.subject_set_id, a.grading_scale_id,
      sum(case when m.code in ('EXEMPT','MED') then 0
               else (coalesce(m.score, 0) / a.max_score) * a.weight end) as num,
      sum(case when m.code in ('EXEMPT','MED') then 0 else a.weight end)  as den
    from mark m
    join assessment a on a.id = m.assessment_id
    where a.term_id = p_term
      and a.counts_for_promotion
      and a.school_id = v_school
    group by m.student_id, a.subject_id, a.subject_set_id, a.grading_scale_id
  ),
  agg as (
    select student_id, subject_id, subject_set_id, grading_scale_id,
           case when den > 0 then round(100.0 * num / den, 2) end as pct
    from scored
  ),
  ranked as (
    select *,
      dense_rank() over (partition by subject_set_id order by pct desc nulls last) as r_set,
      dense_rank() over (partition by subject_id     order by pct desc nulls last) as r_grade,
      count(*)     over (partition by subject_set_id) as set_size
    from agg
  )
  insert into term_result (school_id, term_id, student_id, subject_id, subject_set_id,
                           aggregate_score, band_label, rank_in_set, rank_in_grade, set_size)
  select v_school, p_term, student_id, subject_id, subject_set_id,
         pct, app.band_for(grading_scale_id, pct), r_set, r_grade, set_size
  from ranked;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_decide_absence_note(uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_decide_absence_note(p_note uuid, p_accept boolean, p_note_text text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare n record; v_rows int := 0;
begin
  if not app.has_cap('attendance.resolve') then
    raise exception 'Not authorised to decide absence notes';
  end if;

  select * into n from absence_note where id = p_note and school_id = app.school_id();
  if n.id is null then raise exception 'Unknown absence note'; end if;

  update absence_note
     set status = case when p_accept then 'accepted' else 'rejected' end,
         decided_by = app.person_id(), decided_at = now(), decision_note = p_note_text
   where id = p_note;

  if p_accept then
    update attendance_record ar
       set status = 'absent_auth',
           note = concat_ws(' ', ar.note, '[absence note accepted]')
      from attendance_session s
     where s.id = ar.attendance_session_id
       and ar.student_id = n.student_id
       and s.date between n.covers_from and n.covers_to
       and ar.status = 'absent_unauth'
       and ar.school_id = app.school_id();
    get diagnostics v_rows = row_count;
  end if;

  return v_rows;
end $$;


--
-- Name: rpc_decide_eligibility(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_decide_eligibility(p_session uuid, p_student uuid, p_decision text, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_thr numeric; v_pct numeric; v_term uuid;
begin
  if not app.has_cap('attendance.read.all') then
    raise exception 'Not authorised to decide exam eligibility';
  end if;
  if p_decision not in ('allow','debar') then
    raise exception 'Decision must be allow or debar';
  end if;
  if p_decision = 'debar' and coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required to debar a candidate from an examination';
  end if;

  select es.school_id into v_school from exam_session es
   where es.id = p_session and es.school_id = app.school_id();
  if v_school is null then raise exception 'Unknown exam session'; end if;

  v_thr := app.eligibility_threshold(v_school);

  select t.id into v_term
  from term t join exam_session es on es.academic_year_id = t.academic_year_id
  where es.id = p_session and es.starts_on between t.starts_on and t.ends_on
  limit 1;

  select sm.pct_present into v_pct from attendance_summary sm
   where sm.student_id = p_student and sm.term_id = v_term;

  insert into exam_eligibility_decision (
    school_id, exam_session_id, student_id, attendance_pct, threshold,
    decision, decided_by, reason)
  values (v_school, p_session, p_student, v_pct, v_thr,
          p_decision, app.person_id(), p_reason)
  on conflict (exam_session_id, student_id) do update set
    decision       = excluded.decision,
    reason         = excluded.reason,
    decided_by     = excluded.decided_by,
    decided_at     = now(),
    attendance_pct = excluded.attendance_pct,
    threshold      = excluded.threshold;
end $$;


--
-- Name: rpc_declare_closure(uuid, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_declare_closure(p_year_id uuid, p_date date, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to declare a closure';
  end if;

  update calendar_day
     set day_type = 'closure', closure_reason = p_reason, cycle_day = null
   where academic_year_id = p_year_id and date = p_date
     and school_id = app.school_id();

  -- attendance taken for a day that turned out to be a closure is voided,
  -- not deleted: the record of what was marked survives in audit_log.
  update attendance_record ar
     set status = 'school_activity', note = coalesce(ar.note,'') || ' [voided: ' || p_reason || ']'
    from attendance_session s
   where s.id = ar.attendance_session_id
     and s.date = p_date
     and s.academic_year_id = p_year_id
     and ar.school_id = app.school_id();

  update attendance_session
     set status = 'amended'
   where date = p_date and academic_year_id = p_year_id and school_id = app.school_id();
end $$;


--
-- Name: rpc_escalate_case(uuid, public.case_stage, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_escalate_case(p_case uuid, p_stage public.case_stage, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare c record;
begin
  if not app.has_cap('discipline.escalate') then
    raise exception 'Not authorised to escalate a disciplinary case';
  end if;
  select * into c from disciplinary_case where id = p_case and school_id = app.school_id();
  if c.id is null then raise exception 'Unknown case'; end if;

  update disciplinary_case set stage = p_stage,
         closed_on = case when p_stage = 'closed' then current_date else null end
   where id = p_case;

  insert into occurrence_log (school_id, occurred_at, entered_by, category, entry)
  values (c.school_id, now(), app.person_id(), 'discipline',
          format('Case %s escalated to %s%s', p_case, p_stage,
                 case when p_note is null then '' else ': ' || p_note end));

  if p_stage in ('parent_contact','special_report','disciplinary_committee') then
    insert into notification (school_id, person_id, channel, template, payload)
    select c.school_id, sg.guardian_id, gu.preferred_channel, 'discipline.escalation',
           jsonb_build_object('student_id', c.student_id, 'stage', p_stage)
    from student_guardian sg join guardian gu on gu.id = sg.guardian_id
    where sg.student_id = c.student_id and sg.is_responsible_party;
  end if;
end $$;


--
-- Name: rpc_generate_school_calendar(uuid, smallint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_generate_school_calendar(p_year_id uuid, p_cycle_length smallint DEFAULT 5) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare
  v_school uuid;
  v_days   integer := 0;
  v_cycle  smallint := 0;
  r        record;
begin
  select school_id into v_school from academic_year where id = p_year_id;
  if v_school is null then raise exception 'Unknown academic year %', p_year_id; end if;
  if v_school <> app.school_id() or not app.has_cap('school.manage') then
    raise exception 'Not authorised to generate the calendar';
  end if;

  delete from calendar_day where academic_year_id = p_year_id;

  for r in
    select t.id as term_id, d::date as day
    from term t, generate_series(t.starts_on, t.ends_on, interval '1 day') d
    where t.academic_year_id = p_year_id
    order by d
  loop
    if extract(isodow from r.day) >= 6 then
      insert into calendar_day (school_id, academic_year_id, term_id, date, day_type)
      values (v_school, p_year_id, r.term_id, r.day, 'weekend');
    elsif exists (select 1 from public_holiday h
                  where h.country = 'MU' and h.date = r.day) then
      insert into calendar_day (school_id, academic_year_id, term_id, date, day_type, note)
      select v_school, p_year_id, r.term_id, r.day, 'holiday', h.name
      from public_holiday h where h.country = 'MU' and h.date = r.day limit 1;
    else
      v_cycle := (v_cycle % p_cycle_length) + 1;
      insert into calendar_day (school_id, academic_year_id, term_id, date, day_type, cycle_day)
      values (v_school, p_year_id, r.term_id, r.day, 'teaching', v_cycle);
      v_days := v_days + 1;
    end if;
  end loop;

  return v_days;
end $$;


--
-- Name: rpc_generate_weekly_plan(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_generate_weekly_plan(p_set uuid, p_week_start date) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_plan uuid; v_rows int;
begin
  select ss.school_id into v_school from subject_set ss where ss.id = p_set;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown subject set';
  end if;
  if not app.teaches_set(p_set) then
    raise exception 'You do not teach this set';
  end if;

  insert into weekly_plan (school_id, staff_id, subject_set_id, week_start)
  values (v_school, app.person_id(), p_set, p_week_start)
  on conflict (subject_set_id, week_start) do update set status = weekly_plan.status
  returning id into v_plan;

  insert into weekly_plan_row (school_id, weekly_plan_id, timetable_slot_id, date)
  select v_school, v_plan, ts.id, cd.date
  from calendar_day cd
  join timetable_version tv on tv.academic_year_id = cd.academic_year_id
                           and tv.status = 'published'
                           and tv.effective_from <= cd.date
                           and (tv.effective_to is null or tv.effective_to >= cd.date)
  join timetable_slot ts on ts.timetable_version_id = tv.id
                        and ts.cycle_day = cd.cycle_day
                        and ts.subject_set_id = p_set
  where cd.school_id = v_school
    and cd.day_type = 'teaching'
    and cd.date between p_week_start and p_week_start + 6
    and not exists (
      select 1 from weekly_plan_row r
      where r.weekly_plan_id = v_plan and r.date = cd.date
        and r.timetable_slot_id = ts.id);

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_issue_leaving_certificate(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_issue_leaving_certificate(p_student uuid, p_reason text, p_conduct text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_outstanding int; v_uncleared text; v_id uuid; v_att jsonb;
begin
  if not app.has_cap('student.manage') then
    raise exception 'Not authorised to issue a Leaving Certificate';
  end if;
  select school_id into v_school from student where id = p_student;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown pupil';
  end if;

  select count(*) into v_outstanding from library_loan
   where student_id = p_student and returned_on is null;
  if v_outstanding > 0 then
    raise exception 'Cannot issue: % library book(s) outstanding', v_outstanding;
  end if;

  select string_agg(kind, ', ') into v_uncleared
  from clearance_item where student_id = p_student and not cleared;
  if v_uncleared is not null then
    raise exception 'Cannot issue: not cleared for %', v_uncleared;
  end if;

  -- Attendance is recorded on the Leaving Certificate.
  select jsonb_agg(jsonb_build_object(
           'term', t.name, 'pct_present', sm.pct_present,
           'sessions_possible', sm.sessions_possible,
           'sessions_present', sm.sessions_present))
    into v_att
  from attendance_summary sm join term t on t.id = sm.term_id
  where sm.student_id = p_student;

  insert into leaving_certificate (school_id, student_id, attendance_summary,
                                   conduct, reason, issued_by)
  values (v_school, p_student, coalesce(v_att, '[]'::jsonb), p_conduct, p_reason, app.person_id())
  on conflict (student_id) do update set
    issued_on = current_date, attendance_summary = excluded.attendance_summary,
    conduct = excluded.conduct, reason = excluded.reason, issued_by = excluded.issued_by
  returning id into v_id;

  update student set status = 'left', left_on = current_date, leaving_reason = p_reason
   where id = p_student;

  return v_id;
end $$;


--
-- Name: rpc_move_timetable_slot(uuid, smallint, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_move_timetable_slot(p_slot uuid, p_cycle_day smallint, p_period uuid, p_room uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_status text; v_school uuid;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;

  select tv.status, ts.school_id into v_status, v_school
  from timetable_slot ts join timetable_version tv on tv.id = ts.timetable_version_id
  where ts.id = p_slot;

  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown lesson';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;

  update timetable_slot
     set cycle_day = p_cycle_day,
         period_id = p_period,
         room_id   = coalesce(p_room, room_id)
   where id = p_slot;
end $$;


--
-- Name: rpc_open_register(uuid, date, public.session_type); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_open_register(p_class_group_id uuid, p_date date, p_session public.session_type) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare
  v_session uuid;
  v_school  uuid;
  v_year    uuid;
begin
  select cg.school_id, cg.academic_year_id into v_school, v_year
  from class_group cg where cg.id = p_class_group_id;

  if v_school is null then raise exception 'Unknown class group'; end if;
  if v_school <> app.school_id()
     or not (app.form_teacher_of(p_class_group_id) or app.has_cap('attendance.mark.any')) then
    raise exception 'Not authorised to open this register';
  end if;
  if not app.year_is_open(v_year) then raise exception 'Academic year is closed'; end if;
  if not exists (select 1 from calendar_day cd
                 where cd.academic_year_id = v_year and cd.date = p_date
                   and cd.day_type = 'teaching') then
    raise exception 'No school on % — register cannot be opened', p_date;
  end if;

  insert into attendance_session (school_id, academic_year_id, class_group_id, date, session, taken_by, taken_at)
  values (v_school, v_year, p_class_group_id, p_date, p_session, app.person_id(), now())
  on conflict (class_group_id, date, session) do update set taken_at = coalesce(attendance_session.taken_at, now())
  returning id into v_session;

  insert into attendance_record (school_id, attendance_session_id, student_id, status, recorded_by)
  select v_school, v_session, ce.student_id, 'present', app.person_id()
  from class_enrolment ce
  where ce.class_group_id = p_class_group_id
    and ce.effective_from <= p_date
    and (ce.effective_to is null or ce.effective_to >= p_date)
  on conflict (attendance_session_id, student_id) do nothing;

  return v_session;
end $$;


--
-- Name: rpc_place_lesson(uuid, uuid, smallint, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_place_lesson(p_version uuid, p_set uuid, p_cycle_day smallint, p_period uuid, p_room uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_staff uuid; v_id uuid; v_status text;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;
  select tv.status, tv.school_id into v_status, v_school
  from timetable_version tv where tv.id = p_version;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown timetable version';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;

  select se.staff_id into v_staff from set_educator se
   where se.subject_set_id = p_set and se.is_primary limit 1;

  insert into timetable_slot (school_id, timetable_version_id, cycle_day,
                              period_id, subject_set_id, room_id, staff_id)
  values (v_school, p_version, p_cycle_day, p_period, p_set, p_room, v_staff)
  returning id into v_id;

  return v_id;
end $$;


--
-- Name: rpc_prefill_period(uuid, uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_prefill_period(p_slot uuid, p_set uuid, p_date date) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_school uuid; v_rows integer;
begin
  select school_id into v_school from subject_set where id = p_set;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown subject set';
  end if;
  if not (exists (select 1 from set_educator se
                   where se.subject_set_id = p_set and se.staff_id = app.person_id())
          or app.has_cap('attendance.mark.any')) then
    raise exception 'You do not teach this set';
  end if;
  if not exists (select 1 from calendar_day cd
                 where cd.date = p_date and cd.school_id = v_school
                   and cd.day_type = 'teaching') then
    raise exception 'No school on %', p_date;
  end if;

  insert into period_attendance (school_id, date, timetable_slot_id, subject_set_id,
                                 student_id, status, recorded_by)
  select v_school, p_date, p_slot, p_set, se.student_id,
         coalesce(
           (select ar.status
              from attendance_record ar
              join attendance_session sess on sess.id = ar.attendance_session_id
             where ar.student_id = se.student_id and sess.date = p_date
             order by case sess.session when 'am' then 0 else 1 end
             limit 1),
           'present'::attendance_status),
         app.person_id()
  from set_enrolment se
  where se.subject_set_id = p_set
    and se.effective_from <= p_date
    and (se.effective_to is null or se.effective_to >= p_date)
  on conflict (subject_set_id, date, timetable_slot_id, student_id) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_provision_school(text, text, public.school_type, smallint, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_provision_school(p_code text, p_name text, p_type public.school_type DEFAULT 'state'::public.school_type, p_zone smallint DEFAULT NULL::smallint, p_year_name text DEFAULT NULL::text, p_terms jsonb DEFAULT NULL::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare
  v_school uuid; v_year uuid; v_term jsonb; v_seq smallint := 0;
  v_cycle smallint := 5; v_c smallint := 0; r record; g smallint;
begin
  if not app.has_cap('platform.manage') then
    raise exception 'Only a platform administrator may create a school';
  end if;
  if exists (select 1 from school where code = p_code) then
    raise exception 'A school with code % already exists', p_code;
  end if;

  insert into school (code, name, type, zone, settings)
  values (p_code, p_name, p_type, p_zone,
          jsonb_build_object(
            'exam_eligibility_pct', 80,
            'second_attempt_pct', 75,
            'internal_exam_max_days', 10,
            'suppress_ranks_grades', jsonb_build_array(7,8),
            'enforce_option_blocks', false))
  returning id into v_school;

  -- Grades 7–13 with the legacy Form names still used inside schools.
  for g in 7..13 loop
    insert into grade_level (school_id, grade, legacy_form, cycle_stage)
    values (v_school, g,
            case g when 7 then 'Form I' when 8 then 'Form II' when 9 then 'Form III'
                   when 10 then 'Form IV' when 11 then 'Form V'
                   when 12 then 'Lower VI' else 'Upper VI' end,
            case when g <= 9 then 'lower_secondary'
                 when g <= 11 then 'upper_secondary_sc'
                 else 'upper_secondary_hsc' end);
  end loop;

  -- Standing committees the School Management Manual names.
  if p_year_name is not null and p_terms is not null then
    insert into academic_year (school_id, name, starts_on, ends_on, status)
    values (v_school, p_year_name,
            (p_terms->0->>'starts_on')::date,
            (p_terms->(jsonb_array_length(p_terms)-1)->>'ends_on')::date,
            'active')
    returning id into v_year;

    for v_term in select * from jsonb_array_elements(p_terms) loop
      v_seq := v_seq + 1;
      insert into term (school_id, academic_year_id, sequence, name, starts_on, ends_on)
      values (v_school, v_year, v_seq, v_term->>'name',
              (v_term->>'starts_on')::date, (v_term->>'ends_on')::date);
    end loop;

    -- Expand the calendar: weekdays in term, minus Mauritian public holidays.
    for r in
      select t.id as term_id, d::date as day
      from term t, generate_series(t.starts_on, t.ends_on, interval '1 day') d
      where t.academic_year_id = v_year
      order by d
    loop
      if extract(isodow from r.day) >= 6 then
        insert into calendar_day (school_id, academic_year_id, term_id, date, day_type)
        values (v_school, v_year, r.term_id, r.day, 'weekend');
      elsif exists (select 1 from public_holiday h where h.country='MU' and h.date = r.day) then
        insert into calendar_day (school_id, academic_year_id, term_id, date, day_type, note)
        select v_school, v_year, r.term_id, r.day, 'holiday', h.name
        from public_holiday h where h.country='MU' and h.date = r.day limit 1;
      else
        v_c := (v_c % v_cycle) + 1;
        insert into calendar_day (school_id, academic_year_id, term_id, date, day_type, cycle_day)
        values (v_school, v_year, r.term_id, r.day, 'teaching', v_c);
      end if;
    end loop;

    insert into committee (school_id, academic_year_id, code, name, min_meetings_per_term)
    select v_school, v_year, c.code, c.name, c.n
    from (values
      ('disciplinary','Disciplinary Committee',2), ('pastoral','Pastoral Care Committee',2),
      ('staff_welfare','Staff Welfare Committee',1), ('sports','Sports Committee',1),
      ('events','Event Organising Committee',1), ('magazine','School Magazine Editing Committee',1),
      ('pedagogical','Pedagogical Committee',2), ('pta','PTA Executive Committee',2),
      ('student_council','Student Council',2)
    ) as c(code,name,n);
  end if;

  insert into occurrence_log (school_id, occurred_at, entered_by, category, entry)
  values (v_school, now(), app.person_id(), 'platform',
          format('School %s (%s) provisioned', p_name, p_code));

  return v_school;
end $$;


--
-- Name: rpc_publish_report_cards(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_publish_report_cards(p_term uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_rows int;
begin
  if not app.has_cap('marks.publish') then
    raise exception 'Only the Rector publishes report cards';
  end if;
  update report_card set status = 'published', published_at = now()
   where term_id = p_term and school_id = app.school_id() and status = 'draft';
  get diagnostics v_rows = row_count;

  insert into notification (school_id, person_id, channel, template, payload)
  select rc.school_id, sg.guardian_id, g.preferred_channel, 'report_card.published',
         jsonb_build_object('student_id', rc.student_id, 'term_id', p_term)
  from report_card rc
  join student_guardian sg on sg.student_id = rc.student_id and sg.is_responsible_party
  join guardian g on g.id = sg.guardian_id
  where rc.term_id = p_term and rc.status = 'published';

  return v_rows;
end $$;


--
-- Name: rpc_publish_timetable(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_publish_timetable(p_version uuid, p_from date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_year uuid;
begin
  if not app.has_cap('timetable.publish') then
    raise exception 'Not authorised to publish a timetable';
  end if;
  select academic_year_id into v_year from timetable_version
   where id = p_version and school_id = app.school_id();
  if v_year is null then raise exception 'Unknown timetable version'; end if;

  -- Close off whatever was in force, so historical period attendance still
  -- resolves against the version that applied on its own date.
  update timetable_version
     set status = 'superseded', effective_to = p_from - 1
   where academic_year_id = v_year and status = 'published'
     and school_id = app.school_id() and id <> p_version;

  update timetable_version
     set status = 'published', effective_from = p_from,
         published_by = app.person_id(), published_at = now()
   where id = p_version;
end $$;


--
-- Name: rpc_recompute_attendance_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_recompute_attendance_summary(p_term_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app'
    AS $$
declare v_rows integer;
begin
  if not app.has_cap('attendance.read.all') then
    raise exception 'Not authorised';
  end if;

  delete from attendance_summary where term_id = p_term_id;

  insert into attendance_summary (
    school_id, academic_year_id, term_id, student_id,
    sessions_possible, sessions_present, sessions_absent_unauth,
    sessions_absent_auth, times_late)
  select
    t.school_id, t.academic_year_id, t.id, ar.student_id,
    count(*),
    count(*) filter (where ar.status in ('present','late','school_activity')),
    count(*) filter (where ar.status = 'absent_unauth'),
    count(*) filter (where ar.status in ('absent_auth','on_leave')),
    count(*) filter (where ar.status = 'late')
  from term t
  join attendance_session s on s.academic_year_id = t.academic_year_id
                           and s.date between t.starts_on and t.ends_on
  join attendance_record ar on ar.attendance_session_id = s.id
  where t.id = p_term_id and t.school_id = app.school_id()
  group by t.school_id, t.academic_year_id, t.id, ar.student_id;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;


--
-- Name: rpc_record_coverage(uuid, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_record_coverage(p_row uuid, p_actual text, p_covered boolean, p_remarks text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  update weekly_plan_row r
     set actual = p_actual, covered = p_covered, remarks = p_remarks
    from weekly_plan w
   where r.id = p_row and w.id = r.weekly_plan_id and w.staff_id = app.person_id();
  if not found then raise exception 'Not your weekly plan'; end if;
end $$;


--
-- Name: rpc_remove_lesson(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_remove_lesson(p_slot uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_status text; v_school uuid;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to change the timetable';
  end if;
  select tv.status, ts.school_id into v_status, v_school
  from timetable_slot ts join timetable_version tv on tv.id = ts.timetable_version_id
  where ts.id = p_slot;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown lesson';
  end if;
  if v_status = 'published' then
    raise exception 'Published timetables are immutable — create a new version';
  end if;
  delete from timetable_slot where id = p_slot;
end $$;


--
-- Name: rpc_resolve_discrepancy(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_resolve_discrepancy(p_id uuid, p_outcome text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  if not app.has_cap('attendance.resolve') then
    raise exception 'Not authorised to resolve discrepancies';
  end if;
  if p_outcome not in ('found_on_premises','left_school','medical_room','authorised','unresolved') then
    raise exception 'Invalid outcome %', p_outcome;
  end if;

  update attendance_discrepancy
     set outcome     = p_outcome,
         resolved_by = app.person_id(),
         resolved_at = now()
   where id = p_id
     and school_id = app.school_id();

  if not found then
    raise exception 'Discrepancy not found or not visible to you';
  end if;

  -- A pupil who left school unauthorised is an attendance fact, not just a
  -- note: reflect it on the register so the day's figures stay honest.
  if p_outcome = 'left_school' then
    update attendance_record ar
       set status = 'absent_unauth',
           note = concat_ws(' ', ar.note, '[left school — discrepancy resolved]')
      from attendance_session sess, attendance_discrepancy d
     where d.id = p_id
       and sess.id = ar.attendance_session_id
       and sess.date = d.date
       and ar.student_id = d.student_id
       and sess.session = 'pm'
       and ar.school_id = app.school_id();
  end if;
end $$;


--
-- Name: rpc_review_scheme(uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_review_scheme(p_scheme uuid, p_approve boolean, p_comment text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare s record;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Vetting a scheme of work is a Head of Department function';
  end if;
  select * into s from scheme_of_work where id = p_scheme and school_id = app.school_id();
  if s.id is null then raise exception 'Unknown scheme of work'; end if;
  if s.status <> 'submitted' then
    raise exception 'Only a submitted scheme can be vetted';
  end if;
  if not p_approve and coalesce(trim(p_comment),'') = '' then
    raise exception 'Say why you are returning it — the educator has to act on it';
  end if;

  update scheme_of_work
     set status = (case when p_approve then 'hod_approved' else 'hod_returned' end)::plan_status,
         hod_reviewed_by = app.person_id(), hod_reviewed_at = now(),
         hod_comment = p_comment
   where id = p_scheme;
end $$;


--
-- Name: rpc_set_assessment_status(uuid, public.assessment_status); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_set_assessment_status(p_assessment uuid, p_status public.assessment_status) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare a record;
begin
  select * into a from assessment where id = p_assessment and school_id = app.school_id();
  if a.id is null then raise exception 'Unknown assessment'; end if;

  if p_status in ('draft','open','submitted') then
    if not (app.teaches_set(a.subject_set_id) or app.has_cap('marks.moderate')) then
      raise exception 'You do not teach this set';
    end if;
  elsif p_status = 'moderated' then
    if not app.has_cap('marks.moderate') then
      raise exception 'Moderation is a Head of Department or SMT function';
    end if;
    if a.status <> 'submitted' then
      raise exception 'Only a submitted assessment can be moderated';
    end if;
  elsif p_status = 'published' then
    if not app.has_cap('marks.publish') then
      raise exception 'Only the Rector may publish marks';
    end if;
    if a.status <> 'moderated' then
      raise exception 'Marks must be moderated before publication';
    end if;
  end if;

  update assessment set
    status       = p_status,
    submitted_by = case when p_status='submitted' then app.person_id() else submitted_by end,
    submitted_at = case when p_status='submitted' then now() else submitted_at end,
    moderated_by = case when p_status='moderated' then app.person_id() else moderated_by end,
    moderated_at = case when p_status='moderated' then now() else moderated_at end,
    published_by = case when p_status='published' then app.person_id() else published_by end,
    published_at = case when p_status='published' then now() else published_at end
  where id = p_assessment;
end $$;


--
-- Name: rpc_set_report_comment(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_set_report_comment(p_term uuid, p_student uuid, p_which text, p_comment text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
begin
  if p_which = 'form_teacher' then
    if not (app.form_teacher_of_student(p_student) or app.has_cap('marks.moderate')) then
      raise exception 'Only the Form Teacher writes that comment';
    end if;
    update report_card set form_teacher_comment = p_comment
     where term_id = p_term and student_id = p_student and school_id = app.school_id();
  elsif p_which = 'rector' then
    if not app.has_cap('school.manage') then
      raise exception 'Only the Rector writes that comment';
    end if;
    update report_card set rector_comment = p_comment
     where term_id = p_term and student_id = p_student and school_id = app.school_id();
  else
    raise exception 'Unknown comment field %', p_which;
  end if;
  if not found then raise exception 'No report card — build them for this term first'; end if;
end $$;


--
-- Name: rpc_set_subject_comment(uuid, uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_set_subject_comment(p_term uuid, p_student uuid, p_subject uuid, p_comment text, p_difficulties text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare v_set uuid;
begin
  select tr.subject_set_id into v_set from term_result tr
   where tr.term_id = p_term and tr.student_id = p_student and tr.subject_id = p_subject;
  if v_set is null then raise exception 'No result for that subject'; end if;
  if not (app.teaches_set(v_set) or app.has_cap('marks.moderate')) then
    raise exception 'You do not teach this set';
  end if;

  update term_result
     set educator_comment = p_comment, difficulties = p_difficulties
   where term_id = p_term and student_id = p_student and subject_id = p_subject;
end $$;


--
-- Name: rpc_submit_scheme(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_submit_scheme(p_scheme uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
declare s record;
begin
  select * into s from scheme_of_work where id = p_scheme and school_id = app.school_id();
  if s.id is null then raise exception 'Unknown scheme of work'; end if;
  if s.staff_id <> app.person_id() then
    raise exception 'Only the author may submit a scheme of work';
  end if;
  if s.status not in ('draft','hod_returned') then
    raise exception 'This scheme has already been submitted';
  end if;
  if not exists (select 1 from scheme_week w where w.scheme_of_work_id = p_scheme) then
    raise exception 'Add at least one week before submitting';
  end if;

  update scheme_of_work
     set status = 'submitted', submitted_at = now()
   where id = p_scheme;
end $$;


--
-- Name: scheme_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.scheme_status(p_term uuid) RETURNS TABLE(subject_set_id uuid, set_name text, subject_name text, staff_id uuid, staff_name text, department text, scheme_id uuid, status public.plan_status, due_on date, hod_comment text, weeks smallint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    ss.id, ss.name, sub.name_en,
    se.staff_id, p.first_name || ' ' || p.last_name, d.name,
    sow.id, coalesce(sow.status, 'draft'::plan_status), sow.due_on, sow.hod_comment,
    (select count(*)::smallint from scheme_week w where w.scheme_of_work_id = sow.id)
  from subject_set ss
  join subject sub on sub.id = ss.subject_id
  left join department d on d.id = sub.department_id
  join set_educator se on se.subject_set_id = ss.id and se.is_primary
  join person p on p.id = se.staff_id
  join term t on t.id = p_term
  left join scheme_of_work sow on sow.subject_set_id = ss.id and sow.term_id = p_term
  where ss.school_id = app.school_id()
    and ss.academic_year_id = t.academic_year_id
    and (se.staff_id = app.person_id() or app.has_cap('marks.moderate'))
  order by d.name, sub.name_en, ss.name;
$$;


--
-- Name: school_dashboard(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.school_dashboard(p_date date DEFAULT CURRENT_DATE) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select jsonb_build_object(
    'date', p_date,
    'on_roll', (select count(*) from student
                where school_id = app.school_id() and status = 'enrolled'),
    'staff', (select count(*) from staff
              where school_id = app.school_id() and exited_on is null),
    'registers_taken', (select count(*) from attendance_session
      where school_id = app.school_id() and date = p_date and taken_at is not null),
    'absent_unauthorised_today', (
      select count(*) from attendance_record ar
      join attendance_session s on s.id = ar.attendance_session_id
      where s.date = p_date and ar.status = 'absent_unauth'
        and ar.school_id = app.school_id()),
    'open_discrepancies', (select count(*) from attendance_discrepancy
      where school_id = app.school_id() and resolved_at is null),
    'pending_absence_notes', (select count(*) from absence_note
      where school_id = app.school_id() and status = 'pending'),
    'open_conduct_cases', (select count(*) from disciplinary_case
      where school_id = app.school_id() and closed_on is null),
    'staff_on_leave_today', (select count(*) from staff_leave
      where school_id = app.school_id() and status = 'approved'
        and p_date between starts_on and ends_on),
    'marks_awaiting_moderation', (select count(*) from assessment
      where school_id = app.school_id() and status = 'submitted'),
    'marks_awaiting_publication', (select count(*) from assessment
      where school_id = app.school_id() and status = 'moderated'),
    'below_attendance_threshold', (select count(distinct student_id)
      from attendance_summary
      where school_id = app.school_id() and pct_present < 80),
    'overdue_actions', (select count(*) from action_item
      where school_id = app.school_id() and status = 'open' and due_on < p_date)
  )
  where app.has_cap('attendance.read.all');
$$;


--
-- Name: seating_plan(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.seating_plan(p_paper uuid) RETURNS TABLE(room_code text, seat_label text, row_no smallint, col_no smallint, first_name text, last_name text, admission_number text, class_name text, arrangement text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select r.code, s.seat_label, s.row_no, s.col_no,
         p.first_name, p.last_name, st.admission_number, cg.name,
         (select string_agg(a.kind, ', ') from exam_arrangement a
           where a.student_id = st.id)
  from exam_seat s
  join room r on r.id = s.room_id
  join student st on st.id = s.student_id
  join person p on p.id = st.id
  left join class_enrolment ce on ce.student_id = st.id and ce.effective_to is null
  left join class_group cg on cg.id = ce.class_group_id
  where s.exam_paper_id = p_paper
    and s.school_id = app.school_id()
    and (app.has_cap('school.manage') or app.has_cap('attendance.read.all'))
  order by r.code, s.row_no, s.col_no;
$$;


--
-- Name: set_marksheet(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_marksheet(p_set uuid, p_term uuid) RETURNS TABLE(student_id uuid, first_name text, last_name text, preferred_name text, admission_number text, assessment_id uuid, title text, kind public.assessment_kind, max_score numeric, weight numeric, status public.assessment_status, mark_id uuid, score numeric, code text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    s.id, p.first_name, p.last_name, p.preferred_name, s.admission_number,
    a.id, a.title, a.kind, a.max_score, a.weight, a.status,
    m.id, m.score, m.code
  from set_enrolment se
  join student s on s.id = se.student_id
  join person  p on p.id = s.id
  cross join assessment a
  left join mark m on m.assessment_id = a.id and m.student_id = s.id
  where se.subject_set_id = p_set
    and se.effective_to is null
    and a.subject_set_id = p_set
    and (p_term is null or a.term_id = p_term)
    and (app.teaches_set(p_set) or app.has_cap('marks.read.all'))
  order by p.last_name, p.first_name, a.scheduled_on nulls last, a.title;
$$;


--
-- Name: set_roster(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_roster(p_set uuid, p_date date) RETURNS TABLE(student_id uuid, first_name text, last_name text, preferred_name text, admission_number text, class_name text, register_status public.attendance_status, period_status public.attendance_status)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    s.id, p.first_name, p.last_name, p.preferred_name, s.admission_number,
    cg.name,
    (select ar.status
       from attendance_record ar
       join attendance_session sess on sess.id = ar.attendance_session_id
      where ar.student_id = s.id and sess.date = p_date
      order by case sess.session when 'am' then 0 else 1 end
      limit 1),
    (select pa.status from period_attendance pa
      where pa.subject_set_id = p_set and pa.student_id = s.id and pa.date = p_date
      limit 1)
  from set_enrolment se
  join student s on s.id = se.student_id
  join person  p on p.id = s.id
  left join class_enrolment ce on ce.student_id = s.id and ce.effective_to is null
  left join class_group cg on cg.id = ce.class_group_id
  where se.subject_set_id = p_set
    and se.effective_from <= p_date
    and (se.effective_to is null or se.effective_to >= p_date)
    and (
      exists (select 1 from set_educator ed
               where ed.subject_set_id = p_set and ed.staff_id = app.person_id())
      or app.has_cap('attendance.read.all')
    )
  order by p.last_name, p.first_name;
$$;


--
-- Name: substitute_candidates(date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.substitute_candidates(p_date date, p_slot uuid) RETURNS TABLE(staff_id uuid, staff_name text, score integer, reason text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with slot as (
    select ts.*, ss.subject_id, ss.id as set_id
    from timetable_slot ts join subject_set ss on ss.id = ts.subject_set_id
    where ts.id = p_slot
  ),
  cycle as (select cd.cycle_day from calendar_day cd
            where cd.date = p_date and cd.school_id = app.school_id()),
  busy as (
    select ts.staff_id from timetable_slot ts, slot s, cycle c
    where ts.timetable_version_id = s.timetable_version_id
      and ts.cycle_day = c.cycle_day and ts.period_id = s.period_id
      and ts.staff_id is not null
  ),
  cover_load as (
    select substitute_staff_id as staff_id, count(*)::int as n
    from lesson_substitution
    where school_id = app.school_id() and date >= p_date - 90
    group by 1
  )
  select
    st.id, p.first_name || ' ' || p.last_name,
    (case when st.department_id = (select sub.department_id from slot s
                                   join subject sub on sub.id = s.subject_id) then 40 else 0 end
     + case when exists (select 1 from set_educator se, slot s
                         where se.subject_set_id = s.set_id and se.staff_id = st.id) then 25 else 0 end
     + greatest(0, 20 - coalesce(cl.n, 0) * 4))::int,
    concat_ws(', ',
      case when st.department_id = (select sub.department_id from slot s
                                    join subject sub on sub.id = s.subject_id)
           then 'same department' end,
      case when coalesce(cl.n,0) = 0 then 'no cover yet this term'
           else coalesce(cl.n,0) || ' cover lessons already' end)
  from staff st
  join person p on p.id = st.id
  left join cover_load cl on cl.staff_id = st.id
  where st.school_id = app.school_id()
    and st.exited_on is null
    and st.id not in (select staff_id from busy)
    and st.id not in (select sl.staff_id from staff_leave sl
                      where p_date between sl.starts_on and sl.ends_on and sl.status='approved')
    and app.has_cap('attendance.read.all')
  order by 3 desc
  limit 10;
$$;


--
-- Name: timetable_inputs(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.timetable_inputs(p_year uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select jsonb_build_object(
    'rooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'code', r.code, 'roomType', r.room_type, 'capacity', r.capacity)), '[]'::jsonb)
      from room r where r.school_id = app.school_id() and r.is_active
    ),
    'educators', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'unavailable', coalesce(s.unavailable_slots, '[]'::jsonb),
        'maxPeriodsPerCycle', s.max_periods_per_cycle)), '[]'::jsonb)
      from staff s where s.school_id = app.school_id() and s.exited_on is null
    ),
    'sets', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', ss.id,
        'name', ss.name,
        'periodsPerCycle', ss.periods_per_cycle,
        'doublePeriods', ss.double_periods,
        'requiredRoomType', sub.requires_room_type,
        'preferredRoomId', ss.preferred_room_id,
        'educatorIds', (select coalesce(jsonb_agg(se.staff_id), '[]'::jsonb)
                        from set_educator se where se.subject_set_id = ss.id),
        'studentIds', (select coalesce(jsonb_agg(e.student_id), '[]'::jsonb)
                       from set_enrolment e
                       where e.subject_set_id = ss.id and e.effective_to is null),
        'size', (select count(*) from set_enrolment e
                 where e.subject_set_id = ss.id and e.effective_to is null)
      )), '[]'::jsonb)
      from subject_set ss
      join subject sub on sub.id = ss.subject_id
      where ss.academic_year_id = p_year and ss.school_id = app.school_id()
    )
  )
  where app.has_cap('school.manage');
$$;


--
-- Name: uncovered_lessons(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uncovered_lessons(p_date date) RETURNS TABLE(timetable_slot_id uuid, set_name text, subject_name text, period_name text, starts_at time without time zone, room_code text, absent_staff_id uuid, absent_staff_name text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  with day as (
    select cd.cycle_day, cd.academic_year_id from calendar_day cd
    where cd.date = p_date and cd.school_id = app.school_id() and cd.day_type = 'teaching'
  ),
  version as (
    select tv.id from timetable_version tv, day d
    where tv.academic_year_id = d.academic_year_id and tv.status = 'published'
      and tv.effective_from <= p_date
      and (tv.effective_to is null or tv.effective_to >= p_date)
    order by tv.version desc limit 1
  ),
  away as (
    select sl.staff_id from staff_leave sl
    where p_date between sl.starts_on and sl.ends_on and sl.status = 'approved'
      and sl.school_id = app.school_id()
  )
  select ts.id, ss.name, sub.name_en, pd.name, pd.starts_at, r.code,
         ts.staff_id, p.first_name || ' ' || p.last_name
  from timetable_slot ts
  join version v on v.id = ts.timetable_version_id
  join day d on d.cycle_day = ts.cycle_day
  join subject_set ss on ss.id = ts.subject_set_id
  join subject sub on sub.id = ss.subject_id
  join period_definition pd on pd.id = ts.period_id
  left join room r on r.id = ts.room_id
  left join person p on p.id = ts.staff_id
  where ts.staff_id in (select staff_id from away)
    and app.has_cap('attendance.read.all')
  order by pd.sequence;
$$;


--
-- Name: unplaced_lessons(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unplaced_lessons(p_version uuid) RETURNS TABLE(subject_set_id uuid, set_name text, subject_name text, required smallint, placed integer, outstanding integer, required_room_type public.room_type, size integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    ss.id, ss.name, sub.name_en,
    ss.periods_per_cycle,
    (select count(*)::int from timetable_slot ts
      where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id),
    ss.periods_per_cycle - (select count(*)::int from timetable_slot ts
      where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id),
    sub.requires_room_type,
    (select count(*)::int from set_enrolment se
      where se.subject_set_id = ss.id and se.effective_to is null)
  from subject_set ss
  join subject sub on sub.id = ss.subject_id
  join timetable_version tv on tv.id = p_version
  where ss.academic_year_id = tv.academic_year_id
    and ss.school_id = app.school_id()
    and app.has_cap('school.manage')
    and ss.periods_per_cycle > (select count(*) from timetable_slot ts
        where ts.timetable_version_id = p_version and ts.subject_set_id = ss.id)
  order by ss.name;
$$;


--
-- Name: validate_subject_choice(uuid, uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_subject_choice(p_student uuid, p_grade_level uuid, p_subject_ids uuid[]) RETURNS TABLE(ok boolean, block_name text, chosen integer, min_choices integer, max_choices integer, message text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'app', 'pg_temp'
    AS $$
  select
    cnt between ob.min_choices and ob.max_choices,
    ob.name, cnt::int, ob.min_choices::int, ob.max_choices::int,
    case
      when cnt < ob.min_choices then
        format('%s requires at least %s subject(s); %s chosen', ob.name, ob.min_choices, cnt)
      when cnt > ob.max_choices then
        format('%s allows at most %s subject(s); %s chosen', ob.name, ob.max_choices, cnt)
      else 'ok'
    end
  from option_block ob
  cross join lateral (
    select count(*) as cnt
    from option_block_subject obs
    where obs.option_block_id = ob.id
      and obs.subject_id = any(p_subject_ids)
  ) c
  where ob.grade_level_id = p_grade_level
    and ob.school_id = app.school_id();
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: absence_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.absence_note (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    submitted_by uuid,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    covers_from date NOT NULL,
    covers_to date NOT NULL,
    reason text NOT NULL,
    medical_certificate_path text,
    status text DEFAULT 'pending'::text NOT NULL,
    decided_by uuid,
    decided_at timestamp with time zone,
    decision_note text,
    CONSTRAINT absence_note_check CHECK ((covers_to >= covers_from)),
    CONSTRAINT absence_note_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text])))
);

ALTER TABLE ONLY public.absence_note FORCE ROW LEVEL SECURITY;


--
-- Name: academic_year; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.academic_year (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    name text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status public.year_status DEFAULT 'planning'::public.year_status NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT academic_year_check CHECK ((ends_on > starts_on))
);

ALTER TABLE ONLY public.academic_year FORCE ROW LEVEL SECURITY;


--
-- Name: action_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.action_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    meeting_id uuid,
    description text NOT NULL,
    owner_person_id uuid,
    due_on date,
    status text DEFAULT 'open'::text NOT NULL,
    completed_on date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT action_item_status_check CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.action_item FORCE ROW LEVEL SECURITY;


--
-- Name: admission_checklist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admission_checklist (
    student_id uuid NOT NULL,
    school_id uuid NOT NULL,
    admission_letter_seen boolean DEFAULT false NOT NULL,
    birth_certificate_seen boolean DEFAULT false NOT NULL,
    rules_acknowledged boolean DEFAULT false NOT NULL,
    rules_acknowledged_at timestamp with time zone,
    subject_choice_valid boolean DEFAULT false NOT NULL,
    id_card_issued boolean DEFAULT false NOT NULL,
    completed_at timestamp with time zone
);

ALTER TABLE ONLY public.admission_checklist FORCE ROW LEVEL SECURITY;


--
-- Name: assessment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    term_id uuid,
    subject_set_id uuid,
    grade_level_id uuid,
    subject_id uuid,
    kind public.assessment_kind NOT NULL,
    title text NOT NULL,
    scheduled_on date,
    max_score numeric(6,2) NOT NULL,
    weight numeric(5,2) DEFAULT 1 NOT NULL,
    grading_scale_id uuid,
    counts_for_promotion boolean DEFAULT true NOT NULL,
    status public.assessment_status DEFAULT 'draft'::public.assessment_status NOT NULL,
    submitted_by uuid,
    submitted_at timestamp with time zone,
    moderated_by uuid,
    moderated_at timestamp with time zone,
    published_by uuid,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assessment_max_score_check CHECK ((max_score > (0)::numeric)),
    CONSTRAINT assessment_weight_check CHECK ((weight >= (0)::numeric))
);

ALTER TABLE ONLY public.assessment FORCE ROW LEVEL SECURITY;


--
-- Name: asset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    tag text NOT NULL,
    category text NOT NULL,
    name text NOT NULL,
    room_id uuid,
    custodian_id uuid,
    acquired_on date,
    cost numeric(12,2),
    condition text DEFAULT 'good'::text,
    status text DEFAULT 'in_service'::text NOT NULL,
    disposed_on date,
    notes text,
    CONSTRAINT asset_condition_check CHECK ((condition = ANY (ARRAY['new'::text, 'good'::text, 'fair'::text, 'poor'::text, 'unserviceable'::text]))),
    CONSTRAINT asset_status_check CHECK ((status = ANY (ARRAY['in_service'::text, 'in_repair'::text, 'disposed'::text, 'lost'::text])))
);

ALTER TABLE ONLY public.asset FORCE ROW LEVEL SECURITY;


--
-- Name: asset_verification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_verification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    verified_by uuid,
    verified_on date DEFAULT CURRENT_DATE NOT NULL,
    found boolean NOT NULL,
    condition text,
    note text
);

ALTER TABLE ONLY public.asset_verification FORCE ROW LEVEL SECURITY;


--
-- Name: attendance_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_summary (
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    term_id uuid NOT NULL,
    student_id uuid NOT NULL,
    sessions_possible integer DEFAULT 0 NOT NULL,
    sessions_present integer DEFAULT 0 NOT NULL,
    sessions_absent_unauth integer DEFAULT 0 NOT NULL,
    sessions_absent_auth integer DEFAULT 0 NOT NULL,
    times_late integer DEFAULT 0 NOT NULL,
    pct_present numeric(5,2) GENERATED ALWAYS AS (
CASE
    WHEN (sessions_possible = 0) THEN NULL::numeric
    ELSE round(((100.0 * (sessions_present)::numeric) / (sessions_possible)::numeric), 2)
END) STORED,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.attendance_summary FORCE ROW LEVEL SECURITY;


--
-- Name: class_enrolment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.class_enrolment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    class_group_id uuid NOT NULL,
    student_id uuid NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    roll_number smallint,
    is_class_captain boolean DEFAULT false NOT NULL,
    is_vice_captain boolean DEFAULT false NOT NULL,
    is_prefect boolean DEFAULT false NOT NULL,
    CONSTRAINT class_enrolment_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);

ALTER TABLE ONLY public.class_enrolment FORCE ROW LEVEL SECURITY;


--
-- Name: class_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.class_group (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    grade_level_id uuid NOT NULL,
    name text NOT NULL,
    stream public.stream_type DEFAULT 'regular'::public.stream_type NOT NULL,
    home_room_id uuid,
    capacity smallint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.class_group FORCE ROW LEVEL SECURITY;


--
-- Name: grade_level; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grade_level (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    grade smallint NOT NULL,
    legacy_form text,
    cycle_stage text,
    CONSTRAINT grade_level_grade_check CHECK (((grade >= 7) AND (grade <= 13)))
);

ALTER TABLE ONLY public.grade_level FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN grade_level.legacy_form; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.grade_level.legacy_form IS 'Form I..Upper VI — still in daily use inside schools.';


--
-- Name: term; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.term (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    sequence smallint NOT NULL,
    name text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT term_check CHECK ((ends_on > starts_on)),
    CONSTRAINT term_sequence_check CHECK (((sequence >= 1) AND (sequence <= 4)))
);

ALTER TABLE ONLY public.term FORCE ROW LEVEL SECURITY;


--
-- Name: attendance_by_class; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.attendance_by_class WITH (security_invoker='true') AS
 SELECT cg.id AS class_group_id,
    cg.name AS class_name,
    gl.grade,
    t.id AS term_id,
    t.name AS term_name,
    count(DISTINCT sm.student_id) AS pupils,
    round(avg(sm.pct_present), 2) AS mean_pct,
    min(sm.pct_present) AS lowest_pct,
    count(*) FILTER (WHERE (sm.pct_present < (80)::numeric)) AS below_threshold,
    sum(sm.sessions_absent_unauth) AS unauthorised_sessions,
    sum(sm.times_late) AS lateness
   FROM ((((public.attendance_summary sm
     JOIN public.term t ON ((t.id = sm.term_id)))
     JOIN public.class_enrolment ce ON (((ce.student_id = sm.student_id) AND (ce.effective_to IS NULL))))
     JOIN public.class_group cg ON ((cg.id = ce.class_group_id)))
     JOIN public.grade_level gl ON ((gl.id = cg.grade_level_id)))
  GROUP BY cg.id, cg.name, gl.grade, t.id, t.name;


--
-- Name: attendance_discrepancy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_discrepancy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    date date NOT NULL,
    kind text NOT NULL,
    subject_set_id uuid,
    timetable_slot_id uuid,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_by uuid,
    resolved_at timestamp with time zone,
    outcome text,
    CONSTRAINT attendance_discrepancy_kind_check CHECK ((kind = ANY (ARRAY['present_on_register_absent_in_class'::text, 'absent_on_register_present_in_class'::text]))),
    CONSTRAINT attendance_discrepancy_outcome_check CHECK ((outcome = ANY (ARRAY['found_on_premises'::text, 'left_school'::text, 'medical_room'::text, 'authorised'::text, 'unresolved'::text])))
);

ALTER TABLE ONLY public.attendance_discrepancy REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.attendance_discrepancy FORCE ROW LEVEL SECURITY;


--
-- Name: attendance_record; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_record (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    attendance_session_id uuid NOT NULL,
    student_id uuid NOT NULL,
    status public.attendance_status NOT NULL,
    minutes_late smallint,
    note text,
    recorded_by uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    amended_by uuid,
    amended_at timestamp with time zone,
    amend_reason text,
    CONSTRAINT attendance_record_minutes_late_check CHECK (((minutes_late IS NULL) OR (minutes_late >= 0)))
);

ALTER TABLE ONLY public.attendance_record FORCE ROW LEVEL SECURITY;


--
-- Name: attendance_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_session (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    class_group_id uuid NOT NULL,
    date date NOT NULL,
    session public.session_type NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    taken_by uuid,
    taken_at timestamp with time zone,
    closed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT attendance_session_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'amended'::text])))
);

ALTER TABLE ONLY public.attendance_session FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE attendance_session; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_session IS 'Attendance is taken twice daily, morning and afternoon (School Management Manual 4.5.2).';


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    school_id uuid,
    actor_id uuid,
    action text NOT NULL,
    table_name text,
    record_id uuid,
    before jsonb,
    after jsonb,
    at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.audit_log FORCE ROW LEVEL SECURITY;


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: calendar_day; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_day (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    term_id uuid,
    date date NOT NULL,
    day_type public.day_type NOT NULL,
    cycle_day smallint,
    closure_reason text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.calendar_day FORCE ROW LEVEL SECURITY;


--
-- Name: capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capability (
    code text NOT NULL,
    description text NOT NULL
);

ALTER TABLE ONLY public.capability FORCE ROW LEVEL SECURITY;


--
-- Name: circular; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.circular (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    reference text NOT NULL,
    issued_on date NOT NULL,
    source text DEFAULT 'Ministry of Education'::text NOT NULL,
    subject text NOT NULL,
    file_path text,
    target_roles text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.circular FORCE ROW LEVEL SECURITY;


--
-- Name: circular_ack; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.circular_ack (
    circular_id uuid NOT NULL,
    person_id uuid NOT NULL,
    acknowledged_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.circular_ack FORCE ROW LEVEL SECURITY;


--
-- Name: person; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.person (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    auth_user_id uuid,
    person_type public.person_type NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    preferred_name text,
    sex public.sex_type,
    date_of_birth date,
    national_id text,
    photo_path text,
    email text,
    phone text,
    phone_alt text,
    preferred_language character(2) DEFAULT 'en'::bpchar NOT NULL,
    address jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT person_preferred_language_check CHECK ((preferred_language = ANY (ARRAY['en'::bpchar, 'fr'::bpchar, 'mf'::bpchar])))
);

ALTER TABLE ONLY public.person FORCE ROW LEVEL SECURITY;


--
-- Name: student; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student (
    id uuid NOT NULL,
    school_id uuid NOT NULL,
    admission_number text NOT NULL,
    admission_letter_ref text,
    admitted_on date NOT NULL,
    entry_grade smallint,
    prior_school text,
    psac_result jsonb,
    is_extended_programme boolean DEFAULT false NOT NULL,
    house text,
    transport_mode text,
    bus_route text,
    medical_alerts text[] DEFAULT '{}'::text[] NOT NULL,
    allergies text[] DEFAULT '{}'::text[] NOT NULL,
    sen_notes text,
    candidate_number text,
    centre_number text,
    status public.student_status DEFAULT 'enrolled'::public.student_status NOT NULL,
    left_on date,
    leaving_reason text
);

ALTER TABLE ONLY public.student FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN student.admission_letter_ref; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.student.admission_letter_ref IS 'Reference of the official letter of admission. No student is admitted without one.';


--
-- Name: COLUMN student.sen_notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.student.sen_notes IS 'Restricted (T3). Reads are audited.';


--
-- Name: class_roster; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.class_roster WITH (security_invoker='true') AS
 SELECT ce.class_group_id,
    cg.name AS class_name,
    cg.academic_year_id,
    ce.student_id,
    ce.roll_number,
    ce.is_class_captain,
    ce.is_vice_captain,
    ce.is_prefect,
    ce.effective_from,
    ce.effective_to,
    s.admission_number,
    s.is_extended_programme,
    s.status AS student_status,
    p.first_name,
    p.last_name,
    p.preferred_name,
    p.photo_path,
    p.school_id
   FROM (((public.class_enrolment ce
     JOIN public.class_group cg ON ((cg.id = ce.class_group_id)))
     JOIN public.student s ON ((s.id = ce.student_id)))
     JOIN public.person p ON ((p.id = s.id)));


--
-- Name: VIEW class_roster; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.class_roster IS 'Flattened class roster for the register screen. Respects caller RLS.';


--
-- Name: clearance_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clearance_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    kind text NOT NULL,
    cleared boolean DEFAULT false NOT NULL,
    cleared_by uuid,
    cleared_on date,
    note text,
    CONSTRAINT clearance_item_kind_check CHECK ((kind = ANY (ARRAY['report_book'::text, 'id_card'::text, 'library_books'::text, 'sports_kit'::text, 'textbooks'::text, 'other'::text])))
);

ALTER TABLE ONLY public.clearance_item FORCE ROW LEVEL SECURITY;


--
-- Name: committee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.committee (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    terms_of_reference text,
    min_meetings_per_term smallint
);

ALTER TABLE ONLY public.committee FORCE ROW LEVEL SECURITY;


--
-- Name: committee_member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.committee_member (
    committee_id uuid NOT NULL,
    person_id uuid NOT NULL,
    role_in_committee text
);

ALTER TABLE ONLY public.committee_member FORCE ROW LEVEL SECURITY;


--
-- Name: confidential_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.confidential_note (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    subject_person_id uuid,
    author_id uuid NOT NULL,
    note text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.confidential_note FORCE ROW LEVEL SECURITY;


--
-- Name: correspondence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.correspondence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    direction text NOT NULL,
    dated_on date DEFAULT CURRENT_DATE NOT NULL,
    counterparty text NOT NULL,
    subject text NOT NULL,
    abc_code character(1),
    unique_file_number integer,
    assigned_to uuid,
    status text DEFAULT 'open'::text NOT NULL,
    due_on date,
    file_path text,
    CONSTRAINT correspondence_direction_check CHECK ((direction = ANY (ARRAY['in'::text, 'out'::text]))),
    CONSTRAINT correspondence_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'answered'::text, 'filed'::text])))
);

ALTER TABLE ONLY public.correspondence FORCE ROW LEVEL SECURITY;


--
-- Name: department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.department (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);

ALTER TABLE ONLY public.department FORCE ROW LEVEL SECURITY;


--
-- Name: disciplinary_case; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disciplinary_case (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    opened_on date DEFAULT CURRENT_DATE NOT NULL,
    stage public.case_stage DEFAULT 'form_teacher'::public.case_stage NOT NULL,
    committee_id uuid,
    hearing_on date,
    guardian_summons_sent_on date,
    summons_delivery_proof_path text,
    decision text,
    decided_on date,
    appeal_status text,
    closed_on date
);

ALTER TABLE ONLY public.disciplinary_case FORCE ROW LEVEL SECURITY;


--
-- Name: period_definition; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.period_definition (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    timetable_version_id uuid NOT NULL,
    sequence smallint NOT NULL,
    name text NOT NULL,
    starts_at time without time zone NOT NULL,
    ends_at time without time zone NOT NULL,
    is_teaching boolean DEFAULT true NOT NULL,
    CONSTRAINT period_definition_check CHECK ((ends_at > starts_at))
);

ALTER TABLE ONLY public.period_definition FORCE ROW LEVEL SECURITY;


--
-- Name: subject; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    department_id uuid,
    code text NOT NULL,
    name_en text NOT NULL,
    name_fr text,
    strand public.subject_strand DEFAULT 'other'::public.subject_strand NOT NULL,
    is_core boolean DEFAULT false NOT NULL,
    is_practical boolean DEFAULT false NOT NULL,
    requires_room_type public.room_type,
    external_codes jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.subject FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN subject.external_codes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.subject.external_codes IS 'e.g. {"cambridge":"4024","nce":"MATH"}';


--
-- Name: subject_set; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_set (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    grade_level_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    name text NOT NULL,
    level public.set_level DEFAULT 'core'::public.set_level NOT NULL,
    periods_per_cycle smallint DEFAULT 4 NOT NULL,
    double_periods smallint DEFAULT 0 NOT NULL,
    preferred_room_id uuid,
    max_size smallint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.subject_set FORCE ROW LEVEL SECURITY;


--
-- Name: timetable_slot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timetable_slot (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    timetable_version_id uuid NOT NULL,
    cycle_day smallint NOT NULL,
    period_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    room_id uuid,
    staff_id uuid,
    is_double_start boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.timetable_slot FORCE ROW LEVEL SECURITY;


--
-- Name: discrepancy_feed; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.discrepancy_feed WITH (security_invoker='true') AS
 SELECT d.id,
    d.school_id,
    d.date,
    d.kind,
    d.detected_at,
    d.resolved_at,
    d.outcome,
    d.student_id,
    p.first_name,
    p.last_name,
    p.preferred_name,
    p.photo_path,
    s.admission_number,
    cg.name AS class_name,
    cg.id AS class_group_id,
    sub.name_en AS subject_name,
    ss.name AS set_name,
    pd.name AS period_name,
    pd.starts_at AS period_starts_at,
    ((edu.first_name || ' '::text) || edu.last_name) AS reported_by_educator,
    ((res.first_name || ' '::text) || res.last_name) AS resolved_by_name
   FROM ((((((((((public.attendance_discrepancy d
     JOIN public.person p ON ((p.id = d.student_id)))
     JOIN public.student s ON ((s.id = d.student_id)))
     LEFT JOIN public.class_enrolment ce ON (((ce.student_id = d.student_id) AND (ce.effective_to IS NULL))))
     LEFT JOIN public.class_group cg ON ((cg.id = ce.class_group_id)))
     LEFT JOIN public.subject_set ss ON ((ss.id = d.subject_set_id)))
     LEFT JOIN public.subject sub ON ((sub.id = ss.subject_id)))
     LEFT JOIN public.timetable_slot ts ON ((ts.id = d.timetable_slot_id)))
     LEFT JOIN public.period_definition pd ON ((pd.id = ts.period_id)))
     LEFT JOIN public.person edu ON ((edu.id = ts.staff_id)))
     LEFT JOIN public.person res ON ((res.id = d.resolved_by)));


--
-- Name: VIEW discrepancy_feed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.discrepancy_feed IS 'Display-ready attendance discrepancies for the Usher''s board. security_invoker: requires attendance.read.all AND person.read.all AND student.read.all, because the view inner-joins person and student and RLS on those tables filters it. Missing any one yields an empty board, not an error.';


--
-- Name: exam_arrangement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_arrangement (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    kind text NOT NULL,
    detail text,
    extra_minutes smallint,
    approved_by uuid,
    CONSTRAINT exam_arrangement_kind_check CHECK ((kind = ANY (ARRAY['extra_time'::text, 'separate_room'::text, 'reader'::text, 'scribe'::text, 'enlarged_print'::text, 'rest_breaks'::text])))
);

ALTER TABLE ONLY public.exam_arrangement FORCE ROW LEVEL SECURITY;


--
-- Name: exam_eligibility_decision; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_eligibility_decision (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    exam_session_id uuid NOT NULL,
    student_id uuid NOT NULL,
    attendance_pct numeric(5,2),
    threshold numeric(5,2),
    decision text NOT NULL,
    reason text,
    decided_by uuid,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    guardian_notified_at timestamp with time zone,
    CONSTRAINT exam_eligibility_decision_decision_check CHECK ((decision = ANY (ARRAY['allow'::text, 'debar'::text])))
);

ALTER TABLE ONLY public.exam_eligibility_decision FORCE ROW LEVEL SECURITY;


--
-- Name: exam_paper; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_paper (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    exam_session_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    grade_level_id uuid NOT NULL,
    paper_number smallint DEFAULT 1 NOT NULL,
    date date NOT NULL,
    starts_at time without time zone NOT NULL,
    duration_minutes smallint NOT NULL,
    max_score numeric(6,2),
    assessment_id uuid,
    CONSTRAINT exam_paper_duration_minutes_check CHECK ((duration_minutes > 0))
);

ALTER TABLE ONLY public.exam_paper FORCE ROW LEVEL SECURITY;


--
-- Name: exam_seat; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_seat (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    exam_paper_id uuid NOT NULL,
    student_id uuid NOT NULL,
    room_id uuid NOT NULL,
    seat_label text NOT NULL,
    row_no smallint,
    col_no smallint,
    attendance text,
    irregularity text,
    CONSTRAINT exam_seat_attendance_check CHECK ((attendance = ANY (ARRAY['present'::text, 'absent'::text])))
);

ALTER TABLE ONLY public.exam_seat FORCE ROW LEVEL SECURITY;


--
-- Name: exam_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_session (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    term_id uuid,
    kind text NOT NULL,
    name text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status text DEFAULT 'planning'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT exam_session_check CHECK ((ends_on >= starts_on)),
    CONSTRAINT exam_session_kind_check CHECK ((kind = ANY (ARRAY['term_test'::text, 'end_of_term'::text, 'end_of_year'::text, 'mock'::text, 'national'::text]))),
    CONSTRAINT exam_session_status_check CHECK ((status = ANY (ARRAY['planning'::text, 'screening'::text, 'scheduled'::text, 'running'::text, 'complete'::text]))),
    CONSTRAINT internal_exam_max_ten_days CHECK (((kind = 'national'::text) OR ((ends_on - starts_on) <= 13)))
);

ALTER TABLE ONLY public.exam_session FORCE ROW LEVEL SECURITY;


--
-- Name: grading_band; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grading_band (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    grading_scale_id uuid NOT NULL,
    label text NOT NULL,
    min_score numeric(5,2),
    max_score numeric(5,2),
    points numeric(4,2),
    is_pass boolean DEFAULT false NOT NULL,
    is_credit boolean DEFAULT false NOT NULL,
    sort_order smallint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.grading_band FORCE ROW LEVEL SECURITY;


--
-- Name: grading_scale; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grading_scale (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);

ALTER TABLE ONLY public.grading_scale FORCE ROW LEVEL SECURITY;


--
-- Name: guardian; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guardian (
    id uuid NOT NULL,
    occupation text,
    preferred_channel text DEFAULT 'sms'::text NOT NULL,
    CONSTRAINT guardian_preferred_channel_check CHECK ((preferred_channel = ANY (ARRAY['sms'::text, 'email'::text, 'app'::text])))
);

ALTER TABLE ONLY public.guardian FORCE ROW LEVEL SECURITY;


--
-- Name: health_record; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.health_record (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    kind text NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    description text NOT NULL,
    action_taken text,
    attended_by uuid,
    guardian_notified_at timestamp with time zone,
    sent_home boolean DEFAULT false NOT NULL,
    CONSTRAINT health_record_kind_check CHECK ((kind = ANY (ARRAY['first_aid'::text, 'illness'::text, 'injury'::text, 'medication'::text, 'screening'::text, 'other'::text])))
);

ALTER TABLE ONLY public.health_record FORCE ROW LEVEL SECURITY;


--
-- Name: homework; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.homework (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    set_by uuid NOT NULL,
    set_on date DEFAULT CURRENT_DATE NOT NULL,
    due_on date NOT NULL,
    title text NOT NULL,
    description text,
    attachments text[] DEFAULT '{}'::text[] NOT NULL,
    estimated_minutes smallint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.homework FORCE ROW LEVEL SECURITY;


--
-- Name: homework_submission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.homework_submission (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    homework_id uuid NOT NULL,
    student_id uuid NOT NULL,
    submitted_at timestamp with time zone,
    status text DEFAULT 'pending'::text NOT NULL,
    feedback text,
    CONSTRAINT homework_submission_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'submitted'::text, 'late'::text, 'missing'::text, 'excused'::text])))
);

ALTER TABLE ONLY public.homework_submission FORCE ROW LEVEL SECURITY;


--
-- Name: incident; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incident (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    location text,
    category text NOT NULL,
    severity public.incident_severity DEFAULT 'minor'::public.incident_severity NOT NULL,
    description text NOT NULL,
    witnesses text,
    photo_paths text[] DEFAULT '{}'::text[] NOT NULL,
    reported_by uuid NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT incident_status_check CHECK ((status = ANY (ARRAY['open'::text, 'actioned'::text, 'closed'::text])))
);

ALTER TABLE ONLY public.incident FORCE ROW LEVEL SECURITY;


--
-- Name: incident_student; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incident_student (
    incident_id uuid NOT NULL,
    student_id uuid NOT NULL,
    involvement text DEFAULT 'perpetrator'::text NOT NULL,
    CONSTRAINT incident_student_involvement_check CHECK ((involvement = ANY (ARRAY['perpetrator'::text, 'victim'::text, 'witness'::text])))
);

ALTER TABLE ONLY public.incident_student FORCE ROW LEVEL SECURITY;


--
-- Name: invigilation_duty; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invigilation_duty (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    exam_paper_id uuid NOT NULL,
    room_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    role text DEFAULT 'invigilator'::text NOT NULL,
    status text DEFAULT 'assigned'::text NOT NULL,
    swap_with uuid,
    CONSTRAINT invigilation_duty_role_check CHECK ((role = ANY (ARRAY['chief'::text, 'invigilator'::text, 'relief'::text]))),
    CONSTRAINT invigilation_duty_status_check CHECK ((status = ANY (ARRAY['assigned'::text, 'accepted'::text, 'swap_requested'::text, 'declined'::text])))
);

ALTER TABLE ONLY public.invigilation_duty FORCE ROW LEVEL SECURITY;


--
-- Name: leave_of_absence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_of_absence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    requested_on date DEFAULT CURRENT_DATE NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    reason text NOT NULL,
    approver_level text NOT NULL,
    status text DEFAULT 'submitted'::text NOT NULL,
    decided_on date,
    decision_ref text,
    extension_of uuid,
    resumed_on date,
    CONSTRAINT leave_of_absence_approver_level_check CHECK ((approver_level = ANY (ARRAY['zone_director'::text, 'director_school_management'::text]))),
    CONSTRAINT leave_of_absence_check CHECK ((ends_on >= starts_on)),
    CONSTRAINT leave_of_absence_status_check CHECK ((status = ANY (ARRAY['submitted'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'resumed'::text])))
);

ALTER TABLE ONLY public.leave_of_absence FORCE ROW LEVEL SECURITY;


--
-- Name: leaving_certificate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaving_certificate (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    issued_on date DEFAULT CURRENT_DATE NOT NULL,
    attendance_summary jsonb,
    conduct text,
    reason text,
    pdf_path text,
    issued_by uuid
);

ALTER TABLE ONLY public.leaving_certificate FORCE ROW LEVEL SECURITY;


--
-- Name: lesson_plan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_plan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    timetable_slot_id uuid,
    date date NOT NULL,
    objectives text,
    procedure text,
    methods text,
    activities text,
    resources text,
    evaluation text,
    homework text,
    attachments text[] DEFAULT '{}'::text[] NOT NULL
);

ALTER TABLE ONLY public.lesson_plan FORCE ROW LEVEL SECURITY;


--
-- Name: lesson_substitution; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_substitution (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    date date NOT NULL,
    timetable_slot_id uuid NOT NULL,
    absent_staff_id uuid,
    substitute_staff_id uuid,
    reason text,
    status text DEFAULT 'proposed'::text NOT NULL,
    assigned_by uuid,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lesson_substitution_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'accepted'::text, 'declined'::text, 'uncovered'::text])))
);

ALTER TABLE ONLY public.lesson_substitution FORCE ROW LEVEL SECURITY;


--
-- Name: library_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    isbn text,
    title text NOT NULL,
    author text,
    category text,
    copies smallint DEFAULT 1 NOT NULL,
    shelf text
);

ALTER TABLE ONLY public.library_item FORCE ROW LEVEL SECURITY;


--
-- Name: library_loan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library_loan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    library_item_id uuid NOT NULL,
    student_id uuid,
    staff_id uuid,
    out_on date DEFAULT CURRENT_DATE NOT NULL,
    due_on date NOT NULL,
    returned_on date,
    CONSTRAINT library_loan_check CHECK (((student_id IS NOT NULL) OR (staff_id IS NOT NULL)))
);

ALTER TABLE ONLY public.library_loan FORCE ROW LEVEL SECURITY;


--
-- Name: maintenance_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_request (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    room_id uuid,
    asset_id uuid,
    reported_by uuid,
    reported_on date DEFAULT CURRENT_DATE NOT NULL,
    description text NOT NULL,
    priority text DEFAULT 'normal'::text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    assigned_to text,
    completed_on date,
    photos text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT maintenance_request_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT maintenance_request_status_check CHECK ((status = ANY (ARRAY['open'::text, 'assigned'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.maintenance_request FORCE ROW LEVEL SECURITY;


--
-- Name: mark; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mark (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    assessment_id uuid NOT NULL,
    student_id uuid NOT NULL,
    score numeric(6,2),
    code text,
    band_label text,
    comment text,
    entered_by uuid,
    entered_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mark_check CHECK (((score IS NOT NULL) OR (code IS NOT NULL))),
    CONSTRAINT mark_code_check CHECK ((code = ANY (ARRAY['ABS'::text, 'EXEMPT'::text, 'MED'::text, 'DEBARRED'::text]))),
    CONSTRAINT mark_score_check CHECK ((score >= (0)::numeric))
);

ALTER TABLE ONLY public.mark FORCE ROW LEVEL SECURITY;


--
-- Name: mark_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mark_history (
    id bigint NOT NULL,
    school_id uuid NOT NULL,
    mark_id uuid NOT NULL,
    old_score numeric(6,2),
    new_score numeric(6,2),
    old_code text,
    new_code text,
    changed_by uuid,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    reason text
);

ALTER TABLE ONLY public.mark_history FORCE ROW LEVEL SECURITY;


--
-- Name: mark_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.mark_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mark_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.mark_history_id_seq OWNED BY public.mark_history.id;


--
-- Name: meeting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meeting (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    kind text NOT NULL,
    committee_id uuid,
    department_id uuid,
    title text NOT NULL,
    held_on timestamp with time zone NOT NULL,
    venue text,
    agenda text,
    chaired_by uuid,
    minutes text,
    minutes_path text,
    visibility text DEFAULT 'internal'::text NOT NULL,
    CONSTRAINT meeting_kind_check CHECK ((kind = ANY (ARRAY['staff'::text, 'smt'::text, 'departmental'::text, 'committee'::text, 'pta'::text, 'parent'::text, 'assembly'::text]))),
    CONSTRAINT meeting_visibility_check CHECK ((visibility = ANY (ARRAY['internal'::text, 'smt'::text, 'public'::text])))
);

ALTER TABLE ONLY public.meeting FORCE ROW LEVEL SECURITY;


--
-- Name: meeting_attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meeting_attendance (
    meeting_id uuid NOT NULL,
    person_id uuid NOT NULL,
    present boolean DEFAULT true NOT NULL,
    apology boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.meeting_attendance FORCE ROW LEVEL SECURITY;


--
-- Name: merit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    kind text NOT NULL,
    reason text NOT NULL,
    awarded_by uuid,
    awarded_on date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT merit_kind_check CHECK ((kind = ANY (ARRAY['bonus_marks'::text, 'responsibility'::text, 'good_behaviour_certificate'::text, 'award'::text, 'commendation'::text])))
);

ALTER TABLE ONLY public.merit FORCE ROW LEVEL SECURITY;


--
-- Name: message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    body text NOT NULL,
    attachments text[] DEFAULT '{}'::text[] NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.message FORCE ROW LEVEL SECURITY;


--
-- Name: message_thread; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_thread (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    subject text NOT NULL,
    about_student_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.message_thread FORCE ROW LEVEL SECURITY;


--
-- Name: notice; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notice (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    audience jsonb DEFAULT '{"all": true}'::jsonb NOT NULL,
    publish_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    pinned boolean DEFAULT false NOT NULL,
    requires_acknowledgement boolean DEFAULT false NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notice FORCE ROW LEVEL SECURITY;


--
-- Name: notice_read; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notice_read (
    notice_id uuid NOT NULL,
    person_id uuid NOT NULL,
    read_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notice_read FORCE ROW LEVEL SECURITY;


--
-- Name: notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    person_id uuid NOT NULL,
    channel text NOT NULL,
    template text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    provider_ref text,
    scheduled_for timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    error text,
    CONSTRAINT notification_channel_check CHECK ((channel = ANY (ARRAY['in_app'::text, 'sms'::text, 'email'::text, 'push'::text]))),
    CONSTRAINT notification_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text, 'delivered'::text, 'failed'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.notification FORCE ROW LEVEL SECURITY;


--
-- Name: occurrence_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.occurrence_log (
    id bigint NOT NULL,
    school_id uuid NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    entered_at timestamp with time zone DEFAULT now() NOT NULL,
    entered_by uuid NOT NULL,
    category text,
    entry text NOT NULL,
    corrects_entry_id bigint
);

ALTER TABLE ONLY public.occurrence_log FORCE ROW LEVEL SECURITY;


--
-- Name: occurrence_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.occurrence_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: occurrence_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.occurrence_log_id_seq OWNED BY public.occurrence_log.id;


--
-- Name: option_block; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.option_block (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    grade_level_id uuid NOT NULL,
    name text NOT NULL,
    min_choices smallint DEFAULT 1 NOT NULL,
    max_choices smallint DEFAULT 1 NOT NULL,
    CONSTRAINT option_block_check CHECK ((max_choices >= min_choices))
);

ALTER TABLE ONLY public.option_block FORCE ROW LEVEL SECURITY;


--
-- Name: option_block_subject; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.option_block_subject (
    option_block_id uuid NOT NULL,
    subject_id uuid NOT NULL
);

ALTER TABLE ONLY public.option_block_subject FORCE ROW LEVEL SECURITY;


--
-- Name: pastoral_case; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pastoral_case (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    opened_on date DEFAULT CURRENT_DATE NOT NULL,
    trigger text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    external_referral_to text,
    guardian_consent_given boolean,
    guardian_consent_path text,
    guardian_consent_on date,
    review_on date,
    outcome text,
    closed_on date,
    CONSTRAINT pastoral_case_status_check CHECK ((status = ANY (ARRAY['open'::text, 'monitoring'::text, 'closed'::text]))),
    CONSTRAINT pastoral_case_trigger_check CHECK ((trigger = ANY (ARRAY['attendance'::text, 'performance'::text, 'behaviour'::text, 'welfare'::text, 'referral'::text, 'other'::text])))
);

ALTER TABLE ONLY public.pastoral_case FORCE ROW LEVEL SECURITY;


--
-- Name: pastoral_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pastoral_note (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    pastoral_case_id uuid NOT NULL,
    author_id uuid NOT NULL,
    note text NOT NULL,
    visibility text DEFAULT 'committee'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pastoral_note_visibility_check CHECK ((visibility = ANY (ARRAY['committee'::text, 'smt'::text, 'rector_only'::text])))
);

ALTER TABLE ONLY public.pastoral_note FORCE ROW LEVEL SECURITY;


--
-- Name: period_attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.period_attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    date date NOT NULL,
    timetable_slot_id uuid,
    subject_set_id uuid NOT NULL,
    student_id uuid NOT NULL,
    status public.attendance_status NOT NULL,
    recorded_by uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.period_attendance FORCE ROW LEVEL SECURITY;


--
-- Name: policy_acknowledgement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policy_acknowledgement (
    policy_document_id uuid NOT NULL,
    person_id uuid NOT NULL,
    acknowledged_at timestamp with time zone DEFAULT now() NOT NULL,
    ip inet
);

ALTER TABLE ONLY public.policy_acknowledgement FORCE ROW LEVEL SECURITY;


--
-- Name: policy_document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policy_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    kind text NOT NULL,
    version text NOT NULL,
    file_path text,
    body text,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT policy_document_kind_check CHECK ((kind = ANY (ARRAY['school_rules'::text, 'pta_rules'::text, 'safeguarding'::text, 'other'::text])))
);

ALTER TABLE ONLY public.policy_document FORCE ROW LEVEL SECURITY;


--
-- Name: public_holiday; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.public_holiday (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country character(2) DEFAULT 'MU'::bpchar NOT NULL,
    year smallint NOT NULL,
    date date NOT NULL,
    name text NOT NULL,
    is_computed boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.public_holiday FORCE ROW LEVEL SECURITY;


--
-- Name: term_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.term_result (
    school_id uuid NOT NULL,
    term_id uuid NOT NULL,
    student_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    subject_set_id uuid,
    aggregate_score numeric(6,2),
    band_label text,
    rank_in_set smallint,
    rank_in_grade smallint,
    set_size smallint,
    educator_comment text,
    difficulties text,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.term_result FORCE ROW LEVEL SECURITY;


--
-- Name: pupils_at_risk; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.pupils_at_risk WITH (security_invoker='true') AS
 SELECT s.id AS student_id,
    p.first_name,
    p.last_name,
    s.admission_number,
    cg.name AS class_name,
    gl.grade,
    round(avg(sm.pct_present), 2) AS attendance_pct,
    ( SELECT round(avg(tr.aggregate_score), 1) AS round
           FROM public.term_result tr
          WHERE (tr.student_id = s.id)) AS mean_score,
    ( SELECT count(*) AS count
           FROM public.disciplinary_case dc
          WHERE ((dc.student_id = s.id) AND (dc.closed_on IS NULL))) AS open_cases,
    ( SELECT count(*) AS count
           FROM (public.incident_student isr
             JOIN public.incident i ON ((i.id = isr.incident_id)))
          WHERE ((isr.student_id = s.id) AND (i.occurred_at > (now() - '90 days'::interval)))) AS recent_incidents
   FROM (((((public.student s
     JOIN public.person p ON ((p.id = s.id)))
     LEFT JOIN public.class_enrolment ce ON (((ce.student_id = s.id) AND (ce.effective_to IS NULL))))
     LEFT JOIN public.class_group cg ON ((cg.id = ce.class_group_id)))
     LEFT JOIN public.grade_level gl ON ((gl.id = cg.grade_level_id)))
     LEFT JOIN public.attendance_summary sm ON ((sm.student_id = s.id)))
  WHERE (s.status = 'enrolled'::public.student_status)
  GROUP BY s.id, p.first_name, p.last_name, s.admission_number, cg.name, gl.grade;


--
-- Name: report_card; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_card (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    term_id uuid NOT NULL,
    student_id uuid NOT NULL,
    overall_score numeric(6,2),
    overall_rank smallint,
    class_size smallint,
    attendance_pct numeric(5,2),
    times_late integer,
    form_teacher_comment text,
    rector_comment text,
    pdf_path text,
    status text DEFAULT 'draft'::text NOT NULL,
    published_at timestamp with time zone,
    CONSTRAINT report_card_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])))
);

ALTER TABLE ONLY public.report_card FORCE ROW LEVEL SECURITY;


--
-- Name: results_by_subject; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.results_by_subject WITH (security_invoker='true') AS
 SELECT sub.id AS subject_id,
    sub.name_en AS subject_name,
    gl.grade,
    t.id AS term_id,
    t.name AS term_name,
    count(*) AS entries,
    round(avg(tr.aggregate_score), 2) AS mean_score,
    percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((tr.aggregate_score)::double precision)) AS median_score,
    min(tr.aggregate_score) AS lowest,
    max(tr.aggregate_score) AS highest,
    count(*) FILTER (WHERE (tr.aggregate_score >= (40)::numeric)) AS passes,
    round(((100.0 * (count(*) FILTER (WHERE (tr.aggregate_score >= (40)::numeric)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pass_rate,
    count(*) FILTER (WHERE (tr.aggregate_score >= (75)::numeric)) AS credits
   FROM ((((public.term_result tr
     JOIN public.subject sub ON ((sub.id = tr.subject_id)))
     JOIN public.term t ON ((t.id = tr.term_id)))
     LEFT JOIN public.subject_set ss ON ((ss.id = tr.subject_set_id)))
     LEFT JOIN public.grade_level gl ON ((gl.id = ss.grade_level_id)))
  GROUP BY sub.id, sub.name_en, gl.grade, t.id, t.name;


--
-- Name: role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role (
    code text NOT NULL,
    name text NOT NULL,
    default_scope public.role_scope DEFAULT 'school'::public.role_scope NOT NULL,
    sort_order smallint DEFAULT 100 NOT NULL
);

ALTER TABLE ONLY public.role FORCE ROW LEVEL SECURITY;


--
-- Name: role_capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_capability (
    role_code text NOT NULL,
    capability_code text NOT NULL
);

ALTER TABLE ONLY public.role_capability FORCE ROW LEVEL SECURITY;


--
-- Name: room; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.room (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    room_type public.room_type DEFAULT 'classroom'::public.room_type NOT NULL,
    capacity smallint DEFAULT 40 NOT NULL,
    exam_capacity smallint,
    block text,
    floor smallint,
    features text[] DEFAULT '{}'::text[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.room FORCE ROW LEVEL SECURITY;


--
-- Name: sanction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sanction (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    disciplinary_case_id uuid,
    student_id uuid NOT NULL,
    kind text NOT NULL,
    starts_on date,
    ends_on date,
    details text,
    issued_by uuid NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    guardian_notified_at timestamp with time zone,
    CONSTRAINT sanction_kind_check CHECK ((kind = ANY (ARRAY['warning'::text, 'counselling'::text, 'detention'::text, 'special_report'::text, 'community_service'::text, 'suspension'::text, 'exclusion'::text])))
);

ALTER TABLE ONLY public.sanction FORCE ROW LEVEL SECURITY;


--
-- Name: scheme_of_work; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheme_of_work (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    term_id uuid NOT NULL,
    status public.plan_status DEFAULT 'draft'::public.plan_status NOT NULL,
    due_on date,
    submitted_at timestamp with time zone,
    hod_reviewed_by uuid,
    hod_reviewed_at timestamp with time zone,
    hod_comment text,
    rector_approved_by uuid,
    rector_approved_at timestamp with time zone
);

ALTER TABLE ONLY public.scheme_of_work FORCE ROW LEVEL SECURITY;


--
-- Name: scheme_week; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheme_week (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    scheme_of_work_id uuid NOT NULL,
    week_no smallint NOT NULL,
    objectives text,
    activities text,
    resources text,
    assessment_strategy text,
    revision_notes text,
    syllabus_unit_id uuid
);

ALTER TABLE ONLY public.scheme_week FORCE ROW LEVEL SECURITY;


--
-- Name: school; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.school (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    type public.school_type DEFAULT 'state'::public.school_type NOT NULL,
    zone smallint,
    address jsonb DEFAULT '{}'::jsonb NOT NULL,
    contact jsonb DEFAULT '{}'::jsonb NOT NULL,
    logo_path text,
    motto text,
    vision text,
    mission text,
    locale text DEFAULT 'en'::text NOT NULL,
    timezone text DEFAULT 'Indian/Mauritius'::text NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT school_zone_check CHECK (((zone >= 1) AND (zone <= 4)))
);

ALTER TABLE ONLY public.school FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN school.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.school.settings IS 'Feature flags and policy thresholds, e.g. {"exam_eligibility_pct":80,"second_attempt_pct":75,"internal_exam_max_days":10,"suppress_ranks_grades":[7,8]}';


--
-- Name: script_batch; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.script_batch (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    exam_paper_id uuid NOT NULL,
    room_id uuid,
    count_issued smallint,
    count_collected smallint,
    collected_by uuid,
    collected_at timestamp with time zone,
    marker_id uuid,
    issued_to_marker_at timestamp with time zone,
    returned_at timestamp with time zone,
    marks_entered_at timestamp with time zone,
    note text
);

ALTER TABLE ONLY public.script_batch FORCE ROW LEVEL SECURITY;


--
-- Name: set_educator; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.set_educator (
    subject_set_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    is_primary boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.set_educator FORCE ROW LEVEL SECURITY;


--
-- Name: set_enrolment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.set_enrolment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    student_id uuid NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT set_enrolment_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);

ALTER TABLE ONLY public.set_enrolment FORCE ROW LEVEL SECURITY;


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id uuid NOT NULL,
    school_id uuid NOT NULL,
    staff_number text NOT NULL,
    post text NOT NULL,
    scheme_of_service text,
    employment_type text DEFAULT 'permanent'::text NOT NULL,
    appointed_on date,
    confirmed_on date,
    exited_on date,
    department_id uuid,
    max_periods_per_cycle smallint,
    unavailable_slots jsonb DEFAULT '[]'::jsonb NOT NULL
);

ALTER TABLE ONLY public.staff FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN staff.unavailable_slots; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.staff.unavailable_slots IS 'Part-time / released patterns consumed by the timetable solver, e.g. [{"cycle_day":3,"periods":[1,2]}]';


--
-- Name: staff_document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    kind public.document_kind NOT NULL,
    title text,
    storage_path text NOT NULL,
    uploaded_by uuid,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.staff_document FORCE ROW LEVEL SECURITY;


--
-- Name: staff_leave; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_leave (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    kind text DEFAULT 'sick'::text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    reason text,
    status text DEFAULT 'submitted'::text NOT NULL,
    approved_by uuid,
    decided_at timestamp with time zone,
    CONSTRAINT staff_leave_check CHECK ((ends_on >= starts_on)),
    CONSTRAINT staff_leave_kind_check CHECK ((kind = ANY (ARRAY['sick'::text, 'casual'::text, 'vacation'::text, 'duty'::text, 'training'::text, 'other'::text]))),
    CONSTRAINT staff_leave_status_check CHECK ((status = ANY (ARRAY['submitted'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.staff_leave FORCE ROW LEVEL SECURITY;


--
-- Name: staff_role_assignment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_role_assignment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    role_code text NOT NULL,
    scope_type public.role_scope DEFAULT 'school'::public.role_scope NOT NULL,
    scope_id uuid,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT staff_role_assignment_check CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))
);

ALTER TABLE ONLY public.staff_role_assignment FORCE ROW LEVEL SECURITY;


--
-- Name: student_document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    kind public.document_kind NOT NULL,
    title text,
    storage_path text NOT NULL,
    mime_type text,
    size_bytes integer,
    verified_by uuid,
    verified_at timestamp with time zone,
    is_sensitive boolean DEFAULT true NOT NULL,
    uploaded_by uuid,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_on date
);

ALTER TABLE ONLY public.student_document FORCE ROW LEVEL SECURITY;


--
-- Name: student_guardian; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_guardian (
    student_id uuid NOT NULL,
    guardian_id uuid NOT NULL,
    relationship text NOT NULL,
    is_responsible_party boolean DEFAULT false NOT NULL,
    has_custody boolean DEFAULT true NOT NULL,
    can_collect boolean DEFAULT true NOT NULL,
    contact_priority smallint DEFAULT 1 NOT NULL
);

ALTER TABLE ONLY public.student_guardian FORCE ROW LEVEL SECURITY;


--
-- Name: student_movement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_movement (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    student_id uuid NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    out_at timestamp with time zone,
    in_at timestamp with time zone,
    reason text NOT NULL,
    authorised_by uuid,
    collected_by text,
    escort text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.student_movement FORCE ROW LEVEL SECURITY;


--
-- Name: syllabus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.syllabus (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    grade_level_id uuid NOT NULL,
    version smallint DEFAULT 1 NOT NULL,
    external_ref text,
    status text DEFAULT 'draft'::text NOT NULL
);

ALTER TABLE ONLY public.syllabus FORCE ROW LEVEL SECURITY;


--
-- Name: weekly_plan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_plan (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    staff_id uuid NOT NULL,
    subject_set_id uuid NOT NULL,
    week_start date NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL
);

ALTER TABLE ONLY public.weekly_plan FORCE ROW LEVEL SECURITY;


--
-- Name: weekly_plan_row; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_plan_row (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    weekly_plan_id uuid NOT NULL,
    timetable_slot_id uuid,
    date date NOT NULL,
    planned text,
    actual text,
    remarks text,
    covered boolean
);

ALTER TABLE ONLY public.weekly_plan_row FORCE ROW LEVEL SECURITY;


--
-- Name: syllabus_coverage; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.syllabus_coverage WITH (security_invoker='true') AS
 SELECT ss.id AS subject_set_id,
    ss.name AS set_name,
    sub.name_en AS subject_name,
    t.id AS term_id,
    t.name AS term_name,
    count(wpr.id) AS periods_recorded,
    count(wpr.id) FILTER (WHERE wpr.covered) AS periods_covered,
        CASE
            WHEN (count(wpr.id) = 0) THEN NULL::numeric
            ELSE round(((100.0 * (count(wpr.id) FILTER (WHERE wpr.covered))::numeric) / (count(wpr.id))::numeric), 1)
        END AS coverage_pct
   FROM ((((public.subject_set ss
     JOIN public.subject sub ON ((sub.id = ss.subject_id)))
     JOIN public.term t ON ((t.academic_year_id = ss.academic_year_id)))
     LEFT JOIN public.weekly_plan wp ON (((wp.subject_set_id = ss.id) AND ((wp.week_start >= t.starts_on) AND (wp.week_start <= t.ends_on)))))
     LEFT JOIN public.weekly_plan_row wpr ON ((wpr.weekly_plan_id = wp.id)))
  GROUP BY ss.id, ss.name, sub.name_en, t.id, t.name;


--
-- Name: syllabus_unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.syllabus_unit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    syllabus_id uuid NOT NULL,
    parent_id uuid,
    code text,
    title text NOT NULL,
    objectives text[] DEFAULT '{}'::text[] NOT NULL,
    term_id uuid,
    sort_order smallint DEFAULT 0 NOT NULL
);

ALTER TABLE ONLY public.syllabus_unit FORCE ROW LEVEL SECURITY;


--
-- Name: teaching_resource; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teaching_resource (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    department_id uuid,
    subject_id uuid,
    grade_level_id uuid,
    syllabus_unit_id uuid,
    title text NOT NULL,
    storage_path text,
    url text,
    uploaded_by uuid,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.teaching_resource FORCE ROW LEVEL SECURITY;


--
-- Name: thread_participant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.thread_participant (
    thread_id uuid NOT NULL,
    person_id uuid NOT NULL,
    last_read_at timestamp with time zone
);

ALTER TABLE ONLY public.thread_participant FORCE ROW LEVEL SECURITY;


--
-- Name: timetable_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timetable_version (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    academic_year_id uuid NOT NULL,
    version smallint NOT NULL,
    label text,
    cycle_length smallint DEFAULT 5 NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status text DEFAULT 'draft'::text NOT NULL,
    published_by uuid,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT timetable_version_cycle_length_check CHECK (((cycle_length >= 1) AND (cycle_length <= 20))),
    CONSTRAINT timetable_version_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'superseded'::text])))
);

ALTER TABLE ONLY public.timetable_version FORCE ROW LEVEL SECURITY;


--
-- Name: visitor_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.visitor_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    name text NOT NULL,
    organisation text,
    purpose text NOT NULL,
    host_staff_id uuid,
    signed_in_at timestamp with time zone DEFAULT now() NOT NULL,
    signed_out_at timestamp with time zone,
    badge_no text
);

ALTER TABLE ONLY public.visitor_log FORCE ROW LEVEL SECURITY;


--
-- Name: water_quality_certificate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.water_quality_certificate (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    school_id uuid NOT NULL,
    issued_on date NOT NULL,
    expires_on date,
    tanks_cleaned_on date,
    file_path text,
    issued_by_body text DEFAULT 'Ministry of Health and Quality of Life'::text
);

ALTER TABLE ONLY public.water_quality_certificate FORCE ROW LEVEL SECURITY;


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: mark_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark_history ALTER COLUMN id SET DEFAULT nextval('public.mark_history_id_seq'::regclass);


--
-- Name: occurrence_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occurrence_log ALTER COLUMN id SET DEFAULT nextval('public.occurrence_log_id_seq'::regclass);


--
-- Name: absence_note absence_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absence_note
    ADD CONSTRAINT absence_note_pkey PRIMARY KEY (id);


--
-- Name: academic_year academic_year_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_year
    ADD CONSTRAINT academic_year_pkey PRIMARY KEY (id);


--
-- Name: academic_year academic_year_school_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_year
    ADD CONSTRAINT academic_year_school_id_name_key UNIQUE (school_id, name);


--
-- Name: action_item action_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_item
    ADD CONSTRAINT action_item_pkey PRIMARY KEY (id);


--
-- Name: admission_checklist admission_checklist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_checklist
    ADD CONSTRAINT admission_checklist_pkey PRIMARY KEY (student_id);


--
-- Name: assessment assessment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_pkey PRIMARY KEY (id);


--
-- Name: asset asset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset
    ADD CONSTRAINT asset_pkey PRIMARY KEY (id);


--
-- Name: asset asset_school_id_tag_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset
    ADD CONSTRAINT asset_school_id_tag_key UNIQUE (school_id, tag);


--
-- Name: asset_verification asset_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_verification
    ADD CONSTRAINT asset_verification_pkey PRIMARY KEY (id);


--
-- Name: attendance_discrepancy attendance_discrepancy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_pkey PRIMARY KEY (id);


--
-- Name: attendance_record attendance_record_attendance_session_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_attendance_session_id_student_id_key UNIQUE (attendance_session_id, student_id);


--
-- Name: attendance_record attendance_record_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_pkey PRIMARY KEY (id);


--
-- Name: attendance_session attendance_session_class_group_id_date_session_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_class_group_id_date_session_key UNIQUE (class_group_id, date, session);


--
-- Name: attendance_session attendance_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_pkey PRIMARY KEY (id);


--
-- Name: attendance_summary attendance_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_summary
    ADD CONSTRAINT attendance_summary_pkey PRIMARY KEY (term_id, student_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: calendar_day calendar_day_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_day
    ADD CONSTRAINT calendar_day_pkey PRIMARY KEY (id);


--
-- Name: calendar_day calendar_day_school_id_academic_year_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_day
    ADD CONSTRAINT calendar_day_school_id_academic_year_id_date_key UNIQUE (school_id, academic_year_id, date);


--
-- Name: capability capability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capability
    ADD CONSTRAINT capability_pkey PRIMARY KEY (code);


--
-- Name: circular_ack circular_ack_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.circular_ack
    ADD CONSTRAINT circular_ack_pkey PRIMARY KEY (circular_id, person_id);


--
-- Name: circular circular_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.circular
    ADD CONSTRAINT circular_pkey PRIMARY KEY (id);


--
-- Name: class_enrolment class_enrolment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_enrolment
    ADD CONSTRAINT class_enrolment_pkey PRIMARY KEY (id);


--
-- Name: class_group class_group_academic_year_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_academic_year_id_name_key UNIQUE (academic_year_id, name);


--
-- Name: class_group class_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_pkey PRIMARY KEY (id);


--
-- Name: clearance_item clearance_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clearance_item
    ADD CONSTRAINT clearance_item_pkey PRIMARY KEY (id);


--
-- Name: clearance_item clearance_item_student_id_kind_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clearance_item
    ADD CONSTRAINT clearance_item_student_id_kind_key UNIQUE (student_id, kind);


--
-- Name: committee committee_academic_year_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee
    ADD CONSTRAINT committee_academic_year_id_code_key UNIQUE (academic_year_id, code);


--
-- Name: committee_member committee_member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_member
    ADD CONSTRAINT committee_member_pkey PRIMARY KEY (committee_id, person_id);


--
-- Name: committee committee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee
    ADD CONSTRAINT committee_pkey PRIMARY KEY (id);


--
-- Name: confidential_note confidential_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confidential_note
    ADD CONSTRAINT confidential_note_pkey PRIMARY KEY (id);


--
-- Name: correspondence correspondence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correspondence
    ADD CONSTRAINT correspondence_pkey PRIMARY KEY (id);


--
-- Name: department department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_pkey PRIMARY KEY (id);


--
-- Name: department department_school_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_school_id_code_key UNIQUE (school_id, code);


--
-- Name: disciplinary_case disciplinary_case_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinary_case
    ADD CONSTRAINT disciplinary_case_pkey PRIMARY KEY (id);


--
-- Name: exam_arrangement exam_arrangement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_pkey PRIMARY KEY (id);


--
-- Name: exam_arrangement exam_arrangement_student_id_academic_year_id_kind_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_student_id_academic_year_id_kind_key UNIQUE (student_id, academic_year_id, kind);


--
-- Name: exam_eligibility_decision exam_eligibility_decision_exam_session_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_exam_session_id_student_id_key UNIQUE (exam_session_id, student_id);


--
-- Name: exam_eligibility_decision exam_eligibility_decision_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_pkey PRIMARY KEY (id);


--
-- Name: exam_paper exam_paper_exam_session_id_subject_id_grade_level_id_paper__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_exam_session_id_subject_id_grade_level_id_paper__key UNIQUE (exam_session_id, subject_id, grade_level_id, paper_number);


--
-- Name: exam_paper exam_paper_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_pkey PRIMARY KEY (id);


--
-- Name: exam_seat exam_seat_exam_paper_id_room_id_seat_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_exam_paper_id_room_id_seat_label_key UNIQUE (exam_paper_id, room_id, seat_label);


--
-- Name: exam_seat exam_seat_exam_paper_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_exam_paper_id_student_id_key UNIQUE (exam_paper_id, student_id);


--
-- Name: exam_seat exam_seat_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_pkey PRIMARY KEY (id);


--
-- Name: exam_session exam_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_session
    ADD CONSTRAINT exam_session_pkey PRIMARY KEY (id);


--
-- Name: grade_level grade_level_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_level
    ADD CONSTRAINT grade_level_pkey PRIMARY KEY (id);


--
-- Name: grade_level grade_level_school_id_grade_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_level
    ADD CONSTRAINT grade_level_school_id_grade_key UNIQUE (school_id, grade);


--
-- Name: grading_band grading_band_grading_scale_id_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_band
    ADD CONSTRAINT grading_band_grading_scale_id_label_key UNIQUE (grading_scale_id, label);


--
-- Name: grading_band grading_band_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_band
    ADD CONSTRAINT grading_band_pkey PRIMARY KEY (id);


--
-- Name: grading_scale grading_scale_academic_year_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_scale
    ADD CONSTRAINT grading_scale_academic_year_id_code_key UNIQUE (academic_year_id, code);


--
-- Name: grading_scale grading_scale_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_scale
    ADD CONSTRAINT grading_scale_pkey PRIMARY KEY (id);


--
-- Name: guardian guardian_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardian
    ADD CONSTRAINT guardian_pkey PRIMARY KEY (id);


--
-- Name: health_record health_record_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.health_record
    ADD CONSTRAINT health_record_pkey PRIMARY KEY (id);


--
-- Name: homework homework_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework
    ADD CONSTRAINT homework_pkey PRIMARY KEY (id);


--
-- Name: homework_submission homework_submission_homework_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework_submission
    ADD CONSTRAINT homework_submission_homework_id_student_id_key UNIQUE (homework_id, student_id);


--
-- Name: homework_submission homework_submission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework_submission
    ADD CONSTRAINT homework_submission_pkey PRIMARY KEY (id);


--
-- Name: incident incident_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident
    ADD CONSTRAINT incident_pkey PRIMARY KEY (id);


--
-- Name: incident_student incident_student_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident_student
    ADD CONSTRAINT incident_student_pkey PRIMARY KEY (incident_id, student_id);


--
-- Name: invigilation_duty invigilation_duty_exam_paper_id_room_id_staff_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_exam_paper_id_room_id_staff_id_key UNIQUE (exam_paper_id, room_id, staff_id);


--
-- Name: invigilation_duty invigilation_duty_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_pkey PRIMARY KEY (id);


--
-- Name: leave_of_absence leave_of_absence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_of_absence
    ADD CONSTRAINT leave_of_absence_pkey PRIMARY KEY (id);


--
-- Name: leaving_certificate leaving_certificate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaving_certificate
    ADD CONSTRAINT leaving_certificate_pkey PRIMARY KEY (id);


--
-- Name: leaving_certificate leaving_certificate_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaving_certificate
    ADD CONSTRAINT leaving_certificate_student_id_key UNIQUE (student_id);


--
-- Name: lesson_plan lesson_plan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_plan
    ADD CONSTRAINT lesson_plan_pkey PRIMARY KEY (id);


--
-- Name: lesson_substitution lesson_substitution_date_timetable_slot_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_date_timetable_slot_id_key UNIQUE (date, timetable_slot_id);


--
-- Name: lesson_substitution lesson_substitution_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_pkey PRIMARY KEY (id);


--
-- Name: library_item library_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_item
    ADD CONSTRAINT library_item_pkey PRIMARY KEY (id);


--
-- Name: library_loan library_loan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_loan
    ADD CONSTRAINT library_loan_pkey PRIMARY KEY (id);


--
-- Name: maintenance_request maintenance_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_request
    ADD CONSTRAINT maintenance_request_pkey PRIMARY KEY (id);


--
-- Name: mark mark_assessment_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_assessment_id_student_id_key UNIQUE (assessment_id, student_id);


--
-- Name: mark_history mark_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark_history
    ADD CONSTRAINT mark_history_pkey PRIMARY KEY (id);


--
-- Name: mark mark_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_pkey PRIMARY KEY (id);


--
-- Name: meeting_attendance meeting_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendance
    ADD CONSTRAINT meeting_attendance_pkey PRIMARY KEY (meeting_id, person_id);


--
-- Name: meeting meeting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_pkey PRIMARY KEY (id);


--
-- Name: merit merit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merit
    ADD CONSTRAINT merit_pkey PRIMARY KEY (id);


--
-- Name: message message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id);


--
-- Name: message_thread message_thread_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_thread
    ADD CONSTRAINT message_thread_pkey PRIMARY KEY (id);


--
-- Name: notice notice_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice
    ADD CONSTRAINT notice_pkey PRIMARY KEY (id);


--
-- Name: notice_read notice_read_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_read
    ADD CONSTRAINT notice_read_pkey PRIMARY KEY (notice_id, person_id);


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);


--
-- Name: occurrence_log occurrence_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occurrence_log
    ADD CONSTRAINT occurrence_log_pkey PRIMARY KEY (id);


--
-- Name: option_block option_block_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block
    ADD CONSTRAINT option_block_pkey PRIMARY KEY (id);


--
-- Name: option_block_subject option_block_subject_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block_subject
    ADD CONSTRAINT option_block_subject_pkey PRIMARY KEY (option_block_id, subject_id);


--
-- Name: pastoral_case pastoral_case_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_case
    ADD CONSTRAINT pastoral_case_pkey PRIMARY KEY (id);


--
-- Name: pastoral_note pastoral_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_note
    ADD CONSTRAINT pastoral_note_pkey PRIMARY KEY (id);


--
-- Name: period_attendance period_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_pkey PRIMARY KEY (id);


--
-- Name: period_attendance period_attendance_subject_set_id_date_timetable_slot_id_stu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_subject_set_id_date_timetable_slot_id_stu_key UNIQUE (subject_set_id, date, timetable_slot_id, student_id);


--
-- Name: period_definition period_definition_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_definition
    ADD CONSTRAINT period_definition_pkey PRIMARY KEY (id);


--
-- Name: period_definition period_definition_timetable_version_id_sequence_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_definition
    ADD CONSTRAINT period_definition_timetable_version_id_sequence_key UNIQUE (timetable_version_id, sequence);


--
-- Name: person person_auth_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_auth_user_id_key UNIQUE (auth_user_id);


--
-- Name: person person_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_pkey PRIMARY KEY (id);


--
-- Name: policy_acknowledgement policy_acknowledgement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_acknowledgement
    ADD CONSTRAINT policy_acknowledgement_pkey PRIMARY KEY (policy_document_id, person_id);


--
-- Name: policy_document policy_document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_document
    ADD CONSTRAINT policy_document_pkey PRIMARY KEY (id);


--
-- Name: policy_document policy_document_school_id_kind_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_document
    ADD CONSTRAINT policy_document_school_id_kind_version_key UNIQUE (school_id, kind, version);


--
-- Name: public_holiday public_holiday_country_date_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holiday
    ADD CONSTRAINT public_holiday_country_date_name_key UNIQUE (country, date, name);


--
-- Name: public_holiday public_holiday_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holiday
    ADD CONSTRAINT public_holiday_pkey PRIMARY KEY (id);


--
-- Name: report_card report_card_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_pkey PRIMARY KEY (id);


--
-- Name: report_card report_card_term_id_student_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_term_id_student_id_key UNIQUE (term_id, student_id);


--
-- Name: role_capability role_capability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capability
    ADD CONSTRAINT role_capability_pkey PRIMARY KEY (role_code, capability_code);


--
-- Name: role role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_pkey PRIMARY KEY (code);


--
-- Name: room room_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT room_pkey PRIMARY KEY (id);


--
-- Name: room room_school_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT room_school_id_code_key UNIQUE (school_id, code);


--
-- Name: sanction sanction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanction
    ADD CONSTRAINT sanction_pkey PRIMARY KEY (id);


--
-- Name: scheme_of_work scheme_of_work_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_pkey PRIMARY KEY (id);


--
-- Name: scheme_of_work scheme_of_work_subject_set_id_term_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_subject_set_id_term_id_key UNIQUE (subject_set_id, term_id);


--
-- Name: scheme_week scheme_week_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_week
    ADD CONSTRAINT scheme_week_pkey PRIMARY KEY (id);


--
-- Name: scheme_week scheme_week_scheme_of_work_id_week_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_week
    ADD CONSTRAINT scheme_week_scheme_of_work_id_week_no_key UNIQUE (scheme_of_work_id, week_no);


--
-- Name: school school_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.school
    ADD CONSTRAINT school_code_key UNIQUE (code);


--
-- Name: school school_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.school
    ADD CONSTRAINT school_pkey PRIMARY KEY (id);


--
-- Name: script_batch script_batch_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_pkey PRIMARY KEY (id);


--
-- Name: set_educator set_educator_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_educator
    ADD CONSTRAINT set_educator_pkey PRIMARY KEY (subject_set_id, staff_id);


--
-- Name: set_enrolment set_enrolment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_enrolment
    ADD CONSTRAINT set_enrolment_pkey PRIMARY KEY (id);


--
-- Name: set_enrolment set_enrolment_subject_set_id_student_id_effective_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_enrolment
    ADD CONSTRAINT set_enrolment_subject_set_id_student_id_effective_from_key UNIQUE (subject_set_id, student_id, effective_from);


--
-- Name: staff_document staff_document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_document
    ADD CONSTRAINT staff_document_pkey PRIMARY KEY (id);


--
-- Name: staff_leave staff_leave_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_leave
    ADD CONSTRAINT staff_leave_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: staff_role_assignment staff_role_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_role_assignment
    ADD CONSTRAINT staff_role_assignment_pkey PRIMARY KEY (id);


--
-- Name: staff staff_school_id_staff_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_school_id_staff_number_key UNIQUE (school_id, staff_number);


--
-- Name: student_document student_document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_document
    ADD CONSTRAINT student_document_pkey PRIMARY KEY (id);


--
-- Name: student_guardian student_guardian_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardian
    ADD CONSTRAINT student_guardian_pkey PRIMARY KEY (student_id, guardian_id);


--
-- Name: student_movement student_movement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_movement
    ADD CONSTRAINT student_movement_pkey PRIMARY KEY (id);


--
-- Name: student student_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT student_pkey PRIMARY KEY (id);


--
-- Name: student student_school_id_admission_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT student_school_id_admission_number_key UNIQUE (school_id, admission_number);


--
-- Name: subject subject_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT subject_pkey PRIMARY KEY (id);


--
-- Name: subject subject_school_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT subject_school_id_code_key UNIQUE (school_id, code);


--
-- Name: subject_set subject_set_academic_year_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_academic_year_id_name_key UNIQUE (academic_year_id, name);


--
-- Name: subject_set subject_set_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_pkey PRIMARY KEY (id);


--
-- Name: syllabus syllabus_academic_year_id_subject_id_grade_level_id_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_academic_year_id_subject_id_grade_level_id_version_key UNIQUE (academic_year_id, subject_id, grade_level_id, version);


--
-- Name: syllabus syllabus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_pkey PRIMARY KEY (id);


--
-- Name: syllabus_unit syllabus_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus_unit
    ADD CONSTRAINT syllabus_unit_pkey PRIMARY KEY (id);


--
-- Name: teaching_resource teaching_resource_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_pkey PRIMARY KEY (id);


--
-- Name: term term_academic_year_id_sequence_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term
    ADD CONSTRAINT term_academic_year_id_sequence_key UNIQUE (academic_year_id, sequence);


--
-- Name: term term_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term
    ADD CONSTRAINT term_pkey PRIMARY KEY (id);


--
-- Name: term_result term_result_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_pkey PRIMARY KEY (term_id, student_id, subject_id);


--
-- Name: thread_participant thread_participant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_participant
    ADD CONSTRAINT thread_participant_pkey PRIMARY KEY (thread_id, person_id);


--
-- Name: timetable_slot timetable_slot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_pkey PRIMARY KEY (id);


--
-- Name: timetable_version timetable_version_academic_year_id_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_version
    ADD CONSTRAINT timetable_version_academic_year_id_version_key UNIQUE (academic_year_id, version);


--
-- Name: timetable_version timetable_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_version
    ADD CONSTRAINT timetable_version_pkey PRIMARY KEY (id);


--
-- Name: visitor_log visitor_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitor_log
    ADD CONSTRAINT visitor_log_pkey PRIMARY KEY (id);


--
-- Name: water_quality_certificate water_quality_certificate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_quality_certificate
    ADD CONSTRAINT water_quality_certificate_pkey PRIMARY KEY (id);


--
-- Name: weekly_plan weekly_plan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan
    ADD CONSTRAINT weekly_plan_pkey PRIMARY KEY (id);


--
-- Name: weekly_plan_row weekly_plan_row_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan_row
    ADD CONSTRAINT weekly_plan_row_pkey PRIMARY KEY (id);


--
-- Name: weekly_plan weekly_plan_subject_set_id_week_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan
    ADD CONSTRAINT weekly_plan_subject_set_id_week_start_key UNIQUE (subject_set_id, week_start);


--
-- Name: absence_note_student_id_covers_from_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX absence_note_student_id_covers_from_idx ON public.absence_note USING btree (student_id, covers_from);


--
-- Name: academic_year_one_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX academic_year_one_active ON public.academic_year USING btree (school_id) WHERE (status = 'active'::public.year_status);


--
-- Name: action_item_owner_person_id_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX action_item_owner_person_id_status_idx ON public.action_item USING btree (owner_person_id, status);


--
-- Name: assessment_academic_year_id_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assessment_academic_year_id_status_idx ON public.assessment USING btree (academic_year_id, status);


--
-- Name: assessment_subject_set_id_term_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assessment_subject_set_id_term_id_idx ON public.assessment USING btree (subject_set_id, term_id);


--
-- Name: asset_school_id_room_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX asset_school_id_room_id_idx ON public.asset USING btree (school_id, room_id);


--
-- Name: attendance_discrepancy_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_discrepancy_open ON public.attendance_discrepancy USING btree (school_id, date) WHERE (resolved_at IS NULL);


--
-- Name: attendance_record_absent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_record_absent ON public.attendance_record USING btree (school_id, status) WHERE (status = 'absent_unauth'::public.attendance_status);


--
-- Name: attendance_record_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_record_student_id_idx ON public.attendance_record USING btree (student_id);


--
-- Name: attendance_session_academic_year_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_session_academic_year_id_date_idx ON public.attendance_session USING btree (academic_year_id, date);


--
-- Name: attendance_summary_school_id_term_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_summary_school_id_term_id_idx ON public.attendance_summary USING btree (school_id, term_id);


--
-- Name: audit_log_school_id_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_school_id_at_idx ON public.audit_log USING btree (school_id, at DESC);


--
-- Name: audit_log_table_name_record_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_table_name_record_id_idx ON public.audit_log USING btree (table_name, record_id);


--
-- Name: calendar_day_academic_year_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX calendar_day_academic_year_id_date_idx ON public.calendar_day USING btree (academic_year_id, date);


--
-- Name: calendar_day_teaching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX calendar_day_teaching ON public.calendar_day USING btree (academic_year_id, date) WHERE (day_type = 'teaching'::public.day_type);


--
-- Name: circular_school_id_issued_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX circular_school_id_issued_on_idx ON public.circular USING btree (school_id, issued_on DESC);


--
-- Name: class_enrolment_class_group_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX class_enrolment_class_group_id_idx ON public.class_enrolment USING btree (class_group_id);


--
-- Name: class_enrolment_one_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX class_enrolment_one_current ON public.class_enrolment USING btree (student_id) WHERE (effective_to IS NULL);


--
-- Name: class_enrolment_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX class_enrolment_student_id_idx ON public.class_enrolment USING btree (student_id);


--
-- Name: class_group_academic_year_id_grade_level_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX class_group_academic_year_id_grade_level_id_idx ON public.class_group USING btree (academic_year_id, grade_level_id);


--
-- Name: correspondence_school_id_dated_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX correspondence_school_id_dated_on_idx ON public.correspondence USING btree (school_id, dated_on DESC);


--
-- Name: disciplinary_case_student_id_opened_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX disciplinary_case_student_id_opened_on_idx ON public.disciplinary_case USING btree (student_id, opened_on DESC);


--
-- Name: exam_eligibility_decision_exam_session_id_decision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exam_eligibility_decision_exam_session_id_decision_idx ON public.exam_eligibility_decision USING btree (exam_session_id, decision);


--
-- Name: exam_paper_exam_session_id_date_starts_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exam_paper_exam_session_id_date_starts_at_idx ON public.exam_paper USING btree (exam_session_id, date, starts_at);


--
-- Name: exam_seat_exam_paper_id_room_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exam_seat_exam_paper_id_room_id_idx ON public.exam_seat USING btree (exam_paper_id, room_id);


--
-- Name: exam_session_academic_year_id_starts_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX exam_session_academic_year_id_starts_on_idx ON public.exam_session USING btree (academic_year_id, starts_on);


--
-- Name: health_record_student_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX health_record_student_id_occurred_at_idx ON public.health_record USING btree (student_id, occurred_at DESC);


--
-- Name: homework_subject_set_id_due_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX homework_subject_set_id_due_on_idx ON public.homework USING btree (subject_set_id, due_on);


--
-- Name: incident_school_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX incident_school_id_occurred_at_idx ON public.incident USING btree (school_id, occurred_at DESC);


--
-- Name: incident_student_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX incident_student_student_id_idx ON public.incident_student USING btree (student_id);


--
-- Name: invigilation_duty_staff_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX invigilation_duty_staff_id_idx ON public.invigilation_duty USING btree (staff_id);


--
-- Name: lesson_plan_subject_set_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lesson_plan_subject_set_id_date_idx ON public.lesson_plan USING btree (subject_set_id, date);


--
-- Name: library_item_school_id_title_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_item_school_id_title_idx ON public.library_item USING btree (school_id, title);


--
-- Name: library_loan_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_loan_student_id_idx ON public.library_loan USING btree (student_id) WHERE (returned_on IS NULL);


--
-- Name: maintenance_request_school_id_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX maintenance_request_school_id_status_idx ON public.maintenance_request USING btree (school_id, status);


--
-- Name: mark_history_mark_id_changed_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mark_history_mark_id_changed_at_idx ON public.mark_history USING btree (mark_id, changed_at DESC);


--
-- Name: mark_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mark_student_id_idx ON public.mark USING btree (student_id);


--
-- Name: meeting_school_id_held_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX meeting_school_id_held_on_idx ON public.meeting USING btree (school_id, held_on DESC);


--
-- Name: merit_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merit_student_id_idx ON public.merit USING btree (student_id);


--
-- Name: message_thread_id_sent_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX message_thread_id_sent_at_idx ON public.message USING btree (thread_id, sent_at);


--
-- Name: notice_school_id_publish_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notice_school_id_publish_at_idx ON public.notice USING btree (school_id, publish_at DESC);


--
-- Name: notification_person_id_scheduled_for_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_person_id_scheduled_for_idx ON public.notification USING btree (person_id, scheduled_for DESC);


--
-- Name: notification_status_scheduled_for_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_status_scheduled_for_idx ON public.notification USING btree (status, scheduled_for) WHERE (status = 'queued'::text);


--
-- Name: occurrence_log_school_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX occurrence_log_school_id_occurred_at_idx ON public.occurrence_log USING btree (school_id, occurred_at DESC);


--
-- Name: one_responsible_party_per_student; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_responsible_party_per_student ON public.student_guardian USING btree (student_id) WHERE is_responsible_party;


--
-- Name: period_attendance_student_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX period_attendance_student_id_date_idx ON public.period_attendance USING btree (student_id, date);


--
-- Name: person_auth_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX person_auth_user_id_idx ON public.person USING btree (auth_user_id);


--
-- Name: person_email_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX person_email_ci ON public.person USING btree (school_id, lower(email)) WHERE (email IS NOT NULL);


--
-- Name: person_name_search; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX person_name_search ON public.person USING gin (to_tsvector('simple'::regconfig, ((COALESCE(first_name, ''::text) || ' '::text) || COALESCE(last_name, ''::text))));


--
-- Name: person_school_id_person_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX person_school_id_person_type_idx ON public.person USING btree (school_id, person_type);


--
-- Name: public_holiday_country_year_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX public_holiday_country_year_idx ON public.public_holiday USING btree (country, year);


--
-- Name: set_enrolment_current; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX set_enrolment_current ON public.set_enrolment USING btree (subject_set_id) WHERE (effective_to IS NULL);


--
-- Name: set_enrolment_student_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX set_enrolment_student_id_idx ON public.set_enrolment USING btree (student_id);


--
-- Name: staff_document_staff_id_kind_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_document_staff_id_kind_idx ON public.staff_document USING btree (staff_id, kind);


--
-- Name: staff_leave_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_leave_dates ON public.staff_leave USING btree (staff_id, starts_on, ends_on);


--
-- Name: staff_role_assignment_academic_year_id_role_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_role_assignment_academic_year_id_role_code_idx ON public.staff_role_assignment USING btree (academic_year_id, role_code);


--
-- Name: staff_role_assignment_staff_id_academic_year_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_role_assignment_staff_id_academic_year_id_idx ON public.staff_role_assignment USING btree (staff_id, academic_year_id);


--
-- Name: student_document_student_id_kind_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_document_student_id_kind_idx ON public.student_document USING btree (student_id, kind);


--
-- Name: student_guardian_guardian_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_guardian_guardian_id_idx ON public.student_guardian USING btree (guardian_id);


--
-- Name: student_movement_student_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_movement_student_id_date_idx ON public.student_movement USING btree (student_id, date);


--
-- Name: subject_set_academic_year_id_subject_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subject_set_academic_year_id_subject_id_idx ON public.subject_set USING btree (academic_year_id, subject_id);


--
-- Name: syllabus_unit_syllabus_id_sort_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX syllabus_unit_syllabus_id_sort_order_idx ON public.syllabus_unit USING btree (syllabus_id, sort_order);


--
-- Name: term_academic_year_id_starts_on_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX term_academic_year_id_starts_on_idx ON public.term USING btree (academic_year_id, starts_on);


--
-- Name: term_result_school_id_term_id_subject_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX term_result_school_id_term_id_subject_id_idx ON public.term_result USING btree (school_id, term_id, subject_id);


--
-- Name: timetable_slot_subject_set_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timetable_slot_subject_set_id_idx ON public.timetable_slot USING btree (subject_set_id);


--
-- Name: tt_no_room_clash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tt_no_room_clash ON public.timetable_slot USING btree (timetable_version_id, cycle_day, period_id, room_id) WHERE (room_id IS NOT NULL);


--
-- Name: tt_no_staff_clash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tt_no_staff_clash ON public.timetable_slot USING btree (timetable_version_id, cycle_day, period_id, staff_id) WHERE (staff_id IS NOT NULL);


--
-- Name: visitor_log_school_id_signed_in_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX visitor_log_school_id_signed_in_at_idx ON public.visitor_log USING btree (school_id, signed_in_at DESC);


--
-- Name: weekly_plan_row_weekly_plan_id_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX weekly_plan_row_weekly_plan_id_date_idx ON public.weekly_plan_row USING btree (weekly_plan_id, date);


--
-- Name: academic_year academic_year_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER academic_year_touch BEFORE UPDATE ON public.academic_year FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: attendance_record attendance_absence_alert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_absence_alert AFTER INSERT OR UPDATE OF status ON public.attendance_record FOR EACH ROW EXECUTE FUNCTION app.queue_absence_alert();


--
-- Name: attendance_record attendance_summary_maintain; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_summary_maintain AFTER INSERT OR DELETE OR UPDATE OF status ON public.attendance_record FOR EACH ROW EXECUTE FUNCTION app.attendance_summary_trigger();


--
-- Name: assessment audit_assessment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_assessment AFTER INSERT OR DELETE OR UPDATE ON public.assessment FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: attendance_record audit_attendance_record; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_attendance_record AFTER INSERT OR DELETE OR UPDATE ON public.attendance_record FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: attendance_discrepancy audit_discrepancy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_discrepancy AFTER INSERT OR DELETE OR UPDATE ON public.attendance_discrepancy FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: exam_eligibility_decision audit_eligibility; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_eligibility AFTER INSERT OR DELETE OR UPDATE ON public.exam_eligibility_decision FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: incident audit_incident; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_incident AFTER INSERT OR DELETE OR UPDATE ON public.incident FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: staff_role_assignment audit_role_assignment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_role_assignment AFTER INSERT OR DELETE OR UPDATE ON public.staff_role_assignment FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: sanction audit_sanction; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_sanction AFTER INSERT OR DELETE OR UPDATE ON public.sanction FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: school audit_school; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_school AFTER INSERT OR DELETE OR UPDATE ON public.school FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: student audit_student; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_student AFTER INSERT OR DELETE OR UPDATE ON public.student FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: student_document audit_student_document; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_student_document AFTER INSERT OR DELETE OR UPDATE ON public.student_document FOR EACH ROW EXECUTE FUNCTION app.audit_row();


--
-- Name: leave_of_absence leave_of_absence_route; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER leave_of_absence_route BEFORE INSERT OR UPDATE OF starts_on, ends_on ON public.leave_of_absence FOR EACH ROW EXECUTE FUNCTION app.leave_approver_level();


--
-- Name: mark mark_history_maintain; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mark_history_maintain AFTER UPDATE ON public.mark FOR EACH ROW EXECUTE FUNCTION app.record_mark_change();


--
-- Name: period_attendance period_attendance_discrepancy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER period_attendance_discrepancy AFTER INSERT OR UPDATE OF status ON public.period_attendance FOR EACH ROW EXECUTE FUNCTION app.detect_attendance_discrepancy();


--
-- Name: person person_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER person_touch BEFORE UPDATE ON public.person FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: school school_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER school_touch BEFORE UPDATE ON public.school FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: set_enrolment set_enrolment_option_blocks; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_enrolment_option_blocks AFTER INSERT OR UPDATE OF subject_set_id ON public.set_enrolment FOR EACH ROW EXECUTE FUNCTION app.check_option_blocks();


--
-- Name: timetable_slot timetable_slot_student_clash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER timetable_slot_student_clash BEFORE INSERT OR UPDATE OF cycle_day, period_id, subject_set_id ON public.timetable_slot FOR EACH ROW EXECUTE FUNCTION app.check_timetable_student_clash();


--
-- Name: absence_note absence_note_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absence_note
    ADD CONSTRAINT absence_note_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.staff(id);


--
-- Name: absence_note absence_note_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absence_note
    ADD CONSTRAINT absence_note_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: absence_note absence_note_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absence_note
    ADD CONSTRAINT absence_note_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: absence_note absence_note_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absence_note
    ADD CONSTRAINT absence_note_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.person(id);


--
-- Name: academic_year academic_year_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.academic_year
    ADD CONSTRAINT academic_year_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: action_item action_item_meeting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_item
    ADD CONSTRAINT action_item_meeting_id_fkey FOREIGN KEY (meeting_id) REFERENCES public.meeting(id) ON DELETE SET NULL;


--
-- Name: action_item action_item_owner_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_item
    ADD CONSTRAINT action_item_owner_person_id_fkey FOREIGN KEY (owner_person_id) REFERENCES public.person(id);


--
-- Name: action_item action_item_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_item
    ADD CONSTRAINT action_item_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: admission_checklist admission_checklist_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_checklist
    ADD CONSTRAINT admission_checklist_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: admission_checklist admission_checklist_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admission_checklist
    ADD CONSTRAINT admission_checklist_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: assessment assessment_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: assessment assessment_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: assessment assessment_grading_scale_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_grading_scale_id_fkey FOREIGN KEY (grading_scale_id) REFERENCES public.grading_scale(id);


--
-- Name: assessment assessment_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.staff(id);


--
-- Name: assessment assessment_published_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.staff(id);


--
-- Name: assessment assessment_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: assessment assessment_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: assessment assessment_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: assessment assessment_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.staff(id);


--
-- Name: assessment assessment_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment
    ADD CONSTRAINT assessment_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE SET NULL;


--
-- Name: asset asset_custodian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset
    ADD CONSTRAINT asset_custodian_id_fkey FOREIGN KEY (custodian_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: asset asset_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset
    ADD CONSTRAINT asset_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id) ON DELETE SET NULL;


--
-- Name: asset asset_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset
    ADD CONSTRAINT asset_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: asset_verification asset_verification_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_verification
    ADD CONSTRAINT asset_verification_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.asset(id) ON DELETE CASCADE;


--
-- Name: asset_verification asset_verification_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_verification
    ADD CONSTRAINT asset_verification_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: asset_verification asset_verification_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_verification
    ADD CONSTRAINT asset_verification_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.staff(id);


--
-- Name: attendance_discrepancy attendance_discrepancy_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.staff(id);


--
-- Name: attendance_discrepancy attendance_discrepancy_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: attendance_discrepancy attendance_discrepancy_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: attendance_discrepancy attendance_discrepancy_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE SET NULL;


--
-- Name: attendance_discrepancy attendance_discrepancy_timetable_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_discrepancy
    ADD CONSTRAINT attendance_discrepancy_timetable_slot_id_fkey FOREIGN KEY (timetable_slot_id) REFERENCES public.timetable_slot(id) ON DELETE SET NULL;


--
-- Name: attendance_record attendance_record_amended_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_amended_by_fkey FOREIGN KEY (amended_by) REFERENCES public.staff(id);


--
-- Name: attendance_record attendance_record_attendance_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_attendance_session_id_fkey FOREIGN KEY (attendance_session_id) REFERENCES public.attendance_session(id) ON DELETE CASCADE;


--
-- Name: attendance_record attendance_record_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.staff(id);


--
-- Name: attendance_record attendance_record_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: attendance_record attendance_record_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_record
    ADD CONSTRAINT attendance_record_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: attendance_session attendance_session_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: attendance_session attendance_session_class_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_class_group_id_fkey FOREIGN KEY (class_group_id) REFERENCES public.class_group(id) ON DELETE CASCADE;


--
-- Name: attendance_session attendance_session_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: attendance_session attendance_session_taken_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_session
    ADD CONSTRAINT attendance_session_taken_by_fkey FOREIGN KEY (taken_by) REFERENCES public.staff(id);


--
-- Name: attendance_summary attendance_summary_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_summary
    ADD CONSTRAINT attendance_summary_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: attendance_summary attendance_summary_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_summary
    ADD CONSTRAINT attendance_summary_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: attendance_summary attendance_summary_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_summary
    ADD CONSTRAINT attendance_summary_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: attendance_summary attendance_summary_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_summary
    ADD CONSTRAINT attendance_summary_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE CASCADE;


--
-- Name: calendar_day calendar_day_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_day
    ADD CONSTRAINT calendar_day_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: calendar_day calendar_day_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_day
    ADD CONSTRAINT calendar_day_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: calendar_day calendar_day_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_day
    ADD CONSTRAINT calendar_day_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE SET NULL;


--
-- Name: circular_ack circular_ack_circular_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.circular_ack
    ADD CONSTRAINT circular_ack_circular_id_fkey FOREIGN KEY (circular_id) REFERENCES public.circular(id) ON DELETE CASCADE;


--
-- Name: circular_ack circular_ack_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.circular_ack
    ADD CONSTRAINT circular_ack_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: circular circular_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.circular
    ADD CONSTRAINT circular_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: class_enrolment class_enrolment_class_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_enrolment
    ADD CONSTRAINT class_enrolment_class_group_id_fkey FOREIGN KEY (class_group_id) REFERENCES public.class_group(id) ON DELETE CASCADE;


--
-- Name: class_enrolment class_enrolment_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_enrolment
    ADD CONSTRAINT class_enrolment_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: class_enrolment class_enrolment_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_enrolment
    ADD CONSTRAINT class_enrolment_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: class_group class_group_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: class_group class_group_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: class_group class_group_home_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_home_room_id_fkey FOREIGN KEY (home_room_id) REFERENCES public.room(id) ON DELETE SET NULL;


--
-- Name: class_group class_group_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.class_group
    ADD CONSTRAINT class_group_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: clearance_item clearance_item_cleared_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clearance_item
    ADD CONSTRAINT clearance_item_cleared_by_fkey FOREIGN KEY (cleared_by) REFERENCES public.staff(id);


--
-- Name: clearance_item clearance_item_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clearance_item
    ADD CONSTRAINT clearance_item_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: clearance_item clearance_item_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clearance_item
    ADD CONSTRAINT clearance_item_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: committee committee_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee
    ADD CONSTRAINT committee_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: committee_member committee_member_committee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_member
    ADD CONSTRAINT committee_member_committee_id_fkey FOREIGN KEY (committee_id) REFERENCES public.committee(id) ON DELETE CASCADE;


--
-- Name: committee_member committee_member_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee_member
    ADD CONSTRAINT committee_member_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: committee committee_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.committee
    ADD CONSTRAINT committee_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: confidential_note confidential_note_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confidential_note
    ADD CONSTRAINT confidential_note_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.person(id);


--
-- Name: confidential_note confidential_note_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confidential_note
    ADD CONSTRAINT confidential_note_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: confidential_note confidential_note_subject_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confidential_note
    ADD CONSTRAINT confidential_note_subject_person_id_fkey FOREIGN KEY (subject_person_id) REFERENCES public.person(id);


--
-- Name: correspondence correspondence_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correspondence
    ADD CONSTRAINT correspondence_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.staff(id);


--
-- Name: correspondence correspondence_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.correspondence
    ADD CONSTRAINT correspondence_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: department department_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: disciplinary_case disciplinary_case_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinary_case
    ADD CONSTRAINT disciplinary_case_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: disciplinary_case disciplinary_case_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinary_case
    ADD CONSTRAINT disciplinary_case_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: exam_arrangement exam_arrangement_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: exam_arrangement exam_arrangement_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.staff(id);


--
-- Name: exam_arrangement exam_arrangement_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: exam_arrangement exam_arrangement_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_arrangement
    ADD CONSTRAINT exam_arrangement_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: exam_eligibility_decision exam_eligibility_decision_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.staff(id);


--
-- Name: exam_eligibility_decision exam_eligibility_decision_exam_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_exam_session_id_fkey FOREIGN KEY (exam_session_id) REFERENCES public.exam_session(id) ON DELETE CASCADE;


--
-- Name: exam_eligibility_decision exam_eligibility_decision_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: exam_eligibility_decision exam_eligibility_decision_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_eligibility_decision
    ADD CONSTRAINT exam_eligibility_decision_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: exam_paper exam_paper_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id) ON DELETE SET NULL;


--
-- Name: exam_paper exam_paper_exam_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_exam_session_id_fkey FOREIGN KEY (exam_session_id) REFERENCES public.exam_session(id) ON DELETE CASCADE;


--
-- Name: exam_paper exam_paper_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: exam_paper exam_paper_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: exam_paper exam_paper_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_paper
    ADD CONSTRAINT exam_paper_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: exam_seat exam_seat_exam_paper_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_exam_paper_id_fkey FOREIGN KEY (exam_paper_id) REFERENCES public.exam_paper(id) ON DELETE CASCADE;


--
-- Name: exam_seat exam_seat_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id);


--
-- Name: exam_seat exam_seat_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: exam_seat exam_seat_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_seat
    ADD CONSTRAINT exam_seat_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: exam_session exam_session_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_session
    ADD CONSTRAINT exam_session_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: exam_session exam_session_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_session
    ADD CONSTRAINT exam_session_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: exam_session exam_session_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_session
    ADD CONSTRAINT exam_session_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE SET NULL;


--
-- Name: grade_level grade_level_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grade_level
    ADD CONSTRAINT grade_level_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: grading_band grading_band_grading_scale_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_band
    ADD CONSTRAINT grading_band_grading_scale_id_fkey FOREIGN KEY (grading_scale_id) REFERENCES public.grading_scale(id) ON DELETE CASCADE;


--
-- Name: grading_scale grading_scale_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_scale
    ADD CONSTRAINT grading_scale_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: grading_scale grading_scale_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grading_scale
    ADD CONSTRAINT grading_scale_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: guardian guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardian
    ADD CONSTRAINT guardian_id_fkey FOREIGN KEY (id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: health_record health_record_attended_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.health_record
    ADD CONSTRAINT health_record_attended_by_fkey FOREIGN KEY (attended_by) REFERENCES public.staff(id);


--
-- Name: health_record health_record_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.health_record
    ADD CONSTRAINT health_record_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: health_record health_record_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.health_record
    ADD CONSTRAINT health_record_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: homework homework_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework
    ADD CONSTRAINT homework_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: homework homework_set_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework
    ADD CONSTRAINT homework_set_by_fkey FOREIGN KEY (set_by) REFERENCES public.staff(id);


--
-- Name: homework homework_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework
    ADD CONSTRAINT homework_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: homework_submission homework_submission_homework_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework_submission
    ADD CONSTRAINT homework_submission_homework_id_fkey FOREIGN KEY (homework_id) REFERENCES public.homework(id) ON DELETE CASCADE;


--
-- Name: homework_submission homework_submission_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework_submission
    ADD CONSTRAINT homework_submission_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: homework_submission homework_submission_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.homework_submission
    ADD CONSTRAINT homework_submission_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: incident incident_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident
    ADD CONSTRAINT incident_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: incident incident_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident
    ADD CONSTRAINT incident_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.staff(id);


--
-- Name: incident incident_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident
    ADD CONSTRAINT incident_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: incident_student incident_student_incident_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident_student
    ADD CONSTRAINT incident_student_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES public.incident(id) ON DELETE CASCADE;


--
-- Name: incident_student incident_student_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incident_student
    ADD CONSTRAINT incident_student_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: invigilation_duty invigilation_duty_exam_paper_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_exam_paper_id_fkey FOREIGN KEY (exam_paper_id) REFERENCES public.exam_paper(id) ON DELETE CASCADE;


--
-- Name: invigilation_duty invigilation_duty_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id);


--
-- Name: invigilation_duty invigilation_duty_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: invigilation_duty invigilation_duty_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id);


--
-- Name: invigilation_duty invigilation_duty_swap_with_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invigilation_duty
    ADD CONSTRAINT invigilation_duty_swap_with_fkey FOREIGN KEY (swap_with) REFERENCES public.staff(id);


--
-- Name: leave_of_absence leave_of_absence_extension_of_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_of_absence
    ADD CONSTRAINT leave_of_absence_extension_of_fkey FOREIGN KEY (extension_of) REFERENCES public.leave_of_absence(id);


--
-- Name: leave_of_absence leave_of_absence_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_of_absence
    ADD CONSTRAINT leave_of_absence_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: leave_of_absence leave_of_absence_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_of_absence
    ADD CONSTRAINT leave_of_absence_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: leaving_certificate leaving_certificate_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaving_certificate
    ADD CONSTRAINT leaving_certificate_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.staff(id);


--
-- Name: leaving_certificate leaving_certificate_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaving_certificate
    ADD CONSTRAINT leaving_certificate_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: leaving_certificate leaving_certificate_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaving_certificate
    ADD CONSTRAINT leaving_certificate_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: lesson_plan lesson_plan_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_plan
    ADD CONSTRAINT lesson_plan_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: lesson_plan lesson_plan_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_plan
    ADD CONSTRAINT lesson_plan_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id);


--
-- Name: lesson_plan lesson_plan_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_plan
    ADD CONSTRAINT lesson_plan_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: lesson_plan lesson_plan_timetable_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_plan
    ADD CONSTRAINT lesson_plan_timetable_slot_id_fkey FOREIGN KEY (timetable_slot_id) REFERENCES public.timetable_slot(id) ON DELETE SET NULL;


--
-- Name: lesson_substitution lesson_substitution_absent_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_absent_staff_id_fkey FOREIGN KEY (absent_staff_id) REFERENCES public.staff(id);


--
-- Name: lesson_substitution lesson_substitution_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.staff(id);


--
-- Name: lesson_substitution lesson_substitution_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: lesson_substitution lesson_substitution_substitute_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_substitute_staff_id_fkey FOREIGN KEY (substitute_staff_id) REFERENCES public.staff(id);


--
-- Name: lesson_substitution lesson_substitution_timetable_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_substitution
    ADD CONSTRAINT lesson_substitution_timetable_slot_id_fkey FOREIGN KEY (timetable_slot_id) REFERENCES public.timetable_slot(id) ON DELETE CASCADE;


--
-- Name: library_item library_item_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_item
    ADD CONSTRAINT library_item_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: library_loan library_loan_library_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_loan
    ADD CONSTRAINT library_loan_library_item_id_fkey FOREIGN KEY (library_item_id) REFERENCES public.library_item(id) ON DELETE CASCADE;


--
-- Name: library_loan library_loan_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_loan
    ADD CONSTRAINT library_loan_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: library_loan library_loan_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_loan
    ADD CONSTRAINT library_loan_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: library_loan library_loan_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library_loan
    ADD CONSTRAINT library_loan_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: maintenance_request maintenance_request_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_request
    ADD CONSTRAINT maintenance_request_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.asset(id) ON DELETE SET NULL;


--
-- Name: maintenance_request maintenance_request_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_request
    ADD CONSTRAINT maintenance_request_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.person(id);


--
-- Name: maintenance_request maintenance_request_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_request
    ADD CONSTRAINT maintenance_request_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id) ON DELETE SET NULL;


--
-- Name: maintenance_request maintenance_request_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_request
    ADD CONSTRAINT maintenance_request_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: mark mark_assessment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.assessment(id) ON DELETE CASCADE;


--
-- Name: mark mark_entered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.staff(id);


--
-- Name: mark mark_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: mark mark_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mark
    ADD CONSTRAINT mark_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: meeting_attendance meeting_attendance_meeting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendance
    ADD CONSTRAINT meeting_attendance_meeting_id_fkey FOREIGN KEY (meeting_id) REFERENCES public.meeting(id) ON DELETE CASCADE;


--
-- Name: meeting_attendance meeting_attendance_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendance
    ADD CONSTRAINT meeting_attendance_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: meeting meeting_chaired_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_chaired_by_fkey FOREIGN KEY (chaired_by) REFERENCES public.person(id);


--
-- Name: meeting meeting_committee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_committee_id_fkey FOREIGN KEY (committee_id) REFERENCES public.committee(id) ON DELETE SET NULL;


--
-- Name: meeting meeting_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE SET NULL;


--
-- Name: meeting meeting_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting
    ADD CONSTRAINT meeting_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: merit merit_awarded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merit
    ADD CONSTRAINT merit_awarded_by_fkey FOREIGN KEY (awarded_by) REFERENCES public.staff(id);


--
-- Name: merit merit_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merit
    ADD CONSTRAINT merit_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: merit merit_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merit
    ADD CONSTRAINT merit_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: message message_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: message message_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.person(id);


--
-- Name: message_thread message_thread_about_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_thread
    ADD CONSTRAINT message_thread_about_student_id_fkey FOREIGN KEY (about_student_id) REFERENCES public.student(id) ON DELETE SET NULL;


--
-- Name: message_thread message_thread_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_thread
    ADD CONSTRAINT message_thread_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.person(id);


--
-- Name: message message_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.message_thread(id) ON DELETE CASCADE;


--
-- Name: message_thread message_thread_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_thread
    ADD CONSTRAINT message_thread_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: notice notice_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice
    ADD CONSTRAINT notice_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.person(id);


--
-- Name: notice_read notice_read_notice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_read
    ADD CONSTRAINT notice_read_notice_id_fkey FOREIGN KEY (notice_id) REFERENCES public.notice(id) ON DELETE CASCADE;


--
-- Name: notice_read notice_read_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice_read
    ADD CONSTRAINT notice_read_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: notice notice_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notice
    ADD CONSTRAINT notice_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: notification notification_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: notification notification_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: occurrence_log occurrence_log_corrects_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occurrence_log
    ADD CONSTRAINT occurrence_log_corrects_entry_id_fkey FOREIGN KEY (corrects_entry_id) REFERENCES public.occurrence_log(id);


--
-- Name: occurrence_log occurrence_log_entered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occurrence_log
    ADD CONSTRAINT occurrence_log_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES public.person(id);


--
-- Name: occurrence_log occurrence_log_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occurrence_log
    ADD CONSTRAINT occurrence_log_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: option_block option_block_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block
    ADD CONSTRAINT option_block_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: option_block option_block_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block
    ADD CONSTRAINT option_block_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: option_block option_block_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block
    ADD CONSTRAINT option_block_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: option_block_subject option_block_subject_option_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block_subject
    ADD CONSTRAINT option_block_subject_option_block_id_fkey FOREIGN KEY (option_block_id) REFERENCES public.option_block(id) ON DELETE CASCADE;


--
-- Name: option_block_subject option_block_subject_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.option_block_subject
    ADD CONSTRAINT option_block_subject_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id) ON DELETE CASCADE;


--
-- Name: pastoral_case pastoral_case_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_case
    ADD CONSTRAINT pastoral_case_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: pastoral_case pastoral_case_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_case
    ADD CONSTRAINT pastoral_case_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: pastoral_note pastoral_note_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_note
    ADD CONSTRAINT pastoral_note_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.person(id);


--
-- Name: pastoral_note pastoral_note_pastoral_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_note
    ADD CONSTRAINT pastoral_note_pastoral_case_id_fkey FOREIGN KEY (pastoral_case_id) REFERENCES public.pastoral_case(id) ON DELETE CASCADE;


--
-- Name: pastoral_note pastoral_note_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pastoral_note
    ADD CONSTRAINT pastoral_note_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: period_attendance period_attendance_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.staff(id);


--
-- Name: period_attendance period_attendance_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: period_attendance period_attendance_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: period_attendance period_attendance_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: period_attendance period_attendance_timetable_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_attendance
    ADD CONSTRAINT period_attendance_timetable_slot_id_fkey FOREIGN KEY (timetable_slot_id) REFERENCES public.timetable_slot(id) ON DELETE SET NULL;


--
-- Name: period_definition period_definition_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_definition
    ADD CONSTRAINT period_definition_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: period_definition period_definition_timetable_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_definition
    ADD CONSTRAINT period_definition_timetable_version_id_fkey FOREIGN KEY (timetable_version_id) REFERENCES public.timetable_version(id) ON DELETE CASCADE;


--
-- Name: person person_auth_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: person person_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: policy_acknowledgement policy_acknowledgement_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_acknowledgement
    ADD CONSTRAINT policy_acknowledgement_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: policy_acknowledgement policy_acknowledgement_policy_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_acknowledgement
    ADD CONSTRAINT policy_acknowledgement_policy_document_id_fkey FOREIGN KEY (policy_document_id) REFERENCES public.policy_document(id) ON DELETE CASCADE;


--
-- Name: policy_document policy_document_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policy_document
    ADD CONSTRAINT policy_document_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: report_card report_card_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: report_card report_card_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: report_card report_card_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE CASCADE;


--
-- Name: role_capability role_capability_capability_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capability
    ADD CONSTRAINT role_capability_capability_code_fkey FOREIGN KEY (capability_code) REFERENCES public.capability(code) ON DELETE CASCADE;


--
-- Name: role_capability role_capability_role_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capability
    ADD CONSTRAINT role_capability_role_code_fkey FOREIGN KEY (role_code) REFERENCES public.role(code) ON DELETE CASCADE;


--
-- Name: room room_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT room_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: sanction sanction_disciplinary_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanction
    ADD CONSTRAINT sanction_disciplinary_case_id_fkey FOREIGN KEY (disciplinary_case_id) REFERENCES public.disciplinary_case(id) ON DELETE CASCADE;


--
-- Name: sanction sanction_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanction
    ADD CONSTRAINT sanction_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.staff(id);


--
-- Name: sanction sanction_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanction
    ADD CONSTRAINT sanction_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: sanction sanction_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanction
    ADD CONSTRAINT sanction_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: scheme_of_work scheme_of_work_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: scheme_of_work scheme_of_work_hod_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_hod_reviewed_by_fkey FOREIGN KEY (hod_reviewed_by) REFERENCES public.staff(id);


--
-- Name: scheme_of_work scheme_of_work_rector_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_rector_approved_by_fkey FOREIGN KEY (rector_approved_by) REFERENCES public.staff(id);


--
-- Name: scheme_of_work scheme_of_work_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: scheme_of_work scheme_of_work_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id);


--
-- Name: scheme_of_work scheme_of_work_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: scheme_of_work scheme_of_work_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_of_work
    ADD CONSTRAINT scheme_of_work_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE CASCADE;


--
-- Name: scheme_week scheme_week_scheme_of_work_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_week
    ADD CONSTRAINT scheme_week_scheme_of_work_id_fkey FOREIGN KEY (scheme_of_work_id) REFERENCES public.scheme_of_work(id) ON DELETE CASCADE;


--
-- Name: scheme_week scheme_week_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_week
    ADD CONSTRAINT scheme_week_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: scheme_week scheme_week_syllabus_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheme_week
    ADD CONSTRAINT scheme_week_syllabus_unit_id_fkey FOREIGN KEY (syllabus_unit_id) REFERENCES public.syllabus_unit(id) ON DELETE SET NULL;


--
-- Name: script_batch script_batch_collected_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_collected_by_fkey FOREIGN KEY (collected_by) REFERENCES public.staff(id);


--
-- Name: script_batch script_batch_exam_paper_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_exam_paper_id_fkey FOREIGN KEY (exam_paper_id) REFERENCES public.exam_paper(id) ON DELETE CASCADE;


--
-- Name: script_batch script_batch_marker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_marker_id_fkey FOREIGN KEY (marker_id) REFERENCES public.staff(id);


--
-- Name: script_batch script_batch_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id);


--
-- Name: script_batch script_batch_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.script_batch
    ADD CONSTRAINT script_batch_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: set_educator set_educator_staff_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_educator
    ADD CONSTRAINT set_educator_staff_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: set_educator set_educator_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_educator
    ADD CONSTRAINT set_educator_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: set_enrolment set_enrolment_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_enrolment
    ADD CONSTRAINT set_enrolment_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: set_enrolment set_enrolment_student_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_enrolment
    ADD CONSTRAINT set_enrolment_student_fk FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: set_enrolment set_enrolment_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.set_enrolment
    ADD CONSTRAINT set_enrolment_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: staff staff_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE SET NULL;


--
-- Name: staff_document staff_document_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_document
    ADD CONSTRAINT staff_document_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: staff_document staff_document_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_document
    ADD CONSTRAINT staff_document_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff_document staff_document_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_document
    ADD CONSTRAINT staff_document_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.person(id);


--
-- Name: staff staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_id_fkey FOREIGN KEY (id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: staff_leave staff_leave_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_leave
    ADD CONSTRAINT staff_leave_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.staff(id);


--
-- Name: staff_leave staff_leave_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_leave
    ADD CONSTRAINT staff_leave_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: staff_leave staff_leave_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_leave
    ADD CONSTRAINT staff_leave_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff_role_assignment staff_role_assignment_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_role_assignment
    ADD CONSTRAINT staff_role_assignment_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: staff_role_assignment staff_role_assignment_role_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_role_assignment
    ADD CONSTRAINT staff_role_assignment_role_code_fkey FOREIGN KEY (role_code) REFERENCES public.role(code);


--
-- Name: staff_role_assignment staff_role_assignment_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_role_assignment
    ADD CONSTRAINT staff_role_assignment_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: staff_role_assignment staff_role_assignment_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_role_assignment
    ADD CONSTRAINT staff_role_assignment_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff staff_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: student_document student_document_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_document
    ADD CONSTRAINT student_document_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: student_document student_document_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_document
    ADD CONSTRAINT student_document_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: student_document student_document_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_document
    ADD CONSTRAINT student_document_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.person(id);


--
-- Name: student_document student_document_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_document
    ADD CONSTRAINT student_document_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.staff(id);


--
-- Name: student_guardian student_guardian_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardian
    ADD CONSTRAINT student_guardian_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardian(id) ON DELETE CASCADE;


--
-- Name: student_guardian student_guardian_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardian
    ADD CONSTRAINT student_guardian_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: student student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT student_id_fkey FOREIGN KEY (id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: student_movement student_movement_authorised_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_movement
    ADD CONSTRAINT student_movement_authorised_by_fkey FOREIGN KEY (authorised_by) REFERENCES public.staff(id);


--
-- Name: student_movement student_movement_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_movement
    ADD CONSTRAINT student_movement_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: student_movement student_movement_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_movement
    ADD CONSTRAINT student_movement_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: student student_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT student_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: subject subject_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT subject_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE SET NULL;


--
-- Name: subject subject_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT subject_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: subject_set subject_set_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: subject_set subject_set_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: subject_set subject_set_preferred_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_preferred_room_id_fkey FOREIGN KEY (preferred_room_id) REFERENCES public.room(id) ON DELETE SET NULL;


--
-- Name: subject_set subject_set_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: subject_set subject_set_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_set
    ADD CONSTRAINT subject_set_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: syllabus syllabus_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: syllabus syllabus_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: syllabus syllabus_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: syllabus syllabus_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus
    ADD CONSTRAINT syllabus_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: syllabus_unit syllabus_unit_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus_unit
    ADD CONSTRAINT syllabus_unit_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.syllabus_unit(id) ON DELETE CASCADE;


--
-- Name: syllabus_unit syllabus_unit_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus_unit
    ADD CONSTRAINT syllabus_unit_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: syllabus_unit syllabus_unit_syllabus_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus_unit
    ADD CONSTRAINT syllabus_unit_syllabus_id_fkey FOREIGN KEY (syllabus_id) REFERENCES public.syllabus(id) ON DELETE CASCADE;


--
-- Name: syllabus_unit syllabus_unit_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.syllabus_unit
    ADD CONSTRAINT syllabus_unit_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE SET NULL;


--
-- Name: teaching_resource teaching_resource_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE SET NULL;


--
-- Name: teaching_resource teaching_resource_grade_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_grade_level_id_fkey FOREIGN KEY (grade_level_id) REFERENCES public.grade_level(id);


--
-- Name: teaching_resource teaching_resource_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: teaching_resource teaching_resource_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: teaching_resource teaching_resource_syllabus_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_syllabus_unit_id_fkey FOREIGN KEY (syllabus_unit_id) REFERENCES public.syllabus_unit(id) ON DELETE SET NULL;


--
-- Name: teaching_resource teaching_resource_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teaching_resource
    ADD CONSTRAINT teaching_resource_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.staff(id);


--
-- Name: term term_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term
    ADD CONSTRAINT term_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: term_result term_result_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: term_result term_result_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.student(id) ON DELETE CASCADE;


--
-- Name: term_result term_result_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subject(id);


--
-- Name: term_result term_result_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id);


--
-- Name: term_result term_result_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_result
    ADD CONSTRAINT term_result_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.term(id) ON DELETE CASCADE;


--
-- Name: term term_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term
    ADD CONSTRAINT term_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: thread_participant thread_participant_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_participant
    ADD CONSTRAINT thread_participant_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;


--
-- Name: thread_participant thread_participant_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_participant
    ADD CONSTRAINT thread_participant_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.message_thread(id) ON DELETE CASCADE;


--
-- Name: timetable_slot timetable_slot_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.period_definition(id) ON DELETE CASCADE;


--
-- Name: timetable_slot timetable_slot_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.room(id) ON DELETE SET NULL;


--
-- Name: timetable_slot timetable_slot_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: timetable_slot timetable_slot_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: timetable_slot timetable_slot_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: timetable_slot timetable_slot_timetable_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_slot
    ADD CONSTRAINT timetable_slot_timetable_version_id_fkey FOREIGN KEY (timetable_version_id) REFERENCES public.timetable_version(id) ON DELETE CASCADE;


--
-- Name: timetable_version timetable_version_academic_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_version
    ADD CONSTRAINT timetable_version_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES public.academic_year(id) ON DELETE CASCADE;


--
-- Name: timetable_version timetable_version_published_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_version
    ADD CONSTRAINT timetable_version_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.staff(id);


--
-- Name: timetable_version timetable_version_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timetable_version
    ADD CONSTRAINT timetable_version_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: visitor_log visitor_log_host_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitor_log
    ADD CONSTRAINT visitor_log_host_staff_id_fkey FOREIGN KEY (host_staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: visitor_log visitor_log_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visitor_log
    ADD CONSTRAINT visitor_log_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: water_quality_certificate water_quality_certificate_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_quality_certificate
    ADD CONSTRAINT water_quality_certificate_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: weekly_plan_row weekly_plan_row_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan_row
    ADD CONSTRAINT weekly_plan_row_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: weekly_plan_row weekly_plan_row_timetable_slot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan_row
    ADD CONSTRAINT weekly_plan_row_timetable_slot_id_fkey FOREIGN KEY (timetable_slot_id) REFERENCES public.timetable_slot(id) ON DELETE SET NULL;


--
-- Name: weekly_plan_row weekly_plan_row_weekly_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan_row
    ADD CONSTRAINT weekly_plan_row_weekly_plan_id_fkey FOREIGN KEY (weekly_plan_id) REFERENCES public.weekly_plan(id) ON DELETE CASCADE;


--
-- Name: weekly_plan weekly_plan_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan
    ADD CONSTRAINT weekly_plan_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.school(id) ON DELETE CASCADE;


--
-- Name: weekly_plan weekly_plan_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan
    ADD CONSTRAINT weekly_plan_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id);


--
-- Name: weekly_plan weekly_plan_subject_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_plan
    ADD CONSTRAINT weekly_plan_subject_set_id_fkey FOREIGN KEY (subject_set_id) REFERENCES public.subject_set(id) ON DELETE CASCADE;


--
-- Name: absence_note; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.absence_note ENABLE ROW LEVEL SECURITY;

--
-- Name: admission_checklist ac_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ac_read ON public.admission_checklist FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR app.is_guardian_of(student_id))));


--
-- Name: admission_checklist ac_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ac_write ON public.admission_checklist TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('student.manage'::text)));


--
-- Name: academic_year; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.academic_year ENABLE ROW LEVEL SECURITY;

--
-- Name: academic_year academic_year_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY academic_year_admin_write ON public.academic_year TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: academic_year academic_year_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY academic_year_tenant_read ON public.academic_year FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: action_item; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.action_item ENABLE ROW LEVEL SECURITY;

--
-- Name: admission_checklist; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admission_checklist ENABLE ROW LEVEL SECURITY;

--
-- Name: action_item ai_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_read ON public.action_item FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((owner_person_id = app.person_id()) OR (app.person_type() = 'staff'::text))));


--
-- Name: action_item ai_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_write ON public.action_item TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text))) WITH CHECK (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: absence_note anote_decide; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anote_decide ON public.absence_note FOR UPDATE TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.resolve'::text))) WITH CHECK ((school_id = app.school_id()));


--
-- Name: absence_note anote_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anote_insert ON public.absence_note FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND (app.is_guardian_of(student_id) OR app.has_cap('attendance.mark'::text))));


--
-- Name: absence_note anote_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anote_read ON public.absence_note FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.form_teacher_of_student(student_id) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: attendance_record arecord_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arecord_insert ON public.attendance_record FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND app.has_cap('attendance.mark'::text) AND (EXISTS ( SELECT 1
   FROM public.attendance_session s
  WHERE ((s.id = attendance_record.attendance_session_id) AND (s.status = 'open'::text) AND app.year_is_open(s.academic_year_id) AND (app.form_teacher_of(s.class_group_id) OR app.has_cap('attendance.mark.any'::text)))))));


--
-- Name: attendance_record arecord_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arecord_read ON public.attendance_record FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR (EXISTS ( SELECT 1
   FROM public.attendance_session s
  WHERE ((s.id = attendance_record.attendance_session_id) AND app.form_teacher_of(s.class_group_id)))) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: attendance_record arecord_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arecord_update ON public.attendance_record FOR UPDATE TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.mark'::text) AND (EXISTS ( SELECT 1
   FROM public.attendance_session s
  WHERE ((s.id = attendance_record.attendance_session_id) AND (s.status = 'open'::text) AND app.year_is_open(s.academic_year_id) AND (app.form_teacher_of(s.class_group_id) OR app.has_cap('attendance.mark.any'::text))))))) WITH CHECK ((school_id = app.school_id()));


--
-- Name: attendance_session asession_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asession_read ON public.attendance_session FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.form_teacher_of(class_group_id))));


--
-- Name: attendance_session asession_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asession_write ON public.attendance_session TO authenticated USING (((school_id = app.school_id()) AND app.year_is_open(academic_year_id) AND (app.form_teacher_of(class_group_id) OR app.has_cap('attendance.mark.any'::text)))) WITH CHECK (((school_id = app.school_id()) AND app.year_is_open(academic_year_id) AND (app.form_teacher_of(class_group_id) OR app.has_cap('attendance.mark.any'::text))));


--
-- Name: assessment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assessment ENABLE ROW LEVEL SECURITY;

--
-- Name: assessment assessment_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assessment_read ON public.assessment FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: assessment assessment_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assessment_write ON public.assessment TO authenticated USING (((school_id = app.school_id()) AND (app.teaches_set(subject_set_id) OR app.has_cap('marks.moderate'::text)))) WITH CHECK (((school_id = app.school_id()) AND (app.teaches_set(subject_set_id) OR app.has_cap('marks.moderate'::text))));


--
-- Name: asset; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asset ENABLE ROW LEVEL SECURITY;

--
-- Name: asset asset_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asset_read ON public.asset FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: asset_verification; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asset_verification ENABLE ROW LEVEL SECURITY;

--
-- Name: asset_verification asset_verification_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asset_verification_read ON public.asset_verification FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: asset_verification asset_verification_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asset_verification_write ON public.asset_verification TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: asset asset_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asset_write ON public.asset TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: attendance_summary asummary_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY asummary_read ON public.attendance_summary FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.form_teacher_of_student(student_id) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: attendance_discrepancy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_discrepancy ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_record; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_record ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_session; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_session ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_summary; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_summary ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_read ON public.audit_log FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('audit.read'::text)));


--
-- Name: circular_ack ca_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ca_rw ON public.circular_ack TO authenticated USING ((person_id = app.person_id())) WITH CHECK ((person_id = app.person_id()));


--
-- Name: calendar_day; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.calendar_day ENABLE ROW LEVEL SECURITY;

--
-- Name: calendar_day calendar_day_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_day_admin_write ON public.calendar_day TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: calendar_day calendar_day_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_day_tenant_read ON public.calendar_day FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: capability; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.capability ENABLE ROW LEVEL SECURITY;

--
-- Name: capability capability_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capability_read ON public.capability FOR SELECT TO authenticated USING (true);


--
-- Name: class_enrolment ce_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ce_read ON public.class_enrolment FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.read.all'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id) OR app.form_teacher_of(class_group_id))));


--
-- Name: class_enrolment ce_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ce_write ON public.class_enrolment TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('enrolment.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('enrolment.manage'::text)));


--
-- Name: clearance_item ci_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ci_read ON public.clearance_item FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR app.is_guardian_of(student_id))));


--
-- Name: clearance_item ci_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ci_write ON public.clearance_item TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('student.manage'::text)));


--
-- Name: circular circ_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY circ_read ON public.circular FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: circular circ_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY circ_write ON public.circular TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: circular; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.circular ENABLE ROW LEVEL SECURITY;

--
-- Name: circular_ack; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.circular_ack ENABLE ROW LEVEL SECURITY;

--
-- Name: class_enrolment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.class_enrolment ENABLE ROW LEVEL SECURITY;

--
-- Name: class_group; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.class_group ENABLE ROW LEVEL SECURITY;

--
-- Name: class_group class_group_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY class_group_admin_write ON public.class_group TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: class_group class_group_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY class_group_tenant_read ON public.class_group FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: clearance_item; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clearance_item ENABLE ROW LEVEL SECURITY;

--
-- Name: committee_member cm_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cm_read ON public.committee_member FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.committee c
  WHERE ((c.id = committee_member.committee_id) AND (c.school_id = app.school_id())))));


--
-- Name: committee_member cm_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cm_write ON public.committee_member TO authenticated USING (app.has_cap('school.manage'::text)) WITH CHECK (app.has_cap('school.manage'::text));


--
-- Name: confidential_note cn_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cn_read ON public.confidential_note FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_role('rector'::text)));


--
-- Name: confidential_note cn_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cn_write ON public.confidential_note FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND app.has_role('rector'::text) AND (author_id = app.person_id())));


--
-- Name: committee; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.committee ENABLE ROW LEVEL SECURITY;

--
-- Name: committee_member; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.committee_member ENABLE ROW LEVEL SECURITY;

--
-- Name: committee committee_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY committee_read ON public.committee FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: committee committee_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY committee_write ON public.committee TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: confidential_note; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.confidential_note ENABLE ROW LEVEL SECURITY;

--
-- Name: correspondence corr_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY corr_read ON public.correspondence FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('school.manage'::text) OR (assigned_to = app.person_id()))));


--
-- Name: correspondence corr_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY corr_write ON public.correspondence TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: correspondence; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.correspondence ENABLE ROW LEVEL SECURITY;

--
-- Name: disciplinary_case dc_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dc_read ON public.disciplinary_case FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('discipline.escalate'::text) OR app.form_teacher_of_student(student_id) OR app.is_guardian_of(student_id))));


--
-- Name: disciplinary_case dc_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dc_write ON public.disciplinary_case TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text)));


--
-- Name: department; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.department ENABLE ROW LEVEL SECURITY;

--
-- Name: department department_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY department_admin_write ON public.department TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: department department_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY department_tenant_read ON public.department FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: disciplinary_case; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disciplinary_case ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_discrepancy discrepancy_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discrepancy_read ON public.attendance_discrepancy FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.read.all'::text)));


--
-- Name: attendance_discrepancy discrepancy_resolve; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discrepancy_resolve ON public.attendance_discrepancy FOR UPDATE TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.resolve'::text))) WITH CHECK ((school_id = app.school_id()));


--
-- Name: exam_arrangement ea_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ea_read ON public.exam_arrangement FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: exam_arrangement ea_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ea_write ON public.exam_arrangement TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('student.manage'::text)));


--
-- Name: exam_eligibility_decision eed_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY eed_read ON public.exam_eligibility_decision FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: exam_paper ep_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ep_read ON public.exam_paper FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: exam_paper ep_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ep_write ON public.exam_paper TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: exam_seat es_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY es_read ON public.exam_seat FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('school.manage'::text) OR app.has_cap('attendance.read.all'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id))));


--
-- Name: exam_seat es_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY es_write ON public.exam_seat TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: exam_arrangement; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exam_arrangement ENABLE ROW LEVEL SECURITY;

--
-- Name: exam_eligibility_decision; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exam_eligibility_decision ENABLE ROW LEVEL SECURITY;

--
-- Name: exam_paper; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exam_paper ENABLE ROW LEVEL SECURITY;

--
-- Name: exam_seat; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exam_seat ENABLE ROW LEVEL SECURITY;

--
-- Name: exam_session; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exam_session ENABLE ROW LEVEL SECURITY;

--
-- Name: exam_session exam_session_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exam_session_read ON public.exam_session FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: exam_session exam_session_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY exam_session_write ON public.exam_session TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: grading_band gb_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gb_read ON public.grading_band FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.grading_scale g
  WHERE ((g.id = grading_band.grading_scale_id) AND (g.school_id = app.school_id())))));


--
-- Name: grading_band gb_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gb_write ON public.grading_band TO authenticated USING (app.has_cap('school.manage'::text)) WITH CHECK (app.has_cap('school.manage'::text));


--
-- Name: grade_level; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grade_level ENABLE ROW LEVEL SECURITY;

--
-- Name: grade_level grade_level_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grade_level_admin_write ON public.grade_level TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: grade_level grade_level_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY grade_level_tenant_read ON public.grade_level FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: grading_band; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grading_band ENABLE ROW LEVEL SECURITY;

--
-- Name: grading_scale; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grading_scale ENABLE ROW LEVEL SECURITY;

--
-- Name: grading_scale gs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gs_read ON public.grading_scale FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: grading_scale gs_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gs_write ON public.grading_scale TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: guardian; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.guardian ENABLE ROW LEVEL SECURITY;

--
-- Name: guardian guardian_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY guardian_read ON public.guardian FOR SELECT TO authenticated USING (((id = app.person_id()) OR app.has_cap('person.read.all'::text)));


--
-- Name: guardian guardian_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY guardian_write ON public.guardian TO authenticated USING (app.has_cap('person.manage'::text)) WITH CHECK (app.has_cap('person.manage'::text));


--
-- Name: health_record; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.health_record ENABLE ROW LEVEL SECURITY;

--
-- Name: public_holiday holiday_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY holiday_read ON public.public_holiday FOR SELECT TO authenticated USING (true);


--
-- Name: homework; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.homework ENABLE ROW LEVEL SECURITY;

--
-- Name: homework_submission; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.homework_submission ENABLE ROW LEVEL SECURITY;

--
-- Name: health_record hr_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_read ON public.health_record FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('discipline.escalate'::text) OR app.has_cap('student.manage'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id))));


--
-- Name: health_record hr_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_write ON public.health_record TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text))) WITH CHECK (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: homework_submission hs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hs_read ON public.homework_submission FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((student_id = app.person_id()) OR app.is_guardian_of(student_id) OR (EXISTS ( SELECT 1
   FROM public.homework h
  WHERE ((h.id = homework_submission.homework_id) AND app.teaches_set(h.subject_set_id)))))));


--
-- Name: homework_submission hs_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hs_write ON public.homework_submission TO authenticated USING (((school_id = app.school_id()) AND ((student_id = app.person_id()) OR (EXISTS ( SELECT 1
   FROM public.homework h
  WHERE ((h.id = homework_submission.homework_id) AND app.teaches_set(h.subject_set_id))))))) WITH CHECK ((school_id = app.school_id()));


--
-- Name: homework hw_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hw_read ON public.homework FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.teaches_set(subject_set_id) OR app.has_cap('marks.moderate'::text) OR (EXISTS ( SELECT 1
   FROM public.set_enrolment se
  WHERE ((se.subject_set_id = homework.subject_set_id) AND (se.effective_to IS NULL) AND ((se.student_id = app.person_id()) OR app.is_guardian_of(se.student_id))))))));


--
-- Name: homework hw_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hw_write ON public.homework TO authenticated USING (((school_id = app.school_id()) AND app.teaches_set(subject_set_id))) WITH CHECK (((school_id = app.school_id()) AND app.teaches_set(subject_set_id)));


--
-- Name: invigilation_duty id_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY id_read ON public.invigilation_duty FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: invigilation_duty id_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY id_self ON public.invigilation_duty FOR UPDATE TO authenticated USING (((school_id = app.school_id()) AND (staff_id = app.person_id()))) WITH CHECK (((school_id = app.school_id()) AND (staff_id = app.person_id())));


--
-- Name: invigilation_duty id_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY id_write ON public.invigilation_duty TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: incident; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.incident ENABLE ROW LEVEL SECURITY;

--
-- Name: incident incident_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY incident_read ON public.incident FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.report'::text)));


--
-- Name: incident_student; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.incident_student ENABLE ROW LEVEL SECURITY;

--
-- Name: incident incident_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY incident_write ON public.incident TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.report'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.report'::text) AND (reported_by = app.person_id())));


--
-- Name: invigilation_duty; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invigilation_duty ENABLE ROW LEVEL SECURITY;

--
-- Name: incident_student is_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY is_read ON public.incident_student FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.incident i
  WHERE ((i.id = incident_student.incident_id) AND (i.school_id = app.school_id()) AND app.has_cap('discipline.report'::text)))));


--
-- Name: incident_student is_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY is_write ON public.incident_student TO authenticated USING (app.has_cap('discipline.report'::text)) WITH CHECK (app.has_cap('discipline.report'::text));


--
-- Name: leaving_certificate lc_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lc_read ON public.leaving_certificate FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id))));


--
-- Name: leaving_certificate lc_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lc_write ON public.leaving_certificate TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('student.manage'::text)));


--
-- Name: leave_of_absence; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_of_absence ENABLE ROW LEVEL SECURITY;

--
-- Name: leaving_certificate; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leaving_certificate ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_plan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_plan ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_substitution; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_substitution ENABLE ROW LEVEL SECURITY;

--
-- Name: library_item li_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY li_read ON public.library_item FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: library_item li_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY li_write ON public.library_item TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: library_item; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.library_item ENABLE ROW LEVEL SECURITY;

--
-- Name: library_loan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.library_loan ENABLE ROW LEVEL SECURITY;

--
-- Name: library_loan ll_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ll_read ON public.library_loan FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((app.person_type() = 'staff'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id))));


--
-- Name: library_loan ll_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ll_write ON public.library_loan TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: leave_of_absence loa_decide; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loa_decide ON public.leave_of_absence FOR UPDATE TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK ((school_id = app.school_id()));


--
-- Name: leave_of_absence loa_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loa_insert ON public.leave_of_absence FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND (app.is_guardian_of(student_id) OR app.has_cap('student.manage'::text))));


--
-- Name: leave_of_absence loa_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loa_read ON public.leave_of_absence FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: lesson_plan lp_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lp_read ON public.lesson_plan FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))));


--
-- Name: lesson_plan lp_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lp_write ON public.lesson_plan TO authenticated USING (((school_id = app.school_id()) AND (staff_id = app.person_id()))) WITH CHECK (((school_id = app.school_id()) AND (staff_id = app.person_id())));


--
-- Name: lesson_substitution ls_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ls_read ON public.lesson_substitution FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: lesson_substitution ls_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ls_write ON public.lesson_substitution TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.read.all'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('attendance.read.all'::text)));


--
-- Name: meeting_attendance ma_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ma_read ON public.meeting_attendance FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.meeting m
  WHERE ((m.id = meeting_attendance.meeting_id) AND (m.school_id = app.school_id())))));


--
-- Name: meeting_attendance ma_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ma_write ON public.meeting_attendance TO authenticated USING ((app.person_type() = 'staff'::text)) WITH CHECK ((app.person_type() = 'staff'::text));


--
-- Name: maintenance_request; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_request ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_request maintenance_request_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maintenance_request_read ON public.maintenance_request FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: maintenance_request maintenance_request_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maintenance_request_write ON public.maintenance_request TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: mark; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mark ENABLE ROW LEVEL SECURITY;

--
-- Name: mark_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mark_history ENABLE ROW LEVEL SECURITY;

--
-- Name: mark mark_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mark_read ON public.mark FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('marks.read.all'::text) OR (EXISTS ( SELECT 1
   FROM public.assessment a
  WHERE ((a.id = mark.assessment_id) AND app.teaches_set(a.subject_set_id)))) OR ((EXISTS ( SELECT 1
   FROM public.assessment a
  WHERE ((a.id = mark.assessment_id) AND (a.status = 'published'::public.assessment_status)))) AND ((student_id = app.person_id()) OR app.is_guardian_of(student_id))))));


--
-- Name: mark mark_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mark_write ON public.mark TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.enter'::text) AND (EXISTS ( SELECT 1
   FROM public.assessment a
  WHERE ((a.id = mark.assessment_id) AND app.year_is_open(a.academic_year_id) AND (((a.status = ANY (ARRAY['draft'::public.assessment_status, 'open'::public.assessment_status])) AND app.teaches_set(a.subject_set_id)) OR app.has_cap('marks.moderate'::text))))))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.enter'::text) AND (EXISTS ( SELECT 1
   FROM public.assessment a
  WHERE ((a.id = mark.assessment_id) AND app.year_is_open(a.academic_year_id) AND (((a.status = ANY (ARRAY['draft'::public.assessment_status, 'open'::public.assessment_status])) AND app.teaches_set(a.subject_set_id)) OR app.has_cap('marks.moderate'::text)))))));


--
-- Name: meeting; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meeting ENABLE ROW LEVEL SECURITY;

--
-- Name: meeting_attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meeting_attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: meeting meeting_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY meeting_read ON public.meeting FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((visibility = 'public'::text) OR ((visibility = 'internal'::text) AND (app.person_type() = 'staff'::text)) OR ((visibility = 'smt'::text) AND app.has_cap('school.manage'::text)))));


--
-- Name: meeting meeting_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY meeting_write ON public.meeting TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text))) WITH CHECK (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: merit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merit ENABLE ROW LEVEL SECURITY;

--
-- Name: merit merit_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merit_read ON public.merit FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('discipline.report'::text) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: merit merit_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merit_write ON public.merit TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.report'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.report'::text)));


--
-- Name: message; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message ENABLE ROW LEVEL SECURITY;

--
-- Name: message_thread; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_thread ENABLE ROW LEVEL SECURITY;

--
-- Name: mark_history mh_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mh_read ON public.mark_history FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.read.all'::text)));


--
-- Name: student_movement movement_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movement_read ON public.student_movement FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.is_guardian_of(student_id))));


--
-- Name: student_movement movement_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movement_write ON public.student_movement TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('attendance.resolve'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('attendance.resolve'::text)));


--
-- Name: maintenance_request mr_report; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mr_report ON public.maintenance_request FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND (reported_by = app.person_id())));


--
-- Name: message msg_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY msg_read ON public.message FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.in_thread(thread_id)));


--
-- Name: message msg_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY msg_write ON public.message FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND (sender_id = app.person_id()) AND app.in_thread(thread_id)));


--
-- Name: message_thread mt_create; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mt_create ON public.message_thread FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND (created_by = app.person_id())));


--
-- Name: message_thread mt_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mt_read ON public.message_thread FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.in_thread(id)));


--
-- Name: message_thread mt_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mt_write ON public.message_thread TO authenticated USING ((school_id = app.school_id())) WITH CHECK ((school_id = app.school_id()));


--
-- Name: notice; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notice ENABLE ROW LEVEL SECURITY;

--
-- Name: notice notice_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_read ON public.notice FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (publish_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now()))));


--
-- Name: notice_read; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notice_read ENABLE ROW LEVEL SECURITY;

--
-- Name: notice notice_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notice_write ON public.notice TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text))) WITH CHECK (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: notification notif_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notif_read ON public.notification FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((person_id = app.person_id()) OR app.has_cap('school.manage'::text))));


--
-- Name: notification notif_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notif_write ON public.notification TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: notification; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;

--
-- Name: notice_read nr_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nr_rw ON public.notice_read TO authenticated USING ((person_id = app.person_id())) WITH CHECK ((person_id = app.person_id()));


--
-- Name: option_block_subject obs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY obs_read ON public.option_block_subject FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.option_block ob
  WHERE ((ob.id = option_block_subject.option_block_id) AND (ob.school_id = app.school_id())))));


--
-- Name: option_block_subject obs_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY obs_write ON public.option_block_subject TO authenticated USING (app.has_cap('school.manage'::text)) WITH CHECK (app.has_cap('school.manage'::text));


--
-- Name: occurrence_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.occurrence_log ENABLE ROW LEVEL SECURITY;

--
-- Name: occurrence_log ol_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ol_insert ON public.occurrence_log FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND app.has_cap('occurrence.append'::text) AND (entered_by = app.person_id())));


--
-- Name: occurrence_log ol_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ol_read ON public.occurrence_log FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('occurrence.read'::text)));


--
-- Name: option_block; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.option_block ENABLE ROW LEVEL SECURITY;

--
-- Name: option_block option_block_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY option_block_admin_write ON public.option_block TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: option_block_subject; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.option_block_subject ENABLE ROW LEVEL SECURITY;

--
-- Name: option_block option_block_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY option_block_tenant_read ON public.option_block FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: policy_acknowledgement pa_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pa_read ON public.policy_acknowledgement FOR SELECT TO authenticated USING (((person_id = app.person_id()) OR app.has_cap('school.manage'::text)));


--
-- Name: policy_acknowledgement pa_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pa_write ON public.policy_acknowledgement FOR INSERT TO authenticated WITH CHECK ((person_id = app.person_id()));


--
-- Name: pastoral_case; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pastoral_case ENABLE ROW LEVEL SECURITY;

--
-- Name: pastoral_note; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pastoral_note ENABLE ROW LEVEL SECURITY;

--
-- Name: period_attendance pattendance_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pattendance_read ON public.period_attendance FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('attendance.read.all'::text) OR app.teaches_set(subject_set_id) OR app.form_teacher_of_student(student_id) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: period_attendance pattendance_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pattendance_write ON public.period_attendance TO authenticated USING (((school_id = app.school_id()) AND app.teaches_set(subject_set_id))) WITH CHECK (((school_id = app.school_id()) AND app.teaches_set(subject_set_id)));


--
-- Name: pastoral_case pc_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pc_read ON public.pastoral_case FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text)));


--
-- Name: pastoral_case pc_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pc_write ON public.pastoral_case TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text)));


--
-- Name: policy_document pd_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pd_read ON public.policy_document FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: policy_document pd_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pd_write ON public.policy_document TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: period_attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.period_attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: period_definition; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.period_definition ENABLE ROW LEVEL SECURITY;

--
-- Name: period_definition period_definition_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY period_definition_admin_write ON public.period_definition TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: period_definition period_definition_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY period_definition_tenant_read ON public.period_definition FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: person; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.person ENABLE ROW LEVEL SECURITY;

--
-- Name: person person_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY person_admin_write ON public.person TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('person.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('person.manage'::text)));


--
-- Name: person person_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY person_read ON public.person FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('person.read.all'::text) OR (id = app.person_id()) OR ((person_type = 'student'::public.person_type) AND app.is_guardian_of(id)) OR (person_type = 'staff'::public.person_type))));


--
-- Name: person person_self_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY person_self_update ON public.person FOR UPDATE TO authenticated USING ((id = app.person_id())) WITH CHECK ((id = app.person_id()));


--
-- Name: pastoral_note pn_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pn_read ON public.pastoral_note FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (((visibility = 'committee'::text) AND app.has_cap('discipline.escalate'::text)) OR ((visibility = 'smt'::text) AND app.has_cap('school.manage'::text)) OR ((visibility = 'rector_only'::text) AND app.has_role('rector'::text)))));


--
-- Name: pastoral_note pn_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pn_write ON public.pastoral_note FOR INSERT TO authenticated WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text) AND (author_id = app.person_id())));


--
-- Name: policy_acknowledgement; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.policy_acknowledgement ENABLE ROW LEVEL SECURITY;

--
-- Name: policy_document; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.policy_document ENABLE ROW LEVEL SECURITY;

--
-- Name: public_holiday; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.public_holiday ENABLE ROW LEVEL SECURITY;

--
-- Name: report_card rc_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rc_read ON public.report_card FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('marks.read.all'::text) OR app.form_teacher_of_student(student_id) OR ((status = 'published'::text) AND ((student_id = app.person_id()) OR app.is_guardian_of(student_id))))));


--
-- Name: report_card rc_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rc_write ON public.report_card TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text)));


--
-- Name: report_card; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.report_card ENABLE ROW LEVEL SECURITY;

--
-- Name: teaching_resource res_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY res_read ON public.teaching_resource FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: teaching_resource res_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY res_write ON public.teaching_resource TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.enter'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.enter'::text)));


--
-- Name: role; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role ENABLE ROW LEVEL SECURITY;

--
-- Name: role_capability; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_capability ENABLE ROW LEVEL SECURITY;

--
-- Name: role role_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY role_read ON public.role FOR SELECT TO authenticated USING (true);


--
-- Name: role_capability rolecap_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rolecap_read ON public.role_capability FOR SELECT TO authenticated USING (true);


--
-- Name: room; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.room ENABLE ROW LEVEL SECURITY;

--
-- Name: room room_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY room_admin_write ON public.room TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: room room_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY room_tenant_read ON public.room FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: sanction; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sanction ENABLE ROW LEVEL SECURITY;

--
-- Name: sanction sanction_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sanction_read ON public.sanction FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('discipline.escalate'::text) OR app.form_teacher_of_student(student_id) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: sanction sanction_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sanction_write ON public.sanction TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('discipline.escalate'::text)));


--
-- Name: script_batch sb_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sb_read ON public.script_batch FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: script_batch sb_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sb_write ON public.script_batch TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text)));


--
-- Name: scheme_of_work; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.scheme_of_work ENABLE ROW LEVEL SECURITY;

--
-- Name: scheme_week; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.scheme_week ENABLE ROW LEVEL SECURITY;

--
-- Name: school; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.school ENABLE ROW LEVEL SECURITY;

--
-- Name: school school_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY school_admin_write ON public.school FOR UPDATE TO authenticated USING (((id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: school school_platform_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY school_platform_write ON public.school TO authenticated USING (app.has_cap('platform.manage'::text)) WITH CHECK (app.has_cap('platform.manage'::text));


--
-- Name: school school_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY school_read ON public.school FOR SELECT TO authenticated USING (((id = app.school_id()) OR (id IN ( SELECT app.visible_schools() AS visible_schools))));


--
-- Name: script_batch; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.script_batch ENABLE ROW LEVEL SECURITY;

--
-- Name: student_document sd_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sd_read ON public.student_document FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR ((NOT is_sensitive) AND app.form_teacher_of_student(student_id)) OR app.is_guardian_of(student_id) OR (student_id = app.person_id()))));


--
-- Name: student_document sd_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sd_write ON public.student_document TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR app.is_guardian_of(student_id)))) WITH CHECK (((school_id = app.school_id()) AND (app.has_cap('student.manage'::text) OR app.is_guardian_of(student_id))));


--
-- Name: set_enrolment se_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY se_read ON public.set_enrolment FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.read.all'::text) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id) OR app.teaches_set(subject_set_id))));


--
-- Name: set_enrolment se_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY se_write ON public.set_enrolment TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('enrolment.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('enrolment.manage'::text)));


--
-- Name: set_educator; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.set_educator ENABLE ROW LEVEL SECURITY;

--
-- Name: set_educator set_educator_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY set_educator_read ON public.set_educator FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.subject_set ss
  WHERE ((ss.id = set_educator.subject_set_id) AND (ss.school_id = app.school_id())))));


--
-- Name: set_educator set_educator_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY set_educator_write ON public.set_educator TO authenticated USING (app.has_cap('school.manage'::text)) WITH CHECK (app.has_cap('school.manage'::text));


--
-- Name: set_enrolment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.set_enrolment ENABLE ROW LEVEL SECURITY;

--
-- Name: student_guardian sg_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sg_read ON public.student_guardian FOR SELECT TO authenticated USING (((guardian_id = app.person_id()) OR (student_id = app.person_id()) OR app.has_cap('person.read.all'::text)));


--
-- Name: student_guardian sg_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sg_write ON public.student_guardian TO authenticated USING (app.has_cap('person.manage'::text)) WITH CHECK (app.has_cap('person.manage'::text));


--
-- Name: staff_leave sl_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sl_read ON public.staff_leave FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('staff.manage'::text) OR app.has_cap('attendance.read.all'::text))));


--
-- Name: staff_leave sl_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sl_write ON public.staff_leave TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('staff.manage'::text)))) WITH CHECK (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('staff.manage'::text))));


--
-- Name: scheme_of_work sow_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sow_read ON public.scheme_of_work FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))));


--
-- Name: scheme_of_work sow_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sow_write ON public.scheme_of_work TO authenticated USING (((school_id = app.school_id()) AND (((staff_id = app.person_id()) AND (status = ANY (ARRAY['draft'::public.plan_status, 'hod_returned'::public.plan_status]))) OR app.has_cap('marks.moderate'::text)))) WITH CHECK (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))));


--
-- Name: staff_role_assignment sra_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sra_read ON public.staff_role_assignment FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('roles.manage'::text))));


--
-- Name: staff_role_assignment sra_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sra_write ON public.staff_role_assignment TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('roles.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('roles.manage'::text)));


--
-- Name: staff; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_document; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_document ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_leave; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_leave ENABLE ROW LEVEL SECURITY;

--
-- Name: staff staff_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_read ON public.staff FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: staff_role_assignment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_role_assignment ENABLE ROW LEVEL SECURITY;

--
-- Name: staff staff_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_write ON public.staff TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('staff.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('staff.manage'::text)));


--
-- Name: staff_document std_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY std_read ON public.staff_document FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('staff.manage'::text))));


--
-- Name: staff_document std_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY std_write ON public.staff_document TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('staff.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('staff.manage'::text)));


--
-- Name: student; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student ENABLE ROW LEVEL SECURITY;

--
-- Name: student student_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY student_admin_write ON public.student TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('student.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('student.manage'::text)));


--
-- Name: student_document; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student_document ENABLE ROW LEVEL SECURITY;

--
-- Name: student_guardian; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student_guardian ENABLE ROW LEVEL SECURITY;

--
-- Name: student_movement; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student_movement ENABLE ROW LEVEL SECURITY;

--
-- Name: student student_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY student_read ON public.student FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('student.read.all'::text) OR (id = app.person_id()) OR app.is_guardian_of(id) OR app.form_teacher_of_student(id) OR (EXISTS ( SELECT 1
   FROM public.set_enrolment se
  WHERE ((se.student_id = student.id) AND (se.effective_to IS NULL) AND app.teaches_set(se.subject_set_id)))))));


--
-- Name: syllabus_unit su_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY su_read ON public.syllabus_unit FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: syllabus_unit su_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY su_write ON public.syllabus_unit TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text)));


--
-- Name: subject; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subject ENABLE ROW LEVEL SECURITY;

--
-- Name: subject subject_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subject_admin_write ON public.subject TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: subject_set; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subject_set ENABLE ROW LEVEL SECURITY;

--
-- Name: subject_set subject_set_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subject_set_admin_write ON public.subject_set TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: subject_set subject_set_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subject_set_tenant_read ON public.subject_set FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: subject subject_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subject_tenant_read ON public.subject FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: scheme_week sw_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sw_read ON public.scheme_week FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.scheme_of_work s
  WHERE ((s.id = scheme_week.scheme_of_work_id) AND (s.school_id = app.school_id()) AND ((s.staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))))));


--
-- Name: scheme_week sw_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sw_write ON public.scheme_week TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.scheme_of_work s
  WHERE ((s.id = scheme_week.scheme_of_work_id) AND ((s.staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.scheme_of_work s
  WHERE ((s.id = scheme_week.scheme_of_work_id) AND ((s.staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))))));


--
-- Name: syllabus syl_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY syl_read ON public.syllabus FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: syllabus syl_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY syl_write ON public.syllabus TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('marks.moderate'::text)));


--
-- Name: syllabus; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.syllabus ENABLE ROW LEVEL SECURITY;

--
-- Name: syllabus_unit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.syllabus_unit ENABLE ROW LEVEL SECURITY;

--
-- Name: teaching_resource; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teaching_resource ENABLE ROW LEVEL SECURITY;

--
-- Name: term; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.term ENABLE ROW LEVEL SECURITY;

--
-- Name: term term_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY term_admin_write ON public.term TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: term_result; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.term_result ENABLE ROW LEVEL SECURITY;

--
-- Name: term term_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY term_tenant_read ON public.term FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: thread_participant; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.thread_participant ENABLE ROW LEVEL SECURITY;

--
-- Name: timetable_slot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.timetable_slot ENABLE ROW LEVEL SECURITY;

--
-- Name: timetable_slot timetable_slot_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY timetable_slot_admin_write ON public.timetable_slot TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: timetable_slot timetable_slot_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY timetable_slot_tenant_read ON public.timetable_slot FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: timetable_version; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.timetable_version ENABLE ROW LEVEL SECURITY;

--
-- Name: timetable_version timetable_version_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY timetable_version_admin_write ON public.timetable_version TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: timetable_version timetable_version_tenant_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY timetable_version_tenant_read ON public.timetable_version FOR SELECT TO authenticated USING ((school_id = app.school_id()));


--
-- Name: thread_participant tp_add; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tp_add ON public.thread_participant FOR INSERT TO authenticated WITH CHECK ((app.thread_owner(thread_id) OR app.in_thread(thread_id)));


--
-- Name: thread_participant tp_leave; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tp_leave ON public.thread_participant FOR DELETE TO authenticated USING ((person_id = app.person_id()));


--
-- Name: thread_participant tp_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tp_read ON public.thread_participant FOR SELECT TO authenticated USING (((person_id = app.person_id()) OR app.in_thread(thread_id)));


--
-- Name: thread_participant tp_update_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tp_update_self ON public.thread_participant FOR UPDATE TO authenticated USING ((person_id = app.person_id())) WITH CHECK ((person_id = app.person_id()));


--
-- Name: term_result tr_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tr_read ON public.term_result FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.has_cap('marks.read.all'::text) OR app.teaches_set(subject_set_id) OR app.form_teacher_of_student(student_id) OR (student_id = app.person_id()) OR app.is_guardian_of(student_id))));


--
-- Name: visitor_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.visitor_log ENABLE ROW LEVEL SECURITY;

--
-- Name: visitor_log visitor_log_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY visitor_log_read ON public.visitor_log FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: visitor_log visitor_log_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY visitor_log_write ON public.visitor_log TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: water_quality_certificate; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.water_quality_certificate ENABLE ROW LEVEL SECURITY;

--
-- Name: water_quality_certificate water_quality_certificate_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_quality_certificate_read ON public.water_quality_certificate FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND (app.person_type() = 'staff'::text)));


--
-- Name: water_quality_certificate water_quality_certificate_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_quality_certificate_write ON public.water_quality_certificate TO authenticated USING (((school_id = app.school_id()) AND app.has_cap('school.manage'::text))) WITH CHECK (((school_id = app.school_id()) AND app.has_cap('school.manage'::text)));


--
-- Name: weekly_plan; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_plan ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_plan_row; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_plan_row ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_plan wp_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wp_read ON public.weekly_plan FOR SELECT TO authenticated USING (((school_id = app.school_id()) AND ((staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))));


--
-- Name: weekly_plan wp_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wp_write ON public.weekly_plan TO authenticated USING (((school_id = app.school_id()) AND (staff_id = app.person_id()))) WITH CHECK (((school_id = app.school_id()) AND (staff_id = app.person_id())));


--
-- Name: weekly_plan_row wpr_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wpr_read ON public.weekly_plan_row FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.weekly_plan w
  WHERE ((w.id = weekly_plan_row.weekly_plan_id) AND (w.school_id = app.school_id()) AND ((w.staff_id = app.person_id()) OR app.has_cap('marks.moderate'::text))))));


--
-- Name: weekly_plan_row wpr_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wpr_write ON public.weekly_plan_row TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.weekly_plan w
  WHERE ((w.id = weekly_plan_row.weekly_plan_id) AND (w.staff_id = app.person_id()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.weekly_plan w
  WHERE ((w.id = weekly_plan_row.weekly_plan_id) AND (w.staff_id = app.person_id())))));


--
-- PostgreSQL database dump complete
--

\unrestrict ttlrgdcph9sIjuaADXaKhevHf1LeHE7P4PjTNPTpd8V011RQaQ2rAZkntyUGzip

