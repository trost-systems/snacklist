begin;
select plan(123);

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
create temp table alice_store as select public.add_store((select id from ha), 'Supermarkt') as id;
update public.items
set category_id = (select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks'),
    store_id = (select id from alice_store)
where household_id = (select id from ha);
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

-- Job 169b: Bob in two households sees both and still nothing of Alice's.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb2 as select id from public.create_household(p_request_id => gen_random_uuid(), p_name => 'Bob 2');
insert into public.items (household_id, name) select id, 'Tee' from hb2;
grant select on hb2 to authenticated;
select results_eq($$ select name from public.households order by name $$, $$ values ('Bob'), ('Bob 2') $$,
  'a user in two households sees both households');
select is((select count(*)::int from public.items where household_id in ((select id from hb), (select id from hb2))),
  2, 'and the items of both');
select is((select count(*)::int from public.items where household_id = (select id from ha)), 0,
  'and still no item of another household');
select results_eq($$ select name from public.my_households() order by name $$, $$ values ('Bob'), ('Bob 2') $$,
  'my_households lists only the caller''s memberships');
select throws_ok($$ select * from public.household_members_of((select id from ha)) $$, '42501', 'not_member',
  'household_members_of another household is refused');
select throws_ok($$ select public.set_default_household((select id from ha)) $$, '42501', 'not_member',
  'another household cannot become the default');
select throws_ok($$ select public.leave_household((select id from ha)) $$, '42501', 'not_member',
  'leaving another household is refused');
select throws_ok($$ select public.create_personal_access_token('x', (select id from ha)) $$, '42501', 'not_a_member',
  'a token for another household is refused');
select is(public.leaves_unlocked((select id from ha)), false, 'leaves_unlocked tells nothing of another household');
insert into public.feedback (id, household_id, message, app_version, build, platform, os_version, locale, screen)
values ('30000000-0000-4000-8000-0000000001b2', (select id from ha), 'Als Alices Haushalt', '0.1.0', '1', 'web',
  'Firefox on Linux', 'de', 'list');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.households where id = (select id from hb2)), 0,
  'Alice does not see Bob''s second household');
select is((select count(*)::int from public.household_members where household_id = (select id from hb2)), 0,
  'nor its members');
set local role postgres;
select is((select household_id from public.feedback where id = '30000000-0000-4000-8000-0000000001b2'),
  (select id from hb), 'feedback naming another household lands in the sender''s default');

-- Job 169b W2: who joined through an invite, roles and removal stay inside the household.
insert into public.invites (household_id, code, created_by)
select id, 'BBBB2222', '00000000-0000-0000-0000-0000000000b1' from hb;
insert into public.invite_uses (invite_id, household_id, user_id)
select inv.id, ha.id, '00000000-0000-0000-0000-0000000000a1' from inv, ha;
insert into public.invite_uses (invite_id, household_id, user_id)
select i.id, i.household_id, '00000000-0000-0000-0000-0000000000b1'
from public.invites i, hb where i.household_id = hb.id and i.code = 'BBBB2222';
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.invite_uses where household_id = (select id from ha)), 0,
  'invite_uses of another household are invisible');
select is((select count(*)::int from public.invite_uses where household_id = (select id from hb)), 1,
  'a member reads their own household''s invite_uses');
select throws_ok($$ select * from public.household_invites((select id from ha)) $$, '42501', 'not_member',
  'household_invites of another household is refused');
select throws_ok($$ select * from public.invite_joins((select id from inv)) $$, '42501', 'not_member',
  'invite_joins of another household''s invite is refused');
select throws_ok($$ select public.create_invite((select id from ha), 'group') $$, '42501', 'not_a_member',
  'a group link for another household is refused');
select throws_ok(
  $$ select public.remove_member((select id from ha), '00000000-0000-0000-0000-0000000000a1') $$,
  '42501', 'not_member', 'removing a member of another household is refused');
select throws_ok(
  $$ select public.set_member_role((select id from ha), '00000000-0000-0000-0000-0000000000a1', 'admin') $$,
  '42501', 'not_member', 'changing a role in another household is refused');
set local role postgres;
insert into public.household_removals (household_id, user_id)
select id, '00000000-0000-0000-0000-0000000000b1'::uuid from ha
union all select id, '00000000-0000-0000-0000-0000000000a1'::uuid from hb;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select count(*) from public.household_removals where household_id = (select id from ha) $$,
  '42501', null, 'household_removals of another household are unreadable, even the reader''s own removal');
select throws_ok($$ select count(*) from public.household_removals where household_id = (select id from hb) $$,
  '42501', null, 'and so are their own household''s: only remove_member and check_invite read them');
select throws_ok($$ insert into public.household_removals (household_id, user_id)
  select id, '00000000-0000-0000-0000-0000000000a1' from hb $$, '42501', null,
  'household_removals are written by remove_member only');
