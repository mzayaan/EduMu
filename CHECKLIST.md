# EduMU — everything left to be genuinely finished

Two different questions get two different answers, and conflating them is how
software gets called "done" while nobody can use it.

| Question | Answer |
|---|---|
| How much of the **blueprint** is built? | Everything except **school fees**, which is an open decision |
| Could a Mauritian secondary school **run on this in January**? | **~55%** |

> **History, 2 Aug.** This table once claimed the blueprint was complete. An
> audit (`npm run audit:blueprint`) showed it was not: four specified
> subsystems were missing and seven working RPCs had no caller. Three of the
> four are now built — **promotion rules engine (§15.4)**, **year rollover**,
> **staff attendance / movement / room booking** — and **every RPC now has a
> caller**. Fees remain an open decision rather than a gap. Detail in
> `BLUEPRINT-AUDIT.md`.
>
> The claim was wrong because nobody had checked it mechanically. That is now a
> script, so it cannot drift silently again.

The blueprint being finished changes less than it sounds. Everything built so
far has met five synthetic pupils. The remaining 55% is not features.

The 97% is code against a plan I wrote. The 45% is the honest one. Everything
below closes that gap, in the order it should be done.

---

## 0 · Immediate

- [x] **`npm install`** — was silently installing *nothing* dev. `NODE_ENV` is
      set to `production` on this machine, which makes npm set `omit=dev`, so
      `@types/react`, `vite`, `vitest` and `tailwindcss` were all absent and the
      typecheck failed with a hundred phantom errors. Clean reinstall with
      `NODE_ENV=development`: 515 packages, 0 vulnerabilities. **If a future
      install looks impossibly small, check `NODE_ENV` first.**
- [x] **`npm run verify`** — 3/3, 29 unit tests. Found a real solver bug on the
      way; see below.
- [x] Deleted `supabase/tests/probe.sql` and `.keep`.
- [x] **Security sweep of every RPC** — found and closed a genuine data leak.
      Migration 55, plus a regression test.
- [x] **`scripts/dump-migrations.mjs`** — pulls applied migrations out of
      `supabase_migrations.schema_migrations` and back into the repo. Migrations
      48–55 existed only in the database; a restore would have lost them.
- [x] **`RESTORE.md`** — rehearsal procedure.
- [x] **`DATA-PROTECTION.md`** — DPA 2017 pack.
- [x] **Migrations 48–55 recovered into the repo.** They existed only in the
      database; the baseline dump predates them, so a restore would have lost
      the form-teacher, lateness and security work without any error. Pulled
      from `supabase_migrations.schema_migrations` and verified byte-for-byte
      against the database — the only intentional difference is a forward
      reference in 53 to the fix in 55.
- [ ] **Refresh the baseline dump** — `pg_dump --schema=public --schema=app`.
      Genuinely needs the password. Lower priority now that the migration files
      exist: baseline + 48–55 is a complete restore path, so this is tidiness
      rather than exposure. `scripts/dump-migrations.mjs` keeps it current from
      here — run it after any migration applied outside the repo.
- [ ] **`git add -A && git commit && git push`** to `github.com/mzayaan/EduMu`.
- [ ] **Enable leaked-password protection** — Authentication → Providers →
      Password. One toggle.
- [ ] **Rotate the database password.** Pasted in plaintext into a terminal
      transcript and a chat session. Declined once; it should happen before real
      pupil data exists. Dashboard → Project Settings → Database → Reset, then
      use `$env:PGPASSWORD`, never a pasted URI.

### Two bugs found today, both silent, both by running things

**Solver placed sets into no room at all.** `if (rooms.length > 0 && !room)
continue` — when *no* room was eligible, `rooms.length` was 0, the guard was
false, and the set fell through and was placed with `roomId: null`. A 40-pupil
practical in a school whose only lab seats 32 was timetabled into nowhere and
reported as fully placed. Nothing in `unplaced`. Now fails loudly, and the
roomless case is confined to schools that have not entered rooms yet.

**`report_card_attendance` leaked any child's record to any signed-in user.**
`SECURITY DEFINER`, no authorisation of its own, unconstrained `p_student uuid`,
reachable at `/rest/v1/rpc/report_card_attendance`. RLS does not apply inside a
DEFINER function, so all 215 policies bought nothing on that path. Any parent —
or any teacher at another school — could read any pupil's absence and lateness
counts. Fixed by making it `SECURITY INVOKER` so the existing
`attendance_summary` policy governs it: the rule was already stated correctly
once, and the bug was bypassing it, not the rule being absent.

