-- Job 73: the public API's database side (migration 20261102130000_public_api.sql). API keys are
-- made from the app's session only, with {read} or {read,write}; api_begin takes one request from
-- the key's bucket and the account's day, throttles an address after failed authentications,
-- and reaches only the key's own household; MCP and Siri never take an API key.
begin;
select plan(76);

-- The API is switched off after the migrations (public_api_switch.test.sql); these run with it on.
update public.app_switches set enabled = true where key = 'public_api';

create function pg_temp.login(uid uuid, claims jsonb default '{}') returns void language plpgsql as $$
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

-- How api_auth_failures keys an address (N-255): the function's SHA-256 salted in the database.
create function pg_temp.ip_key(ip text) returns text language sql as $$
  select encode(extensions.digest(
    (select s.salt from public.invite_preview_salt s) || convert_to(pg_temp.hash(ip), 'UTF8'), 'sha256'), 'hex');
$$;

-- The limits of supabase/functions/api/limits.ts: burst 20 at 60 a minute, 1000 a day, 20
-- failures per 600 s.
create function pg_temp.begin_(token text, ip text default 'ip-1') returns setof record language sql as $$
  select outcome, household_id, scopes, rate_limit, rate_remaining, rate_reset, retry_after
  from public.api_begin(pg_temp.hash(token), pg_temp.hash(ip), 20, 60, 1000, 20, 600);
$$;

create function pg_temp.outcome(token text, ip text default 'ip-1') returns text language sql as $$
  select outcome from public.api_begin(pg_temp.hash(token), pg_temp.hash(ip), 20, 60, 1000, 20, 600);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000073a1', 'ada73@example.com'),
  ('00000000-0000-0000-0000-0000000073b1', 'ben73@example.com'),
  ('00000000-0000-0000-0000-0000000073c1', 'cem73@example.com');

-- Ada's household (Cem joins it) and Ben's.
select pg_temp.login('00000000-0000-0000-0000-0000000073a1', '{"session_id": "00000000-0000-0000-0000-0000000073a5"}');
create temp table ha as select id from public.create_household('Ada');
create temp table inv as select code from public.create_invite((select id from ha));
create temp table ka as select * from public.create_api_token('Home Assistant', '{write,read}');
create temp table kr as select * from public.create_api_token(' ', '{read}');
create temp table pat as select * from public.create_personal_access_token('Claude');
grant select on ha, inv, ka, kr, pat to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000073b1', '{"session_id": "00000000-0000-0000-0000-0000000073b5"}');
create temp table hb as select id from public.create_household('Ben');
create temp table kb as select * from public.create_api_token('n8n', '{read,write}');
grant select on hb, kb to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000073c1', '{"session_id": "00000000-0000-0000-0000-0000000073c5"}');
select public.join_household((select code from inv));
create temp table kc as select * from public.create_api_token('Shortcut', '{read}');
grant select on kc to authenticated;

-- Making keys ---------------------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000073a1', '{"session_id": "00000000-0000-0000-0000-0000000073a5"}');
select ok((select token ~ '^fgp_[A-Za-z0-9_-]{43}$' from ka), 'an API key has the access token format');
select is((select scopes from ka), '{read,write}'::text[], 'scopes come back sorted');
select is((select name from kr), 'API', 'a blank name becomes API');
select results_eq(
  $$ select kind, scopes, token_hint from public.personal_access_tokens where id = (select id from ka) $$,
  $$ select 'api'::text, '{read,write}'::text[], right(token, 4) from ka $$,
  'the owner reads kind, scopes and hint of the key'
);
select is((select scopes from public.personal_access_tokens where id = (select id from pat)),
  '{read,write}'::text[], 'an MCP token reads and writes (job 397)');
select throws_ok($$ select public.create_api_token('x', '{write}') $$, '22023', 'invalid_scopes',
  'write alone is no scope set');
select throws_ok($$ select public.create_api_token('x', '{}') $$, '22023', 'invalid_scopes',
  'no scopes are refused');
select throws_ok($$ select public.create_api_token('x', '{read,admin}') $$, '22023', 'invalid_scopes',
  'unknown scopes are refused');
select throws_ok($$ select public.create_api_token('x', null) $$, '22023', 'invalid_scopes',
  'null scopes are refused');
select pg_temp.login('00000000-0000-0000-0000-0000000073a1',
  '{"session_id": "00000000-0000-0000-0000-0000000073a5", "client_id": "claude"}');
select throws_ok($$ select public.create_api_token('x', '{read}') $$, '42501', 'session_required',
  'an OAuth-connected app cannot make a key');
