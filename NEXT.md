# Next session — the remaining ~8%

Written at the end of the previous session so this one starts informed.
Read this, then `STATUS.md` for the numbers. Do not re-read `BLUEPRINT.md`
end to end; it is 20k words and mostly already built.

---

## Before anything else

**Has `supabase db pull` been run?**

```bash
ls supabase/migrations/*.sql | wc -l    # expect ~48, not 0
```

If it returns 0, stop and do that first. 48 migrations exist only inside the
Supabase project, there is no CI to replay them, and every change made today
compounds on an unversioned schema.

---

## Context a cold session needs

```
Supabase project   wdwtapdmdgdcvbifbeiz  (ap-south-1)
Verify             npm run verify           typecheck + unit + parity
                   npm run verify -- --sql  + 14 SQL suites (needs DATABASE_URL)
Benchmark          npm run bench:timetable
```

Demo identities (all in the `DEMO-SSS` tenant):

| Who | Email | Notes |
|---|---|---|
| Anjali Ramdin | `a.ramdin@demo-sss.mu` | Educator, Form Teacher 7A, **also Usher** (demo shortcut), teaches all 5 G7 sets |
| Deven Callychurn | `d.callychurn@demo-sss.mu` | Form Teacher 7B |
| Fatima Joomun | guardian | Responsible Party for roll 1 |
| Rajesh Bhugaloo | `r.bhugaloo@zone2.govmu` | Zone Director, **no teaching duties** — use this identity for role tests |
| — | `QB-SSS` | Second tenant, from multi-tenancy testing |

---

## The work, in the order I would do it

### 1. Drag-and-drop timetable editing (Phase 3 → 100%) — largest item

**DONE.** `features/timetable/EditableGrid.tsx`, reachable from the Edit tab.

Drag to move, drag from the unplaced tray to place, × to return a lesson to the
tray. Clashes are refused with a message written for a Deputy Rector rather than
a Postgres error. Published versions refuse edits and say to create a new one.

**Migration 48 fixed a real hole found while building this.** Migration 05 said
student clashes "are checked by a trigger against set_enrolment" — that trigger
was never created. Room and staff clashes had unique indexes; the pupil clash had
nothing. The solver avoids them and the UI validator catches them, so it never
surfaced until manual editing made a direct write possible.
Covered by `supabase/tests/timetable_editing.sql`.

### 2. Committee & meeting screens (Phase 5 → 100%)

**DONE.** `features/committees/CommitteesScreen.tsx`, Committees tab.

Three panels: committees with membership, meetings with agenda/minutes/actions,
and a personal "My actions" list. Guardians can be added as members — the
Pastoral Care Committee is required to include a parent — while internal minutes
stay invisible to them, since pastoral discussion names children.

Covered by `supabase/tests/committees.sql`, including the round trip from an
overdue action to the Rector's dashboard count and back when it is completed.

### 3. Analytics charts + printable exports (Phase 8 → 100%) — DONE

`features/dashboard/Charts.tsx` and `MinistryReturn.tsx`.

Four charts on the Rector's dashboard: attendance by class, attendance across
the year, pass rate by subject (weakest first — this is opened to find trouble,
not to admire the strongest), and roll by grade. The 80% threshold is drawn as a
reference line wherever attendance appears, and bars are coloured by whether
they clear it. Tables stay underneath the charts: a Rector transcribing onto a
Ministry form needs the number, not the picture.

The Ministry return was a raw JSON `<pre>`; it is now an A4 sheet with signature
blocks, sharing the report book's print CSS. JSON download kept for anyone who
wants to machine-read it.

**`recharts` was missing from `apps/web/package.json`** — the blueprint listed
it but it was never installed. Added; run `npm install`.

#### ORIGINAL NOTES

Data is done: `attendance_by_class`, `results_by_subject`, `pupils_at_risk`,
`school_dashboard()`, `ministry_return()`.

- Recharts is already a dependency. Attendance trend by term, results
  distribution, pass rate by subject.
- `ministry_return()` currently renders as raw JSON in a `<pre>`. Give it the
  same A4 print treatment as the report book (`.no-print`, `@page`).

### 4. Syllabus tree editor (Phase 6 → 100%)

`syllabus` / `syllabus_unit` are a self-referencing tree with `term_id` per
unit. Needs a nested editor and a "portion to be covered this term" assignment.
`syllabus_coverage` already reads from it.

### 5. Asset import + staff messaging UI (Phase 7 → 100%)

- CSV import for `asset` — schools have an existing register. Validation preview
  with per-row errors, dry-run diff, idempotent on `tag`.
- Staff↔staff threads. `message_thread` works and is tested; the guardian side
  has no UI either. **Note the RLS recursion trap**: membership must be answered
  by `app.in_thread()`, never a subquery on `thread_participant`.

### 6. Billing + per-school logo upload (Phase 9 → 100%)

- `school.logo_path` exists and the report book renders it; wire an upload to
  the `student-photos` bucket pattern (path `{school_id}/...`).
- Billing only matters if this is commercialised — confirm before building.

---

## Traps this codebase has already sprung

Do not re-learn these.

**Nine of the failures in this project have been bad assertions, not bad code.**
Every one shared a shape: the assertion encoded a *number observed once* rather
than a *property that must always hold*. Before writing `n = 5`, ask what the
5 means and whether it survives another seed, another tenant, or a second run.
The recurring forms:

- an absolute count where a delta was meant (`outstanding = 1`)
- an unscoped count across tenants (`9 committees` → 18 across two schools)
- a hard-coded fixture slot a previous run had already filled
- an identity that carried a second, legitimate grant

1. **Assert invariants, never row counts.** "Pupil sees exactly 1 row" passed
   until a term of attendance was seeded, then reported a security failure that
   did not exist. Assert *zero foreign rows*.
2. **Role tests need a clean identity.** A Zone Director claim on a teacher's
   `person_id` looked like a leak; those pupils were visible because that person
   teaches them. Use `r.bhugaloo@zone2.govmu`.
3. **Build capability sets from `role_capability`**, never by hand. Hand-written
   caps have produced three false failures.
4. **`c->'key' is not null` is not an assertion.** `->` yields JSON null, which
   is not SQL NULL. Assert on a leaf value.
5. **`security_invoker` views inner-joining `person`/`student` return an empty
   result** to a caller lacking `person.read.all` — silent, not an error.
6. **PL/pgSQL: a table alias that matches a declared record variable** resolves
   to the variable. Keep them distinct.
7. **Untyped `CASE` cannot be assigned to an enum column** without a cast.
8. **Report columns are logical** (`kind|title`), not per-assessment — each
   subject runs its own "Class Test 1".

---

## What NOT to do

- Do not add CI back. It was removed deliberately: several GB of Docker per run.
- Do not build SMS or MES file export. Both are blocked on real external inputs
  and guessing produces confidently wrong output.
- Do not invent a new report book layout. It is designed and tested.

---

## After the 8%

The remaining work is not features. Load one real anonymised class and see what
breaks — five synthetic pupils have told us everything they can.
