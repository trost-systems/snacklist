-- Job 82: the hummlist.com waitlist (docs/WAITLIST.md). Double opt-in sign-ups, their proof of
-- consent once they end, and the sign-up rate counters. Only the service connection (the waitlist
-- edge function and scripts/waitlist/invite.ts) reaches them, through the functions below; anon
-- and authenticated have no privilege on any of it.
--
-- A row's lifecycle, read from its columns:
--   unconfirmed  confirm_token_hash set, confirmed_at null (purged after 7 days, no proof)
--   confirmed    confirmed_at set, the token gone
--   invited      invite_sent_at set as well
--   ended        the row is deleted; a confirmed one leaves a waitlist_consent_proof row

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null check (char_length(email) between 3 and 254 and email = btrim(email)),
  email_hmac text not null check (email_hmac ~ '^[0-9a-f]{64}$'),
  platform text not null check (platform in ('ios', 'android')),
  locale text not null check (locale in ('de', 'en')),
  launch_news boolean not null default false,
  consent_text_version text not null check (consent_text_version ~ '^waitlist-(de|en)-v[0-9]+$'),
  created_at timestamptz not null default now(),
  confirm_token_hash text check (confirm_token_hash ~ '^[0-9a-f]{64}$'),
  confirm_expires_at timestamptz,
  confirmed_at timestamptz,
  invite_sent_at timestamptz,
  launch_mail_sent_at timestamptz,
  last_mail_at timestamptz,
  constraint waitlist_token_until_confirmed check (
    (confirmed_at is null) = (confirm_token_hash is not null)
    and (confirm_token_hash is null) = (confirm_expires_at is null)
  ),
  constraint waitlist_invite_after_confirm check (invite_sent_at is null or confirmed_at is not null),
  constraint waitlist_launch_mail_needs_consent check (
    launch_mail_sent_at is null or (confirmed_at is not null and launch_news)
  )
);

comment on table public.waitlist is
  'Job 82: hummlist.com waitlist sign-ups, one per address (double opt-in). No agent reads rows. Service connection only.';

create unique index waitlist_email_key on public.waitlist (lower(email));
create unique index waitlist_confirm_token_key on public.waitlist (confirm_token_hash);
create index waitlist_confirmed_at on public.waitlist (confirmed_at);

alter table public.waitlist enable row level security;
revoke all on public.waitlist from public, anon, authenticated;

create table public.waitlist_consent_proof (
  id bigint generated always as identity primary key,
  email_hmac text not null check (email_hmac ~ '^[0-9a-f]{64}$'),
  consent_text_version text not null,
  locale text not null check (locale in ('de', 'en')),
  launch_news boolean not null,
  created_at timestamptz not null,
  confirmed_at timestamptz not null,
  last_mail_at timestamptz,
  ended_at timestamptz not null,
  end_reason text not null check (end_reason in ('unsubscribed', 'deletion_request', 'purpose_done'))
);

comment on table public.waitlist_consent_proof is
  'Job 82: proof of consent for a confirmed waitlist sign-up that ended (HMAC of the address, never the address), kept 3 years. Never used for sending. Service connection only.';

alter table public.waitlist_consent_proof enable row level security;
revoke all on public.waitlist_consent_proof from public, anon, authenticated;

create table public.waitlist_rate (
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$' or key_hash = 'all'),
  window_start timestamptz not null,
  hits integer not null check (hits >= 0),
  primary key (key_hash, window_start)
);

comment on table public.waitlist_rate is
  'Job 82: waitlist sign-ups per hashed client key (and ''all'') per hour; purged after 2 hours. Service connection only.';

alter table public.waitlist_rate enable row level security;
revoke all on public.waitlist_rate from public, anon, authenticated;

-- Ends rows: a confirmed one first leaves its proof record. Internal to the functions below.
create function public.waitlist_end(p_ids uuid[], p_reason text, p_now timestamptz)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  with gone as (
    delete from public.waitlist w where w.id = any(p_ids) returning w.*
  ), proof as (
    insert into public.waitlist_consent_proof
      (email_hmac, consent_text_version, locale, launch_news, created_at, confirmed_at,
       last_mail_at, ended_at, end_reason)
    select g.email_hmac, g.consent_text_version, g.locale, g.launch_news, g.created_at,
           g.confirmed_at, g.last_mail_at, p_now, p_reason
    from gone g where g.confirmed_at is not null
  )
  select count(*) into v_count from gone;
  return v_count;
end $$;

