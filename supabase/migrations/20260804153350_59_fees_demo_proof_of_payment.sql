/*
 * EduMU :: 59 School fees — DEMONSTRATION ONLY.
 *
 * ┌────────────────────────────────────────────────────────────────────────┐
 * │ THIS DOES NOT PROCESS PAYMENTS AND MUST NOT BE USED TO.                │
 * │                                                                        │
 * │ No card data, no bank API, no payment gateway, no settlement, no       │
 * │ refunds, no reconciliation against a bank statement. Money never       │
 * │ touches this system.                                                   │
 * │                                                                        │
 * │ The model is the one Mauritian schools actually use: the guardian pays │
 * │ by MCB Juice to the school's own account, screenshots the             │
 * │ confirmation, and uploads it. A human at the school opens the bank    │
 * │ app, checks the money arrived, and marks it verified. The system is a │
 * │ filing cabinet for that conversation, not a payment processor.        │
 * │                                                                        │
 * │ Before any real use this needs: reconciliation against bank           │
 * │ statements, a refund path, an immutable ledger, dual authorisation on │
 * │ write-offs, and an accountant's review. None of that is here.         │
 * └────────────────────────────────────────────────────────────────────────┘
 *
 * Built because `bursar` existed as a role with capabilities and nothing to
 * do, which is worse than either building fees or writing down that they live
 * elsewhere.
 */

create type fee_payment_method as enum
  ('mcb_juice', 'bank_transfer', 'cash', 'cheque', 'waiver');

create type fee_payment_status as enum
  ('awaiting_verification', 'verified', 'rejected');

-- ── what the school charges ───────────────────────────────────────────────
create table fee_structure (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references school on delete cascade,
  academic_year_id uuid not null references academic_year on delete cascade,
  -- null grade = charged to every pupil in the school
  grade            smallint,
  name             text not null,
  description      text,
  amount           numeric(10,2) not null check (amount >= 0),
  currency         text not null default 'MUR',
  due_on           date,
  -- A voluntary contribution must never produce a debt a pupil is chased for.
  is_mandatory     boolean not null default true,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (academic_year_id, grade, name)
);
create index on fee_structure (school_id, academic_year_id);

comment on table fee_structure is
  'DEMO. What the school charges, per year and optionally per grade. State '
  'schools in Mauritius are free; this matters for grant-aided and private.';

alter table fee_structure enable row level security;
alter table fee_structure force  row level security;

-- Guardians need to see what is charged before it is charged to them.
create policy fs_read on fee_structure for select to authenticated
using (school_id = app.school_id());

create policy fs_write on fee_structure for all to authenticated
using (school_id = app.school_id() and app.has_cap('school.manage'))
with check (school_id = app.school_id() and app.has_cap('school.manage'));

create trigger audit_fee_structure
  after insert or update or delete on fee_structure
  for each row execute function app.audit_row();

-- ── what a particular pupil owes ──────────────────────────────────────────
create table fee_charge (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references school on delete cascade,
  academic_year_id uuid not null references academic_year on delete cascade,
  student_id       uuid not null references student on delete cascade,
  fee_structure_id uuid references fee_structure on delete set null,
  description      text not null,
  amount           numeric(10,2) not null check (amount >= 0),
  due_on           date,
  -- Set by the Rector, not earned by non-payment. A waiver is a decision about
  -- a family's circumstances and it needs a reason on the record.
  waived           boolean not null default false,
  waived_reason    text,
  waived_by        uuid references staff,
  created_at       timestamptz not null default now(),
  unique (student_id, fee_structure_id),
  constraint waiver_needs_a_reason
    check (not waived or nullif(trim(waived_reason), '') is not null)
);
create index on fee_charge (school_id, academic_year_id);
create index on fee_charge (student_id);

alter table fee_charge enable row level security;
alter table fee_charge force  row level security;

-- A family sees only their own charges. This is money and it is nobody else's
-- business — the same rule as marks, for the same reason.
create policy fc_read on fee_charge for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('school.manage')
            or app.is_guardian_of(student_id)
            or student_id = app.person_id()));

create policy fc_write on fee_charge for all to authenticated
using (school_id = app.school_id() and app.has_cap('school.manage'))
with check (school_id = app.school_id() and app.has_cap('school.manage'));

create trigger audit_fee_charge
  after insert or update or delete on fee_charge
  for each row execute function app.audit_row();

-- ── what was paid, and the screenshot that says so ────────────────────────
create table fee_payment (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references school on delete cascade,
  student_id     uuid not null references student on delete cascade,
  fee_charge_id  uuid references fee_charge on delete set null,
  amount         numeric(10,2) not null check (amount > 0),
  paid_on        date not null,
  method         fee_payment_method not null default 'mcb_juice',
  -- The MCB Juice transaction reference the guardian reads off their receipt.
  -- Free text on purpose: it is evidence for a human, not a key we resolve.
  reference      text,
  -- Storage path of the uploaded screenshot, under {school_id}/fees/…
  proof_path     text,
  status         fee_payment_status not null default 'awaiting_verification',
  submitted_by   uuid references person,
  submitted_at   timestamptz not null default now(),
  verified_by    uuid references staff,
  verified_at    timestamptz,
  -- Why a payment was rejected. The guardian is shown this, so it has to be
  -- something a person can act on.
  decision_note  text,
  constraint rejection_needs_a_note
    check (status <> 'rejected' or nullif(trim(decision_note), '') is not null)
);
create index on fee_payment (school_id, status);
create index on fee_payment (student_id);

