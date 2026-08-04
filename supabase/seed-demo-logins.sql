/*
 * EduMU :: demo logins — one account for every role.
 *
 * ┌────────────────────────────────────────────────────────────────────────┐
 * │ DEMO TENANT ONLY. NEVER RUN THIS AGAINST A SCHOOL.                     │
 * │                                                                        │
 * │ Every account shares one published password. Anyone who reads the      │
 * │ README can sign in as the Rector. That is the point — it is a          │
 * │ portfolio demo over synthetic pupils — and it is also exactly why it   │
 * │ must never touch a tenant holding real children's records.             │
 * └────────────────────────────────────────────────────────────────────────┘
 *
 * Idempotent: re-running updates the password and leaves everything else
 * alone, so it is safe to run after adding a role.
 *
 * WHY THE AUTH ROWS ARE WRITTEN DIRECTLY
 * --------------------------------------
 * Creating users properly means the Auth Admin API, which needs the
 * service_role key. That key bypasses every RLS policy in the database and
 * has no business being pasted into a terminal. Writing auth.users and
 * auth.identities by hand with pgcrypto's bcrypt is the same thing GoTrue
 * would do, and needs no secret.
 *
 * The auth.identities row is not optional. Without it GoTrue treats the
 * account as having no linked provider and password sign-in fails with a
 * message that points nowhere near the cause.
 */

do $$
declare
  v_school     uuid;
  v_year       uuid;
  v_class      uuid;
  v_password   text := 'EduMU#Demo2026';
  v_domain     text := 'demo-sss.mu';
  r            record;
  v_person     uuid;
  v_user       uuid;
  v_scope      role_scope;
  v_scope_id   uuid;
  v_session    session_type;
  v_email      text;
  v_made       int := 0;
