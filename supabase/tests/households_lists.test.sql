-- Job 169b wave 3, part K: several lists per household (docs/households/W3.md). Every household
-- has a first list; writes without a list (old store builds, Siri, Alexa) land there; the
-- duplicate rule is per list; lists are created, renamed, moved and deleted with their items.
begin;
select plan(61);
-- Job 352 revoked members' read of item_events; this file checks the history the trigger writes
-- as a member reads it under the policy that still guards it.
grant select on public.item_events to authenticated;

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.list_of(p_item uuid) returns text language sql security definer as $$
  select l.name from public.items i join public.lists l on l.id = i.list_id where i.id = p_item
$$;

create function pg_temp.lists_in(p_household uuid) returns text language sql security definer as $$
  select string_agg(l.name || ':' || l.position, ', ' order by l.position, l.created_at)
  from public.lists l where l.household_id = p_household
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'peter@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'lea@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Trost');
create temp table inv as select * from public.create_invite((select id from ha));
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
do $$ begin perform public.join_household((select code from inv)); end $$;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household(p_request_id => gen_random_uuid(), p_name => 'Bob');
create temp table list_b as select id from public.lists;
grant select on ha, hb, list_b to authenticated;

-- Every household starts with one list ----------------------------------------------------------

select is(pg_temp.lists_in((select id from ha)), 'Einkaufsliste:0', 'the old create_household gives the first list');
select is(pg_temp.lists_in((select id from hb)), 'Einkaufsliste:0', 'and so does the new one');
select pg_temp.as_postgres();
insert into public.households (id, name) values ('00000000-0000-4000-8000-0000000000f1', 'Direkt');
select is(pg_temp.lists_in('00000000-0000-4000-8000-0000000000f1'), 'Einkaufsliste:0',
  'a household inserted any other way has its first list too');
select is((select string_agg(coalesce(l.seed_key, '-'), ',') from public.lists l
  where l.household_id in ((select id from ha), (select id from hb), '00000000-0000-4000-8000-0000000000f1')),
  'main,main,main', 'every first list carries the seed key main, for the apps to name it');

-- Lists: create, rename, move ------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table first_a as select id from public.lists where household_id = (select id from ha);
create temp table fest as select * from public.create_list((select id from ha), '  Sommerfest ', 'f0000000-0000-4000-8000-000000000001');
grant select on first_a, fest to authenticated;
select is((select name from fest), 'Sommerfest', 'create_list trims the name');
select is((select position from fest), 1, 'a new list goes to the end');
select is((select created_by from fest), '00000000-0000-0000-0000-0000000000a1'::uuid, 'and records its creator');
select is((select seed_key from fest), null, 'a created list has no seed key');
select is((select id from public.create_list((select id from ha), 'Anders', 'f0000000-0000-4000-8000-000000000001')),
  'f0000000-0000-4000-8000-000000000001'::uuid, 'a retry with the same id answers the same list');
select is(pg_temp.lists_in((select id from ha)), 'Einkaufsliste:0, Sommerfest:1', 'and creates nothing');
select throws_ok($$ select public.create_list((select id from ha), '   ', gen_random_uuid()) $$,
  '22023', 'invalid_name', 'a blank name is refused');
select throws_ok($$ select public.create_list((select id from ha), repeat('x', 61), gen_random_uuid()) $$,
  '22023', 'invalid_name', 'a name past 60 characters is refused');
select throws_ok($$ select public.create_list((select id from ha), 'X', null) $$,
  '22023', 'id_required', 'the client id is required');
select throws_ok($$ select public.create_list((select id from hb), 'X', gen_random_uuid()) $$,
  '42501', 'not_a_member', 'no list in another household');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.create_list((select id from hb), 'X', 'f0000000-0000-4000-8000-000000000001') $$,
  '42501', 'not_a_member', 'another household''s list id is not answered');

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select is((select name from public.rename_list((select id from fest), 'Grillfest')), 'Grillfest',
  'any member renames a list');
select is((select name from public.rename_list((select id from fest), 'Grillfest')), 'Grillfest',
  'renaming to the same name answers the list');
select throws_ok($$ select public.rename_list(gen_random_uuid(), 'X') $$, 'P0002', 'list_not_found',
  'renaming an unknown list');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.rename_list((select id from fest), 'X') $$, '42501', 'not_a_member',
  'renaming another household''s list is refused');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.create_list((select id from ha), 'Baumarkt', 'f0000000-0000-4000-8000-000000000002');
