-- Job 281: reports from the app (RC2, flag report-content-entry). The app posts to the report
-- edge function's /report/app route with its own session token; the function stores here through
-- content_report_submit_app and mails the same confirmation as for the web. A report names what it
-- is about (target_kind, target_id: the household, list or item the reporter picked, or elsewhere)
-- and may carry one screenshot the reporter attached and covered. Still no household_id and no
-- user: a report belongs to no household and is never shown to one. The reporter's user id is kept
-- only in content_report_app_senders, for the per-user hourly limit, and for at most a day; its
-- time equals the report's, so for that day the two can be matched. A report about child sexual
-- abuse material writes no sender row.

alter table public.content_reports drop constraint content_reports_source_check;
-- squawk-ignore constraint-missing-not-valid -- widens the check: every row passes
alter table public.content_reports add constraint content_reports_source_check
  check (source in ('web', 'app'));

alter table public.content_reports
  add column target_kind text check (target_kind in ('household', 'list', 'item', 'elsewhere')),
  add column target_id uuid;
-- Web reports name their place in words only; an app report always names a kind, and an id
-- exactly when it picked a household, list or item.
-- squawk-ignore constraint-missing-not-valid -- every existing row is a web row without a target
alter table public.content_reports add constraint content_reports_target check (
  case source
    when 'web' then target_kind is null and target_id is null
    else target_kind is not null and (target_id is not null) = (target_kind <> 'elsewhere')
  end);

comment on column public.content_reports.target_id is
  'App reports: the id of the household, list or item picked (target_kind). Not a foreign key: the content may be gone by the time Peter looks.';

-- The screenshot an app report attached (a PNG, the reporter covered what has nothing to do with
-- the report). Goes with its report: the purge's delete cascades.
create table public.content_report_screenshots (
  report_id uuid primary key references public.content_reports (id) on delete cascade,
  png bytea not null check (octet_length(png) between 8 and 2097152)
);

comment on table public.content_report_screenshots is
  'Job 281: the screenshot of an app report, if one was attached. Only Peter reads it (docs/MODERATION.md). Service connection only.';

alter table public.content_report_screenshots enable row level security;
revoke all on public.content_report_screenshots from public, anon, authenticated;

-- Who sent an app report when, for the per-user limit only. No foreign key to auth.users: its
-- key-share lock would deadlock delete_account. Rows older than an hour serve no limit and go
-- at every app submit and daily, so a user id stays at most a day after its last report.
create table public.content_report_app_senders (
  user_id uuid not null,
  at timestamptz not null
);

comment on table public.content_report_app_senders is
  'Job 281: one row per app report (user, time) for the hourly per-user limit; pruned after an hour, daily at the latest. Service connection only.';

create index content_report_app_senders_user_at on public.content_report_app_senders (user_id, at);

alter table public.content_report_app_senders enable row level security;
revoke all on public.content_report_app_senders from public, anon, authenticated;

-- One app report, under content_report_submit's table lock, so both counts are exact. Nothing is
-- stored when p_max_per_hour app reports came in the hour before p_now (refused 'global') or this
-- user sent p_max_per_user_hour (refused 'user'): then the one row has only refused set. Otherwise
-- the trimmed report with a new reference and its screenshot; confirm is true when an address was
-- given: every app report with one gets the confirmation (Legal N-241, no per-address cap).
create function public.content_report_submit_app(
  p_user uuid,
  p_locale text,
  p_category text,
  p_target_kind text,
  p_target_id uuid,
  p_location text,
  p_reason text,
  p_name text,
  p_email text,
  p_screenshot bytea,
  p_now timestamptz,
  p_max_per_user_hour integer,
  p_max_per_hour integer
)
returns table (id uuid, ref text, confirm boolean, refused text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_email text := nullif(btrim(p_email), '');
  v_bytes bytea;
  v_ref text;
  v_id uuid;
begin
  lock table public.content_reports in share row exclusive mode;
  delete from public.content_report_app_senders s where s.at <= p_now - interval '1 hour';
  if (select count(*) from public.content_reports r
      where r.source = 'app' and r.created_at > p_now - interval '1 hour') >= p_max_per_hour then
    return query select null::uuid, null::text, false, 'global';
    return;
  end if;
  -- A report about child sexual abuse material may be anonymous (N-228): it neither counts
  -- toward nor leaves a sender row, so nothing ties it to the account. The overall cap holds it.
  if p_category <> 'csam' and (select count(*) from public.content_report_app_senders s
      where s.user_id = p_user and s.at > p_now - interval '1 hour') >= p_max_per_user_hour then
    return query select null::uuid, null::text, false, 'user';
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
       reporter_email, good_faith, target_kind, target_id)
    values (v_ref, p_now, 'app', p_locale, p_category, btrim(p_location), btrim(p_reason),
            nullif(btrim(p_name), ''), v_email, true, p_target_kind, p_target_id)
    on conflict (ref) do nothing
    returning r.id into v_id;
    exit when v_id is not null;
  end loop;

  if p_screenshot is not null then
    insert into public.content_report_screenshots (report_id, png) values (v_id, p_screenshot);
  end if;
  if p_category <> 'csam' then
    insert into public.content_report_app_senders (user_id, at) values (p_user, p_now);
  end if;

  return query select v_id, v_ref, v_email is not null, null::text;
end $$;

-- The daily prune of content_report_app_senders, for users who stop sending. Returns the rows
-- removed.
create function public.prune_content_report_app_senders(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.content_report_app_senders s where s.at <= p_now - interval '1 hour';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function public.content_report_submit_app(uuid, text, text, text, uuid, text, text, text, text, bytea, timestamptz, integer, integer) from public, anon, authenticated;
revoke execute on function public.prune_content_report_app_senders(timestamptz) from public, anon, authenticated;
grant execute on function public.content_report_submit_app(uuid, text, text, text, uuid, text, text, text, text, bytea, timestamptz, integer, integer) to service_role;
grant execute on function public.prune_content_report_app_senders(timestamptz) to service_role;

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('prune-content-report-app-senders', '20 2 * * *',
  'select public.prune_content_report_app_senders()');
