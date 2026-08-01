# 2. Pack identity and capabilities into the JWT

**Status** Accepted · 2026-08-01

## Context
RLS predicates run on every row of every query. Resolving "is this person the
Form Teacher of this class?" by joining `staff_role_assignment` on each row
would make the register screen — the most-used surface in the product —
measurably slow.

## Decision
A custom access-token hook (`app.custom_access_token_hook`) packs `school_id`,
`person_id`, `person_type`, the active `year_id`, the role list with scope ids,
and the flattened capability set into every JWT. RLS helpers read only from the
claims, so they are cheap and `stable`.

## Consequences
- Role changes take effect on the next token refresh, not instantly. Acceptable:
  role changes are administrative, not urgent.
- The hook is `SECURITY INVOKER` — Auth calls it as `supabase_auth_admin`, and
  the dashboard only offers invoker functions. Privileged reads live in
  `app.build_claims`, which is `SECURITY DEFINER`.
- The hook swallows its own exceptions and returns the event unchanged. A bug
  in claim building must never block sign-in for the whole school.
- Tests must build capability sets from `role_capability`, never by hand.
