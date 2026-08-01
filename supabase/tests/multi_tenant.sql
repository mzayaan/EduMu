-- EduMU :: Multi-tenancy — provisioning, isolation, zone oversight.
--
-- IMPORTANT when writing role tests: impersonate an identity that has NO other
-- legitimate grant. An earlier version of this suite used a Zone Director claim
-- attached to a teacher's person_id, and reported a leak — the pupils were
-- visible because that person genuinely teaches them, which is correct
-- behaviour. Use a clean identity or you cannot tell a hole from a grant.
--
-- Every row must read PASS.

create temp table if not exists mt(test text, expected text, got text, pass boolean);
truncate mt;

do $$
declare
  sch uuid; ed uuid; zoff uuid; new_school uuid;
  caps_rec jsonb; caps_plat jsonb; caps_zone jsonb; n int;
begin
  select id into sch from school where code='DEMO-SSS';
  select id into ed  from person where email='a.ramdin@demo-sss.mu';
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps_rec
   from role_capability where role_code='rector';
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps_plat
   from role_capability where role_code='super_admin';
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps_zone
   from role_capability where role_code='zone_officer';

  -- Creating a tenant is a platform act, not a school one.
  perform set_config('request.jwt.claims', jsonb_build_object('school_id',sch,'person_id',ed,
    'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',caps_rec)::text, true);
  set local role authenticated;
  begin perform rpc_provision_school('X1','Test','state',2::smallint,null,null); n:=0;
  exception when others then n:=1; end;
  reset role;
  insert into mt values ('Rector provisions a school','raises (1)',n::text,n=1);

  select id into new_school from school where code='QB-SSS';
  if new_school is null then
    perform set_config('request.jwt.claims', jsonb_build_object('school_id',sch,'person_id',ed,
      'person_type','staff',
      'roles',jsonb_build_array(jsonb_build_object('c','super_admin','s','school')),
      'caps',caps_plat)::text, true);
    set local role authenticated;
    select rpc_provision_school('QB-SSS','Quatre Bornes SSS','state',2::smallint,'2026',
      jsonb_build_array(
        jsonb_build_object('name','First Term','starts_on','2026-01-12','ends_on','2026-04-03'),
        jsonb_build_object('name','Second Term','starts_on','2026-04-20','ends_on','2026-07-17'),
        jsonb_build_object('name','Third Term','starts_on','2026-08-17','ends_on','2026-10-30'))
    ) into new_school;
    reset role;
  end if;
  insert into mt values ('Platform admin provisions a school','not null',
                         case when new_school is null then 'null' else 'ok' end,
                         new_school is not null);

  -- A tenant is useless half-created, so provisioning is one transaction.
  select count(*) into n from grade_level where school_id = new_school;
  insert into mt values ('Grades 7-13 with legacy Form names','7',n::text,n=7);
  select count(*) into n from term where school_id = new_school;
  insert into mt values ('Terms created','3',n::text,n=3);
  select count(*) into n from calendar_day
   where school_id = new_school and day_type='teaching';
  insert into mt values ('Calendar expanded, holidays removed','175',n::text,n=175);
  select count(*) into n from committee where school_id = new_school;
  insert into mt values ('Standing committees seeded','9',n::text,n=9);
  select count(*) into n from occurrence_log
   where school_id = new_school and category='platform';
  insert into mt values ('Provisioning recorded in the occurrence log','1',n::text,n=1);

  -- Tenant isolation.
  perform set_config('request.jwt.claims', jsonb_build_object('school_id',new_school,
    'person_id',ed,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',caps_rec)::text, true);
  set local role authenticated;
  select count(*) into n from student;
  reset role;
  insert into mt values ('New tenant sees the other school''s pupils','0',n::text,n=0);

  -- Zone oversight is AGGREGATE ONLY. Clean identity: no teaching, no form class.
  select id into zoff from person where email='r.bhugaloo@zone2.govmu';
  if zoff is null then
    insert into person (school_id, person_type, first_name, last_name, email)
    values (sch,'staff','Rajesh','Bhugaloo','r.bhugaloo@zone2.govmu') returning id into zoff;
    insert into staff (id, school_id, staff_number, post)
    values (zoff, sch, 'ZONE-01', 'Zone Director');
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('school_id',sch,
    'person_id',zoff,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','zone_officer','s','school')),
    'caps',caps_zone)::text, true);

  set local role authenticated;
  select count(*) into n from student;
  reset role;
  insert into mt values ('Zone Director reads named pupils','0',n::text,n=0);

  set local role authenticated;
  select count(*) into n from attendance_record;
  reset role;
  insert into mt values ('Zone Director reads attendance','0',n::text,n=0);

  set local role authenticated;
  select count(*) into n from mark;
  reset role;
  insert into mt values ('Zone Director reads marks','0',n::text,n=0);

  set local role authenticated;
  select count(*) into n from report_card;
  reset role;
  insert into mt values ('Zone Director reads report cards','0',n::text,n=0);

  set local role authenticated;
  select count(*) into n from platform_overview();
  reset role;
  insert into mt values ('Zone Director sees the zone aggregate','2',n::text,n=2);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from mt;
