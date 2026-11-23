-- Job 419 (Legal L23-2 MUST 1 and 2): one daily cap per user account, and the integration gate
-- opens only for the caller's own Premium.
--
-- MUST 1. Requests per UTC day were counted per household for the API (api_household_days) and per
-- user for MCP (mcp_rate.day/requests). Now one counter per user and day, account_days, is taken
-- by api_begin (one API request = one) and mcp_take_call (one MCP request = one), whichever
-- household or key a call names, so 1,000 a day are shared across MCP and the API. The per-minute
-- bucket and the burst stay as they were (per API key, and per user for MCP).
-- api_household_days is left in place, unused and empty of new writes (squawk: no drops while old
-- function deploys may run); a later migration may drop it. mcp_rate.day/requests are unused too.
--
-- MUST 2. integration_gate no longer opens for household_has_premium(p_household): a plan another
-- member or the household's own entitlement holds does not unlock MCP or the API for the caller.
-- Promotional and tester access is a per-user RevenueCat grant (user_entitlements).

create table public.account_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  requests integer not null check (requests >= 0),
  constraint account_days_pkey primary key (user_id, day)
);

comment on table public.account_days is
  'Job 419: requests per user account and UTC day over MCP and the API together (api_begin, mcp_take_call). Service connection only. Days before yesterday go daily (purge_mcp_rate).';

alter table public.account_days enable row level security;
revoke all on public.account_days from public, anon, authenticated;

comment on table public.api_household_days is
  'Job 73, unused since job 419: the API counted per household; account_days counts per user now. Kept so older function deploys keep working.';

-- As 20261122230000_unified_keys.sql, but the day's count is the user's (account_days).
create or replace function public.api_begin(
  p_token_hash text,
  p_ip_hash text,
  p_burst integer,
  p_per_minute integer,
  p_per_day integer,
  p_failures integer,
  p_failure_window integer
)
returns table (
  outcome text,
  token_id uuid,
  user_id uuid,
  household_id uuid,
  scopes text[],
  rate_limit integer,
  rate_remaining integer,
  rate_reset integer,
  retry_after integer
)
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
declare
  v_now timestamptz := now();
  v_window interval := make_interval(secs => p_failure_window);
  v_rate double precision := p_per_minute / 60.0;
  v_day date := (v_now at time zone 'utc')::date;
  v_day_reset integer := ceil(extract(epoch from ((v_day + 1)::timestamp at time zone 'utc') - v_now))::integer;
  v_fail_start timestamptz;
  v_failures integer;
  v_key record;
  v_tokens double precision;
  v_requests integer;
  v_bucket_reset integer;
  v_ip_key text;
