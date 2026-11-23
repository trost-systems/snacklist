-- Job 50: the integration lock (migration 20261101081327_integration_lock.sql). Ida and Ian share a
-- household with a yearly plan, Jo has none, Tess is a tester. integration_gate() opens every
-- household while the switch is off; with it on only premium ones. A lapse locks at read time and
-- deletes nothing; renewing opens again with the same tokens and links. Alexa is never locked
-- (20261102120000_alexa_free.sql), nor Siri (20261113034530_siri_free.sql, job 184).
begin;
select plan(43);

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

create function pg_temp.yearly(p_tx text, p_household uuid, p_days int) returns jsonb language sql as $$
  select public.purchase_record('apple', p_tx, p_tx, encode(extensions.hmac(p_tx, 'pgTAP key', 'sha256'), 'hex'),
    'com.hummlist.app.yearly', 'premium', 'yearly', 'Production', now() - interval '1 minute', 9.99, 'EUR',
    'DE', p_household, now(), now() + make_interval(days => p_days), true, false)
$$;

create function pg_temp.gate(p_household uuid, p_integration text, p_user uuid default null) returns text language sql as $$
  select case when not locked then 'open' when report then 'locked, report' else 'locked' end
  from public.integration_gate(p_household, p_integration, p_user)
$$;

-- What a household has connected and written: none of it may change because of the lock.
create function pg_temp.integrations(p_household uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'tokens', (select jsonb_agg(t.token_hash order by t.token_hash) from public.personal_access_tokens t
               where t.household_id = p_household and t.revoked_at is null),
    'alexa', (select jsonb_agg(l.session_id order by l.session_id) from public.alexa_links l
              join public.household_members m on m.user_id = l.user_id where m.household_id = p_household),
    'sessions', (select count(*) from auth.sessions s
                 join public.household_members m on m.user_id = s.user_id where m.household_id = p_household),
    'items', (select count(*) from public.items i where i.household_id = p_household),
    'entitlements', (select count(*) from public.entitlements e where e.household_id = p_household))
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000050a1', 'ida50@example.com'),
  ('00000000-0000-0000-0000-0000000050b1', 'ian50@example.com'),
  ('00000000-0000-0000-0000-0000000050c1', 'jo50@example.com'),
  ('00000000-0000-0000-0000-0000000050d1', 'tess50@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000050a1');
create temp table hi as select id from public.create_household('Ida & Ian');
create temp table inv as select code from public.create_invite((select id from hi));
grant select on hi, inv to authenticated;
insert into public.items (household_id, name) select id, 'Milch' from hi;
select pg_temp.login('00000000-0000-0000-0000-0000000050b1');
select public.join_household((select code from inv));
select pg_temp.login('00000000-0000-0000-0000-0000000050c1');
create temp table hj as select id from public.create_household('Jo');
grant select on hj to authenticated;
select pg_temp.as_postgres();

-- The switch ------------------------------------------------------------------------------------

select is((select enabled from public.app_switches where key = 'integration_lock'), false,
  'integration_lock is seeded off');
select matches(obj_description('public.app_switches'::regclass), 'NEVER switch integration_lock on before the public launch and a lead decision',
  'the table says the lock never flips without a lead decision (Legal must-fix 17)');
select is(pg_temp.gate((select id from hj), 'siri'), 'open', 'switch off: a household without premium uses Siri');
select is(pg_temp.gate((select id from hj), 'alexa'), 'open', 'and Alexa');
select is(pg_temp.gate((select id from hj), 'mcp'), 'open', 'and MCP');
select is((select count(*)::int from public.integration_blocks), 0, 'switch off: nothing is noted');

select pg_temp.login('00000000-0000-0000-0000-0000000050c1');
select is(public.integration_lock(), false, 'the app reads the switch as off');
select throws_ok($$ select * from public.integration_gate((select id from hj), 'mcp') $$, '42501', null,
  'a member cannot call the gate');
select throws_ok($$ select * from public.integration_blocks $$, '42501', null,
  'nor read the noted blocks');
select pg_temp.as_postgres();

update public.app_switches set enabled = true where key = 'integration_lock';

select pg_temp.login('00000000-0000-0000-0000-0000000050c1');
select is(public.integration_lock(), true, 'the app reads the switch as on');
select pg_temp.as_postgres();

-- Locked, and the report once an hour ------------------------------------------------------------

select is(pg_temp.gate((select id from hj), 'siri'), 'open', 'switch on, no premium: Siri stays open (free, job 184)');
select ok(not exists (select from public.integration_blocks where household_id = (select id from hj) and integration = 'siri'),
  'and is never noted as blocked');
select is(pg_temp.gate((select id from hj), 'alexa'), 'open', 'switch on, no premium: Alexa stays open (free, job 72)');
select ok(not exists (select from public.integration_blocks where household_id = (select id from hj) and integration = 'alexa'),
  'and is never noted as blocked');
select is(pg_temp.gate((select id from hj), 'mcp'), 'locked, report', 'switch on: no premium, MCP is locked and reported');
select is(pg_temp.gate((select id from hj), 'mcp'), 'locked', 'the second refusal within the hour is not reported');
select is(pg_temp.gate((select id from hi), 'mcp'), 'locked, report', 'Ida''s household is its own pair');
update public.integration_blocks set reported_at = now() - interval '61 minutes'
where household_id = (select id from hj) and integration = 'mcp';
select is(pg_temp.gate((select id from hj), 'mcp'), 'locked, report', 'an hour later it is reported again');
select throws_ok($$ select * from public.integration_gate((select id from hj), 'google') $$, '22023', null,
  'an unknown integration is refused');