set local role postgres;

-- Job 169b W3: lists, "Ich bringe" claims and join requests stay inside the household.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'carl@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.create_list((select id from ha), 'Sommerfest', 'f3000000-0000-4000-8000-000000000001');
select public.claim_item((select id from alice_item), '2');
set local role postgres;
insert into public.join_requests (id, household_id, user_id) values
  ('f3000000-0000-4000-8000-0000000000c1', (select id from ha), '00000000-0000-0000-0000-0000000000c1'),
  ('f3000000-0000-4000-8000-0000000000b1', (select id from ha), '00000000-0000-0000-0000-0000000000b1');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.lists where household_id = (select id from ha)), 0,
  'lists of another household are invisible');
select is((select count(*)::int from public.item_claims where household_id = (select id from ha)), 0,
  'item_claims of another household are invisible');
select results_eq($$ select id from public.join_requests $$,
  $$ values ('f3000000-0000-4000-8000-0000000000b1'::uuid) $$,
  'join_requests: a requester sees their own, not another requester''s');
select throws_ok($$ select public.create_list((select id from ha), 'X', gen_random_uuid()) $$,
  '42501', 'not_a_member', 'creating a list in another household is refused');
select throws_ok($$ select public.rename_list('f3000000-0000-4000-8000-000000000001', 'X') $$,
  '42501', 'not_a_member', 'renaming another household''s list is refused');
select throws_ok($$ select public.move_list('f3000000-0000-4000-8000-000000000001', 0) $$,
  '42501', 'not_a_member', 'moving another household''s list is refused');
select throws_ok($$ select public.delete_list('f3000000-0000-4000-8000-000000000001') $$,
  '42501', 'not_a_member', 'deleting another household''s list is refused');
select throws_ok($$ select public.claim_item((select id from alice_item), null) $$,
  '42501', 'not_a_member', 'claiming another household''s item is refused');
select throws_ok($$ select public.add_list_item((select id from ha), 'f3000000-0000-4000-8000-000000000001', 'X') $$,
  '42501', 'not_a_member', 'adding to another household''s list is refused');
select throws_ok($$ select * from public.household_join_requests((select id from ha)) $$,
  '42501', 'not_member', 'household_join_requests of another household is refused');
select throws_ok($$ select public.decide_join_request('f3000000-0000-4000-8000-0000000000c1', true) $$,
  'P0002', 'request_not_found', 'deciding another household''s request is refused');
select throws_ok($$ select public.set_join_approval((select id from ha), true) $$,
  '42501', 'not_member', 'switching another household''s approval is refused');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.join_requests), 2, 'the owner sees her household''s requests');
set local role postgres;

-- Job 190: Bob neither changes Alice's household currency nor prices her items.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is_empty($$ update public.households set currency = 'CHF' where id = (select id from ha) returning id $$,
  'households.currency: another household''s currency is not updated');
select is_empty($$ update public.items set price_unit_micros = 1, price_basis = 'unit', price_per = 'piece',
  price_currency = 'EUR', priced_at = now() where id = (select id from alice_item) returning id $$,
  'items price: another household''s item is not priced');
set local role postgres;
select results_eq(
  $$ select h.currency, i.price_unit_micros from public.households h join public.items i on i.household_id = h.id
     where i.id = (select id from alice_item) $$,
  $$ values ('EUR', null::bigint) $$,
  'Alice''s currency and item price are unchanged');

-- Job 185: a user's own premium is theirs alone (per_user_premium.test.sql: also within a household).
select public.promotional_premium_sync_user('00000000-0000-0000-0000-0000000000a1', true, null);
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.user_entitlements), 0, 'user_entitlements: Bob does not read Alice''s premium');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.user_entitlements), 1, 'user_entitlements: Alice reads her own');
set local role postgres;

-- Job 199: the grocery log's trips stay inside the household.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.save_trip((select id from ha), 'f1990000-0000-4000-8000-0000000000a1', (select id from alice_store),
  current_date, '[{"name": "Milch"}]');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.trip_history((select id from ha), current_date) $$,
  '42501', 'not_a_member', 'trips of another household are invisible');
select throws_ok($$ select from public.trips $$, '42501', null, 'trips are read through trip_history only');
select throws_ok($$ select public.save_trip((select id from ha), gen_random_uuid(), null, current_date, '[{"name": "X"}]') $$,
  '42501', 'not_a_member', 'logging a trip in another household is refused');
select throws_ok($$ select public.save_trip((select id from hb), 'f1990000-0000-4000-8000-0000000000a1', null,
  current_date, '[{"name": "X"}]') $$,
  '22023', 'other_household', 'saving over another household''s trip id is refused');
