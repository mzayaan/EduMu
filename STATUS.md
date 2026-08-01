# EduMU — build status

Generated at the end of the continuous build session. Percentages are against
the phase definitions in [BLUEPRINT.md §22](./BLUEPRINT.md).

## Database

| | |
|---|---|
| Tables | 100 |
| RLS policies | 190+ (public) + 10 (storage) |
| Migrations | 35 |
| Storage buckets | 6, all RLS-backed |
| SQL test suites | 8 |

## Phases

| Phase | Was | Now | Remaining |
|---|---|---|---|
| **0 — Foundations** | 90% | 95% | CI has still never actually executed |
| **1 — People & Attendance** | 60% | **100%** | — |
| **2 — Assessment** | 40% | 75% | Report card PDFs (blocked), batch generation, results analysis |
| **3 — Timetable** | 15% | 85% | Drag-and-drop manual editor; solver, grid and cover board are done |
| **4 — Examinations** | 15% | 20% | Papers, seating, invigilation, script tracking, MES files (blocked) |
| **5 — Discipline & governance** | 0% | 80% | Committee/meeting screens; schema, RLS and conduct screens done |
| **6 — Curriculum** | 0% | 50% | Screens; schema, RLS, coverage view and RPCs done |
| **7 — Facilities & comms** | 0% | 50% | Screens; schema, RLS done |
| **8 — Analytics** | 0% | 5% | Dashboards, reports, Ministry returns |
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

## Bugs found by testing, not by reading

1. **Solver score was `NaN`.** Cycle days are 1-based, the per-day array
   0-based; indexing by the raw day number wrote past the end. Every
   local-search comparison was false, so 660,000 iterations did nothing. The
   solver looked like it worked. Regression test added.
2. **`thread_participant` had `WITH CHECK (true)`.** Any staff member could add
   themselves to a parent–teacher conversation about another pupil and read it.
   Found by the Supabase advisor.
3. **RLS recursion** in the fix for (2) — a policy on `thread_participant` that
   queries `thread_participant`. Resolved with a narrow `SECURITY DEFINER`
   membership helper.

Three of my own test suites also failed on hand-written expectations rather than
product defects. Expected values are now derived from the data, and that rule is
written into each suite.

## Blocked on external inputs

| Item | Needs |
|---|---|
| Report card PDF layout | A scan of the pilot school's actual report book |
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
