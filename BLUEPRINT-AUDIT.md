# BLUEPRINT.md audited against the built system

Run `node scripts/audit-blueprint.mjs` to reproduce. Verified against the live
catalogue (102 tables, 89 functions, 8 views) and the source tree on 2 Aug 2026.

The headline: **the blueprint is not fully built.** Most of what the audit
surfaced is documentation drift, but four specified subsystems are genuinely
absent, and one of them stops the app working past July.

A note on method — the audit matches identifiers, not intent. It proves whether
a named thing exists; it cannot prove a feature works. Everything below was
confirmed by a second targeted query before being listed.

---

## 1 · Specified in the blueprint, not built

### 1.1 Promotion rules engine — §15.4 — **absent**

The largest gap. §15.4 specifies it completely: a `Rule` type, eight
`Condition` kinds (`aggregate_gte`, `subject_pass_count_gte`,
`credit_count_gte`, `attendance_pct_gte`, `times_repeated_lte`,
`age_on_date_lte`, `has_medical_certificate_for_prolonged_absence`,
`core_subject_passed`), and a shipped rule table covering Grades 7 → 13.

None of it exists:

- no rule storage table, so rules cannot be "data, stored per academic year"
- no pure function in `packages/domain` — that package holds only
  `attendance.ts` and `timetable.ts`
- no mirrored Postgres function
- no repeat counter anywhere; `times_repeated` does not exist as a column

The only trace is `assessment.counts_for_promotion`, a flag with nothing
reading it.

What this costs, concretely:

- **The Manual's second-attempt rule is unimplemented.** "times_repeated ≤ 1 ∧
  aggregate ≥ 35 ∧ attendance ≥ 75 → conditional promote" is a real decision a
  Rector makes about a real child, and the system has no opinion on it.
- **Lower VI entry cannot be evaluated.** "≥ 4 credits at one and the same
  sitting" needs credit counting with a same-sitting constraint. Nothing counts
  credits.
- **Upper VI entry cannot be evaluated** — ≥ 2 Principal + ≥ 2 Subsidiary.

### 1.2 Academic year rollover — `rpc_rollover_year` — **absent**

No rollover function, and no substitute. There is no mechanism to carry pupils
from one academic year into the next: no way to create next year's
`class_enrolment` rows from this year's, apply promotion outcomes, or close the
old year.

This is the one that has a date attached. The system works within an academic
year and has never been asked to cross a boundary. In January someone would be
re-enrolling every pupil by hand.

It also depends on 1.1 — you cannot roll over without knowing who is promoted.

### 1.3 Staff attendance and movement — **absent**

`staff_attendance` and `staff_movement` are named in the blueprint; neither
exists, and no table matches. Pupil attendance is thorough; staff attendance is
not modelled at all. The Manual treats the staff register as a Rector duty.

### 1.4 Room booking — **absent**

`room_booking`, `booked_by`, `requested_by` — nothing. Rooms exist and the
timetable allocates them, but there is no ad-hoc booking of the hall or a lab
outside the timetable.

### 1.5 Fees and the cash book — **absent, and needs a decision**

`ledger_entry`, `cash_book`, `fee_amount`, `fee_paid_on` — nothing.

Worth separating two things that got conflated: **SaaS billing** was scoped out
by decision, and that still looks right. **School fees** are a different matter
— grant-aided and private schools charge them, and `bursar` exists as a role
with capabilities and nothing to bursar. Either build it or write down that
fees stay in the school's existing system; leaving a role with no function is
the worst of the three.

### 1.6 National exam entry and results — **absent, known blocked**

`national_exam_entry`, `national_exam_result` — nothing. This is the MES file
format item already tracked in `CHECKLIST.md` §2, blocked on the specification.
Recorded here for completeness, not as news.

---

## 2 · Built and unreachable — seven RPCs with no caller

These exist, are granted to `authenticated`, and no client code calls them.
Working database, no route to a user.

| RPC | What is stranded |
|---|---|
| `rpc_record_late_arrival` | **The whole late-arrival feature.** Built and SQL-tested today; the Usher has no screen to record an arrival, so it can never fire in practice |
| `rpc_set_subject_comment` | Per-subject teacher comments. The report book renders `educator_comment`, so every report book will print those blank |
| `rpc_amend_mark` | The audited mark-correction path. Corrections presumably happen anyway — just not through the audited route |
| `rpc_declare_closure` | Cyclone and emergency closures. In Mauritius this is not an edge case |
| `rpc_generate_school_calendar` | Year setup — generating `calendar_day` from term dates |
| `rpc_issue_leaving_certificate` | A statutory document a school must issue |
| `rpc_recompute_attendance_summary` | Recovery tool; arguably fine as SQL-only |

`rpc_record_late_arrival` and `rpc_set_subject_comment` are the two that
undermine features believed to be finished.

---

## 3 · Documentation drift

Not defects, but the blueprint is no longer a reliable map.

**Never mentioned in the blueprint:** 72 of 89 functions · all 8 views · 5
tables (`late_arrival`, `exam_arrangement`, `script_batch`,
`teaching_resource`, `admission_checklist`) · 5 enums.

Most post-date the document. The effect is that §16's "API surface" describes a
system that no longer exists, and anyone reading it to find an RPC will not
find it.

**Renamed since the blueprint** — these read as gaps in the raw audit output
and are not:

| Blueprint | Actual |
|---|---|
| `rpc_allocate_exam_seats` | `rpc_allocate_seats` |
| `rpc_assign_invigilation` | `rpc_assign_invigilators` |
| `generate_school_calendar` | `rpc_generate_school_calendar` |
| `rpc_publish_marks` | split into `rpc_set_assessment_status` + `rpc_publish_report_cards` |
| `ar_read` / `ar_write` / `ar_tenant` | `arecord_read` / `arecord_insert` / `arecord_update` |
| `zone_director` | `zone_officer` |

**Named roles that do not exist:** `it_admin`, `ministry_observer`,
`pta_exec`, `class_captain`, `student_council`, `staff_welfare`. Some are
committee rows rather than roles — `is_class_captain` and `is_prefect` are
columns on `student`, so the concept is modelled, just not as a role. Worth one
pass to decide which of these were ever meant to be roles.

---

## 4 · What I would do about it

In order.

1. **Rollover + promotion together.** They are one piece of work and they have a
   deadline the others do not. Without them the system cannot begin a second
   academic year.
2. **Wire up `rpc_record_late_arrival` and `rpc_set_subject_comment`.** Small —
   the hard part is built. Both currently make a finished-looking feature
   silently do nothing.
3. **Decide on fees.** Build, or write down that they stay elsewhere and remove
   the expectation.
4. **The other five uncalled RPCs** — closures especially, given cyclones.
5. **Reconcile the blueprint.** Either update §13/§16 or mark them as the
   original design and point at the schema as the source of truth. A document
   that is 70% accurate is worse than one clearly labelled as historical.
6. **Staff attendance and room booking** — real but not urgent.

Nothing here is a security problem and nothing blocks a single-term pilot. Items
1 and 2 block anything longer.