comment on table fee_payment is
  'DEMO. A record that a guardian says they paid, plus a screenshot. '
  'Verification is a human opening the bank app. Nothing here moves money or '
  'confirms that money moved.';

alter table fee_payment enable row level security;
alter table fee_payment force  row level security;

create policy fp_read on fee_payment for select to authenticated
using (school_id = app.school_id()
       and (app.has_cap('school.manage')
            or app.is_guardian_of(student_id)
            or student_id = app.person_id()));

-- A guardian may submit a payment claim for their own ward, and only in the
-- awaiting state. They cannot mark their own payment verified — that is the
-- entire control in this design, so it lives in the database.
create policy fp_submit on fee_payment for insert to authenticated
with check (school_id = app.school_id()
            and app.is_guardian_of(student_id)
            and status = 'awaiting_verification'
            and submitted_by = app.person_id());

create policy fp_manage on fee_payment for all to authenticated
using (school_id = app.school_id() and app.has_cap('school.manage'))
with check (school_id = app.school_id() and app.has_cap('school.manage'));

create trigger audit_fee_payment
  after insert or update or delete on fee_payment
  for each row execute function app.audit_row();

-- ── storage for the proof screenshots ─────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fee-proofs', 'fee-proofs', false, 5242880,
        array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict (id) do nothing;

-- Path convention {school_id}/fees/{student_id}/… so the existing helpers work.
create policy "fee proof read" on storage.objects for select to authenticated
using (bucket_id = 'fee-proofs' and app.storage_school(name) = app.school_id());

create policy "fee proof upload" on storage.objects for insert to authenticated
with check (bucket_id = 'fee-proofs' and app.storage_school(name) = app.school_id());

-- ── raising the charges ───────────────────────────────────────────────────
create or replace function public.rpc_generate_fee_charges(p_year uuid)
returns integer
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_rows int;
begin
  if not app.has_cap('school.manage') then
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
    -- A null grade on the structure means every pupil.
    and (fs.grade is null or fs.grade = gl.grade)
  on conflict (student_id, fee_structure_id) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows;
end $$;

/*
 * A guardian records that they paid.
 *
 * Deliberately NOT a payment. It creates a claim in `awaiting_verification`
 * and nothing else happens until a human at the school confirms the money
 * arrived. The RLS policy above already prevents a guardian setting any other
 * status; this RPC exists to attach the proof and validate the ward in one
 * place.
 */
create or replace function public.rpc_submit_fee_payment(
  p_student uuid, p_charge uuid, p_amount numeric, p_paid_on date,
  p_method fee_payment_method default 'mcb_juice',
  p_reference text default null, p_proof_path text default null
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_school uuid; v_id uuid;
begin
  if not (app.is_guardian_of(p_student) or app.has_cap('school.manage')) then
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

/*
 * The Bursar opens the bank app, sees the money, and says so.
 *
 * This is the only step that means anything financially, and it is a human
 * decision recorded by a human. Rejection demands a note because the guardian
 * is shown it and has to be able to act on it.
 */
create or replace function public.rpc_verify_fee_payment(
  p_payment uuid, p_verified boolean, p_note text default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.has_cap('school.manage') then
    raise exception 'Only the office may verify a payment';
  end if;
  if not p_verified and nullif(trim(coalesce(p_note, '')), '') is null then
    raise exception 'Rejecting a payment needs a note the guardian can act on';
  end if;

  update fee_payment
     set status = case when p_verified then 'verified' else 'rejected' end,
         verified_by = app.person_id(), verified_at = now(),
         decision_note = p_note
   where id = p_payment and school_id = app.school_id();

  if not found then raise exception 'Unknown payment'; end if;
end $$;

create or replace function public.rpc_waive_fee(
  p_charge uuid, p_reason text
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.has_cap('school.manage') then
    raise exception 'Not authorised to waive a fee';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A waiver needs a reason';
  end if;
  update fee_charge
     set waived = true, waived_reason = p_reason, waived_by = app.person_id()
   where id = p_charge and school_id = app.school_id();
  if not found then raise exception 'Unknown charge'; end if;
end $$;

/*
 * What a family owes.
 *
 * Only VERIFIED payments reduce the balance. A pending claim is shown
 * separately so a guardian can see the school has it, without the balance
 * moving before anyone has checked the money arrived.
 */
create or replace view fee_statement
with (security_invoker = true) as
select
  fc.id as charge_id, fc.school_id, fc.academic_year_id, fc.student_id,
  p.first_name, p.last_name, s.admission_number,
  fc.description, fc.amount, fc.due_on, fc.waived, fc.waived_reason,
  coalesce((select sum(fp.amount) from fee_payment fp
            where fp.fee_charge_id = fc.id and fp.status = 'verified'), 0) as paid,
  coalesce((select sum(fp.amount) from fee_payment fp
            where fp.fee_charge_id = fc.id and fp.status = 'awaiting_verification'), 0)
    as pending,
  case when fc.waived then 0
       else greatest(0, fc.amount - coalesce((select sum(fp.amount) from fee_payment fp
              where fp.fee_charge_id = fc.id and fp.status = 'verified'), 0))
  end as balance
from fee_charge fc
join student s on s.id = fc.student_id
join person  p on p.id = s.id;

grant select on fee_statement to authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'public.rpc_generate_fee_charges(uuid)',
    'public.rpc_submit_fee_payment(uuid, uuid, numeric, date, fee_payment_method, text, text)',
    'public.rpc_verify_fee_payment(uuid, boolean, text)',
    'public.rpc_waive_fee(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
