-- Job 58: add_store, rename_store and delete_store; store names unique per household ignoring
-- case and spacing.
begin;
select plan(24);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000005a1', 'sara@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000005a1');
create temp table hs as select id from public.create_household('Sara');
grant select on hs to authenticated;

create function pg_temp.store(p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = (select id from hs) and name = p_name;
$$;

-- Adding.
create temp table rewe as select public.add_store((select id from hs), '  Rewe   City ') as id;
grant select on rewe to authenticated;
select is((select name from public.stores where id = (select id from rewe)), 'Rewe City',
  'the name is trimmed and its spaces collapsed');
select is((select seed_key from public.stores where id = (select id from rewe)), null, 'a new store has no seed key');
select is(
  (select sort_order from public.stores where id = (select id from rewe)),
  (select max(sort_order) from public.stores where household_id = (select id from hs) and id <> (select id from rewe)) + 10,
  'a new store goes after the last one'
);
select is(public.add_store((select id from hs), 'rewe  city'), (select id from rewe),
  'the same name in another case and spacing returns the existing store');
select is(public.add_store((select id from hs), 'LIDL'), pg_temp.store('Lidl'), 'a preset store is found by name too');
select is((select count(*)::int from public.stores where household_id = (select id from hs)), 4,
  'no duplicate was created');
select throws_ok($$ select public.add_store((select id from hs), '   ') $$, '22023', 'store_name_empty',
  'an empty name is refused');
select lives_ok(format($$ select public.add_store((select id from hs), %L) $$, repeat('x', 40)), '40 characters are fine');
select throws_ok(format($$ select public.add_store((select id from hs), %L) $$, repeat('y', 41)),
  '22001', 'store_name_too_long', '41 characters are refused');
select throws_ok(
  $$ insert into public.stores (household_id, name, sort_order) select id, 'rewe city', 99 from hs $$,
  '23505', null, 'the table refuses a name that differs only in case'
);

-- The layout: the household's route order, every category, none hidden.
select results_eq(
  $$ select category_id, hidden from public.store_category_order where store_id = (select id from rewe) order by sort_order $$,
  $$ select id, false from public.categories where household_id = (select id from hs) order by sort_order, name $$,
  'a new store starts from the route order with every category shown'
);
select lives_ok($$ select public.create_category((select id from hs), 'Bio') $$, 'a category is added');
select is(
  (select count(*)::int from public.store_category_order where store_id = (select id from rewe)),
  (select count(*)::int from public.categories where household_id = (select id from hs)),
  'a category added later joins the new store''s layout'
);

-- Renaming.
select lives_ok($$ select public.rename_store((select id from rewe), ' Rewe  Markt ') $$, 'a store is renamed');
select is((select name from public.stores where id = (select id from rewe)), 'Rewe Markt', 'the new name is cleaned');
select throws_ok($$ select public.rename_store((select id from rewe), 'edeka') $$, '23505', 'store_name_taken',
  'renaming onto another store''s name is refused');
select lives_ok($$ select public.rename_store(pg_temp.store('dm'), 'DM') $$, 'a preset store changes case');
select is((select seed_key from public.stores where id = pg_temp.store('DM')), 'dm', 'and stays that chain');
select lives_ok($$ select public.rename_store(pg_temp.store('DM'), 'Rossmann') $$, 'a preset store gets another name');
select is((select seed_key from public.stores where id = pg_temp.store('Rossmann')), null,
  'and is no longer that chain');

-- Deleting.
insert into public.items (household_id, name, store_id) select id, 'Milch', (select id from rewe) from hs;
insert into public.items (household_id, name, store_id, status) select id, 'Butter', (select id from rewe), 'bought' from hs;
select ok(
  exists (select 1 from public.item_store_memory where store_id = (select id from rewe)),
  'tagging taught the store'
);
select lives_ok($$ select public.delete_store((select id from rewe)) $$, 'the store is deleted');
select results_eq(
  $$ select name, store_id from public.items where household_id = (select id from hs) order by name $$,
  $$ values ('Butter', null::uuid), ('Milch', null::uuid) $$,
  'its items, open and bought, have no store now'
);
select is(
  (select count(*)::int from public.item_store_memory where store_id = (select id from rewe))
  + (select count(*)::int from public.store_category_order where store_id = (select id from rewe)),
  0, 'its memories and layout are gone'
);

select * from finish();
rollback;
