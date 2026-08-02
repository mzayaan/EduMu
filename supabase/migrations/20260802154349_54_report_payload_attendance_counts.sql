-- EduMU :: 54 Point the report book payload at the richer attendance block.
-- Only the 'attendance' key changes; everything else is as migration 45 left it.

create or replace function public.report_card_data(p_term uuid, p_student uuid)
returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with term_info as (
    select t.*, y.name as year_name
    from term t join academic_year y on y.id = t.academic_year_id
    where t.id = p_term
  ),
  sat as (
    select a.id, a.title, a.kind, a.max_score, a.weight, a.scheduled_on,
           a.subject_set_id, a.kind::text || '|' || a.title as col_key,
           case a.kind
             when 'class_test' then 1 when 'homework' then 1 when 'project' then 1
             when 'practical'  then 2 when 'term_test' then 3
             when 'mock'       then 4 when 'end_of_term' then 5
             when 'end_of_year' then 5 else 6 end as sort_group
    from assessment a
    join mark m on m.assessment_id = a.id and m.student_id = p_student
    where a.term_id = p_term and a.status = 'published'
  ),
  cols as (
    select col_key, kind, title, min(sort_group) as sort_group,
           min(scheduled_on) as first_on,
           case when count(distinct max_score) = 1 then max(max_score) end as max_score,
           max(weight) as weight
    from sat group by col_key, kind, title
  ),
  subj as (
    select tr.subject_id, sub.name_en as subject_name, sub.code as subject_code,
           tr.subject_set_id, tr.aggregate_score, tr.band_label,
           tr.rank_in_set, tr.set_size, tr.educator_comment, tr.difficulties,
           (select string_agg(p2.first_name || ' ' || p2.last_name, ', ')
            from set_educator se join person p2 on p2.id = se.staff_id
            where se.subject_set_id = tr.subject_set_id and se.is_primary) as teacher
    from term_result tr join subject sub on sub.id = tr.subject_id
    where tr.term_id = p_term and tr.student_id = p_student
  )
  select jsonb_build_object(
    'school', (select jsonb_build_object('name', name, 'code', code, 'motto', motto,
                 'logo_path', logo_path, 'address', address, 'contact', contact,
                 'type', type, 'zone', zone)
               from school where id = app.school_id()),
    'term', (select jsonb_build_object('name', name, 'sequence', sequence,
               'year', year_name, 'starts_on', starts_on, 'ends_on', ends_on)
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
                'name', cg.name, 'stream', cg.stream, 'grade', gl.grade,
                'legacy_form', gl.legacy_form, 'room', r.code,
                'size', (select count(*) from class_enrolment c2
                         where c2.class_group_id = cg.id and c2.effective_to is null),
                -- A class now has up to two Form Teachers, one per register.
                'form_teacher', (
                  select string_agg(
                    p3.first_name || ' ' || p3.last_name ||
                    case when sra.session is not null
                         then ' (' || upper(sra.session::text) || ')' else '' end,
                    ', ' order by sra.session nulls first)
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
          select coalesce(jsonb_object_agg(x.col_key, jsonb_build_object(
            'score', x.score, 'code', x.code, 'max', x.max_score)), '{}'::jsonb)
          from (select sa.col_key, m.score, m.code, sa.max_score
                from sat sa join mark m on m.assessment_id = sa.id
                where m.student_id = p_student
                  and sa.subject_set_id = s.subject_set_id) x)
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
    -- Counts, not only a percentage.
    'attendance', public.report_card_attendance(p_term, p_student),
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

revoke all on function public.report_card_data(uuid, uuid) from public, anon;
grant execute on function public.report_card_data(uuid, uuid) to authenticated;
