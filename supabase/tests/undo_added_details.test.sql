-- Job 315: the add sheet's Rückgängig (public.undo_add) takes back the store and category picked
-- in the details of the item just added (flag add-feedback-list). Those picks reach the server as
-- an update of the new item (items_learn), not with the insert, so the insert's undo marks never
-- covered them. Any other delete keeps what an edit taught, as the spec's classifier test wants.
begin;
select plan(27);

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

create temp table t (name text primary key, learned text, offer text, id uuid);
grant all on t to authenticated;

-- 1. Nothing learned about Quark yet: add, pick Wochenmarkt and Getränke, Rückgängig.
insert into t select 'quark', pg_temp.learned('Quark'), pg_temp.offer('Quark'), pg_temp.add('Quark');
select is((select learned from t where name = 'quark'), null, 'nothing is learned about Quark yet');
select pg_temp.pick_store((select id from t where name = 'quark'), 'Wochenmarkt');
select pg_temp.pick_category((select id from t where name = 'quark'), 'Getränke');
select is(pg_temp.offer('Quark'), 'Wochenmarkt / Getränke', 'the picks in the details teach the next Quark');
select public.undo_add((select id from t where name = 'quark'));
select is(pg_temp.learned('Quark'), null, 'after Rückgängig nothing is learned about Quark, as before the add');
select is(pg_temp.offer('Quark'), (select offer from t where name = 'quark'),
  'after Rückgängig the next Quark is offered as before the add');

-- 2. Joghurt learned at Rewe under Sonstiges (picked with an earlier add): the picks of a new add
-- and its Rückgängig leave that lesson exactly as it was.
select pg_temp.buy(pg_temp.add('Joghurt', 'Rewe', 'Sonstiges'));
insert into t select 'joghurt', pg_temp.learned('Joghurt'), pg_temp.offer('Joghurt'), pg_temp.add('Joghurt');
select is((select offer from t where name = 'joghurt'), 'Rewe / Sonstiges', 'Joghurt is learned at Rewe under Sonstiges');
select pg_temp.pick_store((select id from t where name = 'joghurt'), 'Wochenmarkt');
select pg_temp.pick_category((select id from t where name = 'joghurt'), 'Getränke');
select pg_temp.pick_store((select id from t where name = 'joghurt'), 'Aldi');
select is(pg_temp.offer('Joghurt'), 'Aldi / Getränke', 'the last picks teach the next Joghurt');
select public.undo_add((select id from t where name = 'joghurt'));
select is(pg_temp.learned('Joghurt'), (select learned from t where name = 'joghurt'),
  'after Rückgängig the Joghurt lesson is as before the add, counts and times included');
select is(pg_temp.offer('Joghurt'), 'Rewe / Sonstiges', 'after Rückgängig the next Joghurt is at Rewe under Sonstiges');

-- 3. A pick of the store Quark was learned with, and back: the count goes back too.
select pg_temp.buy(pg_temp.add('Butter', 'Aldi'));
insert into t select 'butter', pg_temp.learned('Butter'), pg_temp.offer('Butter'), pg_temp.add('Butter');
select pg_temp.pick_store((select id from t where name = 'butter'), 'Rewe');
select pg_temp.pick_store((select id from t where name = 'butter'), 'Aldi');
select public.undo_add((select id from t where name = 'butter'));
select is(pg_temp.learned('Butter'), (select learned from t where name = 'butter'),
  'after Rückgängig Butter is learned at Aldi once, as before the add');

-- 4. Ohne Laden picked in the details forgets the remembered store; Rückgängig brings it back.
select pg_temp.buy(pg_temp.add('Sahne', 'Wochenmarkt'));
insert into t select 'sahne', pg_temp.learned('Sahne'), pg_temp.offer('Sahne'), pg_temp.add('Sahne');
select pg_temp.pick_store((select id from t where name = 'sahne'), null);
select is(pg_temp.offer('Sahne'), '- / Kühlregal', 'Ohne Laden teaches the next Sahne no store');
select public.undo_add((select id from t where name = 'sahne'));
select is(pg_temp.learned('Sahne'), (select learned from t where name = 'sahne'),
  'after Rückgängig Sahne is learned at Wochenmarkt again, and no store is cleared');
select is(pg_temp.offer('Sahne'), 'Wochenmarkt / Kühlregal', 'after Rückgängig the next Sahne is at Wochenmarkt');

-- 5. Ohne Laden and a store picked in turn, either way round: Rückgängig ends where it began.
insert into t select 'sahne-2', pg_temp.learned('Sahne'), null, pg_temp.add('Sahne');
select pg_temp.pick_store((select id from t where name = 'sahne-2'), null);
select pg_temp.pick_store((select id from t where name = 'sahne-2'), 'Wochenmarkt');
select pg_temp.pick_store((select id from t where name = 'sahne-2'), null);
select public.undo_add((select id from t where name = 'sahne-2'));
select is(pg_temp.learned('Sahne'), (select learned from t where name = 'sahne-2'),
  'Ohne Laden, Wochenmarkt, Ohne Laden, Rückgängig: Sahne is learned as before the add');
insert into t select 'sahne-3', pg_temp.learned('Sahne'), null, pg_temp.add('Sahne');
select pg_temp.pick_store((select id from t where name = 'sahne-3'), 'Aldi');
select pg_temp.pick_store((select id from t where name = 'sahne-3'), null);
select public.undo_add((select id from t where name = 'sahne-3'));
select is(pg_temp.learned('Sahne'), (select learned from t where name = 'sahne-3'),
  'Aldi, Ohne Laden, Rückgängig: Sahne is learned as before the add');