begin
  if not public.app_switch('public_api') then
    return query select 'disabled', null::uuid, null::uuid, null::uuid, null::text[], 0, 0, 0, null::integer;
    return;
  end if;

  select t.id, t.user_id, t.household_id,
    case when t.kind = 'pat' then '{read,write}'::text[] else t.scopes end as scopes into v_key
  from public.personal_access_tokens t
  join public.household_members m on m.user_id = t.user_id and m.household_id = t.household_id
  where t.token_hash = p_token_hash and t.revoked_at is null
    and (t.kind = 'api' or (t.kind = 'pat' and public.app_switch('unified_keys')));

  if not found then
    v_ip_key := encode(extensions.digest(
      (select s.salt from public.invite_preview_salt s) || convert_to(p_ip_hash, 'UTF8'), 'sha256'), 'hex');
    select f.window_start, f.failures into v_fail_start, v_failures
    from public.api_auth_failures f
    where f.ip_hash = v_ip_key and f.window_start > v_now - v_window;
    -- No key, or one we know that ended (revoked, its creator left, a Siri credential, an MCP
    -- token while unified_keys is off): a client nobody updated, not a guess. It costs the address
    -- nothing, so an integration polling with a revoked key never blocks others behind the same
    -- address.
    if p_token_hash is null or p_ip_hash is null or exists (
      select from public.personal_access_tokens t where t.token_hash = p_token_hash
    ) then
      return query select 'invalid', null::uuid, null::uuid, null::uuid, null::text[], p_failures,
        greatest(p_failures - coalesce(v_failures, 0), 0),
        coalesce(ceil(extract(epoch from v_fail_start + v_window - v_now))::integer, 0), null::integer;
      return;
    end if;
    if v_failures >= p_failures then
      return query select 'blocked', null::uuid, null::uuid, null::uuid, null::text[], p_failures, 0,
        ceil(extract(epoch from v_fail_start + v_window - v_now))::integer,
        ceil(extract(epoch from v_fail_start + v_window - v_now))::integer;
      return;
    end if;
    -- Ended windows go as new failures come, a hundred at a time, so the table holds about the
    -- addresses that failed in the last window whatever the rate (the daily purge sweeps the rest).
    delete from public.api_auth_failures f where f.ctid in (
      select g.ctid from public.api_auth_failures g where g.window_start <= v_now - v_window limit 100
    );
    insert into public.api_auth_failures as f (ip_hash, window_start, failures)
    values (v_ip_key, v_now, 1)
    on conflict (ip_hash) do update set
      window_start = case when f.window_start <= v_now - v_window then v_now else f.window_start end,
      failures = case when f.window_start <= v_now - v_window then 1 else f.failures + 1 end
    returning f.window_start, f.failures into v_fail_start, v_failures;
    return query select 'invalid', null::uuid, null::uuid, null::uuid, null::text[], p_failures,
      greatest(p_failures - v_failures, 0),
      ceil(extract(epoch from v_fail_start + v_window - v_now))::integer, null::integer;
    return;
  end if;

  -- The key's and the household's share locks, without waiting (20261115100000).
  perform from public.personal_access_tokens t where t.id = v_key.id for key share nowait;
  perform from public.households h where h.id = v_key.household_id for key share nowait;

  -- Always the bucket first, then the day: concurrent requests lock in one order.
  insert into public.api_token_buckets (token_id, tokens, refilled_at)
  values (v_key.id, p_burst, v_now)
  on conflict on constraint api_token_buckets_pkey do nothing;
  select least(p_burst::double precision,
               b.tokens + greatest(extract(epoch from v_now - b.refilled_at), 0) * v_rate)
  into v_tokens
  from public.api_token_buckets b where b.token_id = v_key.id for update;

  insert into public.account_days (user_id, day, requests)
  values (v_key.user_id, v_day, 0)
  on conflict on constraint account_days_pkey do nothing;
  select d.requests into v_requests
  from public.account_days d
  where d.user_id = v_key.user_id and d.day = v_day for update;

  if v_tokens < 1 or v_requests >= p_per_day then
    update public.api_token_buckets b set tokens = v_tokens, refilled_at = v_now
    where b.token_id = v_key.id;
    return query select 'limited', v_key.id, v_key.user_id, v_key.household_id, v_key.scopes,
      case when v_requests >= p_per_day then p_per_day else p_burst end,
      0,
      case when v_requests >= p_per_day then v_day_reset
        else ceil((p_burst - v_tokens) / v_rate)::integer end,
      greatest(
        case when v_tokens < 1 then ceil((1 - v_tokens) / v_rate)::integer else 0 end,
        case when v_requests >= p_per_day then v_day_reset else 0 end
      );
    return;
  end if;

  v_tokens := v_tokens - 1;
  v_requests := v_requests + 1;
  update public.api_token_buckets b set tokens = v_tokens, refilled_at = v_now
  where b.token_id = v_key.id;
  update public.account_days d set requests = v_requests
  where d.user_id = v_key.user_id and d.day = v_day;
  update public.personal_access_tokens t set last_used_at = v_now
  where t.id in (
    select f.id from public.personal_access_tokens f where f.id = v_key.id
    for no key update skip locked
  );

  v_bucket_reset := ceil((p_burst - v_tokens) / v_rate)::integer;
  if floor(v_tokens) <= p_per_day - v_requests then
    return query select 'ok', v_key.id, v_key.user_id, v_key.household_id, v_key.scopes, p_burst,
      floor(v_tokens)::integer, v_bucket_reset, null::integer;
  else
    return query select 'ok', v_key.id, v_key.user_id, v_key.household_id, v_key.scopes, p_per_day,
      p_per_day - v_requests, v_day_reset, null::integer;
  end if;
