-- Job 352: the learned walk order (20261122010000_learned_order.sql). The switch keeps today's
-- order, new and moved items find their remembered place, manual places and set_store_order,
-- and the replay of walks (job 351's F8 trade, the shuffle gate, manual places that hold until a
-- third contradicting walk). supabase/functions/_shared/learned_order_integration_test.ts runs
-- random walks against the TypeScript learner.
begin;
select plan(53);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000003521', 'lena@example.com');
-- Members cannot read item_order_memory; the tests read it as its owner.
create function pg_temp.memories() returns setof public.item_order_memory language sql security definer as $$
  select * from public.item_order_memory
$$;
select pg_temp.login('00000000-0000-0000-0000-000000003521');
create temp table hh as select id from public.create_household(p_name => 'Lena', p_default_stores => false);
grant select on hh to authenticated;

create function pg_temp.h() returns uuid language sql as $$ select id from hh $$;
create function pg_temp.cat(p_seed text) returns uuid language sql as $$
  select id from public.categories where household_id = pg_temp.h() and seed_key = p_seed;
$$;
create function pg_temp.store(p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = pg_temp.h() and name = p_name;
$$;
create function pg_temp.item(p_name text) returns uuid language sql as $$
  select id from public.items where household_id = pg_temp.h() and name = p_name;
$$;
create function pg_temp.add(p_name text, p_category text, p_store text) returns void language sql as $$
  insert into public.items (household_id, name, category_id, store_id)
  values (pg_temp.h(), p_name, pg_temp.cat(p_category), pg_temp.store(p_store));
$$;
-- Today's order of a store section: its walking order (layout rows, then route order), then sort_key.
create function pg_temp.today(p_store uuid) returns text[] language sql as $$
  select array_agg(i.name order by w.r, i.sort_key, i.created_at, i.id)
  from public.items i
  join (select c.id, row_number() over (order by o.sort_order is null, o.sort_order, c.sort_order) as r
        from public.categories c
        left join public.store_category_order o on o.store_id = p_store and o.category_id = c.id
        where c.household_id = pg_temp.h()) w on w.id = i.category_id
  where i.household_id = pg_temp.h() and i.status = 'active' and i.store_id is not distinct from p_store;
$$;
-- The learned order of a store section as the app sorts it: one run by sort_key.
create function pg_temp.shown(p_store uuid) returns text[] language sql as $$
  select array_agg(name order by sort_key, created_at, id) from public.items
  where household_id = pg_temp.h() and status = 'active' and store_id is not distinct from p_store;
$$;
create function pg_temp.key(p_name text) returns text language sql as $$
  select coalesce(canonical_key, public.item_key(name)) from public.items
  where household_id = pg_temp.h() and name = p_name;
$$;
create function pg_temp.memory(p_store uuid, p_name text) returns public.item_order_memory language sql as $$
  select * from pg_temp.memories()
  where household_id = pg_temp.h() and store_id is not distinct from p_store and item_key = pg_temp.key(p_name);
$$;
-- A walk of p_store, p_minutes after now, steps of item names; each in its own trip session.
create function pg_temp.walk(p_store uuid, p_minutes int, p_steps jsonb) returns uuid language sql as $$
  insert into public.trip_sessions (id, household_id, started_at, ended_at, active_seconds, end_reason,
    source, currency, shopped_on, walks)
  select gen_random_uuid(), pg_temp.h(), now(), now(), 0, 'user', 'manual', 'EUR', current_date,
    jsonb_build_array(jsonb_build_object('store_id', p_store, 'at', now() + make_interval(mins => p_minutes),
      'steps', (select jsonb_agg((select jsonb_agg(pg_temp.key(n) order by m)
                                  from jsonb_array_elements_text(s) with ordinality q (n, m)) order by o)
                from jsonb_array_elements(p_steps) with ordinality t (s, o))))
  returning id;
$$;
-- Positions of the named keys in p_store, less the first one's seed.
create function pg_temp.offsets(p_store uuid, p_names text[]) returns double precision[] language sql as $$
  select array_agg((pg_temp.memory(p_store, n)).position - (pg_temp.memory(p_store, p_names[1])).seed_position order by o)
  from unnest(p_names) with ordinality t (n, o);
$$;

create function pg_temp.rounded(p double precision[]) returns numeric[] language sql as $$
  select array_agg(round(x::numeric, 3) order by o) from unnest(p) with ordinality t (x, o);
$$;

select public.add_store(pg_temp.h(), 'Laden A');
select public.add_store(pg_temp.h(), 'Laden B');
-- Laden A's layout names two categories, drinks then chilled; the rest follow in route order.
-- Laden B walks the route backwards.
select pg_temp.logout();
delete from public.store_category_order where store_id in (pg_temp.store('Laden A'), pg_temp.store('Laden B'));
insert into public.store_category_order (household_id, store_id, category_id, sort_order) values
  (pg_temp.h(), pg_temp.store('Laden A'), pg_temp.cat('drinks'), 10),
  (pg_temp.h(), pg_temp.store('Laden A'), pg_temp.cat('chilled'), 20);
insert into public.store_category_order (household_id, store_id, category_id, sort_order)
select pg_temp.h(), pg_temp.store('Laden B'), c.id, -c.sort_order
from public.categories c where c.household_id = pg_temp.h();
select pg_temp.login('00000000-0000-0000-0000-000000003521');

select pg_temp.add('Gurke', 'produce', 'Laden A');
select pg_temp.add('Brot', 'bakery', 'Laden A');
select pg_temp.add('Milch', 'chilled', 'Laden A');
select pg_temp.add('Joghurt', 'chilled', 'Laden A');
select pg_temp.add('Butter', 'chilled', 'Laden A');
select pg_temp.add('Wasser', 'drinks', 'Laden A');
select pg_temp.add('Bier', 'drinks', 'Laden A');
select public.place_item(pg_temp.item('Joghurt'), pg_temp.item('Milch'), 'before');
update public.items set status = 'bought' where id = pg_temp.item('Butter');
select pg_temp.add('Salat', 'produce', 'Laden B');
select pg_temp.add('Äpfel', 'produce', 'Laden B');
select pg_temp.add('Toast', 'bakery', 'Laden B');
select pg_temp.add('Sahne', 'chilled', 'Laden B');
select pg_temp.add('Saft', 'drinks', 'Laden B');
select pg_temp.add('Tomaten', 'produce', null);
select pg_temp.add('Quark', 'chilled', null);
select pg_temp.add('Cola', 'drinks', null);
select pg_temp.add('Brezel', 'bakery', null);
update public.items set store_id = null where household_id = pg_temp.h() and name in ('Tomaten', 'Quark', 'Cola', 'Brezel');
create temp table before as
  select s.store_id, pg_temp.today(s.store_id) as names
  from (values (pg_temp.store('Laden A')), (pg_temp.store('Laden B')), (null::uuid)) s (store_id);
grant select on before to authenticated;

-- 1. The switch keeps today's order.
select is((select names from before where store_id = pg_temp.store('Laden A')),
  array['Wasser', 'Bier', 'Joghurt', 'Milch', 'Gurke', 'Brot'],
  'today: Laden A walks its two layout rows first, then the route');
select throws_ok($$ select public.set_order_mode(pg_temp.h(), 'walk') $$, '22023', 'invalid_order_mode',
  'an unknown order mode is refused');
select is(public.set_order_mode(pg_temp.h(), 'learned'), 'learned', 'set_order_mode answers the mode in force');
select is((select order_mode from public.households where id = pg_temp.h()), 'learned', 'the household sorts by learned order');
select is(pg_temp.shown(pg_temp.store('Laden A')), (select names from before where store_id = pg_temp.store('Laden A')),
  'Laden A (a partial layout) looks as it did');
select is(pg_temp.shown(pg_temp.store('Laden B')), (select names from before where store_id = pg_temp.store('Laden B')),
  'Laden B (its own layout) looks as it did');
select is(pg_temp.shown(null), (select names from before where store_id is null),
  'No store (route order) looks as it did');
select is(
  (select count(*)::int from public.items i
   where i.household_id = pg_temp.h()
     and i.sort_key is distinct from (pg_temp.memory(i.store_id, i.name)).position),
  0, 'every item, the bought one too, sorts by its remembered position');
create temp table snapshot as select id, sort_key from public.items where household_id = pg_temp.h();
grant select on snapshot to authenticated;
select is(public.set_order_mode(pg_temp.h(), 'learned'), 'learned', 'switching again answers the same');
select is((select count(*)::int from public.items i join snapshot s using (id) where i.sort_key is distinct from s.sort_key),
  0, 'switching again changes nothing');

-- 2. New, re-added and moved items.
select pg_temp.add('Kefir', 'chilled', 'Laden A');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Wasser', 'Bier', 'Joghurt', 'Milch', 'Kefir', 'Gurke', 'Brot'],
  'a new item lands at the end of its category''s run in the store');
