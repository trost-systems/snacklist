-- Job 169b wave 2: the invite loop (docs/households/W2.md). Person invites and group links,
-- counted uses and who joined, roles, removal, the owner handover, and the signed-out preview
-- with its rate limits. Two joins racing for a group link's last use are in
-- supabase/functions/_shared/households_integration_test.ts.
begin;
select plan(138);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated', 'session_id', gen_random_uuid())::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Signed out, from [p_ip] as the API gateway reports it (null: no header at all).
create function pg_temp.anon(p_ip text) returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.headers',
    case when p_ip is null then '' else jsonb_build_object('x-real-ip', p_ip)::text end, true);
end $$;

create function pg_temp.hid(p_name text) returns uuid language sql security definer as $$
  select id from public.households where name = p_name
$$;

create function pg_temp.role_of(p_user uuid, p_household text) returns text
language sql security definer as $$
  select role from public.household_members where user_id = p_user and household_id = pg_temp.hid(p_household)
$$;

create function pg_temp.owners(p_household text) returns bigint language sql security definer as $$
  select count(*) from public.household_members where household_id = pg_temp.hid(p_household) and role = 'owner'
$$;

create function pg_temp.invite(p_by uuid, p_household text, p_kind text) returns public.invites
language plpgsql as $$
begin
  perform pg_temp.login(p_by);
  return public.create_invite(pg_temp.hid(p_household), p_kind);
end $$;

create function pg_temp.join_as(p_user uuid, p_code text) returns text language plpgsql as $$
begin
  perform pg_temp.login(p_user);
  return public.accept_invite(p_code, p_mode => 'add') ->> 'status';
end $$;

-- [p_user] joins [p_household] by a person invite of its owner [p_by], [p_days] ago.
create function pg_temp.member(p_by uuid, p_user uuid, p_household text, p_days int) returns void
language plpgsql as $$
begin
  perform pg_temp.join_as(p_user, (pg_temp.invite(p_by, p_household, 'person')).code);
  perform pg_temp.logout();
  update public.household_members set joined_at = now() - make_interval(days => p_days)
  where user_id = p_user and household_id = pg_temp.hid(p_household);
end $$;

-- [p_times] previews of [p_code], each from its own address 10.0.<p_net>.<n>: how many were not
-- rate_limited.
create function pg_temp.previews_from_many(p_code text, p_net int, p_times int) returns int
language plpgsql as $$
declare
  v_passed int := 0;
begin
  for n in 1 .. p_times loop
    perform pg_temp.anon(format('10.0.%s.%s', p_net, n));
    if public.preview_invite_public(p_code) ->> 'status' <> 'rate_limited' then
      v_passed := v_passed + 1;
    end if;
  end loop;
  return v_passed;
end $$;

grant execute on all functions in schema pg_temp to authenticated, anon;

\set olga '''00000000-0000-0000-0000-000000169f01'''
\set anna '''00000000-0000-0000-0000-000000169f02'''
\set max '''00000000-0000-0000-0000-000000169f03'''
\set mia '''00000000-0000-0000-0000-000000169f04'''
\set udo '''00000000-0000-0000-0000-000000169f05'''
\set ben '''00000000-0000-0000-0000-000000169f06'''
\set j1 '''00000000-0000-0000-0000-000000169f11'''
\set j2 '''00000000-0000-0000-0000-000000169f12'''
\set j3 '''00000000-0000-0000-0000-000000169f13'''

insert into auth.users (id, email, raw_user_meta_data) values
  (:olga, 'olga169@example.com', '{"display_name": "Olga Brandt"}'),
  (:anna, 'anna169@example.com', '{"display_name": "Anna"}'),
  (:max, 'max169@example.com', '{"display_name": "Max"}'),
  (:mia, 'mia169@example.com', '{"display_name": "Mia"}'),
  (:udo, 'udo169@example.com', '{"display_name": "Udo"}'),
  (:ben, 'ben169@example.com', '{"display_name": "Ben"}'),
  (:j1, 'j1169@example.com', '{"display_name": "Jana"}'),
  (:j2, 'j2169@example.com', '{"display_name": "Jonas"}'),
  (:j3, 'j3169@example.com', '{"display_name": "Jule"}');

-- Familie Brandt: Olga owns it; Max joined first, then Anna, then Mia.
select pg_temp.login(:olga);
select public.create_household(
  p_request_id => '00000000-0000-0000-0000-00000169f0e1', p_name => 'Familie Brandt', p_kind => 'family');
