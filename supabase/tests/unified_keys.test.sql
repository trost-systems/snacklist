-- Job 397 (AU1): one personal key for MCP and the API, behind app_switches.unified_keys
-- (migration 20261122230000_unified_keys.sql). Off, MCP tokens and API keys stay apart as before;
-- on, authenticate_key (MCP, Siri's Shortcut) takes API keys with their scopes, api_begin takes MCP
-- tokens, keys can be made while public_api is off, and both kinds share one cap of 20.
begin;
select plan(40);

create function pg_temp.login(uid uuid, claims jsonb default jsonb_build_object('session_id', gen_random_uuid()))
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', uid, 'role', 'authenticated') || claims)::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.hash(token text) returns text language sql as $$
  select encode(extensions.digest(token, 'sha256'), 'hex');
$$;

-- As the service role sets them; the caller is postgres afterwards.
create function pg_temp.switch(p_key text, p_on boolean) returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  update public.app_switches set enabled = p_on where key = p_key;
end $$;

-- The API's limits (supabase/functions/api/limits.ts).
create function pg_temp.api(token text) returns setof record language sql as $$
  select outcome, scopes from public.api_begin(pg_temp.hash(token), pg_temp.hash('ip-1'), 20, 60, 1000, 20, 600);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000397a01', 'alma@example.com'),
  ('00000000-0000-0000-0000-000000397b01', 'bert@example.com');

select is((select enabled from public.app_switches where key = 'unified_keys'), false,
  'the switch is seeded off');

select pg_temp.login('00000000-0000-0000-0000-000000397a01');
create temp table ha as select id from public.create_household('Alma');
create temp table mcp as select * from public.create_personal_access_token('Claude', (select id from ha));
select is(public.unified_keys(), false, 'the app reads the switch as off');

-- Off: as before job 397 -----------------------------------------------------------------------

select throws_ok($$ select public.create_api_token('Skript', '{read}', (select id from ha)) $$,
  '42501', 'api_disabled', 'off: no API key while public_api is off');
select pg_temp.switch('public_api', true);
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
create temp table ro as select * from public.create_api_token('Lesen', '{read}', (select id from ha));
create temp table rw as select * from public.create_api_token('Home Assistant', '{read,write}', (select id from ha));
grant select on ha, mcp, ro, rw to authenticated;

select results_eq(
  $$ select kind, scopes from public.personal_access_tokens where id = (select id from mcp) $$,
  $$ values ('pat', '{read,write}'::text[]) $$,
  'an MCP token is a read-and-write key'
);

select pg_temp.as_postgres();
-- A row from a backup dumped before job 397 has no scopes; it restores and reads as {read,write}.
insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint)
values ((select id from ha), '00000000-0000-0000-0000-000000397a01', 'Alt', pg_temp.hash('fgp_restored'), 'ored');
select results_eq(
  $$ select kind, scopes from public.authenticate_key(pg_temp.hash('fgp_restored')) $$,
  $$ values ('pat', '{read,write}'::text[]) $$,
  'an MCP token restored without scopes reads and writes'
);
update public.personal_access_tokens set revoked_at = now() where token_hint = 'ored';
select throws_ok(
  $$ insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint, scopes)
     values ((select id from ha), '00000000-0000-0000-0000-000000397a01', 'x', repeat('7', 64), '7777', '{read}') $$,
  '23514', null, 'an MCP token is never read-only'
);
select throws_ok(
  $$ insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint, kind, scopes)
     values ((select id from ha), '00000000-0000-0000-0000-000000397a01', 'x', repeat('8', 64), '8888', 'siri', '{read}') $$,
  '23514', null, 'a Siri credential carries no scopes'
);
select is(
  (select count(*)::int from public.personal_access_tokens where kind = 'pat' and revoked_at is null and scopes is distinct from '{read,write}'),
  0, 'every MCP token the app made is read-and-write'
);

select results_eq(
  $$ select kind, scopes from public.authenticate_key(pg_temp.hash((select token from mcp))) $$,
  $$ values ('pat', '{read,write}'::text[]) $$,
  'off: MCP takes an MCP token, read-and-write'
);
select is_empty($$ select * from public.authenticate_key(pg_temp.hash((select token from ro))) $$,
  'off: MCP does not take an API key');
select results_eq($$ select * from pg_temp.api((select token from mcp)) as (o text, s text[]) $$,
  $$ values ('invalid', null::text[]) $$, 'off: the API does not take an MCP token');
select results_eq($$ select * from pg_temp.api((select token from ro)) as (o text, s text[]) $$,
  $$ values ('ok', '{read}'::text[]) $$, 'off: the API takes its key');

-- On ------------------------------------------------------------------------------------------

select pg_temp.switch('unified_keys', true);
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
select is(public.unified_keys(), true, 'the app reads the switch as on');

select pg_temp.as_postgres();
select results_eq(
  $$ select user_id, household_id, kind, scopes from public.authenticate_key(pg_temp.hash((select token from ro))) $$,
  $$ select '00000000-0000-0000-0000-000000397a01'::uuid, id, 'api', '{read}'::text[] from ha $$,
  'on: MCP takes a read-only API key with its scope'
);
select results_eq(
  $$ select kind, scopes from public.authenticate_key(pg_temp.hash((select token from rw))) $$,
  $$ values ('api', '{read,write}'::text[]) $$,
  'on: MCP takes a read-and-write API key with its scopes'
);
select results_eq($$ select * from pg_temp.api((select token from mcp)) as (o text, s text[]) $$,
  $$ values ('ok', '{read,write}'::text[]) $$, 'on: the API takes an MCP token, read-and-write');
