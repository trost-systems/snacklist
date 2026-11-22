-- Job 352, review 0: pharmacy ticks stay out of every other store's trip, walk and order (GL-2); a
-- shared detected trip has no clock times for anyone and waits for every other detector's card
-- (N-320, N-321); switching off also clears tap times and "Kein Einkauf" tombstones (N-319); the
-- card alone switches nothing on; an OAuth client's tick is an agent's; members cannot read the
-- learned order; an edited log row freezes its detected trip.
begin;
select plan(26);

create function pg_temp.login(uid uuid, p_client text default null) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_strip_nulls(jsonb_build_object(
    'sub', uid, 'role', 'authenticated', 'client_id', p_client))::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

\set peter '''00000000-0000-0000-0000-000000352e01'''
\set lea '''00000000-0000-0000-0000-000000352e02'''
\set kim '''00000000-0000-0000-0000-000000352e03'''
\set ute '''00000000-0000-0000-0000-000000352e04'''
\set rewe '''00000000-0000-0000-0000-000000352e11'''
\set apo '''00000000-0000-0000-0000-000000352e12'''

insert into auth.users (id, email) values (:peter, 'peter352e@example.com'), (:lea, 'lea352e@example.com'),
  (:kim, 'kim352e@example.com'), (:ute, 'ute352e@example.com');
select pg_temp.login(:peter);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select pg_temp.logout();
insert into public.household_members (household_id, user_id, role)
select id, u, 'member' from home, unnest(array[:lea, :kim, :ute]::uuid[]) u;
-- Peter has not seen the first-trip card yet; Lea and Kim have. Ute's app never showed the switch.
insert into public.trip_detection_settings (user_id, detect_ticks_from, detected_card_at)
values (:peter, '-infinity', null), (:lea, '-infinity', now()), (:kim, '-infinity', now());
insert into public.stores (id, household_id, name, sort_order)
select v.id, home.id, v.name, v.o from home, (values (:rewe::uuid, 'Rewe', 10), (:apo::uuid, 'Apotheke am Markt', 11)) v (id, name, o);
update public.households set order_mode = 'learned' where id = (select id from home);
grant select on home to authenticated;

create function pg_temp.h() returns uuid language sql as $$ select id from home $$;
create function pg_temp.t0() returns timestamptz language sql as $$
  select date_trunc('day', now() - interval '2 days') + interval '9 hours'
$$;
-- [p_names] ticked by [p_actor] [p_gap] apart from t0 + [p_from], at Rewe but [p_pharmacy] at the pharmacy.
create function pg_temp.walk(p_actor uuid, p_from interval, p_names text[], p_pharmacy text default null,
  p_gap interval default '30 seconds') returns void language sql as $$
  insert into public.items (id, household_id, name, store_id)
  select md5(p_actor::text || n)::uuid, pg_temp.h(), n,
    case when n = p_pharmacy then '00000000-0000-0000-0000-000000352e12'::uuid
         else '00000000-0000-0000-0000-000000352e11'::uuid end
  from unnest(p_names) n;
  insert into public.item_events (household_id, item_id, action, item_name, actor, created_at, client_at, source,
    store_id, store_open_after)
  select pg_temp.h(), md5(p_actor::text || n)::uuid, 'bought', n, p_actor,
    pg_temp.t0() + p_from + (o - 1) * p_gap + interval '1 second', pg_temp.t0() + p_from + (o - 1) * p_gap, 'app',
    case when n = p_pharmacy then '00000000-0000-0000-0000-000000352e12'::uuid
         else '00000000-0000-0000-0000-000000352e11'::uuid end,
    cardinality(p_names) - o::int
  from unnest(p_names) with ordinality as x (n, o)
$$;
create function pg_temp.detect() returns integer language sql security definer as $$
  select public.detect_trips(pg_temp.h())
