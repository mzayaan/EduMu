-- EduMU :: Report card assembly, comments and publication.
--
-- The report book is the artefact a school judges the whole system by. The
-- LAYOUT is deliberately not tested here — it lives in the print route and must
-- be replaced with a facsimile of the pilot school's existing book. What is
-- tested is the content and, above all, who may see it and when.
--
-- Every row must read PASS.

create temp table if not exists rp(test text, expected text, got text, pass boolean);
truncate rp;

do $$
declare
  v_school uuid; v_p uuid; v_g uuid; v_s uuid; v_t1 uuid;
  v_caps jsonb; v_ed_caps jsonb; n int; v_card jsonb; v_total int;
begin
  select id into v_school from school where code='DEMO-SSS';
  select id into v_p from person where email='a.ramdin@demo-sss.mu';
  select id into v_g from person where person_type='guardian' limit 1;
  select sg.student_id into v_s from student_guardian sg where sg.guardian_id=v_g limit 1;
  select t.id into v_t1 from term t join academic_year y on y.id=t.academic_year_id
   where y.name='2026' and t.sequence=1;
  select coalesce(jsonb_agg(distinct capability_code),'[]'::jsonb) into v_ed_caps
   from role_capability where role_code='educator';
  v_caps := v_ed_caps
            || jsonb_build_array('school.manage','marks.moderate','marks.publish','marks.read.all');

  update report_card set status='draft', published_at=null where term_id=v_t1;
  select count(*) into v_total from report_card where term_id=v_t1;

  -- Nothing reaches a parent before the Rector publishes.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from report_card;
  reset role;
  insert into rp values ('Guardian sees a draft report card','0',n::text,n=0);

  -- Separation of duties, again: the teacher who marked cannot release.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','educator','s','school')),
    'caps',  v_ed_caps)::text, true);
  set local role authenticated;
  begin perform rpc_publish_report_cards(v_t1); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into rp values ('Educator publishes report cards','raises (1)',n::text,n=1);

  set local role authenticated;
  begin perform rpc_set_report_comment(v_t1, v_s, 'rector', 'Nice work'); n := 0;
  exception when others then n := 1; end;
  reset role;
  insert into rp values ('Educator writes the Rector comment','raises (1)',n::text,n=1);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_p,'person_type','staff',
    'roles', jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',  v_caps)::text, true);
  set local role authenticated;
  select rpc_publish_report_cards(v_t1) into n;
  reset role;
  insert into rp values ('Rector publishes the term''s cards', v_total::text, n::text, n = v_total);

  select count(*) into n from notification where template='report_card.published';
  insert into rp values ('Responsible Parties queued a notification','>0',n::text,n>0);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',v_school,'person_id',v_g,'person_type','guardian',
    'roles', jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',  jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from report_card;
  select report_card_data(v_t1, v_s) into v_card;
  reset role;
  insert into rp values ('Guardian sees only their ward''s published card','1',n::text,n=1);
  insert into rp values ('Card carries subject lines','>0',
    jsonb_array_length(v_card->'subjects')::text,
    jsonb_array_length(v_card->'subjects') > 0);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from rp;
