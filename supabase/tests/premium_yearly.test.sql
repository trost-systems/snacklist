-- Job 49: Snacklist Premium, yearly and Lifetime under one kind (migration
-- 20261031214500_premium_yearly.sql). Pia and Paul share a household, Quinn has her own, Tara is a
-- tester. Premium is active at read time; lifetime and endless promotional grants beat yearly; expiry deletes
-- nothing; only the subscriber learns of a billing problem.
begin;
select plan(69);

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

create function pg_temp.hmac(p_tx text) returns text language sql as $$
  select encode(extensions.hmac(p_tx, 'pgTAP key', 'sha256'), 'hex')
$$;

-- A yearly plan [p_tx] for [p_household], claimed by [p_user] when given, ending [p_days] from now.
create function pg_temp.yearly(p_tx text, p_household uuid, p_days int, p_user uuid default null,
                               p_event_at timestamptz default now())
returns jsonb language plpgsql as $$
begin
  if p_user is not null then
    perform public.purchase_claim(p_user, p_household, 'apple', p_tx);
  end if;
  return public.purchase_record('apple', p_tx, p_tx, pg_temp.hmac(p_tx), 'com.hummlist.app.yearly',
    'premium', 'yearly', 'Production', now() - interval '1 minute', 9.99, 'EUR', 'DE', p_household,
    p_event_at, now() + make_interval(days => p_days), true, false);
end $$;

create function pg_temp.lifetime(p_tx text, p_household uuid) returns jsonb language sql as $$
  select public.purchase_record('apple', p_tx, p_tx, pg_temp.hmac(p_tx), 'com.hummlist.app.lifetime',
    'premium', 'lifetime', 'Production', now() - interval '1 minute', 29.99, 'EUR', 'DE', p_household)
$$;

create function pg_temp.premium(p_household uuid) returns text language sql as $$
  select coalesce((select source || coalesce(' ' || round(extract(epoch from expires_at - now()) / 86400)::text, '')
                   from public.household_premium(p_household)), 'none')
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000049a1', 'pia49@example.com'),
  ('00000000-0000-0000-0000-0000000049b1', 'paul49@example.com'),
  ('00000000-0000-0000-0000-0000000049c1', 'quinn49@example.com'),
  ('00000000-0000-0000-0000-0000000049d1', 'tara49@example.com'),
  ('00000000-0000-0000-0000-0000000049e1', 'gina49@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000049a1');
create temp table hp as select id from public.create_household('Pia & Paul');
create temp table inv as select code from public.create_invite((select id from hp));
grant select on hp, inv to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000049b1');
select public.join_household((select code from inv));
select pg_temp.login('00000000-0000-0000-0000-0000000049c1');
create temp table hq as select id from public.create_household('Quinn');
grant select on hq to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000049e1');
create temp table hg as select id from public.create_household('Gina');
grant select on hg to authenticated;
select pg_temp.as_postgres();

-- The kind ------------------------------------------------------------------------------------

select is((select count(*)::int from public.purchases where kind <> 'premium')
  + (select count(*)::int from public.entitlements where kind <> 'premium'), 0, 'no lifetime kind is left');
select throws_ok($$ insert into public.entitlements (household_id, kind, source, premium_source)
                    values ((select id from hp), 'lifetime', 'promotional', 'promotional') $$, '23514', null,
  'the old kind is refused by the check');
select throws_ok(
  $$ select public.purchase_record('apple', 'k1', 'k1', pg_temp.hmac('k1'), 'com.hummlist.app.lifetime',
       'lifetime', 'lifetime', 'Production', now(), 29.99, 'EUR', 'DE', (select id from hp)) $$,
  '23514', null, 'a purchase cannot be recorded with the old kind');

-- A yearly plan ------------------------------------------------------------------------------

select is(pg_temp.premium((select id from hp)), 'none', 'a new household has no premium');
select is(public.household_has_premium((select id from hp)), false, 'household_has_premium says no');
select is(pg_temp.yearly('y1', (select id from hp), 365, '00000000-0000-0000-0000-0000000049a1') ->> 'outcome',
  'granted', 'Pia buys the yearly plan');