select pg_temp.login('00000000-0000-0000-0000-0000000073a1');
select throws_ok($$ select public.create_api_token('x', '{read}') $$, '42501', 'session_required',
  'a token without a session cannot make a key');
select pg_temp.login('00000000-0000-0000-0000-0000000073a1', '{"session_id": "00000000-0000-0000-0000-0000000073a5"}');
select throws_ok($$ update public.personal_access_tokens set scopes = '{read,write}' where id = (select id from kr) $$,
  '42501', null, 'clients cannot widen a key''s scopes');
select lives_ok($$ select public.create_api_token('k' || n, '{read}') from generate_series(3, 10) n $$,
  'ten active keys per member');
select throws_ok($$ select public.create_api_token('k11', '{read}') $$, 'P0001', 'too_many_tokens',
  'an eleventh is refused');
select is((select count(*)::int from public.personal_access_tokens where kind = 'pat'), 1,
  'the API cap leaves the MCP tokens alone');
update public.personal_access_tokens set revoked_at = now() where name like 'k%' and kind = 'api';
select pg_temp.login('00000000-0000-0000-0000-0000000073b1', '{"session_id": "00000000-0000-0000-0000-0000000073b5"}');
select is((select count(*)::int from public.personal_access_tokens where id = (select id from ka)), 0,
  'another household''s member does not see the key');

-- api_begin: the key and its household ------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000073b1', '{"session_id": "00000000-0000-0000-0000-0000000073b5"}');
select throws_ok($$ select public.api_begin('x', null, 20, 60, 1000, 20, 600) $$,
  '42501', null, 'clients cannot call api_begin');
select pg_temp.as_postgres();
select results_eq(
  $$ select * from pg_temp.begin_((select token from ka)) as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ select 'ok'::text, (select id from ha), '{read,write}'::text[], 20, 19, 1, null::int $$,
  'a key resolves to its household and scopes, with 19 of 20 left, full again in a second'
);
select isnt((select last_used_at from public.personal_access_tokens where id = (select id from ka)), null,
  'a request marks the key used');
select is((select household_id from public.api_begin(pg_temp.hash((select token from kb)), null, 20, 60, 1000, 20, 600)),
  (select id from hb), 'Ben''s key reaches Ben''s household only');
select is((select household_id from public.api_begin(pg_temp.hash((select token from kc)), null, 20, 60, 1000, 20, 600)),
  (select id from ha), 'a member''s key acts in the household it was made for');
select is(pg_temp.outcome((select token from pat)), 'invalid', 'an MCP token is not an API key');
select is((select count(*)::int from public.authenticate_access_token(pg_temp.hash((select token from ka)))), 0,
  'MCP and Siri do not take an API key');
select is((select count(*)::int from public.authenticate_personal_access_token(pg_temp.hash((select token from ka)))), 0,
  'nor does the older PAT lookup');

-- The key's bucket: 20 at once, then one a second (now() stands still inside this test).
select is(
  (select array_agg(pg_temp.outcome((select token from ka))) from generate_series(1, 19)),
  array_fill('ok'::text, array[19]), 'the rest of the burst goes through'
);
select results_eq(
  $$ select * from pg_temp.begin_((select token from ka)) as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ select 'limited'::text, (select id from ha), '{read,write}'::text[], 20, 0, 20, 1 $$,
  'the 21st is limited: retry in a second, full in 20'
);
select is((select requests from public.account_days where user_id = '00000000-0000-0000-0000-0000000073a1'), 20,
  'a limited request takes nothing from the account''s day (20 of Ada)');
select is((select requests from public.account_days where user_id = '00000000-0000-0000-0000-0000000073c1'), 1,
  'a household member''s key counts on their own account (Cem 1)');
update public.api_token_buckets set refilled_at = refilled_at - interval '3 seconds'
where token_id = (select id from ka);
select is(pg_temp.outcome((select token from ka)), 'ok', 'three seconds later it refilled');
select results_eq(
  $$ select * from pg_temp.begin_((select token from kr)) as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ select 'ok'::text, (select id from ha), '{read}'::text[], 20, 19, 1, null::int $$,
  'another key of the household has its own bucket'
);

-- The account's day: 1000 for all its keys (and MCP, mcp_rate.test.sql), not for its household.
update public.account_days set requests = 998 where user_id = '00000000-0000-0000-0000-0000000073a1';
select results_eq(
  $$ select o, l, r, re > 0 and re <= 86400 from pg_temp.begin_((select token from kr))
       as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ values ('ok'::text, 1000, 1, true) $$,
  'near the day''s end the headers show the account''s 1000'
);
select is(pg_temp.outcome((select token from ka)), 'ok', 'the 1000th goes through, on another key');
select results_eq(
  $$ select o, l, r, ra = re and ra > 0 from pg_temp.begin_((select token from kr))
       as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ values ('limited'::text, 1000, 0, true) $$,
  'the 1001st is limited until the next UTC day'
);
select cmp_ok(public.mcp_take_call('00000000-0000-0000-0000-0000000073a1', 20, 60, 1000), '>', 1,
  'MCP shares the account''s day: after 1000 API requests its first call waits for the next UTC day');
