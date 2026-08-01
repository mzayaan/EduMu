# EduMU

School management system for Mauritian secondary schools (Grades 7–13, NYCBE).

Full domain analysis and technical design: **[BLUEPRINT.md](./BLUEPRINT.md)**

Current state and honest percentages: **[STATUS.md](./STATUS.md)** ·
Handover commands: **[SETUP.md](./SETUP.md)**

Roughly 92% of the blueprint is built — 101 tables, 201 RLS policies,
48 migrations, 15 screens, 14 SQL suites. Against "a school could run on this
in January", closer to 45%: everything so far has met five pupils and synthetic
marks, not 900 pupils and 60 staff.

---

## What exists today

| Area | Status |
|---|---|
| Supabase project `edumu` (ap-south-1) | 48 migrations, 101 tables, 6 views |
| RLS on every table, forced | 201 policies · **0 tables without one** |
| Custom access-token hook | applied, enabled, verified |
| Attendance: registers, lessons, discrepancies, absence notes, summaries | complete |
| Assessment: marks, moderation, publication, term results, report books | complete |
| Report book | designed in-house — per-assessment columns incl. mocks |
| Timetable | solver (47 ms for 24 classes), grid, daily cover |
| Examinations | papers, seating strategies, invigilation, eligibility screening |
| Conduct, pastoral, committees, occurrence log | built |
| Curriculum: schemes of work, weekly plans, coverage, homework | built |
| Facilities, library, health, notices, mail register | built |
| Analytics, dashboards, Ministry return | built |
| Multi-tenancy: provisioning, platform console, zone oversight | built |
| Guardian portal | built |
| Drag-and-drop timetable editing, committee screens, analytics charts | not built |
| SMS delivery | **blocked** — needs a Mauritian provider and sender ID |
| MES entry / results files | **blocked** — needs the real format spec |

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
  src/features/      15 feature folders — attendance, marks, reports, timetable,
                     exams, conduct, curriculum, admin, guardian, platform, …
  src/workers/       timetable solver (runs off the main thread)
packages/domain/     pure logic — attendance maths and the timetable solver
scripts/             verify, SQL runner, parity generator, solver benchmark
supabase/tests/      14 SQL suites — RLS and workflow behaviour
docs/adr/            5 architecture decision records
BLUEPRINT.md         the full domain analysis and plan
STATUS.md            what is and is not done
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

There is deliberately **no CI**: `supabase start` pulls several GB of Docker
images per run, which is not worth it for this project. Verification runs
locally instead.

```bash
npm run verify              # typecheck + unit tests + parity freshness
npm run verify -- --sql     # also the SQL suites (needs DATABASE_URL)
```

**Run it before you commit.** Nothing enforces that — the trade for not paying
for CI is that a regression can reach main if nobody runs it. The SQL suites
mutate data, so point `DATABASE_URL` at a **branch**, never production
(Supabase dashboard → Project Settings → Database → Connection string).

The RLS suites are the highest-value tests in the project. Current coverage:

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
