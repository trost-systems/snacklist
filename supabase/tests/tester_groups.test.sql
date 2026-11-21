-- Job 337: tester groups (20261121121147_tester_groups.sql). Only the service connection writes
-- them; a signed-in user reads their own, through the table or my_tester_groups.
begin;
select plan(22);

create function pg_temp.login(uid uuid, client text default null) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', uid, 'role', 'authenticated')
      || case when client is null then '{}'::jsonb else jsonb_build_object('client_id', client) end)::text,
    true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000337a1', 'tessa337@fg.test'),
  ('00000000-0000-0000-0000-0000000337b1', 'bruno337@fg.test'),
  ('00000000-0000-0000-0000-0000000337c1', 'carla337@fg.test');

-- The lead's SQL: Tessa in three groups, inserted out of order; Bruno in one; Carla in none.
insert into public.tester_groups (user_id, group_name, added_at) values
  ('00000000-0000-0000-0000-0000000337a1', 'internal', '2026-11-20T10:00:00Z'),
  ('00000000-0000-0000-0000-0000000337a1', 'beta-de', '2026-11-21T08:00:00Z'),
  ('00000000-0000-0000-0000-0000000337a1', 'beta', '2026-11-19T09:00:00Z'),
  ('00000000-0000-0000-0000-0000000337b1', 'internal', '2026-11-20T10:00:00Z');

-- Names flags can match on: lower case, digits, hyphens, 2 to 32 characters --------------------

select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337c1', 'Internal') $$, '23514', null, 'no upper case');
select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337c1', 'a') $$, '23514', null, 'no single character');
select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337c1', repeat('a', 33)) $$, '23514', null,
  'no more than 32 characters');
select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337c1', 'beta_de') $$, '23514', null, 'no underscore');
select lives_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337c1', repeat('a', 32)) $$, '32 characters are fine');
delete from public.tester_groups where user_id = '00000000-0000-0000-0000-0000000337c1';

-- A signed-in user reads only their own groups and writes none ---------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000337a1');
select is((select array_agg(group_name order by group_name collate "C") from public.tester_groups),
  array['beta', 'beta-de', 'internal'], 'Tessa reads her own groups');
select is((select count(*)::int from public.tester_groups
  where user_id = '00000000-0000-0000-0000-0000000337b1'), 0, 'and not Bruno''s');
select is(public.my_tester_groups(), array['beta', 'beta-de', 'internal'],
  'my_tester_groups lists hers in byte order');
select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337a1', 'premium-free') $$, '42501', null,
  'she cannot put herself into a group');
select throws_ok($$ insert into public.tester_groups (user_id, group_name)
  values ('00000000-0000-0000-0000-0000000337b1', 'beta') $$, '42501', null,
  'nor someone else');
select throws_ok($$ update public.tester_groups set group_name = 'beta-en' where group_name = 'beta' $$,
  '42501', null, 'nor rename a group');
select throws_ok($$ delete from public.tester_groups where group_name = 'internal' $$,
  '42501', null, 'nor leave one');
select throws_ok($$ truncate public.tester_groups $$, '42501', null, 'nor empty the table');

-- An app connected over OAuth reads the same harmless list as the app.
select pg_temp.login('00000000-0000-0000-0000-0000000337a1', '00000000-0000-0000-0000-0000000337d1');
select is(public.my_tester_groups(), array['beta', 'beta-de', 'internal'],
  'a connected app reads the same groups');

select pg_temp.login('00000000-0000-0000-0000-0000000337c1');
select is(public.my_tester_groups(), '{}'::text[], 'a user in no group gets an empty list');

set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok($$ select * from public.tester_groups $$, '42501', null, 'signed out, the table is closed');
select throws_ok($$ select public.my_tester_groups() $$, '42501', null, 'and so is my_tester_groups');

-- The export lists them; the account takes them along -----------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000337a1');
select is(public.export_my_data() -> 'tester_groups', jsonb_build_array(
    jsonb_build_object('group_name', 'beta', 'added_at', '2026-11-19T09:00:00+00:00'::timestamptz),
    jsonb_build_object('group_name', 'beta-de', 'added_at', '2026-11-21T08:00:00+00:00'::timestamptz),
    jsonb_build_object('group_name', 'internal', 'added_at', '2026-11-20T10:00:00+00:00'::timestamptz)),
  'the export holds her groups by name');
select pg_temp.login('00000000-0000-0000-0000-0000000337c1');
select is(public.export_my_data() -> 'tester_groups', '[]'::jsonb, 'and an empty list for none');

select pg_temp.as_postgres();
select is(public.delete_account('00000000-0000-0000-0000-0000000337a1'), 'none',
  'Tessa deletes her account');
select is((select count(*)::int from public.tester_groups
  where user_id = '00000000-0000-0000-0000-0000000337a1'), 0, 'and her groups go with it');
select is((select count(*)::int from public.tester_groups
  where user_id = '00000000-0000-0000-0000-0000000337b1'), 1, 'Bruno''s stay');

select * from finish();
rollback;
