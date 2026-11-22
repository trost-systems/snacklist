-- Job 352: what detected trips may show and to whom (Legal N-319, N-320, N-321), the tick path
-- (set_item_status), removal, export, leaving, and outsiders. The rule itself:
-- trip_detection.test.sql.
begin;
select plan(81);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

\set peter '''00000000-0000-0000-0000-000000352d01'''
\set lea '''00000000-0000-0000-0000-000000352d02'''
\set olaf '''00000000-0000-0000-0000-000000352d03'''
\set kim '''00000000-0000-0000-0000-000000352d04'''
\set ute '''00000000-0000-0000-0000-000000352d05'''
\set rewe '''00000000-0000-0000-0000-000000352f01'''
\set apo '''00000000-0000-0000-0000-000000352f02'''

insert into auth.users (id, email) values (:peter, 'peter352d@example.com'), (:lea, 'lea352d@example.com'),
  (:olaf, 'olaf352d@example.com'), (:kim, 'kim352d@example.com'), (:ute, 'ute352d@example.com');
select pg_temp.login(:peter);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select pg_temp.login(:olaf);
create temp table away as select id from public.create_household(gen_random_uuid(), 'Olafs');
select pg_temp.logout();
insert into public.household_members (household_id, user_id, role)
select id, u, 'member' from home, unnest(array[:lea, :kim, :ute]::uuid[]) u;
-- Peter, Lea and Kim have had the detection switch in front of them since long ago; Ute's app has
-- not shown it yet.
insert into public.trip_detection_settings (user_id, detect_ticks_from)
select u, '-infinity' from unnest(array[:peter, :lea, :kim]::uuid[]) u;
insert into public.stores (id, household_id, name, sort_order)
select v.id, home.id, v.name, v.o from home, (values (:rewe::uuid, 'Rewe', 10), (:apo::uuid, 'Apotheke am Markt', 11)) v (id, name, o);
update public.households set order_mode = 'learned' where id in (select id from home union select id from away);
grant select on home, away to authenticated;

create function pg_temp.h() returns uuid language sql as $$ select id from home $$;
-- Two days ago at 09:00 UTC.
create function pg_temp.t0() returns timestamptz language sql as $$
  select date_trunc('day', now() - interval '2 days') + interval '9 hours'
$$;
create function pg_temp.run(p_n integer, p_from interval, p_actor uuid, p_offset integer default 0,
  p_store uuid default '00000000-0000-0000-0000-000000352f01', p_created timestamptz default null)
returns void language plpgsql as $$
begin
  for i in 0 .. p_n - 1 loop
    insert into public.item_events (household_id, item_id, action, item_name, actor, created_at,
      client_at, source, store_id, store_open_after)
    values (pg_temp.h(), md5('k' || chr(97 + p_offset + i))::uuid, 'bought', 'k' || chr(97 + p_offset + i), p_actor,
      coalesce(p_created, pg_temp.t0() + p_from + i * interval '1 minute' + interval '1 second'),
      pg_temp.t0() + p_from + i * interval '1 minute', 'app', p_store, 5);
  end loop;
end $$;
create function pg_temp.detect() returns integer language sql security definer as $$
  select public.detect_trips(pg_temp.h())
$$;
-- The household's live detected trips as "who:ticks", by start.
create function pg_temp.detected() returns text language sql security definer as $$
  select coalesce(string_agg(
    coalesce((select string_agg(case u when '00000000-0000-0000-0000-000000352d01' then 'peter'
                              when '00000000-0000-0000-0000-000000352d02' then 'lea'
                              when '00000000-0000-0000-0000-000000352d05' then 'ute' else 'kim' end, '+' order by u)
     from unnest(s.detected_by) u), '') || ':' || cardinality(s.tick_ids), ' ' order by s.started_at), '')
  from public.trip_sessions s
  where s.household_id = pg_temp.h() and s.source = 'detected' and s.removed_at is null
$$;
create function pg_temp.trip_of(p_actor uuid) returns uuid language sql security definer as $$
  select s.id from public.trip_sessions s
  where s.household_id = pg_temp.h() and s.source = 'detected' and s.removed_at is null
    and p_actor = any(s.detected_by) order by s.started_at limit 1
