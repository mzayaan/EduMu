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

## 1a. Verifying your work

CI has been removed — the Docker stack it needed was too heavy for what it
bought. The same checks run locally:

```powershell
npm run verify                 # typecheck, unit tests, parity freshness
$env:DATABASE_URL = "postgresql://postgres:...@db....supabase.co:5432/postgres"
npm run verify -- --sql        # plus the 14 SQL suites
```

Point `DATABASE_URL` at a **branch**, not production: several suites debar a
pupil, publish marks and amend registers.

Run `npm run verify` before each commit. Nothing enforces it, which is the
honest cost of dropping CI.

## 2. Bring the migrations into the repo

**This is the important one.** All 48 migrations currently exist only inside the
Supabase project. Until this runs, the schema has no backup — and with CI gone,
nothing else will ever replay them to prove they still work from empty.

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

## 4. Commit and push

```powershell
npm run verify
git add -A
git status          # confirm no .env and no node_modules
git commit -m "Add migrations pulled from the linked project"
git push
```

## 5. Two dashboard toggles before any pilot

- **Authentication → Providers → Password** → enable "Prevent use of leaked
  passwords".
- Consider enabling MFA for the Rector and Clerk accounts.

## Demo shortcuts to reverse for a real school

- `a.ramdin@demo-sss.mu` holds both `form_teacher` and `usher` so a single login
  reaches every screen. The Usher is a distinct post (School Superintendent).
- The demo school, its pupils, timetable, marks and attendance are seeded by
  migrations 10, 15, 18, 22, 26, 44 and 46. Drop them before loading real data.
- A second tenant (`QB-SSS`) exists from testing multi-tenancy.
- `r.bhugaloo@zone2.govmu` is a Zone Director fixture with no teaching duties.
