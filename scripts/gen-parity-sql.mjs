#!/usr/bin/env node
/**
 * Compiles packages/domain/fixtures/attendance-cases.json into a SQL suite that
 * checks app.attendance_stats() against the same expectations the TypeScript
 * tests use. Regenerate with `npm run gen:parity`; CI regenerates and fails if
 * the checked-in file is stale, so the two implementations cannot drift.
 */
import { readFile, writeFile } from 'node:fs/promises'

const OUT = 'supabase/tests/_generated_parity.sql'
const fixture = JSON.parse(
  await readFile('packages/domain/fixtures/attendance-cases.json', 'utf8'),
)

const sqlLit = (v) => (v === null ? 'null' : typeof v === 'boolean' ? String(v) : String(v))
const arr = (statuses) =>
  statuses.length === 0
    ? "'{}'::attendance_status[]"
    : `array[${statuses.map((s) => `'${s}'`).join(',')}]::attendance_status[]`

const checks = fixture.cases
  .map((c) => {
    const name = c.name.replace(/'/g, "''")
    return `
  -- ${c.name}
  select * into st from app.attendance_stats(${arr(c.statuses)}, ${fixture.defaultThreshold});
  insert into pf select '${name} :: pct_present',
    ${sqlLit(c.expect.pctPresent)}::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from ${sqlLit(c.expect.pctPresent)}::numeric;
  insert into pf select '${name} :: pct_excl_auth',
    ${sqlLit(c.expect.pctExclAuth)}::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from ${sqlLit(c.expect.pctExclAuth)}::numeric;
  insert into pf select '${name} :: eligible',
    ${sqlLit(c.expect.eligible)},
    st.eligible::text,
    st.eligible is not distinct from ${sqlLit(c.expect.eligible)};
  insert into pf select '${name} :: shortfall',
    ${sqlLit(c.expect.shortfall)},
    st.shortfall_sessions::text,
    st.shortfall_sessions = ${sqlLit(c.expect.shortfall)};`
  })
  .join('\n')

const sql = `-- EduMU :: GENERATED FILE — DO NOT EDIT.
-- Source: packages/domain/fixtures/attendance-cases.json
-- Regenerate: npm run gen:parity
--
-- Asserts that the SQL implementation of the attendance arithmetic
-- (app.attendance_stats) agrees with the TypeScript specification in
-- packages/domain/src/attendance.ts on every fixture case. The two exist
-- because the server must be the authority for eligibility while the client
-- needs the same maths for display; this suite is what keeps them honest.

create temp table if not exists pf(test text, expected text, got text, pass boolean);
truncate pf;

do $$
declare st record;
begin
${checks}
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from pf;
`

await writeFile(OUT, sql)
console.log(`${OUT}: ${fixture.cases.length} cases → ${fixture.cases.length * 4} assertions`)
