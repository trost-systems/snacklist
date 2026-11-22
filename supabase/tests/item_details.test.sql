-- Job 15: brand, properties and sort_key on items; place_item, move_item, reorder_stores; the
-- add path add_item and add_items on top of the parser (docs/design/h-satz-final/SPEC.md, 3).
begin;
select plan(59);
-- Job 352 revoked members' read of item_events; this file checks the history the trigger writes
-- as a member reads it under the policy that still guards it.
grant select on public.item_events to authenticated;

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'erik@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
create temp table he as select id from public.create_household(p_name => 'Erik', p_stores => array['dm', 'Lidl', 'Edeka']);
grant select on he to authenticated;

create function pg_temp.cat(p_seed text) returns uuid language sql as $$
  select id from public.categories where household_id = (select id from he) and seed_key = p_seed;
$$;

create function pg_temp.store(p_seed text) returns uuid language sql as $$
  select id from public.stores where household_id = (select id from he) and seed_key = p_seed;
$$;

create function pg_temp.item(p_name text) returns uuid language sql as $$
  select id from public.items where household_id = (select id from he) and name = p_name;
$$;

-- The active names of one group in walk order.
create function pg_temp.walk(p_store uuid, p_category uuid) returns text[] language sql as $$
  select array_agg(name order by sort_key, created_at, id) from public.items
  where household_id = (select id from he) and status = 'active'
    and store_id is not distinct from p_store and category_id = p_category;
$$;


-- Columns: trimmed like quantity, capped, null by default.
insert into public.items (household_id, name) select id, 'Milch' from he;
select results_eq(
  $$ select brand, properties, sort_key from public.items where name = 'Milch' $$,
  $$ values (null::text, null::text, 1024::double precision) $$,
  'a plain item has no brand or properties and goes first in its group'
);
insert into public.items (household_id, name, brand, properties) select id, 'Windeln', '  Pampers ', '   ' from he;
select results_eq(
  $$ select brand, properties from public.items where name = 'Windeln' $$,
  $$ values ('Pampers', null::text) $$,
  'brand and properties are trimmed, empty becomes null'
);
select throws_ok(
  format($$ insert into public.items (household_id, name, brand) values (%L, 'X', %L) $$, (select id from he), repeat('b', 61)),
  '23514', null, 'a brand has at most 60 characters'
);
select throws_ok(
  format($$ insert into public.items (household_id, name, properties) values (%L, 'X', %L) $$, (select id from he), repeat('p', 121)),
  '23514', null, 'properties have at most 120 characters'
);

-- sort_key: the end of the group on insert and on a plain move, kept on edits and ticks.
insert into public.items (household_id, name) select id, 'Joghurt' from he;
insert into public.items (household_id, name) select id, 'Butter' from he;
select results_eq(
  $$ select name, sort_key from public.items where category_id = pg_temp.cat('chilled') order by sort_key $$,
  $$ values ('Milch', 1024::double precision), ('Joghurt', 2048), ('Butter', 3072) $$,
  'inserts go to the end of their group, step 1024'
);
insert into public.items (household_id, name) select id, 'Gurke' from he;
select is((select sort_key from public.items where name = 'Gurke'), 1024::double precision,
  'another group counts on its own');
insert into public.items (household_id, name, sort_key) select id, 'Quark', 1536 from he;
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Milch', 'Quark', 'Joghurt', 'Butter'],
  'an insert with a key keeps it');
update public.items set name = 'Vollmilch', quantity = '2', brand = 'Weihenstephan' where name = 'Milch';
select is((select sort_key from public.items where name = 'Vollmilch'), 1024::double precision, 'an edit keeps the key');
update public.items set status = 'bought' where name = 'Vollmilch';
update public.items set status = 'active' where name = 'Vollmilch';
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Vollmilch', 'Quark', 'Joghurt', 'Butter'],
  'tick and untick put the item back where it was');
update public.items set category_id = pg_temp.cat('produce') where name = 'Quark';
select is(pg_temp.walk(null, pg_temp.cat('produce')), array['Gurke', 'Quark'],
  'a plain category change goes to the end of the new group');
update public.items set store_id = pg_temp.store('lidl') where name = 'Quark';
select is((select sort_key from public.items where name = 'Quark'), 1024::double precision,
  'a store change too (the first in Lidl''s produce)');