select pg_temp.member(:olga, :max, 'Familie Brandt', 9);
select pg_temp.member(:olga, :anna, 'Familie Brandt', 8);
select pg_temp.member(:olga, :mia, 'Familie Brandt', 7);
-- Jana has a household of her own, her default, before she joins the Brandts.
select pg_temp.login(:j1);
select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169f0e2', p_name => 'Bei Jana');
select pg_temp.logout();

-- Person invites and group links -----------------------------------------------------------------

create temp table person as select * from pg_temp.invite(:max, 'Familie Brandt', 'person');
select pg_temp.logout();
grant select on person to authenticated, anon;
select pg_temp.logout();
select results_eq(
  $$ select kind, max_uses, use_count, expires_at > now() + interval '6 days 23 hours',
       expires_at <= now() + interval '7 days' from person $$,
  $$ values ('person', 1, 0, true, true) $$,
  'any member makes a person invite: one use, 7 days'
);
select pg_temp.login(:max);
select throws_ok($$ select public.create_invite(pg_temp.hid('Familie Brandt'), 'group') $$,
  '42501', 'not_admin', 'a member cannot make a group link');
select throws_ok($$ select public.create_invite(pg_temp.hid('Familie Brandt'), 'club') $$,
  '22023', 'invalid_kind', 'an unknown kind is refused');
select throws_ok($$ select public.create_invite(pg_temp.hid('Familie Brandt'), null) $$,
  '22023', 'invalid_kind', 'a null kind is refused');
select pg_temp.login(:udo);
select throws_ok($$ select public.create_invite(pg_temp.hid('Familie Brandt'), 'person') $$,
  '42501', 'not_a_member', 'an outsider makes no person invite');
select throws_ok($$ select public.create_invite(pg_temp.hid('Familie Brandt'), 'group') $$,
  '42501', 'not_a_member', 'nor a group link');

create temp table g1 as select * from pg_temp.invite(:olga, 'Familie Brandt', 'group');
select pg_temp.logout();
grant select on g1 to authenticated, anon;
select pg_temp.logout();
select results_eq(
  $$ select kind, max_uses, use_count, expires_at > now() + interval '29 days 23 hours',
       expires_at <= now() + interval '30 days' from g1 $$,
  $$ values ('group', 50, 0, true, true) $$,
  'the owner makes a group link: 50 uses, 30 days'
);
select is((pg_temp.invite(:olga, 'Familie Brandt', 'group')).id, (select id from g1),
  'a second create answers the open group link (idempotent)');

-- The old app's Einladungen page, verbatim (invite_repository.dart before job 169b): a member
-- would get the group link with a revoke button, so the table shows group links to no one.
create function pg_temp.old_app_invites(p_household uuid) returns setof text language sql as $$
  select code from public.invites
  where household_id = p_household and used_at is null and revoked_at is null and expires_at > now()
  order by created_at desc
$$;
grant execute on function pg_temp.old_app_invites(uuid) to authenticated;
select pg_temp.login(:max);
select is((select count(*)::int from pg_temp.old_app_invites(pg_temp.hid('Familie Brandt')) c
  where c = (select code from g1)), 0, 'old builds don''t list the group link for a member');
select is((select count(*)::int from public.invites where kind = 'group'), 0,
  'no group row reaches a member through the table');
select pg_temp.login(:olga);
select is((select count(*)::int from pg_temp.old_app_invites(pg_temp.hid('Familie Brandt')) c
  where c = (select code from g1)), 0, 'nor for the owner (the new app reads household_invites)');
select is((select count(*)::int from pg_temp.old_app_invites(pg_temp.hid('Familie Brandt')) c
  where c = (select code from person)), 1, 'person invites are still listed');
select is((select count(*)::int from public.household_invites(pg_temp.hid('Familie Brandt')) where kind = 'group'), 1,
  'household_invites shows the owner the group link');

-- Group links are the owner's and admins' (Q-HH3); person invites any member's.
select pg_temp.login(:max);
select throws_ok(format('select public.revoke_invite(%L)', (select id from g1)), '42501', 'not_admin',
  'a member cannot revoke the group link');
