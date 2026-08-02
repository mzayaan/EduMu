#!/usr/bin/env node
/**
 * EduMU :: check BLUEPRINT.md against what was actually built.
 *
 * Three questions, and the second is the one people forget:
 *
 *   1. PROMISED, NOT BUILT — an identifier the blueprint names that exists
 *      nowhere in the database or the source tree. Either a real gap, or a
 *      rename that left the document behind.
 *
 *   2. BUILT, NOT DOCUMENTED — a table, RPC or view that exists and the
 *      blueprint never mentions. The document stops being a map of the system
 *      and becomes a historical artefact, which nobody notices until they trust
 *      it.
 *
 *   3. BUILT, NOT REACHABLE — an RPC the client never calls. Not automatically
 *      wrong (triggers, cron targets and SQL-only helpers belong here) but a
 *      user-facing RPC in this list has no route to a user.
 *
 * Matching is whole-word against the full text, NOT just inline-backticked
 * spans — the blueprint puts its whole data model in fenced SQL blocks, and an
 * earlier version of this script that only read `like this` reported 79 of 89
 * functions as undocumented. If a number here looks implausible, suspect the
 * script before the app.
 *
 * It matches identifiers, not intent, so it cannot tell you whether a feature
 * works — only whether the thing the blueprint names is present. Read the
 * output as a list of places to look.
 *
 * Refresh scripts/audit-blueprint-data.json from the live catalogue with:
 *
 *   select string_agg(relname,',' order by relname) from pg_class c
 *     join pg_namespace n on n.oid=c.relnamespace
 *    where n.nspname='public' and c.relkind='r';
 *   -- and similarly for functions, views, enums, columns, role/capability codes
 *
 *   node scripts/audit-blueprint.mjs
 *   node scripts/audit-blueprint.mjs --json
 */

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const asJson = process.argv.includes('--json')

const DB = JSON.parse(readFileSync(join(ROOT, 'scripts', 'audit-blueprint-data.json'), 'utf8'))
const split = (s) => new Set(String(s || '').split(',').map((x) => x.trim()).filter(Boolean))

const tables = split(DB.tables)
const functions = split(DB.functions)
const views = split(DB.views)
const enums = split(DB.enums)
const buckets = split(DB.buckets)
const columns = split(DB.columns)
const enumLabels = split(DB.enumLabels)
const roleCodes = split(DB.roleCodes)
const capabilityCodes = split(DB.capabilityCodes)
// Promotion condition kinds live as JSON string values inside
// promotion_rule.conditions, so no catalogue query can see them. They are real
// and implemented; without this the audit reports the whole rules engine as
// missing every time.
const conditionKinds = split(DB.conditionKinds)

// Anything that legitimately exists somewhere in the system, under any guise.
const everything = new Set([
  ...tables, ...functions, ...views, ...enums, ...buckets,
  ...columns, ...enumLabels, ...roleCodes, ...capabilityCodes, ...conditionKinds,
])

// ── source tree ───────────────────────────────────────────────────────────
const walk = (dir, out = []) => {
  if (!existsSync(dir)) return out
  for (const e of readdirSync(dir)) {
    const p = join(dir, e)
    if (statSync(p).isDirectory()) walk(p, out)
    else out.push(p)
  }
  return out
}

const srcFiles = walk(join(ROOT, 'apps', 'web', 'src'))
const components = srcFiles.filter((f) => /\.tsx$/.test(f))
  .map((f) => f.split(/[\\/]/).pop().replace(/\.tsx$/, ''))
const featureDir = join(ROOT, 'apps', 'web', 'src', 'features')
const features = existsSync(featureDir) ? readdirSync(featureDir) : []
const testDir = join(ROOT, 'supabase', 'tests')
const sqlTests = existsSync(testDir)
  ? readdirSync(testDir).filter((f) => f.endsWith('.sql')) : []

const srcText = srcFiles.filter((f) => /\.(ts|tsx)$/.test(f))
  .map((f) => readFileSync(f, 'utf8')).join('\n')