update public.items set store_id = null, category_id = pg_temp.cat('chilled') where name = 'Quark';

-- History: brand and properties are edits; a key change alone is not.
create temp table events_before as select count(*) as n from public.item_events;
grant select on events_before to authenticated;
update public.items set properties = '3,5 %' where name = 'Vollmilch';
update public.items set brand = null where name = 'Vollmilch';
update public.items set sort_key = 99 where name = 'Vollmilch';
select results_eq(
  $$ select action, item_name from public.item_events where id > 0 order by id desc limit 2 $$,
  $$ values ('edited', 'Vollmilch'), ('edited', 'Vollmilch') $$,
  'brand and properties changes are history'
);
select is((select count(*) from public.item_events) - (select n from events_before), 2::bigint,
  'a sort_key change alone writes no event');
update public.items set sort_key = 1024 where name = 'Vollmilch';

-- place_item: before or after an active anchor, in the anchor's group.
delete from public.items where name in ('Butter', 'Quark');
select results_eq(
  $$ select name from public.place_item(pg_temp.item('Joghurt'), pg_temp.item('Vollmilch'), 'before') $$,
  $$ values ('Joghurt') $$, 'place_item returns the placed row'
);
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Joghurt', 'Vollmilch'], 'before the first');
insert into public.items (household_id, name) select id, 'Sahne' from he;
select public.place_item(pg_temp.item('Joghurt'), pg_temp.item('Sahne'), 'after');
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Vollmilch', 'Sahne', 'Joghurt'], 'after the last');
select public.place_item(pg_temp.item('Joghurt'), pg_temp.item('Vollmilch'), 'after');
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Vollmilch', 'Joghurt', 'Sahne'], 'after the first, in the middle');
select public.place_item(pg_temp.item('Vollmilch'), pg_temp.item('Sahne'), 'before');
select is(pg_temp.walk(null, pg_temp.cat('chilled')), array['Joghurt', 'Vollmilch', 'Sahne'], 'before the last, in the middle');
select is((select sort_key from public.items where name = 'Vollmilch'),
          ((select sort_key from public.items where name = 'Joghurt') + (select sort_key from public.items where name = 'Sahne')) / 2,
          'the key is the midpoint of the neighbours');

-- Across groups the item takes the anchor's store and category, and that is learned.
update public.items set store_id = pg_temp.store('lidl') where name = 'Joghurt';
update public.items set store_id = pg_temp.store('lidl') where name = 'Vollmilch';
update public.items set store_id = pg_temp.store('lidl') where name = 'Sahne';
select public.place_item(pg_temp.item('Gurke'), pg_temp.item('Vollmilch'), 'after');
select results_eq(
  $$ select store_id, category_id from public.items where name = 'Gurke' $$,
  $$ select pg_temp.store('lidl'), pg_temp.cat('chilled') $$,
  'a drop into another group adopts the anchor''s store and category'
);
select is(pg_temp.walk(pg_temp.store('lidl'), pg_temp.cat('chilled')), array['Joghurt', 'Vollmilch', 'Gurke', 'Sahne'],
  'at the dropped position');
select results_eq(
  $$ select (select category_id from public.category_memory where item_key = 'gurk'),
            (select store_id from public.item_store_memory where item_key = 'gurk') $$,
  $$ select pg_temp.cat('chilled'), pg_temp.store('lidl') $$,
  'the category and the store are learned for the item'
);

-- Many drops at one spot: the group is renumbered when the gap gets too small, nothing else.
insert into public.items (household_id, name) select id, 'Eier' from he;
create temp table others as select id, sort_key from public.items where name = 'Eier';
grant select on others to authenticated;
do $$
begin
  for i in 1..25 loop
    insert into public.items (household_id, name, store_id, category_id)
    values ((select id from he), 'Drop ' || i, pg_temp.store('lidl'), pg_temp.cat('chilled'));
    perform public.place_item(pg_temp.item('Drop ' || i), pg_temp.item('Joghurt'), 'after');
  end loop;