select pg_temp.logout();
select is((select revoked_at from public.invites where id = (select id from g1)), null, 'and it stays open');
create temp table spare as select * from pg_temp.invite(:olga, 'Familie Brandt', 'person');
select pg_temp.logout();
grant select on spare to authenticated, anon;
select pg_temp.login(:max);
select lives_ok(format('select public.revoke_invite(%L)', (select id from spare)),
  'a member revokes a person invite of the owner''s');
select pg_temp.logout();
select isnt((select revoked_at from public.invites where id = (select id from spare)), null, 'which is revoked');

select pg_temp.login(:olga);
create temp table old_create as select * from public.create_invite(pg_temp.hid('Familie Brandt'));
grant select on old_create to authenticated, anon;
select results_eq($$ select kind, max_uses, use_count from old_create $$, $$ values ('person', 1, 0) $$,
  'old builds'' create_invite(p_household) still makes a person invite');

-- Roles ------------------------------------------------------------------------------------------

select pg_temp.login(:anna);
select throws_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04', 'admin') $$,
  '42501', 'not_owner', 'only the owner names admins');
select pg_temp.login(:udo);
select throws_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04', 'admin') $$,
  '42501', 'not_member', 'an outsider changes no role');
select pg_temp.login(:olga);
select throws_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04', 'owner') $$,
  '22023', 'invalid_role', 'roles are admin or member');
select throws_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f01', 'member') $$,
  '42501', 'cannot_change_owner', 'the owner''s own role stays');
select throws_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f05', 'admin') $$,
  '42501', 'not_member', 'a non-member cannot be named admin');
