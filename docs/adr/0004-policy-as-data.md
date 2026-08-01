# 4. School policy is data, not code

**Status** Accepted · 2026-08-01

## Context
The School Management Manual sets numbers that look constant but are not: 80%
attendance before mock and end-of-year examinations, 75% at a second attempt,
internal examinations no longer than ten days, promotion criteria, age limits.
Schools vary and the Ministry revises.

## Decision
Every threshold lives in `school.settings` or in year-versioned tables
(`grading_scale`, `grading_band`, promotion rules). No policy number appears as
a literal in application code or in a function body.

## Consequences
- Changing a threshold is a data edit, not a deploy. Verified: setting
  `exam_eligibility_pct` to 95 immediately reflags pupils.
- Historical decisions must snapshot the values they were based on. An exam
  eligibility decision stores both the percentage and the threshold in force,
  so a later amendment cannot rewrite what the Rector was looking at.
- Grades are stored as awarded, referencing the scale version.
- Code review should grep for magic numbers.