select public.move_list('f0000000-0000-4000-8000-000000000002', 0);
select is(pg_temp.lists_in((select id from ha)), 'Baumarkt:0, Einkaufsliste:1, Grillfest:2',
  'move_list puts a list first and numbers the others');
select public.move_list('f0000000-0000-4000-8000-000000000002', 99);
select is(pg_temp.lists_in((select id from ha)), 'Einkaufsliste:0, Grillfest:1, Baumarkt:2',
  'past the end is last');
select public.move_list('f0000000-0000-4000-8000-000000000002', 1);
select public.move_list('f0000000-0000-4000-8000-000000000002', 1);
select is(pg_temp.lists_in((select id from ha)), 'Einkaufsliste:0, Baumarkt:1, Grillfest:2',
  'into the middle, the same twice');
select throws_ok($$ select public.move_list('f0000000-0000-4000-8000-000000000002', null) $$,
  '22023', 'invalid_position', 'a position is required');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.move_list('f0000000-0000-4000-8000-000000000002', 0) $$,
  '42501', 'not_a_member', 'moving another household''s list is refused');
select is((select count(*)::int from public.lists where household_id = (select id from ha)), 0,
  'another household''s lists are invisible');

-- Lists are written through the functions only.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ insert into public.lists (household_id, name) values ((select id from ha), 'X') $$,
  '42501', null, 'members cannot insert lists directly');
select throws_ok($$ delete from public.lists where id = (select id from first_a) $$,
  '42501', null, 'nor delete them');
select throws_ok($$ update public.lists set name = 'X' where id = (select id from first_a) $$,
  '42501', null, 'nor update them');

-- Writes without a list land in the first list --------------------------------------------------

-- An old store build: a plain insert and put_item without p_list.
insert into public.items (id, household_id, name) values
  ('10000000-0000-4000-8000-000000000001', (select id from ha), 'Milch');
select is(pg_temp.list_of('10000000-0000-4000-8000-000000000001'), 'Einkaufsliste',
  'an old app''s insert without list_id lands in the first list');
select is((select list_id from public.put_item('10000000-0000-4000-8000-000000000002', (select id from ha), 'Brot')),
  (select id from first_a), 'the old put_item adds to the first list');
select is((select list_id from public.add_item((select id from ha), 'Eier')),
  (select id from first_a), 'so does the old add_item (Siri, Alexa)');
-- The first list is the one at position 0, whatever its age.
select public.move_list('f0000000-0000-4000-8000-000000000002', 0);
select is((select list_id from public.add_item((select id from ha), 'Schrauben')),
  'f0000000-0000-4000-8000-000000000002'::uuid, 'after a move, the list in front is the first');
select is(public.first_list((select id from ha)), 'f0000000-0000-4000-8000-000000000002'::uuid,
  'first_list names it');
select public.move_list('f0000000-0000-4000-8000-000000000002', 1);

-- The new app's put_item and the shared add with a list.
select is((select list_id from public.put_item('10000000-0000-4000-8000-000000000003', (select id from ha),
  (select id from fest), 'Kuchen')), (select id from fest), 'put_item with p_list adds to that list');
select is((select list_id from public.put_item('10000000-0000-4000-8000-000000000004', (select id from ha),
  'f9999999-0000-4000-8000-000000000000', 'Sahne')), (select id from first_a),
  'a list deleted while the add waited offline: the first list');
select is((select list_id from public.put_item('10000000-0000-4000-8000-000000000005', (select id from ha),
  (select id from list_b), 'Senf')), (select id from first_a),
  'another household''s list is no list here: the first list');
select is((select list_id from public.add_list_item((select id from ha), (select id from fest), 'Würstchen')),
  (select id from fest), 'add_list_item adds to the list given');
select is((select list_id from public.add_list_item((select id from ha), null, 'Ketchup')),
  (select id from first_a), 'with a null list to the first');
select throws_ok($$ select public.add_list_item((select id from ha), 'f9999999-0000-4000-8000-000000000000', 'X') $$,
  'P0002', 'list_not_found', 'and refuses a list that is not the household''s');

-- The duplicate rule is per list --------------------------------------------------------------

select is((select list_id from public.put_item('10000000-0000-4000-8000-000000000006', (select id from ha),
  (select id from fest), 'Milch')), (select id from fest), 'Milch may be open on a second list');
select is((select id from public.put_item('10000000-0000-4000-8000-000000000007', (select id from ha),
  (select id from fest), 'milch')), '10000000-0000-4000-8000-000000000006'::uuid,
  'but not twice on one: put_item answers the open one');