select pg_temp.login('00000000-0000-0000-0000-0000000050c1');
select throws_ok($$ select * from public.integration_blocks where household_id = (select id from hi) $$, '42501', null,
  'Jo cannot read Ida''s household''s blocks');
select pg_temp.login('00000000-0000-0000-0000-0000000050a1');
select throws_ok($$ select * from public.integration_blocks where household_id = (select id from hj) $$, '42501', null,
  'nor Ida Jo''s');
select pg_temp.as_postgres();

-- Premium opens, a lapse locks and deletes nothing, renewing opens with the same links -------------

insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint, scopes)
values ((select id from hi), '00000000-0000-0000-0000-0000000050a1', 'Kurzbefehl', repeat('5', 64), '5050', '{read,write}');
insert into auth.sessions (id, user_id) values ('00000000-0000-4000-8000-0000000050e1', '00000000-0000-0000-0000-0000000050b1');
insert into public.alexa_links (alexa_user_hash, session_id, user_id)
values (repeat('a', 64), '00000000-0000-4000-8000-0000000050e1', '00000000-0000-0000-0000-0000000050b1');

select is(pg_temp.yearly('y50', (select id from hi), 365) ->> 'outcome', 'granted', 'Ida''s household buys a yearly plan');
select is(pg_temp.gate((select id from hi), 'siri'), 'open', 'yearly active: Siri is open');
select is(pg_temp.gate((select id from hi), 'alexa'), 'open', 'Alexa too');
select is(pg_temp.gate((select id from hi), 'mcp', '00000000-0000-0000-0000-0000000050a1'), 'locked',
  'but MCP stays locked: a household''s plan does not unlock it (job 419, per account)');
select is(public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000050a1', true, '2100-01-01T00:00:00Z'), 'granted',
  'Ida gets a Premium grant of her own');
select is(pg_temp.gate((select id from hi), 'mcp', '00000000-0000-0000-0000-0000000050a1'), 'open', 'MCP is open for Ida');
select is(pg_temp.gate((select id from hi), 'mcp', '00000000-0000-0000-0000-0000000050b1'), 'locked',
  'and locked for Ian in the same household');

create temp table before_lapse as select pg_temp.integrations((select id from hi)) as v;
select is(public.purchase_lifecycle('apple', 'y50', now() + interval '1 second', now() - interval '1 minute', false, false) ->> 'outcome',
  'updated', 'the yearly plan expires (EXPIRATION)');
select is(pg_temp.gate((select id from hi), 'mcp', '00000000-0000-0000-0000-0000000050b1'), 'locked', 'lapsed: MCP is locked at read time (reported within the hour already)');
select is(pg_temp.gate((select id from hi), 'alexa'), 'open', 'Alexa stays open after the lapse');
select is(pg_temp.integrations((select id from hi)), (select v from before_lapse),
  'the lapse deleted no token, Alexa link, session, item or entitlement row');

select is(public.purchase_lifecycle('apple', 'y50', now() + interval '2 seconds', now() + interval '365 days', true, false) ->> 'outcome',
  'updated', 'the plan renews (RENEWAL)');
select is(pg_temp.gate((select id from hi), 'siri'), 'open', 'renewed: Siri is open again');
select is(pg_temp.gate((select id from hi), 'mcp', '00000000-0000-0000-0000-0000000050b1'), 'locked', 'MCP stays locked for a member without Premium of their own');
select is(pg_temp.integrations((select id from hi)), (select v from before_lapse),
  'with the same tokens and links, nothing to set up again');

select is(public.purchase_record('apple', 'l50', 'l50', encode(extensions.hmac('l50', 'pgTAP key', 'sha256'), 'hex'),
    'com.hummlist.app.lifetime', 'premium', 'lifetime', 'Production', now() - interval '1 minute', 29.99, 'EUR',
    'DE', (select id from hj)) ->> 'outcome', 'granted', 'Jo buys Lifetime');
select is(pg_temp.gate((select id from hj), 'alexa'), 'open', 'with Lifetime Alexa is open as always');

-- A tester's grant counts as premium (AC6): Tess's own new household works at the cut-over. Since
-- 20261101150000 a tester's grant is a RevenueCat promotional grant for the household.
select pg_temp.login('00000000-0000-0000-0000-0000000050d1');
create temp table ht as select id from public.create_household('Tess');
select pg_temp.as_postgres();
select is(public.promotional_premium_sync((select id from ht), true, '2100-01-01T00:00:00Z'), 'granted',
  'Tess''s household has a promotional grant');
select is(pg_temp.gate((select id from ht), 'mcp', '00000000-0000-0000-0000-0000000050d1'), 'locked, report',
  'which no longer opens MCP (job 419)');
select is(public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000050d1', true, '2100-01-01T00:00:00Z'), 'granted',
  'a tester''s grant is a per-user RevenueCat grant');
select is(pg_temp.gate((select id from ht), 'mcp', '00000000-0000-0000-0000-0000000050d1'), 'open', 'and opens MCP with the switch on');

update public.app_switches set enabled = false where key = 'integration_lock';
select is(pg_temp.gate((select id from hi), 'siri') || ', ' || pg_temp.gate((select id from hj), 'mcp'), 'open, open',
  'switching off again opens everyone');

select * from finish();
rollback;
