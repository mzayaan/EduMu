# BLUEPRINT.md audited against the built system

Reproduce with `npm run audit:blueprint`. Verified against the live catalogue
and the source tree, 2 Aug 2026, after migrations 56–58.

| | First run | Now |
|---|---|---|
| Specified subsystems missing | 4 | **1** (fees — an open decision, not a gap) |
| RPCs with no caller | 7 | **0** |
| Tables | 102 | 107 |
| RPCs wired to the UI | 45 | 62 |
| Tables reachable from the client | 53 | 62 |

The first run of this audit found the blueprint was **not** built, contrary to
what `CHECKLIST.md` claimed. Four subsystems were missing and seven working
RPCs had no way to be reached. Three of the four are now built and every RPC
has a caller.

A note on method — the audit matches identifiers, not intent. It proves whether
a named thing exists; it cannot prove a feature works. Everything below was
confirmed by a targeted query or a test before being recorded.

---

## 1 · Built since the first audit

### 1.1 Promotion rules engine — §15.4 — **built** (migrations 56, 57)

Was the largest gap: fully specified, entirely absent. Now:

- `promotion_rule` — rules as **data**, per academic year, ordered by priority,
  first match wins. Editable, because a promotion threshold is a school and
  Ministry matter that changes between years, and a threshold in code is one
  nobody can correct without a deploy.
- `promotion_decision` — the verdict, plus the **facts it was reached on**,
  frozen at computation. An appeal in November concerns the figures as they
  stood in July, and marks get amended.
- `student.times_repeated` — nothing was counting this, and the Manual's
  one-repeat rule needs it.
- All eight `Condition` kinds from the blueprint.
- `app.promotion_facts` computes; `app.promotion_condition_holds` evaluates.
  Splitting them is what makes the TypeScript mirror testable.
- Rector override on every pupil, with a mandatory reason enforced by a check
  constraint. **The engine advises; the Rector decides.**

Two deliberate choices worth keeping:

**Falling through every rule yields `repeat`, not `promote`.** A wrongly-held
pupil is visible and appealable. A wrongly-promoted one is discovered a year
later by a teacher wondering why the child cannot cope.

**An unknown condition kind evaluates false.** Rules are data, so a kind can
arrive from the database that the running build has never heard of. It must not
promote by accident.

Parity: `packages/domain/src/promotion.ts` mirrors the SQL. 16 shared cases in
`promotion.cases.json` feed both the TypeScript test and a generated SQL suite.
**16/16 agree.** Two implementations exist because the client needs to show a
Rector the effect of moving a threshold across a cohort without a round trip
per pupil, while the database must be the authority when the decision is
written.

### 1.2 Academic year rollover — **built** (migration 57)

`rpc_rollover_year(from, to, commit)`. Dry run by default.

- Refuses outright while any promotion decision is unconfirmed. Rollover acts
  on a human decision; it does not make one.
- Reports pupils it cannot place because next year has no class of the right
  grade — by name, rather than dropping them.
- Increments `times_repeated`, closes the old year, opens the new one, and
  seeds the new year's rules.

This was the item with a date attached. The system had only ever worked *within*
a year; in January someone would have re-enrolled every pupil by hand.

### 1.3 Staff attendance, staff movement, room booking — **built** (migration 58)

- `staff_attendance` — deliberately *not* modelled on pupil attendance. Staff
  have leave types and are covered by substitutes. Opening the register
  pre-marks anyone on approved leave, so an unexplained absence is the only
  thing left to notice.
- `staff_movement` — signing out during the day. A teacher at a Ministry
  meeting is present for the day and off site for two hours, and if a parent
  asks for them somebody must be able to say where they are.
- `room_booking` — with an **exclusion constraint** preventing overlapping
  approved bookings, and a timetable clash check in
  `rpc_decide_room_booking` that the constraint cannot see. Lessons win.
- Postgres has no `time` range type, so migration 58 defines `timerange`.

---

## 2 · Every RPC now has a caller

Was seven stranded. New screens:

| Screen | Wires |
|---|---|
| **Gate** (`features/gate`) | `rpc_record_late_arrival`, `rpc_open_staff_register`, `rpc_mark_staff_attendance`, `rpc_sign_staff_out`, `rpc_sign_staff_in` |
| **Year end** (`features/yearend`) | `rpc_evaluate_promotions`, `rpc_override_promotion`, `rpc_confirm_promotions`, `rpc_rollover_year`, `rpc_seed_promotion_rules`, `rpc_generate_school_calendar`, `rpc_declare_closure` |
| **Rooms** (`features/rooms`) | `rpc_decide_room_booking` |
| **Marks → subject comments** | `rpc_set_subject_comment`, `rpc_amend_mark` |
| **Admin → Certificates & tools** | `rpc_issue_leaving_certificate`, `rpc_recompute_attendance_summary` |

The two that mattered most:

- **`rpc_record_late_arrival`** had been built, SQL-tested and shipped with no
  Usher screen. The database handled late arrivals correctly and nothing could
  trigger it. The Gate screen also spells out the consequence when an arrival
  lands after the morning register — the pupil loses a session against the 80%
  threshold, and the person at the desk is the only one placed to catch a
  mistake.
- **`rpc_set_subject_comment`** — the report book renders `educator_comment`
  per subject and there was no way to enter one, so every report book printed
  those blank while appearing to have the field.

Two guessed RPC signatures were wrong (`rpc_declare_closure` and
`rpc_generate_school_calendar` both take `p_year_id`). Caught by checking the
catalogue rather than at runtime.

---

## 3 · Still outstanding

### 3.1 School fees — **an open decision, not a gap**

`ledger_entry`, `cash_book`, `fee_amount`, `fee_paid_on` — none exist, and
`bursar` remains a role with capabilities and nothing to do.

Worth keeping separate from **SaaS billing**, which was scoped out and should
stay out. **School fees** are different: grant-aided and private schools charge
them. Three options, none chosen yet:

1. Record that fees stay in the school's existing system, and narrow the bursar
   role to match.
2. Read-only tracking — what is owed, what was paid, no receipts.
3. A full ledger and cash book. Real money, so it needs reconciliation and
   audit design, not just tables.

Leaving a role with no function is the worst of the four.

### 3.2 National exam entry and results — blocked

`national_exam_entry`, `national_exam_result`. Blocked on the MES file
specification and a sample file, already tracked in `CHECKLIST.md` §2. Isolate
behind an adapter with fixture tests so the format never reaches the schema.

### 3.3 Documentation drift

`BLUEPRINT.md` still describes the original design. 85 of 103 functions, all 9
views and 7 tables are never named in it, and §16's "API surface" describes a
system that no longer exists.

Recommended: mark Parts C and D as the original design and point at the schema
plus this document as the source of truth. A document that is 70% accurate is
worse than one clearly labelled historical.

**Renames** — these read as gaps in raw audit output and are not:

| Blueprint | Actual |
|---|---|
| `rpc_allocate_exam_seats` | `rpc_allocate_seats` |
| `rpc_assign_invigilation` | `rpc_assign_invigilators` |
| `rpc_evaluate_promotion` | `rpc_evaluate_promotions` (batch) |
| `generate_school_calendar` | `rpc_generate_school_calendar` |
| `rpc_publish_marks` | `rpc_set_assessment_status` + `rpc_publish_report_cards` |
| `ar_read` / `ar_write` / `ar_tenant` | `arecord_read` / `arecord_insert` / `arecord_update` |
| `zone_director` | `zone_officer` |

**Roles named and never built:** `it_admin`, `ministry_observer`, `pta_exec`,
`class_captain`, `student_council`, `staff_welfare`. Some are committee rows
rather than roles — `is_class_captain` and `is_prefect` are columns on
`student`, so the concept is modelled. Worth one pass to decide which were ever
meant to be roles.

---

## 4 · Current state

| | |
|---|---|
| Tables | 107 · **0 without RLS · 0 without FORCE** |
| Policies | 227 |
| `SECURITY DEFINER` RPCs | **0 unguarded · 0 without pinned `search_path`** |
| Functions / views / enums | 103 / 9 / 20 |
| RPCs with no caller | **0** |
| Unit tests | 69 |
| SQL suites | 20 |
| Promotion parity | 16/16 across Postgres and TypeScript |

Nothing outstanding is a security problem, and nothing blocks a single-term
pilot. The system can now cross an academic year boundary, which it could not
before.
