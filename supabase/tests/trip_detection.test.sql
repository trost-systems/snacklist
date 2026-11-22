-- Job 352: detect_trips finds what job 351's final rule finds. Every finalRule case of
-- trip_sim/detect_test.ts (job 351's sim/detect_test.ts) on item_events rows, then reruns
-- (a late tick, a removed and an edited trip), voice and agent ticks, pg_cron's quiet rule and
-- learned households only. Privacy and the app's calls: trip_detection_privacy.test.sql.
begin;
select plan(94);

\set peter '''00000000-0000-0000-0000-000000352b01'''
\set lea '''00000000-0000-0000-0000-000000352b02'''
\set rewe '''00000000-0000-0000-0000-000000352e01'''
\set aldi '''00000000-0000-0000-0000-000000352e02'''
\set ikea '''00000000-0000-0000-0000-000000352e03'''
\set apo '''00000000-0000-0000-0000-000000352e04'''

insert into auth.users (id, email) values (:peter, 'peter352b@example.com'), (:lea, 'lea352b@example.com');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
insert into public.household_members (household_id, user_id, role) select id, :lea, 'member' from home;
insert into public.stores (id, household_id, name, sort_order)
select v.id, home.id, v.name, v.o from home,
  (values (:rewe::uuid, 'Rewe', 10), (:aldi::uuid, 'Aldi', 11), (:ikea::uuid, 'IKEA', 12),
          (:apo::uuid, 'Linden-Apotheke', 13)) v (id, name, o);
update public.households set order_mode = 'learned' where id = (select id from home);
-- Both have the detection switch on since long ago. Olga's app never showed it to her.
insert into public.trip_detection_settings (user_id, detect_ticks_from)
values (:peter, '-infinity'), (:lea, '-infinity');
\set olga '''00000000-0000-0000-0000-000000352b03'''
insert into auth.users (id, email) values (:olga, 'olga352b@example.com');
insert into public.household_members (household_id, user_id, role) select id, :olga, 'member' from home;

create function pg_temp.h() returns uuid language sql as $$ select id from home $$;
create function pg_temp.t0() returns timestamptz language sql as $$ select '2026-11-21 09:00:00+00'::timestamptz $$;

-- A tick as the sim writes one: [p_at] after t0 on the true clock, the device [p_skew] off, the
-- commit [p_server] after t0 (default a second after the tap), tap time stored within the bounds.
create function pg_temp.tick(
  p_at interval, p_key text, p_actor uuid default '00000000-0000-0000-0000-000000352b01',
  p_store uuid default '00000000-0000-0000-0000-000000352e01', p_kind text default 'bought',
  p_source text default 'app', p_server interval default null, p_skew interval default '0',
  p_left integer default 5
) returns void language plpgsql as $$
declare
  v_client timestamptz := pg_temp.t0() + p_at + p_skew;
  v_server timestamptz := pg_temp.t0() + coalesce(p_server, p_at + interval '1 second');
begin
  insert into public.item_events (household_id, item_id, action, item_name, actor, created_at,
    client_at, source, store_id, store_open_after)
  values (pg_temp.h(), md5(p_key)::uuid, p_kind, p_key, p_actor, v_server,
    case when v_server - v_client <= interval '7 days' and v_client - v_server <= interval '24 hours'
         then v_client end,
    p_source, p_store, p_left);
end $$;

-- [p_n] ticks [p_every] apart from [p_from], keys k<offset>.. (as letters: item keys drop digits).
create function pg_temp.run(
  p_n integer, p_every interval, p_from interval default '0', p_offset integer default 0,
  p_actor uuid default '00000000-0000-0000-0000-000000352b01',
  p_store uuid default '00000000-0000-0000-0000-000000352e01', p_source text default 'app',
  p_skew interval default '0', p_server interval default null, p_server_every interval default null
) returns void language plpgsql as $$
begin
  for i in 0 .. p_n - 1 loop
    perform pg_temp.tick(p_from + i * p_every, 'k' || chr(97 + p_offset + i), p_actor, p_store,
      p_source => p_source, p_skew => p_skew, p_server => p_server + i * p_server_every);
  end loop;
end $$;

create function pg_temp.reset() returns void language sql as $$
  delete from public.trips where household_id = pg_temp.h();
  delete from public.trip_sessions where household_id = pg_temp.h();
  delete from public.item_events where household_id = pg_temp.h();
  delete from public.trip_detection_state where household_id = pg_temp.h();
  delete from public.shop_declines where household_id = pg_temp.h();
  delete from public.item_order_memory where household_id = pg_temp.h();
$$;

create function pg_temp.detect() returns integer language sql as $$ select public.detect_trips(pg_temp.h()) $$;

-- The household's live detected trips: store, who, how many ticks, walked, start after t0, and
-- the steps of each walk ("6" one walk of six steps, "4|4" two walks).
create function pg_temp.trips()
returns table (store text, actors text, n integer, walked boolean, start interval, steps text)
language sql as $$
  select st.name,
    (select string_agg(case u when '00000000-0000-0000-0000-000000352b01' then 'peter'
                              when '00000000-0000-0000-0000-000000352b02' then 'lea' else 'olga' end, ','
       order by u) from unnest(s.detected_by) u),
    cardinality(s.tick_ids), s.walked, s.started_at - pg_temp.t0(),
    (select string_agg(jsonb_array_length(w -> 'steps')::text, '|' order by w ->> 'at') from jsonb_array_elements(s.walks) w)
  from public.trip_sessions s left join public.stores st on st.id = s.store_id
  where s.household_id = pg_temp.h() and s.source = 'detected' and s.removed_at is null
  order by s.started_at
$$;

create function pg_temp.summary() returns text language sql as $$
  select coalesce(string_agg(format('%s:%s:%s:%s', coalesce(t.store, '-'), t.n,
    case when t.walked then 'walk' else 'burst' end, coalesce(t.steps, '')), ' '), '')
  from pg_temp.trips() t
$$;

-- The rule (sim/detect_test.ts) ---------------------------------------------------------------

select pg_temp.run(6, '1 minute');
select is(pg_temp.detect(), 1, 'a walk: one trip written');
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'a walk is a trip that teaches its six steps');

