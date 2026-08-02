-- EduMU :: Committees, meetings and actions arising.
--
-- The School Management Manual makes committees structural rather than ad hoc,
-- expects several to meet at least twice a term, and specifically requires the
-- Pastoral Care Committee to include a parent — "not necessarily a member of
-- the PTA Executive Committee". So membership must accept a guardian, not only
-- staff, and that is asserted here.
--
-- The part that decides whether any of it matters is the action list: minutes
-- without follow-up are decoration. Actions carry an owner and a date, appear
-- in that person's own list, and feed the Rector's overdue count.
--
-- SCOPE YOUR ASSERTIONS TO A SCHOOL. An earlier version asserted "9 committees"
-- and got 18 — nine per tenant across two tenants. Correct behaviour, wrong
-- assertion. Anything counted without a school filter, or run outside an
-- impersonated role, sees every tenant.
--
-- Every row must read PASS.

create temp table if not exists cm(test text, expected text, got text, pass boolean);
truncate cm;

do $$
declare
  sch uuid; ed uuid; g uuid; caps_rec jsonb;
  v_pastoral uuid; v_meet uuid; v_act uuid; n int; after_n int;
begin
  select id into sch from school where code='DEMO-SSS';
  select id into ed  from person where email='a.ramdin@demo-sss.mu';
  select id into g   from person where person_type='guardian' limit 1;
  select coalesce(jsonb_agg(distinct capability_code),'[]') into caps_rec
   from role_capability where role_code='rector';
  select id into v_pastoral from committee
   where code='pastoral' and school_id = sch;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',ed,'person_type','staff',
    'roles',jsonb_build_array(jsonb_build_object('c','rector','s','school')),
    'caps',caps_rec)::text, true);

  select count(*) into n from committee where school_id = sch;
  insert into cm values ('Standing committees seeded for this school','9',n::text,n=9);

  -- A parent must be able to sit on the Pastoral Care Committee.
  insert into committee_member (committee_id, person_id, role_in_committee)
  values (v_pastoral, g, 'Parent representative') on conflict do nothing;
  insert into committee_member (committee_id, person_id, role_in_committee)
  values (v_pastoral, ed, 'Convenor') on conflict do nothing;

  select count(*) into n from committee_member cmb
   join person p on p.id = cmb.person_id
   where cmb.committee_id = v_pastoral and p.person_type = 'guardian';
  insert into cm values ('A parent can sit on the Pastoral Care Committee','1',n::text,n=1);

  -- A meeting with minutes and an action arising.
  select id into v_meet from meeting
   where committee_id = v_pastoral and title = 'Pastoral Care — Term 2 review';
  if v_meet is null then
    insert into meeting (school_id, kind, committee_id, title, held_on, venue, agenda, chaired_by)
    values (sch,'committee',v_pastoral,'Pastoral Care — Term 2 review',
            '2026-06-10 09:00+04','Rector''s office','Review of at-risk pupils', ed)
    returning id into v_meet;
  end if;

  update meeting
     set minutes = 'Four pupils reviewed. Two referred to the Zone Educational '
                || 'Psychologist with written parental consent.'
   where id = v_meet;

  select id into v_act from action_item
   where meeting_id = v_meet and description like 'Obtain written consent%';
  if v_act is null then
    insert into action_item (school_id, meeting_id, description, owner_person_id, due_on)
    values (sch, v_meet, 'Obtain written consent from both Responsible Parties',
            ed, '2026-06-17')
    returning id into v_act;
  else
    update action_item set status='open', completed_on=null where id = v_act;
  end if;

  select count(*) into n from action_item
   where meeting_id = v_meet and status='open';
  insert into cm values ('Action recorded against the meeting','1',n::text,n=1);

  set local role authenticated;
  select count(*) into n from action_item
   where owner_person_id = ed and status='open';
  reset role;
  insert into cm values ('Action appears in the owner''s list','>0',n::text,n>0);

  -- Overdue actions surface on the Rector's dashboard, and clear when done.
  set local role authenticated;
  select (school_dashboard('2026-06-30')->>'overdue_actions')::int into n;
  reset role;
  insert into cm values ('Overdue action reaches the dashboard','>0',n::text,n>0);

  update action_item set status='done', completed_on=current_date where id = v_act;
  set local role authenticated;
  select (school_dashboard('2026-06-30')->>'overdue_actions')::int into after_n;
  reset role;
  insert into cm values ('Completing it clears the overdue count',
                         (n-1)::text, after_n::text, after_n = n - 1);

  -- Internal minutes are not for parents. Pastoral discussion names children.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'school_id',sch,'person_id',g,'person_type','guardian',
    'roles',jsonb_build_array(jsonb_build_object('c','guardian','s','ward')),
    'caps',jsonb_build_array())::text, true);
  set local role authenticated;
  select count(*) into n from meeting;
  reset role;
  insert into cm values ('Guardian reads internal meeting minutes','0',n::text,n=0);

  -- ...even though that same guardian sits on the committee.
  set local role authenticated;
  select count(*) into n from committee_member where person_id = g;
  reset role;
  insert into cm values ('Committee membership is visible to the member','>0',n::text,n>0);
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from cm;