select is(pg_temp.premium((select id from hp)), 'yearly 365', 'the household has yearly premium for a year');
select is(public.household_has_premium((select id from hp)), true, 'household_has_premium says yes');
select is(public.household_has_premium((select id from hq)), false, 'Quinn''s household has none');

-- Members read source, end and renewal, never the buyer.
select pg_temp.login('00000000-0000-0000-0000-0000000049b1');
select results_eq(
  $$ select premium_source, auto_renew, round(extract(epoch from expires_at - now()) / 86400)::int
     from public.entitlements $$,
  $$ values ('yearly'::text, true, 365) $$, 'Paul reads the plan''s source, renewal and end');
select throws_ok($$ select granted_by from public.entitlements $$, '42501', null, 'not who pays');
select throws_ok($$ select * from public.household_premium((select id from hp)) $$, '42501', null,
  'members cannot call the server check');
select throws_ok($$ select public.household_has_premium((select id from hp)) $$, '42501', null,
  'nor household_has_premium');
select pg_temp.login('00000000-0000-0000-0000-0000000049c1');
select is((select count(*)::int from public.entitlements), 0, 'Quinn reads none of their rows');

-- Only the subscriber learns of the plan's billing.
select pg_temp.login('00000000-0000-0000-0000-0000000049a1');
select is(public.my_yearly_plan() - 'until',
  '{"subscriber": true, "renewing": true, "billing_issue": false, "elsewhere": false, "household_billed": true}'::jsonb,
  'Pia is the subscriber of her household''s plan');
select pg_temp.login('00000000-0000-0000-0000-0000000049b1');
select is(public.my_yearly_plan() - 'until',
  '{"subscriber": false, "renewing": false, "billing_issue": false, "elsewhere": false, "household_billed": true}'::jsonb,
  'Paul is not, but learns that the household''s plan is billed');
select pg_temp.as_postgres();

-- Lifecycle: cancel, uncancel, out of order, billing issue, expiry ------------------------------

select is(public.purchase_lifecycle('apple', 'y1', now(), now() + interval '365 days', false, null) ->> 'outcome',
  'updated', 'Pia turns auto-renew off');
select is(pg_temp.premium((select id from hp)), 'yearly 365', 'premium stays until the end');
select is((select auto_renew from public.entitlements where premium_source = 'yearly' and household_id = (select id from hp)), false,
  'members see that it will not renew');
select is(public.purchase_lifecycle('apple', 'y1', now() - interval '1 hour', now() - interval '1 day', false, false) ->> 'outcome',
  'stale', 'an older EXPIRATION after a newer event changes nothing');
select is(pg_temp.premium((select id from hp)), 'yearly 365', 'still premium');
select is(public.purchase_lifecycle('apple', 'y1', now() + interval '1 second', now() + interval '14 days', null, true) ->> 'outcome',
  'updated', 'a billing issue with a grace period');
select is(pg_temp.premium((select id from hp)), 'yearly 14', 'premium runs through the grace period');
select pg_temp.login('00000000-0000-0000-0000-0000000049a1');
select is((public.my_yearly_plan() ->> 'billing_issue')::boolean, true, 'Pia is told');
select pg_temp.login('00000000-0000-0000-0000-0000000049b1');
select is((public.my_yearly_plan() ->> 'billing_issue')::boolean, false, 'Paul is not');
select pg_temp.as_postgres();

-- RevenueCat sends CANCELLATION (BILLING_ERROR) with the period's end next to BILLING_ISSUE, in
-- any order; only BILLING_ISSUE has the grace period's end, and a cancellation never cuts it short.
select pg_temp.yearly('g1', (select id from hg), 0);
select is(public.purchase_lifecycle('apple', 'g1', now() + interval '1 second', now() + interval '14 days', null, true) ->> 'outcome',
  'updated', 'Gina''s renewal fails: a billing issue with a grace period');
select is(public.purchase_lifecycle('apple', 'g1', now() + interval '1 second', now() - interval '1 minute', false, null) ->> 'outcome',
  'updated', 'CANCELLATION (BILLING_ERROR) at the same event time');
