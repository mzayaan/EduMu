-- EduMU :: 49 Syllabus tree helpers and asset import.

-- The whole tree for one subject and grade, in one call, with each unit's
-- depth precomputed so the client renders indentation without recursing.
create or replace function public.syllabus_tree(p_syllabus uuid)
returns table (
  id uuid, parent_id uuid, code text, title text,
  objectives text[], term_id uuid, term_name text,
  sort_order smallint, depth int, path text[]
)
language sql stable security definer set search_path = public, app, pg_temp as $$
  with recursive tree as (
    select u.id, u.parent_id, u.code, u.title, u.objectives, u.term_id,
           u.sort_order, 0 as depth,
           array[lpad(u.sort_order::text, 4, '0') || coalesce(u.code,'')] as path
    from syllabus_unit u
    join syllabus s on s.id = u.syllabus_id
    where u.syllabus_id = p_syllabus
      and u.parent_id is null
      and s.school_id = app.school_id()
    union all
    select u.id, u.parent_id, u.code, u.title, u.objectives, u.term_id,
           u.sort_order, t.depth + 1,
           t.path || (lpad(u.sort_order::text, 4, '0') || coalesce(u.code,''))
    from syllabus_unit u
    join tree t on t.id = u.parent_id
  )
  select t.id, t.parent_id, t.code, t.title, t.objectives, t.term_id,
         term.name, t.sort_order, t.depth, t.path
  from tree t
  left join term on term.id = t.term_id
  order by t.path;
$$;

-- Find or create the syllabus for a subject and grade in the active year.
create or replace function public.rpc_ensure_syllabus(
  p_subject uuid, p_grade uuid
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id uuid; v_year uuid; v_school uuid;
begin
  if not app.has_cap('marks.moderate') then
    raise exception 'Building a syllabus is a Head of Department function';
  end if;
  v_school := app.school_id();
  select id into v_year from academic_year
   where school_id = v_school and status = 'active';
  if v_year is null then raise exception 'No active academic year'; end if;

  select id into v_id from syllabus
   where academic_year_id = v_year and subject_id = p_subject
     and grade_level_id = p_grade and version = 1;
  if v_id is null then
    insert into syllabus (school_id, academic_year_id, subject_id, grade_level_id, version)
    values (v_school, v_year, p_subject, p_grade, 1)
    returning id into v_id;
  end if;
  return v_id;
end $$;

/*
 * Asset import.
 *
 * Schools already keep an assets register, usually in a spreadsheet. Import has
 * to be idempotent on the asset tag — a second run of the same file must update
 * rather than duplicate, because it WILL be run twice.
 *
 * Returns a per-row outcome so the UI can show a dry-run diff before committing.
 */
create or replace function public.rpc_import_assets(
  p_rows jsonb, p_commit boolean default false
) returns table (row_no int, tag text, action text, detail text)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare r jsonb; i int := 0; v_school uuid; v_room uuid; v_exists boolean;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to import assets';
  end if;
  v_school := app.school_id();

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    row_no := i;
    tag := nullif(trim(r ->> 'tag'), '');

    if tag is null then
      action := 'error'; detail := 'missing tag';
      return next; continue;
    end if;
    if nullif(trim(r ->> 'name'), '') is null then
      action := 'error'; detail := 'missing name';
      return next; continue;
    end if;

    v_room := null;
    if nullif(trim(r ->> 'room'), '') is not null then
      select id into v_room from room
       where school_id = v_school and lower(code) = lower(trim(r ->> 'room'));
      if v_room is null then
        action := 'error';
        detail := format('unknown room %L', r ->> 'room');
        return next; continue;
      end if;
    end if;

    select exists (select 1 from asset a
                   where a.school_id = v_school and a.tag = tag) into v_exists;
    action := case when v_exists then 'update' else 'create' end;
    detail := coalesce(r ->> 'name', '') ||
              case when v_room is not null then ' → ' || (r ->> 'room') else '' end;

    if p_commit then
      insert into asset (school_id, tag, category, name, room_id,
                         acquired_on, cost, condition)
      values (v_school, tag,
              coalesce(nullif(trim(r ->> 'category'), ''), 'uncategorised'),
              trim(r ->> 'name'), v_room,
              nullif(r ->> 'acquired_on', '')::date,
              nullif(r ->> 'cost', '')::numeric,
              coalesce(nullif(trim(r ->> 'condition'), ''), 'good'))
      on conflict (school_id, tag) do update set
        category    = excluded.category,
        name        = excluded.name,
        room_id     = coalesce(excluded.room_id, asset.room_id),
        acquired_on = coalesce(excluded.acquired_on, asset.acquired_on),
        cost        = coalesce(excluded.cost, asset.cost),
        condition   = excluded.condition;
    end if;

    return next;
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.syllabus_tree(uuid)',
    'public.rpc_ensure_syllabus(uuid, uuid)',
    'public.rpc_import_assets(jsonb, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