$$;
create function pg_temp.events() returns setof public.item_events language sql security definer as $$
  select * from public.item_events
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- The tick path ---------------------------------------------------------------------------------

select pg_temp.login(:peter);
insert into public.items (household_id, name, store_id) select id, 'Brot', :rewe from home;
insert into public.items (household_id, name, store_id) select id, 'Milch', :rewe from home;
create temp table brot as select id from public.items where name = 'Brot' and household_id = (select id from home);
grant select on brot to authenticated;
select is((public.set_item_status((select id from brot), 'bought', now() - interval '6 days')).status, 'bought',
  'set_item_status ticks an item and returns it');
select is((select format('%s %s %s %s', e.source, e.client_at = now() - interval '6 days', e.store_id = :rewe, e.store_open_after)
           from pg_temp.events() e where e.item_id = (select id from brot) and e.action = 'bought'),
  'app t t 1', 'the tick keeps source, a tap time 6 days back, the store and the open items left');
select public.set_item_status((select id from brot), 'bought', now() - interval '6 days');
select is((select count(*)::int from pg_temp.events() e where e.item_id = (select id from brot) and e.action = 'bought'), 1,
  'the same call twice ticks once');
select public.set_item_status((select id from brot), 'active', now() - interval '8 days');
select is((select format('%s %s', e.source, e.client_at is null) from pg_temp.events() e
           where e.item_id = (select id from brot) and e.action = 'restored'), 'app t',
  'a tap time more than 7 days back is not kept');
select public.set_item_status((select id from brot), 'bought', now() + interval '23 hours');
select ok((select e.client_at = now() + interval '23 hours' from pg_temp.events() e
           where e.item_id = (select id from brot) and e.action = 'bought' order by e.id desc limit 1),
  'a tap time 23 hours ahead is kept');
select public.set_item_status((select id from brot), 'active', now() + interval '25 hours');
select ok((select e.client_at is null from pg_temp.events() e
           where e.item_id = (select id from brot) and e.action = 'restored' order by e.id desc limit 1),
  'one 25 hours ahead is not');
update public.items set status = 'bought' where name = 'Milch' and household_id = (select id from home);
select is((select format('%s %s', e.source, e.client_at is null) from pg_temp.events() e
           where e.item_name = 'Milch' and e.action = 'bought'), 'app t',
  'an older app''s plain update is an app tick without a tap time');
select set_config('fg.tick_source', 'agent', true);
update public.items set status = 'active' where name = 'Milch' and household_id = (select id from home);
select set_config('fg.tick_source', '', true);
select is((select e.source from pg_temp.events() e where e.item_name = 'Milch' and e.action = 'restored'), 'agent',
  'an edge function names its source');
select is((select e.source from pg_temp.events() e where e.item_name = 'Milch' and e.action = 'added'), null,
  'other events carry no source');
select throws_ok($$ select public.set_item_status(gen_random_uuid(), 'bought') $$, 'P0002', 'item_not_found',
  'an unknown item is not found');
select throws_ok($$ select public.set_item_status((select id from brot), 'gone') $$, '22023', 'invalid_status',
  'a status is active or bought');

-- N-319: tap times only of people with detection on, who have seen the switch -------------------

select pg_temp.login(:ute);
insert into public.items (household_id, name, store_id) select id, 'Tee', :rewe from home;
select pg_temp.logout();
create temp table tee as select id from public.items where name = 'Tee' and household_id = (select id from home);
grant select on tee to authenticated;
create function pg_temp.tee_tick(p_action text) returns text language sql security definer as $$
  select format('%s %s', e.source, e.client_at is not null) from public.item_events e
  where e.item_id = (select id from tee) and e.action = p_action order by e.id desc limit 1
$$;
grant execute on function pg_temp.tee_tick(text) to authenticated;
select pg_temp.login(:ute);
select public.set_item_status((select id from tee), 'bought', now() - interval '1 minute');
select is(pg_temp.tee_tick('bought'), 'app f', 'a tick of someone whose app never showed the switch keeps no tap time');
select is(public.my_trip_detection() - 'first_trip', '{"on": true, "card_seen": false}'::jsonb,
  'the app''s first call, as it shows the switch, turns detection on');