select lives_ok($$ select public.set_member_role(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f02', 'admin') $$,
  'the owner names Anna admin');
select is(pg_temp.role_of(:anna, 'Familie Brandt'), 'admin', 'Anna is admin');
select is((select role from public.household_members_of(pg_temp.hid('Familie Brandt'))
  where user_id = '00000000-0000-0000-0000-000000169f02'), 'admin', 'household_members_of shows the role');
select public.set_member_role(pg_temp.hid('Familie Brandt'), :mia, 'admin');
select public.set_member_role(pg_temp.hid('Familie Brandt'), :mia, 'member');
select is(pg_temp.role_of(:mia, 'Familie Brandt'), 'member', 'the owner un-names an admin');

select is((pg_temp.invite(:anna, 'Familie Brandt', 'group')).id, (select id from g1),
  'an admin gets the same open group link');

-- Revoke, expiry, then a new link.
select pg_temp.login(:anna);
select public.revoke_invite((select id from g1));
create temp table g2 as select * from public.create_invite(pg_temp.hid('Familie Brandt'), 'group');
grant select on g2 to authenticated, anon;
select isnt((select code from g2), (select code from g1), 'after a revoke, create makes a new code');
select pg_temp.logout();
select isnt((select revoked_at from public.invites where id = (select id from g1)), null,
  'and the revoked link stays revoked');
update public.invites set expires_at = now() - interval '1 second' where id = (select id from g2);
create temp table g3 as select * from pg_temp.invite(:olga, 'Familie Brandt', 'group');
select pg_temp.logout();
grant select on g3 to authenticated, anon;
select isnt((select id from g3), (select id from g2), 'an expired group link is replaced by a new one');
select is((select count(*)::int from public.invites
  where household_id = pg_temp.hid('Familie Brandt') and kind = 'group' and revoked_at is null
    and expires_at > now() and use_count < max_uses), 1, 'one open group link per household');

-- Joining counts uses ----------------------------------------------------------------------------

select is(pg_temp.join_as(:j1, (select code from g1)), 'invalid_invite', 'a revoked group link joins nobody');
select is(pg_temp.join_as(:j1, (select code from g2)), 'invalid_invite', 'nor an expired one');
select is(pg_temp.join_as(:j1, (select code from g3)), 'joined', 'Jana joins through the group link');
select pg_temp.logout();
select results_eq($$ select use_count, used_at is null, used_by is null from public.invites where id = (select id from g3) $$,
  $$ values (1, true, true) $$, 'the link counts one use and stays open');
select results_eq($$ select household_id, user_id from public.invite_uses where invite_id = (select id from g3) $$,
  $$ values (pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f11'::uuid) $$,
  'the join is a row in invite_uses');
select pg_temp.login(:j1);
select is(jsonb_array_length(public.export_my_data() -> 'invite_uses'), 1,
  'her export lists the invite she joined through');
select pg_temp.logout();
select is(pg_temp.join_as(:j1, (select code from g3)), 'member', 'the same link again: already a member');
select pg_temp.logout();
select is((select use_count from public.invites where id = (select id from g3)), 1, 'and no use is counted');

select pg_temp.login(:max);
select results_eq($$ select user_id, display_name from public.invite_joins((select id from g3)) $$,
  $$ values ('00000000-0000-0000-0000-000000169f11'::uuid, 'Jana') $$,
  'invite_joins lists who joined, for any member');
select pg_temp.login(:udo);
select throws_ok($$ select * from public.invite_joins((select id from g3)) $$, '42501', 'not_member',
  'not for an outsider');
select throws_ok($$ select * from public.invite_joins(gen_random_uuid()) $$, '42501', 'not_member',
  'an unknown invite answers the same');

-- The person invite: one use, then it is used up.
select is(pg_temp.join_as(:ben, (select code from person)), 'joined', 'Ben joins with the person invite');
select pg_temp.logout();
select results_eq(
  $$ select use_count, used_at is not null, used_by from public.invites where id = (select id from person) $$,
  $$ values (1, true, '00000000-0000-0000-0000-000000169f06'::uuid) $$,
  'a person invite is used up at one use (used_at and used_by as before)'
);
select is((select count(*)::int from public.invite_uses where invite_id = (select id from person)), 1,
  'a person invite''s join is in invite_uses too');
select is(pg_temp.join_as(:udo, (select code from person)), 'invalid_invite', 'a used person invite joins nobody');

-- The 50th use fills the link.
select pg_temp.logout();
update public.invites set use_count = 49 where id = (select id from g3);
select is(pg_temp.join_as(:j2, (select code from g3)), 'joined', 'the 50th join works');
select pg_temp.logout();
select results_eq($$ select use_count, used_at is not null from public.invites where id = (select id from g3) $$,
  $$ values (50, true) $$, 'the link is full at 50');
select is(pg_temp.join_as(:j3, (select code from g3)), 'invalid_invite', 'a 51st join is refused');
select pg_temp.logout();
select throws_ok($$ update public.invites set use_count = 51 where id = (select id from g3) $$,
  '23514', null, 'use_count never passes max_uses');

-- household_invites and the old app's select.
select pg_temp.login(:max);
create temp table open_codes as select code, kind from public.household_invites(pg_temp.hid('Familie Brandt'));
select set_eq($$ select code from open_codes $$, $$ select code from old_create union select code from g3 $$,
  'household_invites lists the open ones and the full group link: no revoked, expired or used invite');
select results_eq(
  $$ select use_count, max_uses from public.household_invites(pg_temp.hid('Familie Brandt')) where kind = 'group' $$,
  $$ values (50, 50) $$,
  'the newest group link stays listed when full, for "Der Link ist voll"'
);
select set_eq(
  $$ select * from pg_temp.old_app_invites(pg_temp.hid('Familie Brandt')) $$,
  $$ select code from open_codes where kind = 'person' $$,
  'old builds'' direct select on invites finds the same open person invites'
);
select pg_temp.logout();
update public.invites set created_at = now() - interval '1 hour' where id = (select id from g3);
create temp table g4 as select * from pg_temp.invite(:olga, 'Familie Brandt', 'group');
select pg_temp.logout();
grant select on g4 to authenticated, anon;
select isnt((select id from g4), (select id from g3), 'a full group link is replaced by a new one');
select pg_temp.login(:max);
select results_eq(
  $$ select id from public.household_invites(pg_temp.hid('Familie Brandt')) where kind = 'group' $$,
  $$ select id from g4 $$,
  'then only the new link is listed, not the full one before it'
);
select pg_temp.logout();
select pg_temp.login(:max);
select results_eq(
  $$ select kind, max_uses, use_count, created_by from public.household_invites(pg_temp.hid('Familie Brandt'))
     where id = (select id from g4) $$,
  $$ values ('group', 50, 0, '00000000-0000-0000-0000-000000169f01'::uuid) $$,
  'household_invites answers kind, uses and creator'
);
select pg_temp.login(:udo);
select throws_ok($$ select * from public.household_invites(pg_temp.hid('Familie Brandt')) $$, '42501', 'not_member',
  'household_invites refuses an outsider');

-- Old builds join a group link with the old signatures: counted like any join.
select pg_temp.login(:udo);
select is(public.preview_invite((select code from g4)) ->> 'name', 'Familie Brandt',
  'the old preview_invite still names the household of a group link');
select is(public.accept_invite((select code from g4)) ->> 'status', 'joined', 'the old accept_invite joins by it');
select pg_temp.logout();
select is((select use_count from public.invites where id = (select id from g4)), 1, 'and counts the use');

-- Removal ----------------------------------------------------------------------------------------

select pg_temp.login(:j1);
create temp table jana_token as
  select id from public.create_personal_access_token('Jana Brandt', pg_temp.hid('Familie Brandt'));
grant select on jana_token to authenticated;
select public.set_default_household(pg_temp.hid('Familie Brandt'));

select pg_temp.login(:max);
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04') $$,
  '42501', 'not_admin', 'a member removes nobody');
select pg_temp.login(:udo);
select lives_ok($$ select public.leave_household(pg_temp.hid('Familie Brandt')) $$, 'Udo leaves again');
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04') $$,
  '42501', 'not_member', 'an outsider removes nobody');