select pg_temp.reset();
select pg_temp.run(10, '2 seconds');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:10:burst:', 'ticking everything at home afterwards: a trip in history, no walk');

select pg_temp.reset();
select pg_temp.run(4, '3 seconds');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'three or four quick ticks are no trip');

select pg_temp.reset();
select pg_temp.run(12, '10 seconds');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:12:burst:', 'a delivery unpacked, a tick every 10 s: a trip that teaches nothing');

select pg_temp.reset();
select pg_temp.run(5, '1 minute', p_store => :aldi);
select pg_temp.run(5, '1 minute', '7 minutes', 10);
select pg_temp.detect();
select is(pg_temp.summary(), 'Aldi:5:walk:5 Rewe:5:walk:5', 'two stores 3 minutes apart are two trips');

select pg_temp.reset();
select pg_temp.tick('0', 'bread', p_store => :aldi, p_left => 0);
select pg_temp.run(5, '1 minute', '4 minutes');
select pg_temp.detect();
select is(pg_temp.summary(), 'Aldi:1:walk: Rewe:5:walk:5', 'one item at a small store before the big one is its own trip (T3a)');

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.tick('4.5 minutes', 'candles', p_store => :ikea, p_left => 0);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'a lone item ticked 30 s after the walk: bought at Rewe, no IKEA trip');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.tick('6 minutes', 'kg', p_store => :aldi, p_left => 3);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:7:walk:7', 'a last tick tagged to a store with items left stays in the walk');

select pg_temp.reset();
select pg_temp.run(8, '90 seconds', p_server => '13 minutes', p_server_every => '400 milliseconds');
select pg_temp.run(3, '20 minutes', '2 hours', 20);
select pg_temp.detect();
select is((select steps from pg_temp.trips() where walked), '8',
  'offline: the commit times are a sync burst, the device times are the walk');

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_skew => '-1 hour');
select pg_temp.detect();
select is((select start from pg_temp.trips()), interval '1 second', 'a device clock an hour off is corrected by its usual offset');

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.tick('2 minutes 2 seconds', 'stray');
select pg_temp.tick('2 minutes 5 seconds', 'stray', p_kind => 'restored');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:5:walk:5', 'a stray tick undone within seconds does not count');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '15 minutes', 4);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:8:walk:4|4', 'a 12-minute wait at the deli is one trip, taught as two walks');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '5 hours', 4);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:4:walk:4 Rewe:4:walk:4', 'the same store again in the evening is a new trip');

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.run(3, '2 seconds', '20 minutes', 5);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:8:walk:5', 'catching up in the car joins the trip without teaching');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.run(2, '3 seconds', '2 minutes', 10, :lea);
select pg_temp.detect();
select is((select actors from pg_temp.trips()), 'peter', 'a partner ticking "we have that" at home stays out of the trip');

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.run(5, '70 seconds', '30 seconds', 10, :lea);
select pg_temp.detect();
select is((select format('%s %s %s', count(*), max(actors), max(steps)) from pg_temp.trips()), '1 peter,lea 5|5',
  'two people splitting the list in one store are one household trip, two walks');

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_source => 'voice');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'Siri and Alexa ticks never start a trip');

