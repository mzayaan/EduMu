#!/usr/bin/env node
/**
 * Local verification — what CI used to do, without the Docker stack.
 *
 *   npm run verify              typecheck + unit tests + parity freshness
 *   npm run verify -- --sql     also run the SQL suites (needs DATABASE_URL)
 *
 * Run it before you commit. Nothing enforces that, which is the trade for not
 * paying for CI: a regression can reach main if nobody runs this.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const wantSql = process.argv.includes('--sql')
const results = []

function step(name, fn) {
  process.stdout.write(`\n▸ ${name}\n`)
  try {
    fn()
    results.push([name, true])
  } catch (err) {
    results.push([name, false])
    if (err.stdout) process.stdout.write(String(err.stdout))
    if (err.stderr) process.stderr.write(String(err.stderr))
  }
}

const run = (cmd, args) =>
  execFileSync(cmd, args, { stdio: 'inherit', shell: process.platform === 'win32' })

step('Typecheck', () => run('npx', ['tsc', '-b', 'apps/web']))
step('Unit tests', () => run('npx', ['vitest', 'run']))

step('Parity suite is current', () => {
  const before = readFileSync('supabase/tests/_generated_parity.sql', 'utf8')
  run('node', ['scripts/gen-parity-sql.mjs'])
  const after = readFileSync('supabase/tests/_generated_parity.sql', 'utf8')
  if (before !== after) {
    throw new Error(
      'supabase/tests/_generated_parity.sql was stale and has been regenerated.\n' +
      'The TypeScript and SQL attendance arithmetic may have diverged — review and commit it.',
    )
  }
})

if (wantSql) {
  step('SQL suites', () => {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'DATABASE_URL is not set.\n' +
        'Supabase dashboard → Project Settings → Database → Connection string (URI).\n' +
        'Run the suites against a BRANCH, not production — several of them mutate data.',
      )
    }
    run('node', ['scripts/run-sql-tests.mjs'])
  })
}

const failed = results.filter(([, ok]) => !ok)
console.log('\n' + '─'.repeat(50))
for (const [name, ok] of results) console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}`)
console.log(`${results.length - failed.length}/${results.length} passed`)
if (!wantSql) console.log('(SQL suites skipped — add --sql with DATABASE_URL set)')
process.exit(failed.length ? 1 : 0)