begin
  select id into v_school from school where code = 'DEMO-SSS';
  if v_school is null then
    raise exception 'No DEMO-SSS school — this script is for the demo tenant only';
  end if;

  select id into v_year from academic_year
   where school_id = v_school order by (status = 'active') desc, starts_on desc limit 1;

  select cg.id into v_class from class_group cg
   where cg.academic_year_id = v_year order by cg.name limit 1;

  -- ── staff accounts, one per staff role ────────────────────────────────
  for r in
    select * from (values
      ('rector',        'rector',       'Priya',    'Seebaluck',   'Rector'),
      ('deputy_rector', 'deputy',       'Kevin',    'Appadoo',     'Deputy Rector'),
      ('school_admin',  'admin',        'Marie',    'Louis',       'School Administrator'),
      ('clerk',         'clerk',        'Sanjay',   'Ramgoolam',   'Clerk'),
      ('bursar',        'bursar',       'Nadia',    'Beebeejaun',  'Bursar'),
      ('hod',           'hod',          'Vikram',   'Gopal',       'Head of Department'),
      ('educator',      'educator',     'Sarah',    'Lim',         'Educator'),
      ('form_teacher',  'formteacher',  'Yashwin',  'Pillay',      'Educator / Form Teacher'),
      ('usher',         'usher',        'Jean',     'Baptiste',    'Usher (School Superintendent)'),
      ('librarian',     'librarian',    'Reena',    'Mohit',       'Librarian'),
      ('lab_tech',      'labtech',      'Ashok',    'Cheekhoory',  'Laboratory Technician'),
      ('counsellor',    'counsellor',   'Lydia',    'Perrine',     'Counsellor'),
      ('zone_officer',  'zoneofficer',  'Devi',     'Narain',      'Zone Officer'),
      ('super_admin',   'superadmin',   'Platform', 'Administrator','Platform Administrator')
    ) as t(role_code, local_part, first_name, last_name, post)
  loop
    v_email := r.local_part || '@' || v_domain;

    -- person
    select id into v_person from person
     where school_id = v_school and email = v_email;

    if v_person is null then
      insert into person (school_id, person_type, first_name, last_name, email,
                          preferred_language, address, is_active)
      values (v_school, 'staff', r.first_name, r.last_name, v_email, 'en', '{}'::jsonb, true)
      returning id into v_person;
    end if;

    -- staff subtype. `staff.id` is the same key as `person.id`, so this is a
    -- subtype row rather than a separate identity.
    insert into staff (id, school_id, staff_number, post, employment_type, appointed_on)
    values (v_person, v_school, upper(r.local_part) || '-001', r.post, 'permanent', current_date)
    on conflict (id) do update set post = excluded.post;

    -- auth user
    select id into v_user from auth.users where email = v_email;

    if v_user is null then
      v_user := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data, is_super_admin,
        -- These MUST be '' and not NULL. GoTrue is written in Go and scans
        -- them into non-nullable strings; a NULL raises "converting NULL to
        -- string is unsupported" and the token endpoint returns a bare 500
        -- with nothing in the browser to suggest the cause. The account looks
        -- perfectly valid in SQL and simply cannot sign in.
        confirmation_token, recovery_token, email_change_token_new,
        email_change, email_change_token_current,
        phone_change, phone_change_token, reauthentication_token)
      values (
        '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
        v_email, crypt(v_password, gen_salt('bf')),
        now(), now(), now(),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
        jsonb_build_object('full_name', r.first_name || ' ' || r.last_name),
        false,
        '', '', '', '', '', '', '', '');

      insert into auth.identities (
        id, provider_id, user_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at)
      values (
        gen_random_uuid(), v_user::text, v_user,
        jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
        'email', now(), now(), now());

      v_made := v_made + 1;
    else
      -- Re-running resets the password, which is what makes this safe to use
      -- as a "put the demo back" button.
      update auth.users
         set encrypted_password = crypt(v_password, gen_salt('bf')),
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             updated_at = now()
       where id = v_user;
    end if;

    update person set auth_user_id = v_user where id = v_person;

    -- role assignment, scoped the way the role definition says
    select default_scope into v_scope from role where code = r.role_code;
    v_scope := coalesce(v_scope, 'school');
    v_scope_id := case when v_scope = 'class' then v_class else v_school end;

    -- A class may have only one Form Teacher per session, and Anjali Ramdin
    -- already holds AM on the demo class. This one takes the afternoon
    -- register, which is also a better demo: it shows the two-teacher split.
    v_session := case when r.role_code = 'form_teacher' then 'pm'::session_type end;

    insert into staff_role_assignment (school_id, academic_year_id, staff_id,
                                       role_code, scope_type, scope_id,
                                       valid_from, session)
    select v_school, v_year, v_person, r.role_code, v_scope, v_scope_id,
           current_date, v_session
    where not exists (
      select 1 from staff_role_assignment sra
      where sra.staff_id = v_person and sra.role_code = r.role_code
        and sra.valid_to is null);
  end loop;

  -- ── guardian and pupil ────────────────────────────────────────────────
  -- These two are person_type, not staff roles, so they attach to people who
  -- already exist in the demo data. A guardian invented here would have no
  -- ward, and would show an empty portal that looks broken rather than
  -- demonstrating anything.
  for r in
    select p.id, p.person_type,
           case p.person_type when 'guardian' then 'guardian' else 'student' end as local_part
    from person p
    where p.school_id = v_school
      and p.person_type in ('guardian', 'student')
      and p.auth_user_id is null
    order by p.person_type, p.last_name, p.first_name
  loop
    -- One of each is enough to demonstrate the portal.
    v_email := r.local_part || '@' || v_domain;
    if exists (select 1 from auth.users where email = v_email) then
      continue;
    end if;

    v_user := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data, is_super_admin,
      -- Empty strings, never NULL — see the note on the staff insert above.
      confirmation_token, recovery_token, email_change_token_new,
      email_change, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token)
    values (
      '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
      v_email, crypt(v_password, gen_salt('bf')),
      now(), now(), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      '{}'::jsonb, false,
      '', '', '', '', '', '', '', '');

    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), v_user::text, v_user,
      jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
      'email', now(), now(), now());

    update person set auth_user_id = v_user, email = v_email where id = r.id;
    v_made := v_made + 1;
  end loop;

  -- Belt and braces: repair any account that predates this fix, including ones
  -- created by an earlier run of this very script.
  update auth.users set
    confirmation_token         = coalesce(confirmation_token, ''),
    recovery_token             = coalesce(recovery_token, ''),
    email_change_token_new     = coalesce(email_change_token_new, ''),
    email_change               = coalesce(email_change, ''),
    email_change_token_current = coalesce(email_change_token_current, ''),
    phone_change               = coalesce(phone_change, ''),
    phone_change_token         = coalesce(phone_change_token, ''),
    reauthentication_token     = coalesce(reauthentication_token, '');

  raise notice 'Demo logins ready. % new account(s). Password: %', v_made, v_password;
end $$;

-- Refuse to report success while any account still cannot sign in. A NULL in
-- one of these columns produces a 500 from /auth/v1/token with nothing in the
-- browser or the SQL to explain it, so it is worth failing loudly here.
do $$
declare n int;
begin
  select count(*) into n from auth.users
   where confirmation_token is null or recovery_token is null
      or email_change_token_new is null or email_change is null
      or email_change_token_current is null or phone_change is null
      or phone_change_token is null or reauthentication_token is null;
  if n > 0 then
    raise exception '% account(s) have NULL auth token columns and will 500 on sign-in', n;
  end if;
end $$;

-- What was created, and what each account will actually see.
select
  u.email,
  p.first_name || ' ' || p.last_name as person,
  p.person_type::text,
  coalesce((select string_agg(distinct sra.role_code, ', ' order by sra.role_code)
            from staff_role_assignment sra
            where sra.staff_id = p.id and sra.valid_to is null), '—') as roles,
  jsonb_array_length(app.build_claims(u.id) -> 'caps') as capabilities
from auth.users u
join person p on p.auth_user_id = u.id
order by capabilities desc, u.email;
