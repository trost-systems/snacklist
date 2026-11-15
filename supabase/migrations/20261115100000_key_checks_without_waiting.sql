-- Job 241 review 1: checking a key does not wait for the key's or the household's row.
--
-- authenticate_access_token and api_begin decide by reading, then write last_used_at only if the
-- key's row is free right now (skip locked). "Zuletzt benutzt" may miss a request that came while
-- the row was busy; the next one writes it. A revoke counts from the moment it is committed, as
-- before.
--
-- The rows api_begin and integration_gate write reference the key or the household. Each call
-- first asks for the referenced rows' share locks without waiting, so a key or household that is
-- being deleted ends the call at once (lock_not_available, the functions' 503) instead of holding
-- it until the delete is through. With those locks the rows the two write are only ever held by
-- another such call; should one wait for a lock all the same, it ends after two seconds.
--
-- purchase_take_call, alexa_take_adds and alexa_remember write rows that reference the user. They
-- ask for the user's share lock the same way: an account that is being deleted ends them at once.
--
-- create_api_token counts a user's keys one call at a time: the cap of ten holds for calls that
-- arrive together.

create or replace function public.authenticate_access_token(p_token_hash text)
returns table (user_id uuid, household_id uuid, kind text)
language plpgsql security definer set search_path = '' as $$
declare
  v_key record;
begin
  select t.id, t.user_id, m.household_id, t.kind into v_key
  from public.personal_access_tokens t
  join public.household_members m on m.user_id = t.user_id
    and case when t.kind = 'siri' then m.is_default else m.household_id = t.household_id end
  where t.token_hash = p_token_hash
    and t.revoked_at is null
    and (t.kind = 'pat' or exists (
      select from auth.sessions s
      where s.id = t.session_id and s.user_id = t.user_id
        and (s.not_after is null or s.not_after > now())
    ));
  if not found then
    return;
  end if;
  update public.personal_access_tokens t set last_used_at = now()
  where t.id in (
    select f.id from public.personal_access_tokens f where f.id = v_key.id
    for no key update skip locked
  );
  return query select v_key.user_id, v_key.household_id, v_key.kind;
end $$;

-- As 20261102200000_public_api_switch.sql, but for the two share locks and last_used_at.
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
begin
  if not public.app_switch('public_api') then
    return query select 'disabled', null::uuid, null::uuid, null::uuid, null::text[], 0, 0, 0, null::integer;
    return;
  end if;

  select t.id, t.user_id, t.household_id, t.scopes into v_key
  from public.personal_access_tokens t
  join public.household_members m on m.user_id = t.user_id and m.household_id = t.household_id
  where t.token_hash = p_token_hash and t.kind = 'api' and t.revoked_at is null;

  if not found then
    select f.window_start, f.failures into v_fail_start, v_failures
    from public.api_auth_failures f
    where f.ip_hash = p_ip_hash and f.window_start > v_now - v_window;
    -- No key, or one we know that ended (revoked, its creator left, an MCP or Siri token): a client
    -- nobody updated, not a guess. It costs the address nothing, so an integration polling with a
    -- revoked key never blocks others behind the same address.
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
    values (p_ip_hash, v_now, 1)
    on conflict (ip_hash) do update set
      window_start = case when f.window_start <= v_now - v_window then v_now else f.window_start end,
      failures = case when f.window_start <= v_now - v_window then 1 else f.failures + 1 end
    returning f.window_start, f.failures into v_fail_start, v_failures;
    return query select 'invalid', null::uuid, null::uuid, null::uuid, null::text[], p_failures,
      greatest(p_failures - v_failures, 0),
      ceil(extract(epoch from v_fail_start + v_window - v_now))::integer, null::integer;
    return;
  end if;

  -- The key's and the household's share locks, without waiting (see the head of this file).
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

  insert into public.api_household_days (household_id, day, requests)
  values (v_key.household_id, v_day, 0)
  on conflict on constraint api_household_days_pkey do nothing;
  select d.requests into v_requests
  from public.api_household_days d
  where d.household_id = v_key.household_id and d.day = v_day for update;

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
  update public.api_household_days d set requests = v_requests
  where d.household_id = v_key.household_id and d.day = v_day;
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

-- As 20261113034530_siri_free.sql, but for the household's share lock.
create or replace function public.integration_gate(p_household uuid, p_integration text, p_user uuid)
returns table (locked boolean, report boolean)
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
begin
  if p_integration not in ('siri', 'alexa', 'mcp', 'api') then
    raise exception 'unknown integration %', p_integration using errcode = '22023';
  end if;
  if p_integration in ('siri', 'alexa')
    or not public.app_switch('integration_lock')
    or public.household_has_premium(p_household)
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

-- As 20261108125048_households_multi.sql, but for the lock before the count.
create or replace function public.create_api_token(p_name text, p_scopes text[], p_household uuid)
returns table (id uuid, name text, token text, scopes text[])
language plpgsql security definer set search_path = '' as $$
declare
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_household uuid;
  v_scopes text[];
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.app_switch('public_api') then
    raise exception 'api_disabled' using errcode = '42501',
      hint = 'The public API is switched off on this server (app_switches.public_api).';
  end if;
  if v_claims ? 'client_id' or nullif(v_claims ->> 'session_id', '') is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  v_household := public.token_household(p_household);
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  select array_agg(distinct s order by s) into v_scopes from unnest(p_scopes) s;
  if v_scopes is null or v_scopes not in ('{read}'::text[], '{read,write}'::text[]) then
    raise exception 'invalid_scopes' using errcode = '22023';
  end if;
  -- One call at a time for a user: the count holds for calls that arrive together.
  perform pg_advisory_xact_lock(hashtextextended('api_keys:' || auth.uid()::text, 0));
  if (select count(*) from public.personal_access_tokens t
      where t.user_id = auth.uid() and t.revoked_at is null and t.kind = 'api') >= 10 then
    raise exception 'too_many_tokens' using errcode = 'P0001';
  end if;
  -- 32 random bytes, base64url without padding: 43 characters after the prefix.
  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  return query
  insert into public.personal_access_tokens as t
    (household_id, user_id, name, token_hash, token_hint, kind, scopes)
  values (
    v_household,
    auth.uid(),
    coalesce(nullif(btrim(p_name), ''), 'API'),
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4),
    'api',
    v_scopes
  )
  returning t.id, t.name, v_token, t.scopes;
