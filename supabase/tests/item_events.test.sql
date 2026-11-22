-- Job 12: the item history. The items trigger writes one row per change with the action, the
-- item's name and category at that moment, the actor and the household; clients only read it.
begin;
select plan(13);
-- Job 352 revoked members' read of item_events; this file checks the history the trigger writes
-- as a member reads it under the policy that still guards it.
grant select on public.item_events to authenticated;

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household('Bob');
insert into public.items (household_id, name) select id, 'Brot' from hb;

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Alice');
create temp table drinks as
  select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks';
insert into public.items (household_id, name) select id, 'Milch' from ha;
create temp table milk as select id from public.items where household_id = (select id from ha);
grant select on ha, hb, drinks, milk to authenticated;

update public.items set name = 'Hafermilch' where id = (select id from milk);
update public.items set category_id = (select id from drinks) where id = (select id from milk);
update public.items set status = 'bought' where id = (select id from milk);
update public.items set status = 'active' where id = (select id from milk);
delete from public.items where id = (select id from milk);

select results_eq(
  $$ select action, item_name from public.item_events order by id $$,
  $$ values ('added', 'Milch'), ('edited', 'Hafermilch'), ('edited', 'Hafermilch'),
            ('bought', 'Hafermilch'), ('restored', 'Hafermilch'), ('deleted', 'Hafermilch') $$,
  'each insert, edit, tick, undo and delete writes its action with the name at that moment'
);
select results_eq(
  $$ select action, category_id = (select id from drinks) from public.item_events order by id $$,
  $$ values ('added', false), ('edited', false), ('edited', true),
            ('bought', true), ('restored', true), ('deleted', true) $$,
  'a move records the new category, and later events keep it'
);
select is(
  (select count(distinct item_id)::int from public.item_events), 1,
  'every event points at the one item, even after it is deleted'
);
select is(
  (select item_id from public.item_events limit 1), (select id from milk),
  'the event names the item it describes'
);
select is(
  (select count(*)::int from public.item_events where actor = '00000000-0000-0000-0000-0000000000a1'), 6,
  'the signed-in user is the actor of every event'
);
select is(
  (select count(*)::int from public.item_events where household_id = (select id from ha)), 6,
  'events belong to the item''s household'
);
select is(
  (select count(*)::int from public.item_events where household_id = (select id from hb)), 0,
  'another household''s events are invisible'
);

select throws_ok(
  $$ insert into public.item_events (household_id, item_id, action, item_name)
     select id, gen_random_uuid(), 'added', 'Fake' from ha $$,
  '42501', null, 'a member cannot insert history into their own household'
);
select throws_ok(
  $$ update public.item_events set item_name = 'Fake' $$,
  '42501', null, 'a member cannot rewrite history'
);
select throws_ok(
  $$ delete from public.item_events $$,
  '42501', null, 'a member cannot delete history'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is(
  (select count(*)::int from public.item_events), 1, 'Bob sees only his own household''s event'
);
select is(
  (select action from public.item_events), 'added', 'Bob''s insert was recorded as added'
);

reset role;
set local role anon;
select throws_ok(
  $$ select count(*) from public.item_events $$,
  '42501', null, 'signed-out clients cannot read history'
);

select * from finish();
rollback;
