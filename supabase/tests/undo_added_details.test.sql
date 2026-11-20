-- The add sheet's Rückgängig (public.undo_add) is a plain delete of the item just added (job 322,
-- Peter t1071u): a store and category picked in its details stay learned, as after any delete.
-- Job 315 had it take them back.
begin;
select plan(12);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000315c1', 'carla@example.com'),
  ('00000000-0000-0000-0000-0000000315d1', 'dora@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000315c1');
create temp table hc as
  select id from public.create_household(p_name => 'Carla', p_stores => array['Rewe', 'Aldi', 'Wochenmarkt']);
grant select on hc to authenticated;

create function pg_temp.store(p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = (select id from hc) and name = p_name;
$$;
create function pg_temp.category(p_name text) returns uuid language sql as $$
  select id from public.categories where household_id = (select id from hc) and name = p_name;
$$;

-- Adds p_name as the add sheet does (put_item, flag input-stable-rows on) and answers its id.
create function pg_temp.add(p_name text, p_store text default null, p_category text default null)
returns uuid language sql as $$
  select i.id from public.put_item(
    p_id => gen_random_uuid(), p_household => (select id from hc), p_list => null, p_name => p_name,
    p_store => pg_temp.store(p_store), p_category => pg_temp.category(p_category),
    p_category_store => true) i;
$$;

-- A pick in the added item's details: the app's edit op, an update of the item.
create function pg_temp.pick_store(p_item uuid, p_store text) returns void language sql as $$
  update public.items set store_id = pg_temp.store(p_store) where id = p_item;
$$;
create function pg_temp.pick_category(p_item uuid, p_category text) returns void language sql as $$
  update public.items set category_id = pg_temp.category(p_category) where id = p_item;
$$;

-- Bought without teaching anything, so the next add of the name is a new item.
create function pg_temp.buy(p_item uuid) returns void language plpgsql as $$
begin
  perform set_config('family_groceries.learning', 'off', true);
  update public.items set status = 'bought' where id = p_item;
  perform set_config('family_groceries.learning', '', true);
end $$;

-- Everything the household learned about p_name's store and category, timestamps included.
create function pg_temp.learned(p_name text) returns text language sql as $$
  select nullif(concat_ws(' | ',
    (select string_agg(c.name || ' x' || m.corrections || ' @' || m.updated_at, ', ' order by c.name)
     from public.category_memory m join public.categories c on c.id = m.category_id
     where m.household_id = (select id from hc) and m.item_key = public.item_key(p_name)),
    (select string_agg(s.name || ' x' || m.times || ' @' || m.updated_at, ', ' order by s.name)
     from public.item_store_memory m join public.stores s on s.id = m.store_id
     where m.household_id = (select id from hc) and m.item_key = public.item_key(p_name)),
    (select 'cleared @' || c.updated_at from public.item_store_cleared c
     where c.household_id = (select id from hc) and c.item_key = public.item_key(p_name))), '');
$$;

-- The next add's offer: the typed row of the add sheet, its store and category.
create function pg_temp.offer(p_text text) returns text language sql as $$
  select coalesce(st.name, '-') || ' / ' || coalesce(c.name, '-')
  from public.suggest_entries((select id from hc), p_text, 8, true) s
  left join public.stores st on st.id = s.store_id
  left join public.categories c on c.id = s.category_id
  where s.source = 'typed';
$$;

create temp table t (name text primary key, id uuid);
grant all on t to authenticated;

-- 1. Store and category picked in the added Quark's details, then Rückgängig: the item goes, the
-- picks stay learned.
insert into t select 'quark', pg_temp.add('Quark');
select pg_temp.pick_store((select id from t where name = 'quark'), 'Wochenmarkt');
select pg_temp.pick_category((select id from t where name = 'quark'), 'Getränke');
select is(pg_temp.offer('Quark'), 'Wochenmarkt / Getränke', 'the picks in the details teach the next Quark');
select public.undo_add((select id from t where name = 'quark'));
select is((select count(*)::int from public.items where id = (select id from t where name = 'quark')), 0,
  'undo_add deletes the item');
select is(pg_temp.offer('Quark'), 'Wochenmarkt / Getränke', 'after Rückgängig the picks stay learned');

-- 2. The same as a plain delete: what the picks taught stays.
insert into t select 'joghurt', pg_temp.add('Joghurt');
select pg_temp.pick_store((select id from t where name = 'joghurt'), 'Aldi');
select pg_temp.pick_category((select id from t where name = 'joghurt'), 'Getränke');
delete from public.items where id = (select id from t where name = 'joghurt');
select is(pg_temp.offer('Joghurt'), 'Aldi / Getränke', 'a plain delete keeps the picks too');

-- 3. Ohne Laden picked in the details forgets the remembered store, also after Rückgängig.
select pg_temp.buy(pg_temp.add('Sahne', 'Wochenmarkt'));
insert into t select 'sahne', pg_temp.add('Sahne');
select pg_temp.pick_store((select id from t where name = 'sahne'), null);
select public.undo_add((select id from t where name = 'sahne'));
select is(pg_temp.offer('Sahne'), '- / Kühlregal', 'after Rückgängig Ohne Laden stays learned');

-- 4. A pick made with the add is taken back, as by any delete within 10 minutes.
insert into t select 'honig', pg_temp.add('Honig', 'Aldi');
select public.undo_add((select id from t where name = 'honig'));
select is(pg_temp.learned('Honig'), null, 'Rückgängig takes back the store picked with the add');

-- 5. The picks leave job 315's edit marks unwritten.
select is((select count(*)::int from public.category_memory where edit_item is not null)
  + (select count(*)::int from public.item_store_memory where edit_item is not null)
  + (select count(*)::int from public.item_store_cleared where edit_item is not null), 0,
  'no edit marks are written');

-- 6. Another household's undo_add of the item does nothing: the items policies decide.
insert into t select 'zimt', pg_temp.add('Zimt');
select pg_temp.pick_store((select id from t where name = 'zimt'), 'Aldi');
select pg_temp.login('00000000-0000-0000-0000-0000000315d1');
select public.undo_add((select id from t where name = 'zimt'));
select pg_temp.login('00000000-0000-0000-0000-0000000315c1');
select is((select count(*)::int from public.items where id = (select id from t where name = 'zimt')), 1,
  'another user''s undo_add leaves the item');
select is(pg_temp.offer('Zimt'), 'Aldi / Vorrat & Konserven', 'and its lessons');
select public.undo_add((select id from t where name = 'zimt'));
select is((select count(*)::int from public.items where id = (select id from t where name = 'zimt')), 0,
  'the member''s undo_add deletes it');
select lives_ok($$ select public.undo_add((select id from t where name = 'zimt')) $$, 'a retried undo_add is no error');
select is(pg_temp.offer('Zimt'), 'Aldi / Vorrat & Konserven', 'the pick stays learned');

select * from finish();
rollback;
