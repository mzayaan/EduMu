# EduMU — restoring the database

An unrehearsed backup is a hope, not a backup. Rehearse this into an empty
project **before** a real school's data exists, and again after any change to
the schema, storage buckets or the auth hook.

The rehearsal is the point. If you only ever read this document, you have not
tested anything.

---

## What a complete restore consists of

Four things. Miss any one and the app comes up in a state that looks fine and
is not.

| # | Artifact | Covers | Where |
|---|---|---|---|
| 1 | `supabase/migrations/00000000000000_baseline.sql` | 102 tables, 215 policies, enums, functions in `public` and `app` | pg_dump, `--schema=public --schema=app` |
| 2 | `supabase/migrations/00000000000001_storage_and_cron.sql` | 6 storage buckets, 10 storage RLS policies, the pg_cron job | hand-written — pg_dump with those flags does **not** capture it |
| 3 | Migrations `48`+ | Everything applied after the baseline was taken | `node scripts/dump-migrations.mjs` |
| 4 | The auth hook | Every capability claim in every JWT | **Dashboard only. Not in any dump.** |

Item 4 is the one that will catch you. See step 5.

---

## Rehearsal

### 1 · Create an empty project

Same region as production (`ap-south-1`) so you are rehearsing the same
latency and the same Postgres build. Note the new project ref.

Do not use the production project. The whole point is to prove the artifacts
are sufficient on their own.

### 2 · Apply the baseline

```powershell
$env:PGPASSWORD = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
psql "postgresql://postgres.<newref>@aws-1-ap-south-1.pooler.supabase.com:5432/postgres" `
     -f supabase/migrations/00000000000000_baseline.sql
```

Use the **session pooler** host. `db.<ref>.supabase.co` is IPv6-only and will
not resolve on most connections — this cost an afternoon once already.

The server is Postgres 17.6, so you need a **PG17** client. A PG16 `psql` or
`pg_dump` fails on the version check.

### 3 · Apply the storage and cron supplement

```powershell
psql "$CONN" -f supabase/migrations/00000000000001_storage_and_cron.sql
```

Skipping this is survivable-looking: the app runs, and file uploads fail later
with a permissions error that reads as an application bug.

### 4 · Apply everything after the baseline

```powershell
Get-ChildItem supabase/migrations/2026*.sql | Sort-Object Name | ForEach-Object {
  Write-Host "→ $($_.Name)"
  psql "$CONN" -f $_.FullName
}
```

If that directory is empty or stale, the database is ahead of the repo. Fix it
first:

```powershell
$env:DATABASE_URL = "postgresql://postgres.<prodref>:<pw>@aws-1-ap-south-1.pooler.supabase.com:5432/postgres"
node scripts/dump-migrations.mjs
```

### 5 · Enable the auth hook — do not skip this

Dashboard → **Authentication → Hooks → Custom Access Token** →
select `app.custom_access_token_hook`.

Without it, tokens are issued with no `caps` and no `school_id`. Every RLS
policy then evaluates false, so **every screen comes up empty with no error**.
Nothing in the UI, the logs or the network tab points at the hook. It reads as
"the restore lost all the data".

The hook must be **SECURITY INVOKER** — the dashboard picker only lists invoker
functions. The privileged reads it needs live in `app.build_claims`, which is
DEFINER. If you find yourself editing the hook to be DEFINER to make it work,
you are solving the wrong problem.

### 6 · Point the app at it

```
apps/web/.env.local
  VITE_SUPABASE_URL=https://<newref>.supabase.co
  VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

### 7 · Verify

Structural check — run against the restored database:

```sql
select 'tables'        as k, count(*)::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r'
union all select 'without RLS', count(*)::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
union all select 'RLS not FORCEd', count(*)::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relrowsecurity and not c.relforcerowsecurity
union all select 'policies', count(*)::text from pg_policy
union all select 'buckets', count(*)::text from storage.buckets
union all select 'cron jobs', count(*)::text from cron.job;
```

Expected, as of migration 55:

```
tables          102
without RLS       0      ← any other number: stop
RLS not FORCEd    0      ← any other number: stop
policies        215
buckets           6      ← 0 means step 3 was skipped
cron jobs         1
```

Then the checks a structural query cannot make:

- [ ] **Sign in and confirm the JWT carries `caps`.** Decode the token; if
      `caps` is absent or empty, step 5 was missed. This is the single most
      likely failure.
- [ ] Open a register and save it.
- [ ] Open a report book and confirm attendance counts render.
- [ ] Upload a file, to prove the storage policies came across.
- [ ] Sign in as a guardian and confirm you see one family and not the school.
- [ ] Run the SQL suites in `supabase/tests/` — particularly
      `rls_isolation_sweep.sql` and `rpc_definer_authorisation.sql`.

Only when all of those pass has the backup been tested.

---

## What this does not cover

- **Row data.** The baseline is schema only. Real pupil data needs Supabase's
  own backup, and point-in-time recovery is worth paying for once real records
  exist — children's data, and a day's lost attendance cannot be reconstructed.
- **Auth users.** `auth.users` is not in the dump. A restored project has the
  schema and no accounts.
- **Secrets.** API keys and the database password are per-project and are
  regenerated. Do not expect them to carry over, and do not store them here.

## Do not

- Do not load `supabase/seed.sql` into anything real. It is demo data and says
  so at the top.
- Do not restore into production to "test" it.
- Do not treat a successful `psql` exit as a successful restore. The auth hook
  failure produces a clean exit and a broken system.