update public.account_days set requests = 999 where user_id = '00000000-0000-0000-0000-0000000073a1';
select is(public.mcp_take_call('00000000-0000-0000-0000-0000000073a1', 20, 60, 1000), null,
  'and the 1000th call may be MCP''s');
select is(pg_temp.outcome((select token from kr)), 'limited', 'after which the API is limited too');
select is(pg_temp.outcome((select token from kc)), 'ok', 'a household member has their own day');
select is(pg_temp.outcome((select token from kb)), 'ok', 'Ben''s account has its own day');

-- Failed authentications per address.
select results_eq(
  $$ select o, l, r, re from pg_temp.begin_('fgp_wrong', 'ip-2') as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ values ('invalid'::text, 20, 19, 600) $$,
  'an unknown key counts one of 20 failures for the address'
);
select is(
  (select array_agg(pg_temp.outcome('fgp_wrong' || n, 'ip-2')) from generate_series(2, 20) n),
  array_fill('invalid'::text, array[19]), 'up to 20 failures are answered as invalid'
);
select results_eq(
  $$ select o, l, r, ra from pg_temp.begin_('fgp_wrong21', 'ip-2') as (o text, h uuid, s text[], l int, r int, re int, ra int) $$,
  $$ values ('blocked'::text, 20, 0, 600) $$,
  'then unknown keys from the address are blocked for the rest of the window'
);
select is(pg_temp.outcome((select token from kb), 'ip-2'), 'ok',
  'a valid key from the blocked address still goes through');
select is(pg_temp.outcome('fgp_wrong', 'ip-3'), 'invalid', 'another address is not blocked');
select is((select failures from public.api_auth_failures where ip_hash = pg_temp.ip_key('ip-2')), 20,
  'a blocked request counts no further failure');
select is((select count(*)::int from public.api_auth_failures where ip_hash = pg_temp.hash('ip-2')), 0,
  'the address is stored salted, never as its plain SHA-256 (N-255)');
update public.api_auth_failures set window_start = window_start - interval '601 seconds'
where ip_hash = pg_temp.ip_key('ip-2');
select is(pg_temp.outcome('fgp_wrong', 'ip-2'), 'invalid',
  'after the window the address is free, and a new failure starts a new window');
select is((select failures from public.api_auth_failures where ip_hash = pg_temp.ip_key('ip-2')), 1,
  'counted from one');
select is((select outcome from public.api_begin(null, null, 20, 60, 1000, 20, 600)), 'invalid',
  'no key and no address: invalid, nothing to count');
select is((select count(*)::int from public.api_auth_failures where ip_hash in (select pg_temp.ip_key(a) from unnest(array['ip-1', 'ip-2', 'ip-3', 'ip-4']) a)), 2,
  'only addresses that sent unknown keys are kept: an MCP token (ip-1) counted nothing');

-- Keys that ended.
update public.personal_access_tokens set revoked_at = now() where id = (select id from kr);
select is(pg_temp.outcome((select token from kr), 'ip-4'), 'invalid', 'a revoked key is invalid');
delete from public.household_members where user_id = '00000000-0000-0000-0000-0000000073c1';
select is(pg_temp.outcome((select token from kc), 'ip-4'), 'invalid', 'a key whose creator left is invalid');
select is(
  (select array_agg(pg_temp.outcome((select token from kr), 'ip-5')) from generate_series(1, 30)),
  array_fill('invalid'::text, array[30]), 'an integration polling with a revoked key 30 times is never blocked'
);
select is((select count(*)::int from public.api_auth_failures where ip_hash in (pg_temp.ip_key('ip-4'), pg_temp.ip_key('ip-5'))), 0,
  'ended keys count nothing against their address');
select is(pg_temp.outcome((select token from kb), 'ip-5'), 'ok', 'so a valid key from that address goes through');
insert into public.api_auth_failures (ip_hash, window_start, failures)
select pg_temp.hash('old-' || n), now() - interval '11 minutes', 1 from generate_series(1, 150) n;
select is(pg_temp.outcome('fgp_wrong', 'ip-6'), 'invalid', 'a new failure');
select is((select count(*)::int from public.api_auth_failures where ip_hash in (select pg_temp.hash('old-' || n) from generate_series(1, 150) n)), 50,
  'deletes a hundred ended windows as it goes, so the table cannot be flooded');