select is((select id from public.add_list_item((select id from ha), (select id from fest), 'Milch')),
  '10000000-0000-4000-8000-000000000006'::uuid, 'add_list_item finds it on that list');
select is((select id from public.add_item((select id from ha), 'Milch')),
  '10000000-0000-4000-8000-000000000001'::uuid, 'and the old add_item the first list''s');
select is((select count(*)::int from public.items where household_id = (select id from ha) and normalized_name = 'milch'),
  2, 'two Milch, one per list');
select throws_ok(
  $$ update public.items set list_id = (select id from fest) where id = '10000000-0000-4000-8000-000000000001' $$,
  '23505', 'already_on_list', 'moving an item to a list where it is open is refused');
update public.items set list_id = (select id from fest) where id = '10000000-0000-4000-8000-000000000002';
select is(pg_temp.list_of('10000000-0000-4000-8000-000000000002'), 'Grillfest', 'any other move works');
select throws_ok(
  $$ update public.items set list_id = (select id from list_b)
     where id = '10000000-0000-4000-8000-000000000002' $$,
  '23503', null, 'an item cannot move to another household''s list');
select throws_ok(
  $$ update public.items set name = 'Milch' where id = '10000000-0000-4000-8000-000000000005' $$,
  '23505', 'already_on_list', 'renaming to a name open on the same list is refused');

-- Similar items (job 32b) on the same list only.
insert into public.items (id, household_id, list_id, name) values
  ('10000000-0000-4000-8000-000000000008', (select id from ha), (select id from fest), 'Möhren'),
  ('10000000-0000-4000-8000-000000000009', (select id from ha), (select id from first_a), 'Karotten');
select is_empty($$ select * from public.similar_items('10000000-0000-4000-8000-000000000009') $$,
  'a synonym on another list is not similar');
insert into public.items (id, household_id, list_id, name) values
  ('10000000-0000-4000-8000-00000000000a', (select id from ha), (select id from fest), 'Karotten');
select is((select id from public.similar_items('10000000-0000-4000-8000-00000000000a')),
  '10000000-0000-4000-8000-000000000008'::uuid, 'one on the same list is');

-- History carries the list.
select is((select list_id from public.item_events where item_id = '10000000-0000-4000-8000-000000000003' and action = 'added'),
  (select id from fest), 'item_events record the item''s list');
update public.items set list_id = (select id from first_a) where id = '10000000-0000-4000-8000-000000000003';
select is(
  (select list_id from public.item_events where item_id = '10000000-0000-4000-8000-000000000003' and action = 'edited'),
  (select id from first_a), 'a move to another list is an edit with the new list');

-- Unmerge brings a merged row back; its list deleted meanwhile, onto the first list.
select public.merge_items('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-00000000000a',
  '10000000-0000-4000-8000-000000000008');

-- Deleting lists ------------------------------------------------------------------------------

insert into public.items (id, household_id, list_id, name) values
  ('10000000-0000-4000-8000-00000000000b', (select id from ha), (select id from fest), 'Grillkohle');
select pg_temp.as_postgres();
create temp table events_before as select count(*)::int as n from public.item_events;
grant select on events_before to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select lives_ok($$ select public.delete_list((select id from fest)) $$, 'any member deletes a list');
select is((select count(*)::int from public.items where list_id = (select id from fest)), 0, 'its items go with it');
select is((select count(*)::int from public.items where id = '10000000-0000-4000-8000-000000000001'), 1,
  'other lists keep theirs');
select pg_temp.as_postgres();
select is((select count(*)::int from public.item_events), (select n from events_before),
  'the cascade leaves no deleted event per item');
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select lives_ok($$ select public.delete_list((select id from fest)) $$, 'deleting it again is done already');
select is((select (public.unmerge_items('20000000-0000-4000-8000-000000000001') -> 'merged' ->> 'list_id')::uuid),
  (select id from first_a), 'an unmerged row whose list is gone comes back on the first list');
select public.delete_list('f0000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.delete_list((select id from first_a)) $$, 'P0001', 'last_list',
  'the last list is not deleted');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.delete_list((select id from first_a)) $$, '42501', 'not_a_member',
  'deleting another household''s list is refused');

-- An abuse guard: 50 lists a household.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.create_list((select id from ha), 'Liste ' || n, gen_random_uuid()) from generate_series(2, 50) n;
select throws_ok($$ select public.create_list((select id from ha), 'Eine zu viel', gen_random_uuid()) $$,
  'P0001', 'too_many_lists', 'the 51st list is refused');

select * from finish();
rollback;