end $$;
select is(
  pg_temp.walk(pg_temp.store('lidl'), pg_temp.cat('chilled')),
  array['Joghurt'] || (select array_agg('Drop ' || i order by i desc) from generate_series(1, 25) as i)
    || array['Vollmilch', 'Gurke', 'Sahne'],
  'every drop lands directly after the anchor, in order'
);
select ok(
  (select min(gap) >= 0.001 from (
     select sort_key - lag(sort_key) over (order by sort_key) as gap from public.items
     where store_id = pg_temp.store('lidl') and category_id = pg_temp.cat('chilled')) g),
  'renumbering keeps neighbouring keys at least 0.001 apart (25 halvings of 1024 would not)'
);
select is((select sort_key from public.items where name = 'Eier'), (select sort_key from others),
  'other groups are untouched');

select throws_ok($$ select public.place_item(pg_temp.item('Sahne'), pg_temp.item('Joghurt'), 'middle') $$,
  '22023', 'invalid_edge', 'the edge is before or after');
select throws_ok($$ select public.place_item(pg_temp.item('Sahne'), pg_temp.item('Sahne'), 'after') $$,
  '22023', 'invalid_anchor', 'an item is not its own anchor');
update public.items set status = 'bought' where name = 'Eier';
select throws_ok($$ select public.place_item(pg_temp.item('Sahne'), pg_temp.item('Eier'), 'after') $$,
  '22023', 'invalid_anchor', 'the anchor must be active');
select throws_ok($$ select public.place_item(gen_random_uuid(), pg_temp.item('Sahne'), 'after') $$,
  'P0002', 'item_not_found', 'a missing item');
select throws_ok($$ select public.place_item(pg_temp.item('Sahne'), gen_random_uuid(), 'after') $$,
  'P0002', 'item_not_found', 'a missing anchor');

-- move_item: the end of group (store, category).
select results_eq(
  $$ select name, store_id, category_id from public.move_item(pg_temp.item('Joghurt'), null, pg_temp.cat('produce')) $$,
  $$ select 'Joghurt', null::uuid, pg_temp.cat('produce') $$,
  'move_item returns the moved row'
);
insert into public.items (household_id, name) select id, 'Apfel' from he;
select public.move_item(pg_temp.item('Sahne'), null, pg_temp.cat('produce'));
select is(pg_temp.walk(null, pg_temp.cat('produce')), array['Joghurt', 'Apfel', 'Sahne'],
  'a moved item goes to the end of the new group');
select is((select category_id from public.category_memory where item_key = 'sahn'), pg_temp.cat('produce'),
  'the category move is learned');
select is((select count(*)::int from public.item_store_memory where item_key = 'sahn'), 0,
  'moving to no store forgets the store');
select public.move_item(pg_temp.item('Sahne'), pg_temp.store('dm'), null);
select results_eq(
  $$ select store_id, category_id from public.items where name = 'Sahne' $$,
  $$ select pg_temp.store('dm'), pg_temp.cat('produce') $$,
  'a null category keeps the category'
);
select public.move_item(pg_temp.item('Apfel'), null, pg_temp.cat('produce'));
select is(pg_temp.walk(null, pg_temp.cat('produce')), array['Joghurt', 'Apfel'],
  'a move within its own group goes to the end of it');
select throws_ok($$ select public.move_item(gen_random_uuid(), null, null) $$,
  'P0002', 'item_not_found', 'move_item of a missing item');

-- reorder_stores: every store once.
select lives_ok(
  $$ select public.reorder_stores((select id from he), array[pg_temp.store('edeka'), pg_temp.store('dm'), pg_temp.store('lidl')]) $$,
  'a full store order is accepted'
);
select results_eq(
  $$ select seed_key, sort_order from public.stores where household_id = (select id from he) order by sort_order $$,
  $$ values ('edeka', 10), ('dm', 20), ('lidl', 30) $$,
  'and numbered 10, 20, 30'
);
select throws_ok($$ select public.reorder_stores((select id from he), array[pg_temp.store('edeka'), pg_temp.store('dm')]) $$,
  '22023', 'invalid_store_order', 'a store missing');
select throws_ok(
  $$ select public.reorder_stores((select id from he), array[pg_temp.store('edeka'), pg_temp.store('dm'), pg_temp.store('dm')]) $$,
  '22023', 'invalid_store_order', 'a store twice');
select throws_ok(
  $$ select public.reorder_stores((select id from he),
       array[pg_temp.store('edeka'), pg_temp.store('dm'), pg_temp.store('lidl'), gen_random_uuid()]) $$,
  '22023', 'invalid_store_order', 'an unknown store');