select pg_temp.login(:anna);
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f01') $$,
  '42501', 'cannot_remove_owner', 'an admin cannot remove the owner');
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f02') $$,
  '22023', 'cannot_remove_self', 'nobody removes themselves (that is leaving)');
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f05') $$,
  '42501', 'not_member', 'removing a non-member answers not_member');
select pg_temp.login(:olga);
select public.set_member_role(pg_temp.hid('Familie Brandt'), :mia, 'admin');
select pg_temp.login(:anna);
select throws_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04') $$,
  '42501', 'cannot_remove_admin', 'an admin cannot remove another admin');
select lives_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f11') $$,
  'an admin removes a member');
select pg_temp.logout();
select is(pg_temp.role_of(:j1, 'Familie Brandt'), null, 'Jana is out');
select is((select h.name from public.household_members m join public.households h on h.id = m.household_id
  where m.user_id = :j1 and m.is_default), 'Bei Jana', 'her default moved to her other household');
select isnt((select revoked_at from public.personal_access_tokens where id = (select id from jana_token)), null,
  'her key for the household ended');
select is((select count(*)::int from public.invite_uses where user_id = :j1), 0,
  'her join record goes with the membership');
select pg_temp.login(:max);
select is((select count(*)::int from public.invite_joins((select id from g3)) where user_id = :j1), 0,
  'and who-joined lists only current members');

-- A removed member stays out: the links made until the removal no longer let them in.
select pg_temp.logout();
select is((select count(*)::int from public.household_removals
  where household_id = pg_temp.hid('Familie Brandt') and user_id = :j1), 1, 'the removal is recorded');
select pg_temp.login(:j1);
select is(jsonb_array_length(public.export_my_data() -> 'household_removals'), 1, 'and in her export');
select is(pg_temp.join_as(:j1, (select code from g4)), 'invalid_invite',
  'the group link she still holds lets her not back in');
select pg_temp.logout();
update public.household_removals set removed_at = now() - interval '1 minute' where user_id = :j1;
update public.invites set created_at = now() - interval '2 minutes' where id = (select id from g4);
select is(pg_temp.join_as(:j1, (select code from g4)), 'invalid_invite', 'a link made a minute before neither');
select pg_temp.login(:j1);
select is(public.preview_invite((select code from g4)) ->> 'status', 'invalid_invite',
  'the in-app preview says invalid, as for a revoked link');
-- Removing is the owner's and admins' call (Q-HH3): a plain member's newer invite keeps her out too.
select (pg_temp.invite(:max, 'Familie Brandt', 'person')).code as max_code \gset
select is(pg_temp.join_as(:j1, :'max_code'), 'invalid_invite',
  'a plain member''s person invite made after the removal does not let her back');
select pg_temp.login(:j1);
select is(public.accept_invite(:'max_code', false) ->> 'status', 'invalid_invite', 'nor through the old join');
select is(public.preview_invite(:'max_code') ->> 'status', 'invalid_invite',
  'and the in-app preview of it says invalid');
select is(pg_temp.join_as(:j1, (pg_temp.invite(:anna, 'Familie Brandt', 'person')).code), 'joined',
  'an admin''s person invite made after the removal brings her back');
select pg_temp.logout();
select is((select count(*)::int from public.household_removals where user_id = :j1), 0,
  'and ends the removal record');
