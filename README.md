# EduMU

School management system for Mauritian secondary schools (Grades 7–13, NYCBE).

Full domain analysis and technical design: **[BLUEPRINT.md](./BLUEPRINT.md)**

Phase 0 + Phase 1 (attendance) are live. The database is real; the register screen
runs against it.

---

## What exists today

| Area | Status |
|---|---|
| Supabase project `edumu` (ap-south-1) | provisioned |
| Schema: school, calendar, structure, people, roles, timetable shell, attendance | applied (12 migrations) |
| RLS on every table, forced | applied and tested (7/7 passing) |
| Custom access-token hook packing `school_id`, roles and capabilities into the JWT | applied, enabled and verified |
| RPCs: calendar generation, register open/close/amend, closure declaration, summary recompute | applied |
| Seed: 2026 term dates, 15 Mauritian public holidays, demo school, 175 teaching days | applied |
| Vite + TS + Tailwind SPA, offline outbox, sync badge | scaffolded |
| Daily AM/PM register screen, calendar-aware | built |
| Lesson (period) attendance — the digital attendance card | built |
| Usher's discrepancy board, Realtime | built |
| Attendance summaries: trigger + nightly `pg_cron` rebuild | applied |
| Exam eligibility screening (80% rule) with recorded decisions | built |
| Assessment: scales, marks entry, moderation, publication, term aggregation | built |
| Documents & storage: 6 RLS-backed buckets, verification workflow | built |
| Option-block validation (NCE core + 4 electives, SC, HSC) | built |
| Absence notes: guardian submits, Form Teacher accepts, register rewritten | built |
| Guardian portal: wards, attendance, results, homework, notices | built |
| Conduct: incidents, merits, cases, escalation, append-only occurrence log | built |
| Curriculum: syllabus, schemes of work, weekly plans, homework, coverage | schema + RLS |
| Facilities, library, health, notices, circulars, correspondence, messaging | schema + RLS |
| **Timetable solver** — constraint solver, worker, cover board | built |
| Report card PDF layout | **blocked** — needs a scan of the pilot school's report book |
| SMS delivery | **blocked** — needs a Mauritian provider and sender ID |
| MES entry / results files | **blocked** — needs the real format spec |
| Attendance domain maths + unit tests | written (6 passing) |

## Project

```
Project ref   wdwtapdmdgdcvbifbeiz
API URL       https://wdwtapdmdgdcvbifbeiz.supabase.co
Region        ap-south-1 (Mumbai — closest Supabase region to Mauritius)
```

## Getting started

```bash
npm install
cd apps/web && cp .env.example .env     # already points at the project
npm run dev -w @edumu/web
```

Pull the applied migrations into the repo so git is the source of truth:

```bash
npx supabase login
npx supabase link --project-ref wdwtapdmdgdcvbifbeiz
npx supabase db pull                    # writes supabase/migrations/*.sql
npm run db:types                        # regenerates apps/web/src/types/database.ts
```

### The auth hook — enabled and verified

RLS depends on `school_id`, `person_id`, roles and capabilities being present in
the JWT. `app.custom_access_token_hook` is deployed and **enabled** under
Authentication → Hooks. Verified output for a seeded Form Teacher:

```json
{ "school_id": "afeaeeb4-…", "person_type": "staff",
  "roles": [{"c":"educator","s":"school"},
            {"c":"form_teacher","s":"class","id":"70743e99-…"}],
  "caps":  [ 5 capabilities ] }
```

Two design notes, both load-bearing:

- The hook is **SECURITY INVOKER**. Supabase Auth calls it as
  `supabase_auth_admin`, and the dashboard's picker only offers invoker
  functions — a definer hook would run with the owner's rights on every token
  mint. The privileged reads live in `app.build_claims`, which stays
  SECURITY DEFINER and is owned by `postgres`.
- The hook swallows its own exceptions and returns the event unchanged. A
  failure while building claims must never block sign-in; the user lands on the
  "not linked to a school" screen instead of a 500.

If you ever recreate the hook, re-run the grants:

```sql
grant usage   on schema app to supabase_auth_admin;
grant execute on function app.custom_access_token_hook(jsonb) to supabase_auth_admin;
grant execute on function app.build_claims(uuid)              to supabase_auth_admin;
revoke execute on function app.custom_access_token_hook(jsonb) from public, anon, authenticated;
```

### Creating your first user

```sql
-- After signing a user up through the app or the dashboard:
update person set auth_user_id = '<auth.users.id>'
where email = 'a.ramdin@demo-sss.mu';
```

The seed already includes two Educators who are Form Teachers of 7A and 7B, a
guardian, five students in 7A, and an open register for 13 January 2026.