create temp table joghurt as select sort_key from public.items where id = pg_temp.item('Joghurt');
grant select on joghurt to authenticated;
delete from public.items where id = pg_temp.item('Joghurt');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Wasser', 'Bier', 'Milch', 'Kefir', 'Gurke', 'Brot'],
  'a deleted item leaves the list');
select pg_temp.add('Joghurt', 'chilled', 'Laden A');
select is((select sort_key from public.items where id = pg_temp.item('Joghurt')), (select sort_key from joghurt),
  'a deleted and re-added key returns to its remembered place');
update public.items set category_id = pg_temp.cat('drinks') where id = pg_temp.item('Milch');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Wasser', 'Bier', 'Joghurt', 'Milch', 'Kefir', 'Gurke', 'Brot'],
  'a category change alone keeps the place');
create temp table salat as select sort_key from public.items where id = pg_temp.item('Salat');
grant select on salat to authenticated;
update public.items set store_id = pg_temp.store('Laden A') where id = pg_temp.item('Salat');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Wasser', 'Bier', 'Joghurt', 'Milch', 'Kefir', 'Gurke', 'Salat', 'Brot'],
  'moved to a store without memory of it, an item lands at the end of its category''s run');
select public.move_item(pg_temp.item('Salat'), pg_temp.store('Laden B'), null);
select is((select sort_key from public.items where id = pg_temp.item('Salat')), (select sort_key from salat),
  'moved back, it takes its remembered place in that store');