select pg_temp.login(:j1);
select public.leave_household(pg_temp.hid('Familie Brandt'));
select pg_temp.login(:olga);
select lives_ok($$ select public.remove_member(pg_temp.hid('Familie Brandt'), '00000000-0000-0000-0000-000000169f04') $$,
  'the owner removes an admin');
select pg_temp.logout();
select is(pg_temp.role_of(:mia, 'Familie Brandt'), null, 'Mia is out');
update public.household_removals set removed_at = now() - interval '1 minute' where user_id = :mia;
select is(pg_temp.join_as(:mia, (pg_temp.invite(:olga, 'Familie Brandt', 'person')).code), 'joined',
  'the owner''s invite made after the removal brings her back too');
select pg_temp.logout();
select is((select count(*)::int from public.household_removals where user_id = :mia), 0,
  'and ends her removal record');
select pg_temp.login(:olga);
select public.remove_member(pg_temp.hid('Familie Brandt'), :mia);

-- Ownership passes on ----------------------------------------------------------------------------

-- Verein: Max joined before Anna, Anna is admin: the admin takes over.
select pg_temp.login(:olga);
select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169f0e3', p_name => 'Verein');
select pg_temp.member(:olga, :max, 'Verein', 5);
select pg_temp.member(:olga, :anna, 'Verein', 4);
select pg_temp.login(:olga);
select public.set_member_role(pg_temp.hid('Verein'), :anna, 'admin');
select public.leave_household(pg_temp.hid('Verein'));
select pg_temp.logout();
select is(pg_temp.role_of(:anna, 'Verein'), 'owner', 'the owner leaves: the earliest-joined admin owns it');
select is(pg_temp.owners('Verein'), 1::bigint, 'one owner');

-- WG: no admin: the earliest-joined member.
select pg_temp.login(:olga);
select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169f0e4', p_name => 'WG');
select pg_temp.member(:olga, :mia, 'WG', 5);
select pg_temp.member(:olga, :max, 'WG', 6);
select pg_temp.login(:olga);
select public.leave_household(pg_temp.hid('WG'));
select pg_temp.logout();
select is(pg_temp.role_of(:max, 'WG'), 'owner', 'without an admin the earliest-joined member owns it');
select is(pg_temp.owners('WG'), 1::bigint, 'one owner');

-- Konto: Ben deletes his account; Anna (admin, joined later) takes over before Max.
select pg_temp.login(:ben);
select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169f0e5', p_name => 'Konto');
select pg_temp.member(:ben, :max, 'Konto', 5);
select pg_temp.member(:ben, :anna, 'Konto', 4);
select pg_temp.login(:ben);
select public.set_member_role(pg_temp.hid('Konto'), :anna, 'admin');
select pg_temp.logout();
select is(public.delete_account(:ben), 'kept', 'Ben deletes his account; Konto stays');
select is(pg_temp.role_of(:anna, 'Konto'), 'owner', 'the admin owns it now');
select is(pg_temp.owners('Konto'), 1::bigint, 'one owner');

-- Removal by an admin of a member who owns nothing never hands over: Verein's owner stays.
select pg_temp.login(:anna);
select public.remove_member(pg_temp.hid('Verein'), :max);
select pg_temp.logout();
select is(pg_temp.role_of(:anna, 'Verein'), 'owner', 'a removal leaves the owner in place');

-- The signed-out preview -------------------------------------------------------------------------

insert into public.items (household_id, name, status) values
  (pg_temp.hid('Familie Brandt'), 'Milch', 'active'),
  (pg_temp.hid('Familie Brandt'), 'Brot', 'active'),
  (pg_temp.hid('Familie Brandt'), 'Butter', 'bought');
select pg_temp.login(:olga);
create temp table p_open as select * from public.create_invite(pg_temp.hid('Familie Brandt'), 'person');
grant select on p_open to anon, authenticated;
select pg_temp.logout();
insert into public.households (id, name, created_by, archived_at, archived_by) values
  ('00000000-0000-0000-0000-00000169fa01', 'Archiviert', :olga, now(), :olga);
insert into public.invites (household_id, code, created_by) values
  ('00000000-0000-0000-0000-00000169fa01', 'ARCH2222', :olga);
update public.invites set expires_at = now() - interval '1 second' where id = (select id from old_create);