select public.set_item_status((select id from tee), 'active', now() - interval '1 minute');
select is(pg_temp.tee_tick('restored'), 'app t', 'from then on a tick keeps its tap time');
select public.set_trip_detection(false);
select public.set_item_status((select id from tee), 'bought', now() - interval '1 minute');
select is(pg_temp.tee_tick('bought'), 'app f', 'switched off, a tick keeps none; the source stays');
select public.set_trip_detection(true);

-- N-321: no direct read of item_events, suggest_items for members only -------------------------

select throws_ok($$ select from public.item_events $$, '42501', null, 'a member cannot read item_events');
select lives_ok($$ select * from public.suggest_items((select id from home)) $$, 'a member still gets usuals');
select pg_temp.login(:peter);
insert into public.items (household_id, name) select id, 'Käse' from home;
select public.set_item_status((select id from public.items where name = 'Käse' and household_id = (select id from home)), 'bought');
select is(
  (select array_agg((s.name, s.uses, s.last_used)::text order by s.name)
   from public.suggest_items((select id from home), '', 200, now() - interval '1 minute') s),
  (select array_agg((s.name, s.uses, s.last_used)::text order by s.name)
   from public.suggest_items((select id from home), '', 200) s),
  'a member''s p_now is ignored: no clock to walk back the household''s tick times with');
select ok((select count(*) > 0 and bool_and(s.last_used = date_trunc('day', s.last_used, 'Europe/Berlin'))
           from public.suggest_items((select id from home), '', 200) s),
  'and last_used comes to the day');
select pg_temp.login(:olaf);
select throws_ok($$ select * from public.suggest_items((select id from home)) $$, '42501', 'not_a_member',
  'an outsider gets not_a_member from suggest_items');
select throws_ok($$ select public.set_item_status((select id from brot), 'active') $$, 'P0002', 'item_not_found',
  'and cannot tick another household''s item');
select pg_temp.logout();

-- Detection, N-320: hidden from others until the detector saw the card --------------------------

select pg_temp.run(6, '0', :peter);
select pg_temp.run(6, '3 hours', :lea, 10);
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:6 lea:6', 'Peter''s and Lea''s walks are detected');

select pg_temp.login(:lea);
select throws_ok(format($$ select public.trip_session(%L, %L) $$, pg_temp.h(), pg_temp.trip_of(:peter)),
  'P0002', 'trip_not_found', 'Lea cannot open Peter''s trip before he saw the first-trip card');