select is(public.household_has_premium((select id from hg)), true, 'premium stays in the grace period');
select is(pg_temp.premium((select id from hg)), 'yearly 14', 'until the grace period''s end');
select is(public.purchase_lifecycle('apple', 'g1', now() + interval '2 seconds', now() - interval '1 minute', false, null) ->> 'outcome',
  'updated', 'CANCELLATION (BILLING_ERROR) at a later event time');
select is(pg_temp.premium((select id from hg)), 'yearly 14', 'still until the grace period''s end');
select is((select auto_renew from public.purchases where transaction_id = 'g1'), false, 'the cancellation turns renewal off');
select is(public.purchase_lifecycle('apple', 'g1', now() + interval '3 seconds', now() - interval '1 minute', false, false) ->> 'outcome',
  'updated', 'EXPIRATION after the grace period');
select is(public.household_has_premium((select id from hg)), false, 'ends premium');

-- Integrations of the household, to show expiry touches none of them.
insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint, scopes)
values ((select id from hp), '00000000-0000-0000-0000-0000000049a1', 'Kurzbefehl', repeat('4', 64), '4949', '{read,write}');
insert into public.alexa_links (alexa_user_hash, session_id, user_id)
values (repeat('9', 64), gen_random_uuid(), '00000000-0000-0000-0000-0000000049b1');
create temp table before_expiry as
  select (select count(*) from public.personal_access_tokens where household_id = (select id from hp) and revoked_at is null) as pats,
         (select count(*) from public.alexa_links where user_id = '00000000-0000-0000-0000-0000000049b1') as alexa,
         (select count(*) from public.entitlements where household_id = (select id from hp)) as rows_;

select is(public.purchase_lifecycle('apple', 'y1', now() + interval '2 seconds', now() - interval '1 minute', false, false) ->> 'outcome',
  'updated', 'EXPIRATION');
select is(pg_temp.premium((select id from hp)), 'none', 'premium is off at read time');
select is(public.household_has_premium((select id from hp)), false, 'the server check says no');
select is(
  row((select count(*) from public.personal_access_tokens where household_id = (select id from hp) and revoked_at is null),
      (select count(*) from public.alexa_links where user_id = '00000000-0000-0000-0000-0000000049b1'),
      (select count(*) from public.entitlements where household_id = (select id from hp)))::text,
  (select row(pats, alexa, rows_)::text from before_expiry),
  'expiry deletes nothing: tokens, Alexa links and the unlock row stay');
select ok(exists (select from public.households where id = (select id from hp)), 'the household stays');

-- An end that passes without any event ends premium too (no cron).
select pg_temp.yearly('y2', (select id from hq), 30, '00000000-0000-0000-0000-0000000049c1');
update public.purchases set expires_at = now() - interval '1 second' where transaction_id = 'y2';
update public.entitlements set expires_at = now() - interval '1 second'
where purchase_id = (select id from public.purchases where transaction_id = 'y2');
select is(pg_temp.premium((select id from hq)), 'none', 'a missed EXPIRATION never leaves premium on');
select is(pg_temp.yearly('y2', (select id from hq), 365, null, now() + interval '3 seconds') ->> 'outcome',
  'restored', 'a late RENEWAL of the same transaction');
select is(pg_temp.premium((select id from hq)), 'yearly 365', 'brings it back');

-- H-56 for yearly: the same transaction never binds to another household.
select is(pg_temp.yearly('y2', (select id from hp), 365) ->> 'outcome', 'used_elsewhere',
  'Quinn''s plan does not bind to Pia''s household');
select is(pg_temp.premium((select id from hp)), 'none', 'Pia''s household gets nothing from it');
-- A RENEWAL under another App User ID (TRANSFER, an App User ID drift) still renews the plan where
-- it is bound: Quinn paid, her premium runs on.
select is(pg_temp.yearly('y2', (select id from hp), 400, null, now() + interval '3500 milliseconds') ->> 'outcome',
  'used_elsewhere', 'a RENEWAL of Quinn''s plan under Pia''s household id');