-- 3. place_item.
select is((select name from public.place_item(pg_temp.item('Brot'), pg_temp.item('Wasser'), 'before')), 'Brot',
  'place_item returns the placed row');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Brot', 'Wasser', 'Bier', 'Joghurt', 'Milch', 'Kefir', 'Gurke'],
  'before the first: the front');
select public.place_item(pg_temp.item('Wasser'), pg_temp.item('Gurke'), 'after');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Brot', 'Bier', 'Joghurt', 'Milch', 'Kefir', 'Gurke', 'Wasser'],
  'after the last: the end');
select public.place_item(pg_temp.item('Kefir'), pg_temp.item('Bier'), 'after');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Brot', 'Bier', 'Kefir', 'Joghurt', 'Milch', 'Gurke', 'Wasser'],
  'after an item in the middle');
select public.place_item(pg_temp.item('Milch'), pg_temp.item('Joghurt'), 'before');
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Brot', 'Bier', 'Kefir', 'Milch', 'Joghurt', 'Gurke', 'Wasser'],
  'before an item in the middle');
select is((select (source, contradictions) from pg_temp.memory(pg_temp.store('Laden A'), 'Milch')),
  ('manual'::text, 0), 'a place is remembered as manual');
create temp table placed as
  select (select string_agg((id, sort_key, updated_at)::text, ';' order by id) from public.items where household_id = pg_temp.h()) as items,
         (select string_agg((item_key, position, manual_at)::text, ';' order by item_key) from pg_temp.memories()
          where household_id = pg_temp.h()) as memory;
grant select on placed to authenticated;
select public.place_item(pg_temp.item('Milch'), pg_temp.item('Joghurt'), 'before');
select is(
  (select string_agg((id, sort_key, updated_at)::text, ';' order by id) from public.items where household_id = pg_temp.h()),
  (select items from placed), 'the same place twice changes no item');
select is(
  (select string_agg((item_key, position, manual_at)::text, ';' order by item_key) from pg_temp.memories()
   where household_id = pg_temp.h()),
  (select memory from placed), 'the same place twice changes no memory');
select is((select category_id from public.items where id = pg_temp.item('Milch')), pg_temp.cat('drinks'),
  'a place keeps the category');
select throws_ok($$ select public.place_item(pg_temp.item('Milch'), pg_temp.item('Äpfel'), 'after') $$,
  '22023', 'anchor_in_other_store', 'an anchor in another store is refused');
select throws_ok($$ select public.place_item(pg_temp.item('Milch'), pg_temp.item('Butter'), 'after') $$,
  '22023', 'invalid_anchor', 'a bought anchor is refused');

