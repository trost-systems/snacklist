-- Job 275: DSA notices ("Inhalte melden", Art. 16 DSA; Legal Addendum B, N-227 to N-230). The
-- report form on snacklist.app posts through the site's Vercel function to the report edge
-- function, which stores here and mails the confirmation; Peter decides each report himself and
-- records it with content_report_decide, and scripts/moderation/notify.ts mails the decision.
-- Only the service connection reaches the tables, through the functions below: anon and
-- authenticated have no privilege on any of it. No household_id: a web report belongs to no
-- household, is never shown to one and is not in export_my_data (the in-app job adds its own).
--
-- A report's lifecycle, read from its columns:
--   open       closed_at null
--   decided    closed_at set (the latest decision's time); every decision is a row of
--              content_report_decisions, notified_at once its mail went out
--   held       retain_until set while proceedings run: the purge waits for it
--   gone       12 months after closed_at (purge_content_reports, daily)

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique check (ref ~ '^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'),
  created_at timestamptz not null default now(),
  source text not null check (source in ('web')),
  locale text not null check (locale in ('de', 'en')),
  category text not null
    check (category in ('hate', 'personal_rights', 'ip', 'csam', 'danger', 'other')),
  location text not null check (char_length(btrim(location)) between 1 and 2000),
  reason text not null check (char_length(btrim(reason)) between 20 and 5000),
  reporter_name text check (char_length(reporter_name) between 1 and 200),
  reporter_email text check (char_length(reporter_email) between 3 and 254),
  good_faith boolean not null check (good_faith),
  confirmation_sent_at timestamptz,
  closed_at timestamptz,
  retain_until timestamptz,
  retain_reason text,
  constraint content_reports_retain_with_reason check ((retain_until is null) = (retain_reason is null))
);

comment on table public.content_reports is
  'Job 275: DSA notices (Art. 16) from the snacklist.app report form. Only Peter reads them; no agent or bot does. Service connection only.';
comment on column public.content_reports.retain_until is
  'Set by Peter while proceedings need the report (with retain_reason); the 12-month purge waits until then.';

create index content_reports_created_at on public.content_reports (created_at);
-- Reports that still owe their confirmation (notify.ts --confirmations).
create index content_reports_unconfirmed on public.content_reports (created_at)
  where reporter_email is not null and confirmation_sent_at is null;

alter table public.content_reports enable row level security;
revoke all on public.content_reports from public, anon, authenticated;

create table public.content_report_decisions (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.content_reports (id) on delete cascade,
  decided_at timestamptz not null,
  outcome text not null
    check (outcome in ('removed', 'made_invisible', 'account_suspended', 'no_change')),
  ground text not null check (char_length(btrim(ground)) between 1 and 5000),
  notified_at timestamptz
);

comment on table public.content_report_decisions is
  'Job 275: Peter''s decisions on content_reports (date, outcome, ground), kept with the report. Service connection only.';

create index content_report_decisions_report_id on public.content_report_decisions (report_id);

alter table public.content_report_decisions enable row level security;
revoke all on public.content_report_decisions from public, anon, authenticated;

-- One web report. Under a transaction lock, so the hour's count is exact: no row when p_max_per_hour
-- web reports already came in the hour before p_now, and nothing is stored. Otherwise the trimmed
-- report with a new reference; confirm says whether the caller mails the confirmation: whenever an
-- address was given (Art. 16(4) DSA has no volume exception; Legal N-241).
create function public.content_report_submit(
  p_locale text,
  p_category text,
  p_location text,
  p_reason text,
  p_name text,
  p_email text,
  p_now timestamptz,
  p_max_per_hour integer
)
returns table (id uuid, ref text, confirm boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  -- Crockford base32 without I L O U; 256 is a multiple of 32, so every letter is equally likely.
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_email text := nullif(btrim(p_email), '');
  v_bytes bytea;
  v_ref text;
  v_id uuid;
begin
  -- Conflicts with itself and with every write, so two submits count one after the other.
  lock table public.content_reports in share row exclusive mode;
  if (select count(*) from public.content_reports r
      where r.source = 'web' and r.created_at > p_now - interval '1 hour') >= p_max_per_hour then
    return;
  end if;

  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_ref := 'M-' || (
      select string_agg(substr(v_alphabet, 1 + get_byte(v_bytes, i) % 32, 1), '' order by i)
      from generate_series(0, 3) i
    ) || '-' || (
      select string_agg(substr(v_alphabet, 1 + get_byte(v_bytes, i) % 32, 1), '' order by i)
      from generate_series(4, 7) i
    );
    insert into public.content_reports as r
      (ref, created_at, source, locale, category, location, reason, reporter_name,
       reporter_email, good_faith)
    values (v_ref, p_now, 'web', p_locale, p_category, btrim(p_location), btrim(p_reason),
            nullif(btrim(p_name), ''), v_email, true)
    on conflict (ref) do nothing
    returning r.id into v_id;
    exit when v_id is not null;
  end loop;

  return query select v_id, v_ref, v_email is not null;
end $$;

-- The confirmation went out; a report with an address and no confirmation_sent_at still owes one
-- (notify.ts --confirmations, Legal N-244). False when the report is gone or has no address.
create function public.content_report_confirmation_sent(p_id uuid, p_now timestamptz)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.content_reports r set confirmation_sent_at = p_now
  where r.id = p_id and r.reporter_email is not null;
  return found;
end $$;

-- Peter's decision on the report with this reference: logged, and the report closed at p_now (a
-- later decision moves it). Returns the decision's id, which notify.ts takes.
create function public.content_report_decide(
  p_ref text,
  p_outcome text,
  p_ground text,
  p_now timestamptz default now()
)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_report uuid;
  v_decision bigint;
begin
  update public.content_reports r set closed_at = p_now
  where r.ref = upper(btrim(p_ref))
  returning r.id into v_report;
  if v_report is null then
    raise exception 'no report with this reference' using errcode = 'P0002';
  end if;
  insert into public.content_report_decisions (report_id, decided_at, outcome, ground)
  values (v_report, p_now, p_outcome, btrim(p_ground))
  returning id into v_decision;
  return v_decision;
end $$;

-- The decision mail went out (scripts/moderation/notify.ts --send). False for an unknown decision.
create function public.content_report_notified(p_decision bigint, p_now timestamptz default now())
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.content_report_decisions d set notified_at = p_now where d.id = p_decision;
  return found;
end $$;

-- Retention (privacy policy §10): reports and their decisions go 12 months after the case closed,
-- unless Peter holds one with retain_until. Returns the reports removed.
create function public.purge_content_reports(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.content_reports r
  where r.closed_at < p_now - interval '12 months'
    and (r.retain_until is null or r.retain_until < p_now);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function public.content_report_submit(text, text, text, text, text, text, timestamptz, integer) from public, anon, authenticated;
revoke execute on function public.content_report_confirmation_sent(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.content_report_decide(text, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.content_report_notified(bigint, timestamptz) from public, anon, authenticated;
revoke execute on function public.purge_content_reports(timestamptz) from public, anon, authenticated;
grant execute on function public.content_report_submit(text, text, text, text, text, text, timestamptz, integer) to service_role;
grant execute on function public.content_report_confirmation_sent(uuid, timestamptz) to service_role;
grant execute on function public.content_report_decide(text, text, text, timestamptz) to service_role;
grant execute on function public.content_report_notified(bigint, timestamptz) to service_role;
grant execute on function public.purge_content_reports(timestamptz) to service_role;

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('purge-content-reports', '27 3 * * *', 'select public.purge_content_reports()');
