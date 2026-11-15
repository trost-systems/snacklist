-- Job 253 (migration 20261115130000_checks_before_locks.sql): a call that is refused takes no lock
-- on the rows it was refused for. Olga owns a household, Ada is its admin, Mats a plain member;
-- Sven owns another one. Olga's asks before someone joins by a code: Dora was declined an hour
-- ago, Rita's request is open, Cara is in as many households as one may be, Gina is new.
--
-- A row lock leaves its transaction's id in the row's xmax, also when the call that took it failed
-- and gave it back, so an unchanged xmax says no lock was taken. Every call runs in a
-- subtransaction of its own (throws_ok, lives_ok, pg_temp.answer): a lock the same one took before
-- would leave the xmax as it is. Each section ends with the call that does take the lock, as the
-- proof that the mark would have moved. Calls that would wait for a held row, and the advisory
-- locks a failed call gives back, are in supabase/functions/_shared/key_checks_integration_test.ts
-- and outsiders_integration_test.ts.
begin;
select plan(51);

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

create function pg_temp.household_mark(p_name text default 'Olga 253') returns text
language sql security definer as $$
  select xmax::text from public.households where name = p_name
$$;

create function pg_temp.invite_mark() returns text language sql security definer as $$
  select xmax::text from public.invites where code = 'HMREV253'
$$;

-- What a call answers, or the error it ends with.
create function pg_temp.answer(p_call text) returns text language plpgsql as $$
declare
  v_answer text;
begin
  execute p_call into v_answer;
  return v_answer;
exception when others then
  return sqlerrm;
end $$;

create function pg_temp.item_mark() returns text language sql security definer as $$
  select i.xmax::text from public.items i join public.households h on h.id = i.household_id
  where h.name = 'Olga 253' and i.name = 'Milch'
$$;

create function pg_temp.advisory_locks() returns bigint language sql security definer as $$
  select count(*) from pg_catalog.pg_locks where locktype = 'advisory' and pid = pg_backend_pid()
$$;

\set olga '00000000-0000-0000-0000-000000253a01'
\set ada '00000000-0000-0000-0000-000000253a02'
\set mats '00000000-0000-0000-0000-000000253a03'
\set sven '00000000-0000-0000-0000-000000253b01'
\set dora '00000000-0000-0000-0000-000000253c01'
\set rita '00000000-0000-0000-0000-000000253c02'
\set cara '00000000-0000-0000-0000-000000253c03'
\set gina '00000000-0000-0000-0000-000000253c04'

insert into auth.users (id, email) values
  (:'olga', 'olga253@example.com'),
  (:'ada', 'ada253@example.com'),
  (:'mats', 'mats253@example.com'),
  (:'sven', 'sven253@example.com'),
  (:'dora', 'dora253@example.com'),
  (:'rita', 'rita253@example.com'),
  (:'cara', 'cara253@example.com'),
  (:'gina', 'gina253@example.com');

select pg_temp.login(:'olga');
create temp table home as select id from public.create_household('Olga 253');
select pg_temp.login(:'sven');
create temp table away as select id from public.create_household('Sven 253');
select pg_temp.logout();
create temp table cap as select public.household_cap() as households;
grant select on cap to authenticated;
select pg_temp.login(:'cara');
create temp table full_house as
select (public.create_household(gen_random_uuid(), 'Cara 253 ' || n)).id
from generate_series(1, (select households from cap)) n;
select pg_temp.logout();
grant select on home, away to authenticated;
update public.households set join_approval = true where id = (select id from home);
insert into public.household_members (household_id, user_id, role) values
  ((select id from home), :'ada', 'admin'),
  ((select id from home), :'mats', 'member');
insert into public.invites (household_id, code, created_by, kind, max_uses, expires_at) values
  ((select id from home), 'HMGRP253', :'olga', 'group', 50, now() + interval '30 days'),
  ((select id from home), 'HMREV253', :'olga', 'group', 50, now() + interval '30 days'),
  ((select id from away), 'AWGRP253', :'sven', 'group', 50, now() + interval '30 days');