## Layout

```
apps/web/            Vite + React + TypeScript SPA (PWA, offline-first)
  src/lib/           supabase client, offline outbox, query client, formatting
  src/features/      attendance (register screen, hooks, api)
  src/types/         database types
packages/domain/     pure business logic — attendance maths, tested
supabase/tests/      RLS behaviour tests
BLUEPRINT.md         the full analysis and plan
```

## Design rules

1. **The database is the API.** PostgREST plus RLS. Edge Functions only for
   third parties and long-running jobs.
2. **Nothing is authorised in the client.** Capabilities in the JWT decide what
   the UI offers; RLS decides what the database returns.
3. **Attendance is never deleted.** No DELETE policy exists. Post-close
   amendments go through `rpc_amend_attendance`, which demands a reason and
   writes to `audit_log`.
4. **Policy is data, not code.** Thresholds (80% exam eligibility, 75% second
   attempt, 10-day internal exam limit) live in `school.settings`. Grep for
   magic numbers in review.
5. **Offline is a requirement, not a nice-to-have.** Registers are taken in
   corridors. The outbox is in Phase 1 for that reason.

## Testing

```bash
npm test                        # domain logic — 6 passing
npm run typecheck
# RLS: run supabase/tests/*.sql against a branch
```

The RLS suite is the highest-value test in the project and should be a CI gate
before any migration merges. Current coverage:

| File | Asserts |
|---|---|
| `rls_attendance.sql` | Form Teacher scoping, students cannot read the class register, guardians see only their ward, attendance cannot be deleted, tenant isolation |
| `rls_discrepancy.sql` | Board is invisible to students and plain Educators, resolving needs `attendance.resolve`, outcomes are a closed set |
| `period_attendance_loop.sql` | Prefill is idempotent and silent, marking a pupil absent in a lesson raises a discrepancy that reaches the Usher, educators cannot mark sets they don't teach |
| `exam_eligibility.sql` | Summary arithmetic, debarring requires a reason and snapshots the figure, threshold is read from `school.settings`, guardians cannot screen |
| `marks_publication.sql` | Weighted aggregate matches the formula, guardians see nothing until published, the marking teacher cannot publish, amendments require a reason and land in `mark_history` |
| `_generated_parity.sql` | Generated — SQL and TypeScript attendance arithmetic agree on every fixture case |
| `phase1_completion.sql` | Accepted absence notes rewrite the register, option blocks validate, no tenant claim means no rows |
| `rls_messaging.sql` | Uninvolved staff cannot join or read a parent–teacher thread; participants can invite |

**Build capability sets in tests from `role_capability`, never by hand.**
`discrepancy_feed` is `security_invoker` and inner-joins `person` and `student`,
so a caller with `attendance.read.all` but without `person.read.all` /
`student.read.all` sees an **empty board rather than an error**. A hand-written
capability array in a test produces a false failure — which is how this was
found. Any new role that should see the board needs all three.

## Attendance arithmetic — two implementations, one fixture

The rules are subtle: three different denominators, depending on whether you are
applying the 80% exam rule, showing a guardian their child's attendance, or
computing scholarship eligibility "exclusive of authorised absences".

The **server is the authority** — eligibility is decided over RLS-protected data,
so it cannot be computed on the client. But the client needs the same maths for
display. Rather than let two implementations drift:

```
packages/domain/fixtures/attendance-cases.json     ← the single source of truth
   ├─ attendance.parity.test.ts        checks the TypeScript  (npm test)
   └─ scripts/gen-parity-sql.mjs  →  supabase/tests/_generated_parity.sql
                                        checks app.attendance_stats() in SQL
```

Add a case to the JSON and both implementations are checked against it.
CI regenerates the SQL suite and fails if the checked-in file is stale.

```bash
npm run gen:parity      # after editing the fixture
```

Verified: all 10 cases agree across both implementations, including the null
cases (a pupil whose absences are wholly authorised has an *undefined*
scholarship percentage, not 0%).

## Known warnings

Two remaining advisor warnings, both deliberate:

- **Signed-in users can execute SECURITY DEFINER functions** (7 RPCs). Intended:
  each re-checks `app.has_cap()` before doing anything, and needs definer rights
  to write across tables the caller cannot touch directly.
- **Leaked password protection disabled.** Worth enabling before any real pilot:
  Authentication → Providers → Password → "Prevent use of leaked passwords".

## Next

Phase 2 — assessment and report books. Before writing it, get a scan of the
pilot school's actual report book: matching their existing layout exactly is what
buys staff adoption. See §24 of the blueprint for the other open questions.
