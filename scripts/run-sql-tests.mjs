#!/usr/bin/env node
/**
 * Runs every suite in supabase/tests against a Postgres URL and fails the
 * process if any assertion row comes back FAIL.
 *
 * The suites print a result set of (test, expected, got, result). Anything
 * other than PASS in the result column is a failure — including a suite that
 * returns no rows at all, which usually means an exception swallowed the DO
 * block or the demo seed is missing.
 *
 * Usage: DATABASE_URL=postgres://... node scripts/run-sql-tests.mjs
 */
import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'

const run = promisify(execFile)
const DIR = 'supabase/tests'
const url = process.env.DATABASE_URL

if (!url) {
  console.error('DATABASE_URL is required')
  process.exit(2)
}

const files = (await readdir(DIR))
  .filter((f) => f.endsWith('.sql'))
  .sort()

let failed = 0
let total = 0

for (const file of files) {
  const sql = await readFile(join(DIR, file), 'utf8')
  process.stdout.write(`\n${file}\n`)

  let stdout
  try {
    ({ stdout } = await run('psql', [url, '-v', 'ON_ERROR_STOP=1', '-A', '-F', '\t', '-q'], {
      input: sql,
      maxBuffer: 10 * 1024 * 1024,
    }))
  } catch (err) {
    console.error(`  ERROR running suite: ${err.stderr || err.message}`)
    failed++
    continue
  }

  const rows = stdout
    .split('\n')
    .map((l) => l.split('\t'))
    .filter((c) => c.length >= 4 && (c[3] === 'PASS' || c[3] === 'FAIL'))

  if (rows.length === 0) {
    console.error('  ERROR: suite produced no assertions')
    failed++
    continue
  }

  for (const [test, expected, got, result] of rows) {
    total++
    if (result === 'PASS') {
      console.log(`  ok   ${test}`)
    } else {
      failed++
      console.error(`  FAIL ${test} — expected ${expected}, got ${got}`)
    }
  }
}

console.log(`\n${total - failed}/${total} assertions passed`)
process.exit(failed > 0 ? 1 : 0)
