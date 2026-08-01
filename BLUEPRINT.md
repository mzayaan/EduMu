# EduMU — School Management System for Mauritian Secondary Schools
## Full Analysis & Implementation Blueprint

**Version** 1.0 · **Date** 1 August 2026 · **Author** Zayaan
**Scope decision** Single school, multi-tenant-ready schema
**Stack decision** React (Vite) + TypeScript SPA · Supabase (Postgres + Auth + RLS + Storage + Edge Functions)

---

## Table of Contents

**Part A — Domain Analysis**
1. Executive Summary
2. The Mauritian Secondary Education System
3. The Academic Calendar
4. Assessment, Examinations & Grading
5. Actors, Roles & Responsibilities
6. The Paper Inventory — Every Register, Book, Form and Process

**Part B — Product Definition**
7. Product Vision, Goals, Non-Goals
8. Module Specifications (M1–M12)
9. Role × Screen Matrix
10. Non-Functional Requirements

**Part C — Technical Design**
11. Stack Selection & Rationale
12. System Architecture
13. Data Model — Full Schema
14. Security Model — Auth, RBAC, RLS
15. Core Algorithms (Timetable, Exams, Grading, Promotion)
16. Edge Functions & API Surface
17. Storage, Documents & PDF Generation
18. Offline, Notifications, i18n

**Part D — Delivery**
19. Reporting & Analytics
20. Data Migration & Onboarding
21. Testing Strategy
22. Phased Roadmap
23. Risks & Mitigations
24. Open Questions

---
---

# PART A — DOMAIN ANALYSIS

## 1. Executive Summary

Mauritian secondary schools run a **seven-year programme, Grade 7 to Grade 13**, inside the Nine-Year Continuous Basic Education (NYCBE) framework introduced in 2016. Almost every operational process in these schools is still paper-based: attendance registers taken twice daily, a lateness book, a movement book, attendance cards carried by class captains, hand-written mark sheets consolidated into report books, timetables drawn by hand by the Deputy Rector, occurrence log books, assets registers, visitors' books, and a filing cabinet organised by an "ABC code" system that the official School Management Manual still prescribes.

This creates four systemic failures:

| Failure | Concrete symptom |
|---|---|
| **Latency** | A parent learns their child has been absent 11 times only at the end of term. |
| **Fragility** | One water-damaged register destroys a term of attendance evidence. The 80%-attendance rule for exam eligibility becomes unenforceable. |
| **Labour** | Deputy Rector spends 2–3 weeks each January hand-solving the timetable. Mark consolidation for 900 students × 8 subjects × 3 terms is done by hand into report books. |
| **Blindness** | No school can answer "which Grade 9 students are at risk of failing NCE Maths and also have <75% attendance?" without a manual audit. |

**EduMU** digitises the whole operational surface of a secondary school — enrolment, attendance, discipline, marks, report cards, promotion, timetabling, exam logistics, staff administration, and parent communication — while keeping the artefacts recognisable to the people who use them today. A form teacher should see something that looks like the register they already know. A rector should be able to print a document that looks like the one they already sign.

Design principle throughout: **do not invent a new bureaucracy; make the existing one instant.**

---

## 2. The Mauritian Secondary Education System

### 2.1 Structural map

| Grades | Level | Delivered in | Terminal assessment |
|---|---|---|---|
| 1–6 | Basic Education (Primary) | Primary schools | **PSAC** (Primary School Achievement Certificate) |
| **7–9** | Basic Education (Lower Secondary) | Regional Secondary Schools | **NCE** (National Certificate of Education) |
| **10–11** | Upper Secondary | Regional Secondary Schools / Academies | **SC** — Cambridge School Certificate / GCE O-Level |
| **12–13** | Upper Secondary | Regional Secondary Schools / Academies / Polytechnics | **HSC** — Higher School Certificate / GCE A-Level |

Legacy naming still in daily use inside schools — the system **must support both** and map between them:

| New | Legacy |
|---|---|
| Grade 7 | Form I |
| Grade 8 | Form II |
| Grade 9 | Form III |
| Grade 10 | Form IV |
| Grade 11 | Form V |
| Grade 12 | Lower VI |
| Grade 13 | Upper VI |

### 2.2 Entry, streams and tracks

- **Grade 7 admission** is regional: parental choice + overall PSAC grading + proximity of residence, within the four maintained **Education Zones**. Admission is by an official **letter of admission** — no student may be admitted without one.
- **Extended Programme**: learners not making the grade follow a four-year cycle instead of three, in a special reduced-size class in every secondary school, on the same but adapted core curriculum, with mobility permitted between Extended and Regular streams. (The old Prevocational stream no longer exists.) *This is a first-class modelling requirement, not an edge case.*
- **From Grade 10** students choose one of three paths: stay in their current school, move to an **Academy** (national-basis admission, Grades 10–13, centres of excellence specialising in 2–3 areas), or enter a **vocational school**. Both General and Technical education run side by side; students may sit **SC (General)** or **SC (Technical)**.
- **Polytechnics** exist in every zone, delivering to Diploma level, entered after Grade 11, Grade 13, or a vocational programme + foundation.

### 2.3 School ownership types

| Type | Managed by | Note |
|---|---|---|
| State Secondary School (SSS) | Ministry of Education, via Zone Directorate | Rector is a public officer |
| Grant-aided private secondary school | Private Secondary Education Authority (PSEA/PSSA) | Ministry-funded, own management |
| Confessional / private fee-paying | Own boards | Fees module matters most here |
| Academy | Ministry, greater autonomy, new management model | Grades 10–13 only |

This is why **multi-tenancy is designed in from day one** even though we launch on one school: the same product must later serve a grant-aided school with a Manager and a fee ledger, and an Academy with no Grades 7–9 at all.

### 2.4 Curriculum shape (drives the subject/option data model)

**Grades 7–9 (NCE):** 3 compulsory subjects — English, Mathematics, French — plus **4 electives** drawn from strands:

- **Humanities** — Arabic, Hindi, Marathi, Modern Chinese, Tamil, Telugu, Urdu, History, Geography, etc.
- **Science** — Chemistry, Physics, Biology
- **Technical Studies** — Home Economics, Design & Technology (CDT), Visual Arts, Computer Studies
- **Social Sciences** — Social Studies, Accounting, Economics, Entrepreneurship Education

**Grades 10–11 (SC):** subject combinations of roughly 6–8 subjects, constrained by school-defined option blocks (e.g. "Science block", "Commerce block") plus a compulsory core.

**Grades 12–13 (HSC):** 3 subjects at **Principal** level + 1–2 at **Subsidiary** level + **General Paper** + compulsory **Computer Science/Studies** in most configurations.

**Modelling consequence:** subject enrolment is *per-student*, not *per-class*. A Grade 10 "class" is an administrative home group; the actual teaching groups are **subject sets** that cut across classes. Any system that models "class has subjects" instead of "student has subject enrolments" will break at Grade 10 and be unusable at Grade 12. This is the single most important schema decision in the document.

---

## 3. The Academic Calendar

### 3.1 Official calendar — Academic Year 2026 (verified)

Published by the Ministry of Education and Human Resource, communiqué dated 11 December 2025.

| Term | Start | End |
|---|---|---|
| **First Term** | Monday 12 January 2026 | Friday 3 April 2026 |
| **Second Term** | Monday 20 April 2026 | Friday 17 July 2026 |
| **Third Term** | Monday 17 August 2026 | Friday 30 October 2026 |

Special dates:
- **Mon 12 Jan 2026** — Admission day: Grade 1 (primary), **Grade 7 (regional secondary schools)**, **Grade 10 (Academies)**.
- **Tue 13 Jan 2026** — Resumption of all other classes.
- Breaks: 4–19 April, 18 July–16 August (long winter break), and end-of-year from 31 October.

### 3.2 What the system must derive from this

The calendar is not decorative — it is the spine of the data model. Every attendance record, timetable slot, assessment window and report card is keyed to it.

The system stores an `academic_year` with ordered `terms`, then **generates a day-by-day school calendar** by:

1. Expanding each term into weekdays (Mon–Fri).
2. Subtracting **public holidays** — Mauritius has a moving set including New Year (1–2 Jan), Thaipoosam Cavadee, Abolition of Slavery (1 Feb), Chinese Spring Festival, Maha Shivaratree, Ugadi, National Day (12 Mar), Labour Day (1 May), Eid-ul-Fitr, Ganesh Chaturthi, All Saints' Day (1 Nov), Arrival of Indentured Labourers (2 Nov), Divali, Christmas. Several are **lunar/computed and shift annually** → they must be a maintained table, never hard-coded.
3. Subtracting school-specific closure days (sports day, prize-giving, exam-only days, cyclone closures).
4. Marking **cyclone / torrential-rain closures** retroactively — a Class III cyclone warning closes all schools nationally at short notice. The system needs a "declare non-school day" action that retro-voids attendance for that date, un-schedules lessons, and notifies parents. **This is a genuine Mauritian requirement most off-the-shelf SIS products get wrong.**
5. Marking the **cycle day** (see §15.1) — schools typically run a repeating 5-day or 10-day timetable cycle, which drifts out of sync with the weekday whenever a holiday falls mid-week.

### 3.3 The intra-term rhythm

| When | What happens |
|---|---|
| Week 1 of Term 1 | Admissions, class allocation, subject/option selection, Class Captain & Vice-Captain elections, timetable published |
| Week 2 of each term | Educators submit **Schemes of Work** via HODs to the Rector |
| Weekly | Weekly Plan of Work with a "remarks" column recording work actually completed |
| Continuous | Daily lesson plans, homework, class work, marked exercise books |
| Mid-term / end of term | **Term tests** and internal examinations (must not exceed 10 days) |
| July (Term 2) | **Mock examinations** for SC/HSC candidates |
| Term 3 | NCE, SC, HSC national examinations; revision; end-of-year internal exams for non-exam grades |
| End of year | Promotion decisions, report books issued, prize-giving, Leaving Certificates |

---

## 4. Assessment, Examinations & Grading

### 4.1 The two parallel assessment systems

Every Mauritian secondary school runs **two assessment systems simultaneously**, and they must be modelled separately because they have different owners, scales, and lifecycles.

**(a) Internal assessment — owned by the school**
- Class tests, homework, projects, practicals
- Term tests
- End-of-term / end-of-year internal examinations
- July mock examinations
- Feeds the **report book** and the **promotion decision**

**(b) National / external assessment — owned by MES and Cambridge**
- **NCE** at Grade 9 — administered by the **Mauritius Examinations Syndicate (MES)**; a combination of **written papers and School-Based Assessment (SBA)**
- **SC / GCE O-Level** at Grade 11 — MES in collaboration with **Cambridge Assessment International Education**
- **HSC / GCE A-Level** at Grade 13 — same
- The school's job here is **entries, fees, candidate data, seating, invigilation accommodation, and results ingestion** — not marking

### 4.2 Grading scales to support

The system must treat grading scales as **configurable data, not code**. At minimum, ship these:

| Scale | Used for | Bands |
|---|---|---|
| **Percentage** | Internal tests and exams | 0–100 |
| **SC numerical grades** | Cambridge School Certificate | 1 (≥75), 2 (≥60), 3 (≥50), 4 (≥40), 5 (≥30), 6 (<30); 7/8 ungraded — *thresholds are indicative and must be admin-editable* |
| **HSC** | A-Level | A–E at Principal level; Subsidiary pass grades; points aggregate |
| **NCE** | Grade 9 | Achievement bands + SBA component weighting |
| **Internal letter scale** | School-defined | e.g. A/B/C/D/E/U with own cut-offs |

**Requirement:** a `grading_scale` + `grading_band` pair of tables, versioned by academic year, so that changing a cut-off in 2027 does not retroactively re-grade 2026 report cards. Historical grades are stored **as awarded**, with the scale version referenced.

### 4.3 Rules the system must encode (from the School Management Manual)

These are real, quotable rules that translate directly into validations and automated flags:

**Exam eligibility**
- The school insists on **at least 80% attendance** before July mock examinations and end-of-year internal examinations, and during Term 3.
- A student may be **prevented from sitting** tests/examinations for persistent absence despite school efforts.
- Students with high absences may be **debarred from competing** for certain awards.
- Attendance is **recorded on the Leaving Certificate**.

**Internal exams**
- Internal examinations **must not last more than ten days**.
- The Rector controls all internal examinations.
- Should a student not make the required grades at end-of-year internal exams, the Rector may act (repeat / conditional promotion).

**Promotion to Lower VI (Grade 12)**
- Passed Cambridge SC with **at least 4 credits at one and the same sitting**, or
- GCE O-Level in **5 subjects** with minimum specified performance
- Age relief clauses: a student who would be disqualified by age from Lower VI, or who cannot repeat Form V under the "no class repeated more than once" internal rule, may be exceptionally promoted

**Promotion to Upper VI (Grade 13)**
- The Lower VI end-of-year examination is **mandatory for all** Lower VI students
- Pass in **at least 2 subjects at Principal level** and **2 at Subsidiary level**
- Otherwise repeat Lower VI if not over-aged; if barred by age or having already repeated twice, the student may be entered for **GCE A-Level in at least 2 subjects in lieu of HSC**, with the Responsible Party informed **in writing**

**General repetition**
- A student may repeat a class after failing it, and is asked to leave after failing the same class twice
- Exception path: promotion may still be considered where the **average mark at the second-year end-of-year exam is at least 35%**, **attendance at the second attempt is above 75%**, or there was **prolonged absence supported by a medical certificate**

**Age rules**
- A pupil may not remain after attaining **age 18** unless qualified for admission to Form VI by obtaining SC or an acceptable equivalent; a pupil turning 18 after sitting the exam may remain until results are known
- Students must be told **at the start of the school year** if they are not eligible to repeat SC or HSC

**State of Mauritius Scholarship**
- Eligibility constraints on number of attempts, on supplementary certificates showing a credit in a sixth subject, and on **absences exclusive of authorised absences** — the system must be able to compute the authorised/unauthorised split accurately for exactly this purpose

**Design consequence:** all of the above live in a **Promotion Rules Engine** (§15.4) as declarative, editable, year-versioned rules — never as hard-coded `if` statements. The rules change; the engine should not.

---

## 5. Actors, Roles & Responsibilities

### 5.1 Full actor catalogue

**Inside the school — management**

| Actor | Real-world responsibility | What they need from the system |
|---|---|---|
| **Rector** | Overall management. Administrative (committees, meetings, staff supervision, resources), pedagogical (curriculum control, monitoring teaching & learning), socio-cultural (health standards, environment, community). Controls all internal examinations. Enters students for SC/HSC. Empowered by the Education Act to make rules for administration and discipline. | Whole-school dashboard, approvals queue, discipline escalations, exam control, staff appraisal, printable statutory documents, Ministry reporting pack |
| **Deputy Rector** | Deputises for the Rector. **Prepares the school timetable.** Assists in enforcing discipline. Monitors Educators' work with Rector and HODs. | Timetable builder + solver, daily substitution board, register monitoring, class visit / appraisal records |
| **Head of Department (HOD)** | Works out a syllabus per form with departmental Educators; determines the portion of syllabus per term; convenes Departmental Meetings; **vets Schemes of Work before submission to Rector**; keeps a department file; mentors less-experienced Educators. | Department workspace: scheme-of-work review queue, syllabus coverage tracker, departmental results analysis, meeting notes, mentoring log |
| **School Superintendent / Usher** | Monitors student attendance closely; **issues attendance cards to Class Captains in the morning and collects them in the afternoon**; ensures students on register are actually in class; brings violations to Rector immediately; member of both **Disciplinary Committee** and **Pastoral Care Committee**; supervises movement and bus boarding. | Live attendance discrepancy board (register vs. class), lateness capture, movement log, incident capture on mobile, gate/bus duty |
| **Assistant School Superintendent** | Supports the Usher. | Same, scoped |