-- Clients read none of it; the household day is the member's own at most.
select pg_temp.login('00000000-0000-0000-0000-0000000073b1', '{"session_id": "00000000-0000-0000-0000-0000000073b5"}');
select throws_ok($$ select * from public.account_days $$, '42501', null,
  'members do not read the day counters');
select throws_ok($$ select * from public.api_token_buckets $$, '42501', null, 'nor the buckets');
select throws_ok($$ select * from public.api_auth_failures $$, '42501', null, 'nor the failures');
select throws_ok($$ select * from public.api_idempotency $$, '42501', null, 'nor the idempotency records');

-- The integration lock knows the API.
select pg_temp.as_postgres();
select is((select locked from public.integration_gate((select id from ha), 'api')), false,
  'with the lock off the API is open');
update public.app_switches set enabled = true where key = 'integration_lock';
select results_eq($$ select locked, report from public.integration_gate((select id from hb), 'api') $$,
  $$ values (true, true) $$, 'with it on, a household without Premium is locked and reported once');
select is((select integration from public.integration_blocks where household_id = (select id from hb)), 'api',
  'the refusal is noted for the API');
-- After every migration (job 72's alexa_free runs before this one, job 184's siri_free after it):
-- Siri and Alexa stay free, the API does not.
select is((select locked from public.integration_gate((select id from hb), 'alexa')), false,
  'with the lock on, Alexa stays open for a household without Premium (job 72)');
select results_eq($$ select locked, report from public.integration_gate((select id from hb), 'siri') $$,
  $$ values (false, false) $$, 'and Siri, unreported (job 184)');
select ok(not exists (select from public.integration_blocks where household_id = (select id from hb) and integration = 'siri'),
  'Siri is never noted as blocked');
select is((select locked from public.integration_gate((select id from hb), 'mcp')), true,
  'MCP is locked for it');
select is(public.promotional_premium_sync((select id from ha), true, '2100-01-01T00:00:00Z'), 'granted',
  'Ada''s household gets Premium');
select is((select locked from public.integration_gate((select id from ha), 'api', '00000000-0000-0000-0000-0000000073a1')), true,
  'a household''s Premium alone no longer opens the API');
select is(public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000073a1', true, '2100-01-01T00:00:00Z'), 'granted',
  'Ada gets Premium of her own');
select is((select locked from public.integration_gate((select id from ha), 'api', '00000000-0000-0000-0000-0000000073a1')), false,
  'with her own Premium the API is open while the lock is on');
select is((select locked from public.integration_gate((select id from ha), 'api', '00000000-0000-0000-0000-0000000073c1')), true,
  'and stays locked for the household member without one');
update public.app_switches set enabled = false where key = 'integration_lock';

-- Retention and cascades.
insert into public.api_idempotency (token_id, key, request_hash, status, body, created_at)
values ((select id from kb), 'old', repeat('a', 64), 201, '{}', now() - interval '25 hours'),
       ((select id from kb), 'new', repeat('b', 64), 201, '{}', now());
insert into public.account_days (user_id, day, requests)
values ('00000000-0000-0000-0000-0000000073b1', (now() at time zone 'utc')::date - 2, 5),
       ('00000000-0000-0000-0000-0000000073b1', (now() at time zone 'utc')::date - 1, 5);
update public.api_auth_failures set window_start = now() - interval '25 hours' where ip_hash = pg_temp.ip_key('ip-2');
select ok(public.purge_api_rate() >= 2 and public.purge_mcp_rate() >= 1, 'the daily job deletes the old idempotency record, day and failure window');
select results_eq(
  $$ select (select count(*)::int from public.api_idempotency where token_id = (select id from kb)),
            (select count(*)::int from public.account_days where user_id = '00000000-0000-0000-0000-0000000073b1'),
            (select count(*)::int from public.api_auth_failures where ip_hash in (select pg_temp.ip_key(a) from unnest(array['ip-1', 'ip-2', 'ip-3', 'ip-4']) a)) $$,
  $$ values (1, 2, 1) $$, 'and keeps yesterday, today and fresh records'
);
delete from public.personal_access_tokens where id = (select id from kb);
select results_eq(
  $$ select (select count(*)::int from public.api_idempotency where token_id = (select id from kb)),
            (select count(*)::int from public.api_token_buckets where token_id = (select id from kb)) $$,
  $$ values (0, 0) $$, 'a deleted key takes its bucket and idempotency records with it'
);
select is((select schedule from cron.job where jobname = 'purge-api-rate'), '41 3 * * *',
  'the purge runs daily at 03:41 UTC');

select * from finish();
rollback;
