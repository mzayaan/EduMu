# EduMU — everything left to be genuinely finished

Two different questions get two different answers, and conflating them is how
software gets called "done" while nobody can use it.

| Question | Answer |
|---|---|
| How much of the **blueprint** is built? | **~97%** |
| Could a Mauritian secondary school **run on this in January**? | **~45%** |

The 97% is code against a plan I wrote. The 45% is the honest one. Everything
below closes that gap, in the order it should be done.

---

## 0 · Immediate — do these before anything else

- [ ] **`npm install`** — `recharts` was added for the dashboard charts and is
      not yet installed. The dashboard will not build without it.
- [ ] **`npm run verify`** — typecheck, unit tests, parity check.
- [ ] **`git add -A && git commit`** — the last several hours of work are on
      disk but unversioned. Bash cannot reach `D:\Project` from the agent
      sandbox, so this cannot be done for you.
- [ ] **`git push`** to `github.com/mzayaan/EduMu`.
- [ ] **Rotate the database password.** It was pasted in plaintext into a
      terminal transcript and a chat session. Dashboard → Project Settings →
      Database → Reset. Then use `$env:PGPASSWORD` or `.pgpass`, never a
      pasted URI.
- [ ] **Enable leaked-password protection** — Authentication → Providers →
      Password. One toggle.
- [ ] Delete `supabase/tests/probe.sql` and `supabase/tests/.keep` — scratch
      files the agent could not unlink.

---

## 1 · Code — the remaining ~3%

- [ ] **Syllabus tree editor** (Phase 6). `syllabus` / `syllabus_unit` is a
      self-referencing tree with `term_id` per unit. Needs a nested editor and a
      "portion to be covered this term" assignment. `syllabus_coverage` already
      reads from it.
- [ ] **Asset CSV import** (Phase 7). Schools have an existing register.
      Validation preview with per-row errors, dry-run diff, idempotent on `tag`.
- [ ] **Staff ↔ staff messaging UI** (Phase 7). `message_thread` works and is
      tested; no screen exists for staff or guardians.
      ⚠️ Membership must be answered by `app.in_thread()` — a subquery on
      `thread_participant` re-enters its own policy and errors.
- [ ] **Per-school logo upload** (Phase 9). `school.logo_path` exists and the
      report book renders it. Wire an upload on the `{school_id}/…` path
      pattern.
- [ ] **Billing** (Phase 9) — only if this is commercialised. Confirm first.

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

- [ ] **Restore rehearsal.** Take `00000000000000_baseline.sql` +
      `00000000000001_storage_and_cron.sql` into an empty Supabase project and
      confirm the app runs against it. An unrehearsed backup is a hope.
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

- [ ] **Mauritius Data Protection Act 2017 registration.** Name the controller
      (the school) and processor (you). Children's data is high-risk by
      definition.
- [ ] **Retention schedule** per record class, and a documented deletion policy.
- [ ] **Breach procedure** with the 72-hour notification path to the Data
      Protection Office.
- [ ] **Consent capture review** — photography, external-agency referral. The
      flags exist; the wording needs a human.
- [ ] **Subject-access export** tested end to end for one pupil.
- [ ] **Agreement with the pilot school** on ownership, hosting location and
      what happens to the data if the arrangement ends.

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
| Tables / views | 101 / 6 · **0 without RLS** |
| RLS policies | 201 public + 10 storage |
| Functions | 82 · Enums 19 · Buckets 6 |
| Tenants | 2 (multi-tenancy exercised, not theoretical) |
| Screens | 20 files across 17 features |
| SQL suites | 15 |
| Schema backup | baseline 380KB + storage/cron supplement |

**Phases:** 1, 2, 3, 5 complete · 0 at 98% · 4, 6, 7, 8, 9 at 85–95%.

Ten bugs found, every one by running something rather than reading it. The two
worst were silent: a solver score of `NaN` that disabled 660,000 optimisation
iterations while every test passed, and a pupil-clash trigger that migration 05
claimed to create and never did — invisible for 47 migrations because only the
solver and the UI were writing timetables.

Nine further failures were bad assertions rather than bad code. That pattern,
and how to avoid it, is at the top of `NEXT.md`.
