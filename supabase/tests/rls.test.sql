begin;
select plan(64);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Alice');
insert into public.items (household_id, name) select id, 'Milch' from ha;
create temp table inv as select * from public.create_invite((select id from ha));
-- Job 2: Alice's learned memories and catalog ids for the cross-household checks.
update public.items
set category_id = (select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks'),
    store_id = (select id from public.stores where household_id = (select id from ha) and seed_key = 'lidl')
where household_id = (select id from ha);
create temp table alice_store as select id from public.stores where household_id = (select id from ha) and seed_key = 'lidl';
create temp table alice_category as
  select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks';
-- Job 15: a learned brand and an item to place, move and reorder around.
update public.items set brand = 'Lillydoo' where household_id = (select id from ha) and name = 'Milch';
create temp table alice_item as select id, sort_key from public.items where household_id = (select id from ha) and name = 'Milch';
-- Job 8: a bought and then deleted item stays in Alice's history as a suggestion.
insert into public.items (household_id, name) select id, 'Kaffee' from ha;
update public.items set status = 'bought' where household_id = (select id from ha) and name = 'Kaffee';
delete from public.items where household_id = (select id from ha) and name = 'Kaffee';
-- Job 32b: a duplicate-hint merge (Möhren + Karotten) in Alice's household.
insert into public.items (id, household_id, name) select '32b00000-0000-4000-8000-000000000001', id, 'Möhren' from ha;
insert into public.items (id, household_id, name) select '32b00000-0000-4000-8000-000000000002', id, 'Karotten' from ha;
do $$ begin perform public.merge_items('32b00000-0000-4000-8000-0000000000a1',
  '32b00000-0000-4000-8000-000000000001', '32b00000-0000-4000-8000-000000000002'); end $$;

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household('Bob');
insert into public.items (household_id, name) select id, 'Brot' from hb;
grant select on ha, hb, inv, alice_store, alice_category, alice_item to authenticated, anon;
create temp table bob_item as select id from public.items where name = 'Brot';
grant select on bob_item to authenticated, anon;

-- Bob is signed in from here on and must not see or touch Alice's household.
select is((select count(*)::int from public.households), 1, 'a user sees only their own household');
select is((select count(*)::int from public.items where household_id = (select id from ha)), 0,
  'items of another household are invisible');
select is((select count(*)::int from public.categories where household_id = (select id from ha)), 0,
  'categories of another household are invisible');
select is((select count(*)::int from public.stores where household_id = (select id from ha)), 0,
  'stores of another household are invisible');
select is((select count(*)::int from public.store_category_order where household_id = (select id from ha)), 0,
  'store orders of another household are invisible');
select is((select count(*)::int from public.household_members where household_id = (select id from ha)), 0,
  'members of another household are invisible');
select is((select count(*)::int from public.invites), 0, 'invites of another household are invisible');
select is((select count(*)::int from public.item_events where household_id = (select id from ha)), 0,
  'history of another household is invisible');
select is((select count(*)::int from public.profiles), 1, 'profiles outside the household are invisible');
select is((select count(*)::int from public.suggest_items((select id from ha), '', 200)), 0,
  'suggestions from another household''s history are empty');
select is((select count(*)::int from public.item_merges where household_id = (select id from ha)), 0,
  'duplicate-hint merges of another household are invisible');
select throws_ok($$ select public.unmerge_items('32b00000-0000-4000-8000-0000000000a1') $$, '42501', null,
  'undoing another household''s merge is denied');

select throws_ok(
  $$ insert into public.items (household_id, name) select id, 'Fremd' from ha $$,
  '42501', null, 'inserting into another household is denied'
);
update public.items set name = 'Gehackt' where household_id = (select id from ha);
delete from public.items where household_id = (select id from ha);
delete from public.categories where household_id = (select id from ha);
select throws_ok(
  $$ update public.items set household_id = (select id from ha) where name = 'Brot' $$,
  '42501', null, 'moving an item into another household is denied'
);
select throws_ok(
  $$ select public.create_invite((select id from ha)) $$,
  '42501', 'not_a_member', 'creating an invite for another household is denied'
);
select throws_ok(
  $$ select public.revoke_invite((select id from inv)) $$,
  '42501', 'not_a_member', 'revoking an invite of another household is denied (job 22)'
);
select throws_ok(
  $$ select * from public.invite_attempts $$,
  '42501', null, 'the invite rate-limit log is not readable by clients'
);
select throws_ok(
  $$ insert into public.household_members (household_id, user_id) select id, '00000000-0000-0000-0000-0000000000b1' from ha $$,
  '42501', null, 'self-adding to a household without an invite is denied'
);
select throws_ok(
  $$ insert into public.item_events (household_id, item_id, action, item_name) select id, gen_random_uuid(), 'added', 'x' from hb $$,
  '42501', null, 'history is append-only through triggers'
);
select throws_ok(
  $$ select public.seed_household((select id from ha)) $$,
  '42501', null, 'seeding is internal'
);
select throws_ok(
  $$ select public.classify_item((select id from ha), 'Milch') $$,
  '42501', 'not_a_member', 'classifying for another household is denied (it would reveal its category ids)'
);
select is(
  (select seed_key from public.categories where id = public.classify_item((select id from hb), 'Milch')),
  'chilled', 'classifying for the own household works'
);

-- Job 2: learned memories and the catalog RPCs.
select is((select count(*)::int from public.category_memory), 0, 'category memories of another household are invisible');
select is((select count(*)::int from public.item_store_memory), 0, 'store memories of another household are invisible');
select throws_ok(
  $$ insert into public.category_memory (household_id, item_key, category_id) select id, 'x', (select id from alice_category) from ha $$,
  '42501', null, 'memories cannot be written directly'
);
select throws_ok($$ select public.suggest_store((select id from ha), 'Milch') $$, '42501', 'not_a_member',
  'suggest_store for another household is denied');
select throws_ok($$ select public.add_items((select id from ha), array['Milch']) $$, '42501', 'not_a_member',
  'add_items into another household is denied');
select throws_ok($$ select public.create_category((select id from ha), 'Fremd') $$, '42501', 'not_a_member',
  'creating a category in another household is denied');
select throws_ok($$ select public.reorder_categories((select id from ha), array[(select id from alice_category)]) $$,
  '42501', 'not_a_member', 'reordering another household''s categories is denied');
select throws_ok($$ select public.delete_category((select id from alice_category)) $$, '42501', 'not_a_member',
  'deleting another household''s category is denied');
select throws_ok(
  $$ select public.set_store_layout((select id from alice_store), array[(select id from alice_category)]) $$,
  '42501', 'not_a_member', 'changing another household''s store layout is denied'
);
update public.store_category_order set hidden = true where store_id = (select id from alice_store);

-- Job 15: learned brands, the parser, the add path and the walk-order RPCs.
select is((select count(*)::int from public.household_brands), 0, 'learned brands of another household are invisible');
select ok((select count(*) from public.brands) >= 300, 'the global brands are readable');
select throws_ok(
  $$ insert into public.household_brands (household_id, brand_key, brand) select id, 'x', 'X' from hb $$,
  '42501', null, 'learned brands cannot be written directly'
);
select throws_ok($$ insert into public.brands (brand) values ('Fremd') $$, '42501', null, 'global brands are read-only');
select throws_ok($$ select * from public.parse_item((select id from ha), 'Milch') $$, '42501', 'not_a_member',
  'parse_item for another household is denied');
select throws_ok($$ select * from public.add_item((select id from ha), 'Milch') $$, '42501', 'not_a_member',
  'add_item into another household is denied');
select throws_ok($$ select public.place_item((select id from alice_item), (select id from bob_item), 'after') $$,
  'P0002', 'item_not_found', 'placing another household''s item is denied');
select throws_ok($$ select public.place_item((select id from bob_item), (select id from alice_item), 'after') $$,
  'P0002', 'item_not_found', 'an anchor in another household is not found');
select throws_ok($$ select public.move_item((select id from alice_item), null, null) $$,
  'P0002', 'item_not_found', 'moving another household''s item is denied');
select throws_ok($$ select public.move_item((select id from bob_item), null, (select id from alice_category)) $$,
  '23503', null, 'an item cannot be moved into another household''s category');
select throws_ok($$ select public.reorder_stores((select id from ha), array[(select id from alice_store)]) $$,
  '42501', 'not_a_member', 'reordering another household''s stores is denied');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select results_eq(
  $$ select item_key from public.category_memory union all select item_key from public.item_store_memory $$,
  $$ values ('milch'), ('milch') $$,
  'Alice''s memories are intact'
);
select is((select count(*)::int from public.store_category_order where store_id = (select id from alice_store) and hidden), 0,
  'the other user''s layout update changed nothing');
select results_eq(
  $$ select name from public.items where household_id = (select id from ha) order by name $$,
  $$ values ('Milch'), ('Möhren') $$,
  'the other user''s update and delete attempts changed nothing'
);
select is((select count(*)::int from public.categories where household_id = (select id from ha)), 11,
  'the other user''s category delete changed nothing');
select results_eq(
  $$ select sort_key, store_id, category_id from public.items where id = (select id from alice_item) $$,
  $$ select (select sort_key from alice_item), (select id from alice_store), (select id from alice_category) $$,
  'the other user''s place and move attempts changed nothing'
);
select results_eq($$ select brand from public.household_brands $$, $$ values ('Lillydoo') $$,
  'Alice sees her learned brand');
select results_eq($$ select name from public.suggest_items((select id from ha), '', 200) $$, $$ values ('Kaffee') $$,
  'Alice gets her own suggestions');
select pg_temp.anon();
set local role postgres;
select throws_ok(
  $$ insert into public.items (household_id, name, category_id)
     select (select id from ha), 'Mix', c.id from public.categories c where c.household_id = (select id from hb) limit 1 $$,
  '23503', null, 'even a privileged writer cannot point an item at another household''s category'
);

select pg_temp.anon();
select throws_ok($$ select public.classify_item((select id from ha), 'Milch') $$, '42501', null,
  'anon cannot classify');
set local role postgres;
select isnt(public.classify_item((select id from ha), 'Milch'), null,
  'trusted server paths without a user (service role, triggers) still classify');
select pg_temp.anon();
select throws_ok($$ select count(*) from public.items $$, '42501', null, 'anon cannot read items');
select throws_ok($$ select count(*) from public.brands $$, '42501', null, 'anon cannot read brands');
select throws_ok($$ select public.create_household('x') $$, '42501', null, 'anon cannot call household RPCs');

-- Job 21: feedback is insert-only. Bob's note lands in his own household whatever he claims,
-- he cannot send as Alice, and nobody reads notes back, Alice's included.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.feedback (id, message, app_version, build, platform, os_version, locale, screen)
values ('30000000-0000-4000-8000-0000000000b1', 'Bobs Notiz', '0.1.0', '1', 'web', 'Firefox on Linux', 'de', 'list');
select throws_ok(
  $$ insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'Als Alice', '0.1.0', '1', 'web',
       'Firefox on Linux', 'de', 'list') $$,
  '42501', null, 'feedback cannot be sent in another household member''s name');
select throws_ok($$ select count(*) from public.feedback $$, '42501', null, 'feedback is not readable by clients');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select count(*) from public.feedback where household_id = (select id from hb) $$, '42501', null,
  'not across households either');
set local role postgres;
select is((select household_id from public.feedback where id = '30000000-0000-4000-8000-0000000000b1'),
  (select id from hb), 'a note carries the sender''s household, not another one');

-- Job 47: ended memberships (for the buyer's claim) are service-only, in any household.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select count(*) from public.household_departures where household_id = (select id from ha) $$,
  '42501', null, 'departures of another household are not readable');
select throws_ok($$ select count(*) from public.household_departures where household_id = (select id from hb) $$,
  '42501', null, 'nor of one''s own');

-- Job 58: adding, renaming and deleting stores.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.add_store((select id from ha), 'Rewe') $$,
  '42501', 'not_a_member', 'adding a store to another household is denied');
select throws_ok($$ select public.rename_store((select id from alice_store), 'Aldi') $$,
  '42501', 'not_a_member', 'renaming another household''s store is denied');
select throws_ok($$ select public.delete_store((select id from alice_store)) $$,
  '42501', 'not_a_member', 'deleting another household''s store is denied');

select * from finish();
rollback;
