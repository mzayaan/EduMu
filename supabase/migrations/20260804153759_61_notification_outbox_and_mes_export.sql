-- EduMU :: 61 The notification outbox the office can actually drain, and an
-- examination-entry export.

-- ── outbox ────────────────────────────────────────────────────────────────
/*
 * `notification` has been filling correctly on unauthorised absence,
 * discipline escalation and report publication since phase 3, and nothing has
 * ever emptied it. This is the read side plus the two status transitions.
 *
 * The guardian's number is resolved HERE rather than in the client, because
 * the client must not be handed a list of every parent's phone number in order
 * to send to a subset. RLS on this function's caller decides the school; the
 * function decides the recipients.
 */
create or replace function public.notification_outbox(
  p_channel text default 'sms', p_limit int default 200
) returns table (
  id uuid, person_id uuid, recipient_name text, phone text,
  template text, body text, status text, scheduled_for timestamptz, error text
)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select
    n.id, n.person_id,
    p.first_name || ' ' || p.last_name,
    coalesce(p.phone, p.phone_alt),
    n.template,
    -- The rendered message. Templates live in payload so a school can reword
    -- without a deploy; the fallback keeps an unknown template sendable rather
    -- than dropping it silently.
    coalesce(
      n.payload ->> 'body',
      case n.template
        when 'absence_unauthorised' then
          format('%s was marked absent from school on %s. Please contact the school.',
                 coalesce(n.payload ->> 'student_name', 'Your child'),
                 coalesce(n.payload ->> 'date', ''))
        when 'report_published' then
          format('The report book for %s is now available.',
                 coalesce(n.payload ->> 'student_name', 'your child'))
        when 'discipline_escalation' then
          format('The school needs to speak with you about %s. Please call.',
                 coalesce(n.payload ->> 'student_name', 'your child'))
        else n.template
      end),
    n.status, n.scheduled_for, n.error
  from notification n
  join person p on p.id = n.person_id
  where n.school_id = app.school_id()
    and n.channel = p_channel
    and n.status in ('queued', 'failed')
    and (n.scheduled_for is null or n.scheduled_for <= now())
    and app.has_cap('person.read.all')
  order by n.scheduled_for nulls first
  limit p_limit;
$$;

/*
 * Record what a provider did with a message.
 *
 * `p_provider_ref` is kept even on failure: a provider that accepted and then
 * failed downstream reports against that id, and without it a delivery report
 * cannot be matched to the pupil it concerns.
 */
create or replace function public.rpc_mark_notification_sent(
  p_id uuid, p_ok boolean, p_provider_ref text default null, p_error text default null
) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.has_cap('person.read.all') then
    raise exception 'Not authorised to dispatch notifications';
  end if;

  update notification
     set status       = case when p_ok then 'sent' else 'failed' end,
         sent_at      = case when p_ok then now() else sent_at end,
         provider_ref = coalesce(p_provider_ref, provider_ref),
         error        = case when p_ok then null else p_error end
   where id = p_id and school_id = app.school_id();

  if not found then raise exception 'Unknown notification'; end if;
end $$;

-- Ad-hoc message to one family, for the cases a template does not cover.
create or replace function public.rpc_queue_message(
  p_person uuid, p_body text, p_channel text default 'sms'
) returns uuid
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id uuid;
begin
  if not app.has_cap('person.read.all') then
    raise exception 'Not authorised to message guardians';
  end if;
  if nullif(trim(coalesce(p_body, '')), '') is null then
    raise exception 'The message is empty';
  end if;

  insert into notification (school_id, person_id, channel, template, payload, status)
  values (app.school_id(), p_person, p_channel, 'adhoc',
          jsonb_build_object('body', p_body), 'queued')
  returning id into v_id;
  return v_id;
end $$;

-- ── examination entries export ────────────────────────────────────────────
/*
 * MES has no published file format.
 *
 * Entries for SC/HSC school candidates are made through an Oracle APEX portal
 * (mes.govmu.org → E-Services → "Entries for School Candidates"), and no
 * schema for a bulk upload is published anywhere. Inventing one and calling it
 * "the MES format" would be worse than having none, because the name would be
 * believed.
 *
 * So this exports OUR OWN documented shape, which is what a clerk needs in
 * front of them while keying the portal, and what an adapter would map from
 * the day somebody obtains the real specification. See MES.md.
 *
 * One row per candidate per subject, because that is the grain the portal
 * collects and the grain a check against a paper entry form happens at.
 */
create or replace function public.exam_entry_export(p_session uuid)
returns table (
  centre_number text, candidate_number text, admission_number text,
  surname text, other_names text, date_of_birth date, sex text,
  class_name text, subject_code text, subject_name text, level text,
  is_private boolean, extra_time_minutes int, arrangements text
)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select
    s.centre_number, s.candidate_number, s.admission_number,
    upper(p.last_name), p.first_name, p.date_of_birth::date, p.sex::text,
    cg.name, sub.code, sub.name_en, ss.level::text,
    false,
    ea.extra_minutes::int,
    ea.detail
  from student s
  join person p on p.id = s.id
  join set_enrolment se on se.student_id = s.id and se.effective_to is null
  join subject_set ss on ss.id = se.subject_set_id
  join subject sub on sub.id = ss.subject_id
  left join class_enrolment ce on ce.student_id = s.id and ce.effective_to is null
  left join class_group cg on cg.id = ce.class_group_id
  left join exam_arrangement ea on ea.student_id = s.id
  join exam_session es on es.id = p_session
  where s.school_id = app.school_id()
    and s.status = 'enrolled'
    and app.has_cap('school.manage')
  order by upper(p.last_name), p.first_name, sub.code;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.notification_outbox(text, int)',
    'public.rpc_mark_notification_sent(uuid, boolean, text, text)',
    'public.rpc_queue_message(uuid, text, text)',
    'public.exam_entry_export(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
