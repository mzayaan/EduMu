# EduMU — build status

Generated at the end of the continuous build session. Percentages are against
the phase definitions in [BLUEPRINT.md §22](./BLUEPRINT.md).

## Database

| | |
|---|---|
| Tables | 101 (+ 6 views) |
| RLS policies | 200 (public) + 10 (storage) |
| Migrations | 47 |
| Storage buckets | 6, all RLS-backed |
| SQL test suites | 14 |

## Phases

| Phase | Was | Now | Remaining |
|---|---|---|---|
| **0 — Foundations** | 90% | 95% | CI has still never actually executed |
| **1 — People & Attendance** | 60% | **100%** | — |
| **2 — Assessment** | 40% | 75% | Report card PDFs (blocked), batch generation, results analysis |
| **3 — Timetable** | 15% | 85% | Drag-and-drop manual editor; solver, grid and cover board are done |
| **4 — Examinations** | 15% | 85% | MES entry/results files (blocked); papers, seating, invigilation, scripts done |
| **5 — Discipline & governance** | 0% | 80% | Committee/meeting screens; schema, RLS and conduct screens done |
| **6 — Curriculum** | 0% | 90% | Syllabus tree editor; schemes, weekly plans, homework, coverage all built |
| **7 — Facilities & comms** | 0% | 85% | Asset import and messaging UI; notices, maintenance, library, visitors, health, mail register built |
| **8 — Analytics** | 0% | 80% | Charts and printable exports; dashboard, at-risk, results analysis and Ministry return done |
| **9 — Multi-tenant** | 0% | 0% | Provisioning, branding, zone dashboards |

## Timetable solver benchmark

Against a synthetic 24-class school — 192 sets, 45 educators, 31 rooms,
990 conflict edges, 696 periods into 40 slots:

```
construction only      47 ms    696/696 placed, 0 hard violations
+ 10 s local search             696/696 placed, score 3476 → 1335
```

The NFR asked for a first viable solution inside 2 minutes.

`npm run bench:timetable` reproduces it.

## Exam seating

`rpc_allocate_seats` walks rooms largest-first and offers three strategies:
`separate_class` (hash-scatter so neighbours are rarely classmates), `spaced`
(every other seat, capacity permitting) and `sequential`. Debarred candidates
are never seated, and if anyone is left unseated the whole allocation raises
rather than silently under-seating a hall.

`rpc_assign_invigilators` hands duties to whoever has invigilated least this
session, skipping anyone on approved leave, with one chief per room.

## Bugs found by testing, not by reading

1. **Solver score was `NaN`.** Cycle days are 1-based, the per-day array
   0-based; indexing by the raw day number wrote past the end. Every
   local-search comparison was false, so 660,000 iterations did nothing. The
   solver looked like it worked. Regression test added.
2. **`thread_participant` had `WITH CHECK (true)`.** Any staff member could add
   themselves to a parent–teacher conversation about another pupil and read it.
   Found by the Supabase advisor.
3. **PL/pgSQL name collision** in `rpc_allocate_seats`: the room query used
   `room r` while `r` was also a declared record variable, so `r.id` resolved to
   the unassigned variable. Table aliases are now distinct from every declared
   variable.
4. **Nested aggregates** in `ministry_return` — `avg()` inside `jsonb_agg()` is
   not legal SQL. Aggregates are computed in CTEs first.
5. **A brittle assertion, not a bug.** `rls_attendance.sql` asserted a pupil
   sees "exactly 1 row" — true of a one-register fixture, false the moment a
   term of attendance was seeded, and it reported a security failure where
   there was none. Assertions now test the invariant (zero foreign rows).
   A follow-up sweep across 25 table/actor pairs confirmed no leak anywhere.
6. **A role test that impersonated the wrong identity.** A Zone Director claim
   attached to a teacher's `person_id` appeared to leak pupils — they were
   visible because that person genuinely teaches them. Role tests must use an
   identity with no other grant.
7. **Untyped CASE in an enum assignment** — `case when … then 'hod_approved' …`
   infers `text`, which cannot be assigned to a `plan_status` column. Needed an
   explicit cast.
8. **RLS recursion** in the fix for (2) — a policy on `thread_participant` that
   queries `thread_participant`. Resolved with a narrow `SECURITY DEFINER`
   membership helper.

Three of my own test suites also failed on hand-written expectations rather than
product defects. Expected values are now derived from the data, and that rule is
written into each suite.

## Blocked on external inputs

The report book is no longer on this list: it was designed in-house rather than
copied, so nothing is waiting on a scan.

| Item | Needs |
|---|---|
| SMS delivery | A Mauritian gateway account, sender ID, per-message cost |
| MES entry & results files | The current format specification and a sample |

The notification queue already fills correctly — unauthorised absences and
discipline escalations write rows to `notification`. Only the dispatcher that
drains it to a provider is missing.

## Still unaddressed

- `supabase db pull` has not been run. **35 migrations exist only in the
  Supabase project.** See [SETUP.md](./SETUP.md).
- No git repository yet.
- Nothing has been tested against real school data or a real user.