select pg_temp.reset();
select pg_temp.run(3, '1 minute');
select pg_temp.run(3, '1.5 seconds', '3 minutes', 3);
select pg_temp.run(2, '1 minute', '4 minutes', 6);
select pg_temp.detect();
select is((select string_agg(jsonb_array_length(st)::text, ',' order by o)
           from public.trip_sessions s, jsonb_array_elements(s.walks -> 0 -> 'steps') with ordinality as x (st, o)
           where s.household_id = pg_temp.h()), '1,1,1,3,1,1', 'neighbours ticked together are one step of the walk');
select is((select s.walks -> 0 -> 'steps' -> 3 from public.trip_sessions s where s.household_id = pg_temp.h()),
  '["kd", "ke", "kf"]'::jsonb, 'a step holds the keys ticked together');

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_store => :apo);
select pg_temp.detect();
select is(pg_temp.summary(), '', 'a pharmacy is never a trip and teaches nothing (GL-2)');

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_skew => '-1 hour', p_server => '20 minutes', p_server_every => '400 milliseconds');
select pg_temp.run(4, '3 hours', '2 hours', 10, p_skew => '-1 hour');
select pg_temp.detect();
select ok((select abs(extract(epoch from start)) <= 2 from pg_temp.trips() where walked order by start limit 1),
  'the clock offset comes from online ticks even when most ticks were offline');

select pg_temp.reset();
select pg_temp.run(4, '3 hours', p_skew => '1 hour');
select pg_temp.run(6, '1 minute', '10 days', 10);
select pg_temp.detect();
select is((select start from pg_temp.trips() where walked), interval '10 days 1 second',
  'the clock offset uses the last week only: a phone set right later is not shifted back');

select pg_temp.reset();
select pg_temp.run(2, '1 minute');
select pg_temp.tick('2 minutes', 'kc', p_left => 0);
select pg_temp.run(3, '1 minute', '3 minutes', 3);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'ticking the store''s last item does not end the trip');

select pg_temp.reset();
select pg_temp.run(6, '90 seconds', p_skew => '1 hour', p_server => '20 minutes', p_server_every => '400 milliseconds');
select pg_temp.run(4, '3 hours', '2 hours', 10, p_skew => '1 hour');
select pg_temp.detect();
select ok((select abs(extract(epoch from start)) <= 2 and steps = '6' from pg_temp.trips() where walked order by start limit 1),
  'a phone clock an hour ahead is corrected too, offline walks included');

select pg_temp.reset();
select pg_temp.run(6, '90 seconds', p_skew => '2 days', p_server => '20 minutes', p_server_every => '400 milliseconds');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:burst:', 'a tap time two days ahead falls back to the commit time: a sync burst');
select pg_temp.reset();
select pg_temp.run(6, '90 seconds', p_skew => '1 hour', p_server => '20 minutes', p_server_every => '400 milliseconds');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'an hour ahead lies within the bounds');

select pg_temp.reset();
select pg_temp.run(2, '1 minute');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'two slow steps at a store with items left are no walk');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '10 minutes', 4);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:8:walk:8', 'a 7-minute gap inside a walk keeps one walk');

select pg_temp.reset();
select pg_temp.run(6, '30 seconds');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'steps 30 s apart are a walk');

select pg_temp.reset();
select pg_temp.run(6, '90 seconds', p_server => '3 days', p_server_every => '400 milliseconds');
select pg_temp.run(4, '3 hours', '4 days', 10);
select pg_temp.detect();
select ok((select abs(extract(epoch from start)) <= 2 and steps = '6' from pg_temp.trips() where walked order by start limit 1),
  'a walk synced three days later keeps its tap times');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.run(6, '1 minute', '1 day', 0);