-- 4. set_store_order.
select public.set_store_order(pg_temp.h(), pg_temp.store('Laden A'), array[pg_temp.item('Gurke'), pg_temp.item('Joghurt')]);
select is(pg_temp.shown(pg_temp.store('Laden A')), array['Gurke', 'Joghurt', 'Brot', 'Bier', 'Kefir', 'Milch', 'Wasser'],
  'the listed items go first in that order, the others keep theirs');
select is((select array_agg(source order by item_key) from pg_temp.memories()
           where household_id = pg_temp.h() and item_key in (pg_temp.key('Gurke'), pg_temp.key('Joghurt'))),
  array['manual', 'manual'], 'the listed items are manual places');
create temp table ordered as
  select (select string_agg((id, sort_key, updated_at)::text, ';' order by id) from public.items where household_id = pg_temp.h()) as items,
         (select string_agg((item_key, position, manual_at)::text, ';' order by item_key) from pg_temp.memories()
          where household_id = pg_temp.h()) as memory;
grant select on ordered to authenticated;
select public.set_store_order(pg_temp.h(), pg_temp.store('Laden A'), array[pg_temp.item('Gurke'), pg_temp.item('Joghurt')]);
select is(
  (select string_agg((id, sort_key, updated_at)::text, ';' order by id) from public.items where household_id = pg_temp.h()),
  (select items from ordered), 'the same order twice changes no item');
select is(
  (select string_agg((item_key, position, manual_at)::text, ';' order by item_key) from pg_temp.memories()
   where household_id = pg_temp.h()),
  (select memory from ordered), 'the same order twice changes no memory');
select throws_ok(
  $$ select public.set_store_order(pg_temp.h(), pg_temp.store('Laden A'), array[pg_temp.item('Äpfel')]) $$,
  '22023', 'invalid_items', 'an item of another store is refused');
create temp table other as select id from public.create_household(p_request_id => gen_random_uuid(), p_name => 'Zweiter');
grant select on other to authenticated;
select throws_ok($$ select public.set_store_order((select id from other), null, '{}') $$,
  '55000', 'order_mode', 'a household sorting by categories has no store order');

-- 4b. Twins: Bier and Gurke are on the party list too, in Laden A. Gurke goes after Bier: between
-- Bier and the next other item, whatever the twins, and again to the same place.
select pg_temp.logout();
insert into public.lists (household_id, name) values (pg_temp.h(), 'Party');
insert into public.items (household_id, name, category_id, store_id, list_id)
select pg_temp.h(), n, pg_temp.cat(c), pg_temp.store('Laden A'),
  (select id from public.lists where household_id = pg_temp.h() and name = 'Party')
from (values ('Bier', 'drinks'), ('Gurke', 'produce')) v (n, c);
select pg_temp.login('00000000-0000-0000-0000-000000003521');
create function pg_temp.main_item(p_name text) returns uuid language sql as $$
  select i.id from public.items i join public.lists l on l.id = i.list_id
  where i.household_id = pg_temp.h() and i.name = p_name and l.name <> 'Party';
$$;
create function pg_temp.sort_key(p_name text) returns double precision language sql as $$
  select sort_key from public.items where id = pg_temp.main_item(p_name);
$$;
select public.place_item(pg_temp.main_item('Gurke'), pg_temp.main_item('Bier'), 'after');
create temp table twin_place as select pg_temp.sort_key('Gurke') as k;
grant select on twin_place to authenticated;
select ok(pg_temp.sort_key('Bier') < (select k from twin_place) and (select k from twin_place) < pg_temp.sort_key('Kefir'),
  'next to an item with a twin on another list: strictly between it and the next other item');
select public.place_item(pg_temp.main_item('Gurke'), pg_temp.main_item('Bier'), 'after');
select is(pg_temp.sort_key('Gurke'), (select k from twin_place), 'the same place again, twins and all, stays put');
delete from public.items where list_id = (select id from public.lists where household_id = pg_temp.h() and name = 'Party');

