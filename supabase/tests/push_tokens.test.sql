-- Job 376: push devices (20261122183000_push_tokens.sql, docs/PUSH.md). A user reads their own
-- rows and writes only through register_push_token and unregister_push_token; a token moves to
-- whoever registers it last; 10 devices per user; the export lists devices without tokens; rows go
-- with the account and after 270 days without a registration.
begin;
select plan(37);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000376a01', 'anna376@fg.test'),
  ('00000000-0000-4000-8000-000000376b01', 'bruno376@fg.test'),
  ('00000000-0000-4000-8000-000000376c01', 'carla376@fg.test');

-- Registering and reading -----------------------------------------------------------------------

select pg_temp.login('00000000-0000-4000-8000-000000376a01');
select lives_ok($$ select public.register_push_token('test-token-a', 'ios') $$, 'Anna registers her phone');
select is((select array_agg(platform) from public.push_tokens), array['ios'], 'she reads her device');
select is((select token from public.push_tokens), 'test-token-a', 'with its token');

select pg_temp.login('00000000-0000-4000-8000-000000376b01');
select is((select count(*)::int from public.push_tokens), 0, 'Bruno reads none of Anna''s devices');

select pg_temp.login('00000000-0000-4000-8000-000000376a01');
select throws_ok($$ insert into public.push_tokens (user_id, token, platform)
  values ('00000000-0000-4000-8000-000000376a01', 'test-token-x', 'ios') $$, '42501', null,
  'no direct insert');
select throws_ok($$ update public.push_tokens set platform = 'android' $$, '42501', null, 'no direct update');
select throws_ok($$ delete from public.push_tokens $$, '42501', null, 'no direct delete');
select throws_ok($$ select public.register_push_token('test-token-b', 'web') $$, '22023', 'invalid_platform',
  'only ios and android');
select throws_ok($$ select public.register_push_token('test-token-b', null) $$, '22023', 'invalid_platform',
  'a platform is needed');
select throws_ok($$ select public.register_push_token('', 'ios') $$, '22023', 'invalid_token', 'no empty token');
select throws_ok($$ select public.register_push_token(repeat('t', 4097), 'ios') $$, '22023', 'invalid_token',
  'no token over 4096 characters');
select lives_ok($$ select public.register_push_token(repeat('t', 4096), 'android') $$,
  '4096 characters are fine');
select lives_ok($$ select public.unregister_push_token(repeat('t', 4096)) $$, 'and unregister');

-- Registering again moves updated_at and keeps one row.
select pg_temp.as_postgres();
update public.push_tokens set created_at = now() - interval '3 days', updated_at = now() - interval '2 days'
where token = 'test-token-a';
select pg_temp.login('00000000-0000-4000-8000-000000376a01');
select public.register_push_token('test-token-a', 'android');
select is((select (platform, created_at < now(), updated_at = now())::text from public.push_tokens),
  '(android,t,t)', 'registering again keeps the row and its creation, and moves updated_at');
select is((select count(*)::int from public.push_tokens), 1, 'one row per token');

-- The token moves to whoever registers it last ---------------------------------------------------

select pg_temp.login('00000000-0000-4000-8000-000000376b01');
select public.register_push_token('test-token-a', 'ios');
select pg_temp.as_postgres();
select is((select (user_id, created_at = now())::text from public.push_tokens where token = 'test-token-a'),
  '(00000000-0000-4000-8000-000000376b01,t)', 'a token Anna had on the device moves to Bruno, as new');
select is((select count(*)::int from public.push_tokens), 1, 'still one row for it');

select pg_temp.login('00000000-0000-4000-8000-000000376a01');
select public.unregister_push_token('test-token-a');
select pg_temp.as_postgres();
select is((select count(*)::int from public.push_tokens), 1, 'Anna unregistering it leaves Bruno''s row');
select pg_temp.login('00000000-0000-4000-8000-000000376b01');
select public.unregister_push_token('test-token-a');
select is((select count(*)::int from public.push_tokens), 0, 'Bruno unregistering it deletes it');
select lives_ok($$ select public.unregister_push_token('test-token-unknown') $$,
  'unregistering an unknown token changes nothing');

-- 10 devices per user ----------------------------------------------------------------------------

select pg_temp.as_postgres();
insert into public.push_tokens (user_id, token, platform, created_at, updated_at)
select '00000000-0000-4000-8000-000000376c01', 'test-token-c' || n, 'android',
  now() - make_interval(days => 20 - n), now() - make_interval(days => 20 - n)
from generate_series(1, 10) n;
select pg_temp.login('00000000-0000-4000-8000-000000376c01');
select public.register_push_token('test-token-c11', 'ios');
select is((select count(*)::int from public.push_tokens), 10, 'an 11th device keeps 10');
select ok(not exists (select from public.push_tokens where token = 'test-token-c1'),
  'the one registered longest ago goes');
select ok(exists (select from public.push_tokens where token = 'test-token-c11'), 'the new one stays');
select public.register_push_token('test-token-c2', 'android');
select public.register_push_token('test-token-c12', 'ios');
select ok(exists (select from public.push_tokens where token = 'test-token-c2'),
  'registering again counts as recent');
select ok(not exists (select from public.push_tokens where token = 'test-token-c3'),
  'so the next oldest goes instead');

-- The export: platform and times, never the token -------------------------------------------------

create temp table export as select public.export_my_data() -> 'push_devices' as devices;
select is((select jsonb_array_length(devices) from export), 10, 'Carla''s export lists her 10 devices');
select is((select array_agg(distinct k order by k) from export, jsonb_array_elements(devices) d,
  jsonb_object_keys(d) k), array['created_at', 'platform', 'updated_at'], 'with platform and times');
select ok((select public.export_my_data()::text !~ 'test-token'), 'and no token anywhere');

-- Signed out --------------------------------------------------------------------------------------

set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok($$ select public.register_push_token('test-token-z', 'ios') $$, '42501', null,
  'signed out, registering is closed');
select throws_ok($$ select public.unregister_push_token('test-token-c2') $$, '42501', null,
  'and unregistering');
select throws_ok($$ select * from public.push_tokens $$, '42501', null, 'and the table');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok($$ select public.register_push_token('test-token-z', 'ios') $$, '28000', 'not_authenticated',
  'a session without a user registers nothing');
select throws_ok($$ select public.purge_push_tokens() $$, '42501', null, 'no client runs the purge');

-- The daily cleanup --------------------------------------------------------------------------------

select pg_temp.as_postgres();
update public.push_tokens set updated_at = now() - interval '271 days' where token = 'test-token-c4';
update public.push_tokens set updated_at = now() - interval '269 days' where token = 'test-token-c5';
select ok(exists (select from cron.job where jobname = 'purge-push-tokens'
  and schedule = '53 3 * * *' and command = 'select public.purge_push_tokens()'), 'the purge runs daily');
select is(public.purge_push_tokens(), 1, 'it deletes the device not registered for 270 days');
select ok(exists (select from public.push_tokens where token = 'test-token-c5'), 'and keeps a younger one');

-- Account deletion ---------------------------------------------------------------------------------

select public.delete_account('00000000-0000-4000-8000-000000376c01');
select is((select count(*)::int from public.push_tokens
  where user_id = '00000000-0000-4000-8000-000000376c01'), 0, 'deleting the account deletes its devices');

select * from finish();
rollback;