select pg_temp.run(6, '1 minute', '2 days', 0);
select pg_temp.run(6, '40 seconds', '3 days', 10);
select pg_temp.detect();
select is((select count(*)::int from public.trip_sessions s, jsonb_array_elements(s.walks) w
           where s.household_id = pg_temp.h()), 4,
  'every walk is stored, a shuffle too: the learner''s gate decides what it teaches');

-- Peter's answers (TD-Q1, TD-Q2, TD-Q5) -------------------------------------------------------

-- What the household's learned order holds: every place of every store.
create function pg_temp.order_memory() returns text language sql as $$
  select coalesce(string_agg(format('%s/%s/%s', m.store_id, m.item_key, m.position), ' '
    order by m.store_id, m.item_key), '') from public.item_order_memory m where m.household_id = pg_temp.h()
$$;
-- [p_actor]'s „Nein, nur abgehakt" for their latest tick of [p_key] (what decline_shop stores).
create function pg_temp.decline(p_key text, p_actor uuid default '00000000-0000-0000-0000-000000352b01')
returns void language sql as $$
  insert into public.shop_declines (household_id, user_id, tick_id)
  select pg_temp.h(), p_actor, max(e.id) from public.item_events e
  where e.household_id = pg_temp.h() and e.item_name = p_key and e.actor = p_actor and e.action = 'bought'
$$;

-- Items for the keys, so a walk has places to teach.
insert into public.items (id, household_id, name, store_id)
select md5('k' || chr(97 + n))::uuid, home.id, 'k' || chr(97 + n), :rewe from home, generate_series(0, 15) n;

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.detect();
select isnt(pg_temp.order_memory(), '', 'a walk teaches the learned order (so the checks below can see a change)');

select pg_temp.reset();
select pg_temp.run(4, '3 seconds');
select pg_temp.detect();
select is(pg_temp.summary() || '|' || pg_temp.order_memory(), '|', 'TD-Q1: four fast ticks are no trip and teach nothing');

select pg_temp.reset();
select pg_temp.run(5, '3 seconds');
select pg_temp.detect();
select is(pg_temp.summary() || '|' || pg_temp.order_memory(), 'Rewe:5:burst:|',
  'TD-Q1: exactly 5 fast ticks make a trip that teaches nothing');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '32 minutes', 4);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:8:walk:4|4', 'TD-Q2: the same store again 29 minutes after the last tick continues the trip');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '34 minutes', 4);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:4:walk:4 Rewe:4:walk:4', 'TD-Q2: 31 minutes after the last tick is a new trip');

select pg_temp.reset();
select pg_temp.run(5, '2 seconds');
select pg_temp.run(4, '1 minute', '12 minutes', 5);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:9:walk:4', 'TD-Q2: a burst, then a walk 12 minutes later: one trip, taught by the walk only');

select pg_temp.reset();
select pg_temp.run(3, '2 seconds');
select pg_temp.run(4, '1 minute', '12 minutes', 3);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:7:walk:4', 'TD-Q2: three quick ticks at the door, then a walk: one trip with all seven');

select pg_temp.reset();
select pg_temp.run(6, '2 seconds');
select pg_temp.run(6, '2 seconds', '15 minutes', 6);
select pg_temp.detect();
select is(pg_temp.summary() || '|' || pg_temp.order_memory(), 'Rewe:12:burst:|',
  'TD-Q2: two bursts 15 minutes apart are one trip that teaches nothing');

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.run(3, '2 seconds', '33 minutes', 5);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:8:walk:5', 'TD-Q2: a walk, then a burst 29 minutes later: one trip, taught by the walk only');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.decline('ka');
select pg_temp.detect();
select is(pg_temp.summary() || '|' || pg_temp.order_memory(), '|',
  'TD-Q5: a run answered „Nein, nur abgehakt" is no trip, no walk and no change in the learned order');
select is((select count(*)::int from public.trip_sessions s where s.household_id = pg_temp.h()), 0,
  'TD-Q5: nothing of it is stored as a trip');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.run(4, '1 minute', '10 minutes', 4);
