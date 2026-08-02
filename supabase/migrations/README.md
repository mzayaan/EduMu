# Migrations

## How this folder came to look like this

The schema was built as 48 incremental migrations applied directly to the linked
project. Running `supabase db pull` afterwards **squashed the history and wrote
an empty baseline file** — the CLI diffs remote history against local migrations,
saw 48 already-applied entries, concluded there was nothing to write, and reset
`supabase_migrations.schema_migrations`.

No schema and no data were lost: the live database was and is complete. What was
lost is the incremental history. The recovery is a full dump, which is arguably a
better starting point than 48 steps nobody will ever replay individually.

## Regenerating the baseline

`supabase db dump` shells out to a Docker container. If Docker isn't available,
use `pg_dump` directly — the server is **PostgreSQL 17.6**, so a **PostgreSQL 17
client** is required (an older `pg_dump` will refuse).

Connection string: Supabase dashboard → Project Settings → Database →
Connection string → URI. Use the **direct** connection, not the pooler.

```powershell
$env:PGPASSWORD = "<your database password>"

pg_dump `
  --host=db.wdwtapdmdgdcvbifbeiz.supabase.co --port=5432 `
  --username=postgres --dbname=postgres `
  --schema=public --schema=app `
  --schema-only --no-owner --no-privileges `
  --file=supabase\migrations\00000000000000_baseline.sql
```

Notes on the flags:

- `--schema=public --schema=app` — the application's own schemas. `app` holds
  the RLS helper functions; without it every policy fails to compile.
- `--no-owner --no-privileges` — Supabase manages roles; keeping ownership
  statements makes the dump unrestorable elsewhere.
- **Do not** add `--no-comments`. The schema carries a lot of explanatory
  comments, several recording rules from the School Management Manual.
- **Do not** dump the `storage`, `auth`, `cron` or `graphql` schemas. They are
  Supabase-managed and will fight with its own migrations on restore. What this
  project puts *into* them lives in `00000000000001_storage_and_cron.sql`.

## Verify the dump before trusting it

The last one was 0 bytes and nothing caught it. Check against the live database:

| Object | Expected |
|---|---|
| Tables (`public` + `app`) | 101 |
| RLS policies (`public`) | 201 |
| Functions (`public` + `app`) | 82 |
| Enum types | 19 |
| Triggers (`public`) | 20 |

```powershell
(Get-Item supabase\migrations\00000000000000_baseline.sql).Length   # must be > 0
Select-String -Path supabase\migrations\00000000000000_baseline.sql `
  -Pattern "CREATE TABLE" | Measure-Object                          # ~101
Select-String -Path supabase\migrations\00000000000000_baseline.sql `
  -Pattern "CREATE POLICY" | Measure-Object                         # ~201
```

Spot-check that these specific objects made it in — each is load-bearing and
each was added late, so they are the ones most likely to be missing:

```
app.custom_access_token_hook      RLS reads everything from the JWT it builds
timetable_slot_student_clash      the pupil-clash guard (migration 48)
report_card_data                  the whole report book payload
rpc_provision_school              multi-tenant provisioning
app.attendance_stats              parity with the TypeScript arithmetic
```

## Order

1. `00000000000000_baseline.sql` — schema, from `pg_dump`
2. `00000000000001_storage_and_cron.sql` — buckets, storage RLS, nightly job

Optionally `supabase/seed.sql` for the demo tenant, which is **not** required
and should be skipped when loading a real school.
