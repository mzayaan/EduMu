# EduMU — Data Protection Act 2017 pack

Working document for compliance with the Mauritius **Data Protection Act 2017
(Act No. 20 of 2017)**, administered by the Data Protection Office.

> I am not a lawyer and this is not legal advice. Everything below needs review
> by someone qualified in Mauritian law before a real pupil's record is entered.
> The retention periods in §3 in particular are **proposals**, not law — see the
> note at the head of that section.

Children's data is high-risk by definition, the penalty ceiling is **MUR 200,000
and up to five years' imprisonment**, and the school — not the software — carries
most of the obligation. Getting this wrong is not a technical failure.

---

## 1 · Who is what

| Role | Who | Why |
|---|---|---|
| **Controller** | The school | Decides why and how pupil data is processed |
| **Processor** | You / EduMU | Processes on the school's documented instructions |
| **Sub-processor** | Supabase (AWS `ap-south-1`, Mumbai) | Hosting and storage |
| **Data subjects** | Pupils, guardians, staff | Pupils are minors — see §6 |

Both controllers and processors must register with the Commissioner. Two
registrations, not one. The school does its own; you do yours.

**Registration.** Fees are set by the Data Protection (Fees) Regulations 2020
(GN No. 152 of 2020, in force 1 August 2020) and scale with the number of
employees. Registration is renewable. Confirm the current amount and the current
form with the Data Protection Office directly — `dpo@govmu.org`,
[dataprotection.govmu.org](https://dataprotection.govmu.org) — rather than
relying on any figure quoted second-hand, including here.

**Sub-processor disclosure.** Data rests on AWS in Mumbai. That is a transfer
outside Mauritius and the school must know it, agree to it, and be able to point
at the safeguard relied on. Do not let this surface for the first time during an
audit.

---

## 2 · Lawful basis, per purpose

Basis is per purpose, not per system. "The school uses EduMU" is not a basis.

| Purpose | Proposed basis | Note |
|---|---|---|
| Attendance register | Legal obligation / public task | Statutory; not consent |
| Assessment and reporting | Public task | Core function |
| Discipline records | Public task | Retention is the sensitive part |
| Guardian contact for absence | Legal obligation / vital interests | Safeguarding |
| SMS to guardians | Public task, with opt-out | Not marketing; do not treat it as such |
| Photographs | **Consent** | Separately capturable, separately withdrawable |
| External agency referral | **Consent** or vital interests | Depends on the referral |
| Health and dietary flags | Special category — explicit consent or vital interests | Highest bar |

Consent is the wrong basis for anything the school would do anyway. If a
guardian cannot meaningfully refuse without the pupil losing schooling, it is
not consent, and calling it consent makes it worse rather than better.

Where consent *is* the basis, withdrawal has to be as easy as giving it, and the
system must actually stop the processing when it is withdrawn.

---

## 3 · Retention schedule

> **These periods are proposals.** Mauritian schools are subject to Ministry of
> Education record-keeping requirements and public-archive rules that override
> anything convenient. Confirm each line with the school and the Ministry before
> anything is deleted. **Do not enable automated deletion until this table is
> signed off** — a wrong retention rule destroys evidence a pupil may later need,
> and unlike most bugs it cannot be reversed.

| Record class | Proposed retention | From | Rationale |
|---|---|---|---|
| Pupil master record (identity, enrolment) | Long-term / permanent | Leaving date | Schools are routinely asked to confirm attendance decades later |
| Examination results (NCE, SC, HSC) | Long-term / permanent | Award | Reissued on request throughout a life |
| Internal marks, term results | 7 years | Leaving date | Appeals, verification |
| Report books | 7 years | Issue | As above |
| Attendance registers | 7 years | End of academic year | Statutory returns, welfare enquiries |
| Late-arrival records | 3 years | End of academic year | Operational; no long-term value |
| Discipline and occurrence log | 7 years, or to age 25 if a safeguarding matter | Incident | The safeguarding tail is the point |
| Safeguarding / child-protection referrals | To age 25 minimum | Referral | Deliberately long; take advice |
| Health and dietary flags | Duration of enrolment + 1 year | Leaving | No reason to keep longer |
| Guardian contact details | Duration of enrolment + 1 year | Leaving | |
| Photographs (consented) | Until consent withdrawn, or leaving + 1 year | | Delete on withdrawal, promptly |
| Staff employment records | Per employment law | Termination | Separate regime; take advice |
| Messages (staff ↔ guardian) | 3 years | Last message | May contain safeguarding content — review before purging |
| Audit / access logs | 2 years | Event | Needed to investigate a breach |
| Notification queue (SMS/email) | 1 year | Send | Delivery evidence only |

Two things follow from this table:

1. **Retention must be per class, not per database.** A single "delete after N
   years" job across the schema would destroy exam results and safeguarding
   records. Any deletion job has to be driven by this table.
2. **Deletion must be recorded.** What was deleted, under which line, when, and
   on whose authority. A deletion you cannot evidence looks identical to a
   breach.

---

## 4 · Breach procedure

The statutory clock: notify the Commissioner **without undue delay and, where
feasible, within 72 hours** of becoming aware. Where the breach is likely to
result in high risk to the data subjects, they must be notified too.

72 hours from *awareness*, not from confidence. An incomplete notification on
time beats a complete one late.

### On discovery

**Hour 0 — contain and record.** Note the time of awareness in writing; the
clock runs from it. Revoke sessions or keys if credentials are involved. Do not
delete anything: evidence.

**Hours 0–24 — establish scope.** What categories of data, roughly how many
subjects, whether children are involved (they will be), whether special-category
data is involved, and whether the data was accessed or merely exposed.

**Hours 0–72 — notify the Commissioner.** Include, per the Act:

- the nature of the breach
- categories and approximate number of data subjects affected
- categories and approximate number of records affected
- likely consequences
- measures taken or proposed, including mitigation
- contact point for further information

Approximate numbers are acceptable. Waiting for exact ones is not.

**Notify data subjects** where high risk is likely. For pupils, notification
goes to guardians, in plain language, saying what happened, what it means for
their child, and what they should do.

**After** — write it up: cause, timeline, what changed. Enter it in the
occurrence log.

### Roles — fill these in before you need them

| Role | Person | Contact |
|---|---|---|
| Who declares an incident | *Rector* | |
| Who notifies the Commissioner | *(controller — the school)* | `dpo@govmu.org` |
| Technical lead | *(processor — you)* | |
| Who speaks to guardians | *Rector* | |

A processor who discovers a breach must tell the controller **immediately** —
the school's 72 hours run from when it becomes aware, so a delay in telling them
consumes their statutory window, not yours.

---

## 5 · Data subject rights

| Right | Route today | Status |
|---|---|---|
| Access | Subject-access export | **Needs end-to-end test for one pupil** |
| Rectification | Admin screens | Works |
| Erasure | Constrained by §3 retention | Case-by-case; not a button |
| Restriction | No mechanism | **Gap** |
| Objection | Per purpose | Consent-based purposes only |
| Portability | Export | Same route as access |

Statutory response deadlines apply — confirm the current period with the Data
Protection Office and record it here.

**Test the subject-access export properly.** Run it for one pupil and read the
output as a parent would. Two failure modes, both common: it omits something it
should include (messages, discipline notes, attendance detail), or it discloses a
third party — a sibling, another pupil in an incident, a staff member's private
note. The second is itself a breach, caused by responding to a rights request.

---

## 6 · Children

Pupils are minors and this raises the bar throughout.

- Guardians exercise rights on a pupil's behalf, but an older pupil has their own
  interest — including, sometimes, against a guardian. Do not assume guardian
  access is always appropriate.
- **Guardian ≠ parent.** Custody arrangements, separated parents, and
  guardians with no legal standing are all real. The system models
  `student_guardian`; the school must keep it accurate, and someone must own
  removing access when an arrangement changes.
- Safeguarding records may need to be withheld from a guardian where disclosure
  would put the child at risk. This is a legal judgement, not a settings toggle.
- Photography consent belongs to the guardian while the pupil is a minor, and
  should be revisited, not assumed to persist for seven years.

---

## 7 · Processing agreement with the school

Before any real data. Must cover:

- [ ] Subject matter, duration, nature and purpose of processing
- [ ] Categories of data and of data subjects
- [ ] That you process **only on documented instructions**
- [ ] Confidentiality of anyone with access
- [ ] Security measures (§8)
- [ ] Sub-processors named — **Supabase / AWS Mumbai** — and the approval route for adding one
- [ ] Assistance with data subject requests
- [ ] Breach notification to the school **without undue delay**
- [ ] Deletion or return of all data at the end of the arrangement, and which
- [ ] Audit and inspection rights
- [ ] **Who owns the data if the arrangement ends** — settle this in writing at the start, when it is easy

---

## 8 · Technical measures already in place

Worth stating in the registration and the agreement, because they are real:

- Row Level Security on **all 102 tables**, `FORCE`d, so even the table owner is
  subject to policy. 215 policies.
- Authorisation lives in the database, not the client. The UI hides what a user
  cannot do; the database is what actually refuses.
- Tenant isolation by `school_id` on every policy, exercised across two tenants
  rather than assumed.
- Family isolation verified across 25 table/actor pairs
  (`supabase/tests/rls_isolation_sweep.sql`).
- Every `SECURITY DEFINER` RPC authorises itself, with a structural test that
  fails if a new one forgets (`supabase/tests/rpc_definer_authorisation.sql`).
- All DEFINER functions pin `search_path`.
- Encryption in transit and at rest via Supabase.

### Outstanding

- [ ] **MFA** for Rector, Deputy Rector and Clerk accounts
- [ ] **Leaked-password protection** — Authentication → Providers → Password
- [ ] **Point-in-time recovery** — a paid plan; children's records justify it
- [ ] **Error and uptime monitoring** — nothing currently reports a failure
      except a user noticing, which is also true of a breach
- [ ] **Rotate the database password.** It was pasted in plaintext into a
      terminal transcript and a chat session. Currently declined; it should be
      done before real data, and the exposure noted here so the decision is
      visible rather than forgotten.
- [ ] Access logging sufficient to answer "who read this child's record"

---

## Sources

- [The Data Protection Act 2017 (Act No. 20 of 2017) — full text](https://www.fscmauritius.org/media/105843/the-data-protection-act-2017.pdf)
- [Data Protection Act 2017 — ILO NATLEX copy](https://natlex.ilo.org/dyn/natlex2/natlex2/files/download/108724/MUS108724.pdf)
- [Mauritius Data Protection Office](https://dataprotection.govmu.org)
- [Controller/processor registration form](https://dataprotection.govmu.org/Pages/Home%20-%20Pages/Take%20Action/Application%20form%20processor(registration%20and%20renewal).pdf)
- [DLA Piper — Breach notification in Mauritius](https://www.dlapiperdataprotection.com/?t=breach-notification&c=MU)
- [DLA Piper Africa / Juristconsult — the 2020 regulations](https://www.dlapiperafrica.com/en/mauritius/insights/2020/new-data-protection-regulations-.html)