const calledRpcs = new Set(
  [...srcText.matchAll(/\.rpc\(\s*['"`]([a-z0-9_]+)['"`]/g)].map((m) => m[1]))
const queriedTables = new Set(
  [...srcText.matchAll(/\.from\(\s*['"`]([a-z0-9_]+)['"`]/g)].map((m) => m[1]))

// ── blueprint ─────────────────────────────────────────────────────────────
const bp = readFileSync(join(ROOT, 'BLUEPRINT.md'), 'utf8')

// Whole-word presence anywhere in the document — prose, tables or fenced SQL.
const mentions = (word) =>
  new RegExp(`(^|[^A-Za-z0-9_])${word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^A-Za-z0-9_]|$)`)
    .test(bp)

// Every snake_case-ish token the blueprint uses, from anywhere in the text.
const tokens = new Set([...bp.matchAll(/\b([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\b/g)].map((m) => m[1]))

// Tokens that look like identifiers but are SQL/TS keywords, config, or prose.
const NOISE = new Set(`
search_path,pg_temp,pg_cron,pg_catalog,information_schema,service_role,row_level,
foreign_key,primary_key,not_null,on_conflict,do_update,do_nothing,order_by,group_by,
security_invoker,security_definer,check_violation,gen_random_uuid,current_date,current_user,
set_config,jsonb_build_object,jsonb_agg,jsonb_array_elements,string_agg,array_agg,to_char,
date_trunc,generate_series,row_number,dense_rank,unique_index,partial_index,
node_modules,package_lock,tsconfig_json,vite_config,use_state,use_effect,use_query,
react_query,react_router,react_dom,react_i18next,idb_keyval,date_fns,tailwind_merge,
service_worker,web_worker,local_storage,index_db,edge_function,edge_functions,
data_model,use_case,use_cases,real_time,end_to_end,day_to_day,drag_and_drop,
front_end,back_end,multi_tenant,multi_tenancy,single_school,off_line,
`.split(/[\s,]+/).filter(Boolean))

// ── 1. promised, not built ────────────────────────────────────────────────
const promisedMissing = [...tokens]
  .filter((t) => !NOISE.has(t))
  .filter((t) => !everything.has(t))
  // not a component, feature folder or test suite either
  .filter((t) => !components.some((c) => c.toLowerCase() === t.replace(/_/g, '')))
  .filter((t) => !features.includes(t))
  .filter((t) => !sqlTests.some((s) => s.replace(/\.sql$/, '') === t))
  .sort()

// ── 2. built, not documented ──────────────────────────────────────────────
const undocumented = {
  tables: [...tables].filter((t) => !mentions(t)).sort(),
  functions: [...functions].filter((f) => !mentions(f)).sort(),
  views: [...views].filter((v) => !mentions(v)).sort(),
  enums: [...enums].filter((e) => !mentions(e)).sort(),
}

// ── 3. built, not reachable ───────────────────────────────────────────────
const uncalledRpcs = [...functions].filter((f) => f.startsWith('rpc_') && !calledRpcs.has(f)).sort()
const unqueriedTables = [...tables].filter((t) => !queriedTables.has(t)).sort()

const out = {
  inventory: {
    blueprintChars: bp.length,
    blueprintTokens: tokens.size,
    tables: tables.size, functions: functions.size, views: views.size,
    enums: enums.size, buckets: buckets.size,
    components: components.length, features: features.length, sqlSuites: sqlTests.length,
    rpcsCalled: calledRpcs.size, tablesQueried: queriedTables.size,
  },
  promisedMissing,
  undocumented,
  uncalledRpcs,
  unqueriedTables,
}

if (asJson) {
  console.log(JSON.stringify(out, null, 2))
} else {
  const h = (s) => console.log(`\n\x1b[1m${s}\x1b[0m`)
  const list = (a, indent = '   ') =>
    a.length ? a.forEach((x) => console.log(indent + x)) : console.log(indent + '— none')
  const i = out.inventory

  h('Inventory')
  console.log(`   blueprint   ${i.blueprintChars.toLocaleString()} chars · ${i.blueprintTokens} snake_case tokens`)
  console.log(`   database    ${i.tables} tables · ${i.functions} functions · ${i.views} views · ${i.enums} enums · ${i.buckets} buckets`)
  console.log(`   source      ${i.components} components · ${i.features} features · ${i.sqlSuites} SQL suites`)
  console.log(`   wired       ${i.rpcsCalled} RPCs called · ${i.tablesQueried} tables queried from the client`)

  h(`1 · Named in the blueprint, exists nowhere (${promisedMissing.length})`)
  list(promisedMissing)

  h('2 · Built, never named in the blueprint')
  for (const [k, v] of Object.entries(undocumented)) {
    console.log(`   ${k} (${v.length})`)
    list(v, '      ')
  }

  h(`3 · RPCs never called from the client (${uncalledRpcs.length})`)
  console.log('   triggers, cron targets and SQL-only helpers belong here')
  list(uncalledRpcs)

  h(`   Tables never queried from the client (${unqueriedTables.length})`)
  console.log('   many are reached only through an RPC or a view, which is fine')
  list(unqueriedTables)
}