select is((select count(*)::int from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips')),
  1, 'her history shows only her own detected trip');
select is((public.trip_session(pg_temp.h(), pg_temp.trip_of(:lea)) ->> 'mine')::boolean, true, 'which is hers');
select is(public.trip_history(pg_temp.h(), current_date) -> 'trips', '[]'::jsonb,
  'trip_history (older apps) shows no detected trip');

select pg_temp.login(:peter);
select is(public.my_trip_detection() - 'first_trip', '{"on": true, "card_seen": false}'::jsonb,
  'my_trip_detection: on, card not seen');
select is(public.my_trip_detection() -> 'first_trip',
  jsonb_build_object('id', pg_temp.trip_of(:peter), 'household_id', pg_temp.h(), 'store_name', 'Rewe'),
  'first_trip names his newest detected trip and its store');
select public.seen_detected_trip_card();
select is(public.my_trip_detection(), '{"on": true, "card_seen": true, "first_trip": null}'::jsonb,
  'after the card: seen, no first trip');

-- N-321: no clock times of others' detected trips -------------------------------------------------

select pg_temp.login(:lea);
select is((select format('%s %s %s %s', j ->> 'started_at', j ->> 'ended_at', j ->> 'pauses', j ->> 'mine')
           from public.trip_session(pg_temp.h(), pg_temp.trip_of(:peter)) j),
  '   false', 'Peter''s trip opens for Lea now, without start, end or pauses');
select is((select format('%s %s %s', j ->> 'source', j ->> 'walked', j -> 'detected_by')
           from public.trip_session(pg_temp.h(), pg_temp.trip_of(:peter)) j),
  format('detected true ["%s"]', :peter), 'with source, walked and who');
select is((select (t ->> 'created_at')::timestamptz from jsonb_array_elements(
             public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = pg_temp.trip_of(:peter)::text),
  (pg_temp.t0()::date)::timestamp at time zone 'UTC', 'in her history its log row is dated at midnight');
select ok((select (t ->> 'updated_at')::timestamptz = (pg_temp.t0()::date)::timestamp at time zone 'UTC'
             and t ->> 'session_source' = 'detected' and (t ->> 'walked')::boolean
           from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = pg_temp.trip_of(:peter)::text),
  'updated_at too; session_source and walked are there');
select ok((select (t ->> 'created_at')::timestamptz <> (pg_temp.t0()::date)::timestamp at time zone 'UTC'
           from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = pg_temp.trip_of(:lea)::text),
  'her own trip keeps its times');
select ok((public.trip_session(pg_temp.h(), pg_temp.trip_of(:lea)) ->> 'started_at') is not null,
  'and its start');
-- Two of Peter's trips on one day: their order in Lea's history must not tell which came first.
select pg_temp.logout();
select pg_temp.run(6, '2 hours', :peter, 20);
select pg_temp.detect();
create temp table same_day as
select t.id, row_number() over (order by t.id desc) as n from public.trips t join public.trip_sessions s on s.id = t.session_id
where s.household_id = pg_temp.h() and s.detected_by = array[:peter::uuid];
grant select on same_day to authenticated;
update public.trips t set created_at = pg_temp.t0() + case when d.n = 1 then interval '1 hour' else interval '5 hours' end
from same_day d where d.id = t.id;
select pg_temp.login(:lea);
select is((select jsonb_agg(t ->> 'id' order by o) from jsonb_array_elements(
             public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') with ordinality as x (t, o)
           where (t ->> 'id')::uuid in (select id from same_day)),
  (select jsonb_agg(id order by n) from same_day),
  'N-321: others'' detected trips of one day come in an order that tells nothing of their times');
select pg_temp.logout();
delete from public.item_events where household_id = pg_temp.h() and actor = :peter and item_name >= 'ku';
select pg_temp.detect();
select pg_temp.login(:lea);

select pg_temp.logout();
select throws_ok(format($$ update public.trip_sessions set source = 'manual' where id = %L $$, pg_temp.trip_of(:peter)),
  'P0002', 'trip_not_found', 'a save onto a detected trip''s id cannot turn it into a trip-mode trip');

-- GL-2: a trip-mode trip at a pharmacy teaches no walk ------------------------------------------

select pg_temp.logout();
select pg_temp.run(6, '6 hours', :kim, 0, :apo);
insert into public.trip_sessions (id, household_id, started_by, started_at, ended_at, active_seconds,
  end_reason, source, currency, shopped_on)
values ('00000000-0000-0000-0000-000000352c02', pg_temp.h(), :kim, pg_temp.t0() + interval '6 hours',
  pg_temp.t0() + interval '6 hours 10 minutes', 600, 'user', 'manual', 'EUR', current_date - 2);
select pg_temp.detect();
select is((select walks from public.trip_sessions where id = '00000000-0000-0000-0000-000000352c02'), '[]'::jsonb,
  'no walk at a pharmacy, from trip mode either');
select is(pg_temp.detected(), 'peter:6 lea:6', 'and no detected trip there');

-- Removing ("Kein Einkauf") ---------------------------------------------------------------------

select pg_temp.login(:olaf);
select throws_ok(format($$ select public.remove_detected_trip(%L) $$, pg_temp.trip_of(:lea)), '42501', 'not_a_member',
  'an outsider cannot remove a trip');
select throws_ok(format($$ select public.trip_session(%L, %L) $$, pg_temp.h(), pg_temp.trip_of(:lea)), '42501',
  'not_a_member', 'nor open one');
select throws_ok(format($$ select public.trip_history_v2(%L, current_date) $$, pg_temp.h()), '42501', 'not_a_member',
  'nor read the history');
select pg_temp.login(:kim);
select throws_ok($$ select public.remove_detected_trip('00000000-0000-0000-0000-000000352c02') $$, '22023',
  'not_detected', 'a trip-mode trip is not removed this way');
create temp table removed as select pg_temp.trip_of(:lea) as id;
grant select on removed to authenticated;
select lives_ok($$ select public.remove_detected_trip((select id from removed)) $$, 'any member removes a detected trip');
select lives_ok($$ select public.remove_detected_trip((select id from removed)) $$, 'twice is no error');
select pg_temp.login(:lea);
select throws_ok($$ select public.trip_session((select id from home), (select id from removed)) $$, 'P0002',
  'trip_not_found', 'a removed trip is not found');
select is((select count(*)::int from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = (select id from removed)::text), 0, 'nor in the history');
select pg_temp.logout();
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:6', 'and a rerun does not bring it back');

create temp table peters as select pg_temp.trip_of(:peter) as id;
grant select on peters to authenticated;
select pg_temp.login(:kim);
select lives_ok($$ select public.delete_trip((select md5(id::text || ':' || '00000000-0000-0000-0000-000000352f01')::uuid from peters)) $$,
  'deleting a detected trip''s log row');
select pg_temp.logout();
select ok((select removed_at is not null from public.trip_sessions where id = (select id from peters)),
  'removes the trip instead of deleting it');
select pg_temp.detect();
select is(pg_temp.detected(), '', 'so detection does not find it again');

-- N-319: the switch -------------------------------------------------------------------------------

delete from public.trip_sessions where household_id = pg_temp.h();
delete from public.item_events where household_id = pg_temp.h();
delete from public.trip_detection_state where household_id = pg_temp.h();
-- Peter and Lea split the list at Rewe (one household trip); Lea alone in the evening; and a
-- trip of hers she edited.
select pg_temp.run(5, '0', :peter);
select pg_temp.run(5, '30 seconds', :lea, 10);
select pg_temp.run(6, '5 hours', :lea, 0);
select pg_temp.run(6, '1 day', :lea, 0);
select pg_temp.run(6, '1 day 8 hours', :lea, 0);
insert into public.trip_sessions (id, household_id, started_by, started_at, ended_at, active_seconds,
  end_reason, source, currency, shopped_on)
values ('00000000-0000-0000-0000-000000352c03', pg_temp.h(), :lea, pg_temp.t0() + interval '1 day 8 hours',
  pg_temp.t0() + interval '1 day 8 hours 10 minutes', 600, 'user', 'manual', 'EUR', current_date - 1);
select pg_temp.detect();
select is(pg_temp.detected(), 'peter+lea:10 lea:6 lea:6', 'three detected trips, one of them shared');
select is(jsonb_array_length((select walks from public.trip_sessions where id = '00000000-0000-0000-0000-000000352c03')), 1,
  'and her trip-mode trip has its walk');
update public.trip_sessions set frozen_at = now()
where household_id = pg_temp.h() and source = 'detected' and started_at = (
  select max(started_at) from public.trip_sessions where household_id = pg_temp.h() and source = 'detected');
create function pg_temp.decline(p_actor uuid) returns void language sql security definer as $$
  insert into public.shop_declines (household_id, user_id, tick_id)
  select pg_temp.h(), p_actor, max(e.id) from public.item_events e
  where e.household_id = pg_temp.h() and e.actor = p_actor and e.action = 'bought'
$$;
create function pg_temp.declines(p_actor uuid) returns integer language sql security definer as $$
  select count(*)::int from public.shop_declines d where d.user_id = p_actor
$$;
select pg_temp.decline(:lea);
select pg_temp.login(:lea);
select public.set_trip_detection(false);
select is(public.my_trip_detection() ->> 'on', 'false', 'Lea switches detection off');
select pg_temp.logout();
select is(pg_temp.declines(:lea), 0, 'TD-Q5: switching detection off deletes her „Nein" answers');
select is(pg_temp.detected(), 'lea:6', 'her unedited trips go, the shared one too; the edited one stays');
select is((select walks from public.trip_sessions where id = '00000000-0000-0000-0000-000000352c03'), '[]'::jsonb,
  'her trip-mode trip loses its walk');
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:5 lea:6', 'the next run detects Peter''s part of the shared trip, without her');
select pg_temp.run(6, '1 day 3 hours', :lea, 0, p_created => now() - interval '1 hour');
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:5 lea:6', 'her ticks while off are not detected');
select pg_temp.login(:lea);
select public.set_trip_detection(true);
select is(public.my_trip_detection() ->> 'on', 'true', 'she switches it on again');
select pg_temp.logout();
delete from public.trip_detection_state where household_id = pg_temp.h();
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:5 lea:6', 'ticks from before the switch-on never come back');
select is((select walks from public.trip_sessions where id = '00000000-0000-0000-0000-000000352c03'), '[]'::jsonb,
  'nor does that walk');
select pg_temp.run(6, '1 day 5 hours', :lea, 0, p_created => now() + interval '1 minute');
select pg_temp.detect();
select is(pg_temp.detected(), 'peter:5 lea:6 lea:6', 'new ticks are detected again');

-- Export, leaving, account deletion ----------------------------------------------------------------

select pg_temp.decline(:lea);
select pg_temp.decline(:peter);
select pg_temp.login(:peter);
select is((select jsonb_agg(t ->> 'shopped_on') from jsonb_array_elements(public.export_my_data() -> 'trips_detected') t),
  jsonb_build_array((pg_temp.t0() at time zone 'Europe/Berlin')::date), 'the export lists the detected trips the user is in');
select is(public.export_my_data() -> 'trip_sessions_started', '[]'::jsonb, 'and not as trips they started');
select is(public.export_my_data() #>> '{trip_detection,on}', 'true', 'with the switch');
select pg_temp.login(:lea);
select is(jsonb_array_length(public.export_my_data() -> 'trips_detected'), 2, 'Lea''s export has her two');
select ok((select bool_and(h ? 'client_at' and h ? 'source') from jsonb_array_elements(public.export_my_data() -> 'history') h),
  'and her history the tap times and sources');
select is((select jsonb_agg(jsonb_build_object('h', d ->> 'household_id' = pg_temp.h()::text, 'name', d ? 'item_name',
             'ticked', d ? 'ticked_at', 'declined', d ? 'declined_at'))
           from jsonb_array_elements(public.export_my_data() #> '{trip_detection,shops_declined}') d),
  '[{"h": true, "name": true, "ticked": true, "declined": true}]'::jsonb,
  'TD-Q5: and her „Nein" answers: household, item, tick and answer times');
select public.leave_household(pg_temp.h());
select pg_temp.logout();
select is(pg_temp.detected(), 'peter:5 :6 :6', 'leaving takes Lea out of the detected trips');
select ok(not exists (select from public.trip_sessions where started_by = :lea), 'and out of started_by');
select is(pg_temp.declines(:lea), 0, 'TD-Q5: and deletes her „Nein" answers there');
select is(pg_temp.declines(:peter), 1, 'TD-Q5: not Peter''s');
select is(public.delete_account(:peter), 'kept', 'Peter deletes his account');
select is(pg_temp.detected(), ':5 :6 :6', 'which takes him out of them too');
select is(pg_temp.declines(:peter), 0, 'TD-Q5: and deletes his „Nein" answers');


-- N-319: Ute's ticks count from her app's first call on, none from before.
select pg_temp.run(6, '1 day 6 hours', :ute, 0);
select pg_temp.detect();
select is((select count(*)::int from public.trip_sessions where :ute = any(detected_by)), 0,
  'ticks from before the first call are never detected');
select pg_temp.run(6, '1 day 7 hours', :ute, 0, p_created => now() + interval '1 minute');
select pg_temp.detect();
select is((select count(*)::int from public.trip_sessions where :ute = any(detected_by)), 1, 'later ones are');

-- N-325: even with a client grant, a „Nein" answer stays with the person who gave it.
select pg_temp.logout();
insert into public.shop_declines (household_id, user_id, tick_id)
select id, u, 990360 from home, unnest(array[:kim, :ute]::uuid[]) u;
grant select on public.shop_declines to authenticated;
select pg_temp.login(:kim);
select is((select count(*)::int from public.shop_declines), 1, 'N-325: Kim sees one answer');
select is((select user_id from public.shop_declines), :kim::uuid, 'N-325: and it is his own');
select is((select count(*)::int from public.shop_declines where user_id = :ute), 0,
  'N-325: Ute''s answer in the same household stays hidden from him');
select pg_temp.logout();
revoke all on public.shop_declines from authenticated;

select * from finish();
rollback;