create temp table to_revoke as select id from public.invites where code = 'HMREV253';
grant select on to_revoke to authenticated;
insert into public.join_requests (household_id, user_id, invite_id, decision, decided_at, decided_by)
select (select id from home), :'dora', i.id, 'declined', now() - interval '1 hour', :'olga'
from public.invites i where i.code = 'HMGRP253';
insert into public.join_requests (household_id, user_id, invite_id)
select (select id from home), :'rita', i.id from public.invites i where i.code = 'HMGRP253';
insert into public.items (household_id, list_id, name)
values ((select id from home), public.first_list((select id from home)), 'Milch');
create temp table milk as select id from public.items where name = 'Milch' and household_id = (select id from home);
grant select on milk to authenticated;
create temp table marks (what text primary key, mark text);
grant all on marks to authenticated;

insert into marks values
  ('household', pg_temp.household_mark()),
  ('away', pg_temp.household_mark('Sven 253')),
  ('invite', pg_temp.invite_mark());

-- Someone outside the household.
select pg_temp.login(:'sven');
select throws_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253a03', 'admin') $$,
  '42501', 'not_member', 'set_member_role refuses someone outside the household');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select throws_ok($$ select public.leave_household((select id from home)) $$,
  '42501', 'not_member', 'leave_household refuses them');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select throws_ok(
  $$ select public.remove_member((select id from home), '00000000-0000-0000-0000-000000253a03') $$,
  '42501', 'not_member', 'remove_member refuses them');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');

-- A plain member and an admin: neither changes roles, the member removes nobody.
select pg_temp.login(:'mats');
select throws_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253a02', 'member') $$,
  '42501', 'not_owner', 'set_member_role refuses a plain member');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select throws_ok(
  $$ select public.remove_member((select id from home), '00000000-0000-0000-0000-000000253a02') $$,
  '42501', 'not_admin', 'remove_member refuses a plain member');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select pg_temp.login(:'ada');
select throws_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253a03', 'admin') $$,
  '42501', 'not_owner', 'set_member_role refuses an admin');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');

-- The owner asks for what cannot happen.
select pg_temp.login(:'olga');
select throws_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253b01', 'admin') $$,
  '42501', 'not_member', 'set_member_role refuses the owner a role for someone who is no member');
select throws_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253a01', 'member') $$,
  '42501', 'cannot_change_owner', 'and another role for the owner');
select throws_ok(
  $$ select public.remove_member((select id from home), '00000000-0000-0000-0000-000000253b01') $$,
  '42501', 'not_member', 'remove_member refuses the owner someone who is no member');
select throws_ok(
  $$ select public.remove_member((select id from home), '00000000-0000-0000-0000-000000253a01') $$,
  '22023', 'cannot_remove_self', 'and themselves');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');

-- A group invite is the admins' to revoke.
select pg_temp.login(:'sven');
select throws_ok($$ select public.revoke_invite((select id from to_revoke)) $$,
  '42501', 'not_a_member', 'revoke_invite refuses someone outside the household');
select is(pg_temp.invite_mark(), (select mark from marks where what = 'invite'),
  'without a lock on the invite''s row');
select pg_temp.login(:'mats');
select throws_ok($$ select public.revoke_invite((select id from to_revoke)) $$,
  '42501', 'not_admin', 'and a plain member, for a group invite');
select is(pg_temp.invite_mark(), (select mark from marks where what = 'invite'),
  'without a lock on the invite''s row');
select pg_temp.login(:'ada');
select lives_ok($$ select public.revoke_invite((select id from to_revoke)) $$, 'an admin revokes it');
select isnt(pg_temp.invite_mark(), (select mark from marks where what = 'invite'),
  'which locks the invite''s row');

-- Joining by a code: whoever is told no, or asks a second time, does not take the household's row.
select pg_temp.login(:'dora');
select is(pg_temp.answer($$ select public.accept_invite('HMGRP253', 'add') ->> 'status' $$),
  'declined_recently', 'a guest who was declined within the day is told so');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select pg_temp.login(:'rita');
select is(pg_temp.answer($$ select public.accept_invite('HMGRP253', 'add') ->> 'status' $$),
  'requested', 'a guest who asks again through the same invite has their request still');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select pg_temp.login(:'cara');