The general lesson is worth keeping: **RLS coverage is not access control if
`SECURITY DEFINER` functions are exposed.** `rpc_definer_authorisation.sql` now
fails if any DEFINER RPC lacks a guard, so the next one cannot slip in quietly.

---

## 1 · Code — ~~the remaining 3%~~ COMPLETE

- [x] **Syllabus tree editor** — `features/curriculum/SyllabusEditor.tsx`.
      Nested units, inline editing, per-unit term assignment. Warns when units
      have no term, because coverage is measured against the portion planned
      for each term and untermed units never appear in the figure.
- [x] **Asset CSV import** — `features/admin/AssetImport.tsx`. Dry run first,
      per-row errors, idempotent on tag. A blank room in a later file does not
      clear a room recorded earlier.
- [x] **Staff ↔ staff and staff ↔ guardian messaging** —
      `features/messages/MessagesScreen.tsx`. One screen for both; RLS decides
      what each person sees, so there is no second version to keep in step.
- [x] **Per-school crest upload** — in the platform console. Stored at
      `{school_id}/logo/…` so the existing path convention and its RLS policy
      apply unchanged.
**Billing: decided against.** Not building it. If EduMU is ever commercialised
that decision can be revisited, but speculative payment infrastructure for a
system that has not had a pilot would be the wrong thing to carry.

All covered by `supabase/tests/syllabus_and_import.sql` (13 assertions).

Audited mechanically (`npm run audit:blueprint`). `BLUEPRINT-AUDIT.md` has the
detail.

- [x] **Promotion rules engine (§15.4)** — migrations 56–57. Rules as data per
      year, all eight condition kinds, Rector override with a mandatory reason,
      facts frozen with each decision. Mirrored in `packages/domain` and
      checked for parity: 16/16 cases agree across Postgres and TypeScript.
- [x] **Academic year rollover** — migration 57. Dry run by default; refuses
      while any decision is unconfirmed; names anyone it cannot place.
      **The system can now cross a year boundary, which it could not before.**
- [x] **Staff attendance, staff movement, room booking** — migration 58.
- [x] **Every RPC now has a caller.** Was seven stranded, now zero. New Gate,
      Year end and Rooms screens, plus subject comments under Marks and
      certificates under Admin.
- [ ] **Decide on school fees.** Not a gap — a decision nobody has made.
      `bursar` is still a role with capabilities and nothing to do. Options in
      `BLUEPRINT-AUDIT.md` §3.1. Distinct from the SaaS billing that was scoped
      out, which should stay out.
- [ ] Reconcile the blueprint text, or mark Parts C and D as the original
      design and point at the schema as the source of truth.

Everything below this point is the work that decides whether it survives
contact with a school.

---

## 2 · Blocked on external inputs

Neither can be guessed at. Guessing produces something that looks finished and
is wrong.

- [ ] **SMS delivery.** Needs a Mauritian gateway account, a registered sender
      ID, and per-message cost. The `notification` queue already fills correctly
      on unauthorised absence, discipline escalation and report publication —
      only the dispatcher is missing. SMS matters more than the portal: guardian
      app adoption will never reach 100%, and SMS is what actually gets read.
- [ ] **MES entry and results file formats.** Needs the current specification
      and a sample file. Isolate behind an adapter with fixture-based tests so
      the format never leaks into the schema.

---

## 3 · Correctness the demo data cannot prove

The whole system has met five synthetic pupils. These need real scale.

- [ ] **Load one real anonymised class.** More problems will surface here than
      in all the feature work. Do this before building anything else.
- [ ] **Import three prior years of results** so analytics has something to say
      on day one, and so NCE → SC value-added is testable.
- [ ] **Run the timetable solver on the school's actual sets.** Benchmarked at
      47 ms for a synthetic 24-class school, but real schools have part-time
      staff, shared rooms, split classes and Extended Programme groups.
- [ ] **Test the offline outbox in a real dead spot**, on the phones staff
      actually carry. It has never met a genuine connection loss.
- [ ] **Generate report books for a full grade** and put them in front of the
      Rector. The layout is designed, not copied — it will need revision.
- [ ] **Verify the 80% eligibility screen against the school's own reckoning**
      for a past term. If the numbers disagree, the definition is wrong
      somewhere and it matters.

---

## 4 · Operational readiness

- [ ] **Restore rehearsal.** Procedure now written up in `RESTORE.md`, with the
      expected verification counts. Still needs actually running — the document
      is not the rehearsal.
- [ ] **Enable the auth hook on any new project** — Authentication → Hooks →
      `app.custom_access_token_hook`. Without it every RLS policy denies and the
      failure looks nothing like the cause.