-- add_item and add_items: the parser, explicit values, duplicates.
delete from public.items;
select results_eq(
  $$ select name, quantity, (select seed_key from public.categories c where c.id = category_id)
     from public.add_items((select id from he), array['2 Tomaten', 'Hack 500 g']) $$,
  $$ values ('Tomaten', '2', 'produce'), ('Hack', '500 g', 'meat') $$,
  'old payloads still parse the quantity and classify'
);
create temp table pampers as
  select * from public.add_item((select id from he), 'Windeln Pampers Größe 3');
grant select on pampers to authenticated;
select results_eq(
  $$ select name, brand, properties, quantity, store_id from pampers $$,
  $$ select 'Windeln', 'Pampers', 'Größe 3', null::text, pg_temp.store('dm') $$,
  'add_item splits brand and properties and takes the drugstore hint'
);
select results_eq(
  $$ select id from public.add_item((select id from he), 'pampers windeln größe 3') $$,
  $$ select id from pampers $$,
  'the same item in another order is already on the list'
);
select is(
  (select count(*)::int from public.add_items((select id from he), array['Windeln Pampers Größe 4', 'Windeln Größe 3'])
   where id <> (select id from pampers)),
  2, 'another size or no brand is another item'
);
select results_eq(
  $$ select brand, properties, quantity, store_id
     from public.add_item((select id from he), 'Windeln Pampers Größe 3', pg_temp.store('lidl'), 'Lillydoo', 'Größe 5', '2') $$,
  $$ select 'Lillydoo', 'Größe 5', '2', pg_temp.store('lidl') $$,
  'explicit store, brand, properties and quantity replace the parsed ones'
);
select is((select count(*)::int from public.household_brands where brand_key = 'lillydoo'), 1,
  'an explicit unknown brand is learned');
insert into public.items (household_id, name) select id, 'Windeln Babylove Größe 2' from he;
select is(
  (select name from public.add_item((select id from he), 'Windeln Babylove Größe 2')),
  'Windeln Babylove Größe 2', 'a row written before the parser is found by its whole text'
);
select is((select name from public.add_item((select id from he), 'Tomate')), 'Tomaten', '"Tomate" is still "2 Tomaten"');
select is_empty($$ select * from public.add_item((select id from he), '  ') $$, 'a blank entry adds nothing');

-- Caps on the entry paths (review 0 and 1): parsed text never exceeds a column, an explicit
-- over-long field is refused with 22001 before anything is written.
select results_eq(
  $$ select char_length(name) <= 120, char_length(coalesce(brand, '')) <= 60,
            char_length(coalesce(properties, '')) <= 120, char_length(coalesce(quantity, '')) <= 40
     from public.add_item((select id from he), repeat('Langerartikelname ', 30) || 'Größe ' || repeat('9', 300)) $$,
  $$ values (true, true, true, true) $$,
  'an over-long entry is added, every field within its cap'
);
select is((select count(*)::int from public.items where name like 'Langerartikelname %'), 1, 'and it is stored');
select results_eq(
  $$ select char_length(properties) <= 120 from public.parse_item((select id from he),
       'Saft ' || repeat('Erdbeere Vanille Mango Kokos ', 12) || repeat('1', 300) || ' %') $$,
  $$ values (true) $$,
  'parsed properties stop at 120 characters'
);
select results_eq(
  $$ select name from public.parse_item((select id from he), repeat('x', 400)) $$,
  $$ values (repeat('x', 120)) $$,
  'one 400-character word is cut to 120'
);
select throws_ok($$ select * from public.add_item((select id from he), 'Tee', p_brand => repeat('b', 61)) $$,
  '22001', null, 'an explicit brand over 60 characters is refused');
select throws_ok($$ select * from public.add_item((select id from he), 'Tee', p_properties => repeat('p', 121)) $$,
  '22001', null, 'explicit properties over 120 characters are refused');
select throws_ok($$ select * from public.add_item((select id from he), 'Tee', p_quantity => repeat('9', 41)) $$,
  '22001', null, 'an explicit quantity over 40 characters is refused');
select is((select count(*)::int from public.items where name = 'Tee'), 0, 'nothing was written for them');

select * from finish();
rollback;
