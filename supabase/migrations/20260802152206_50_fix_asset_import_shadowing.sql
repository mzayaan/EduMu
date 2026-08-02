-- EduMU :: 50 An OUT parameter named `tag` shadowed asset.tag.
--
-- Same class of bug as the `room r` alias in rpc_allocate_seats: PL/pgSQL
-- resolves an ambiguous name to the variable, not the column. OUT parameters
-- are variables too. They are now prefixed, and the asset table is aliased, so
-- neither can be mistaken for the other.

drop function if exists public.rpc_import_assets(jsonb, boolean);

create function public.rpc_import_assets(
  p_rows jsonb, p_commit boolean default false
) returns table (out_row_no int, out_tag text, out_action text, out_detail text)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  r jsonb; i int := 0; v_school uuid; v_room uuid; v_exists boolean;
  v_tag text; v_name text;
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to import assets';
  end if;
  v_school := app.school_id();

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    v_tag  := nullif(trim(r ->> 'tag'), '');
    v_name := nullif(trim(r ->> 'name'), '');

    out_row_no := i;
    out_tag    := coalesce(v_tag, '');

    if v_tag is null then
      out_action := 'error'; out_detail := 'missing tag';
      return next; continue;
    end if;
    if v_name is null then
      out_action := 'error'; out_detail := 'missing name';
      return next; continue;
    end if;

    v_room := null;
    if nullif(trim(r ->> 'room'), '') is not null then
      select rm.id into v_room from room rm
       where rm.school_id = v_school
         and lower(rm.code) = lower(trim(r ->> 'room'));
      if v_room is null then
        out_action := 'error';
        out_detail := format('unknown room %L', r ->> 'room');
        return next; continue;
      end if;
    end if;

    select exists (
      select 1 from asset a where a.school_id = v_school and a.tag = v_tag
    ) into v_exists;

    out_action := case when v_exists then 'update' else 'create' end;
    out_detail := v_name ||
      case when v_room is not null then ' → ' || (r ->> 'room') else '' end;

    if p_commit then
      insert into asset (school_id, tag, category, name, room_id,
                         acquired_on, cost, condition)
      values (v_school, v_tag,
              coalesce(nullif(trim(r ->> 'category'), ''), 'uncategorised'),
              v_name, v_room,
              nullif(r ->> 'acquired_on', '')::date,
              nullif(r ->> 'cost', '')::numeric,
              coalesce(nullif(trim(r ->> 'condition'), ''), 'good'))
      on conflict (school_id, tag) do update set
        category    = excluded.category,
        name        = excluded.name,
        -- A blank room in the file must not clear a room already recorded.
        room_id     = coalesce(excluded.room_id, asset.room_id),
        acquired_on = coalesce(excluded.acquired_on, asset.acquired_on),
        cost        = coalesce(excluded.cost, asset.cost),
        condition   = excluded.condition;
    end if;

    return next;
  end loop;
end $$;

revoke all on function public.rpc_import_assets(jsonb, boolean) from public, anon;
grant execute on function public.rpc_import_assets(jsonb, boolean) to authenticated;