select is(pg_temp.answer($$ select public.accept_invite('HMGRP253', 'add') ->> 'status' $$),
  'too_many_households', 'a guest in as many households as one may be cannot ask');
select is(pg_temp.answer($$ select public.join_household('HMGRP253') $$),
  null, 'the oldest builds'' call answers them nothing');
select is(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'without a lock on the household''s row');
select is(pg_temp.answer($$ select public.accept_invite('AWGRP253', 'add') ->> 'status' $$),
  'too_many_households', 'nor can they add a household that lets everyone in');
select is(pg_temp.household_mark('Sven 253'), (select mark from marks where what = 'away'),
  'without a lock on that household''s row');
select pg_temp.login(:'gina');
select is(pg_temp.answer($$ select public.accept_invite('HMGRP253', 'add') ->> 'status' $$),
  'requested', 'a new guest''s request is taken');
select isnt(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'which locks the household''s row');
select is(pg_temp.answer($$ select public.accept_invite('AWGRP253', 'add') ->> 'status' $$),
  'joined', 'and they join the household that lets everyone in');
select isnt(pg_temp.household_mark('Sven 253'), (select mark from marks where what = 'away'),
  'which locks that household''s row');
-- The cap counts a join that adds a household. One that replaces the default household leaves
-- that one first and has room.
select pg_temp.login(:'cara');
select is(pg_temp.answer($$ select public.accept_invite('AWGRP253', true) ->> 'status' $$),
  'joined', 'at the cap, a guest still joins in place of their default household');

-- The owner's role change takes the household's row for itself, and the mark shows it. It comes
-- last: a transaction that holds a row for itself takes no second lock on it.
update marks set mark = pg_temp.household_mark() where what = 'household';
select pg_temp.login(:'olga');
select lives_ok(
  $$ select public.set_member_role((select id from home), '00000000-0000-0000-0000-000000253a03', 'admin') $$,
  'the owner changes a role');
select isnt(pg_temp.household_mark(), (select mark from marks where what = 'household'),
  'which locks the household''s row');
select is(
  (select role from public.household_members where user_id = '00000000-0000-0000-0000-000000253a03'),
  'admin', 'and changes it');

-- Claims: a member's claim locks the item's row, an outsider's does not.
insert into marks values ('item', pg_temp.item_mark());
select pg_temp.login(:'sven');
select throws_ok($$ select public.claim_item((select id from milk), null) $$,
  '42501', 'not_a_member', 'claim_item refuses someone outside the household');
select is(pg_temp.item_mark(), (select mark from marks where what = 'item'),
  'without a lock on the item''s row');
select throws_ok($$ select public.claim_item(gen_random_uuid(), null) $$,
  'P0002', 'item_not_found', 'and an item that does not exist is still not found');
select pg_temp.login(:'mats');
select lives_ok($$ select public.claim_item((select id from milk), null) $$, 'a member claims it');
select isnt(pg_temp.item_mark(), (select mark from marks where what = 'item'),
  'which locks the item''s row');

-- The lock that puts a household's adds in a row is for its members only. Sven's household has
-- had no add yet, so this transaction does not hold its lock.
insert into marks values ('advisory', pg_temp.advisory_locks()::text);
select pg_temp.login(:'olga');
select lives_ok($$ select public.lock_household_items((select id from away)) $$,
  'lock_household_items answers someone outside the household');
select is(pg_temp.advisory_locks()::text, (select mark from marks where what = 'advisory'),
  'without taking the household''s lock');
select pg_temp.login(:'sven');
select lives_ok($$ select public.lock_household_items((select id from away)) $$,
  'a member takes it');
select is(pg_temp.advisory_locks(), (select mark::bigint + 1 from marks where what = 'advisory'),
  'and holds it');
-- The server's own writes (triggers of functions that run as their owner) take it for any household.
select pg_temp.logout();
select lives_ok($$ select public.lock_household_items(gen_random_uuid()) $$,
  'lock_household_items answers the server''s roles');
select is(pg_temp.advisory_locks(), (select mark::bigint + 2 from marks where what = 'advisory'),
  'with the lock');

select * from finish();
rollback;