-- 5. Replay. Laden G and Laden M hold four chilled keys each, seeds s .. s + 3 in this order.
select public.add_store(pg_temp.h(), 'Laden G');
select public.add_store(pg_temp.h(), 'Laden M');
select pg_temp.add(n, 'chilled', 'Laden G') from unnest(array['Ga', 'Gb', 'Gc', 'Gd']) n;
select pg_temp.add(n, 'chilled', 'Laden M') from unnest(array['Ma', 'Mb', 'Mc', 'Md']) n;
update public.items set status = 'bought' where id = pg_temp.item('Gb');
select pg_temp.logout();
create temp table walks (name text primary key, id uuid);
insert into walks values
  ('in order 1', pg_temp.walk(pg_temp.store('Laden G'), 1, '[["Ga"], ["Gb"], ["Gc"], ["Gd"]]')),
  ('in order 2', pg_temp.walk(pg_temp.store('Laden G'), 2, '[["Ga"], ["Gb"], ["Gc"], ["Gd"]]')),
  ('in order 3', pg_temp.walk(pg_temp.store('Laden G'), 3, '[["Ga"], ["Gb"], ["Gc"], ["Gd"]]')),
  ('shuffle', pg_temp.walk(pg_temp.store('Laden G'), 4, '[["Gc"], ["Ga"], ["Gb"]]'));
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden G'));
select is(pg_temp.offsets(pg_temp.store('Laden G'), array['Ga', 'Gb', 'Gc', 'Gd']), array[0, 1, 2, 3]::double precision[],
  'walks in the stored order move nothing, and after 3 taught walks the gate turns a shuffle away');
update public.trip_sessions set removed_at = now() where id in (select id from walks where name like 'in order%');
-- Gc was ticked by a transaction that began after this one and committed before the replay
-- reached the store: its updated_at is later than this transaction's now().
alter table public.items disable trigger items_before_write;
update public.items set updated_at = now() + interval '1 second' where id = pg_temp.item('Gc');
alter table public.items enable trigger items_before_write;
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden G'));
select ok((select updated_at > now() + interval '1 second' from public.items where id = pg_temp.item('Gc')),
  'a replay''s new sort_key carries a later updated_at than the write before it, so the app keeps it');
-- The shuffle is the first walk now: Gc, Ga, Gb take the slots 0, 1, 2 in that order, halfway.
select is(pg_temp.offsets(pg_temp.store('Laden G'), array['Ga', 'Gb', 'Gc', 'Gd']), array[0.5, 1.5, 1, 3]::double precision[],
  'with the removed sessions'' walks gone, the shuffle teaches: the walked keys trade their own slots halfway');
select is((select sort_key from public.items where id = pg_temp.item('Gb')), (pg_temp.memory(pg_temp.store('Laden G'), 'Gb')).position,
  'a bought item''s sort_key follows');
select is(pg_temp.shown(pg_temp.store('Laden G')), array['Ga', 'Gc', 'Gd'], 'open items follow');

select pg_temp.login('00000000-0000-0000-0000-000000003521');
select public.place_item(pg_temp.item('Mb'), pg_temp.item('Md'), 'after');
select pg_temp.logout();
select is(pg_temp.offsets(pg_temp.store('Laden M'), array['Ma', 'Mb', 'Mc', 'Md']), array[0, 1027, 2, 3]::double precision[],
  'Mb is placed after Md');
-- Each walk takes Mb before Md, against its place; five of six pairs agree, so the gate lets it through.
insert into walks values
  ('against 1', pg_temp.walk(pg_temp.store('Laden M'), 1, '[["Ma"], ["Mc"], ["Mb"], ["Md"]]')),
  ('against 2', pg_temp.walk(pg_temp.store('Laden M'), 2, '[["Ma"], ["Mc"], ["Mb"], ["Md"]]'));
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden M'));
select is(pg_temp.offsets(pg_temp.store('Laden M'), array['Ma', 'Mb', 'Mc', 'Md']), array[0, 1027, 2, 3]::double precision[],
  'a manual place holds against two contradicting walks');
select is((select (source, contradictions) from pg_temp.memory(pg_temp.store('Laden M'), 'Mb')), ('manual'::text, 2),
  'and counts them');
insert into walks values ('against 3', pg_temp.walk(pg_temp.store('Laden M'), 4, '[["Ma"], ["Mc"], ["Mb"], ["Md"]]'));
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden M'));
-- Released, Mb trades: Ma, Mc, Mb, Md take the slots 0, 2, 3, 1027 halfway; Mb and Md meet at 515,
-- Md a hair after Mb, as the walk ticked them.
select is(pg_temp.rounded(pg_temp.offsets(pg_temp.store('Laden M'), array['Ma', 'Mb', 'Mc', 'Md'])), array[0, 515, 2, 515]::numeric[],
  'the third contradicting walk releases it to the learned order');
