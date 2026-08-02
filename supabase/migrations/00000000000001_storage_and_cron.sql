-- EduMU :: Storage buckets, storage policies, and the scheduled rebuild.
--
-- WHY THIS FILE EXISTS SEPARATELY
--
-- The baseline is produced with `pg_dump --schema=public --schema=app`, which
-- covers the application's own schemas. It does NOT cover:
--
--   * storage.buckets      — rows in a Supabase-managed table
--   * storage.objects RLS  — policies on a Supabase-managed table
--   * cron.job             — the nightly attendance rebuild
--
-- Dumping those schemas wholesale would fight with Supabase's own migrations on
-- restore, so they are reproduced here by hand instead. Extracted directly from
-- the live database, not from memory.
--
-- Apply AFTER the baseline: every policy calls app.* helper functions.

-- ─────────────────────────────────────────────────────────── buckets

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('student-photos', 'student-photos', false,  2097152,
    '{image/jpeg,image/png,image/webp}'::text[]),
  ('student-docs',   'student-docs',   false, 10485760,
    '{application/pdf,image/jpeg,image/png}'::text[]),
  ('staff-docs',     'staff-docs',     false, 10485760,
    '{application/pdf,image/jpeg,image/png}'::text[]),
  ('reports',        'reports',        false, 20971520,
    '{application/pdf}'::text[]),
  ('resources',      'resources',      false, 52428800, null),
  ('imports',        'imports',        false, 20971520,
    '{text/csv,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet}'::text[])
on conflict (id) do nothing;

-- ────────────────────────────────────────────────── storage policies
--
-- Object paths are {school_id}/{owner_id}/{filename}: the first segment is the
-- tenant, the second is the subject of the record. app.storage_school() and
-- app.storage_owner() parse them, and live in the baseline.

drop policy if exists "photos readable in school"   on storage.objects;
drop policy if exists "photos writable by admin"    on storage.objects;
drop policy if exists "student docs readable"       on storage.objects;
drop policy if exists "student docs writable"       on storage.objects;
drop policy if exists "staff docs readable"         on storage.objects;
drop policy if exists "staff docs writable"         on storage.objects;
drop policy if exists "reports readable"            on storage.objects;
drop policy if exists "resources readable in school" on storage.objects;
drop policy if exists "resources writable by staff" on storage.objects;
drop policy if exists "imports by admin"            on storage.objects;

create policy "photos readable in school" on storage.objects for select to authenticated
  using (bucket_id = 'student-photos' and app.storage_school(name) = app.school_id());

create policy "photos writable by admin" on storage.objects for insert to authenticated
  with check (bucket_id = 'student-photos'
              and app.storage_school(name) = app.school_id()
              and app.has_cap('student.manage'));

-- Birth certificates and medical records are the most sensitive data held.
create policy "student docs readable" on storage.objects for select to authenticated
  using (bucket_id = 'student-docs'
         and app.storage_school(name) = app.school_id()
         and (app.has_cap('student.manage')
              or app.is_guardian_of(app.storage_owner(name))
              or app.storage_owner(name) = app.person_id()));

create policy "student docs writable" on storage.objects for insert to authenticated
  with check (bucket_id = 'student-docs'
              and app.storage_school(name) = app.school_id()
              and (app.has_cap('student.manage')
                   or app.is_guardian_of(app.storage_owner(name))));

create policy "staff docs readable" on storage.objects for select to authenticated
  using (bucket_id = 'staff-docs'
         and app.storage_school(name) = app.school_id()
         and (app.has_cap('staff.manage')
              or app.storage_owner(name) = app.person_id()));

create policy "staff docs writable" on storage.objects for insert to authenticated
  with check (bucket_id = 'staff-docs'
              and app.storage_school(name) = app.school_id()
              and app.has_cap('staff.manage'));

-- Generated report books: a pupil and their Responsible Party, nobody else.
create policy "reports readable" on storage.objects for select to authenticated
  using (bucket_id = 'reports'
         and app.storage_school(name) = app.school_id()
         and (app.has_cap('marks.read.all')
              or app.is_guardian_of(app.storage_owner(name))
              or app.storage_owner(name) = app.person_id()));

create policy "resources readable in school" on storage.objects for select to authenticated
  using (bucket_id = 'resources' and app.storage_school(name) = app.school_id());

create policy "resources writable by staff" on storage.objects for insert to authenticated
  with check (bucket_id = 'resources'
              and app.storage_school(name) = app.school_id()
              and app.has_cap('marks.enter'));

create policy "imports by admin" on storage.objects for all to authenticated
  using (bucket_id = 'imports'
         and app.storage_school(name) = app.school_id()
         and app.has_cap('school.manage'))
  with check (bucket_id = 'imports'
              and app.storage_school(name) = app.school_id()
              and app.has_cap('school.manage'));

-- ──────────────────────────────────────────────────── scheduled job
--
-- A trigger keeps attendance_summary live as registers are marked; this nightly
-- rebuild is the authority, so amendments and retroactive closures cannot leave
-- drift. 18:00 UTC is 22:00 in Mauritius — after school, before anyone looks.

create extension if not exists pg_cron with schema extensions;

select cron.unschedule('edumu-rebuild-attendance-summaries')
where exists (select 1 from cron.job
              where jobname = 'edumu-rebuild-attendance-summaries');

select cron.schedule(
  'edumu-rebuild-attendance-summaries',
  '0 18 * * *',
  'select app.rebuild_all_attendance_summaries()'
);
