-- Job 199: the grocery log. save_trip, delete_trip and trip_history (Free sees 4 weeks), the item
-- snapshot, and what happens to trips when a store, a member, an account or the household goes.
begin;
select plan(51);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- The table as stored, for checks while signed in (members read through trip_history only).
create function pg_temp.trips() returns setof public.trips language sql security definer as $$
  select * from public.trips
$$;

grant execute on all functions in schema pg_temp to authenticated;

\set lea '''00000000-0000-0000-0000-000000199a01'''
\set pia '''00000000-0000-0000-0000-000000199a02'''
\set kim '''00000000-0000-0000-0000-000000199a03'''
\set olaf '''00000000-0000-0000-0000-000000199a04'''
\set trip '''00000000-0000-0000-0000-000000199c01'''

insert into auth.users (id, email) values
  (:lea, 'lea199@example.com'), (:pia, 'pia199@example.com'),
  (:kim, 'kim199@example.com'), (:olaf, 'olaf199@example.com');

select pg_temp.login(:lea);
create temp table home as select id from public.create_household('Zuhause', false, '{Lidl}');
select pg_temp.login(:olaf);
create temp table away as select id from public.create_household('Olafs', false, '{Aldi}');
select pg_temp.logout();
insert into public.household_members (household_id, user_id, role)
select id, u, 'member' from home, unnest(array[:pia, :kim]::uuid[]) u;
create temp table lidl as
  select s.id from public.stores s join home h on s.household_id = h.id where s.name = 'Lidl';
create temp table aldi as
  select s.id from public.stores s join away a on s.household_id = a.id where s.name = 'Aldi';
grant select on home, away, lidl, aldi to authenticated;

-- Saving and editing.
select pg_temp.login(:lea);
select is(
  (select to_jsonb(t) - '{created_at,updated_at,id,household_id,store_id,logged_by,session_id}'::text[]
   from public.save_trip((select id from home), :trip, (select id from lidl), current_date - 1,
     '[{"name": "  Möhren ", "quantity": "1 kg"}, {"name": "Milch", "quantity": " "}]') t),
  jsonb_build_object('store_name', 'Lidl', 'shopped_on', current_date - 1, 'items', jsonb_build_array(
    jsonb_build_object('name', 'Möhren', 'quantity', '1 kg', 'canonical_key', public.canonical_key('Möhren')),
    jsonb_build_object('name', 'Milch', 'quantity', null, 'canonical_key', public.canonical_key('Milch')))),
  'save_trip returns the trip: store name snapshot, names trimmed, empty quantity null, canonical keys');
select ok((select bool_and(i ->> 'canonical_key' <> '') from pg_temp.trips() t, jsonb_array_elements(t.items) i
  where id = :trip), 'every item has its canonical key');
select is((select logged_by from pg_temp.trips() where id = :trip), :lea::uuid, 'the saver logged it');
select lives_ok(format($$ select public.save_trip(%L, %L, %L, current_date - 1,
    '[{"name": "  Möhren ", "quantity": "1 kg"}, {"name": "Milch", "quantity": " "}]') $$,
  (select id from home), :trip, (select id from lidl)), 'the same save again succeeds');
select is((select count(*)::int from pg_temp.trips() where household_id = (select id from home)), 1,
  'and leaves one trip');

select pg_temp.login(:pia);
select public.save_trip((select id from home), :trip, null, current_date, '[{"name": "Brot"}]');
select is((select (logged_by, store_id, store_name, shopped_on, items #>> '{0,name}')::text from pg_temp.trips() where id = :trip),
  (:lea::uuid, null::uuid, null::text, current_date, 'Brot')::text,
  'Pia''s edit replaces store, day and items and keeps Lea as the one who logged it');
select is(jsonb_array_length(public.trip_history((select id from home), current_date) -> 'trips'), 1,
  'a member reads the household''s trips through trip_history');
select throws_ok($$ select from public.trips $$, '42501', null, 'but not the table itself');

-- Refusals.
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date + 2, '[{"name": "X"}]') $$,
  (select id from home)), '22023', 'day_in_future', 'a day after tomorrow is refused');
select lives_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date + 1, '[{"name": "X"}]') $$,
  (select id from home)), 'tomorrow is allowed for time zones');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, '[]') $$,
  (select id from home)), '22023', 'no_items', 'an empty item list is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, null) $$,
  (select id from home)), '22023', 'no_items', 'no item list is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, '{"name": "X"}') $$,
  (select id from home)), '22023', 'no_items', 'an object instead of a list is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, '[{"name": "  "}]') $$,
  (select id from home)), '22023', 'invalid_item', 'a blank name is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, %L) $$,
  (select id from home), jsonb_build_array(jsonb_build_object('name', repeat('x', 121)))),
  '22023', 'invalid_item', 'a name over 120 characters is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, %L) $$,
  (select id from home), jsonb_build_array(jsonb_build_object('name', 'X', 'quantity', 2))),
  '22023', 'invalid_item', 'a quantity that is no text is refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, %L) $$,
  (select id from home), (select jsonb_agg(jsonb_build_object('name', 'X')) from generate_series(1, 201))),
  '22023', 'too_many_items', 'more than 200 items are refused');
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), %L, current_date, '[{"name": "X"}]') $$,
  (select id from home), (select id from aldi)), 'P0002', 'store_not_found',
  'another household''s store is refused');