select is((select (source, contradictions) from pg_temp.memory(pg_temp.store('Laden M'), 'Mb')), ('learned'::text, 0),
  'released, it is learned again');
insert into walks values ('agrees', pg_temp.walk(pg_temp.store('Laden M'), 3, '[["Ma"], ["Mc"], ["Md"], ["Mb"]]'));
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden M'));
select is((select (position - seed_position, source, contradictions) from pg_temp.memory(pg_temp.store('Laden M'), 'Mb')),
  (1026::double precision, 'manual'::text, 1), 'an agreeing walk between them resets the count: the place holds');
update public.trip_sessions set removed_at = now() where id = (select id from walks where name = 'agrees');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden M'));
select is(pg_temp.rounded(pg_temp.offsets(pg_temp.store('Laden M'), array['Ma', 'Mb', 'Mc', 'Md'])), array[0, 515, 2, 515]::numeric[],
  'a removed session''s walk no longer counts after replay');
select is(
  (select count(*)::int from public.items i
   where i.household_id = pg_temp.h() and i.store_id = pg_temp.store('Laden M')
     and i.sort_key is distinct from (pg_temp.memory(i.store_id, i.name)).position),
  0, 'the store''s items sort by the replayed positions');

-- 6. Ties. Two keys a walk swaps both land on their midpoint; spread in walk order, the latest walk
-- decides. pg_temp.ranks joins tied open items with '='.
create function pg_temp.ranks(p_store uuid) returns text[] language sql as $$
  select array_agg(t.names order by t.sort_key) from (
    select sort_key, string_agg(name, '=' order by name) as names from public.items
    where household_id = pg_temp.h() and status = 'active' and store_id = p_store
    group by sort_key) t;
$$;
select pg_temp.login('00000000-0000-0000-0000-000000003521');
select public.add_store(pg_temp.h(), 'Laden T');
select public.add_store(pg_temp.h(), 'Laden U');
select public.add_store(pg_temp.h(), 'Laden V');
select pg_temp.add(n, 'chilled', 'Laden T') from unnest(array['Ta', 'Tb']) n;
select pg_temp.add(n, 'chilled', 'Laden U') from unnest(array['Ua', 'Ub', 'Uc']) n;
select pg_temp.add(n, 'chilled', 'Laden V') from unnest(array['Va', 'Vb', 'Vc']) n;
select pg_temp.logout();
select pg_temp.walk(pg_temp.store('Laden T'), 1, '[["Tb"], ["Ta"]]');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden T'));
select is(pg_temp.ranks(pg_temp.store('Laden T')), array['Tb', 'Ta'], 'a walk that swaps two neighbours flips them');
select pg_temp.walk(pg_temp.store('Laden T'), 2, '[["Tb"], ["Ta"]]');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden T'));
select is(pg_temp.ranks(pg_temp.store('Laden T')), array['Tb', 'Ta'], 'a second walk that agrees keeps them flipped');
select pg_temp.walk(pg_temp.store('Laden T'), 3, '[["Ta"], ["Tb"]]');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden T'));
select is(pg_temp.ranks(pg_temp.store('Laden T')), array['Ta', 'Tb'], 'a walk back flips them again');
select pg_temp.walk(pg_temp.store('Laden U'), 1, '[["Ua"], ["Uc"], ["Ub"]]');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden U'));
select is(pg_temp.ranks(pg_temp.store('Laden U')), array['Ua', 'Uc', 'Ub'], 'an adjacent swap in a longer walk flips the pair');
-- Va, Vb and Vc share one seed: the walk ticks Vc, then Va and Vb in one step.
update public.item_order_memory set seed_position = (pg_temp.memory(pg_temp.store('Laden V'), 'Va')).seed_position
where household_id = pg_temp.h() and store_id = pg_temp.store('Laden V');
select pg_temp.walk(pg_temp.store('Laden V'), 1, '[["Vc"], ["Va", "Vb"]]');
select public.replay_store_order(pg_temp.h(), pg_temp.store('Laden V'));
select is(pg_temp.ranks(pg_temp.store('Laden V')), array['Vc', 'Va=Vb'], 'keys of one step stay tied, after the earlier step');

select * from finish();
rollback;
