-- EduMU :: 60 `case when ... then 'verified' else 'rejected' end` produces text,
-- and fee_payment.status is an enum. Postgres will not coerce it.
--
-- Third time this exact shape has bitten this project (rpc_review_scheme and
-- rpc_decide_eligibility before it). The rule: any CASE whose result lands in
-- an enum column needs the cast written on it, because the literal branches
-- are untyped and PL/pgSQL will not infer from the target.
--
-- It survived the first test pass because the guardian-path assertions all
-- expected a refusal, so nothing reached the successful verify until an
-- office-role test ran it.

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
     set status = (case when p_verified then 'verified' else 'rejected' end)::fee_payment_status,
         verified_by = app.person_id(), verified_at = now(),
         decision_note = p_note
   where id = p_payment and school_id = app.school_id();

  if not found then raise exception 'Unknown payment'; end if;
end $$;

revoke all on function public.rpc_verify_fee_payment(uuid, boolean, text) from public, anon;
grant execute on function public.rpc_verify_fee_payment(uuid, boolean, text) to authenticated;