select pg_temp.anon('203.0.113.7');
create temp table shown as select public.preview_invite_public(lower((select code from p_open))) as doc;
select is((select doc from shown), jsonb_build_object(
  'status', 'ok', 'household', 'Familie Brandt', 'inviter', 'Olga', 'members', 4,
  'open_items', 2, 'premium', false, 'invite_kind', 'person'),
  'a link holder sees household, the inviter''s first name, counts and premium, not the household''s kind (N-151; code in any case)');
select is(public.preview_invite_public((select code from g4)) ->> 'invite_kind', 'group',
  'and whether it is a group link');
select is(public.preview_invite_public('ZZZZ-ZZZZ'), jsonb_build_object(
  'status', 'invalid', 'household', null, 'inviter', null, 'members', null,
  'open_items', null, 'premium', null, 'invite_kind', null),
  'an unknown code: invalid, every other field null');
select is(public.preview_invite_public((select code from g1)) ->> 'status', 'invalid', 'revoked: invalid');
select is(public.preview_invite_public((select code from g2)) ->> 'status', 'invalid', 'expired: invalid');
select is(public.preview_invite_public((select code from person)) ->> 'status', 'invalid',
  'a used person invite: invalid');
select is(public.preview_invite_public('ARCH2222') ->> 'status', 'invalid', 'an archived household: invalid');
select is(public.preview_invite_public((select code from g3)), jsonb_build_object(
  'status', 'full', 'household', null, 'inviter', null, 'members', null,
  'open_items', null, 'premium', null, 'invite_kind', null),
  'a group link at 50: full, nothing else');
select pg_temp.logout();
select is((select preview_count from public.invites where id = (select id from p_open)), 1,
  'an ok preview counts preview_count');
select is((select preview_count from public.invites where id = (select id from g3)), 0,
  'a full one does not');

insert into public.entitlements (household_id, kind, source, premium_source)
values (pg_temp.hid('Familie Brandt'), 'premium', 'promotional', 'promotional');
select pg_temp.anon('203.0.113.8');
select is(public.preview_invite_public((select code from p_open)) ->> 'premium', 'true',
  'premium shows when the household has it');
select pg_temp.logout();
update public.profiles set display_name = '' where id = :olga;
select pg_temp.anon('203.0.113.8');
select is(public.preview_invite_public((select code from p_open)) -> 'inviter', 'null'::jsonb,
  'no inviter when the creator has no name');
select pg_temp.logout();
update public.profiles set display_name = 'olga169' where id = :olga;
select pg_temp.anon('203.0.113.8');
select is(public.preview_invite_public((select code from p_open)) -> 'inviter', 'null'::jsonb,
  'nor when the name is still the email''s local part');
select pg_temp.anon(null);
select is(public.preview_invite_public((select code from p_open)) ->> 'status', 'ok',
  'a call without the address header still answers');

-- Rate limits: 30 opens per client and hour, 60 per code.
select pg_temp.anon('198.51.100.1');
select is((select count(*)::int from generate_series(1, 30)
  where public.preview_invite_public('QQQQ' || 'QQQQ') ->> 'status' = 'invalid'), 30,
  'a client gets 30 answers an hour');
select is(public.preview_invite_public((select code from p_open)) ->> 'status', 'rate_limited',
  'the 31st is rate_limited, even for a good code');
select pg_temp.anon('198.51.100.2');
select is(public.preview_invite_public((select code from p_open)) ->> 'status', 'ok',
  'another client is not affected');
select is(pg_temp.previews_from_many('WWWWWWWW', 1, 60), 60, 'a code gets 60 opens an hour from many clients');
select is(pg_temp.previews_from_many('WWWWWWWW', 2, 1), 0, 'the 61st is rate_limited');
select pg_temp.anon('198.51.100.3');
select is(public.preview_invite_public('VVVVVVVV') ->> 'status', 'invalid', 'another code is not affected');

select pg_temp.logout();
select is((select count(*)::int from public.invite_preview_rate
  where key_hash = encode(extensions.digest(
    (select salt from public.invite_preview_salt) || convert_to('client:198.51.100.1', 'UTF8'), 'sha256'), 'hex')),
  1, 'a client is stored as a salted SHA-256 of its address');
select is((select count(*)::int from public.invite_preview_rate
  where key_hash in (encode(extensions.digest('client:198.51.100.1', 'sha256'), 'hex'),
                     encode(extensions.digest('198.51.100.1', 'sha256'), 'hex'))), 0,
  'never an unsalted hash');