**Inside the school — teaching**

| Actor | Real-world responsibility | What they need |
|---|---|---|
| **Educator (subject teacher)** | Teaches to pupils' educational needs; sets and corrects class work and homework; assesses performance, records difficulties and weaknesses, submits subject reports; guides pupils; maintains parent communication; maintains discipline in and out of class; must be *in attendance* during the lesson. Prepares Scheme of Work, Weekly Plan of Work, Daily Lesson Plan. | Fast mark entry, homework set/collect, per-student difficulty notes, subject report writer, scheme/plan submission, my-timetable, class list with photos |
| **Form Teacher** | Owns the class. Monitors attendance closely; keeps faithful records of **lateness, absences and cases of indiscipline**; inculcates values; brings violations to the Rector. | The register (the app's most-used screen), class pastoral view, report book assembly, parent contact log |
| **Assistant Form Teacher** | Shares the Form Teacher role. | Same, delegated |
| **Educator (Extended Programme)** | Adapted core curriculum, reduced class size. | Adapted assessment recording, individual support plans |

**Inside the school — administrative & ancillary**

| Actor | Responsibility | Needs |
|---|---|---|
| **School Clerk / Administrative Officer** | Files, books, ledgers, registers; incoming/outgoing mail with tracking; the ABC filing system; confidentiality. | Document register (in/out mail), student & staff file management, admissions data entry, certificate issuance |
| **Word Processing Operator** | Typing, saving documents under ABC codes. | Templated document generation |
| **Library Officer** | Stock of reference books, reading books, magazines; lending. | Catalogue, loans, overdue, "returned library books" check on leaving |
| **Laboratory Technician / Lab Auxiliary** | **Prepares practical-work timetable**, **lab and specialist-room utilisation timetable**, **keeps ledger of equipment and updates stock**. | Lab booking, practical scheduling, equipment ledger, consumables stock, safety/incident log |
| **Bursar / Accounts** | Cash books, ledgers, fees (grant-aided/private), PTA funds. | Fee ledger, receipts, PTA accounts, procurement |
| **IT Technician** | Computer room, devices, network. | Asset register, device assignment, ticket queue |
| **Caretaker / General Worker / Security** | Premises, maintenance, visitors' book. | Maintenance requests, visitor log |
| **Matron / Health focal point** | Health standards, water-quality certificates, first aid. | Health incident log, medical alerts on student records, water-quality certificate expiry reminders |

**Students**

| Actor | Responsibility | Needs |
|---|---|---|
| **Student** | Follows Rules & Regulations from the moment they leave home, in school buses and on premises. | Timetable, homework, marks, attendance record, notices |
| **Class Captain / Vice Class Captain** | Elected within the **first week of resumption**. Ensures discipline per school rules; **keeps custody of the Attendance Card** and produces it on demand; maintains order between periods and during an Educator's absence. | Digital attendance card handoff, "teacher absent" flag, class notices |
| **Prefect** | Helps Rector and Educators maintain discipline school-wide, on buses, sports day, inter-college competitions, tours. | Duty roster, incident reporting |
| **Student Council member** | Student voice, office bearers. | Council workspace, motions, notice publishing |

**Parents & community**

| Actor | Responsibility | Needs |
|---|---|---|
| **Responsible Party (parent/guardian)** | Legally named on admission form. Must supply an **Absence Note the next day** after absence; applies **in writing** for leave of absence; receives a **regular return of attendance**; acknowledges receipt of School Rules. | Portal + SMS: attendance alerts, absence-note submission, results, report card, homework, notices, meeting bookings, fee status |
| **PTA Executive** | Registered association; AGM and Executive Committee meetings; procures sports/leisure facilities; assists during exam periods to control absenteeism. | PTA workspace, membership, meeting minutes, fund ledger, event management |
| **Alumni / Old Students Association** | Contributes to prevention of indiscipline, mentoring, prize-giving. | Directory, event invitations |

**External / above the school**

| Actor | Responsibility | System touchpoint |
|---|---|---|
| **Zone Director / Zone Directorate** | Approves student leave up to 3 months; processes transfer requests; provides Educational Psychologist support; receives escalations. | Read-only zone dashboard, transfer request workflow, statistical returns |
| **Director, School Management (Ministry)** | Approves leaves exceeding 3 months. | Approval workflow |
| **Ministry of Education (MoE)** | Policy, circulars, statistical returns, performance indicators tied to Budget. | Circular repository, standardised statistical export |
| **Mauritius Examinations Syndicate (MES)** | Runs PSAC, NCE, SC, HSC; requires accommodation at schools; entries and fees. | Entry file export, candidate data, results import, room accommodation booking |
| **Cambridge Assessment International Education** | SC/HSC syllabuses and grading. | Syllabus code reference data |
| **Mauritius Institute of Education (MIE)** | Curriculum (NCF), teacher training. | CPD records against staff |
| **PSEA/PSSA** (grant-aided) | Manager role, funding. | Manager approvals, grant reporting |
| **Educational Psychologist (zone)** | Pastoral referrals, with parental written consent. | Referral workflow with consent capture |
| **Police / Local Authority / Health services** | Incidents, health campaigns. | Incident escalation record, campaign scheduling |

### 5.2 Committees as first-class objects

The Manual makes committees structural, not ad-hoc. The system models a generic **Committee** entity with members, meeting schedule, agenda, minutes, decisions and follow-up actions. Seeded types:

- **Disciplinary Committee** — receives gross/repeated indiscipline referred by the Rector; Usher is a member; issues decisions communicated to the Responsible Party (by registered letter with *avis de réception* where required)
- **Pastoral Care Committee** — includes a caring parent (not necessarily PTA Exec); handles students who are irregular in attendance, underperforming, or at risk; **keeps a record of each case**; may involve external agencies **with the parent's written consent**; decides which cases escalate to Disciplinary
- **Staff Welfare Committee**
- **Sports Committee**
- **Event Organising Committee**
- **School Magazine Editing Committee**
- **Pedagogical Committee** — examines the "dashboard" of pedagogical issues
- **Departmental meetings** — per subject department
- **Student Council**
- **PTA Executive Committee**

Every staff member is expected to be involved in at least one activity or committee — so committee membership is also a **workload/contribution** signal for appraisal.

### 5.3 Application role taxonomy (what we actually implement)

Roles are **not** a single enum on the user. A person can be an Educator *and* a Form Teacher *and* an HOD *and* a Disciplinary Committee member — simultaneously, and only for a given academic year.

```
Identity (auth.users)
   └── person (staff | student | guardian)
         └── role_assignment (role, scope, academic_year, valid_from, valid_to)
```

**Role scopes:**

| Scope | Meaning | Example |
|---|---|---|
| `school` | Whole tenant | Rector, Deputy Rector, Clerk |
| `department` | One subject department | HOD Mathematics |
| `class` | One home class | Form Teacher of 10A |
| `subject_set` | One teaching group | Educator of "Grade 10 Physics Set 2" |
| `committee` | One committee | Pastoral Care member |
| `self` | Own record only | Student |
| `ward` | Linked students only | Responsible Party |

**Base roles shipped:** `super_admin` (vendor), `school_admin`, `rector`, `deputy_rector`, `hod`, `educator`, `form_teacher`, `usher`, `clerk`, `librarian`, `lab_tech`, `bursar`, `it_admin`, `counsellor`, `student`, `class_captain`, `prefect`, `guardian`, `pta_exec`, `zone_officer` (read-only), `ministry_observer` (read-only, aggregate).

Permissions are **capability strings** (`attendance.mark`, `marks.enter`, `marks.publish`, `discipline.escalate`, `timetable.publish`, `student.read.pii`) mapped to roles in a table, so a school can tune them without a deployment.

---

## 6. The Paper Inventory — Every Register, Book, Form and Process

This section is the heart of the analysis. The School Management Manual explicitly enumerates the records a school must keep. Below, **every one of them** is mapped to its digital replacement, its owner, and its non-obvious traps.

### 6.1 Resources & assets records

| Paper artefact | Today | Digital replacement | Traps |
|---|---|---|---|
| **School Profile** | A typed document, updated rarely | `school` record + auto-generated profile page (roll, staff FTE, rooms, results history) | Must be exportable in the Ministry's requested shape |
| **Space Audit** | Manual survey of rooms | `room` table: type (classroom/lab/workshop/IT room/library/hall), capacity, features, floor, block | Capacity drives both timetabling and exam seating |
| **Assets Register** | Bound register | `asset` table: tag, category, location, custodian, acquisition date, cost, condition, disposal | Needs periodic **verification runs** with a signed printout |
| **Ledgers** | Handwritten | `ledger_entry` per fund (school fund, PTA fund, lab consumables) | Grant-aided schools need this to reconcile with PSEA |
| **Inventory Sheets** | Per-room sheets | Generated per room from `asset` | Room-change moves must be logged, not overwritten |
| **Cash Books** | Handwritten | `cash_book` with receipts/payments, bank reconciliation | Out of scope for Phase 1 in a State school; Phase 3 for private |
| **Timetable** | Hand-drawn, photocopied | Timetable engine (§15.1) | The *master* artefact; everything else keys off it |

### 6.2 Pedagogy records

| Paper artefact | Today | Digital replacement | Traps |
|---|---|---|---|
| **Syllabi** | Per form, per subject, worked out by HOD | `syllabus` → `syllabus_unit` tree, versioned per academic year, linked to NCF/Cambridge codes | HOD determines **the portion to be covered each term** — model `term_allocation` |
| **Schemes of Work** | Educator writes; **HOD vets**; submitted to Rector by **week 2 of the term** | `scheme_of_work` with week-by-week learning objectives, plus revision & assessment strategies; submission workflow `draft → hod_review → rector_approved` with due-date reminders | Must support "returned with comments"; must keep a department-file archive |
| **Weekly Plan of Work** | Notebook, period-wise, with a **remarks column** for work actually completed | `weekly_plan` with rows per timetable period, `planned` vs `actual` + remarks | The remarks column is the real value — it's the coverage-slippage signal. Feed it into a **syllabus coverage %** metric per class |
| **Daily Lesson Plans** | Educator's own notebook, must be *in possession* | `lesson_plan`: objectives, procedure, method, activities, resources, evaluation, homework set | Do **not** force this into a rigid form; allow attachment/free text or it won't be adopted |
| **Records of Work** | What was actually taught | Derived from `weekly_plan.actual` + `lesson` completion | — |
| **Examination Reports** | Typed per exam | Auto-generated analytics pack (§19) | — |
| **Notes of meetings** (HOD, Departmental, Pedagogical Committee) | Minute books | `meeting` + `minute` + `action_item` with owners and due dates | Actions must appear in the owner's task list, or minutes stay decorative |
| **Calendar of Activities** | Established by Rector at start of each term | `calendar_event` on the school calendar | Drives scheme-of-work planning — publish before schemes are due |
| **Performance data and trends** | Spreadsheets | Analytics module | Needs historical import to be useful in year 1 |

### 6.3 Administration records — the daily-friction core

| Paper artefact | Today | Digital replacement | Traps |
|---|---|---|---|
| **Attendance Register (students)** | Taken **twice daily** (morning & afternoon). Monitored daily by Form Teacher, Usher, Deputy Rector, Rector. **Students must not have access to it.** | `attendance_session` (AM/PM per class per day) + `attendance_record` per student | Two sessions/day is mandatory, not optional. Access control is a stated rule → students must never see the register write surface |
| **Attendance Card (students)** | Physical card issued by Usher to **Class Captain each morning**, returned each afternoon. Subject teachers mark period attendance on it to catch class-shirking. | `period_attendance` per timetable period, entered by the subject Educator on their device | This is the highest-value digitisation in the whole product: it turns a manual cross-check into an automatic one. **Discrepancy rule:** present on AM register but absent in period X ⇒ auto-flag to Usher within minutes |
| **Lateness Book** | Separate bound book | `attendance_record.status = late` + `minutes_late`, plus a lateness report | Keep it queryable per student per term — it feeds pastoral referrals |
| **Movement Book (students)** | Signing in/out during the day | `student_movement`: out/in, reason, authorised_by, escort | Needed for safeguarding: "who authorised this child leaving at 11:20?" |
| **Attendance Register (staff)** | Bound register, signed | `staff_attendance` with arrival/departure; optionally QR/PIN | Sensitive industrially — must be configurable and auditable, never silently punitive |
| **Movement Book (staff)** | Leaving premises during hours | `staff_movement` with reason and approver | — |
| **Students' Records / personal files** | A physical file per student; first elements are the **admission form** + birth certificate; updated until they leave | `student` + `student_document` (typed, versioned, access-controlled) | Retention & deletion policy needed. Birth certificate is high-sensitivity PII |
| **Staff Records** | Personal files | `staff` + `staff_document` + qualifications + CPD | Payroll stays out of scope (Ministry-run for SSS) |
| **Notes of meetings (staff, SMT)** | Minute books | `meeting` module | — |
| **School Rules and Regulations** | Printed, **given to each parent on admission and after each review**, with acknowledged receipt | `policy_document` versioned + `acknowledgement` per guardian per version | The acknowledgement is a legal artefact — timestamp + IP + version hash |
| **PTA Rules and Regulations** | Printed | Same mechanism | — |
| **Contracts for services** | Filed copies | `contract` with vendor, dates, value, renewal reminders | — |

### 6.4 "Other" records

| Paper artefact | Digital replacement | Notes |
|---|---|---|
| **Records of indiscipline** | `incident` → `disciplinary_case` → `sanction`, with the **Student Information Sheet** as a structured profile compiled from staff/stakeholder input | The Manual describes this sheet as *"a written record of the indiscipline history"* used by the Rector and Pastoral Care Committee. Model it as a generated view over incidents, not a free-text blob |
| **Occurrence Log Book** | `occurrence_log` — append-only, timestamped, signed, immutable | **Must be genuinely append-only** (no UPDATE/DELETE, corrections as new entries). This is the school's evidential record |
| **Confidential Book for Ministry officials** | `confidential_note` with restricted RLS visible only to Rector + named Ministry roles | Encrypt at rest; separate audit trail |
| **Visitors' Book** | `visitor_log` with sign-in/out, host, badge, purpose | Safeguarding-relevant; consider QR self-check-in on a tablet |
| **Infrastructure Maintenance Book** | `maintenance_request` → work order → completion, with photos | Links to `room` and `asset` |
| **Circulars from the Ministry** | `circular` repository: number, date, subject, attachment, acknowledgement, affected roles | Searchable archive is a genuinely loved feature — schools lose circulars constantly |
| **Historical performance statistics** | Analytics warehouse tables | Import at least 3 prior years at onboarding |
| **The ABC filing system** | `document` with `abc_code` (first letter of keyword), `unique_file_number`, `file_name`, drawer mapping | **Keep it.** Don't force schools off a system they navigate fluently — mirror it as metadata so physical and digital stay reconcilable during transition |
| **Incoming/outgoing mail book** | `correspondence` — direction, date, sender/recipient, subject, UFN, assigned officer, status | The Manual explicitly asks for a tracking system identifying the officer to whom a document was channelled — so `assigned_to` + a full handoff trail |
| **Notice Boards** | `notice` with audience targeting (whole school / staff / class / role) + a physical-board print view | The Manual lists exactly what must be displayed (§6.6) — auto-compose that pack |

### 6.5 Student lifecycle processes

**Admission (Grade 7 and mid-year transfers)**
1. Official **letter of admission** issued centrally — no admission without it
2. Responsible Party completes the **admission form** at school
3. **Birth certificate** produced and copied
4. Personal file opened (admission form + birth certificate as first elements)
5. Eligibility check for **class and the subject combination opted for** — if ineligible, admission is refused/redirected
6. School Rules & Regulations issued; receipt acknowledged
7. Class allocation, subject/option selection, ID card issued

→ Digital: an **Admission Workflow** with letter reference, document upload + verification checkboxes, automated eligibility validation against the option-block rules, e-acknowledgement of rules, auto-generated student ID with photo, and auto-enrolment into `subject_set`s.

**Transfer in / out**
- All vacancies in State schools are filled by a **central transfer exercise at the Ministry**; requests go to the **Zone Director**, not processed at school level
- On leaving, the Rector issues a **Leaving Certificate**, only after the student has returned: **report book, Student Identity Card, library books, and other school property**

→ Digital: a **Clearance Checklist** that blocks Leaving Certificate generation until every item is cleared (library integration checks outstanding loans automatically), plus attendance summary printed on the certificate as required.

**Leave of absence**
- Responsible Party applies **in writing**, with dates
- **Zone Director** approves up to **3 months**
- Beyond 3 months → forwarded to **Director, School Management**
- Student must resume on expiry; extension must be requested **before** the leave period ends
- Failure to resume without an extension request → struck off

→ Digital: a **Leave of Absence workflow** with an auto-routing rule on duration, an expiry countdown, an automatic reminder to the guardian before expiry, and an automatic "non-resumption" flag to the Rector on day 1 after expiry.

**Absence (day-to-day)**
- Absence explained by the Responsible Party via an **Absence Note the next day**
- Only absence notes or **medical certificates** count as authorised
- Responsible Party **promptly contacted** on unauthorised absence
- School sends a **regular return of attendance** to all Responsible Parties

→ Digital: guardian submits an absence note in the portal (or replies to SMS); unauthorised absence triggers a same-morning automated contact; a scheduled job emails/SMSes each guardian a periodic attendance return. Authorised vs unauthorised split is preserved because scholarship eligibility depends on it.

**Promotion / repetition / leaving** → see §15.4.

### 6.6 The Notice Board pack (auto-composed)

The Manual prescribes exactly what must be displayed. The system generates a printable pack and a digital board:

Vision & Mission · Class and teacher timetables · List of classes with room number, roll, class captains and Student Council reps · Staff list (teaching, administrative, ancillary) · List of Form Teachers · List of Prefects · Student Council office bearers · PTA Executive Committee members · Members of clubs and committees · School Calendar · Important activities with dates · **Certificate of Water Quality with date tanks were last cleaned** · Class lists · Examination timetables · plus a positive-recognition board.

The water-quality certificate is a nice illustration of why a generic SIS fails here: it needs an expiry reminder and a document slot that no imported product will have.


### 6.7 Communication rhythms to support

| Channel | Cadence | System support |
|---|---|---|
| **Morning Assembly** | Almost daily, ≤15 min | Assembly notes / announcements published to the digital board and archived |
| **Staff meetings** | Regular | Meeting module with agenda, attendance, minutes, actions |
| **Departmental meetings** | Regular, per department | Same, scoped to department |
| **SMT meetings** | Regular | Same, confidential scope |
| **Committee meetings** | ≥2 per term for several committees | Same |
| **Meetings with administrative staff** (office, library, lab) | Regular | Same |
| **Meetings with PTA President** | Regular contacts, AGM, Exec meetings | PTA workspace |
| **Parent convocations** | Rector convenes parents of low performers | Auto-generated invitation list from performance triggers + booking slots |
| **Letters to parents** | As needed; registered letters with *avis de réception* for disciplinary matters | Letter templates, merge fields, print + post tracking, delivery-proof upload |
| **Working session before national exam entries** | Annually | Exam entry workflow with checklist |

---
---

# PART B — PRODUCT DEFINITION

## 7. Vision, Goals, Non-Goals

**Vision.** Every register, mark, timetable and letter that a Mauritian secondary school produces on paper, produced instantly and correctly instead — with the same look, the same signatures, and none of the waiting.

**Primary goals (measurable)**

| Goal | Baseline | Target |
|---|---|---|
| Time to publish a term timetable | 2–3 weeks manual | < 1 day, including manual adjustment |
| Time for a guardian to learn of an unauthorised absence | Days to weeks | < 90 minutes from AM register close |
| Time to produce report books for the whole school | 1–2 weeks of clerical work | < 1 hour after marks lock |
| Marks lost / registers damaged per year | Non-zero | Zero |
| Time for the Rector to answer a Ministry statistical return | Half a day | One click |
| Register–class discrepancy detection (shirking) | Manual spot-checks | Automatic, same period |

**Non-goals (explicitly out of scope)**

- Payroll for State-school staff (Ministry-run)
- Replacing MES/Cambridge marking — we handle entries and results ingestion only
- A learning-management system with content authoring and video (we do homework + resources, not courseware)
- National-level Ministry data platform (the schema is ready for it; the product is not)
- Biometric attendance hardware in Phase 1 (QR/PIN only)

**Guiding constraints**

1. **Low bandwidth / intermittent connectivity.** Registers must work with a flaky connection; marks entry must never lose keystrokes.
2. **Shared devices.** Many schools have a staff room with 2–3 PCs. Fast user switching, short session timeouts, no "remember me" on shared machines.
3. **Mobile-first for Educators and Guardians**, desktop-first for Clerk/Deputy Rector/Bursar.
4. **Trilingual reality.** UI in **English and French** (English default, French essential — official communiqués and parent letters are frequently French); Kreol Morisien copy for parent-facing SMS where useful.
5. **Print is a first-class output.** Anything statutory must produce a clean A4 PDF.

---

## 8. Module Specifications

### M1 — School Setup & Academic Structure

*Owner: School Admin / Rector · Frequency: annual*

- **School profile**: name, type (state / grant-aided / private / academy), zone, address, contacts, logo, motto, vision & mission, roll capacity, session model (single / double session)
- **Academic year**: create year, define terms with real start/end dates (seeded with the official 2026 dates), lock/close year
- **Calendar generator**: expands terms → school days; public holidays table (maintained annually, incl. lunar-computed dates); school closure days; **cyclone/emergency closure action** with retroactive attendance voiding and mass notification
- **Timetable cycle definition**: 5-day or 10-day cycle, periods per day, period start/end times, break/lunch, assembly slot, double-period rules
- **Rooms**: code, name, type (classroom, science lab, computer room, workshop, home-ec room, art room, library, hall, gym), capacity, exam capacity, features
- **Grades & classes**: grade levels 7–13 with legacy Form mapping; classes per grade (e.g. 10A–10E); stream type (**Regular / Extended / Technical / General**); class capacity; assigned home room; assigned Form Teacher + Assistant
- **Departments** and HOD assignment
- **Subjects**: code, name, strand (Humanities / Science / Technical Studies / Social Sciences / Core), levels offered, NCE/Cambridge syllabus code, whether practical, weekly period allocation per grade
- **Option blocks**: named blocks per grade with mutually exclusive subject choices and min/max selections — this is what enforces valid subject combinations at admission and at Grade 10/12 transitions
- **Grading scales & bands**, versioned per year
- **Rules configuration**: attendance thresholds (default 80% exam eligibility, 75% second-attempt promotion), internal exam max duration (10 days), repeat limits, age limits

### M2 — People: Students, Staff, Guardians

*Owner: Clerk · Frequency: continuous*

**Student record**
Identity (name, preferred name, sex, DOB, National ID/birth-certificate ref, nationality, religion where recorded for language-subject allocation), photo, admission (letter ref, date, entry grade, PSAC/transfer origin), contacts, address + region (drives bus routes and proximity policy), medical alerts and allergies, special educational needs, Extended Programme flag, house/team, transport mode and bus route, prior school, sibling links, documents (birth certificate, PSAC result, medical, photos), status lifecycle (`applicant → enrolled → on_leave → transferred_out → left → struck_off → alumnus`).

**Guardian / Responsible Party**
One student may have several; exactly one is the legally designated **Responsible Party**. Fields: relationship, occupation, phone(s), email, preferred language, preferred channel (SMS/email/app), consent flags (photography, external agency referral, data sharing), custody/access restrictions, rules-acknowledgement history.

**Staff record**
Employment (post, scheme of service, grade, appointment date, confirmation, employment type), subject qualifications and teaching load capacity, department, roles held per year, timetable, qualifications and CPD/MIE training, appraisal records and class-visit notes, leave balances and history, documents, emergency contacts, exit.

**Bulk operations**: CSV import with a validation preview and a dry-run diff, photo batch upload matched on admission number, mass promotion at year rollover.

### M3 — Enrolment, Classes & Subject Sets

*Owner: Deputy Rector / Clerk · Frequency: start of year + rolling*

- **Class allocation**: assign enrolled students to classes with balance helpers (sex ratio, PSAC/NCE performance banding, region, siblings-apart rules)
- **Subject enrolment per student** — the core design point from §2.4. A student's subject list is validated against the option blocks for their grade and stream.
- **Subject sets (teaching groups)**: a set has a subject, a grade, a level (Core/Extended/Principal/Subsidiary), one or more Educators, a preferred room, and a roster of students that may span home classes. Sets are what the timetable actually schedules.
- **Set movement**: move a student between sets mid-term with an effective date, carrying their marks history correctly (marks belong to student+subject+assessment, not to the set).
- **Roll returns**: number on roll per class/grade/sex, as at any date — the number the Ministry asks for constantly.

### M4 — Attendance

*Owner: Form Teacher, Educator, Usher · Frequency: 2× daily + every period*

This is the most-used module in the product and must be ruthlessly fast.

**Daily register (AM / PM)**
- Form Teacher opens the register for their class; default all-present; tap to change
- Statuses: `present`, `absent_unauthorised`, `absent_authorised`, `late` (+ minutes), `on_leave` (approved leave of absence), `excluded` (suspension), `school_activity` (off-site but present for statutory purposes)
- Closes automatically at a configured cut-off; late edits require a reason and are audit-logged
- **Students must never have write access, and never read access to the class register** — enforced in RLS, not just UI

**Period attendance (the digital Attendance Card)**
- Subject Educator marks their set each period, pre-populated from the AM register
- **Discrepancy engine**: present on AM register but absent in a period ⇒ instant alert to the Usher's live board with the student, the period, the Educator and the location; the Usher resolves with an outcome (`found_on_premises`, `left_school`, `medical_room`, `authorised`, `unresolved`)
- Also flags the inverse: absent on the register but marked present in class

**Guardian-side**
- Automated same-morning notification for unauthorised absence (SMS/app), in the guardian's preferred language
- Guardian submits an **Absence Note** with optional medical-certificate upload; the Form Teacher/Usher approves, converting `unauthorised → authorised`
- Scheduled **attendance return** to every Responsible Party (configurable: weekly/monthly/termly)

**Lateness & movement**
- Lateness capture at the gate by the Usher (search by name/photo/ID, one tap)
- **Movement log**: sign-out/sign-in during the day with reason, authoriser and escort — safeguarding-critical

**Staff attendance** — arrival/departure, movement out of premises with reason and approver, absence reasons feeding the substitution engine

**Derived metrics** — attendance % per student/class/grade/subject per term and per year, authorised vs unauthorised split (needed for scholarship rules), consecutive-absence streaks, at-risk lists at the configured thresholds, class-level trend to spot a struggling Form Teacher or a timetable problem

### M5 — Curriculum, Planning & Homework

*Owner: HOD, Educator · Frequency: termly / weekly / daily*

- **Syllabus builder**: units and objectives per subject per grade per year, tagged to NCF or Cambridge syllabus codes; **HOD sets the portion to be covered each term**
- **Scheme of Work workflow**: Educator drafts week-by-week objectives (must include revision and assessment strategies), submits by the week-2 deadline → HOD vets → Rector approves. Statuses, comments, return-for-revision, automated deadline reminders, and a department-file archive.
- **Weekly Plan of Work**: rows generated automatically from the Educator's actual timetable for that week; `planned` vs `actual` + remarks. Drives **syllabus coverage %** per set, surfaced on the Rector's and HOD's dashboards — the earliest reliable warning that a class is falling behind.
- **Lesson plans**: light structured form (objectives, procedure, methods, activities, resources, evaluation, homework) with attachment support; deliberately not mandatory-field-heavy
- **Homework**: set with due date, attached resources, per-set or per-student; visible to students and guardians; submission status; a "quantum of homework" heat-map per class per week so no class gets six subjects' homework on the same night
- **Resources**: files per unit, shared at department level

### M6 — Assessment, Marks & Report Books

*Owner: Educator, HOD, Rector · Frequency: continuous + termly peaks*

**Assessment definition**
- `assessment` types: class test, homework, project, practical, **term test**, **end-of-term exam**, **end-of-year exam**, **July mock**, **SBA component** (NCE), national exam (external)
- Per assessment: subject, grade/set scope, date window, max mark, weighting toward the term aggregate, grading scale, whether it counts toward promotion

**Marks entry**
- Grid view: students × assessments for one set, keyboard-driven, autosave, **works offline and syncs**
- Validation: mark ≤ max, non-numeric absence codes (`ABS`, `EXEMPT`, `MED`, `DEBARRED`)
- Import from a spreadsheet with a column-mapping preview
- Status lifecycle: `draft → submitted (Educator) → moderated (HOD) → published (Rector/Deputy)`. Guardians and students see **nothing until published** — a hard requirement; premature leakage of marks is a real reputational risk.
- Full audit trail on every mark change after submission, with reason

**Computation**
- Weighted term aggregate per subject → grade via the year's scale
- Overall aggregate, rank in set, rank in class, rank in grade (with configurable tie handling and an option to suppress ranks)
- Subject teacher comment + **recorded difficulties and weaknesses** (an explicit duty of the Educator), Form Teacher comment, Rector comment
- Attendance summary auto-inserted (this is required on the Leaving Certificate and expected on reports)

**Report Book**
- Generated PDF per student per term, in the school's existing layout (logo, grade, class, subjects, marks, grades, ranks, comments, attendance, signature blocks)
- Cumulative report book showing all three terms plus the year result
- Batch generation for a whole class/grade with a single job, downloadable as a zip or printed as one merged PDF in class order
- Guardian receives it in the portal, with an option for print-only schools

**Analysis**
- Per-set and per-subject distributions, pass rates, mean/median, comparison against grade and against previous terms
- Value-added: NCE → SC trajectory, mock → actual SC correlation
- The **examination report** the Rector currently types, generated automatically

### M7 — Timetabling

*Owner: Deputy Rector · Frequency: annual + continuous adjustment*

Full algorithm in §15.1. Functionally:

- **Inputs**: cycle definition, rooms, subject sets with weekly period requirements, Educator availability and load limits, room-type requirements (labs, workshops, IT room), double-period requirements for practicals, Educator part-time days, "no PE right before lunch" style soft rules
- **Solver**: constraint-based generation producing several candidate timetables with a quality score, then a **drag-and-drop manual editor** with live conflict detection — the Deputy Rector must always be able to override. A solver that cannot be overridden will not be adopted.
- **Outputs**: master timetable, per-class timetable, per-Educator timetable, per-room timetable, per-student timetable (matters from Grade 10 up, where sets diverge), printable notice-board pack
- **Versioning**: publish v1, v2… with effective dates; everything downstream (period attendance, lesson records) references the version in force on that date
- **Lab / specialist-room utilisation timetable** and **practical-work timetable** — explicitly a Lab Technician duty in the Manual, so give them their own booking surface for ad-hoc sessions on top of the fixed grid
- **Daily cover / substitution board**: staff absence in → uncovered periods out → suggested substitutes ranked by free period, subject match, and fairness of cover load already carried this term → publish to the staff room screen and push to the substitute's phone. Class Captains can flag "no teacher arrived" which surfaces here too.

### M8 — Examinations & Logistics

*Owner: Rector, Deputy Rector · Frequency: 3–4 peaks per year*

**Internal examinations**
- Exam session with date range, **validated against the 10-day maximum**
- Exam timetable builder (papers, durations, no student clash across their own subject set, rest-gap rules)
- **Eligibility screening**: automatic list of students below the 80% attendance threshold, with a Rector decision (`allow` / `debar`) recorded per student per session and communicated to guardians
- **Room and seating allocation**: capacity-aware, with configurable seating strategies (alternate subjects, no two students of the same class adjacent, spacing), producing printable seating plans and desk labels
- **Invigilation roster**: duty allocation across Educators, fairness-balanced, with clash checks against their own teaching, printable duty slips, and a swap-request workflow
- **Attendance and irregularity capture** per paper (absent candidates, malpractice reports, incidents)
- **Script tracking**: issued → collected → distributed to markers → returned → marks entered

**National examinations (NCE / SC / HSC)**
- Candidate entry management: subject entries per student, entry deadlines, **fee computation and payment tracking**, entry file export in the MES-required format
- Candidate numbers and centre numbers stored against students
- MES **accommodation booking**: the Ministry's policy is to provide school premises to MES and the Public/Disciplined Forces Service Commission for exams — model as a room-blocking event that also closes the school day for affected classes
- **Results ingestion**: import result files, map to students, publish; then automatic promotion evaluation, statistical analysis, and the school's results report
- SBA component tracking for NCE with internal deadlines and moderation status

### M9 — Discipline, Pastoral Care & Safeguarding

*Owner: Usher, Form Teacher, Rector, committees*

- **Incident capture** in under 20 seconds on a phone: student(s), category, location, time, description, witnesses, severity, optional photo
- Categories seeded from the rules: uniform, punctuality, mobile phone use (prohibited during classes and examinations), bullying/extortion, damage, absconding, violence, prohibited substances, academic dishonesty
- **Progressive escalation ladder**: verbal warning → Form Teacher counselling → parent contact → **Special Report** (formally monitoring work, conduct and attendance for a period) → Pastoral Care Committee → Disciplinary Committee → suspension/exclusion, with mandated notification steps
- **Merits alongside demerits** — the Manual specifically wants recognition: bonus marks or delegated responsibility for well-disciplined students, and **certificates of good behaviour issued on Prize-Giving Day**, especially for lower forms. A discipline module that only records bad news will be resented by staff and students.
- **Student Information Sheet**: a generated profile pulling attendance, marks, incidents, home context and staff observations — used by the Rector and Pastoral Care Committee
- **Pastoral Care Committee workspace**: case list (irregular attendance, underperformance, at-risk), case notes with restricted visibility, **written parental consent capture** before any external-agency referral, referral to the Zone Educational Psychologist, review dates, outcome recording
- **Disciplinary Committee workspace**: referral, hearing scheduling, guardian summons (letter template + registered-post tracking with *avis de réception*), decision, sanction, appeal
- **Occurrence Log** — append-only, immutable, timestamped, attributable

### M10 — Staff Administration & Operations

*Owner: Rector, Deputy Rector, Clerk*

- Staff directory, records and documents
- **Leave management**: application → approver by type and duration → balance ledger → calendar → automatic feed into the substitution engine
- **Class visits & appraisal**: scheduled observation, structured rubric, evidence, feedback conversation, development actions — an explicit Rector/Deputy/HOD duty
- **CPD/MIE training records** against each staff member
- **Committee management**: the generic committee entity from §5.2 — membership, meeting scheduling, agenda, attendance, minutes, decisions, action items with owners and due dates that appear in personal task lists
- **Meeting module** shared across staff meetings, SMT, departmental, pedagogical, PTA
- **Correspondence register**: incoming/outgoing mail with the ABC/UFN scheme, assigned officer, deadline tracking, and full handoff trail
- **Circular repository** with role-targeted acknowledgement
- **Document generation**: letters to parents, convocations, certificates (good behaviour, attendance, **Leaving Certificate**), attestations — templated with merge fields and a signature block

### M11 — Facilities, Assets, Library & Health

*Owner: Clerk, Lab Tech, Librarian, IT, Matron*

- **Asset register** with tag, category, location, custodian, condition, verification runs and disposal
- **Inventory per room**, generated, with move history
- **Maintenance requests** → work orders → completion with photos, linked to room/asset
- **Lab management**: equipment ledger, consumables stock with reorder levels, practical scheduling, safety incidents, chemical register
- **Library**: catalogue, loans, returns, overdue, reservations — and the automatic hook into student clearance on leaving
- **IT assets** and device assignment
- **Visitors' log** with sign-in/out and host
- **Health**: medical alerts on the student record, first-aid/incident log, medication administration record, **water-quality certificates with expiry reminders**, health campaign scheduling with external services

### M12 — Communication, Portals & Notifications

*Owner: all · the module that determines whether parents perceive any value*

- **Notice board**: audience-targeted (whole school / staff / a grade / a class / a role / a committee), scheduled publication, read receipts, plus a print view for the physical boards and the auto-composed statutory display pack (§6.6)
- **Guardian portal**: children switcher, attendance (with absence-note submission), timetable, homework, marks *once published*, report books, notices, fee status, meeting bookings, document downloads, rules acknowledgement
- **Student portal**: timetable, homework, resources, own marks, own attendance, notices, club/committee memberships
- **Messaging**: school → guardian broadcast and 1:1 Educator ↔ guardian threads, with an archive that satisfies the "maintain regular communication with parents" duty and gives the school an evidence trail
- **SMS gateway** integration — non-negotiable in Mauritius, since app adoption among guardians will not reach 100% and SMS is what actually gets read
- **Emergency broadcast**: cyclone closure, early dismissal — one action, all channels, all guardians, with delivery reporting
- **PTA workspace**: membership, AGM and Exec meetings, minutes, fund ledger, events
- **Parent–teacher meeting scheduler** with slot booking, auto-invitation of parents of low performers (the Rector's convocation duty, automated)

---

## 9. Role × Screen Matrix

Legend: ● full · ◐ scoped/partial · ○ read-only · — none

| Screen / capability | Rector | Dep. Rector | HOD | Educator | Form Tchr | Usher | Clerk | Student | Guardian |
|---|---|---|---|---|---|---|---|---|---|
| Whole-school dashboard | ● | ● | ◐ dept | — | — | ◐ | ○ | — | — |
| Student record (full PII) | ● | ● | ○ dept | ◐ own sets | ◐ own class | ◐ | ● | ◐ self | ◐ ward |
| Admission workflow | ● | ◐ | — | — | — | — | ● | — | ◐ submit |
| Daily register (AM/PM) | ○ | ○ | — | — | ● own class | ● all | ○ | — | ○ ward |
| Period attendance | ○ | ○ | ○ dept | ● own sets | ○ own class | ● all | — | — | ○ ward |
| Discrepancy board | ○ | ● | — | — | ○ | ● | — | — | — |
| Absence note approval | ● | ● | — | — | ● | ● | ◐ | — | ◐ submit |
| Leave-of-absence workflow | ● | ◐ | — | — | ○ | — | ● | — | ◐ apply |
| Marks entry | ○ | ○ | ● dept | ● own sets | ○ own class | — | — | — | — |
| Marks moderation | ● | ● | ● dept | — | — | — | — | — | — |
| Marks publication | ● | ◐ | — | — | — | — | — | — | — |
| Report book generation | ● | ● | ○ | ◐ comment | ● own class | — | ● print | ○ self | ○ ward |
| Timetable builder | ● | ● | ◐ propose | — | — | — | — | — | — |
| My timetable | ● | ● | ● | ● | ● | ● | ● | ● | ○ ward |
| Substitution board | ● | ● | ○ | ○ own | ○ | ● | — | — | — |
| Exam session setup | ● | ● | ◐ | — | — | — | ◐ | — | — |
| Seating & invigilation | ● | ● | ○ | ○ own duty | ○ | ● | ◐ print | ○ own seat | — |
| National exam entries | ● | ◐ | ◐ | — | — | — | ● | ○ own | ○ ward |
| Incident capture | ● | ● | ● | ● | ● | ● | — | — | — |
| Disciplinary Committee | ● | ● | ◐ member | ◐ member | ○ own class | ● | — | — | ○ own case |
| Pastoral Care Committee | ● | ● | ◐ member | ◐ member | ◐ | ● | — | — | ◐ consent |
| Occurrence log | ● | ● | ○ | ◐ append | ◐ append | ● | ○ | — | — |
| Confidential book | ● | — | — | — | — | — | — | — | — |
| Scheme of Work | ● approve | ● | ● vet | ● submit | — | — | — | — | — |
| Syllabus coverage | ● | ● | ● dept | ○ own | — | — | — | — | — |
| Staff records & leave | ● | ◐ | ○ dept | ◐ self | ◐ self | ◐ self | ● | — | — |
| Class visit / appraisal | ● | ● | ● dept | ○ own | — | — | — | — | — |
| Assets, library, lab | ○ | ○ | ◐ | ◐ | — | ◐ | ● | ○ library | — |
| Notices | ● | ● | ◐ dept | ◐ own sets | ◐ own class | ◐ | ● | ○ | ○ |
| Messaging with guardians | ● | ● | ● | ● | ● | ● | ● | — | ● |
| Fees / PTA ledger | ● | ○ | — | — | — | — | ● | — | ○ own |
| Ministry statistical returns | ● | ◐ | — | — | — | — | ◐ | — | — |
| Audit log | ● | ○ | — | — | — | — | — | — | — |

---

## 10. Non-Functional Requirements

**Performance**
- Register screen interactive in **< 1.5 s on 3G**, and fully usable offline thereafter
- Marks grid: 40 students × 12 assessments renders and accepts input with **no perceptible input lag**
- Report-book batch of 1,000 students completes in **< 10 minutes** (async job with progress)
- Timetable solve for a 900-student school: first viable solution **< 2 minutes**, refined solutions streaming thereafter

**Availability & resilience**
- Target 99.5% during school hours (07:00–17:00 MUT), maintenance outside term time where possible
- **Offline-first for attendance and marks entry** — the two things staff will be doing when the connection drops. Local queue, conflict-aware sync, visible sync status.
- Cyclone season: the system must be usable from home; emergency broadcast must work when the school building is closed

**Security & privacy**
- Mauritius **Data Protection Act 2017** applies (GDPR-aligned): lawful basis, purpose limitation, data-subject rights, breach notification to the Data Protection Office. Children's data is high-risk by definition.
- Row-Level Security enforced in Postgres for **every** table — never trusted to the client
- Encryption in transit (TLS) and at rest; separate handling for confidential notes and medical data
- MFA available for Rector/Deputy/Clerk/Admin; enforced for `super_admin`
- Full audit log of reads on sensitive PII and all writes to marks, attendance, discipline
- Configurable retention and a documented deletion policy; export-on-request for data subjects
- Session timeout tuned short for shared staff-room devices

**Accessibility & usability**
- WCAG 2.1 AA; keyboard-complete for the marks grid; large tap targets for the phone-based register
- Legible on a 5-year-old Android phone and on a staff-room PC at 1366×768

**Localisation**
- **English** (default) and **French** UI, per-user preference; guardian communications in the guardian's preferred language including Kreol Morisien templates for SMS
- Dates `dd/mm/yyyy`, currency MUR, timezone `Indian/Mauritius` (UTC+4, no DST) — store `timestamptz`, render local

**Compatibility & operations**
- Modern evergreen browsers + Android WebView; no IE
- Print CSS for A4; PDFs generated server-side for anything statutory
- Automated nightly backups with tested restore; point-in-time recovery
- Environment separation (dev / staging / prod) with a Supabase branch per PR

**Scale (multi-tenant readiness)**
- Design point: 1 school, ~1,200 students, ~90 staff, ~1,500 guardian accounts with a few hundred active daily
- Headroom: 50 schools, 60,000 students on the same schema without redesign — achieved via `school_id` on every table and partitioning-ready design on the two hot tables (`attendance_record`, `mark`)

---
---

# PART C — TECHNICAL DESIGN

## 11. Stack Selection & Rationale

### 11.1 The stack

| Layer | Choice | Why |
|---|---|---|
| **Frontend** | **React 19 + Vite + TypeScript** (SPA) | You asked for light. No server runtime to operate, no SSR cache to reason about, a single static bundle on a CDN. Fast dev loop, trivial deploys. |
| **UI** | **Tailwind CSS + shadcn/ui** + Radix primitives | Copy-in components (no runtime dependency lock-in), accessible by default, easy to restyle to the school's identity. |
| **Routing** | **TanStack Router** (or React Router 7 in data mode) | Typed routes, loaders, and route-level code splitting keep the initial bundle small. |
| **Server state** | **TanStack Query** | Caching, background refetch, optimistic updates, and — critically — a persisted cache that underpins offline mode. |
| **Forms** | **React Hook Form + Zod** | One Zod schema shared by the form, the API boundary, and generated types. |
| **Tables/grids** | **TanStack Table** + virtualisation | The marks grid and register need virtualised rendering at 40×12 and beyond. |
| **Offline** | **Vite PWA plugin** (Workbox) + IndexedDB outbox + TanStack Query persister | Registers and marks entry must survive connection loss. |
| **Charts** | **Recharts** | Sufficient for the analytics module; small. |
| **Backend / DB** | **Supabase**: Postgres 16, Auth (GoTrue), PostgREST, Realtime, Storage, Edge Functions (Deno) | Mandated. RLS in Postgres is the right place for this domain's access rules — the rules are genuinely row-shaped ("my class", "my sets", "my ward"). |
| **Heavy compute** | **Web Workers** (timetable solver, batch PDF, CSV parsing) | Keeps the serverless model intact; no extra infrastructure to run a solver. |
| **PDF** | `@react-pdf/renderer` in a worker for single + small batches | Statutory documents get pixel control and offline generation. |
| **Whole-school PDF batches** | One small containerised job worker (Playwright) on Fly.io/Railway, triggered by a `job` row | The single justified exception to "serverless only" — see §11.3. |
| **SMS** | Local Mauritian gateway (e.g. Rogers/Emtel/MTML bulk SMS) behind an Edge Function adapter | Provider is swappable; the adapter interface is not. |
| **Email** | Resend or Postmark via Edge Function | — |
| **Hosting** | Vercel / Netlify / Cloudflare Pages (static) | Any of them; the app is a static bundle. |
| **Errors/analytics** | Sentry + PostHog (self-host optional for data-residency comfort) | — |
| **Testing** | Vitest, Testing Library, Playwright, pgTAP for RLS | RLS must be tested at the database level, not through the UI. |
| **CI/CD** | GitHub Actions + Supabase CLI migrations + preview branches | Every PR gets a Supabase branch and a preview URL. |

### 11.2 Why not Next.js

Next.js is the conventional answer and would be defensible — SSR helps printing and SEO for a public site. But: this product is **100% authenticated**, has **no SEO surface**, and needs **offline behaviour** that fights SSR. Running a Node server adds an operational dimension for no benefit here. A static SPA + Supabase means the only thing you operate is the database. If a public-facing marketing/admissions site is needed later, ship it as a separate static site.

### 11.3 The one non-serverless piece

Generating 1,200 report-book PDFs must not depend on a teacher's laptop staying awake. The pattern:

```
Client enqueues job row  →  Realtime/webhook wakes the worker  →
Playwright renders each report from a print route  →
PDFs written to Supabase Storage  →  job row updated  →
Client shows progress via Realtime subscription
```

The worker is ~150 lines, scales to zero, and costs a few dollars a month. Everything else stays inside Supabase.

### 11.4 Repository layout

```
edumu/
├─ apps/web/                 # Vite React SPA
│  ├─ src/
│  │  ├─ app/                # routes
│  │  ├─ features/           # attendance, marks, timetable, discipline, ...
│  │  │  └─ attendance/{api,components,hooks,schemas,types}
│  │  ├─ components/ui/      # shadcn
│  │  ├─ lib/                # supabase client, offline outbox, i18n, pdf, rbac
│  │  ├─ workers/            # timetable-solver.worker.ts, pdf.worker.ts
│  │  └─ types/database.ts   # generated from Supabase
├─ packages/
│  ├─ domain/                # pure TS: grading, promotion rules, attendance maths
│  └─ shared-schemas/        # Zod schemas shared with edge functions
├─ supabase/
│  ├─ migrations/            # timestamped SQL
│  ├─ functions/             # deno edge functions
│  ├─ seed/                  # subjects, holidays, grading scales, MU reference data
│  └─ tests/                 # pgTAP RLS tests
└─ services/pdf-worker/      # the one container
```

**Rule:** all business rules that decide an outcome (promotion, eligibility, grading, attendance %) live in `packages/domain` as pure functions **and** are mirrored as Postgres functions where they must be enforced server-side. Never in a component.

---

## 12. System Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                      CLIENT (Vite SPA / PWA)                  │
│  Routes → Features → TanStack Query → supabase-js             │
│  Web Workers: timetable solver · PDF · CSV                    │
│  IndexedDB: query cache + offline outbox (attendance, marks)  │
└───────────────┬───────────────────────────────────────────────┘
                │ HTTPS · JWT (school_id + roles in app_metadata)
┌───────────────▼───────────────────────────────────────────────┐
│                          SUPABASE                             │
│                                                               │
│  Auth (GoTrue)  ── custom access-token hook injects           │
│                     school_id, role list, person_id           │
│                                                               │
│  PostgREST  ──►  Postgres 16                                  │
│                   ├─ RLS on every table (the real API)        │
│                   ├─ SECURITY DEFINER RPCs for multi-step ops │
│                   ├─ Triggers: audit, derived stats, alerts   │
│                   ├─ Materialised views for analytics         │
│                   └─ pg_cron: nightly rollups, reminders      │
│                                                               │
│  Realtime  ──►  discrepancy board, substitution board,        │
│                 job progress, notice publication              │
│                                                               │
│  Storage   ──►  photos · documents · report PDFs · imports    │
│                 (RLS-backed buckets)                          │
│                                                               │
│  Edge Functions (Deno):                                       │
│    sms-send · email-send · exam-entry-export ·                │
│    results-import · notification-dispatch ·                   │
│    ministry-return · webhook receivers                        │
└───────────────┬───────────────────────────────────────────────┘
                │
    ┌───────────▼──────────┐   ┌──────────────────────────┐
    │ PDF batch worker     │   │ SMS gateway (MU) / Email │
    │ (Playwright, Fly.io) │   │                          │
    └──────────────────────┘   └──────────────────────────┘
```

**Key architectural decisions**

1. **The database is the API.** PostgREST + RLS. Edge Functions exist only for things Postgres shouldn't do: talking to third parties, and long-running orchestration.
2. **JWT carries `school_id`, `person_id` and role list** via a custom access-token hook, so RLS predicates are cheap index lookups instead of recursive joins on every row.
3. **Multi-tenancy by `school_id` column + RLS**, not schema-per-tenant. Simpler migrations, and a single school today.
4. **Append-only tables are enforced by RLS**, not convention: `occurrence_log`, `audit_log` and `mark_history` grant `INSERT` and `SELECT` only, to everyone, including admins.
5. **Derived data is materialised, not computed on read.** Attendance percentages, term aggregates and rankings are maintained by triggers/jobs into summary tables — a report book must never trigger a 12-table aggregate per student.
6. **Everything is year-scoped.** `academic_year_id` on virtually every operational table. Closing a year makes it read-only via RLS.

---

## 13. Data Model

### 13.1 Entity map

```
school ─┬─ academic_year ─┬─ term
        │                 ├─ calendar_day ── holiday / closure
        │                 └─ timetable_version ── timetable_slot
        ├─ department ── subject ── syllabus ── syllabus_unit
        ├─ room
        ├─ grade_level ── class_group ── class_enrolment
        ├─ option_block ── option_block_subject
        ├─ subject_set ─┬─ set_enrolment
        │               └─ set_educator
        ├─ person ─┬─ student ─┬─ student_guardian ── guardian
        │          │           ├─ student_document
        │          │           └─ student_status_event
        │          └─ staff ─┬─ staff_role_assignment
        │                    ├─ staff_leave
        │                    └─ staff_document
        ├─ attendance_session ── attendance_record
        ├─ period_attendance ── attendance_discrepancy
        ├─ student_movement / staff_movement / visitor_log
        ├─ assessment ── mark ── mark_history
        ├─ grading_scale ── grading_band
        ├─ term_result ── report_card
        ├─ exam_session ─┬─ exam_paper ── exam_seat
        │                ├─ invigilation_duty
        │                └─ exam_eligibility_decision
        ├─ national_exam_entry ── national_exam_result
        ├─ incident ── disciplinary_case ── sanction
        ├─ committee ── committee_member ── meeting ── minute ── action_item
        ├─ occurrence_log / confidential_note / audit_log
        ├─ notice / message_thread / message / notification
        ├─ asset / maintenance_request / library_item / loan
        └─ correspondence / circular / policy_document / acknowledgement
```

### 13.2 Foundations

```sql
-- Every table carries school_id. Every table carries created_at/by, updated_at/by.
create table school (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name              text not null,
  type              school_type not null,          -- state | grant_aided | private | academy
  zone              smallint,                      -- 1..4 education zones
  address           jsonb,
  contact           jsonb,
  logo_path         text,
  vision            text,
  mission           text,
  settings          jsonb not null default '{}',   -- feature flags, thresholds, locale
  created_at        timestamptz not null default now()
);

create table academic_year (
  id            uuid primary key default gen_random_uuid(),
  school_id     uuid not null references school,
  name          text not null,                     -- '2026'
  starts_on     date not null,
  ends_on       date not null,
  status        year_status not null default 'planning', -- planning|active|closed
  unique (school_id, name)
);

create table term (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references school,
  academic_year_id  uuid not null references academic_year on delete cascade,
  sequence          smallint not null check (sequence between 1 and 4),
  name              text not null,                 -- 'First Term'
  starts_on         date not null,
  ends_on           date not null,
  unique (academic_year_id, sequence),
  check (ends_on > starts_on)
);

-- Seed for 2026 (official):
--  1 First Term  2026-01-12 → 2026-04-03
--  2 Second Term 2026-04-20 → 2026-07-17
--  3 Third Term  2026-08-17 → 2026-10-30

create table public_holiday (
  id          uuid primary key default gen_random_uuid(),
  country     char(2) not null default 'MU',
  year        smallint not null,
  date        date not null,
  name        text not null,
  is_computed boolean not null default false,      -- lunar / movable
  unique (country, date, name)
);

create table calendar_day (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references school,
  academic_year_id  uuid not null references academic_year,
  term_id           uuid references term,
  date              date not null,
  day_type          day_type not null,   -- teaching|holiday|weekend|closure|exam_only|activity
  cycle_day         smallint,            -- 1..N in the timetable cycle; null on non-teaching days
  closure_reason    text,                -- 'Cyclone Class III', 'Prize Giving'
  note              text,
  unique (school_id, academic_year_id, date)
);
```

`calendar_day` is generated by an RPC `generate_school_calendar(year_id)` and is the **single source of truth** for "was there school on this date" — attendance, timetable expansion and coverage metrics all read it. The `cycle_day` column is what keeps a 10-day cycle correct across holidays.

### 13.3 Academic structure

```sql
create table department (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  name text not null, code text not null,
  hod_staff_id uuid,                                -- nullable, set per year via role assignment
  unique (school_id, code)
);

create table subject (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  department_id uuid references department,
  code text not null,                               -- 'MATH', 'PHYS'
  name_en text not null,
  name_fr text,
  strand subject_strand,                            -- core|humanities|science|technical|social_science
  is_practical boolean not null default false,
  requires_room_type room_type,                     -- lab/workshop/computer_room
  external_codes jsonb,                             -- {cambridge:'4024', nce:'...'}
  unique (school_id, code)
);

create table grade_level (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  grade smallint not null check (grade between 7 and 13),
  legacy_form text,                                 -- 'Form I' ... 'Upper VI'
  cycle_stage text,                                 -- lower_secondary | upper_secondary_sc | upper_secondary_hsc
  unique (school_id, grade)
);

create table class_group (                          -- the home class, e.g. 10A
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  academic_year_id uuid not null references academic_year,
  grade_level_id uuid not null references grade_level,
  name text not null,                               -- '10A'
  stream stream_type not null default 'regular',    -- regular|extended|technical|general
  home_room_id uuid references room,
  capacity smallint,
  unique (academic_year_id, name)
);

create table room (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  code text not null, name text not null,
  room_type room_type not null,
  capacity smallint not null,
  exam_capacity smallint,                           -- usually lower than teaching capacity
  block text, floor smallint,
  features text[],
  unique (school_id, code)
);

-- Option blocks: how valid subject combinations are enforced
create table option_block (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  academic_year_id uuid not null references academic_year,
  grade_level_id uuid not null references grade_level,
  name text not null,                               -- 'Block A', 'Science Combination'
  min_choices smallint not null default 1,
  max_choices smallint not null default 1
);
create table option_block_subject (
  option_block_id uuid references option_block on delete cascade,
  subject_id uuid references subject,
  primary key (option_block_id, subject_id)
);

-- The teaching group. THIS is what gets timetabled.
create table subject_set (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  academic_year_id uuid not null references academic_year,
  grade_level_id uuid not null references grade_level,
  subject_id uuid not null references subject,
  name text not null,                               -- 'G10 Physics Set 2'
  level set_level,                                  -- core|extended|principal|subsidiary
  periods_per_cycle smallint not null,
  double_periods smallint not null default 0,
  preferred_room_id uuid references room,
  max_size smallint
);
create table set_educator (
  subject_set_id uuid references subject_set on delete cascade,
  staff_id uuid not null,
  is_primary boolean not null default true,
  primary key (subject_set_id, staff_id)
);
create table set_enrolment (
  id uuid primary key default gen_random_uuid(),
  subject_set_id uuid not null references subject_set,
  student_id uuid not null,
  effective_from date not null,
  effective_to date,                                -- null = current
  unique (subject_set_id, student_id, effective_from)
);
```

**Note the shape:** `set_enrolment` is temporal (`effective_from`/`effective_to`), which is what lets a student move sets mid-term without corrupting historical registers or marks.

### 13.4 People

```sql
create table person (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  auth_user_id uuid unique,                         -- references auth.users; null for people without logins
  person_type person_type not null,                 -- student|staff|guardian
  first_name text not null, last_name text not null,
  preferred_name text,
  sex sex_type, date_of_birth date,
  national_id text, photo_path text,
  email citext, phone text, phone_alt text,
  preferred_language char(2) not null default 'en', -- en|fr|mfe
  address jsonb,
  created_at timestamptz not null default now()
);

create table student (
  id uuid primary key references person,
  school_id uuid not null references school,
  admission_number text not null,
  admission_letter_ref text,                        -- the official letter — required
  admitted_on date not null,
  entry_grade smallint,
  prior_school text,
  psac_result jsonb,
  is_extended_programme boolean not null default false,
  house text, transport_mode text, bus_route text,
  medical_alerts text[], allergies text[],
  sen_notes text,                                   -- restricted visibility
  status student_status not null default 'enrolled',
  left_on date, leaving_reason text,
  candidate_number text, centre_number text,        -- MES/Cambridge
  unique (school_id, admission_number)
);

create table guardian (
  id uuid primary key references person,
  occupation text,
  preferred_channel text not null default 'sms'     -- sms|email|app
);
create table student_guardian (
  student_id uuid references student,
  guardian_id uuid references guardian,
  relationship text not null,
  is_responsible_party boolean not null default false,
  has_custody boolean not null default true,
  can_collect boolean not null default true,
  contact_priority smallint not null default 1,
  primary key (student_id, guardian_id)
);
-- exactly one responsible party per student:
create unique index one_rp_per_student on student_guardian (student_id)
  where is_responsible_party;

create table staff (
  id uuid primary key references person,
  school_id uuid not null references school,
  staff_number text not null,
  post text not null,                               -- 'Educator', 'Rector', 'Usher', ...
  scheme_of_service text,
  employment_type text,                             -- permanent|contract|supply|part_time
  appointed_on date, confirmed_on date, exited_on date,
  department_id uuid references department,
  max_periods_per_cycle smallint,
  unavailable_slots jsonb,                          -- part-time patterns
  unique (school_id, staff_number)
);

create table class_enrolment (
  id uuid primary key default gen_random_uuid(),
  class_group_id uuid not null references class_group,
  student_id uuid not null references student,
  effective_from date not null,
  effective_to date,
  roll_number smallint,
  is_class_captain boolean not null default false,
  is_vice_captain boolean not null default false,
  is_prefect boolean not null default false
);
```

### 13.5 Roles

```sql
create table role (
  code text primary key,                            -- 'rector','hod','form_teacher',...
  name text not null,
  default_scope role_scope not null                 -- school|department|class|subject_set|committee|self|ward
);
create table capability (
  code text primary key,                            -- 'attendance.mark','marks.publish',...
  description text
);
create table role_capability (
  role_code text references role, capability_code text references capability,
  primary key (role_code, capability_code)
);
create table staff_role_assignment (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  academic_year_id uuid not null references academic_year,
  staff_id uuid not null references staff,
  role_code text not null references role,
  scope_type role_scope not null,
  scope_id uuid,                                    -- department/class_group/subject_set/committee id
  valid_from date not null, valid_to date
);
create index on staff_role_assignment (staff_id, academic_year_id, role_code);
```

The JWT hook reads `staff_role_assignment` for the active year and packs `{school_id, person_id, roles:[{code,scope_type,scope_id}]}` into the token. RLS helper functions (`app.has_capability(text)`, `app.teaches_set(uuid)`, `app.form_teacher_of(uuid)`, `app.is_guardian_of(uuid)`) read from the JWT claims.

### 13.6 Attendance (the hot path)

```sql
create table attendance_session (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references school,
  academic_year_id uuid not null references academic_year,
  class_group_id uuid not null references class_group,
  date date not null,
  session session_type not null,                    -- am | pm
  taken_by uuid references staff,
  taken_at timestamptz,
  status text not null default 'open',              -- open|closed|amended
  unique (class_group_id, date, session)
);

create table attendance_record (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  attendance_session_id uuid not null references attendance_session on delete cascade,
  student_id uuid not null references student,
  status attendance_status not null,                -- present|absent_unauth|absent_auth|late|on_leave|excluded|school_activity
  minutes_late smallint,
  note text,
  amended_by uuid, amended_at timestamptz, amend_reason text,
  unique (attendance_session_id, student_id)
);
create index on attendance_record (student_id, school_id);

create table period_attendance (                    -- the digital "attendance card"
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  timetable_slot_id uuid not null references timetable_slot,
  date date not null,
  subject_set_id uuid not null references subject_set,
  student_id uuid not null references student,
  status attendance_status not null,
  recorded_by uuid references staff,
  recorded_at timestamptz not null default now(),
  unique (subject_set_id, date, timetable_slot_id, student_id)
);

create table attendance_discrepancy (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null references student,
  date date not null,
  kind text not null,                               -- present_on_register_absent_in_class | inverse
  timetable_slot_id uuid, subject_set_id uuid,
  detected_at timestamptz not null default now(),
  resolved_by uuid, resolved_at timestamptz,
  outcome text                                      -- found_on_premises|left_school|medical_room|authorised|unresolved
);

create table absence_note (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null references student,
  submitted_by uuid references guardian,
  covers_from date not null, covers_to date not null,
  reason text not null,
  medical_certificate_path text,
  status text not null default 'pending',           -- pending|accepted|rejected
  decided_by uuid, decided_at timestamptz
);

create table leave_of_absence (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null references student,
  requested_on date not null,
  starts_on date not null, ends_on date not null,
  reason text not null,
  approver_level text not null,                     -- zone_director (<=3mo) | director_school_management (>3mo)
  status text not null default 'submitted',
  decided_on date, decision_ref text,
  extension_of uuid references leave_of_absence,
  resumed_on date
);

create table student_movement (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, student_id uuid not null references student,
  date date not null, out_at timestamptz, in_at timestamptz,
  reason text not null, authorised_by uuid references staff,
  collected_by text, escort text
);

-- Materialised summary, maintained by trigger + nightly job
create table attendance_summary (
  school_id uuid not null, academic_year_id uuid not null, term_id uuid not null,
  student_id uuid not null,
  sessions_possible int not null, sessions_present int not null,
  sessions_absent_unauth int not null, sessions_absent_auth int not null,
  times_late int not null,
  pct_present numeric(5,2) generated always as
    (case when sessions_possible = 0 then null
          else round(100.0*sessions_present/sessions_possible, 2) end) stored,
  primary key (term_id, student_id)
);
```

The `pct_present` column is what the 80% exam-eligibility rule and the 75% second-attempt promotion rule read. It is stored, not computed on demand.

### 13.7 Timetable

```sql
create table timetable_version (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null references academic_year,
  version smallint not null, label text,
  effective_from date not null, effective_to date,
  status text not null default 'draft',             -- draft|published|superseded
  cycle_length smallint not null default 5,         -- days in the cycle
  published_by uuid, published_at timestamptz,
  unique (academic_year_id, version)
);

create table period_definition (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, timetable_version_id uuid references timetable_version,
  sequence smallint not null,                       -- 1..n within a day
  name text not null,                               -- 'P1','Break','P2',...
  starts_at time not null, ends_at time not null,
  is_teaching boolean not null default true
);

create table timetable_slot (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  timetable_version_id uuid not null references timetable_version on delete cascade,
  cycle_day smallint not null,
  period_id uuid not null references period_definition,
  subject_set_id uuid not null references subject_set,
  room_id uuid references room,
  staff_id uuid references staff,
  is_double_start boolean not null default false
);
-- Hard constraints as DB constraints, so a bad manual edit is impossible:
create unique index tt_no_room_clash on timetable_slot (timetable_version_id, cycle_day, period_id, room_id)
  where room_id is not null;
create unique index tt_no_staff_clash on timetable_slot (timetable_version_id, cycle_day, period_id, staff_id)
  where staff_id is not null;
-- Student clashes are checked by a trigger against set_enrolment (can't be a unique index).

create table lesson_substitution (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, date date not null,
  timetable_slot_id uuid not null references timetable_slot,
  absent_staff_id uuid references staff,
  substitute_staff_id uuid references staff,
  reason text, status text not null default 'proposed',  -- proposed|accepted|declined|uncovered
  assigned_by uuid, assigned_at timestamptz
);

create table room_booking (                          -- labs, practicals, MES accommodation
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, room_id uuid not null references room,
  starts_at timestamptz not null, ends_at timestamptz not null,
  purpose text not null, booked_by uuid,
  blocks_teaching boolean not null default false,
  exclude using gist (room_id with =, tstzrange(starts_at, ends_at) with &&)
);
```

### 13.8 Assessment & results

```sql
create table grading_scale (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null,
  code text not null,                               -- 'PERCENT','SC','HSC','NCE','INTERNAL'
  name text not null,
  unique (academic_year_id, code)
);
create table grading_band (
  id uuid primary key default gen_random_uuid(),
  grading_scale_id uuid not null references grading_scale on delete cascade,
  label text not null,                              -- '1','2','A','U'
  min_score numeric(5,2), max_score numeric(5,2),
  points numeric(4,2), is_pass boolean, is_credit boolean,
  sort_order smallint not null
);

create table assessment (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null,
  term_id uuid references term,
  subject_set_id uuid references subject_set,       -- null = grade-wide (common paper)
  grade_level_id uuid, subject_id uuid,
  kind assessment_kind not null,                    -- class_test|homework|project|practical|term_test|end_of_term|end_of_year|mock|sba|external
  title text not null,
  scheduled_on date, max_score numeric(6,2) not null,
  weight numeric(5,2) not null default 1,           -- weight in the term aggregate
  grading_scale_id uuid references grading_scale,
  counts_for_promotion boolean not null default true,
  status text not null default 'draft'              -- draft|open|submitted|moderated|published
);

create table mark (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  assessment_id uuid not null references assessment on delete cascade,
  student_id uuid not null references student,
  score numeric(6,2),
  code text,                                        -- ABS|EXEMPT|MED|DEBARRED when score is null
  band_label text,
  comment text,
  entered_by uuid, entered_at timestamptz not null default now(),
  unique (assessment_id, student_id),
  check (score is not null or code is not null)
);
create table mark_history (                          -- append-only
  id bigserial primary key, mark_id uuid not null,
  old_score numeric(6,2), new_score numeric(6,2),
  old_code text, new_code text,
  changed_by uuid not null, changed_at timestamptz not null default now(),
  reason text
);

create table term_result (                           -- materialised per student per subject per term
  school_id uuid not null, term_id uuid not null, student_id uuid not null,
  subject_id uuid not null, subject_set_id uuid,
  aggregate_score numeric(6,2), band_label text,
  rank_in_set smallint, rank_in_grade smallint,
  educator_comment text, difficulties text,
  primary key (term_id, student_id, subject_id)
);

create table report_card (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, term_id uuid not null, student_id uuid not null,
  overall_score numeric(6,2), overall_rank smallint, class_size smallint,
  attendance_pct numeric(5,2), times_late int,
  form_teacher_comment text, rector_comment text,
  pdf_path text, status text not null default 'draft',  -- draft|published
  published_at timestamptz,
  unique (term_id, student_id)
);
```

### 13.9 Examinations

```sql
create table exam_session (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null, term_id uuid,
  kind text not null,                               -- term_test|end_of_term|end_of_year|mock|national
  name text not null, starts_on date not null, ends_on date not null,
  status text not null default 'planning',
  -- enforce the 10-day rule for internal exams:
  constraint internal_exam_max_10_days
    check (kind = 'national' or ends_on - starts_on <= 13)  -- 10 school days ≈ 2 weeks
);

create table exam_paper (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, exam_session_id uuid not null references exam_session on delete cascade,
  subject_id uuid not null, grade_level_id uuid not null,
  paper_number smallint not null default 1,
  date date not null, starts_at time not null, duration_minutes smallint not null,
  max_score numeric(6,2), assessment_id uuid references assessment
);

create table exam_eligibility_decision (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, exam_session_id uuid not null, student_id uuid not null,
  attendance_pct numeric(5,2), threshold numeric(5,2),
  decision text not null,                            -- allow|debar
  decided_by uuid not null, decided_at timestamptz not null default now(),
  reason text, guardian_notified_at timestamptz,
  unique (exam_session_id, student_id)
);

create table exam_seat (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, exam_paper_id uuid not null references exam_paper,
  student_id uuid not null, room_id uuid not null, seat_label text not null,
  attendance text,                                   -- present|absent
  irregularity text,
  unique (exam_paper_id, room_id, seat_label),
  unique (exam_paper_id, student_id)
);

create table invigilation_duty (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, exam_paper_id uuid not null references exam_paper,
  room_id uuid not null, staff_id uuid not null,
  role text not null default 'invigilator',          -- chief|invigilator|relief
  status text not null default 'assigned',
  swap_requested_with uuid
);

create table national_exam_entry (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null,
  student_id uuid not null, exam_body text not null, -- MES|Cambridge
  qualification text not null,                       -- NCE|SC|HSC
  subject_id uuid not null, syllabus_code text,
  entry_level text,                                  -- principal|subsidiary|core
  fee_amount numeric(10,2), fee_paid_on date,
  entry_status text not null default 'draft',
  submitted_on date,
  unique (student_id, academic_year_id, subject_id, qualification)
);

create table national_exam_result (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, student_id uuid not null,
  qualification text not null, sitting text not null, -- '2026 November'
  subject_id uuid, syllabus_code text,
  grade text, points numeric(4,2),
  is_credit boolean, is_pass boolean,
  imported_at timestamptz not null default now(), source_file text
);
```

### 13.10 Discipline, pastoral, governance

```sql
create table incident (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null,
  occurred_at timestamptz not null, location text,
  category text not null, severity smallint not null check (severity between 1 and 5),
  description text not null, witnesses text,
  photo_paths text[],
  reported_by uuid not null references staff,
  status text not null default 'open'
);
create table incident_student (
  incident_id uuid references incident on delete cascade,
  student_id uuid references student,
  involvement text not null,                         -- perpetrator|victim|witness
  primary key (incident_id, student_id)
);

create table disciplinary_case (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, student_id uuid not null,
  opened_on date not null, stage text not null,      -- form_teacher|parent_contact|special_report|pastoral|disciplinary_committee
  committee_id uuid, hearing_on date,
  guardian_summons_sent_on date, summons_delivery_proof_path text,
  decision text, decided_on date, appeal_status text,
  closed_on date
);
create table sanction (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, disciplinary_case_id uuid references disciplinary_case,
  student_id uuid not null, kind text not null,      -- warning|detention|special_report|suspension|exclusion|community_service
  starts_on date, ends_on date, details text,
  issued_by uuid not null, guardian_notified_at timestamptz
);
create table merit (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, student_id uuid not null,
  kind text not null,                                -- bonus_marks|responsibility|good_behaviour_certificate|award
  reason text not null, awarded_by uuid, awarded_on date not null
);

create table pastoral_case (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, student_id uuid not null,
  opened_on date not null, trigger text not null,    -- attendance|performance|behaviour|welfare|referral
  status text not null default 'open',
  external_referral_to text,
  guardian_consent_given boolean, guardian_consent_path text, guardian_consent_on date,
  review_on date, outcome text, closed_on date
);
create table pastoral_note (                          -- restricted visibility
  id uuid primary key default gen_random_uuid(),
  pastoral_case_id uuid not null references pastoral_case on delete cascade,
  author_id uuid not null, note text not null,
  visibility text not null default 'committee',       -- committee|smt|rector_only
  created_at timestamptz not null default now()
);

create table committee (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, academic_year_id uuid not null,
  code text not null,                                 -- disciplinary|pastoral|staff_welfare|sports|events|magazine|pedagogical|pta|student_council
  name text not null, terms_of_reference text,
  min_meetings_per_term smallint
);
create table committee_member (
  committee_id uuid references committee on delete cascade,
  person_id uuid references person, role_in_committee text,
  primary key (committee_id, person_id)
);
create table meeting (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, kind text not null,        -- staff|smt|departmental|committee|pta|parent
  committee_id uuid references committee, department_id uuid references department,
  held_on timestamptz not null, venue text, agenda text,
  chaired_by uuid, minutes text, minutes_path text,
  visibility text not null default 'internal'
);
create table meeting_attendance (
  meeting_id uuid references meeting on delete cascade,
  person_id uuid references person, present boolean not null default true,
  primary key (meeting_id, person_id)
);
create table action_item (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, meeting_id uuid references meeting,
  description text not null, owner_person_id uuid references person,
  due_on date, status text not null default 'open', completed_on date
);

-- Append-only evidential records
create table occurrence_log (
  id bigserial primary key, school_id uuid not null,
  occurred_at timestamptz not null, entered_at timestamptz not null default now(),
  entered_by uuid not null, category text, entry text not null,
  corrects_entry_id bigint references occurrence_log   -- corrections are new rows
);
create table confidential_note (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null, subject_person_id uuid,
  author_id uuid not null, note text not null,
  created_at timestamptz not null default now()
);
create table audit_log (
  id bigserial primary key, school_id uuid,
  actor_id uuid, action text not null, table_name text, record_id uuid,
  before jsonb, after jsonb, ip inet, user_agent text,
  at timestamptz not null default now()
);
```

### 13.11 Planning, communication, facilities (abbreviated)

```sql
syllabus(id, subject_id, grade_level_id, academic_year_id, version, status)
syllabus_unit(id, syllabus_id, parent_id, code, title, objectives[], term_id, order)
scheme_of_work(id, subject_set_id, staff_id, term_id, status, submitted_at,
               hod_reviewed_by, hod_comment, rector_approved_at)
scheme_week(id, scheme_of_work_id, week_no, objectives, activities,
            assessment_strategy, revision_notes)
weekly_plan(id, staff_id, subject_set_id, week_start, status)
weekly_plan_row(id, weekly_plan_id, timetable_slot_id, date, planned, actual, remarks)
lesson_plan(id, timetable_slot_id, date, staff_id, objectives, procedure,
            methods, activities, resources, evaluation, homework, attachments[])
homework(id, subject_set_id, set_by, set_on, due_on, title, description,
         attachments[], estimated_minutes)
homework_submission(id, homework_id, student_id, submitted_at, status, feedback)

notice(id, school_id, title, body, audience jsonb, publish_at, expires_at,
       created_by, pinned, requires_acknowledgement)
notice_read(notice_id, person_id, read_at)
message_thread(id, school_id, subject, about_student_id, created_by)
message(id, thread_id, sender_id, body, attachments[], sent_at)
thread_participant(thread_id, person_id, last_read_at)
notification(id, school_id, person_id, channel, template, payload jsonb,
             status, provider_ref, sent_at, delivered_at, error)
circular(id, school_id, reference, issued_on, source, subject, file_path, target_roles[])
circular_ack(circular_id, person_id, acknowledged_at)
policy_document(id, school_id, kind, version, file_path, effective_from)
policy_acknowledgement(policy_document_id, person_id, acknowledged_at, ip)
correspondence(id, school_id, direction, dated_on, counterparty, subject,
               abc_code, unique_file_number, assigned_to, status, file_path)

asset(id, school_id, tag, category, name, room_id, custodian_id, acquired_on,
      cost, condition, status, disposed_on)
asset_verification(id, asset_id, verified_by, verified_on, found, condition, note)
maintenance_request(id, school_id, room_id, asset_id, reported_by, reported_on,
                    description, priority, status, completed_on, photos[])
library_item(id, school_id, isbn, title, author, copies, category)
library_loan(id, library_item_id, student_id, staff_id, out_on, due_on, returned_on)
visitor_log(id, school_id, name, organisation, purpose, host_staff_id,
            signed_in_at, signed_out_at, badge_no)
health_record(id, school_id, student_id, kind, occurred_at, description,
              action_taken, guardian_notified_at)
water_quality_certificate(id, school_id, issued_on, expires_on, tanks_cleaned_on, file_path)
clearance_item(id, school_id, student_id, kind, cleared, cleared_by, cleared_on)
leaving_certificate(id, school_id, student_id, issued_on, attendance_summary jsonb,
                    conduct text, pdf_path, issued_by)
job(id, school_id, kind, payload jsonb, status, progress, result jsonb,
    requested_by, started_at, finished_at, error)
```

---

## 14. Security Model

### 14.1 Authentication

- Supabase Auth. **Email + password** for staff; **phone/OTP** for guardians (far higher completion rate in Mauritius than email); students get school-issued accounts.
- **Custom access-token hook** (Postgres function) injects into every JWT:
  ```json
  { "school_id": "...", "person_id": "...", "person_type": "staff",
    "roles": [{"c":"educator","s":"school"},
              {"c":"form_teacher","s":"class","id":"..."},
              {"c":"hod","s":"department","id":"..."}],
    "caps": ["attendance.mark","marks.enter", "..."] }
  ```
- MFA (TOTP) enforced for `super_admin`, offered to Rector/Deputy/Clerk.
- Short refresh windows and no persistent session on devices flagged as shared.

### 14.2 RLS pattern

Every table gets: `enable row level security` + a **tenant predicate** + a **role predicate**. Helper functions read JWT claims and are marked `stable` so the planner caches them per statement.

```sql
create schema app;

create function app.school_id() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'school_id','')::uuid $$;

create function app.person_id() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'person_id','')::uuid $$;

create function app.has_cap(cap text) returns boolean language sql stable as $$
  select (current_setting('request.jwt.claims', true)::jsonb -> 'caps') ? cap $$;

create function app.form_teacher_of(cg uuid) returns boolean language sql stable as $$
  select exists (
    select 1 from jsonb_array_elements(
      current_setting('request.jwt.claims', true)::jsonb -> 'roles') r
    where r->>'c' = 'form_teacher' and (r->>'id')::uuid = cg) $$;

create function app.teaches_set(s uuid) returns boolean language sql stable as $$
  select exists (select 1 from set_educator se
                 where se.subject_set_id = s and se.staff_id = app.person_id()) $$;

create function app.is_guardian_of(st uuid) returns boolean language sql stable as $$
  select exists (select 1 from student_guardian sg
                 where sg.student_id = st and sg.guardian_id = app.person_id()) $$;

create function app.year_is_open(y uuid) returns boolean language sql stable as $$
  select exists (select 1 from academic_year a where a.id = y and a.status = 'active') $$;
```

**Example — the attendance register.** This encodes the Manual's rule that *students must not have access to attendance registers* at the database level:

```sql
alter table attendance_record enable row level security;

create policy ar_tenant on attendance_record
  using (school_id = app.school_id());

create policy ar_read on attendance_record for select using (
  school_id = app.school_id() and (
       app.has_cap('attendance.read.all')                       -- rector, deputy, usher
    or exists (select 1 from attendance_session s
               where s.id = attendance_session_id
                 and app.form_teacher_of(s.class_group_id))
    or app.is_guardian_of(student_id)                            -- own ward only
    or student_id = app.person_id()                              -- own record only
  ));

create policy ar_write on attendance_record for insert with check (
  school_id = app.school_id()
  and app.has_cap('attendance.mark')
  and exists (select 1 from attendance_session s
              join academic_year y on y.id = s.academic_year_id
              where s.id = attendance_session_id
                and s.status = 'open'
                and y.status = 'active'
                and (app.form_teacher_of(s.class_group_id)
                     or app.has_cap('attendance.mark.any')))
);
-- No UPDATE policy: amendments go through rpc_amend_attendance(), which is
-- SECURITY DEFINER, requires a reason, and writes audit_log.
```

Note that `student_id = app.person_id()` gives a student their own row but **never the class register** — the read is row-shaped, so a student querying the table receives exactly one row per session.

**Example — marks are invisible until published:**

```sql
create policy mark_read on mark for select using (
  school_id = app.school_id() and (
       app.has_cap('marks.read.all')
    or exists (select 1 from assessment a where a.id = assessment_id and app.teaches_set(a.subject_set_id))
    or (
        exists (select 1 from assessment a where a.id = assessment_id and a.status = 'published')
        and (student_id = app.person_id() or app.is_guardian_of(student_id))
       )
  ));
```

**Example — append-only occurrence log:**

```sql
alter table occurrence_log enable row level security;
create policy ol_read   on occurrence_log for select using (school_id = app.school_id() and app.has_cap('occurrence.read'));
create policy ol_insert on occurrence_log for insert with check (school_id = app.school_id() and app.has_cap('occurrence.append') and entered_by = app.person_id());
-- deliberately no update / delete policy: corrections insert a new row referencing corrects_entry_id
revoke update, delete on occurrence_log from authenticated;
```

**Example — closed-year immutability:** every operational table's write policies include `app.year_is_open(academic_year_id)`. Closing a year is a one-line status change that makes the entire year read-only, everywhere, atomically.

### 14.3 Sensitive data tiers

| Tier | Data | Access |
|---|---|---|
| **T3 Restricted** | Confidential notes, pastoral notes (`rector_only`), medical/SEN detail, birth certificates | Rector + explicitly named roles; every **read** written to `audit_log` |
| **T2 Sensitive** | Marks pre-publication, discipline cases, guardian contact, addresses | Role-scoped; writes audited |
| **T1 Internal** | Timetable, notices, class lists, attendance | Broad staff read |
| **T0 Public-in-school** | Notices marked public, school calendar | All authenticated |

### 14.4 Storage buckets

| Bucket | Contents | Policy |
|---|---|---|
| `student-photos` | Face photos | Staff read; guardians read own ward |
| `student-docs` | Birth certificates, medicals, absence notes | T3/T2; per-student RLS via path prefix `{school_id}/{student_id}/…` |
| `staff-docs` | Staff files | Self + Rector/Clerk |
| `reports` | Generated report-card and certificate PDFs | Signed URLs only, short TTL |
| `resources` | Teaching resources, homework attachments | Set members + staff |
| `imports` | CSV uploads | Uploader + admin, auto-purged after 30 days |

### 14.5 Data protection posture (Mauritius DPA 2017)

- Register the processing; name a controller (the school) and processor (you, if SaaS)
- Lawful basis: public task / legal obligation for the school record; **consent** specifically for photography, external-agency referral, and any marketing
- Consent flags are per-purpose, revocable, and timestamped on `person`/`student_guardian`
- Data-subject access request → an export RPC producing a single archive per student
- Retention schedule per record class; hard-delete job with a legal-hold flag
- Breach procedure with a 72-hour notification path to the Data Protection Office

---

## 15. Core Algorithms

### 15.1 Timetable generation

**Problem shape.** Assign every `subject_set` its `periods_per_cycle` to (cycle_day, period, room, educator) tuples. This is NP-hard; the practical approach is heuristic construction followed by local search, run in a Web Worker so the UI stays alive.

**Hard constraints (violation = invalid)**
1. An educator is in at most one place per (cycle_day, period)
2. A room is used by at most one set per (cycle_day, period)
3. **No student clash** — derived from `set_enrolment`; two sets sharing any student cannot share a slot
4. Practical/lab subjects only in rooms of the required type
5. Room capacity ≥ set size
6. Educator unavailability (part-time days, released periods)
7. Double periods occupy consecutive teaching periods on the same day, not spanning a break
8. Each set receives exactly its required period count

**Soft constraints (scored)**
- Spread: the same subject shouldn't appear twice in one day for a class unless it's a double
- Educator load balance across days; no more than *n* consecutive teaching periods
- Minimise educator room-hopping (especially between blocks)
- Avoid PE/practicals immediately before lunch; avoid Maths last period on Friday (schools have strong opinions — make these editable rules, not code)
- Form Teacher present for their class's first period of the day (helps register-taking)
- Minimise gaps ("free periods") in educator days
- Keep specialist rooms utilised evenly

**Algorithm**
```
1. Preprocess
   - Build the set-conflict graph: edge between sets sharing ≥1 student or ≥1 educator
   - Compute set "difficulty" = degree × periods_required × room-type scarcity
2. Construct  (greedy, difficulty-descending, with DSATUR-style tie-break)
   - For each set, for each required period block:
       choose the feasible slot with the best soft score
       if none feasible → backtrack limited depth, else park in "unplaced"
3. Improve  (simulated annealing, ~10–60 s budget)
   - Neighbourhood moves: relocate a block; swap two blocks; swap rooms;
     swap educators between parallel sets; Kempe-chain swap on the conflict graph
   - Accept worse solutions with probability e^(-Δ/T), geometric cooling
   - Never accept a hard-constraint violation
4. Repair
   - Any remaining unplaced blocks are surfaced explicitly with the reason
     ("no free lab on any day for G11 Chem Set 3") — never silently dropped
5. Emit 3–5 candidate timetables with scores and a diff view
```

**Manual editor.** Drag-and-drop grid with live validation: dragging a block highlights all legal targets, shows the soft-score delta, and blocks illegal drops with the specific reason. A "swap" mode and an "unplaced tray" complete it. **The Deputy Rector's judgement always wins** — the solver's job is to produce a 95% solution in two minutes, not to be right.

**Publication.** Publishing creates a new `timetable_version` with an effective date. Past dates keep resolving against the version in force then, so historical period attendance and lesson records stay coherent.

**Cycle-day handling.** With a 10-day cycle, a Monday holiday must not silently shift everything. The rule is configurable per school: *skip* (the cycle day is lost) or *carry* (the cycle resumes where it left off). This is stored on `calendar_day.cycle_day` at generation time so it's explicit and inspectable rather than computed on the fly.

### 15.2 Daily substitution

```
Input: staff absences for date D (from staff_leave + same-morning absence)
1. Expand the timetable for D's cycle_day → list of slots for absent staff
2. For each uncovered slot, build the candidate pool:
     staff free that period ∧ not on leave ∧ under daily cover cap
3. Score candidates:
     +40  same subject specialism
     +25  already teaches this class/set
     +20  fewer cover periods this term (fairness)
     +10  same block/proximity to the room
     -30  would create 4+ consecutive teaching periods
     -50  part-time day / released period
4. Assign greedily; leave genuinely uncoverable slots marked 'uncovered'
   and route them to the Deputy Rector with options
     (merge classes / supervised study / release a non-teaching duty)
5. Publish → push notification to substitutes, staff-room screen, class notice
```

Class Captains flagging "no educator arrived" creates an ad-hoc uncovered slot in the same board — closing the loop the Manual describes, where a class must never be left unattended.

### 15.3 Exam seating

```
Input: exam_paper, candidate list, available rooms with exam_capacity
1. Sort rooms by exam_capacity desc; allocate candidates to rooms
2. Within a room, lay out a grid from room geometry (rows × cols)
3. Apply the chosen strategy:
   - 'alternate_subject': no two adjacent candidates sit the same paper
   - 'separate_class':    no two adjacent candidates from the same class_group
   - 'spaced':            leave every other seat empty (capacity permitting)
4. Constraint check via a simple backtracking pass over the grid;
   fall back to 'spaced' if the stricter strategy is infeasible
5. Emit: seating plan PDF per room, desk labels, attendance sheet per room,
   and a per-student "your seat" view
```

Special arrangements (extra time, separate room, reader/scribe) are attributes on the candidate and force a dedicated room allocation before the general pass.

### 15.4 Promotion rules engine

Rules are **data**, stored per academic year, evaluated by a pure function in `packages/domain` mirrored as a Postgres function.

```ts
type Rule = {
  id: string;
  appliesTo: { grade: number; stream?: Stream };
  outcome: 'promote' | 'repeat' | 'conditional_promote' | 'leave' | 'refer';
  priority: number;                        // first match wins
  conditions: Condition[];                 // ALL must hold
};

type Condition =
  | { kind: 'aggregate_gte'; value: number }
  | { kind: 'subject_pass_count_gte'; value: number; level?: 'principal'|'subsidiary' }
  | { kind: 'credit_count_gte'; value: number; sameSitting: boolean }
  | { kind: 'attendance_pct_gte'; value: number; countAuthorisedAsPresent: boolean }
  | { kind: 'times_repeated_lte'; value: number }
  | { kind: 'age_on_date_lte'; value: number; asOf: 'jan_1' | 'exam_date' }
  | { kind: 'has_medical_certificate_for_prolonged_absence' }
  | { kind: 'core_subject_passed'; subject: 'english'|'french'|'maths' };
```

Shipped rule set (editable, year-versioned):

| Grade | Rule | Conditions | Outcome |
|---|---|---|---|
| 7–8 | Standard promotion | aggregate ≥ school threshold | promote |
| 7–8 | Second-attempt relief | times_repeated ≤ 1 ∧ aggregate ≥ 35 ∧ attendance ≥ 75 | conditional_promote |
| 9 | NCE outcome | NCE result bands | promote / orient to technical or vocational |
| 11 → 12 | Lower VI entry | SC with ≥ 4 credits at one and the same sitting **or** GCE O-Level in 5 subjects with minimum performance | promote |
| 11 → 12 | Age relief | would be disqualified by age from Lower VI, or cannot repeat Form V under the one-repeat rule | conditional_promote |
| 12 → 13 | Upper VI entry | Lower VI end-of-year exam sat (mandatory) ∧ ≥ 2 passes at Principal ∧ ≥ 2 at Subsidiary | promote |
| 12 → 13 | Fallback | fails above ∧ (over age ∨ already repeated twice) | enter for GCE A-Level in ≥ 2 subjects in lieu of HSC + **written notice to Responsible Party** |
| any | Twice-failed | times_repeated ≥ 2 ∧ no relief condition met | leave |
| any | Age ceiling | age > 18 ∧ not qualified for Form VI admission | leave (with the post-exam grace clause) |

The engine outputs a **recommendation with the rule ID and the evidence** for each student. The Rector reviews the whole cohort in one screen, overrides individually with a mandatory reason, and the decision is recorded. **The engine never decides autonomously** — that is both legally and politically necessary.

### 15.5 Attendance percentage — the subtle one

Getting this wrong invalidates exam eligibility and scholarship decisions, so define it precisely:

```
sessions_possible = 2 × (teaching days in term from calendar_day)
                    − sessions during approved leave_of_absence
                    − sessions before admission / after leaving

present            = present + late + school_activity
absent_authorised  = absence covered by an accepted absence_note or medical certificate
absent_unauthorised= everything else

pct_present  = present / sessions_possible                 -- the 80% / 75% rules use this
pct_attended_incl_authorised = (present + absent_authorised) / sessions_possible
```

The **scholarship rule counts absences "exclusive of authorised absences"** — a different denominator again. So store the raw counts and compute the three views, rather than storing one percentage and hoping.

### 15.6 Grading & aggregation

```
For each (student, subject, term):
  aggregate = Σ(score_i / max_i × weight_i) / Σ(weight_i) × 100
  where assessments with code ∈ {EXEMPT, MED} are excluded from both sums
        and code = ABS scores 0 (configurable per school)
  band = the grading_band of the assessment's scale whose [min,max] contains aggregate
  rank_in_set / rank_in_grade computed with dense ranking; ties share a rank
```

Overall aggregate uses subject weights (a school may weight core subjects higher). Ranks can be suppressed entirely per grade — some schools deliberately don't rank Grades 7–8.

### 15.7 Discrepancy detection

A trigger on `period_attendance` insert:
```sql
-- if the student was 'present' on the AM/PM register for this date
-- but is marked absent in this period → insert attendance_discrepancy
-- Realtime pushes it to the Usher's board within ~1 second.
```
Inverse case handled symmetrically. Both are cleared by the Usher with a recorded outcome — which itself becomes attendance evidence.

---
---

# PART D — DELIVERY

## 16. Edge Functions & API Surface

Everything CRUD goes directly through PostgREST with RLS. Edge Functions exist only where Postgres shouldn't reach:

| Function | Purpose |
|---|---|
| `sms-send` | Adapter over the Mauritian SMS gateway; templating, language selection, delivery-receipt webhook |
| `email-send` | Transactional email |
| `notification-dispatch` | Reads `notification` queue, fans out by channel and guardian preference, retries with backoff |
| `absence-alert` | Triggered after AM register close: builds the unauthorised-absence list, dispatches to Responsible Parties |
| `attendance-return` | Scheduled: periodic attendance return to every Responsible Party |
| `exam-entry-export` | Produces the MES/Cambridge entry file in the required format |
| `results-import` | Parses MES/Cambridge result files, matches candidates, stages for review, then commits |
| `report-batch` | Enqueues a `job` row and signals the PDF worker |
| `ministry-return` | Generates standardised statistical returns (roll by grade/sex, attendance, results) |
| `emergency-broadcast` | Cyclone/closure: marks calendar days, voids attendance, blasts all channels |
| `sms-inbound` | Webhook: guardian replies to an absence SMS become an absence note |
| `data-export` | DPA subject-access export for one person |

**SECURITY DEFINER RPCs in Postgres** (multi-step operations that must be atomic and audited):
`rpc_open_register`, `rpc_close_register`, `rpc_amend_attendance`, `rpc_publish_marks`,
`rpc_compute_term_results`, `rpc_generate_school_calendar`, `rpc_publish_timetable`,
`rpc_allocate_exam_seats`, `rpc_assign_invigilation`, `rpc_evaluate_promotion`,
`rpc_rollover_year`, `rpc_issue_leaving_certificate`, `rpc_declare_closure`.

## 17. Storage, Documents & PDF

**Statutory print templates to build** (each an A4 print route + PDF):
Report Book (term + cumulative) · Leaving Certificate (with attendance summary) · Certificate of Good Behaviour · Attendance Certificate · Class list · Register printout (for inspection/archive) · Timetable (class / educator / room / master) · Exam timetable · Seating plan · Desk labels · Invigilation duty slip · Exam attendance sheet · Convocation letter to parents · Disciplinary summons (registered post) · Leave-of-absence decision · Notice-board display pack · Ministry statistical return · Asset verification sheet · Inventory sheet per room.

All templates are data-driven with the school's letterhead, bilingual (EN/FR) with per-document language choice, and produce a stable filename convention `{type}/{year}/{grade}/{admission_no}.pdf` in the `reports` bucket.

## 18. Offline, Notifications, i18n

**Offline (PWA)**
- Precache the app shell; runtime-cache reference data (students, sets, timetable) with a stale-while-revalidate policy
- **Outbox pattern**: attendance and mark mutations write to IndexedDB with a client-generated UUID, render optimistically, and drain on reconnect
- Idempotency: server upserts on the natural key (`attendance_session_id + student_id`), so a replayed mutation is harmless
- Conflict rule: **last-write-wins with an audit entry**, plus a visible warning if the server value changed since the local write — attendance conflicts are rare and human-resolvable, so don't over-engineer CRDTs
- Visible sync status in the header: "3 registers pending sync"

**Notifications**
- Channels: in-app, push (web push), SMS, email. Per-guardian preference, per-event-type opt-out where legally permitted.
- Quiet hours; digest mode for low-priority events; hard override for emergency broadcast.
- Templates versioned and translatable; SMS templates written for 160 characters and for Kreol readability.

**i18n**
- `react-i18next`, namespaces per feature, EN and FR complete at launch; MFE (Kreol Morisien) for parent-facing SMS/notice templates only
- All user-visible strings from the database (subject names, notice bodies) carry `_en` / `_fr` variants where they are school-authored
- `Intl` for dates/numbers; `dd/mm/yyyy`; `Indian/Mauritius`

## 19. Reporting & Analytics

**Dashboards**

| Role | Key widgets |
|---|---|
| **Rector** | Roll and attendance today vs. term average · unauthorised absence count · open discipline cases by stage · syllabus coverage by department · marks-entry completion by department · exam eligibility at-risk count · staff absence and uncovered periods · action items overdue |
| **Deputy Rector** | Uncovered periods now · registers not yet taken · timetable conflicts · room utilisation |
| **HOD** | Scheme-of-work submissions outstanding · syllabus coverage per set · results distribution vs. grade · educators' marks-entry status |
| **Form Teacher** | My class: attendance trend, lateness league, incidents, at-risk students, report-card completion |
| **Usher** | Live discrepancy board · lateness today · students off-premises · open incidents |

**Standard reports**
Attendance return per class/grade/term · Unauthorised-absence register · Lateness report · Exam eligibility list · Results analysis per subject/set/grade with distributions · Value-added NCE→SC and mock→SC · Subject-choice statistics · Discipline statistics by category and grade · Staff absence and cover statistics · Asset verification · Library overdue · Ministry statistical return.

**Implementation:** materialised views refreshed by `pg_cron` (nightly + on-demand after marks publication), never live aggregation over `mark`/`attendance_record`.

## 20. Data Migration & Onboarding

**Sequence for one school (≈6 weeks)**

| Week | Activity |
|---|---|
| 1 | Discovery: collect the school's actual forms — their report book, their register, their timetable, their letters. Configure school profile, calendar 2026, periods, rooms. |
| 2 | Reference data: departments, subjects with strands, grade levels, option blocks, grading scales, holidays. Staff import + accounts. |
| 3 | Student import (from the school's existing spreadsheets or Ministry files), guardians, class allocation, subject-set construction and enrolment. Photo batch. |
| 4 | Timetable: import the current one manually or generate. Parallel run — paper register **and** app for one grade. |
| 5 | Extend to all grades. Marks entry for the current term. Report-card template matched to their existing design (this is the trust-building moment). |
| 6 | Guardian onboarding (SMS invite with OTP), notice board live, paper registers retired for attendance. |

**Historical import** (3 prior years minimum): enrolment, results, NCE/SC/HSC outcomes — so analytics has something to say on day one.

**Import tooling**: CSV templates per entity, a validation preview with per-row errors, a dry-run diff, and idempotent re-import keyed on admission number / staff number.

## 21. Testing Strategy

| Layer | Tool | What |
|---|---|---|
| Domain logic | Vitest | Grading aggregation, promotion rules (a table-driven test per rule row in §15.4), attendance percentages incl. the three denominators, calendar generation across holidays and cycle drift |
| **RLS** | **pgTAP** | For every table × every role: can a student read the class register? (must be no) can a guardian read unpublished marks? (no) can an educator write to another set? (no) can anyone update `occurrence_log`? (no) can anyone write to a closed year? (no). **This is the highest-value test suite in the project.** |
| Database | pgTAP | Constraints: no room clash, no staff clash, one responsible party, exam ≤ 10 days, room-booking overlap exclusion |
| Components | Testing Library | Register interactions, marks grid keyboard navigation |
| Integration | Vitest + local Supabase | RPCs, triggers, discrepancy detection |
| E2E | Playwright | The five critical journeys: take a register offline and sync · enter and publish marks · generate and publish a timetable · run an exam session end to end · guardian receives an absence alert and submits a note |
| Performance | k6 + pgbench | 200 concurrent register submissions at 07:45; report batch of 1,200 |
| Accessibility | axe + manual | WCAG 2.1 AA on the top 10 screens |
| Load-shape realism | Seed script | A synthetic 1,200-student school with 3 years of history — run every performance test against it |

**Non-negotiable CI gate:** the pgTAP RLS suite must pass before any migration merges.

## 22. Phased Roadmap

**Phase 0 — Foundations (3 weeks)**
Repo, CI, Supabase project + branching, auth with the JWT hook, role/capability model, school setup, academic year + calendar generation with 2026 seeded, rooms, departments, subjects, grade levels, classes. Design system and app shell. RLS harness and the first pgTAP tests.

**Phase 1 — People & Attendance (5 weeks) — *the wedge***
Students, staff, guardians, documents. Class and subject-set enrolment with option-block validation. Daily register (offline-capable). Period attendance. Discrepancy board. Lateness, movement. Absence notes. Attendance summaries. Guardian SMS alerts and attendance returns. Guardian portal v1 (attendance only).
*Ship this alone and the school already has a reason to keep using it.*

**Phase 2 — Assessment & Report Books (5 weeks)**
Grading scales, assessments, marks entry (offline), moderation and publication workflow, term results, ranks, comments, report-book PDFs, batch generation, results analysis. Student and guardian portal marks views.

**Phase 3 — Timetable & Substitution (5 weeks)**
Cycle definition, period definitions, timetable solver in a worker, manual editor with live validation, publication and versioning, per-role timetable views, room bookings, lab/practical scheduling, staff leave, daily substitution board.

**Phase 4 — Examinations (4 weeks)**
Exam sessions with the 10-day rule, exam timetable, eligibility screening against the 80% rule with Rector decisions, seating allocation, invigilation rosters, script tracking, national exam entries and fees, results import.

**Phase 5 — Discipline, Pastoral & Governance (4 weeks)**
Incidents, escalation ladder, merits, disciplinary and pastoral committees with consent capture, occurrence log, Student Information Sheet, committees, meetings, action items, correspondence register, circulars, policy acknowledgements.

**Phase 6 — Curriculum & Planning (3 weeks)**
Syllabus, schemes of work with the HOD→Rector workflow, weekly plans with coverage tracking, lesson plans, homework, resources.

**Phase 7 — Facilities, Library, Health, Finance (3 weeks)**
Assets, maintenance, inventory, library with clearance hooks, lab equipment ledger, visitors, health records, water-quality certificates, leaving certificates. Fees/PTA ledger for grant-aided and private schools.

**Phase 8 — Analytics, Ministry Returns, Hardening (3 weeks)**
Materialised analytics, dashboards per role, standard reports, Ministry statistical returns, value-added analysis, performance tuning, penetration test, DPA documentation.

**Phase 9 — Multi-tenant enablement (3 weeks)**
Tenant provisioning, per-school branding, cross-school admin console, zone-level read-only dashboards, billing if commercialised.

*Total ≈ 38 weeks for the full scope; a genuinely useful product exists at the end of Phase 2 (~13 weeks).*

## 23. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Staff won't adopt it** — the classic reason school systems fail | Fatal | Ship the register first and make it *faster than paper*. Match their existing report-book layout exactly. Train the Usher and Form Teachers, not "everyone". Never make a teacher enter data twice. |
| **Connectivity in classrooms** | High | Offline-first from Phase 1, not retrofitted. Test on a throttled 3G profile in CI. |
| **Timetable solver produces something the Deputy Rector dislikes** | High | The editor is the product; the solver is an accelerant. Always allow full manual control and never auto-publish. |
| **Guardian adoption of the portal is low** | Medium | SMS is the primary channel, portal is the bonus. Design for a guardian who never installs anything. |
| **RLS bug leaks marks or medical data** | Severe | pgTAP suite as a CI gate; no client-side-only authorisation anywhere; audited reads on T3 data; external pen-test before Phase 8 sign-off. |
| **Ministry/MES file formats change** | Medium | Isolate every external format behind an adapter with fixture-based tests; never let a format leak into the schema. |
| **Rules change (thresholds, promotion criteria)** | Medium | Everything policy-shaped is data, year-versioned. No hard-coded thresholds anywhere — grep for magic numbers in review. |
| **Cyclone closure mid-term corrupts attendance stats** | Medium | First-class closure action that voids attendance and recomputes summaries. |
| **Scope creep into an LMS** | Medium | Non-goals in §7 are binding. Homework and resources only. |
| **Single-school assumptions leak into the schema** | Medium | `school_id` on every table from commit one; a CI check that fails any migration adding a table without it. |
| **Data protection non-compliance** | High | DPA register, consent per purpose, retention policy, subject-access export built in Phase 1 rather than bolted on. |
| **Key-person dependency (you)** | Medium | Migrations in the repo, domain logic pure and tested, ADRs for every significant decision. |

## 24. Open Questions

Answer these before Phase 1 code:

1. **Which school** is the pilot — state, grant-aided, or private? This decides whether fees and a Manager role are in scope early.
2. **Session model** — single or double session? Double session changes the register model (two cohorts, one building) substantially.
3. **Cycle length** — 5-day or 10-day timetable cycle, and which drift rule on holidays?
4. **Report book layout** — obtain a scan of the school's actual report book, day one. This is the single artefact most worth copying exactly.
5. **Exact internal grading scale and cut-offs** for the pilot school, and whether ranks are published in Grades 7–8.
6. **Do they use the Extended Programme?** If yes, get the adapted curriculum and its assessment rules.
7. **SMS gateway** — which provider, what per-message cost, what sender ID can be registered?
8. **Existing data** — what format is the current student list in, and how many prior years exist?
9. **Devices** — what do Educators actually carry? If most have no smartphone, period attendance needs a shared-tablet-per-corridor model instead.
10. **Who owns the data** in the SaaS arrangement, and where must it be hosted? (Supabase region choice; data-residency expectations for a State school.)
11. **MES entry file format** — obtain the current specification and a sample.
12. **Ministry statistical returns** — obtain the actual templates the school submits today.

---

## Sources

- [Secondary Education — Nine Year Schooling, Careers Guidance, Govt. of Mauritius](https://careersguidance.govmu.org/careersguidance/wp-content/uploads/2023/11/secondary-education.pdf)
- [School Calendar 2026 — Public Notice, Ministry of Education and Human Resource](https://publicnotice.govmu.org/publicnotice/?p=30783) · [PDF](https://publicnotice.govmu.org/publicnotice/wp-content/uploads/2025/12/School-Calendar-2026.pdf)
- [School Management Manual for Rectors of State Secondary Schools — Ministry of Education](https://education.govmu.org/Documents/educationsector/seceducation/Documents/School%20Management%20Manual.pdf)
- [Secondary Education — Republic of Mauritius portal](https://govmu.org/EN/infoservices/education/Pages/secondary.aspx)
- [Mauritius Examinations Syndicate](https://mes.govmu.org/mes/)
- [National Certificate of Education](https://en.wikipedia.org/wiki/National_Certificate_of_Education) · [School Certificate (Mauritius)](https://en.wikipedia.org/wiki/School_Certificate_(Mauritius)) · [Higher School Certificate (Mauritius)](https://en.wikipedia.org/wiki/Higher_School_Certificate_(Mauritius))
- [Education in Mauritius](https://en.wikipedia.org/wiki/Education_in_Mauritius)
- [NCF Grades 7–9 — Mauritius Institute of Education](https://fliphtml5.com/eisr/sgym/NCF_Grades_7-9/)


---