select pg_temp.decline('ke');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:4:walk:4', 'TD-Q5: a declined run joins no trip: the walk before it stays as it was');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.decline('ka');
select pg_temp.run(4, '1 minute', '32 minutes', 4);
select pg_temp.detect();
select is(pg_temp.summary(), '', 'TD-Q5: ticks within 30 minutes of the declined run belong to it');

select pg_temp.reset();
select pg_temp.run(4, '1 minute');
select pg_temp.decline('ka');
select pg_temp.run(4, '1 minute', '34 minutes', 4);
select pg_temp.detect();
select is((select string_agg(format('%s %s', n, start), ', ' order by start) from pg_temp.trips()), '4 00:34:01',
  'TD-Q5: a run after a gap of more than 30 minutes is detected');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.run(5, '70 seconds', '30 seconds', 10, :lea);
select pg_temp.decline('ka');
select pg_temp.detect();
select is((select string_agg(format('%s %s %s', actors, n, steps), ', ' order by start) from pg_temp.trips()), 'lea 5 5',
  'TD-Q5: Peter''s „Nein" leaves Lea''s walk alongside him detected, without his ticks');

-- decline_shop, the app's call.
\set otto '''00000000-0000-0000-0000-000000352b04'''
insert into auth.users (id, email) values (:otto, 'otto352b@example.com');
select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'detected before the answer arrives');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
select lives_ok($$ select public.decline_shop(md5('ka')::uuid, now()) $$, 'TD-Q5: Peter answers „Nein, nur abgehakt"');
select lives_ok($$ select public.decline_shop(md5('ka')::uuid, now()) $$, 'TD-Q5: and the retry of the same answer');
select set_config('request.jwt.claims', jsonb_build_object('sub', :otto, 'role', 'authenticated')::text, true);
select throws_ok($$ select public.decline_shop(md5('ka')::uuid, now()) $$, 'P0002', 'item_not_found',
  'TD-Q5: someone outside the household cannot decline its shops');
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
select is((select format('%s %s', count(*), bool_and(d.tick_id = e.id and d.user_id = :peter and d.client_at is not null))
           from public.shop_declines d, public.item_events e
           where d.household_id = pg_temp.h() and e.household_id = pg_temp.h() and e.item_name = 'ka' and e.action = 'bought'),
  '1 t', 'TD-Q5: decline_shop stores one answer, for Peter''s tick, idempotent');
select ok(pg_temp.h() in (select public.detect_due_households()),
  'TD-Q5: an answer after a run makes the household due again');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'TD-Q5: and the next run takes the trip back');

select pg_temp.reset();
update public.households set order_mode = 'categories' where id = pg_temp.h();
select pg_temp.run(1, '1 minute');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
select public.decline_shop(md5('ka')::uuid, now());
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.shop_declines d where d.household_id = pg_temp.h()), 0,
  'TD-Q5: a decline in a household that sorts by categories stores nothing');
update public.households set order_mode = 'learned' where id = pg_temp.h();
select ok(exists (select from cron.job where jobname = 'purge-shop-declines' and command = 'select public.purge_shop_declines()'),
  'TD-Q5: pg_cron purges the answers daily');
insert into public.shop_declines (household_id, user_id, tick_id, declined_at)
values (pg_temp.h(), :peter, 1, now() - interval '15 days 1 minute'), (pg_temp.h(), :peter, 2, now() - interval '14 days');
select public.purge_shop_declines();
select is((select array_agg(tick_id) from public.shop_declines d where d.household_id = pg_temp.h()), array[2::bigint],
  'TD-Q5: an answer goes after 15 days');
delete from public.items where household_id = pg_temp.h();

-- What a detected trip holds ---------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.detect();
select is((select format('%s %s %s %s %s %s', s.source, s.end_reason, s.currency, s.active_seconds,
             s.shopped_on, s.started_by = :peter)
           from public.trip_sessions s where s.household_id = pg_temp.h()),
  'detected auto EUR 300 2026-11-21 t', 'a detected trip: source, end, currency, duration, day, starter');
select is((select jsonb_agg(l ->> 'key' order by o) from public.trip_sessions s,
             jsonb_array_elements(s.lines) with ordinality as x (l, o) where s.household_id = pg_temp.h()),
  '["ka", "kb", "kc", "kd", "ke", "kf"]'::jsonb, 'its lines are the ticked items in tick order');
