/*
 * EduMU :: 62 Give the Bursar, Librarian and Lab Technician something to do.
 *
 * Found by creating a login for every role for the first time. Five roles
 * existed in the taxonomy with ZERO capabilities — bursar, librarian, lab_tech,
 * student, guardian — so signing in as any of them produced an empty shell.
 *
 * The Bursar was the worst of it: fees are that post's entire job, and the fees
 * module gated every write on `school.manage`, which a Bursar does not have and
 * should not have. A Bursar who could edit fees could also republish the
 * timetable.
 *
 * Nothing had caught this because the system only ever had one login, holding
 * four roles at once. A role taxonomy is untested until somebody signs in as
 * each of them.
 *
 * `student` and `guardian` stay capability-free on purpose: their access is
 * relationship-based, decided by app.is_guardian_of() and
 * `student_id = app.person_id()` inside the policies, not by a capability. The
 * fix for those is routing, not permissions.
 */

insert into capability (code, description) values
  ('fees.manage',   'Raise fee charges, verify payments, and waive fees'),
  ('library.manage','Catalogue library items and manage loans'),
  ('assets.manage', 'Maintain the asset register and handle maintenance requests')
on conflict (code) do nothing;

insert into role_capability (role_code, capability_code) values
  -- The Bursar's actual job, and nothing else. Explicitly NOT school.manage.
  ('bursar', 'fees.manage'),
  ('bursar', 'person.read.all'),
  ('bursar', 'student.read.all'),

  ('librarian', 'library.manage'),
  ('librarian', 'student.read.all'),

  ('lab_tech', 'assets.manage'),

  -- Posts that already hold school.manage get these explicitly too, so a
  -- future decision to narrow school.manage does not silently remove them.
  ('rector', 'fees.manage'),
  ('rector', 'library.manage'),
  ('rector', 'assets.manage'),
  ('deputy_rector', 'fees.manage'),
  ('school_admin', 'fees.manage'),
  ('school_admin', 'library.manage'),
  ('school_admin', 'assets.manage')
on conflict do nothing;

-- ── policies accept the specific capability OR school.manage ─────────────
-- school.manage is kept so nothing that works today stops working. The narrow
-- capability is what a single-purpose post gets.

drop policy if exists fs_write on fee_structure;
create policy fs_write on fee_structure for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')));

drop policy if exists fc_write on fee_charge;
create policy fc_write on fee_charge for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')));

drop policy if exists fp_manage on fee_payment;
create policy fp_manage on fee_payment for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('fees.manage') or app.has_cap('school.manage')));

drop policy if exists li_write on library_item;
create policy li_write on library_item for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('library.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('library.manage') or app.has_cap('school.manage')));

drop policy if exists ll_write on library_loan;
create policy ll_write on library_loan for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('library.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('library.manage') or app.has_cap('school.manage')));

drop policy if exists asset_write on asset;
create policy asset_write on asset for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('assets.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('assets.manage') or app.has_cap('school.manage')));

drop policy if exists maintenance_request_write on maintenance_request;
create policy maintenance_request_write on maintenance_request for all to authenticated
using (school_id = app.school_id()
       and (app.has_cap('assets.manage') or app.has_cap('school.manage')))
with check (school_id = app.school_id()
       and (app.has_cap('assets.manage') or app.has_cap('school.manage')));

-- ── the fee RPCs must agree with the policies ────────────────────────────
create or replace function public.rpc_generate_fee_charges(p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_rows int;
begin
  if not (app.has_cap('fees.manage') or app.has_cap('school.manage')) then
    raise exception 'Not authorised to raise fee charges';
  end if;
  select y.school_id into v_school from academic_year y where y.id = p_year;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown academic year';
  end if;

  insert into fee_charge (school_id, academic_year_id, student_id,
                          fee_structure_id, description, amount, due_on)
  select v_school, p_year, st.id, fs.id, fs.name, fs.amount, fs.due_on
  from fee_structure fs
  join class_enrolment ce on ce.effective_to is null
  join class_group cg on cg.id = ce.class_group_id and cg.academic_year_id = p_year
  join grade_level gl on gl.id = cg.grade_level_id
  join student st on st.id = ce.student_id and st.status = 'enrolled'
  where fs.academic_year_id = p_year
    and fs.is_active
    and (fs.grade is null or fs.grade = gl.grade)
  on conflict (student_id, fee_structure_id) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

create or replace function public.rpc_verify_fee_payment(
  p_payment uuid, p_verified boolean, p_note text default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.has_cap('fees.manage') or app.has_cap('school.manage')) then
    raise exception 'Only the office may verify a payment';
  end if;
  if not p_verified and nullif(trim(coalesce(p_note, '')), '') is null then
    raise exception 'Rejecting a payment needs a note the guardian can act on';
  end if;

  update fee_payment
     set status = (case when p_verified then 'verified' else 'rejected' end)::fee_payment_status,
         verified_by = app.person_id(), verified_at = now(),
         decision_note = p_note
   where id = p_payment and school_id = app.school_id();

  if not found then raise exception 'Unknown payment'; end if;
end $$;

create or replace function public.rpc_waive_fee(p_charge uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  -- A waiver forgives money owed, so it stays with the office rather than the
  -- Bursar who processes payments. Separation of duties, deliberately.
  if not app.has_cap('school.manage') then
    raise exception 'Only the Rector or school administration may waive a fee';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A waiver needs a reason';
  end if;
  update fee_charge
     set waived = true, waived_reason = p_reason, waived_by = app.person_id()
   where id = p_charge and school_id = app.school_id();
  if not found then raise exception 'Unknown charge'; end if;
end $$;

-- The guardian submit path must not accidentally admit a Bursar acting as a
-- parent — keep it to guardians and the office.
create or replace function public.rpc_submit_fee_payment(
  p_student uuid, p_charge uuid, p_amount numeric, p_paid_on date,
  p_method fee_payment_method default 'mcb_juice',
  p_reference text default null, p_proof_path text default null
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_id uuid;
begin
  if not (app.is_guardian_of(p_student)
          or app.has_cap('fees.manage') or app.has_cap('school.manage')) then
    raise exception 'You may only record a payment for your own child';
  end if;
  select s.school_id into v_school from student s where s.id = p_student;
  if v_school is null or v_school <> app.school_id() then
    raise exception 'Unknown pupil';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount must be more than zero';
  end if;
  if p_paid_on > current_date then
    raise exception 'A payment cannot be dated in the future';
  end if;

  insert into fee_payment (school_id, student_id, fee_charge_id, amount, paid_on,
                           method, reference, proof_path, status, submitted_by)
  values (v_school, p_student, p_charge, p_amount, p_paid_on,
          p_method, nullif(trim(p_reference), ''), p_proof_path,
          'awaiting_verification', app.person_id())
  returning id into v_id;

  return v_id;
end $$;