select pg_temp.login(:olaf);
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, '[{"name": "X"}]') $$,
  (select id from home)), '42501', 'not_a_member', 'a non-member cannot log a trip');
select throws_ok(format($$ select public.save_trip(%L, %L, null, current_date, '[{"name": "X"}]') $$,
  (select id from away), :trip), '22023', 'other_household', 'nor take over a trip id of another household');
select throws_ok(format($$ select public.delete_trip(%L) $$, :trip), '42501', 'not_a_member',
  'nor delete another household''s trip');
select throws_ok(format($$ select public.trip_history(%L, current_date) $$, (select id from home)),
  '42501', 'not_a_member', 'nor read it');
select pg_temp.logout();
select throws_ok(format($$ select public.save_trip(%L, gen_random_uuid(), null, current_date, '[{"name": "X"}]') $$,
  (select id from home)), '28000', 'not_authenticated', 'signed out, nothing is saved');

-- The snapshot: a ticked item is logged, added again (the same row is reused), ticked again,
-- renamed and deleted. The trip keeps what was bought.
select pg_temp.login(:lea);
create temp table kaffee as
  with i as (insert into public.items (household_id, name, quantity) select id, 'Kaffee', '2' from home returning id)
  select id from i;
update public.items set status = 'bought' where id = (select id from kaffee);
select public.save_trip((select id from home), '00000000-0000-0000-0000-000000199c02', (select id from lidl), current_date,
  (select jsonb_agg(jsonb_build_object('name', i.name, 'quantity', i.quantity)) from public.items i where i.id = (select id from kaffee)));
update public.items set status = 'active' where id = (select id from kaffee);
select is((select (bought_at, bought_by)::text from public.items where id = (select id from kaffee)),
  (null::timestamptz, null::uuid)::text, 'adding a bought item again reuses its row and clears its bought time');
update public.items set status = 'bought' where id = (select id from kaffee);
select isnt((select bought_at from public.items where id = (select id from kaffee)), null,
  'ticking it again sets a new bought time on the same row');