- [ ] **Point-in-time recovery** — Supabase paid plans. Children's records.
- [ ] **MFA for Rector, Deputy Rector and Clerk accounts.**
- [ ] **Error and uptime monitoring** (Sentry or equivalent). Currently nothing
      reports a failure except a user noticing.
- [ ] **Decide the hosting** for the SPA and register a domain.
- [ ] **Re-run `pg_dump` after every schema change**, or drift returns. There is
      no CI to catch it.

---

## 5 · Legal and institutional

Drafted in `DATA-PROTECTION.md`. Drafting is the easy half — every item below
still needs a human, and most need a lawyer.

- [x] Controller/processor roles, lawful basis per purpose, retention schedule,
      breach procedure, processing-agreement checklist — all drafted.
- [ ] **Legal review.** I am not a lawyer and the document says so. The
      retention periods especially are proposals, not law.
- [ ] **Register with the Data Protection Office** — `dpo@govmu.org`. Two
      registrations: the school as controller, you as processor. Fees scale with
      employee count under the Data Protection (Fees) Regulations 2020; confirm
      the current amount with the Office rather than any second-hand figure.
- [ ] **Confirm retention with the school and the Ministry** before enabling any
      automated deletion. A wrong retention rule destroys evidence a pupil may
      later need, and cannot be undone.
- [ ] **Test the subject-access export for one real pupil** and read it as a
      parent would. Watch for the failure that is itself a breach: disclosing a
      sibling, another pupil in an incident, or a staff member's private note.
- [ ] **Consent wording** — photography, external-agency referral. Flags exist;
      the words need a human.
- [ ] **Processing agreement with the pilot school.** Settle data ownership and
      what happens at the end of the arrangement *at the start*, while it is
      still easy.

---

## 6 · The pilot — the part that actually decides it

- [ ] **Choose the school.** State, grant-aided or private changes what matters
      (fees and a Manager role appear for grant-aided).
- [ ] **Answer the open questions in `BLUEPRINT.md` §24** — session model,
      cycle length, grading cut-offs, Extended Programme, devices staff carry.
- [ ] **Data migration**: pupils, staff, guardians, timetable, historical
      results. Expect this to take longer than any feature.
- [ ] **Train the Usher and Form Teachers first.** Not "everyone" — the register
      is the wedge and those are the people who take it.
- [ ] **Parallel run for one grade**: paper register *and* app, one term.
- [ ] **Retire paper only when the school asks to.**
- [ ] **Sit in a staff room during morning registration** and watch. Every
      assumption in this system about how a register gets taken is untested.

---

## Reversals before a real school

- [ ] `a.ramdin@demo-sss.mu` holds both `form_teacher` and `usher` so one login
      reaches every screen. The Usher is a distinct post (School Superintendent).
- [ ] Drop the `QB-SSS` test tenant.
- [ ] Drop `r.bhugaloo@zone2.govmu`, the Zone Director test fixture.
- [ ] Do not load `supabase/seed.sql` — it is demo data and says so at the top.
- [ ] Timetable version 1 is a draft with a synthetic Grade 7 grid.

---

## What exists today

| | |
|---|---|
| Tables | 107 · **0 without RLS · 0 without FORCE · 0 unpoliced** |
| RLS policies | 227 |
| SECURITY DEFINER RPCs | **0 without a self-guard · 0 without pinned `search_path`** |
| RPCs with no UI caller | **0** (was 7) |
| Tenants | 2 (multi-tenancy exercised, not theoretical) |
| Screens | 33 components across 20 features |
| SQL suites | 20 |
| Unit tests | 69, all passing |
| Cross-implementation parity | attendance 10/10 · promotion 16/16 |
| Schema backup | baseline + storage/cron supplement + `dump-migrations.mjs` |

**Phases:** 1, 2, 3, 5 complete · 0 at 99% · 4, 6, 7, 8, 9 at 85–95%.

Twelve bugs found, every one by running something rather than reading it. The
worst were all silent:

- a solver score of `NaN` that disabled 660,000 optimisation iterations while
  every test passed
- a pupil-clash trigger that migration 05 claimed to create and never did —
  invisible for 47 migrations because only the solver and the UI wrote timetables
- a solver that placed room-constrained sets into no room at all and reported
  full success
- a `SECURITY DEFINER` RPC that let any signed-in user read any child's
  attendance record, behind a schema with otherwise complete RLS

Nine further failures were bad assertions rather than bad code. That pattern,
and how to avoid it, is at the top of `NEXT.md`.

The through-line: **every one of these passed a reading and failed a run.** The
remaining 55% in the table at the top of this file is the same category of risk,
scaled up — which is why "load one real class" outranks every feature idea.
