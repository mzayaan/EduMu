-- EduMU :: GENERATED FILE — DO NOT EDIT.
-- Source: packages/domain/fixtures/attendance-cases.json
-- Regenerate: npm run gen:parity
--
-- Asserts that the SQL implementation of the attendance arithmetic
-- (app.attendance_stats) agrees with the TypeScript specification in
-- packages/domain/src/attendance.ts on every fixture case. The two exist
-- because the server must be the authority for eligibility while the client
-- needs the same maths for display; this suite is what keeps them honest.

create temp table if not exists pf(test text, expected text, got text, pass boolean);
truncate pf;

do $$
declare st record;
begin

  -- late and school activity count as present
  select * into st from app.attendance_stats(array['present','late','school_activity','absent_unauth']::attendance_status[], 80);
  insert into pf select 'late and school activity count as present :: pct_present',
    75::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 75::numeric;
  insert into pf select 'late and school activity count as present :: pct_excl_auth',
    75::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 75::numeric;
  insert into pf select 'late and school activity count as present :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'late and school activity count as present :: shortfall',
    1,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 1;

  -- authorised absence excluded from the scholarship denominator
  select * into st from app.attendance_stats(array['present','present','absent_auth','absent_unauth']::attendance_status[], 80);
  insert into pf select 'authorised absence excluded from the scholarship denominator :: pct_present',
    50::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 50::numeric;
  insert into pf select 'authorised absence excluded from the scholarship denominator :: pct_excl_auth',
    66.67::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 66.67::numeric;
  insert into pf select 'authorised absence excluded from the scholarship denominator :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'authorised absence excluded from the scholarship denominator :: shortfall',
    2,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 2;

  -- on_leave is an authorised absence
  select * into st from app.attendance_stats(array['present','on_leave','on_leave','present']::attendance_status[], 80);
  insert into pf select 'on_leave is an authorised absence :: pct_present',
    50::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 50::numeric;
  insert into pf select 'on_leave is an authorised absence :: pct_excl_auth',
    100::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 100::numeric;
  insert into pf select 'on_leave is an authorised absence :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'on_leave is an authorised absence :: shortfall',
    2,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 2;

  -- exactly at the threshold is eligible
  select * into st from app.attendance_stats(array['present','present','present','present','present','present','present','present','absent_unauth','absent_unauth']::attendance_status[], 80);
  insert into pf select 'exactly at the threshold is eligible :: pct_present',
    80::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 80::numeric;
  insert into pf select 'exactly at the threshold is eligible :: pct_excl_auth',
    80::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 80::numeric;
  insert into pf select 'exactly at the threshold is eligible :: eligible',
    true,
    st.eligible::text,
    st.eligible is not distinct from true;
  insert into pf select 'exactly at the threshold is eligible :: shortfall',
    0,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 0;

  -- just under the threshold is not eligible
  select * into st from app.attendance_stats(array['present','present','present','present','present','present','present','absent_unauth','absent_unauth','absent_unauth']::attendance_status[], 80);
  insert into pf select 'just under the threshold is not eligible :: pct_present',
    70::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 70::numeric;
  insert into pf select 'just under the threshold is not eligible :: pct_excl_auth',
    70::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 70::numeric;
  insert into pf select 'just under the threshold is not eligible :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'just under the threshold is not eligible :: shortfall',
    1,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 1;

  -- perfect attendance
  select * into st from app.attendance_stats(array['present','present','present','present']::attendance_status[], 80);
  insert into pf select 'perfect attendance :: pct_present',
    100::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 100::numeric;
  insert into pf select 'perfect attendance :: pct_excl_auth',
    100::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 100::numeric;
  insert into pf select 'perfect attendance :: eligible',
    true,
    st.eligible::text,
    st.eligible is not distinct from true;
  insert into pf select 'perfect attendance :: shortfall',
    0,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 0;

  -- never attended
  select * into st from app.attendance_stats(array['absent_unauth','absent_unauth','absent_unauth','absent_unauth']::attendance_status[], 80);
  insert into pf select 'never attended :: pct_present',
    0::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 0::numeric;
  insert into pf select 'never attended :: pct_excl_auth',
    0::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 0::numeric;
  insert into pf select 'never attended :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'never attended :: shortfall',
    4,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 4;

  -- wholly authorised absence leaves the scholarship view undefined
  select * into st from app.attendance_stats(array['absent_auth','on_leave']::attendance_status[], 80);
  insert into pf select 'wholly authorised absence leaves the scholarship view undefined :: pct_present',
    0::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 0::numeric;
  insert into pf select 'wholly authorised absence leaves the scholarship view undefined :: pct_excl_auth',
    null::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from null::numeric;
  insert into pf select 'wholly authorised absence leaves the scholarship view undefined :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'wholly authorised absence leaves the scholarship view undefined :: shortfall',
    2,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 2;

  -- excluded pupil counts as absent for attendance purposes
  select * into st from app.attendance_stats(array['present','present','excluded','excluded']::attendance_status[], 80);
  insert into pf select 'excluded pupil counts as absent for attendance purposes :: pct_present',
    50::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from 50::numeric;
  insert into pf select 'excluded pupil counts as absent for attendance purposes :: pct_excl_auth',
    50::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from 50::numeric;
  insert into pf select 'excluded pupil counts as absent for attendance purposes :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'excluded pupil counts as absent for attendance purposes :: shortfall',
    2,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 2;

  -- no sessions yields null rather than zero
  select * into st from app.attendance_stats('{}'::attendance_status[], 80);
  insert into pf select 'no sessions yields null rather than zero :: pct_present',
    null::text,
    coalesce(st.pct_present::text,'null'),
    st.pct_present is not distinct from null::numeric;
  insert into pf select 'no sessions yields null rather than zero :: pct_excl_auth',
    null::text,
    coalesce(st.pct_excl_auth::text,'null'),
    st.pct_excl_auth is not distinct from null::numeric;
  insert into pf select 'no sessions yields null rather than zero :: eligible',
    false,
    st.eligible::text,
    st.eligible is not distinct from false;
  insert into pf select 'no sessions yields null rather than zero :: shortfall',
    0,
    st.shortfall_sessions::text,
    st.shortfall_sessions = 0;
end $$;

select test, expected, got, case when pass then 'PASS' else 'FAIL' end as result from pf;
