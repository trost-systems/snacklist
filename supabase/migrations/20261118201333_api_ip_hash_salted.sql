-- Legal Review N-255 (17 Nov 2026): the failed-key count per address is keyed by a salted hash.
--
-- The api function sends the SHA-256 of X-Real-IP. Unsalted, that hash of an IPv4 address can be
-- reversed by trying all 2^32 addresses, so api_auth_failures stores SHA-256(salt || that hash)
-- with the secret the invite preview already salts its client keys with: made in the database,
-- never in the repo, readable by no client. Rows keyed by the old unsalted hash simply stop
-- matching and go with the daily purge.

comment on table public.invite_preview_salt is
  'Job 169b: the secret that salts invite_preview_rate''s keys and (N-255) api_auth_failures'' address keys; generated in the database. No client access.';

comment on table public.api_auth_failures is
  'Job 73: failed API authentications per address (salted SHA-256 of the IP, never the IP; N-255) in the current window. Service connection only.';

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

  select t.id, t.user_id, t.household_id, t.scopes into v_key
  from public.personal_access_tokens t
  join public.household_members m on m.user_id = t.user_id and m.household_id = t.household_id
  where t.token_hash = p_token_hash and t.kind = 'api' and t.revoked_at is null;

  if not found then
    v_ip_key := encode(extensions.digest(
      (select s.salt from public.invite_preview_salt s) || convert_to(p_ip_hash, 'UTF8'), 'sha256'), 'hex');
    select f.window_start, f.failures into v_fail_start, v_failures
    from public.api_auth_failures f
    where f.ip_hash = v_ip_key and f.window_start > v_now - v_window;
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