$$;
create function pg_temp.trip_of(p_by uuid[]) returns uuid language sql security definer as $$
  select s.id from public.trip_sessions s
  where s.household_id = pg_temp.h() and s.source = 'detected' and s.removed_at is null and s.detected_by = p_by
  order by s.started_at limit 1
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- Kim at Rewe with one pharmacy item in the middle of the walk; Peter and Lea at Rewe together;
-- Peter alone in the afternoon.
select pg_temp.walk(:kim, '0', array['Milch', 'Brot', 'Aspirin', 'Kaese', 'Eier', 'Apfel'], 'Aspirin');
select pg_temp.walk(:peter, '3 hours', array['Nudeln', 'Reis', 'Mehl', 'Zucker', 'Salz']);
select pg_temp.walk(:lea, '3 hours 15 seconds', array['Butter', 'Sahne', 'Quark', 'Joghurt', 'Kefir']);
select pg_temp.walk(:peter, '6 hours', array['Tee', 'Kaffee', 'Kakao', 'Honig']);
select pg_temp.detect();

-- GL-2 ---------------------------------------------------------------------------------------------

create temp table kims as select pg_temp.trip_of(array[:kim::uuid]) as id;
select is((select format('%s %s %s', s.store_id = :rewe, s.walked, cardinality(s.tick_ids))
           from public.trip_sessions s where s.id = (select id from kims)),
  't t 5', 'Kim''s walk at Rewe around the pharmacy item is still detected, from her five Rewe ticks');
select is((select count(*)::int from public.trip_sessions s, public.item_events e
           where s.household_id = pg_temp.h() and e.id = any(s.tick_ids) and e.store_id = :apo), 0,
  'no detected trip holds the pharmacy tick');
select is((select jsonb_path_query_array(s.walks, '$[*].steps[*][*]') from public.trip_sessions s where s.id = (select id from kims)),
  '["milch", "brot", "kas", "eier", "apfel"]'::jsonb, 'nor a step of the walk');
select is((select count(*)::int from public.item_order_memory m, public.items i
           where m.household_id = pg_temp.h() and m.store_id = :rewe and i.name = 'Aspirin'
             and m.item_key = public.item_order_key(nullif(i.canonical_key, ''), i.name)), 0,
  'and Rewe''s learned order has no place for it');
select is((select count(*)::int from public.trip_sessions s
           where s.household_id = pg_temp.h() and s.started_at = pg_temp.t0() + interval '1 minute'), 0,
  'nor does the pharmacy tick start a trip of its own');

-- N-320, N-321: a shared trip ---------------------------------------------------------------------

create temp table shared as select pg_temp.trip_of(array[:peter, :lea]::uuid[]) as id;
grant select on shared to authenticated;
select isnt((select id from shared), null, 'Peter''s and Lea''s ticks at Rewe are one shared trip');

select pg_temp.login(:lea);
select throws_ok($$ select public.trip_session((select id from home), (select id from shared)) $$, 'P0002',
  'trip_not_found', 'Lea cannot open the shared trip before Peter saw his first-trip card');
select is((select count(*)::int from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = (select id from shared)::text), 0, 'nor see it in her history');

select pg_temp.login(:peter);
select is((select format('%s|%s|%s|%s', j ->> 'started_at', j ->> 'ended_at', j ->> 'pauses', j ->> 'mine')
           from public.trip_session(pg_temp.h(), (select id from shared)) j),
  '|||true', 'Peter opens it (Lea saw her card), without start, end or pauses: they are Lea''s ticks too');
select is((select (t ->> 'created_at')::timestamptz from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = (select id from shared)::text),
  (pg_temp.t0()::date)::timestamp at time zone 'UTC', 'its log row is dated at midnight for him too');
select ok((public.trip_session(pg_temp.h(), pg_temp.trip_of(array[:peter::uuid])) ->> 'started_at') is not null,
  'his own trip keeps its start');
select is((select string_agg(format('%s:%s', t ->> 'with_others', t ->> 'started_at' is not null), ' ' order by t ->> 'shopped_on', t ->> 'with_others')
           from jsonb_array_elements(public.export_my_data() -> 'trips_detected') t),
  'false:t true:f', 'his export has the shared trip without its clock times, his own with them');
select ok((select bool_and(t -> 'created_at' = 'null' and t -> 'ended_at' = 'null' and t -> 'pauses' = 'null')
           from jsonb_array_elements(public.export_my_data() -> 'trips_detected') t where (t ->> 'with_others')::boolean),
  'no end, pauses or creation time either');