end $$;


-- As 20261121120000_mcp_rate.sql, but the day's count is account_days', shared with the API.
create or replace function public.mcp_take_call(
  p_user uuid,
  p_burst integer,
  p_per_minute integer,
  p_per_day integer
)
returns integer
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
declare
  v_now timestamptz := now();
  v_rate double precision := p_per_minute / 60.0;
  v_day date := (v_now at time zone 'utc')::date;
  v_day_reset integer := ceil(extract(epoch from ((v_day + 1)::timestamp at time zone 'utc') - v_now))::integer;
  v_row record;
  v_tokens double precision;
  v_requests integer;
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  if not found then
    raise exception 'no such user' using errcode = 'P0002';
  end if;

  insert into public.mcp_rate (user_id, tokens, refilled_at, day, requests)
  values (p_user, p_burst, v_now, v_day, 0)
  on conflict (user_id) do nothing;
  select r.tokens, r.refilled_at into v_row
  from public.mcp_rate r where r.user_id = p_user for update;

  insert into public.account_days (user_id, day, requests)
  values (p_user, v_day, 0)
  on conflict on constraint account_days_pkey do nothing;
  select d.requests into v_requests
  from public.account_days d where d.user_id = p_user and d.day = v_day for update;

  v_tokens := least(p_burst::double precision,
                    v_row.tokens + greatest(extract(epoch from v_now - v_row.refilled_at), 0) * v_rate);

  if v_tokens >= 1 and v_requests < p_per_day then
    update public.mcp_rate r set tokens = v_tokens - 1, refilled_at = v_now where r.user_id = p_user;
    update public.account_days d set requests = v_requests + 1 where d.user_id = p_user and d.day = v_day;
    return null;
  end if;

  update public.mcp_rate r set tokens = v_tokens, refilled_at = v_now where r.user_id = p_user;
  return greatest(
    case when v_tokens < 1 then ceil((1 - v_tokens) / v_rate)::integer else 0 end,
    case when v_requests >= p_per_day then v_day_reset else 0 end
  );
end $$;

-- Job 419 (LEAD 20:40): MCP counts a tool call, not a request. The bucket still takes every
-- request; the day takes [p_calls] (the tools/call messages of the request, 0 for initialize,
-- tools/list, ping, notifications) and refuses all of them when the day cannot hold them, as
-- mcp_take_call refuses one. A refused request takes nothing from the day. mcp_take_call stays
-- for function deploys that still call it.
create function public.mcp_take(
  p_user uuid,
  p_burst integer,
  p_per_minute integer,
  p_per_day integer,
  p_calls integer
)
returns integer
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
declare
  v_now timestamptz := now();
  v_rate double precision := p_per_minute / 60.0;
  v_day date := (v_now at time zone 'utc')::date;
  v_day_reset integer := ceil(extract(epoch from ((v_day + 1)::timestamp at time zone 'utc') - v_now))::integer;
  v_row record;
  v_tokens double precision;
  v_requests integer := 0;
  v_day_full boolean := false;
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  if not found then
    raise exception 'no such user' using errcode = 'P0002';
  end if;

  insert into public.mcp_rate (user_id, tokens, refilled_at, day, requests)
  values (p_user, p_burst, v_now, v_day, 0)
  on conflict (user_id) do nothing;
  select r.tokens, r.refilled_at into v_row
  from public.mcp_rate r where r.user_id = p_user for update;

  if p_calls > 0 then
    insert into public.account_days (user_id, day, requests)
    values (p_user, v_day, 0)
    on conflict on constraint account_days_pkey do nothing;
    select d.requests into v_requests
    from public.account_days d where d.user_id = p_user and d.day = v_day for update;
    v_day_full := v_requests + p_calls > p_per_day;
  end if;

  v_tokens := least(p_burst::double precision,
                    v_row.tokens + greatest(extract(epoch from v_now - v_row.refilled_at), 0) * v_rate);

  if v_tokens >= 1 and not v_day_full then
    update public.mcp_rate r set tokens = v_tokens - 1, refilled_at = v_now where r.user_id = p_user;
    if p_calls > 0 then
      update public.account_days d set requests = v_requests + p_calls
      where d.user_id = p_user and d.day = v_day;
    end if;
    return null;
  end if;

  update public.mcp_rate r set tokens = v_tokens, refilled_at = v_now where r.user_id = p_user;
  return greatest(
    case when v_tokens < 1 then ceil((1 - v_tokens) / v_rate)::integer else 0 end,
    case when v_day_full then v_day_reset else 0 end
  );