select is((select count(*)::int from public.invite_preview_rate
  where key_hash ~ '198\.51|203\.0' or not key_hash ~ '^[0-9a-f]{64}$'), 0, 'and never the address');
insert into public.invite_preview_rate (key_hash, window_start, hits) values
  (repeat('a', 64), date_trunc('hour', now()) - interval '1 hour', 5),
  (repeat('b', 64), now() - interval '3 hours', 5);
select pg_temp.anon('198.51.100.9');
select public.preview_invite_public('VVVVVVVV');
select pg_temp.logout();
select is((select count(*)::int from public.invite_preview_rate where window_start < date_trunc('hour', now())), 0,
  'rows of past hours are deleted');

-- Grants -----------------------------------------------------------------------------------------

select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute')),
  array['preview_invite_public'],
  'signed out, only preview_invite_public can be called'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname in ('my_role_in', 'hand_over_ownership', 'invite_preview_hit', 'claim_invite', 'check_invite')),
  null, 'the helpers are not callable by clients'
);
select pg_temp.anon('198.51.100.10');
select throws_ok($$ select * from public.invite_uses $$, '42501', null, 'anon reads no invite_uses');
select throws_ok($$ select * from public.invite_preview_rate $$, '42501', null, 'nor the preview counters');
select throws_ok($$ select * from public.invite_preview_salt $$, '42501', null, 'nor the salt');
select throws_ok($$ select public.remove_member(gen_random_uuid(), gen_random_uuid()) $$, '42501', null,
  'anon calls no remove_member');
select throws_ok($$ select * from public.household_invites(gen_random_uuid()) $$, '42501', null,
  'nor household_invites');
select pg_temp.login(:olga);
select throws_ok($$ select * from public.invite_preview_salt $$, '42501', null, 'a member reads no salt');
select throws_ok($$ select * from public.invite_preview_rate $$, '42501', null, 'nor the counters');
select throws_ok(
  $$ insert into public.invite_uses (invite_id, household_id, user_id)
     select id, household_id, '00000000-0000-0000-0000-000000169f01' from p_open $$,
  '42501', null, 'invite_uses are written by joins only'
);
select results_eq(
  $$ select count(*)::int, count(m.user_id)::int from public.invite_uses u
     left join public.household_members m on (m.household_id, m.user_id) = (u.household_id, u.user_id)
     where u.household_id = pg_temp.hid('Familie Brandt') $$,
  $$ values (3, 3) $$,
  'members read their household''s invite_uses, all of current members (leavers'' rows went)');

-- A removal record lasts 30 days: every invite made up to the removal has expired by then.
select pg_temp.logout();
insert into public.household_removals (household_id, user_id, removed_at) values
  (pg_temp.hid('Familie Brandt'), :udo, now() - interval '31 days'),
  (pg_temp.hid('Familie Brandt'), :j1, now() - interval '29 days');
select public.purge_household_removals();
select is(
  array(select user_id from public.household_removals
    where household_id = pg_temp.hid('Familie Brandt') order by user_id),
  array[:mia, :j1]::uuid[],
  'the daily purge deletes records older than 30 days and keeps younger ones');
select is((select schedule || ' ' || command from cron.job where jobname = 'purge-household-removals'),
  '47 3 * * * select public.purge_household_removals()', 'and runs every night');
delete from public.household_removals where user_id = :j1;

-- Removal records go with the account and with the household.
select pg_temp.logout();
select is((select count(*)::int from public.household_removals where user_id in (:mia, :max)), 2,
  'Mia (Brandt) and Max (Verein) have removal records');
select is(public.delete_account(:mia), 'kept', 'Mia deletes her account');
select is((select count(*)::int from public.household_removals where user_id = :mia), 0, 'her record went with it');
delete from public.households where id = pg_temp.hid('Verein');
select is((select count(*)::int from public.household_removals where user_id = :max), 0,
  'Max''s went with the household');
select pg_temp.login(:olga);
select results_eq(
  $$ select e ->> 'kind', (e ->> 'max_uses')::int, (e ->> 'use_count')::int
     from jsonb_array_elements(public.export_my_data() -> 'invites_created') e
     where e ->> 'code' = (select code from g3) $$,
  $$ values ('group', 50, 50) $$,
  'the export lists an invite''s kind and uses'
);

select * from finish();
rollback;
