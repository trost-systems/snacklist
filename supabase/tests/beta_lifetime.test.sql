-- Job 371: every account from before launch gets lifetime Premium as a RevenueCat promotional
-- grant on its own customer, to 2100-01-01 (RevenueCat's API needs an end). On the server that
-- grant is a bought Lifetime: Anna has the grant, Ben bought Lifetime, Carla has neither. Anna and
-- Ben are in their own household and Carla's, neither with a household grant. MCP and the API open
-- for Anna and Ben in both, not for Carla; the household cap is the same for all three; syncing the
-- grant again changes nothing.
begin;
select plan(25);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.gate(p_household uuid, p_integration text, p_user uuid) returns text
language sql as $$
  select case when g.locked then 'locked' else 'open' end
  from public.integration_gate(p_household, p_integration, p_user) g
$$;

create function pg_temp.hid(p_name text) returns uuid language sql as $$
  select id from public.households where name = p_name
$$;

create function pg_temp.households_of(p_user uuid) returns int language sql as $$
  select count(*)::int from public.household_members where user_id = p_user
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000371a1', 'anna371@example.com'),
  ('00000000-0000-0000-0000-0000000371b1', 'ben371@example.com'),
  ('00000000-0000-0000-0000-0000000371c1', 'carla371@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000371c1');
select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Carla 371');
create temp table inv as select code from public.create_invite(pg_temp.hid('Carla 371'), 'group');
grant select on inv to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000371a1');
select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Anna 371');
select public.accept_invite((select code from inv), p_mode => 'add');
select pg_temp.login('00000000-0000-0000-0000-0000000371b1');
select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Ben 371');
select public.accept_invite((select code from inv), p_mode => 'add');
select pg_temp.as_postgres();

select is(pg_temp.households_of('00000000-0000-0000-0000-0000000371a1'), 2, 'Anna is in two households');
select is((select count(*)::int from public.entitlements
           where household_id in (pg_temp.hid('Anna 371'), pg_temp.hid('Ben 371'), pg_temp.hid('Carla 371'))),
  0, 'none of the three households has a grant of its own');

-- The grant, written the way the purchases function syncs it ------------------------------------

select is(public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000371a1', true,
  '2100-01-01T00:00:00Z'), 'granted', 'Anna''s lifetime grant is synced');
select is(public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000371a1', true,
  '2100-01-01T00:00:00Z'), 'unchanged', 'syncing it again changes nothing');
select is((select count(*)::int from public.user_entitlements
           where user_id = '00000000-0000-0000-0000-0000000371a1'), 1, 'Anna has one row');
select is(public.purchase_record_user('apple', 'lt371', 'lt371',
    encode(extensions.hmac('lt371', 'pgTAP key', 'sha256'), 'hex'), 'com.snacklist.app.lifetime',
    'premium', 'lifetime', 'Production', now() - interval '1 minute', 29.99, 'EUR', 'DE',
    '00000000-0000-0000-0000-0000000371b1') ->> 'outcome',
  'granted', 'Ben buys Lifetime');

-- Premium, the same as a bought Lifetime ---------------------------------------------------------

select is(public.user_has_premium('00000000-0000-0000-0000-0000000371a1'), true, 'Anna has premium');
select is(public.user_has_premium('00000000-0000-0000-0000-0000000371b1'), true, 'as Ben has');
select is(public.user_has_premium('00000000-0000-0000-0000-0000000371c1'), false, 'Carla has not');
select is((select count(*)::int from public.user_premium('00000000-0000-0000-0000-0000000371a1')), 1,
  'user_premium names one source for Anna');
select is((select row(source, expires_at)::text
           from public.user_premium('00000000-0000-0000-0000-0000000371a1')),
  row('promotional', '2100-01-01T00:00:00Z'::timestamptz)::text, 'her grant, to 2100');

-- MCP and the API under the integration lock ----------------------------------------------------

update public.app_switches set enabled = true where key = 'integration_lock';

select is(pg_temp.gate(pg_temp.hid('Anna 371'), 'mcp', '00000000-0000-0000-0000-0000000371a1'), 'open',
  'MCP is open for Anna in her household');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'mcp', '00000000-0000-0000-0000-0000000371a1'), 'open',
  'and in Carla''s');
select is(pg_temp.gate(pg_temp.hid('Anna 371'), 'api', '00000000-0000-0000-0000-0000000371a1'), 'open',
  'the API too in hers');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'api', '00000000-0000-0000-0000-0000000371a1'), 'open',
  'and in Carla''s');
select is(pg_temp.gate(pg_temp.hid('Ben 371'), 'mcp', '00000000-0000-0000-0000-0000000371b1'), 'open',
  'MCP is open for Ben in his household');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'mcp', '00000000-0000-0000-0000-0000000371b1'), 'open',
  'and in Carla''s');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'api', '00000000-0000-0000-0000-0000000371b1'), 'open',
  'the API too');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'mcp', '00000000-0000-0000-0000-0000000371c1'), 'locked',
  'MCP is locked for Carla in her own household');
select is(pg_temp.gate(pg_temp.hid('Carla 371'), 'api', '00000000-0000-0000-0000-0000000371c1'), 'locked',
  'and the API');

-- The household cap does not move with Premium ---------------------------------------------------

select is(public.household_cap(), 20, 'one cap, 20, whatever the account has');

-- 18 more households, Carla's, take Anna and Ben to 20 and Carla to 19.
insert into public.households (id, name, created_by)
select ('00000000-0000-0000-0000-000000371' || lpad(i::text, 3, '0'))::uuid, 'Fuell 371 ' || i,
  '00000000-0000-0000-0000-0000000371c1'
from generate_series(1, 19) i;
insert into public.household_members (household_id, user_id, role)
select ('00000000-0000-0000-0000-000000371' || lpad(i::text, 3, '0'))::uuid,
  '00000000-0000-0000-0000-0000000371c1', 'owner'
from generate_series(1, 18) i;
insert into public.household_members (household_id, user_id)
select ('00000000-0000-0000-0000-000000371' || lpad(i::text, 3, '0'))::uuid, u::uuid
from generate_series(1, 18) i,
  unnest(array['00000000-0000-0000-0000-0000000371a1', '00000000-0000-0000-0000-0000000371b1']) u;

select throws_ok($$ insert into public.household_members (household_id, user_id)
  values ('00000000-0000-0000-0000-000000371019', '00000000-0000-0000-0000-0000000371a1') $$,
  'P0001', 'too_many_households', 'Anna''s 21st household is refused');
select throws_ok($$ insert into public.household_members (household_id, user_id)
  values ('00000000-0000-0000-0000-000000371019', '00000000-0000-0000-0000-0000000371b1') $$,
  'P0001', 'too_many_households', 'as Ben''s is');
select lives_ok($$ insert into public.household_members (household_id, user_id, role)
  values ('00000000-0000-0000-0000-000000371019', '00000000-0000-0000-0000-0000000371c1', 'owner') $$,
  'Carla''s 20th is not');
select pg_temp.login('00000000-0000-0000-0000-0000000371c1');
select throws_ok($$ select public.create_household(p_request_id => gen_random_uuid(), p_name => 'Mehr') $$,
  'P0001', 'too_many_households', 'and her 21st is, at the same cap');
select pg_temp.as_postgres();

select * from finish();
rollback;
