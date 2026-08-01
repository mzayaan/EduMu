# 1. The database is the API

**Status** Accepted · 2026-08-01

## Context
EduMU holds children's attendance, marks, medical notes and discipline records.
Access rules are genuinely row-shaped: "my class", "my sets", "my ward", "my own
record". They are also many — a person holds several scoped roles at once.

## Decision
PostgREST over Postgres, with Row Level Security as the only authorisation
mechanism. Edge Functions exist solely for work Postgres should not do: talking
to third parties (SMS, email, MES file formats) and long-running orchestration.

No authorisation logic in the client. Capabilities in the JWT decide what the UI
*offers*; RLS decides what the database *returns*. The two are allowed to
disagree, and when they do, RLS wins.

## Consequences
- A UI bug cannot leak data. The worst case is a button that errors.
- Access rules are testable without a running app — see `supabase/tests/`.
- Views must be `security_invoker`, or they become a hole around RLS.
- Multi-table writes need `SECURITY DEFINER` RPCs that re-check capabilities.
  This trips the Supabase advisor; it is intentional and documented.
- **Trap discovered in practice:** a `security_invoker` view that inner-joins
  `person`/`student` silently returns zero rows to a caller lacking
  `person.read.all`. Safe, but confusing. Documented on `discrepancy_feed`.