-- One sign-up. A new address is stored with the token; a known unconfirmed one whose last mail is
-- 24 h old or older takes the new answers and token. Either way the row comes back and the caller
-- mails the confirmation to its email; last_mail_at already says so, so a concurrent duplicate
-- gets no row. A known confirmed address, or one mailed less than 24 h ago, changes nothing and
-- returns no row.
create function public.waitlist_signup(
  p_email text,
  p_email_hmac text,
  p_platform text,
  p_locale text,
  p_launch_news boolean,
  p_consent_version text,
  p_token_hash text,
  p_now timestamptz
)
returns table (id uuid, email text, locale text, launch_news boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
  insert into public.waitlist as w
    (email, email_hmac, platform, locale, launch_news, consent_text_version, created_at,
     confirm_token_hash, confirm_expires_at, last_mail_at)
  values (btrim(p_email), p_email_hmac, p_platform, p_locale, p_launch_news, p_consent_version,
          p_now, p_token_hash, p_now + interval '48 hours', p_now)
  on conflict ((lower(email))) do nothing
  returning w.id, w.email, w.locale, w.launch_news;
  if found then return; end if;

  return query
  update public.waitlist w set
    platform = p_platform,
    locale = p_locale,
    launch_news = p_launch_news,
    consent_text_version = p_consent_version,
    confirm_token_hash = p_token_hash,
    confirm_expires_at = p_now + interval '48 hours',
    last_mail_at = p_now
  where lower(w.email) = lower(btrim(p_email))
    and w.confirmed_at is null
    and w.last_mail_at <= p_now - interval '24 hours'
  returning w.id, w.email, w.locale, w.launch_news;
end $$;

-- Confirms the row with this token if it is unexpired: the token is gone after, so a second
-- press finds nothing. Returns what the welcome mail needs, or no row.
create function public.waitlist_confirm(p_token_hash text, p_now timestamptz)
returns table (id uuid, email text, locale text, launch_news boolean)
language sql security definer set search_path = '' as $$
  update public.waitlist w set
    confirmed_at = p_now,
    confirm_token_hash = null,
    confirm_expires_at = null
  where w.confirm_token_hash = p_token_hash and w.confirm_expires_at > p_now
  returning w.id, w.email, w.locale, w.launch_news;
$$;

-- A mail went out to the row: welcome after confirming, invite from scripts/waitlist/invite.ts.
-- An invite also sets invite_sent_at (once). False when the row is gone or not confirmed.
create function public.waitlist_mailed(p_id uuid, p_kind text, p_now timestamptz)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if p_kind not in ('welcome', 'invite') then
    raise exception 'unknown mail kind' using errcode = '22023';
  end if;
  update public.waitlist w set
    last_mail_at = p_now,
    invite_sent_at = case when p_kind = 'invite' then coalesce(w.invite_sent_at, p_now)
                          else w.invite_sent_at end
  where w.id = p_id and w.confirmed_at is not null;
  return found;
end $$;

-- The unsubscribe link (its signature checked by the caller): deletes the row at once.
create function public.waitlist_unsubscribe(p_id uuid, p_now timestamptz)
returns boolean
language sql security definer set search_path = '' as $$
  select public.waitlist_end(array[p_id], 'unsubscribed', p_now) > 0;
$$;

-- Counts one sign-up request for the client key and for everyone in the current hour; false when
-- either is over its limit.
create function public.waitlist_rate_hit(
  p_key_hash text,
  p_now timestamptz,
  p_per_key integer,
  p_total integer
)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_window timestamptz := date_trunc('hour', p_now);
  v_key integer;
  v_all integer;
begin
  -- Counters go 2 hours after their window here, not only in the daily purge, so none is kept
  -- for a day (Legal: at most 24 h).
  delete from public.waitlist_rate r where r.window_start < p_now - interval '2 hours';
  insert into public.waitlist_rate as r (key_hash, window_start, hits)
  values (p_key_hash, v_window, 1)
  on conflict (key_hash, window_start) do update set hits = r.hits + 1
  returning r.hits into v_key;
  insert into public.waitlist_rate as r (key_hash, window_start, hits)
  values ('all', v_window, 1)
  on conflict (key_hash, window_start) do update set hits = r.hits + 1
  returning r.hits into v_all;
  return v_key <= p_per_key and v_all <= p_total;
end $$;

-- A batch is the ISO week of confirmed_at in Europe/Berlin, written 2026-W47.
create function public.waitlist_batch_window(p_batch text)
returns tstzrange
language plpgsql stable set search_path = '' as $$
declare
  v_monday date;
begin
  if p_batch !~ '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$' then
    raise exception 'batch must look like 2026-W47' using errcode = '22023';
  end if;
  v_monday := to_date(left(p_batch, 4) || '-' || right(p_batch, 2) || '-1', 'IYYY-IW-ID');
  if to_char(v_monday, 'IYYY-"W"IW') <> p_batch then
    raise exception 'no such ISO week' using errcode = '22023';
  end if;
  return tstzrange(v_monday::timestamp at time zone 'Europe/Berlin',
                   (v_monday + 7)::timestamp at time zone 'Europe/Berlin', '[)');
end $$;

-- The invite script's dry run: counts only, per platform and locale, never an address.
create function public.waitlist_batch_counts(p_batch text)
returns table (platform text, locale text, confirmed integer, invited integer, to_invite integer)
language sql stable security definer set search_path = '' as $$
  select w.platform, w.locale, count(*)::integer,
         count(w.invite_sent_at)::integer,
         (count(*) - count(w.invite_sent_at))::integer
  from public.waitlist w
  where w.confirmed_at <@ public.waitlist_batch_window(p_batch)
  group by w.platform, w.locale
  order by w.platform, w.locale;
$$;

-- The batch's uninvited rows, with addresses: only scripts/waitlist/invite.ts --confirm reads it.
create function public.waitlist_batch_rows(p_batch text)
returns table (id uuid, email text, platform text, locale text)
language sql stable security definer set search_path = '' as $$
  select w.id, w.email, w.platform, w.locale
  from public.waitlist w
  where w.confirmed_at <@ public.waitlist_batch_window(p_batch) and w.invite_sent_at is null
  order by w.confirmed_at, w.id;
$$;

-- The retention rules (Legal handoff §3, docs/WAITLIST.md "Purge"); returns the rows removed.
create function public.purge_waitlist(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_total integer;
  v_count integer;
begin
  delete from public.waitlist w
  where w.confirmed_at is null and w.created_at < p_now - interval '7 days';
  get diagnostics v_total = row_count;

  v_total := v_total + public.waitlist_end(array(
    select w.id from public.waitlist w
    where w.confirmed_at is not null and (
      p_now >= timestamptz '2027-12-31 00:00 Europe/Berlin'
      or (not w.launch_news and w.invite_sent_at < p_now - interval '3 months')
      or (w.launch_news and w.launch_mail_sent_at < p_now - interval '30 days')
    )
  ), 'purpose_done', p_now);

  -- After the end date nothing may stay, confirmed or not.
  if p_now >= timestamptz '2027-12-31 00:00 Europe/Berlin' then
    delete from public.waitlist;
    get diagnostics v_count = row_count;
    v_total := v_total + v_count;
  end if;

  delete from public.waitlist_consent_proof p
  where greatest(p.last_mail_at, p.ended_at) < p_now - interval '3 years';
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  delete from public.waitlist_rate r where r.window_start < p_now - interval '2 hours';
  get diagnostics v_count = row_count;
  return v_total + v_count;
end $$;

revoke execute on function public.waitlist_end(uuid[], text, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_signup(text, text, text, text, boolean, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_confirm(text, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_mailed(uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_unsubscribe(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_rate_hit(text, timestamptz, integer, integer) from public, anon, authenticated;
revoke execute on function public.waitlist_batch_window(text) from public, anon, authenticated;
revoke execute on function public.waitlist_batch_counts(text) from public, anon, authenticated;
revoke execute on function public.waitlist_batch_rows(text) from public, anon, authenticated;
revoke execute on function public.purge_waitlist(timestamptz) from public, anon, authenticated;
grant execute on function public.waitlist_signup(text, text, text, text, boolean, text, text, timestamptz) to service_role;
grant execute on function public.waitlist_confirm(text, timestamptz) to service_role;
grant execute on function public.waitlist_mailed(uuid, text, timestamptz) to service_role;
grant execute on function public.waitlist_unsubscribe(uuid, timestamptz) to service_role;
grant execute on function public.waitlist_rate_hit(text, timestamptz, integer, integer) to service_role;
grant execute on function public.waitlist_batch_counts(text) to service_role;
grant execute on function public.waitlist_batch_rows(text) to service_role;
grant execute on function public.purge_waitlist(timestamptz) to service_role;

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('purge-waitlist', '23 3 * * *', 'select public.purge_waitlist(now())');
