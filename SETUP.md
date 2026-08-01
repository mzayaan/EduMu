# Handover — commands to run on Windows

## 1. Push the first commit (2 minutes)

The commit already exists. I built it with the git directory outside the mount
(the mount forbids `unlink`, so git cannot manage its own lock files there) and
exported it as **`edumu-initial.bundle`** in this folder — a complete repository
with full history, 75 files, 16,803 insertions.

I could not push it: this environment has no GitHub credentials and cannot run
an OAuth flow. Three commands finish it:

```powershell
Remove-Item -Recurse -Force .git          # clears my half-initialised attempt
git clone edumu-initial.bundle .tmp-repo  # unpack the real commit
Move-Item .tmp-repo\.git .git ; Remove-Item -Recurse -Force .tmp-repo
git remote set-url origin https://github.com/mzayaan/EduMu.git
git push -u origin main
```

Then verify nothing sensitive shipped, and delete the bundle:

```powershell
git ls-files | Select-String "\.env$"     # must return nothing
Remove-Item edumu-initial.bundle
Remove-Item supabase\tests\probe.sql, supabase\tests\.keep -ErrorAction SilentlyContinue
git commit -am "Remove scratch files" ; git push
```

`.env` is gitignored and untracked — only `.env.example` is committed, and it
holds the publishable key, which is safe to publish.

## 2. Bring the migrations into the repo

**This is the important one.** All 24 migrations currently exist only inside the
Supabase project. Until this runs, the schema has no backup.

```powershell
npx supabase login
npx supabase link --project-ref wdwtapdmdgdcvbifbeiz
npx supabase db pull
npm run db:types
```

`db pull` writes `supabase/migrations/*.sql`. Confirm the folder is no longer
empty before committing.

## 3. Check everything still passes

```powershell
npm run typecheck
npm test
npm run gen:parity
git status          # _generated_parity.sql should be unchanged
```

## 4. First commit

```powershell
git add -A
git status          # confirm no .env and no node_modules
git commit -m "EduMU: attendance core, RLS, eligibility screening

Phase 0 and Phase 1 of the blueprint. Supabase schema with RLS on every
table, custom access-token hook, offline-first register, lesson attendance,
Usher's discrepancy board, exam eligibility screening against the 80% rule.

Four SQL test suites plus a generated parity suite keeping the TypeScript and
SQL attendance arithmetic in agreement."
git push -u origin main
```

## 5. Wire up CI

The workflow in `.github/workflows/ci.yml` runs typecheck, unit tests, the
parity check, and the SQL suites against a fresh local Supabase. It needs no
secrets — `supabase start` runs a throwaway database in the runner.

Check the first run: `supabase db reset` replaying all migrations from empty is
the step that proves the schema is genuinely reproducible from the repo.

## 6. Two dashboard toggles before any pilot

- **Authentication → Providers → Password** → enable "Prevent use of leaked
  passwords".
- Consider enabling MFA for the Rector and Clerk accounts.

## Demo shortcuts to reverse for a real school

- `a.ramdin@demo-sss.mu` holds both `form_teacher` and `usher` so a single login
  reaches every screen. The Usher is a distinct post (School Superintendent).
- The demo school, its five pupils and the seeded Term 1 attendance are in
  migrations 10, 15, 18 and 22. Drop them before loading real data.