end $$;

-- As 20261030190000_purchases.sql, but for the user's share lock.
create or replace function public.purchase_take_call(p_user uuid, p_limit integer default 20) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_start timestamptz;
  v_calls integer;
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  insert into public.purchase_rate (user_id, window_start, calls)
  values (p_user, now(), 0)
  on conflict (user_id) do nothing;
  select r.window_start, r.calls into v_start, v_calls
  from public.purchase_rate r where r.user_id = p_user for update;
  if v_start <= now() - interval '1 minute' then
    v_start := now();
    v_calls := 0;
  end if;
  if v_calls + 1 > p_limit then
    update public.purchase_rate set window_start = v_start, calls = v_calls where user_id = p_user;
    return false;
  end if;
  update public.purchase_rate set window_start = v_start, calls = v_calls + 1 where user_id = p_user;
  return true;
end $$;

-- As 20261030140000_alexa.sql, but for the user's share lock.
create or replace function public.alexa_take_adds(p_user uuid, p_count integer, p_limit integer default 30)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_start timestamptz;
  v_adds integer;
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  insert into public.alexa_rate (user_id, window_start, adds)
  values (p_user, now(), 0)
  on conflict (user_id) do nothing;
  select window_start, adds into v_start, v_adds
  from public.alexa_rate where user_id = p_user for update;
  if v_start <= now() - interval '1 minute' then
    v_start := now();
    v_adds := 0;
  end if;
  if v_adds + p_count > p_limit then
    update public.alexa_rate set window_start = v_start, adds = v_adds where user_id = p_user;
    return false;
  end if;
  update public.alexa_rate set window_start = v_start, adds = v_adds + p_count
  where user_id = p_user;
  return true;
end $$;

-- As 20261102093000_alexa_cleanup.sql, but for the user's share lock.
create or replace function public.alexa_remember(
  p_hash text,
  p_user uuid,
  p_session uuid,
  p_relinked boolean default false
) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  insert into public.alexa_links (alexa_user_hash, session_id, user_id)
  values (p_hash, p_session, p_user)
  on conflict (alexa_user_hash, session_id) do update
    set user_id = excluded.user_id, last_seen = now();
  if p_relinked then
    return public.alexa_revoke(p_hash, p_session);
  end if;
  return 0;
end $$;