select ok((select bool_and((l -> 'bought')::boolean and (l -> 'planned')::boolean and l ->> 'store_name' = 'Rewe')
           from public.trip_sessions s, jsonb_array_elements(s.lines) l where s.household_id = pg_temp.h()),
  'bought, planned, at the trip''s store');
select is((select format('%s %s %s', t.store_name, jsonb_array_length(t.items), t.logged_by is null)
           from public.trips t where t.household_id = pg_temp.h()),
  'Rewe 6 t', 'and one log row, as trip mode writes it, logged by nobody');
select is((select w ->> 'store_id' from public.trip_sessions s, jsonb_array_elements(s.walks) w
           where s.household_id = pg_temp.h()), :rewe, 'its walk names the store');
select is((select (w ->> 'at')::timestamptz from public.trip_sessions s, jsonb_array_elements(s.walks) w
           where s.household_id = pg_temp.h()), pg_temp.t0() + interval '1 second',
  'and starts at the first tap, on the server''s clock');

-- Reruns ----------------------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.detect();
select pg_temp.tick('5 minutes', 'kf', p_server => '30 minutes');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'a late tick of the trip: the rerun leaves one trip, with it');
select is((select count(*)::int from public.trips t where t.household_id = pg_temp.h()), 1, 'and one log row');
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'a rerun without new ticks changes nothing');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.detect();
select public.detect_remove(pg_temp.h(), (select id from public.trip_sessions where household_id = pg_temp.h()));
select pg_temp.tick('7 minutes', 'kg', p_server => '40 minutes');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'a removed trip stays removed after a rerun, and its ticks find no new trip');
select is((select format('%s %s %s', lines, walks, removed_at is not null) from public.trip_sessions s
           where s.household_id = pg_temp.h()), '[] [] t', 'it is a tombstone without lines or walks');
select is((select count(*)::int from public.trips t where t.household_id = pg_temp.h()), 0, 'without log rows');

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
select pg_temp.detect();
update public.trip_sessions set frozen_at = now() where household_id = pg_temp.h();
create temp table frozen as select id, tick_ids from public.trip_sessions where household_id = pg_temp.h();
select pg_temp.run(4, '1 minute', '7 minutes', 6, p_server => '50 minutes', p_server_every => '1 second');
select pg_temp.detect();
select is((select s.tick_ids from public.trip_sessions s join frozen f using (id)), (select tick_ids from frozen),
  'an edited (frozen) trip keeps its ticks');
select is(pg_temp.summary(), 'Rewe:6:walk:6 Rewe:4:walk:4',
  'and the later ticks make a trip of their own instead of joining it');

-- Sources -------------------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(3, '1 minute');
select pg_temp.tick('3 minutes', 'agent', p_source => 'agent');
select pg_temp.tick('3 minutes 30 seconds', 'siri', p_source => 'voice');
select pg_temp.run(3, '1 minute', '4 minutes', 3);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'agent and voice ticks inside a walk neither teach nor break it');
select ok(not exists (select from public.trip_sessions s, jsonb_array_elements(s.walks -> 0 -> 'steps') st
                      where s.household_id = pg_temp.h() and st ?| array['agent', 'siri']),
  'their keys are in no step');

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_source => 'agent');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'agent ticks alone make no trip');

-- Trip mode ------------------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(6, '1 minute');
insert into public.trip_sessions (id, household_id, started_by, started_at, ended_at, active_seconds,
  end_reason, source, currency, shopped_on)
values ('00000000-0000-0000-0000-000000352c01', pg_temp.h(), :peter, pg_temp.t0() - interval '1 minute',
  pg_temp.t0() + interval '10 minutes', 600, 'user', 'manual', 'EUR', '2026-11-21');
select pg_temp.detect();
select is(pg_temp.summary(), '', 'ticks of a trip-mode trip''s starter during it make no detected trip');
select is((select jsonb_array_length(walks -> 0 -> 'steps') from public.trip_sessions
           where id = '00000000-0000-0000-0000-000000352c01'), 6, 'they are the trip-mode trip''s walk');

-- pg_cron --------------------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(6, '1 minute', now() - pg_temp.t0() - interval '20 minutes');
select is(public.detect_due_trips() >= 1, true, 'detect_due_trips runs a household quiet for 10 minutes');
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'and detects its trip');
select is((select detected_through from public.trip_detection_state where household_id = pg_temp.h()),
  (select max(created_at) from public.item_events where household_id = pg_temp.h()), 'up to its newest tick');
