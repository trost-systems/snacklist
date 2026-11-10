-- Legal review N-114: my_household_removals tells the caller about their own removals that still
-- refuse old invites, and nothing else: not another user's, not a household they left, not one
-- older than 30 days.
begin;
select plan(8);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

grant execute on all functions in schema pg_temp to authenticated, anon;

\set ola '''00000000-0000-0000-0000-000000178c01'''
\set ben '''00000000-0000-0000-0000-000000178c02'''
\set kim '''00000000-0000-0000-0000-000000178c03'''

insert into auth.users (id, email) values
  (:ola, 'ola178@example.com'), (:ben, 'ben178@example.com'), (:kim, 'kim178@example.com');

-- Ola owns "Verein" and "Alt"; Ben is in both, Kim in "Verein" and "Kim".
insert into public.households (id, name, created_by) values
  ('00000000-0000-0000-0000-000000178d01', 'Verein', :ola),
  ('00000000-0000-0000-0000-000000178d02', 'Alt', :ola),
  ('00000000-0000-0000-0000-000000178d03', 'Kim', :kim);
insert into public.household_members (household_id, user_id, role) values
  ('00000000-0000-0000-0000-000000178d01', :ola, 'owner'),
  ('00000000-0000-0000-0000-000000178d01', :ben, 'member'),
  ('00000000-0000-0000-0000-000000178d01', :kim, 'member'),
  ('00000000-0000-0000-0000-000000178d02', :ola, 'owner'),
  ('00000000-0000-0000-0000-000000178d02', :ben, 'member'),
  ('00000000-0000-0000-0000-000000178d03', :kim, 'owner');

-- Ola removes Ben from "Verein"; Kim leaves it herself.
select pg_temp.login(:ola);
select public.remove_member('00000000-0000-0000-0000-000000178d01', :ben);
select pg_temp.login(:kim);
select public.leave_household('00000000-0000-0000-0000-000000178d01');

-- Ben's removal from "Alt" happened 31 days ago and the nightly purge has not run yet.
select pg_temp.logout();
delete from public.household_members
where household_id = '00000000-0000-0000-0000-000000178d02' and user_id = :ben;
insert into public.household_removals (household_id, user_id, removed_at)
values ('00000000-0000-0000-0000-000000178d02', :ben, now() - interval '31 days');

select pg_temp.login(:ben);
select results_eq(
  $$ select household_id, household_name from public.my_household_removals() $$,
  $$ values ('00000000-0000-0000-0000-000000178d01'::uuid, 'Verein'::text) $$,
  'Ben sees his removal from Verein with its name, not the one older than 30 days');
select is((select removed_at from public.my_household_removals()), now(),
  'with the time of the removal (this transaction''s), which keys the notice on his devices');

select pg_temp.login(:kim);
select is_empty($$ select * from public.my_household_removals() $$,
  'Kim, who left Verein herself, has no removal');

select pg_temp.login(:ola);
select is_empty($$ select * from public.my_household_removals() $$,
  'Ola, who removed Ben, sees nothing of his removal');

select pg_temp.logout();
update public.household_removals set removed_at = now() - interval '30 days' + interval '1 minute'
where household_id = '00000000-0000-0000-0000-000000178d01';
select pg_temp.login(:ben);
select is((select count(*)::int from public.my_household_removals()), 1,
  'a removal still shows a minute before its 30 days are up');

-- A new invite from Ola brings Ben back: the removal is over.
select pg_temp.login(:ola);
create temp table inv as select code from public.create_invite('00000000-0000-0000-0000-000000178d01');
grant select on inv to authenticated;
select pg_temp.login(:ben);
select is(public.accept_invite((select code from inv), p_mode => 'add') ->> 'status', 'joined', 'Ben rejoins by a new invite');
select is_empty($$ select * from public.my_household_removals() $$, 'and his removal is gone');

select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.my_household_removals() $$, '42501', null,
  'anon cannot call my_household_removals');

select * from finish();
rollback;
