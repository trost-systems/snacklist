-- Job 324 (AM2): put_item with p_separate adds the typed item next to the same open item; without
-- it the add still answers with the open item (job 64b); the setting does not outlive the call.
begin;
select plan(9);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'peter@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Trost');
grant select on ha to authenticated;

select ok((select id = '32400000-0000-4000-8000-000000000001' from public.put_item(
  '32400000-0000-4000-8000-000000000001', (select id from ha), 'Nudeln', '500 g'
)), 'the first Nudeln lands');

select is((select id from public.put_item(
  '32400000-0000-4000-8000-000000000002', (select id from ha), 'Nudeln'
)), '32400000-0000-4000-8000-000000000001'::uuid, 'without p_separate the add is the open Nudeln');

select is((select id from public.put_item(
  '32400000-0000-4000-8000-000000000003', (select id from ha), 'Nudeln', '2', p_separate => true
)), '32400000-0000-4000-8000-000000000003'::uuid, 'with p_separate it answers with its own row');
select is(
  (select count(*)::int from public.items
    where household_id = (select id from ha) and normalized_name = 'nudeln' and status = 'active'),
  2, 'two open Nudeln'
);
select is((select id from public.put_item(
  '32400000-0000-4000-8000-000000000003', (select id from ha), 'Nudeln', '2', p_separate => true
)), '32400000-0000-4000-8000-000000000003'::uuid, 'a retry answers with the same row');

select is(current_setting('family_groceries.separate', true), '', 'the setting is cleared after the call');
select ok((select id <> '32400000-0000-4000-8000-000000000004' from public.put_item(
  '32400000-0000-4000-8000-000000000004', (select id from ha), 'Nudeln'
)), 'a later add in the same transaction is skipped again');
select is((select count(*)::int from public.add_item((select id from ha), 'Nudeln')), 1,
  'add_item still answers with one open row');
select is(
  (select count(*)::int from public.items
    where household_id = (select id from ha) and normalized_name = 'nudeln' and status = 'active'),
  2, 'still two open Nudeln'
);

select * from finish();
rollback;