select is(pg_temp.premium((select id from hq)), 'yearly 400', 'renews Quinn''s plan in her household');
select is(pg_temp.premium((select id from hp)), 'none', 'and grants Pia''s household nothing');
select is(public.purchase_lifecycle('apple', 'nope', now(), now() + interval '1 year', true, false) ->> 'outcome',
  'unknown', 'a lifecycle event for an unknown transaction');
select is((select count(*)::int from public.purchases where transaction_id = 'nope'), 0, 'writes nothing');

-- A second yearly plan is its own row, never merged.
select is(pg_temp.yearly('y3', (select id from hq), 100) ->> 'second_yearly', 'true',
  'a second yearly plan while one is active is flagged');
select is((select count(*)::int from public.entitlements where household_id = (select id from hq) and premium_source = 'yearly'),
  2, 'both rows are kept');
select is(pg_temp.premium((select id from hq)), 'yearly 400', 'premium runs to the later end');

-- Lifetime and endless grants beat yearly ------------------------------------------------------

select is(pg_temp.lifetime('l1', (select id from hq)) ->> 'outcome', 'granted', 'Quinn buys Lifetime as well');
select is(pg_temp.premium((select id from hq)), 'lifetime', 'Lifetime wins, with no end');
select is(public.purchase_lifecycle('apple', 'y2', now() + interval '4 seconds', now() - interval '1 minute', false, false) ->> 'outcome',
  'updated', 'the yearly plan expires');
select is(pg_temp.premium((select id from hq)), 'lifetime', 'premium stays (Lifetime)');
select is(public.purchase_lifecycle('apple', 'l1', now(), null, false, false) ->> 'outcome', 'lifetime',
  'Lifetime has no lifecycle');

-- Tara, a tester, joins Pia's household while it has an active yearly plan again; RevenueCat grants
-- the household premium without end (20261101150000_testers_via_revenuecat.sql).
select pg_temp.yearly('y4', (select id from hp), 200);
select pg_temp.login('00000000-0000-0000-0000-0000000049a1');
create temp table inv2 as select code from public.create_invite((select id from hp));
grant select on inv2 to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000049d1');
select public.join_household((select code from inv2));
select pg_temp.as_postgres();
select is(public.promotional_premium_sync((select id from hp), true, null), 'granted',
  'the grant applies to a household with only a yearly plan');
select is(pg_temp.premium((select id from hp)), 'promotional', 'and wins over it');
select is(public.purchase_lifecycle('apple', 'y4', now() + interval '5 seconds', now() - interval '1 minute', false, false) ->> 'outcome',
  'updated', 'the yearly plan expires');
select is(pg_temp.premium((select id from hp)), 'promotional', 'the grant does not');

-- Refund and reinstate keep the yearly state.
select is(public.purchase_revoke('apple', 'y3', now(), 'com.hummlist.app.yearly', 'yearly', 'Production', null) ->> 'plan',
  'yearly', 'a refund of a yearly plan names its plan');
select is(pg_temp.yearly('y3', (select id from hq), 50, null, now() - interval '1 day') ->> 'outcome', 'revoked',
  'an older renewal of a refunded plan does not bring it back');
select is(pg_temp.yearly('y3', (select id from hq), 50, null, now() + interval '6 seconds') ->> 'outcome', 'restored',
  'a renewal after the refund (a new paid period) does');
select public.purchase_revoke('apple', 'y3', now() + interval '7 seconds', 'com.hummlist.app.yearly', 'yearly', 'Production', null);
select is(public.purchase_reinstate('apple', 'y3'), true, 'REFUND_REVERSED');
select ok((select expires_at > now() + interval '45 days' from public.entitlements
           where purchase_id = (select id from public.purchases where transaction_id = 'y3')),
  'the reinstated row has its end again');

-- The offer switch -----------------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000049b1');
select is(public.premium_offer(), false, 'the purchase offer is seeded off, and members may read it');
select throws_ok($$ select public.app_switch('premium_offer') $$, '42501', null, 'the switch table stays closed');
select pg_temp.as_postgres();
select ok(exists (select from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'entitlements'),
  'Realtime still publishes entitlements');

select * from finish();
rollback;
