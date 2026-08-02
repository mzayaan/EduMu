#!/usr/bin/env node
/**
 * EduMU :: write applied migrations back out as files.
 *
 * Why this exists
 * ---------------
 * Migrations applied through the Supabase MCP or the dashboard SQL editor land
 * in the database and nowhere else. The repo's baseline dump then silently
 * predates them, and a restore loses work nobody noticed was missing — which is
 * exactly the state this project was in for migrations 48 through 55.
 *
 * Supabase keeps the full text of every applied migration in
 * supabase_migrations.schema_migrations. This pulls it back into the repo, so
 * the file tree and the database agree again.
 *
 * Deliberately does NOT replace the baseline pg_dump. The dump captures the
 * resolved end state (grants, defaults, extension objects); this captures the
 * history and the reasoning in the comments. They answer different questions,
 * and a restore wants both.
 *
 * Usage
 * -----
 *   $env:DATABASE_URL = "postgresql://postgres.<ref>:<pw>@aws-1-ap-south-1.pooler.supabase.com:5432/postgres"
 *   node scripts/dump-migrations.mjs            # write anything missing
 *   node scripts/dump-migrations.mjs --force    # also overwrite existing files
 *   node scripts/dump-migrations.mjs --check    # exit 1 if anything is missing
 *
 * The direct db.<ref>.supabase.co host is IPv6-only and will not resolve on most
 * home connections. Use the session pooler host, as above.
 *
 * Do not paste the password into a shell you do not control, and do not commit
 * it. Set it in the environment for the one command.
 */

import { writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT = join(ROOT, 'supabase', 'migrations')

const force = process.argv.includes('--force')
const checkOnly = process.argv.includes('--check')

const url = process.env.DATABASE_URL
if (!url) {
  console.error(
    'DATABASE_URL is not set.\n\n' +
      '  $env:DATABASE_URL = "postgresql://postgres.<ref>:<pw>' +
      '@aws-1-ap-south-1.pooler.supabase.com:5432/postgres"\n\n' +
      'Use the session pooler host — the direct host is IPv6-only.',
  )
  process.exit(2)
}

// Keep the filename in the shape the Supabase CLI expects, so `supabase db push`
// and `db diff` continue to line up with what is on disk.
const safe = (s) => s.replace(/[^a-zA-Z0-9_]+/g, '_').replace(/^_+|_+$/g, '')

const client = new pg.Client({
  connectionString: url,
  ssl: { rejectUnauthorized: false },
})

try {
  await client.connect()
} catch (err) {
  console.error(`Could not connect: ${err.message}`)
  if (/ENETUNREACH|EHOSTUNREACH/.test(err.message)) {
    console.error('That looks like the IPv6-only direct host. Use the pooler host.')
  }
  process.exit(1)
}

const { rows } = await client.query(`
  select version, name, coalesce(statements, '{}') as statements
  from supabase_migrations.schema_migrations
  order by version
`)
await client.end()

if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true })

let written = 0
let skipped = 0
const missing = []

for (const row of rows) {
  // Older rows can carry a null name; the version alone still identifies them.
  const base = row.name ? `${row.version}_${safe(row.name)}` : String(row.version)
  const file = join(OUT, `${base}.sql`)
  const sql = (row.statements ?? []).join('\n')

  if (!sql.trim()) {
    // A recorded migration with no retained text — usually a baseline marker.
    // Note it rather than writing an empty file that looks like a real one.
    console.log(`  –  ${base}.sql  (no statements retained; not written)`)
    continue
  }

  if (existsSync(file) && !force) {
    skipped++
    continue
  }

  missing.push(`${base}.sql`)
  if (!checkOnly) {
    writeFileSync(file, sql.endsWith('\n') ? sql : `${sql}\n`, 'utf8')
    written++
    console.log(`  +  ${base}.sql  (${sql.length.toLocaleString()} chars)`)
  }
}

console.log(
  `\n${rows.length} migration(s) in the database · ` +
    `${written} written · ${skipped} already present`,
)

if (checkOnly && missing.length) {
  console.error(
    `\nMissing from the repo:\n${missing.map((m) => `  ${m}`).join('\n')}\n\n` +
      'Run without --check to write them.',
  )
  process.exit(1)
}

if (!checkOnly && written > 0) {
  console.log('\nReview the diff before committing — this overwrites from the database,')
  console.log('so any local edit not yet applied would be lost.')
}