-- 6. Without Rückgängig the picks stay learned.
insert into t select 'schmand', null, null, pg_temp.add('Schmand');
select pg_temp.pick_store((select id from t where name = 'schmand'), 'Aldi');
select pg_temp.pick_category((select id from t where name = 'schmand'), 'Getränke');
select pg_temp.buy((select id from t where name = 'schmand'));
select is(pg_temp.offer('Schmand'), 'Aldi / Getränke', 'kept picks teach the next Schmand');

-- 7. Any other delete keeps what an edit taught (the spec: move, delete, add again lands where
-- it was moved), and also the insert's pick-less add.
insert into t select 'quark-moved', null, null, pg_temp.add('Quark');
select pg_temp.pick_store((select id from t where name = 'quark-moved'), 'Aldi');
select pg_temp.pick_category((select id from t where name = 'quark-moved'), 'Getränke');
delete from public.items where id = (select id from t where name = 'quark-moved');
select is(pg_temp.offer('Quark'), 'Aldi / Getränke', 'a plain delete keeps the moves');

-- 8. Something else taught the name after the picks (another Kefir item bought at Rewe):
-- the Rückgängig leaves that lesson.
insert into t select 'kefir-old', null, null, pg_temp.add('Kefir');
insert into t select 'kefir', null, null, pg_temp.add('Kefir');
select pg_temp.pick_store((select id from t where name = 'kefir'), 'Rewe');
update public.items set store_id = pg_temp.store('Rewe'), status = 'bought'
where id = (select id from t where name = 'kefir-old');
select public.undo_add((select id from t where name = 'kefir'));
select ok(pg_temp.learned('Kefir') like '%Rewe x2%', 'a lesson taught after the picks survives the Rückgängig');

-- 9. A tick in a store (status and store in one update, the app's SetStatus) is a buy, not a
-- pick: nothing takes it back.
insert into t select 'senf', null, null, pg_temp.add('Senf');
update public.items set status = 'bought', store_id = pg_temp.store('Aldi') where id = (select id from t where name = 'senf');
select public.undo_add((select id from t where name = 'senf'));
select is(pg_temp.offer('Senf'), 'Aldi / Vorrat & Konserven', 'a buy in a store stays learned, also after undo_add');

-- 10. Another household's undo_add of the item does nothing: the items policies decide.
insert into t select 'zimt', null, null, pg_temp.add('Zimt');
select pg_temp.pick_store((select id from t where name = 'zimt'), 'Aldi');
select pg_temp.login('00000000-0000-0000-0000-0000000315d1');
select public.undo_add((select id from t where name = 'zimt'));
select pg_temp.login('00000000-0000-0000-0000-0000000315c1');
select is((select count(*)::int from public.items where id = (select id from t where name = 'zimt')), 1,
  'another user''s undo_add leaves the item');
select is(pg_temp.offer('Zimt'), 'Aldi / Vorrat & Konserven', 'and its lessons');
select public.undo_add((select id from t where name = 'zimt'));
select lives_ok($$ select public.undo_add((select id from t where name = 'zimt')) $$, 'a retried undo_add is no error');
select is(pg_temp.offer('Zimt'), '- / Vorrat & Konserven', 'the member''s undo_add takes the pick back');

-- 11. Ohne Laden after a remembered store that is deleted before the Rückgängig: the delete still
-- goes through, and the store's memory stays gone with the store.
insert into t select 'essig-old', null, null, pg_temp.add('Essig');
select pg_temp.pick_store((select id from t where name = 'essig-old'), 'Rewe');
select pg_temp.buy((select id from t where name = 'essig-old'));
insert into t select 'essig', null, null, pg_temp.add('Essig');
select pg_temp.pick_store((select id from t where name = 'essig'), null);
reset role;
delete from public.stores where id = pg_temp.store('Rewe');
select pg_temp.login('00000000-0000-0000-0000-0000000315c1');
select lives_ok($$ select public.undo_add((select id from t where name = 'essig')) $$,
  'Rückgängig works after the stashed store was deleted');
select is(pg_temp.learned('Essig'), null, 'nothing is learned about Essig: its store is gone, the clear taken back');

-- 12. Ohne Laden picked with the add (the flag-off chips; put_item clears the guessed store with
-- an update): the undo brings the remembered store back. The clear the insert records stays, as on
-- main, and the memory wins over it.
insert into t select 'birne-old', null, null, pg_temp.add('Birne', 'Wochenmarkt');
select pg_temp.buy((select id from t where name = 'birne-old'));
insert into t select 'birne', pg_temp.learned('Birne'), null, (select i.id from public.put_item(
  p_id => gen_random_uuid(), p_household => (select id from hc), p_list => null, p_name => 'Birne',
  p_no_store => true, p_category_store => true) i);
select is(pg_temp.offer('Birne'), '- / Obst & Gemüse', 'an add with Ohne Laden teaches no store');
select public.undo_add((select id from t where name = 'birne'));
select is(pg_temp.offer('Birne'), 'Wochenmarkt / Obst & Gemüse', 'the undo puts Wochenmarkt back');

-- 13. An undo sent late (queued offline) still takes back the add's own pick, which a plain delete
-- only does within 10 minutes.
insert into t select 'honig', null, null, pg_temp.add('Honig', 'Aldi');
reset role;
update public.item_store_memory set updated_at = updated_at - interval '11 minutes', undo_at = undo_at - interval '11 minutes'
where item_key = 'honig';
select pg_temp.login('00000000-0000-0000-0000-0000000315c1');
select public.undo_add((select id from t where name = 'honig'));
select is(pg_temp.learned('Honig'), null, 'a late undo takes back the pick made with the add');

select * from finish();
rollback;