select results_eq($$ select * from pg_temp.api((select token from ro)) as (o text, s text[]) $$,
  $$ values ('ok', '{read}'::text[]) $$, 'on: the API still takes its key');
select is((select count(*)::int from public.api_token_buckets where token_id = (select id from mcp)), 1,
  'on: an MCP token on the API counts in its own API bucket');

-- Older function versions (a rollback) check no scope: they never get an API key.
select is_empty($$ select * from public.authenticate_access_token(pg_temp.hash((select token from ro))) $$,
  'on: the lookup older versions call still refuses an API key');
select is_empty($$ select * from public.authenticate_personal_access_token(pg_temp.hash((select token from ro))) $$,
  'on: the oldest lookup refuses it too');

select pg_temp.switch('public_api', false);
select results_eq($$ select * from pg_temp.api((select token from mcp)) as (o text, s text[]) $$,
  $$ values ('disabled', null::text[]) $$, 'on: public_api off still closes the API');
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
select lives_ok($$ select public.create_api_token('Neu', '{read}', (select id from ha)) $$,
  'on: a key can be made while public_api is off');
select pg_temp.as_postgres();
select results_eq(
  $$ select kind, scopes from public.authenticate_key(pg_temp.hash((select token from mcp))) $$,
  $$ values ('pat', '{read,write}'::text[]) $$,
  'on: MCP still takes an MCP token'
);

-- Who may make keys -------------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-000000397a01',
  '{"session_id": "00000000-0000-0000-0000-000000397e51", "client_id": "00000000-0000-0000-0000-000000397c11"}');
select throws_ok($$ select public.create_api_token('x', '{read,write}', (select id from ha)) $$,
  '42501', 'session_required', 'on: an OAuth-connected app cannot make a key');
select throws_ok($$ select public.create_personal_access_token('x', (select id from ha)) $$,
  '42501', 'session_required', 'on: nor an MCP token (job 389)');
select pg_temp.login('00000000-0000-0000-0000-000000397a01', '{}');
select throws_ok($$ select public.create_api_token('x', '{read}', (select id from ha)) $$,
  '42501', 'session_required', 'on: a token without a session cannot make a key');
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
select throws_ok($$ select public.create_api_token('x', '{write}', (select id from ha)) $$,
  '22023', 'invalid_scopes', 'on: write without read is no scope set');

-- One cap of 20 for both kinds while on: 4 keys so far.
select is((select count(*)::int from public.personal_access_tokens where revoked_at is null), 4, 'four active keys');
select lives_ok($$ select public.create_personal_access_token('k' || n, (select id from ha)) from generate_series(1, 8) n $$,
  'old app builds still make MCP tokens');
select lives_ok($$ select public.create_api_token('k' || n, '{read}', (select id from ha)) from generate_series(1, 8) n $$,
  'API keys above the old cap of 10 while on');
select throws_ok($$ select public.create_api_token('k21', '{read}', (select id from ha)) $$,
  'P0001', 'too_many_tokens', 'on: the 21st key of either kind is refused');
select throws_ok($$ select public.create_personal_access_token('k21', (select id from ha)) $$,
  'P0001', 'too_many_tokens', 'on: an old build''s 21st key too');
update public.personal_access_tokens set revoked_at = now() where name = 'k1' and kind = 'api';
select lives_ok($$ select public.create_personal_access_token('k21', (select id from ha)) $$,
  'a revoked key frees its place');

-- Off again: today's caps, apart.
select pg_temp.switch('unified_keys', false);
select pg_temp.switch('public_api', true);
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
select throws_ok($$ select public.create_api_token('k22', '{read}', (select id from ha)) $$,
  'P0001', 'too_many_tokens', 'off: at most 10 API keys');
select pg_temp.as_postgres();
select is_empty($$ select * from public.authenticate_key(pg_temp.hash((select token from ro))) $$,
  'off again: MCP no longer takes an API key');

-- Ends ----------------------------------------------------------------------------------------

select pg_temp.switch('unified_keys', true);
select pg_temp.login('00000000-0000-0000-0000-000000397a01');
update public.personal_access_tokens set revoked_at = now() where id = (select id from ro);
select pg_temp.as_postgres();
select is_empty($$ select * from public.authenticate_key(pg_temp.hash((select token from ro))) $$,
  'a revoked key is refused');

select pg_temp.login('00000000-0000-0000-0000-000000397b01');
select is((select count(*)::int from public.personal_access_tokens), 0, 'another user sees none of the keys');
select throws_ok($$ select * from public.authenticate_key(repeat('0', 64)) $$, '42501', null,
  'clients cannot resolve key hashes');
select throws_ok($$ select public.key_cap_reached('api') $$, '42501', null,
  'clients cannot call the cap check');

select pg_temp.login('00000000-0000-0000-0000-000000397a01');
select public.leave_current_household();
select pg_temp.as_postgres();
select is_empty($$ select * from public.authenticate_key(pg_temp.hash((select token from rw))) $$,
  'a key stops working once its creator leaves the household');

select * from finish();
rollback;
