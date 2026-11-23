-- Job 397 (AU1, docs/research/388-auth-unify-api-domain.md): one personal key for MCP and the
-- public API, scoped {read} or {read,write}, behind the server switch app_switches.unified_keys
-- (seeded off), so the deploy and the switch-on are separate steps.
--   * Every MCP token (kind 'pat') gets scopes {read,write}: what it can do today. A 'pat' row
--     without scopes (restored from an older backup) means the same. The kind stays for history;
--     the app makes new keys as 'api'.
--   * authenticate_key() is the functions' lookup from now on: it returns the key's scopes, and
--     with the switch on 'api' keys too, so MCP and Siri's Shortcut take them and check the scope.
--     authenticate_access_token and authenticate_personal_access_token stay as they were for
--     older function versions (a rollback): those check no scope, so they never return an 'api'
--     key, which may be read-only. A 'pat' key is always {read,write}.
--   * With the switch on, api_begin takes 'pat' keys, create_api_token no longer needs the
--     public_api switch (requests still do), and both create functions share one cap of 20 active
--     keys per member. create_personal_access_token stays for app builds that still call it.
-- Rate limits stay per surface: MCP counts per user (mcp_rate), the API per key and household.

insert into public.app_switches (key, enabled) values ('unified_keys', false);

comment on table public.app_switches is
  'Job 47: server-side switches, set by the service role only (NEEDS_LEAD "Job 47", "Job 49", "Job 50"). household_archive: archiving a household on the last leave is allowed. premium_offer (job 49): the app may offer Snacklist Premium for sale. integration_lock (job 50): MCP and the API (job 73) need Snacklist Premium; Siri (job 184) and Alexa (job 72) stay free. public_api (job 75): the public API is served and API keys can be made. feedback_digest (job 225): the daily feedback mail runs; set only through feedback_digest_set. mcp_lists_stores (job 345): the MCP tools create_list, rename_list, add_store, rename_store and set_store_layout are served. unified_keys (job 397): one personal key works on MCP and the API with its scopes, and keys can be made while public_api is off.';

alter table public.personal_access_tokens drop constraint personal_access_tokens_scopes_check;
update public.personal_access_tokens set scopes = '{read,write}' where kind = 'pat' and scopes is null;
alter table public.personal_access_tokens add constraint personal_access_tokens_scopes_check
  check (
    case kind
      when 'api' then scopes is not null and scopes in ('{read}'::text[], '{read,write}'::text[])
      -- Null for a row from a backup dumped before this migration, which must still restore
      -- (docs/BACKUP.md); the lookups read it as {read,write}.
      when 'pat' then scopes is null or scopes = '{read,write}'::text[]
      else scopes is null
    end
  ) not valid;
alter table public.personal_access_tokens validate constraint personal_access_tokens_scopes_check;

comment on column public.personal_access_tokens.scopes is
  'Job 73: what a personal key may do: {read} or {read,write}. MCP tokens (kind pat) are {read,write} (job 397; null in a row restored from an older backup means the same). Null for Siri credentials.';

-- Whether one personal key works on MCP and the API (the app's Zugänge shows one list then).
create function public.unified_keys() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.app_switch('unified_keys')
$$;

revoke execute on function public.unified_keys() from public, anon;
grant execute on function public.unified_keys() to authenticated;

-- As authenticate_access_token (20261115100000_key_checks_without_waiting.sql), with the key's
-- scopes, and 'api' keys while unified_keys is on.
create function public.authenticate_key(p_token_hash text)
returns table (user_id uuid, household_id uuid, kind text, scopes text[])
language plpgsql security definer set search_path = '' as $$
declare
  v_key record;
begin
  select t.id, t.user_id, m.household_id, t.kind, t.scopes into v_key
  from public.personal_access_tokens t
  join public.household_members m on m.user_id = t.user_id
    and case when t.kind = 'siri' then m.is_default else m.household_id = t.household_id end
  where t.token_hash = p_token_hash
    and t.revoked_at is null
    and case t.kind
      when 'pat' then true
      when 'api' then public.app_switch('unified_keys')
      else exists (
        select from auth.sessions s
        where s.id = t.session_id and s.user_id = t.user_id
          and (s.not_after is null or s.not_after > now())
      )
    end;
  if not found then
    return;
  end if;
  update public.personal_access_tokens t set last_used_at = now()
  where t.id in (
    select f.id from public.personal_access_tokens f where f.id = v_key.id
    for no key update skip locked
  );
  return query select v_key.user_id, v_key.household_id, v_key.kind,
    case when v_key.kind = 'pat' then '{read,write}'::text[] else v_key.scopes end;
end $$;

revoke execute on function public.authenticate_key(text) from public, anon, authenticated;
grant execute on function public.authenticate_key(text) to service_role;

-- As 20261118201333_api_ip_hash_salted.sql, but an MCP token is a key here too while
-- unified_keys is on.
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

-- Whether the caller may make one more key of [p_kind]; called under the user's key lock. With
-- unified_keys on, MCP tokens and API keys count together against the higher cap.
create function public.key_cap_reached(p_kind text) returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) >= case when public.app_switch('unified_keys') then 20
                          when p_kind = 'api' then 10 else 20 end
  from public.personal_access_tokens t
  where t.user_id = auth.uid() and t.revoked_at is null
    and (t.kind = p_kind or (public.app_switch('unified_keys') and t.kind in ('pat', 'api')))
$$;

revoke execute on function public.key_cap_reached(text) from public, anon, authenticated;

-- As 20261122160000_pat_session_required.sql, but a read-and-write key, under the cap above.
create or replace function public.create_personal_access_token(p_name text, p_household uuid)
returns table (id uuid, name text, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_household uuid;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_claims ? 'client_id' or nullif(v_claims ->> 'session_id', '') is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  v_household := public.token_household(p_household);
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  -- One call at a time for a user, the same lock as create_api_token: the cap holds for calls
  -- that arrive together.
  perform pg_advisory_xact_lock(hashtextextended('api_keys:' || auth.uid()::text, 0));
  if public.key_cap_reached('pat') then
    raise exception 'too_many_tokens' using errcode = 'P0001';
  end if;
  -- 32 random bytes, base64url without padding: 43 characters after the prefix.
  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  return query
  insert into public.personal_access_tokens as t
    (household_id, user_id, name, token_hash, token_hint, scopes)
  values (
    v_household,
    auth.uid(),
    coalesce(nullif(btrim(p_name), ''), 'Token'),
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4),
    '{read,write}'
  )
  returning t.id, t.name, v_token;
end $$;

-- As 20261115100000_key_checks_without_waiting.sql, but with unified_keys on a key can be made
-- while public_api is off, under the shared cap.
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
  if not public.app_switch('public_api') and not public.app_switch('unified_keys') then
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
  if public.key_cap_reached('api') then
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
