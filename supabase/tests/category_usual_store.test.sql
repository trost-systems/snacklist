-- Job 272 (ST1): with p_category_store, a grocery added for the first time with no remembered
-- store gets the store the household uses most for its category; corrections still win, and
-- calls without it (old and flag-off apps) get what they got before.
begin;
select plan(47);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000272c1', 'carla@example.com'),
  ('00000000-0000-0000-0000-0000000272d1', 'dora@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000272d1');
create temp table hd as select id from public.create_household(p_name => 'Dora', p_stores => array['Rewe', 'Aldi', 'dm']);
select pg_temp.login('00000000-0000-0000-0000-0000000272c1');
create temp table hc as select id from public.create_household(p_name => 'Carla', p_stores => array['Rewe', 'Aldi', 'dm']);
grant select on hc, hd to authenticated;

create function pg_temp.store(p_household uuid, p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = p_household and name = p_name;
$$;

-- Adds p_name to the household as the app does (put_item) and answers the store it got.
create function pg_temp.add(
  p_household uuid, p_name text, p_category_store boolean, p_store text default null, p_no_store boolean default false
) returns text language plpgsql as $$
declare
  v_store uuid;
begin
  if p_category_store is null then
    select i.store_id into v_store from public.put_item(
      p_id => gen_random_uuid(), p_household => p_household, p_list => null, p_name => p_name,
      p_store => pg_temp.store(p_household, p_store), p_no_store => p_no_store) i;
  else
    select i.store_id into v_store from public.put_item(
      p_id => gen_random_uuid(), p_household => p_household, p_list => null, p_name => p_name,
      p_store => pg_temp.store(p_household, p_store), p_no_store => p_no_store,
      p_category_store => p_category_store) i;
  end if;
  -- Bought, so the next add of the name is a new item, not the open one. Not a lesson: a tick
  -- with a store teaches that store (items_learn), which would hide what the add itself learned.
  perform set_config('family_groceries.learning', 'off', true);
  update public.items set status = 'bought' where household_id = p_household and name = p_name and status = 'active';
  perform set_config('family_groceries.learning', '', true);
  return coalesce((select name from public.stores where id = v_store), '-');
end $$;

-- The store on the typed row of suggest_entries, with and without the flag.
create function pg_temp.typed(p_household uuid, p_text text, p_category_store boolean) returns text language sql as $$
  select coalesce(st.name, '-')
  from public.suggest_entries(p_household, p_text, 8, p_category_store) s
  left join public.stores st on st.id = s.store_id
  where s.source = 'typed';
$$;

create function pg_temp.memory(p_name text) returns text language sql as $$
  select coalesce(string_agg(st.name || ' x' || m.times, ', ' order by st.name), '-')
  from public.item_store_memory m join public.stores st on st.id = m.store_id
  where m.household_id = (select id from hc) and m.item_key = public.item_key(p_name);
$$;

-- Carla's chilled groceries: Rewe three times, Aldi once, each a store picked with the add.
select pg_temp.add((select id from hc), n, null, s)
from (values ('Joghurt', 'Rewe'), ('Butter', 'Rewe'), ('Quark', 'Rewe'), ('Sahne', 'Aldi')) as v (n, s);

-- 6. Without the flag, nothing changes.
select is(pg_temp.add((select id from hc), 'Schmand', null), '-',
  'without p_category_store a first-time grocery gets no store, as before');
select is(pg_temp.typed((select id from hc), 'Frischkäse', false), '-',
  'without p_category_store the typed row has no store, as before');
select results_eq(
  $$ select * from public.suggest_entries((select id from hc), 'Frischkäse') $$,
  $$ select * from public.suggest_entries((select id from hc), 'Frischkäse', 8, false) $$,
  'an old call of suggest_entries answers as p_category_store false'
);
select is(public.guess_store((select id from hc), 'Frischkäse', null, public.classify_item((select id from hc), 'Frischkäse')),
  null, 'guess_store without p_category_store has no store for it, as before');

-- 1. With the flag, the category's usual store.
select is(public.category_usual_store((select id from hc), public.classify_item((select id from hc), 'Frischkäse')),
  pg_temp.store((select id from hc), 'Rewe'), 'the usual store of chilled groceries is Rewe (3 to 1)');
select is(pg_temp.typed((select id from hc), 'Frischkäse', true), 'Rewe',
  'with p_category_store the typed row of a first-time grocery shows the category''s usual store');
select is(pg_temp.add((select id from hc), 'Frischkäse', true), 'Rewe',
  'with p_category_store a first-time grocery is added at the category''s usual store');
-- 4. The default is not a lesson.
select is(pg_temp.memory('Frischkäse'), '-', 'the category default is not learned as the item''s store');
select is(pg_temp.add((select id from hc), 'Mascarpone', true, 'Rewe'), 'Rewe',
  'a row that carries the default store adds it');
select is(pg_temp.memory('Mascarpone'), '-', 'and does not learn it either');
select is(pg_temp.add((select id from hc), 'Hüttenkäse', true, 'Aldi'), 'Aldi', 'another store picked with the add is kept');
select is(pg_temp.memory('Hüttenkäse'), 'Aldi x1', 'and learned');
select is(pg_temp.add((select id from hc), 'Hüttenkäse', true), 'Aldi', 'and the next add of it goes there');

-- 2. The item's own memory wins, by its key and by its canonical key.
select pg_temp.add((select id from hc), n, null, s)
from (values ('Gurke', 'Rewe'), ('Tomaten', 'Rewe'), ('Möhren', 'Aldi')) as v (n, s);
select is(pg_temp.add((select id from hc), 'Möhren', true), 'Aldi', 'a remembered store beats the category default');
select is(pg_temp.typed((select id from hc), 'Karotten', true), 'Aldi',
  'a store remembered for a synonym beats it too (typed row)');
select is(pg_temp.add((select id from hc), 'Karotten', true), 'Aldi', 'a store remembered for a synonym beats it too (add)');

-- 3. A later correction teaches the next add; a change to no store too.
update public.items set store_id = pg_temp.store((select id from hc), 'Aldi')
where household_id = (select id from hc) and name = 'Frischkäse';
select is(pg_temp.add((select id from hc), 'Frischkäse', true), 'Aldi', 'a later store change wins the next add');
update public.items set store_id = null where household_id = (select id from hc) and name = 'Frischkäse';
select is(pg_temp.typed((select id from hc), 'Frischkäse', true), '-',
  'after a change to no store the typed row has none');
select is(pg_temp.add((select id from hc), 'Frischkäse', true), '-',
  'after a change to no store the next add has none, not the category default');
update public.items set store_id = pg_temp.store((select id from hc), 'Rewe')
where household_id = (select id from hc) and name = 'Frischkäse';
select is(pg_temp.add((select id from hc), 'Frischkäse', true), 'Rewe', 'a store set again after that wins again');
select is((select count(*)::int from public.item_store_cleared where item_key = public.item_key('Frischkäse')), 1,
  'the recorded clear stays under the memory that wins, for when the memory goes');
select is(pg_temp.add((select id from hc), 'Ricotta', true, null, true), '-', '"Ohne Laden" picked with the add holds');
select is(pg_temp.add((select id from hc), 'Ricotta', true), '-', 'and the next add stays without a store');

-- Undo: deleting an add within 10 minutes undoes the store it taught, and the clear is back.
select is(
  (select st.name from public.put_item(p_id => '27200000-0000-4000-8000-000000000002', p_household => (select id from hc),
     p_list => null, p_name => 'Ricotta', p_store => pg_temp.store((select id from hc), 'Aldi'), p_category_store => true) i
   join public.stores st on st.id = i.store_id),
  'Aldi', 'a store picked with the add of a cleared grocery is kept');
select is(pg_temp.typed((select id from hc), 'Ricotta', true), 'Aldi', 'and its memory wins over the clear');
delete from public.items where id = '27200000-0000-4000-8000-000000000002';
select is(pg_temp.add((select id from hc), 'Ricotta', true), '-',
  'after the add is deleted (undo) the clear is in force again');

-- "Ohne Laden" picked with an add that got no store at all is recorded too.
select is(pg_temp.add((select id from hc), 'Kekse', true, null, true), '-', '"Ohne Laden" with a first-time sweet');
select is((select count(*)::int from public.item_store_cleared where item_key = public.item_key('Kekse')), 1,
  'is recorded although the add had no store to clear');
select pg_temp.add((select id from hc), 'Lakritz', null, null, true);
select is((select count(*)::int from public.item_store_cleared where item_key = public.item_key('Lakritz')), 0,
  'without p_category_store such an add records nothing');
select pg_temp.add((select id from hc), 'Schokolade', null, 'Aldi');
select is(pg_temp.typed((select id from hc), 'Gummibärchen', true), 'Aldi', 'sweets now have a usual store');
select is(pg_temp.add((select id from hc), 'Kekse', true), '-', 'and the cleared sweet still gets none');

-- parse_item, which the app runs on an add typed on the device, shows the same store.
select is(
  (select p.store_id from public.parse_item((select id from hc), 'Mozzarella') p),
  null, 'without p_category_store parse_item has no store for a first-time grocery, as before');
select results_eq(
  $$ select * from public.parse_item((select id from hc), 'Balea Shampoo') $$,
  $$ select * from public.parse_item((select id from hc), 'Balea Shampoo', false) $$,
  'an old call of parse_item answers as p_category_store false'
);
select is(
  (select st.name from public.parse_item((select id from hc), 'Mozzarella', true) p join public.stores st on st.id = p.store_id),
  'Rewe', 'with p_category_store parse_item gives the category''s usual store');
select pg_temp.add((select id from hc), 'Shampoo', true, null, true);
select is(
  (select st.name from public.parse_item((select id from hc), 'Balea Shampoo') p join public.stores st on st.id = p.store_id),
  'dm', 'without p_category_store the brand''s store, as before, cleared or not');
select is((select p.store_id from public.parse_item((select id from hc), 'Balea Shampoo', true) p),
  null, 'with p_category_store a recorded clear beats the brand''s store');
select is((select p.store_id from public.parse_item((select id from hc), 'Shampoo', true) p),
  null, 'and the dm seed');
select is(
  (select st.name from public.parse_item((select id from hc), 'Balea', true) p join public.stores st on st.id = p.store_id),
  'dm', 'a brand alone, which becomes the name, keeps its store');

-- The usual store comes before the dm seed; the old wrapper without p_list takes the flag.
select pg_temp.add((select id from hc), 'Duschgel', null, 'Rewe');
select is(
  (select st.name from public.put_item(p_id => gen_random_uuid(), p_household => (select id from hc),
     p_name => 'Zahnpasta', p_category_store => true) i join public.stores st on st.id = i.store_id),
  'Rewe', 'the category''s usual store beats the dm seed (put_item without p_list)');

-- A retry of an add answers with its row, as without the flag (put_item.test.sql).
select is(
  (select array_agg(i.name) from public.put_item(p_id => '27200000-0000-4000-8000-000000000001',
     p_household => (select id from hc), p_list => null, p_name => 'Joghurt', p_category_store => true) i),
  array['Joghurt'], 'an add with p_category_store answers with its row');
select is(
  (select array_agg(i.name) from public.put_item(p_id => '27200000-0000-4000-8000-000000000001',
     p_household => (select id from hc), p_list => null, p_name => 'Joghurt', p_category_store => true) i),
  array['Joghurt'], 'and so does its retry');

-- A deleted store takes its memories; its items' store going to none is no "Ohne Laden".
select pg_temp.add((select id from hc), 'Feta', true, null, true);
update public.items set store_id = pg_temp.store((select id from hc), 'Aldi')
where household_id = (select id from hc) and name = 'Feta';
select is(pg_temp.add((select id from hc), 'Feta', true), 'Aldi', 'a cleared grocery set to Aldi goes there');
select public.delete_store(pg_temp.store((select id from hc), 'Aldi'));
select is(pg_temp.add((select id from hc), 'Feta', true), '-',
  'with Aldi deleted, its earlier clear is in force again');
select is((select count(*)::int from public.item_store_cleared where item_key = public.item_key('Sahne')), 0,
  'Aldi''s other groceries record no clear');
select is(pg_temp.add((select id from hc), 'Sahne', true), 'Rewe', 'and get the category''s usual store');

-- 5. Another household with the same stores and names is unaffected.
select pg_temp.login('00000000-0000-0000-0000-0000000272d1');
select is(pg_temp.add((select id from hd), 'Frischkäse', true), '-',
  'another household without store memory gets no category default');
select throws_ok(
  $$ select public.category_usual_store((select id from hc), null) $$,
  '42501', 'not_a_member', 'category_usual_store of another household is denied'
);

select * from finish();
rollback;
