# MES examination entries — what I found, and what we built instead

Researched 2 Aug 2026. Short version: **there is no published MES file format**,
so we did not build one.

---

## The finding

Entries for school candidates (SC / HSC / GCE O and A Level) are made through
an **Oracle APEX web application** hosted on Oracle Cloud and linked from the
MES site under E-Services → *"Entries for School Candidates"*:

```
https://g9357e5fc8383c2-mesld01.adb.uk-london-1.oraclecloudapps.com/ords/f?p=100
```

Around that portal MES publishes web notices, instructions for submission,
Cambridge guides, fee charts, subject lists for O and A Level, and notes of
guidance. Entries are collected in **November/December of the year before the
examination**, with a press communiqué in early November giving the exact dates
and fees.

What is **not** published anywhere:

- a file schema for bulk upload
- field names, ordering, or encoding
- subject code lists in machine-readable form
- a results file layout coming back the other way

That is not an oversight in our research — the workflow is a clerk keying a
portal, with any bulk facility living inside the authenticated system.

## Why we did not invent one

An adapter named `mes.ts` producing a "MES format" would be believed. Somebody
would eventually hand its output to MES, and the failure would surface in
November of an examination year, which is the worst possible week.

The honest position: we have an internal export, clearly labelled as ours, and
a boundary where a real adapter drops in once somebody obtains the
specification.

## What exists

`public.exam_entry_export(p_session uuid)` — one row per candidate per subject,
which is the grain the portal collects and the grain at which a clerk checks
against a paper entry form.

| Column | Notes |
|---|---|
| `centre_number` | School's MES centre number, from `school` |
| `candidate_number` | From `student.candidate_number` — often assigned by MES, so frequently blank until they issue it |
| `admission_number` | Ours, for reconciliation. **Not an MES field** |
| `surname` | Upper-cased, matching the convention on entry forms |
| `other_names` | |
| `date_of_birth`, `sex` | |
| `class_name` | Ours, so a Form Teacher can check their own class |
| `subject_code`, `subject_name` | **Our subject codes, not Cambridge syllabus codes.** Mapping these is the single largest piece of work in a real integration |
| `level` | principal / subsidiary, for HSC |
| `extra_time_minutes`, `arrangements` | From `exam_arrangement` — access arrangements need separate approval from MES and are not part of a normal entry |

## What a real integration needs

1. **The specification**, from MES directly — `mes.govmu.org`, Records Unit.
2. **A subject code map.** Our `subject.code` is internal. Cambridge syllabus
   codes (`0500`, `9700`, …) are the real identifiers and change between
   syllabus versions. This belongs in a table, versioned by examination year,
   not in code.
3. **Candidate number assignment** — whether MES issues them or the school
   allocates within a range.
4. **The results direction**, which we have not modelled at all. Results come
   back as grades per candidate per syllabus and would populate `mark` /
   `term_result` for the national examination.
5. **Fixture-based tests** against a real sample file, so the format never
   reaches the schema. Keep it behind the adapter boundary: if an MES field
   name ever appears in a migration, the design has already failed.

## Before relying on any of this

The export is a **worksheet**, not a submission. It exists so a clerk keying
the portal has the right rows in front of them and can tick them off, and so
somebody can check the school's own record against what was entered.

Verify one class against a paper entry form before trusting it for a cohort.

---

## Sources

- [MES E-Services](https://mes.govmu.org/mes/?page_id=4055) — the entry portal link
- [MES Records Unit](https://mes.govmu.org/mes/?page_id=4059)
- [MES Cambridge HSC](https://mes.govmu.org/mes/?page_id=7136)
- [MES home](https://mes.govmu.org/mes/)