select throws_ok($$ select public.save_trip((select id from hb), gen_random_uuid(), (select id from alice_store),
  current_date, '[{"name": "X"}]') $$,
  'P0002', 'store_not_found', 'a trip at another household''s store is refused');
select throws_ok($$ select public.delete_trip('f1990000-0000-4000-8000-0000000000a1') $$,
  '42501', 'not_a_member', 'deleting another household''s trip is refused');
select throws_ok($$ insert into public.trips (id, household_id, shopped_on, items)
  select gen_random_uuid(), id, current_date, '[{"name": "X"}]' from hb $$,
  '42501', null, 'trips are written by save_trip only, even in the own household');
set local role postgres;
select is((select items #>> '{0,name}' from public.trips where id = 'f1990000-0000-4000-8000-0000000000a1'), 'Milch',
  'Alice''s trip is untouched');

-- Job 234: trip-mode sessions stay inside the household.
create temp table alice_session as select jsonb_build_object('id', 'f2340000-0000-4000-8000-0000000000a1',
  'list_id', null, 'started_at', '2026-11-14T09:00:00Z', 'ended_at', '2026-11-14T09:20:00Z',
  'active_seconds', 1200, 'end_reason', 'user', 'source', 'manual', 'currency', 'EUR',
  'shopped_on', current_date::text, 'pauses', '[]'::jsonb,
  'lines', jsonb_build_array(jsonb_build_object('key', 'k', 'name', 'Milch', 'planned', true, 'bought', true,
    'store_id', (select id from alice_store), 'store_name', 'Supermarkt'))) as t;
grant select on alice_session to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.save_trip_session((select id from ha), (select t from alice_session), true);
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.trip_session((select id from ha), 'f2340000-0000-4000-8000-0000000000a1') $$,
  '42501', 'not_a_member', 'trip sessions of another household are invisible');
select throws_ok($$ select public.trip_session((select id from hb), 'f2340000-0000-4000-8000-0000000000a1') $$,
  'P0002', 'trip_not_found', 'also under the own household');
select throws_ok($$ select from public.trip_sessions $$, '42501', null, 'trip sessions are read through trip_session only');
select throws_ok($$ select public.save_trip_session((select id from ha), (select t from alice_session), true) $$,
  '42501', 'not_a_member', 'saving a session in another household is refused');
select throws_ok($$ select public.save_trip_session((select id from hb), (select t from alice_session), true) $$,
  '22023', 'other_household', 'saving over another household''s session id is refused');
select throws_ok($$ select public.mark_trip_line_planned('f2340000-0000-4000-8000-0000000000a1', 'k', true) $$,
  '42501', 'not_a_member', 'marking another household''s line is refused');
select throws_ok($$ select public.delete_trip_session('f2340000-0000-4000-8000-0000000000a1') $$,
  '42501', 'not_a_member', 'deleting another household''s session is refused');
select throws_ok($$ insert into public.trip_sessions (id, household_id, started_at, ended_at, active_seconds,
    end_reason, source, currency, shopped_on)
  select gen_random_uuid(), id, now(), now(), 0, 'user', 'manual', 'EUR', current_date from hb $$,
  '42501', null, 'trip sessions are written by save_trip_session only, even in the own household');
select public.save_trip_session((select id from hb),
  (select t || '{"id": "f2340000-0000-4000-8000-0000000000b1"}' from alice_session), true);
set local role postgres;
select is((select (store_id, store_name)::text from public.trips where session_id = 'f2340000-0000-4000-8000-0000000000b1'),
  (null::uuid, 'Supermarkt')::text, 'a line at another household''s store logs no store id');
select is((select (household_id, started_by)::text from public.trip_sessions where id = 'f2340000-0000-4000-8000-0000000000a1'),
  ((select id from ha), '00000000-0000-0000-0000-0000000000a1'::uuid)::text, 'Alice''s session is untouched');

-- Realtime sends a delete's replica identity (the primary key) to every subscriber of the table,
-- without RLS or filters. No published table may key its rows by a person.
select is(
  (select coalesce(string_agg(distinct c.relname || '.' || a.attname, ', '), '')
   from pg_publication_tables pt
   join pg_class c on c.relname = pt.tablename
   join pg_namespace n on n.oid = c.relnamespace and n.nspname = pt.schemaname
   join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   join pg_constraint fk on fk.conrelid = c.oid and fk.contype = 'f' and a.attnum = any(fk.conkey)
     and fk.confrelid = 'auth.users'::regclass
   where pt.pubname = 'supabase_realtime'
     and (c.relreplident = 'f' or exists (
       select from pg_index i where i.indrelid = c.oid and a.attnum = any(i.indkey)
         and ((c.relreplident = 'd' and i.indisprimary) or (c.relreplident = 'i' and i.indisreplident))))),
  '', 'no realtime delete event names a user');

select * from finish();
rollback;