select is(public.my_trip_detection() #>> '{first_trip,id}', pg_temp.trip_of(array[:peter::uuid])::text,
  'his first-trip card names a trip he can open');
select public.seen_detected_trip_card();

select pg_temp.login(:lea);
select is((select format('%s|%s|%s|%s', j ->> 'started_at', j ->> 'ended_at', j ->> 'pauses', j ->> 'mine')
           from public.trip_session(pg_temp.h(), (select id from shared)) j),
  '|||true', 'once he has, Lea opens it, without clock times');
select is((select (t ->> 'updated_at')::timestamptz from jsonb_array_elements(public.trip_history_v2(pg_temp.h(), current_date) -> 'trips') t
           where t ->> 'session_id' = (select id from shared)::text),
  (pg_temp.t0()::date)::timestamp at time zone 'UTC', 'and in her history at midnight');

-- An edited log row freezes its trip -------------------------------------------------------------

select pg_temp.logout();
create temp table shared_row as select t.id, t.shopped_on from public.trips t where t.session_id = (select id from shared);
grant select on shared_row to authenticated;
select pg_temp.login(:lea);
select lives_ok($$ select public.save_trip((select id from home), (select id from shared_row),
    '00000000-0000-0000-0000-000000352e11', (select shopped_on from shared_row), '[{"name": "Brezeln"}]') $$,
  'Lea edits the shared trip in the history''s sheet');
select pg_temp.logout();
select ok((select frozen_at is not null from public.trip_sessions where id = (select id from shared)), 'which freezes it');
select pg_temp.walk(:peter, '1 day', array['Wasser', 'Saft', 'Bier', 'Wein']);
select pg_temp.detect();
select is((select t.items #>> '{0,name}' from public.trips t where t.session_id = (select id from shared)), 'Brezeln',
  'so the next run keeps her edit');

-- N-319: switching off clears tap times and tombstones ------------------------------------------

select pg_temp.walk(:lea, '9 hours', array['Lauch', 'Zwiebel', 'Knoblauch', 'Ingwer']);
select pg_temp.walk(:peter, '12 hours', array['Chips', 'Cola', 'Nuesse']);
select pg_temp.walk(:lea, '12 hours 10 seconds', array['Gurke', 'Paprika', 'Tomate']);
select pg_temp.detect();
create temp table tombs as
select pg_temp.trip_of(array[:lea::uuid]) as alone, pg_temp.trip_of(array[:peter, :lea]::uuid[]) as together;
select public.detect_remove(pg_temp.h(), alone) from tombs;
select public.detect_remove(pg_temp.h(), together) from tombs;
select pg_temp.login(:lea);
select public.set_trip_detection(false);
select pg_temp.logout();
select is((select count(*)::int from public.item_events where actor = :lea and client_at is not null), 0,
  'switching off clears the tap times of Lea''s ticks');
select is((select count(*)::int from public.trip_sessions where id = (select alone from tombs)), 0,
  'and deletes her "Kein Einkauf" tombstone');
select is((select detected_by from public.trip_sessions where id = (select together from tombs)), array[:peter::uuid],
  'a shared tombstone only loses her');

-- The card alone switches nothing on -------------------------------------------------------------

select pg_temp.login(:ute);
select lives_ok($$ select public.seen_detected_trip_card() $$, 'a card seen without a settings row');
select pg_temp.logout();
select ok(not public.trip_detection_on(:ute), 'does not switch detection on');

-- An OAuth client's tick is an agent's --------------------------------------------------------------

select pg_temp.login(:kim);
insert into public.items (household_id, name, store_id) select id, 'Senf', :rewe from home;
select pg_temp.login(:kim, 'mcp-client');
select public.set_item_status((select id from public.items where name = 'Senf'), 'bought', now());
select pg_temp.logout();
select is((select format('%s %s', source, client_at is null) from public.item_events where item_name = 'Senf' and action = 'bought'),
  'agent t', 'a tick by an app connected over OAuth is an agent''s, even through set_item_status');

-- The learned order is not for clients ----------------------------------------------------------

select pg_temp.login(:kim);
select throws_ok($$ select from public.item_order_memory $$, '42501', null, 'a member cannot read the learned order');

select * from finish();
rollback;