update public.items set name = 'Tee', quantity = '1' where id = (select id from kaffee);
delete from public.items where id = (select id from kaffee);
select is((select items from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c02'),
  jsonb_build_array(jsonb_build_object('name', 'Kaffee', 'quantity', '2', 'canonical_key', public.canonical_key('Kaffee'))),
  'the trip keeps the items as bought through re-add, re-tick, rename and delete');

-- A deleted store: the trip keeps its name, and an edit without a store keeps it too.
select public.delete_store((select id from lidl));
select is((select (store_id, store_name)::text from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c02'),
  (null::uuid, 'Lidl')::text, 'a deleted store leaves the trip with its name and no store id');
select public.save_trip((select id from home), '00000000-0000-0000-0000-000000199c02', null, current_date,
  '[{"name": "Kaffee", "quantity": "3"}]');
select is((select store_name from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c02'), 'Lidl',
  'editing that trip keeps the gone store''s name');

-- The export.
select is(
  (select jsonb_path_query_array(public.export_my_data(), '$.trips_logged[*] ? (@.store_name == "Lidl")')),
  jsonb_build_array(jsonb_build_object(
    'household_id', (select id from home), 'store_name', 'Lidl', 'shopped_on', current_date,
    'items', jsonb_build_array(jsonb_build_object('name', 'Kaffee', 'quantity', '3')),
    'created_at', (select created_at from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c02'))),
  'export_my_data lists the trips Lea logged with store, day and items');
select pg_temp.login(:pia);
select is(jsonb_array_length(public.export_my_data() -> 'trips_logged'), 1,
  'Pia''s export lists the trip she logged, not the one she edited');

-- The history: Free sees the 28 days up to today, Premium all; logging has no limit.
\set edge '''00000000-0000-0000-0000-000000199c10'''
\set old '''00000000-0000-0000-0000-000000199c11'''
\set past '''00000000-0000-0000-0000-000000199c12'''
select pg_temp.login(:pia);
select public.save_trip((select id from home), :edge, null, current_date - 27, '[{"name": "Mehl"}]');
select public.save_trip((select id from home), :old, null, current_date - 28, '[{"name": "Zucker"}]');
select lives_ok(format($$ select public.save_trip(%L, %L, null, current_date - 60, '[{"name": "Hefe"}]') $$,
  (select id from home), :past), 'a Free member logs a trip 60 days back');
create temp table free_history as select public.trip_history((select id from home), current_date) as h;
select is((select h - 'trips' from free_history),
  jsonb_build_object('premium', false, 'since', current_date - 27, 'locked', 2),
  'Free: since is 27 days back, the trips 28 and 60 days back are locked');
select is((select jsonb_path_query_array(h, '$.trips[*].id') from free_history),
  (select jsonb_agg(to_jsonb(t.id) order by t.shopped_on desc, t.created_at desc, t.id desc) from pg_temp.trips() t
   where t.household_id = (select id from home) and t.shopped_on >= current_date - 27),
  'Free: the trips from 27 days back on, newest first');
select ok((select h -> 'trips' @> jsonb_build_array(jsonb_build_object('id', :edge::uuid)) from free_history),
  'the trip 27 days back is shown');
select ok((select not h -> 'trips' @> jsonb_build_array(jsonb_build_object('id', :old::uuid))
                  and not h -> 'trips' @> jsonb_build_array(jsonb_build_object('id', :past::uuid)) from free_history),
  'the trips 28 and 60 days back are not');
select is((select h #> '{trips,0}' from free_history),
  (select to_jsonb(t) from pg_temp.trips() t where t.household_id = (select id from home)
   order by t.shopped_on desc, t.created_at desc, t.id desc limit 1),
  'each trip has the shape save_trip returns');
select is(public.trip_history((select id from home), current_date + 400) - 'trips',
  jsonb_build_object('premium', false, 'since', current_date + 1 - 27, 'locked', 3),
  'a far-future today is clamped to tomorrow');
select is(public.trip_history((select id from home), current_date - 400) - 'trips',
  jsonb_build_object('premium', false, 'since', current_date - 1 - 27, 'locked', 1),
  'a far-past today is clamped to yesterday');
select throws_ok(format($$ select public.trip_history(%L, null) $$, (select id from home)),
  '22023', 'missing_argument', 'trip_history needs a day');
select pg_temp.logout();
select public.promotional_premium_sync_user(:pia, true, null);
select pg_temp.login(:pia);
select is(public.trip_history((select id from home), current_date) - 'trips',
  jsonb_build_object('premium', true, 'since', null, 'locked', 0), 'Premium: since null, nothing locked');
select is(jsonb_array_length(public.trip_history((select id from home), current_date) -> 'trips'),
  (select count(*)::int from pg_temp.trips() t where t.household_id = (select id from home)),
  'Premium sees every trip');
select pg_temp.login(:kim);
select is(public.trip_history((select id from home), current_date) ->> 'locked', '2',
  'Pia''s Premium is hers: Kim in the same household still sees 4 weeks');
select pg_temp.logout();
select public.promotional_premium_sync((select id from home), true, null);
select pg_temp.login(:kim);
select is(public.trip_history((select id from home), current_date) - 'trips',
  jsonb_build_object('premium', true, 'since', null, 'locked', 0),
  'a household grant (promotional, household-bound Lifetime) opens the history for Kim too');
select pg_temp.logout();
select public.promotional_premium_sync((select id from home), false, null);
select pg_temp.login(:pia);
select public.delete_trip(:edge);
select public.delete_trip(:old);
select public.delete_trip(:past);

-- Deleting.
select pg_temp.login(:lea);
select public.delete_trip('00000000-0000-0000-0000-000000199c02');
select is((select count(*)::int from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c02'), 0,
  'delete_trip deletes the trip');
select lives_ok($$ select public.delete_trip('00000000-0000-0000-0000-000000199c02') $$,
  'deleting it again is no error');

-- Leaving, account deletion, household deletion.
select pg_temp.login(:kim);
select public.save_trip((select id from home), '00000000-0000-0000-0000-000000199c03', null, current_date, '[{"name": "Salz"}]');
select is(public.leave_household((select id from home)) ->> 'status', 'left', 'Kim leaves');
select pg_temp.logout();
select is((select logged_by from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c03'), null,
  'a trip of a member who left stays, without who logged it');
select pg_temp.login(:pia);
select public.save_trip((select id from home), '00000000-0000-0000-0000-000000199c04', null, current_date, '[{"name": "Reis"}]');
select pg_temp.logout();
select is(public.delete_account(:pia), 'kept', 'Pia deletes her account');
select is((select logged_by from pg_temp.trips() where id = '00000000-0000-0000-0000-000000199c04'), null,
  'her trip stays for Lea, without who logged it');
select is(public.delete_account(:lea), 'deleted', 'Lea, the last member, deletes her account');
select is((select count(*)::int from pg_temp.trips() where household_id = (select id from home)), 0,
  'the household''s trips go with it');

select * from finish();
rollback;
