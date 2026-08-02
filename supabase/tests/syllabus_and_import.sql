-- EduMU :: Syllabus tree and asset import.
--
-- Two things worth asserting beyond "it works":
--
--   1. `rpc_ensure_syllabus` must be idempotent. Opening a subject/grade pair
--      in the editor calls it, and the editor is opened constantly.
--   2. Asset import must be idempotent on the tag AND must not clear a field
--      that is blank in the file. Schools re-run the same spreadsheet, and a
--      partial second file must not wipe rooms recorded the first time.
--
-- NOTE on `rpc_import_assets`: its OUT parameters are prefixed `out_` because
-- an OUT parameter named `tag` shadowed `asset.tag` — PL/pgSQL resolves an
-- ambiguous name to the variable. Same class of bug as the `room r` alias in
-- rpc_allocate_seats.
--
-- Every row must read PASS.

create temp table if not exists sa(test text, expected text, got text, pass boolean);
truncate sa;

do $$
declare
  sch uuid; p uuid; caps jsonb; v_syl uuid; v_again uuid;
  v_math uuid; v_g7 uuid; root uuid; n int; rows_json jsonb;
begin
  select id into sch from school where code='DEMO-SSS';
  select id into p   from person where email='a.ramdin@demo-sss.mu';
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps
   from role_capability where role_code='rector';
  select id into v_math from subject where school_id=sch and code='MATH';
  select id into v_g7   from grade_level where school_id=sch and grade=7;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',p,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',caps)::text, true);

  -- ── syllabus ────────────────────────────────────────────────────────
  set local role authenticated;
  select rpc_ensure_syllabus(v_math, v_g7) into v_syl;
  select rpc_ensure_syllabus(v_math, v_g7) into v_again;
  reset role;
  insert into sa values ('Syllabus created','not null',
    case when v_syl is null then 'null' else 'ok' end, v_syl is not null);
  insert into sa values ('Ensure is idempotent','same id',
    case when v_again = v_syl then 'same id' else 'different' end, v_again = v_syl);

  delete from syllabus_unit where syllabus_id = v_syl;
  insert into syllabus_unit (school_id, syllabus_id, code, title, sort_order, term_id)
  values (sch, v_syl, 'N1', 'Number', 1,
    (select id from term where academic_year_id =
      (select academic_year_id from syllabus where id = v_syl) and sequence = 1))
  returning id into root;
  insert into syllabus_unit (school_id, syllabus_id, parent_id, code, title, objectives, sort_order)
  values (sch, v_syl, root, 'N1.1', 'Place value',
          array['Read and write numbers to 1 000 000'], 1),
         (sch, v_syl, root, 'N1.2', 'Operations on integers',
          array['Add, subtract, multiply and divide integers'], 2);

  set local role authenticated;
  select count(*) into n from syllabus_tree(v_syl);
  reset role;
  insert into sa values ('Tree returns every unit','3',n::text,n=3);

  set local role authenticated;
  select max(depth) into n from syllabus_tree(v_syl);
  reset role;
  insert into sa values ('Children are one level deeper','1',n::text,n=1);

  -- ── asset import ────────────────────────────────────────────────────
  delete from asset where tag in ('LAB-001','IT-014');

  rows_json := jsonb_build_array(
    jsonb_build_object('tag','LAB-001','name','Bunsen burner',
                       'category','Laboratory','room','LAB-C'),
    jsonb_build_object('tag','IT-014','name','Desktop PC',
                       'category','IT','room','IT-1','cost','18500'),
    jsonb_build_object('tag','','name','Nameless'),
    jsonb_build_object('tag','R-900','name','Chair','room','NO-SUCH-ROOM'));

  -- One bad room must not cost the good rows: errors are per row.
  set local role authenticated;
  select count(*) into n from rpc_import_assets(rows_json, false) where out_action='error';
  reset role;
  insert into sa values ('Dry run flags the two bad rows','2',n::text,n=2);

  select count(*) into n from asset where tag in ('LAB-001','IT-014');
  insert into sa values ('Dry run wrote nothing','0',n::text,n=0);

  set local role authenticated;
  select count(*) into n from rpc_import_assets(rows_json, true) where out_action='create';
  reset role;
  insert into sa values ('Commit creates the good rows','2',n::text,n=2);

  select count(*) into n from asset where tag in ('LAB-001','IT-014');
  insert into sa values ('Assets exist after commit','2',n::text,n=2);

  -- The same file WILL be run twice.
  set local role authenticated;
  select count(*) into n from rpc_import_assets(rows_json, true) where out_action='update';
  reset role;
  insert into sa values ('Second run reports updates, not creates','2',n::text,n=2);

  select count(*) into n from asset where tag in ('LAB-001','IT-014');
  insert into sa values ('Re-import does not duplicate','2',n::text,n=2);

  -- A later, thinner file must not wipe what the first one recorded.
  set local role authenticated;
  perform rpc_import_assets(
    jsonb_build_array(jsonb_build_object('tag','LAB-001','name','Bunsen burner')), true);
  reset role;
  select count(*) into n from asset where tag='LAB-001' and room_id is not null;
  insert into sa values ('Blank room does not clear an existing one','1',n::text,n=1);

  -- Importing is not an Educator's job.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',p,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',(select coalesce(jsonb_agg(distinct capability_code),'[]')
            from role_capability where role_code='educator'))::text, true);
  set local role authenticated;
  begin
    perform rpc_import_assets(rows_json, true);
    n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into sa values ('Educator cannot import assets','raises (1)',n::text,n=1);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from sa;