end $$;

revoke execute on function public.mcp_take(uuid, integer, integer, integer, integer)
  from public, anon, authenticated;

-- Gives back [p_n] requests of today: a call the plan gate refused (402, the locked tool answer)
-- does not use up the day. Never below 0.
create function public.account_day_refund(p_user uuid, p_n integer default 1)
returns void
language sql security definer set search_path = '' as $$
  update public.account_days d set requests = greatest(d.requests - p_n, 0)
  where d.user_id = p_user and d.day = (now() at time zone 'utc')::date
$$;

revoke execute on function public.account_day_refund(uuid, integer)
  from public, anon, authenticated;

create or replace function public.purge_mcp_rate() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_total integer;
  v_count integer;
begin
  delete from public.mcp_rate r where r.refilled_at < now() - interval '1 day';
  get diagnostics v_total = row_count;
  delete from public.account_days d where d.day < (now() at time zone 'utc')::date - 1;
  get diagnostics v_count = row_count;
  return v_total + v_count;
end $$;

-- As 20261115100000_key_checks_without_waiting.sql, but only the caller's own Premium opens it.
create or replace function public.integration_gate(p_household uuid, p_integration text, p_user uuid)
returns table (locked boolean, report boolean)
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
begin
  if p_integration not in ('siri', 'alexa', 'mcp', 'api') then
    raise exception 'unknown integration %', p_integration using errcode = '22023';
  end if;
  if p_integration in ('siri', 'alexa')
    or not public.app_switch('integration_lock')
    or public.user_has_premium(p_user) then
    return query select false, false;
    return;
  end if;
  perform from public.households h where h.id = p_household for key share nowait;
  return query
    insert into public.integration_blocks as b (household_id, integration, reported_at)
    values (p_household, p_integration, now())
    on conflict (household_id, integration) do update set reported_at = now()
      where b.reported_at <= now() - interval '1 hour'
    returning true, true;
  if not found then
    return query select true, false;
  end if;
end $$;

-- Legal must-fix 17 (job 419, LEAD 20:45): the lock stays off until a lead decision. It is seeded
-- off and only the service role changes it; this note travels with the table.
comment on table public.app_switches is
  'Job 47: server-side switches, set by the service role only (NEEDS_LEAD "Job 47", "Job 49", "Job 50"). household_archive: archiving a household on the last leave is allowed. premium_offer (job 49): the app may offer Snacklist Premium for sale. integration_lock (job 50): MCP and the API (job 73) need the caller''s own Snacklist Premium (job 419); Siri (job 184) and Alexa (job 72) stay free. NEVER switch integration_lock on before the public launch and a lead decision: only after the Lifetime grant script ran (scripts/iap/beta-lifetime.ts) and the users accepted the new Terms in the app (Legal must-fix 7 and 17, docs/PAYWALL_RELEASE.md 6.4). public_api (job 75): the public API is served and API keys can be made.';