select pg_temp.tick(now() - pg_temp.t0() - interval '2 minutes', 'kz');
delete from public.trip_sessions where household_id = pg_temp.h();
select public.detect_due_trips();
select is(pg_temp.summary(), '', 'a household with a tick in the last 10 minutes waits');
update public.item_events set created_at = created_at - interval '9 minutes'
where household_id = pg_temp.h() and item_name = 'kz';
select public.detect_due_trips();
select isnt(pg_temp.summary(), '', 'and is detected once it has been quiet for 10 minutes');
select ok(exists (select from cron.job where jobname = 'detect-trips' and schedule = '*/5 * * * *'
                  and command = 'call public.detect_due_trips_each()'),
  'pg_cron runs it every 5 minutes, a commit after each household');

-- Who is detected (N-319) ---------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(6, '1 minute', p_actor => :olga);
select pg_temp.detect();
select is(pg_temp.summary(), '', 'someone whose app never showed the switch is not detected');
select pg_temp.run(6, '1 minute', '1 minute 30 seconds', 10, :peter);
select pg_temp.detect();
select is((select format('%s %s', actors, n) from pg_temp.trips()), 'peter 6',
  'their ticks stay out of a trip ticked alongside them');

-- The window -----------------------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(6, '1 minute', '-20 days');
select pg_temp.run(6, '1 minute', '0', 10);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'a run looks back no more than 14 days before the newest tick');

select pg_temp.reset();
update public.households set order_mode = 'categories' where id = pg_temp.h();
select pg_temp.run(6, '1 minute', now() - pg_temp.t0() - interval '1 hour');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
select public.set_order_mode(pg_temp.h(), 'learned');
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
select pg_temp.detect();
select is(pg_temp.summary(), '', 'ticks from before the household switched to the learned order are never detected');
select pg_temp.run(6, '1 minute', now() - pg_temp.t0() + interval '1 minute', 10);
select pg_temp.detect();
select is(pg_temp.summary(), 'Rewe:6:walk:6', 'ticks after the switch are');

-- Ids and the household row --------------------------------------------------------------------------

select pg_temp.reset();
select pg_temp.run(5, '1 minute');
select pg_temp.detect();
create temp table first_id as select id from public.trip_sessions where household_id = pg_temp.h() and source = 'detected';
create temp table household_row as select ctid::text as x from public.households where id = pg_temp.h();
select pg_temp.tick('5 minutes', 'kf', p_server => '30 minutes');
select pg_temp.detect();
select is((select array_agg(id) from public.trip_sessions where household_id = pg_temp.h() and source = 'detected'),
  (select array_agg(id) from first_id), 'a rerun that finds the trip again keeps its id');
select is((select session_id from public.trips where household_id = pg_temp.h()), (select id from first_id),
  'and its log row''s');
select pg_temp.run(6, '1 minute', '5 hours', 10, p_server => '6 hours', p_server_every => '1 second');
select pg_temp.detect();
select is((select id from public.trip_sessions where household_id = pg_temp.h() and source = 'detected'
           order by started_at limit 1), (select id from first_id), 'so does one that adds another trip');
select pg_temp.run(4, '1 minute', '10 minutes', 20, p_server => '7 hours', p_server_every => '1 second');
select pg_temp.detect();
select is((select format('%s %s', s.id = f.id, cardinality(s.tick_ids)) from public.trip_sessions s, first_id f
           where s.household_id = pg_temp.h() and s.source = 'detected' order by s.started_at limit 1),
  't 10', 'and one that grows it: the trip with most of its ticks keeps the id');
select is((select ctid::text from public.households where id = pg_temp.h()), (select x from household_row),
  'runs never write the household row (members read it, realtime sends it)');

-- Learned households only ------------------------------------------------------------------------

select pg_temp.reset();
update public.households set order_mode = 'categories' where id = pg_temp.h();
select pg_temp.run(6, '1 minute', now() - pg_temp.t0() - interval '20 minutes');
select public.detect_due_trips();
select is(pg_temp.detect(), 0, 'a household that sorts by categories is not detected');
select is(pg_temp.summary(), '', 'and has no detected trip');

select * from finish();
rollback;
