-- Job 168b: a member sets their household's kind; only the known kinds, only their own household.
begin;
select plan(6);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000168a1', 'kind-a@example.com'),
  ('00000000-0000-0000-0000-0000000168b1', 'kind-b@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000168a1');
select public.create_household('A', false, '{}');
select pg_temp.login('00000000-0000-0000-0000-0000000168b1');
select public.create_household('B', false, '{}');

select pg_temp.login('00000000-0000-0000-0000-0000000168a1');
select is(
  (select kind from public.households where name = 'A'), null,
  'a new household has no kind'
);
update public.households set kind = 'club' where name = 'A';
select is(
  (select kind from public.households where name = 'A'), 'club',
  'a member sets the kind'
);
select throws_ok(
  $$ update public.households set kind = 'pets' where name = 'A' $$,
  '23514', null,
  'an unknown kind is refused'
);
update public.households set kind = 'family'
  where id = (select household_id from public.household_members where user_id = '00000000-0000-0000-0000-0000000168b1');
select is(
  (select count(*)::int from public.households where kind = 'family'), 0,
  'another household''s kind stays (no row visible)'
);
reset role;
select is(
  (select kind from public.households where name = 'B'), null,
  'household B is unchanged'
);
select ok(
  exists(select from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'invites'),
  'invites are published to realtime'
);

select * from finish();
rollback;
