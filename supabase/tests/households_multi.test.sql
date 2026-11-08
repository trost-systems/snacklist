-- Job 169b wave 1: several households per user (docs/households/W1.md). One membership is the
-- default: old store builds see only it, Siri follows it, and every exit hands it on. Old
-- signatures act on the default only; the new ones add and leave single households. The
-- concurrent cases (two sessions) are in supabase/functions/_shared/households_integration_test.ts.
begin;
select plan(88);

create function pg_temp.login(uid uuid, claims jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', uid, 'role', 'authenticated') || claims)::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- The user's memberships as the database has them: household name and whether it is the default.
create function pg_temp.memberships(p_user uuid) returns table (name text, is_default boolean)
language sql security definer as $$
  select h.name, m.is_default from public.household_members m
  join public.households h on h.id = m.household_id
  where m.user_id = p_user order by m.joined_at, h.name
$$;

create function pg_temp.default_of(p_user uuid) returns text language sql security definer as $$
  select h.name from public.household_members m join public.households h on h.id = m.household_id
  where m.user_id = p_user and m.is_default
$$;

create function pg_temp.hid(p_name text) returns uuid language sql security definer as $$
  select id from public.households where name = p_name
$$;

-- An invite to [p_household], made by its member [p_by].
create function pg_temp.invite(p_by uuid, p_household text) returns text language plpgsql as $$
declare
  v_code text;
begin
  perform pg_temp.login(p_by);
  select code into v_code from public.create_invite(pg_temp.hid(p_household));
  return v_code;
end $$;

-- Membership times one day apart, in the order given, so "the oldest remaining" is defined.
create function pg_temp.age(p_user uuid, variadic p_households text[]) returns void
language plpgsql security definer as $$
begin
  for i in 1 .. array_length(p_households, 1) loop
    update public.household_members set joined_at = now() - make_interval(days => 10 - i)
    where user_id = p_user and household_id = pg_temp.hid(p_households[i]);
  end loop;
end $$;

-- [p_user] joins with [p_code] in mode add (the code is made before the login switches users).
create function pg_temp.join_as(p_user uuid, p_code text) returns text language plpgsql as $$
begin
  perform pg_temp.login(p_user);
  return public.accept_invite(p_code, p_mode => 'add') ->> 'status';
end $$;

grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000169a1', 'peter169@example.com'),
  ('00000000-0000-0000-0000-0000000169b1', 'lea169@example.com'),
  ('00000000-0000-0000-0000-0000000169c1', 'carl169@example.com');
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000169a5a1', '00000000-0000-0000-0000-0000000169a1');

-- Peter: Zuhause (old create, his first: the default), then Sommerfest with a request id.
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select lives_ok($$ select public.create_household('Zuhause') $$, 'the old create makes a first household');
select throws_ok($$ select public.create_household('Zweiter') $$, 'P0001', 'already_in_household',
  'the old create (no request id) still answers already_in_household to a member');
create temp table req as select public.create_household(
  p_request_id => '00000000-0000-0000-0000-00000169e001', p_name => 'Sommerfest', p_kind => 'club') as h;
grant select on req to authenticated;
select is((select (h).name from req), 'Sommerfest', 'with a request id a member creates another household');
select is(
  (select (public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e001', p_name => 'Doppelt')).id),
  (select (h).id from req), 'the same request id returns the same household'
);
select is((select (h).kind from req), 'club', 'the kind is stored');
select throws_ok(
  $$ select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e002', p_kind => 'verein') $$,
  '23514', null, 'an unknown kind is refused');

-- Lea: Lea's household; Peter joins it with mode add.
select pg_temp.login('00000000-0000-0000-0000-0000000169b1');
select lives_ok($$ select public.create_household('Bei Lea') $$, 'Lea creates her household');
create temp table code_lea as select pg_temp.invite('00000000-0000-0000-0000-0000000169b1', 'Bei Lea') as code;
grant select on code_lea to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(
  public.accept_invite((select code from code_lea), p_mode => 'add'),
  jsonb_build_object('status', 'joined', 'household_id', pg_temp.hid('Bei Lea')),
  'accept_invite mode add joins'
);
select pg_temp.logout();
select pg_temp.age('00000000-0000-0000-0000-0000000169a1', 'Zuhause', 'Sommerfest', 'Bei Lea');
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Zuhause', true), ('Sommerfest', false), ('Bei Lea', false) $$,
  'mode add left the default alone: three memberships, the first is the default'
);
select throws_ok(
  $$ update public.household_members set is_default = true
     where user_id = '00000000-0000-0000-0000-0000000169a1' and household_id = pg_temp.hid('Sommerfest') $$,
  '23505', null, 'one default per user (partial unique index)'
);
select lives_ok(
  $$ update public.household_members set role = 'admin'
     where user_id = '00000000-0000-0000-0000-0000000169a1' and household_id = pg_temp.hid('Bei Lea') $$,
  'role admin is allowed'
);
update public.household_members set role = 'member'
where user_id = '00000000-0000-0000-0000-0000000169a1' and household_id = pg_temp.hid('Bei Lea');
select throws_ok(
  $$ update public.household_members set role = 'boss' where user_id = '00000000-0000-0000-0000-0000000169a1' $$,
  '23514', null, 'roles are owner, admin or member'
);

-- What old store builds and the new app see.
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select results_eq(
  $$ select h.name from public.household_members m join public.households h on h.id = m.household_id
     where m.user_id = '00000000-0000-0000-0000-0000000169a1' $$,
  $$ values ('Zuhause') $$,
  'the old app''s own-membership query returns exactly one row, the default'
);
select is(
  (select count(*)::int from public.household_members where household_id = pg_temp.hid('Bei Lea')), 1,
  'a plain select of a non-default household hides the user''s own row (Lea''s stays)'
);
select results_eq(
  $$ select name, kind, role, is_default, member_count, open_count, premium from public.my_households() $$,
  $$ values ('Zuhause', null::text, 'owner', true, 1, 0, false),
            ('Sommerfest', 'club', 'owner', false, 1, 0, false),
            ('Bei Lea', null, 'member', false, 2, 0, false) $$,
  'my_households lists every membership in joining order'
);
insert into public.items (household_id, name) values (pg_temp.hid('Bei Lea'), 'Milch');
select is(
  (select open_count from public.my_households() where name = 'Bei Lea'), 1,
  'open_count counts the unchecked items'
);
select results_eq(
  $$ select user_id, role from public.household_members_of(pg_temp.hid('Bei Lea')) $$,
  $$ values ('00000000-0000-0000-0000-0000000169a1'::uuid, 'member'),
            ('00000000-0000-0000-0000-0000000169b1'::uuid, 'owner') $$,
  'household_members_of lists every member, the caller''s non-default row included'
);
select is(
  (select display_name from public.household_members_of(pg_temp.hid('Bei Lea'))
   where user_id = '00000000-0000-0000-0000-0000000169b1'), 'lea169',
  'household_members_of carries display names'
);
select pg_temp.login('00000000-0000-0000-0000-0000000169c1');
select throws_ok($$ select * from public.household_members_of(pg_temp.hid('Bei Lea')) $$,
  '42501', 'not_member', 'household_members_of refuses a non-member');
select is((select count(*)::int from public.my_households()), 0, 'no memberships: my_households is empty');
select pg_temp.login('00000000-0000-0000-0000-0000000169b1');
select results_eq(
  $$ select user_id from public.household_members where household_id = pg_temp.hid('Bei Lea') order by joined_at $$,
  $$ values ('00000000-0000-0000-0000-0000000169a1'::uuid), ('00000000-0000-0000-0000-0000000169b1'::uuid) $$,
  'other members still see Peter''s non-default row'
);

-- set_default_household
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select lives_ok($$ select public.set_default_household(pg_temp.hid('Bei Lea')) $$, 'set_default_household');
select is(pg_temp.default_of('00000000-0000-0000-0000-0000000169a1'), 'Bei Lea', 'the default moved');
select is(
  (select count(*)::int from public.my_households() where is_default), 1, 'still exactly one default'
);
select pg_temp.login('00000000-0000-0000-0000-0000000169c1');
select throws_ok($$ select public.set_default_household(pg_temp.hid('Bei Lea')) $$, '42501', 'not_member',
  'set_default_household refuses a non-member');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.set_default_household(pg_temp.hid('Zuhause'));

-- Single-row readers: given household, else the default.
select is(public.leaves_unlocked(), false, 'leaves_unlocked() answers with several memberships');
select pg_temp.logout();
insert into public.entitlements (household_id, kind, source, premium_source)
values (pg_temp.hid('Sommerfest'), 'premium', 'promotional', 'promotional');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(public.leaves_unlocked(pg_temp.hid('Sommerfest')), true,
  'leaves_unlocked(household): the only member of an unlocked household');
select is(public.leaves_unlocked(null), false, 'leaves_unlocked(null) judges the default (Zuhause)');
select is(public.leaves_unlocked(), false, 'leaves_unlocked() judges the default');
select is((select premium from public.my_households() where name = 'Sommerfest'), true,
  'my_households shows premium per household');
select lives_ok($$ select public.my_yearly_plan(), public.my_yearly_plan(pg_temp.hid('Sommerfest')) $$,
  'my_yearly_plan answers with several memberships');

create function pg_temp.feedback(p_message text, p_household uuid) returns void language sql as $$
  insert into public.feedback (id, user_id, household_id, message, category, app_version, build, platform,
    os_version, locale, screen)
  values (gen_random_uuid(), '00000000-0000-0000-0000-0000000169a1', p_household, p_message, 'idea', '0.1.0', '1',
    'web', 'Chrome on macOS', 'de', 'list')
$$;
grant execute on function pg_temp.feedback(text, uuid) to authenticated;
select pg_temp.feedback('Schön', pg_temp.hid('Sommerfest'));
select pg_temp.feedback('Ohne', null);
select pg_temp.feedback('Fremd', '00000000-0000-0000-0000-00000169ffff');
select pg_temp.logout();
select results_eq(
  $$ select message, household_id from public.feedback
     where user_id = '00000000-0000-0000-0000-0000000169a1' order by message $$,
  $$ values ('Fremd', pg_temp.hid('Zuhause')), ('Ohne', pg_temp.hid('Zuhause')),
            ('Schön', pg_temp.hid('Sommerfest')) $$,
  'feedback keeps a household the sender is in, else files under the default'
);

select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
create temp table export as select public.export_my_data() as doc;
grant select on export to authenticated;
select is((select doc -> 'household' ->> 'name' from export), 'Zuhause', 'the export''s household is the default');
select results_eq(
  $$ select e ->> 'name', (e ->> 'is_default')::boolean from export, jsonb_array_elements(doc -> 'households') e $$,
  $$ values ('Zuhause', true), ('Sommerfest', false), ('Bei Lea', false) $$,
  'the export lists every household'
);

-- preview_invite judges the old join screen's warning against the default.
create temp table code_carl as select null::text as code;
grant all on code_carl to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000169c1');
select lives_ok($$ select public.create_household('Carl') $$, 'Carl creates his household');
update code_carl set code = pg_temp.invite('00000000-0000-0000-0000-0000000169c1', 'Carl');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is((public.preview_invite((select code from code_carl)) ->> 'leaves_unlocked')::boolean, false,
  'preview_invite: leaving the default (Zuhause, no premium) loses no unlock');
select public.set_default_household(pg_temp.hid('Sommerfest'));
select is((public.preview_invite((select code from code_carl)) ->> 'leaves_unlocked')::boolean, true,
  'preview_invite: leaving the default (Sommerfest, unlocked) would');
select public.set_default_household(pg_temp.hid('Zuhause'));
select is(public.preview_invite((select code from code_lea)) ->> 'status', 'member',
  'preview_invite of a non-default household the user is in: member');

-- Old accept_invite: moves out of the default only, the joined household becomes the default.
select is(public.accept_invite((select code from code_lea)) ->> 'status', 'member',
  'the old accept_invite answers member for a non-default household the user is already in');
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Zuhause', true), ('Sommerfest', false), ('Bei Lea', false) $$,
  'and changes nothing'
);
-- Lea joins Zuhause first, so Peter's leave of his default keeps it.
select is(
  pg_temp.join_as('00000000-0000-0000-0000-0000000169b1', pg_temp.invite('00000000-0000-0000-0000-0000000169a1', 'Zuhause')),
  'joined', 'Lea joins Zuhause with mode add'
);
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(
  public.accept_invite((select code from code_carl), false) - 'household_id',
  jsonb_build_object('status', 'joined', 'previous', 'left'),
  'the old accept_invite leaves the default (Zuhause, kept by Lea)'
);
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Sommerfest', false), ('Bei Lea', false), ('Carl', true) $$,
  'the other memberships stay; the joined household is the default'
);
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select results_eq(
  $$ select h.name from public.household_members m join public.households h on h.id = m.household_id
     where m.user_id = '00000000-0000-0000-0000-0000000169a1' $$,
  $$ values ('Carl') $$,
  'an old app now shows the household it joined'
);
select throws_ok($$ select public.accept_invite('ABCDEFGH', p_mode => 'move') $$, '22023', 'invalid_mode',
  'accept_invite knows mode add only');

-- Default promotion on every exit.
select pg_temp.logout();
select pg_temp.age('00000000-0000-0000-0000-0000000169a1', 'Sommerfest', 'Bei Lea', 'Carl');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(
  public.leave_household(pg_temp.hid('Carl')),
  jsonb_build_object('status', 'left', 'deleted', false, 'archived', false),
  'leave_household leaves one household (Carl keeps it)'
);
select is(pg_temp.default_of('00000000-0000-0000-0000-0000000169a1'), 'Sommerfest',
  'after leaving the default, the oldest remaining membership is the default');
select throws_ok($$ select public.leave_household(pg_temp.hid('Carl')) $$, '42501', 'not_member',
  'leave_household refuses a household the user is not in');

-- A removal (W2 gives it an RPC; the row going is what counts here).
select pg_temp.logout();
delete from public.household_members
where user_id = '00000000-0000-0000-0000-0000000169a1' and household_id = pg_temp.hid('Sommerfest');
select is(pg_temp.default_of('00000000-0000-0000-0000-0000000169a1'), 'Bei Lea',
  'after a removal of the default, the next membership is the default');

-- A deleted household (cascade).
insert into public.households (name, created_by) values ('Eltern', '00000000-0000-0000-0000-0000000169c1');
insert into public.household_members (household_id, user_id) values
  (pg_temp.hid('Eltern'), '00000000-0000-0000-0000-0000000169a1');
select is(
  (select is_default from public.household_members
   where user_id = '00000000-0000-0000-0000-0000000169a1' and household_id = pg_temp.hid('Eltern')),
  false, 'a further membership is not the default'
);
delete from public.households where id = pg_temp.hid('Bei Lea');
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Eltern', true) $$,
  'after the default household is deleted, the remaining membership is the default'
);
select is(pg_temp.default_of('00000000-0000-0000-0000-0000000169b1'), 'Zuhause',
  'Lea lost her default with it (Bei Lea): Zuhause is hers now');

-- The last leave: no default, no error.
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(
  public.leave_household(pg_temp.hid('Eltern')),
  jsonb_build_object('status', 'left', 'deleted', true, 'archived', false),
  'the last member''s leave deletes the household'
);
select is((select count(*)::int from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1')), 0,
  'after the last leave: no membership and no error');
select is(public.leave_current_household(false), 'none', 'the old leave without a membership: none');

-- Old leave_current_household: only the default membership.
select lives_ok($$ select public.create_household('Erste') $$, 'a first household again');
select lives_ok(
  $$ select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e003', p_name => 'Zweite') $$,
  'and a second');
select pg_temp.logout();
select pg_temp.age('00000000-0000-0000-0000-0000000169a1', 'Erste', 'Zweite');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(public.leave_current_household(false), 'deleted', 'the old leave(p_archive) leaves the default');
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Zweite', true) $$,
  'and only it: the other membership stays and is the default'
);
select lives_ok(
  $$ select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e004', p_name => 'Dritte') $$,
  'another household');
select lives_ok($$ select public.leave_current_household() $$, 'the old void leave');
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Dritte', true) $$,
  'the old void leave also leaves the default only'
);

-- unarchive_household: the old signature leaves the default only, mode add leaves nothing.
select pg_temp.logout();
insert into public.households (name, created_by, archived_at, archived_by) values
  ('Archiv A', '00000000-0000-0000-0000-0000000169a1', now(), '00000000-0000-0000-0000-0000000169a1'),
  ('Archiv B', '00000000-0000-0000-0000-0000000169a1', now(), '00000000-0000-0000-0000-0000000169a1');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select lives_ok(
  $$ select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e005', p_name => 'Vierte') $$,
  'a second membership next to Dritte');
select pg_temp.logout();
select pg_temp.age('00000000-0000-0000-0000-0000000169a1', 'Dritte', 'Vierte');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is(
  public.unarchive_household(pg_temp.hid('Archiv A'), false, p_mode => 'add'),
  jsonb_build_object('status', 'unarchived', 'previous', 'none'),
  'unarchive mode add restores'
);
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Dritte', true), ('Vierte', false), ('Archiv A', false) $$,
  'and leaves nothing'
);
select throws_ok($$ select public.unarchive_household(pg_temp.hid('Archiv B'), false, p_mode => 'move') $$,
  '22023', 'invalid_mode', 'unarchive_household knows mode add only');
select is(
  public.unarchive_household(pg_temp.hid('Archiv B'), false),
  jsonb_build_object('status', 'unarchived', 'previous', 'deleted'),
  'the old unarchive leaves the default (Dritte, deleted as its last member)'
);
select results_eq(
  $$ select * from pg_temp.memberships('00000000-0000-0000-0000-0000000169a1') $$,
  $$ values ('Vierte', false), ('Archiv A', false), ('Archiv B', true) $$,
  'only the default went; the restored household is the default'
);

-- The 10-membership cap.
select pg_temp.logout();
insert into public.households (id, name, created_by)
select ('00000000-0000-0000-0000-000001690' || lpad(i::text, 3, '0'))::uuid, 'Verein ' || i,
  '00000000-0000-0000-0000-0000000169c1'
from generate_series(1, 7) i;
insert into public.household_members (household_id, user_id)
select ('00000000-0000-0000-0000-000001690' || lpad(i::text, 3, '0'))::uuid, '00000000-0000-0000-0000-0000000169a1'
from generate_series(1, 7) i;
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select is((select count(*)::int from public.my_households()), 10, 'ten memberships');
select throws_ok(
  $$ select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e006', p_name => 'Elfte') $$,
  'P0001', 'too_many_households', 'an eleventh household is refused'
);
select is(
  (select (public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e005')).name), 'Vierte',
  'a retry of an earlier request still answers at the cap'
);
select pg_temp.logout();
delete from public.households where name like 'Verein %';

-- Access keys: PATs and API keys bound to a household, Siri follows the default.
update public.app_switches set enabled = true where key = 'public_api';
select pg_temp.login('00000000-0000-0000-0000-0000000169a1',
  '{"session_id": "00000000-0000-0000-0000-00000169a5a1"}');
select public.set_default_household(pg_temp.hid('Vierte'));
create temp table keys (kind text, household text, token text);
grant all on keys to authenticated;
insert into keys select 'pat', 'Archiv A', token
  from public.create_personal_access_token('Archiv', pg_temp.hid('Archiv A'));
insert into keys select 'pat-default', 'Vierte', token from public.create_personal_access_token('Standard');
insert into keys select 'api', 'Archiv B', token
  from public.create_api_token('API', array['read'], pg_temp.hid('Archiv B'));
insert into keys select 'api-default', 'Vierte', token from public.create_api_token('API 2', array['read']);
insert into keys select 'siri', 'Vierte', token from public.create_siri_credential();
select throws_ok(
  $$ select public.create_personal_access_token('Fremd', pg_temp.hid('Carl')) $$, '42501', 'not_a_member',
  'a PAT for a household the user is not in is refused');
select throws_ok(
  $$ select public.create_api_token('Fremd', array['read'], pg_temp.hid('Carl')) $$, '42501', 'not_a_member',
  'an API key for a household the user is not in is refused');
select pg_temp.logout();
select results_eq(
  $$ select k.kind, h.name from keys k
     join public.personal_access_tokens t on t.token_hash = encode(extensions.digest(k.token, 'sha256'), 'hex')
     join public.households h on h.id = t.household_id order by k.kind $$,
  $$ values ('api', 'Archiv B'), ('api-default', 'Vierte'), ('pat', 'Archiv A'), ('pat-default', 'Vierte'),
            ('siri', 'Vierte') $$,
  'keys are bound to the given household, else the default'
);

create function pg_temp.acts_in(p_kind text) returns text language sql as $$
  select h.name from keys k
  cross join lateral public.authenticate_access_token(encode(extensions.digest(k.token, 'sha256'), 'hex')) a
  join public.households h on h.id = a.household_id
  where k.kind = p_kind
$$;
select is(pg_temp.acts_in('pat'), 'Archiv A', 'a PAT acts in its household');
select is(pg_temp.acts_in('siri'), 'Vierte', 'Siri acts in the default');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.set_default_household(pg_temp.hid('Archiv B'));
select pg_temp.logout();
select is(pg_temp.acts_in('siri'), 'Archiv B', 'Siri follows the default at request time');
select is(pg_temp.acts_in('pat'), 'Archiv A', 'a PAT does not');

-- Carl stays in both, so the households and their revoked keys stay.
insert into public.household_members (household_id, user_id) values
  (pg_temp.hid('Vierte'), '00000000-0000-0000-0000-0000000169c1'),
  (pg_temp.hid('Archiv A'), '00000000-0000-0000-0000-0000000169c1');
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.leave_household(pg_temp.hid('Vierte'));
select public.leave_household(pg_temp.hid('Archiv A'));
select pg_temp.logout();
select results_eq(
  $$ select k.kind, t.revoked_at is not null from keys k
     join public.personal_access_tokens t on t.token_hash = encode(extensions.digest(k.token, 'sha256'), 'hex')
     order by k.kind $$,
  $$ values ('api', false), ('api-default', true), ('pat', true), ('pat-default', true), ('siri', false) $$,
  'leaving ends the keys of that household; the Siri credential stays while a membership is left'
);
select is(pg_temp.acts_in('siri'), 'Archiv B', 'Siri still works in the default');
select is(
  (select h.name from keys k
   join public.personal_access_tokens t on t.token_hash = encode(extensions.digest(k.token, 'sha256'), 'hex')
   join public.households h on h.id = t.household_id where k.kind = 'siri'),
  'Archiv B', 'the credential moved off the household it was made in (its deletion cascades)'
);
select is(public.purge_access_tokens() >= 0, true, 'purge_access_tokens runs');
select is(
  (select t.revoked_at is null from keys k
   join public.personal_access_tokens t on t.token_hash = encode(extensions.digest(k.token, 'sha256'), 'hex')
   where k.kind = 'siri'), true,
  'the purge keeps a Siri credential whose user still has a membership'
);
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.leave_household(pg_temp.hid('Archiv B'));
select pg_temp.logout();
select is(
  (select count(*)::int from keys k
   join public.personal_access_tokens t on t.token_hash = encode(extensions.digest(k.token, 'sha256'), 'hex')
   where t.revoked_at is null), 0,
  'the last leave ends the Siri credential too'
);

-- delete_account: every membership, the owner role passes on per household.
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.create_household('Solo');
select pg_temp.join_as('00000000-0000-0000-0000-0000000169a1', pg_temp.invite('00000000-0000-0000-0000-0000000169b1', 'Zuhause'));
select pg_temp.login('00000000-0000-0000-0000-0000000169a1');
select public.create_household(p_request_id => '00000000-0000-0000-0000-00000169e007', p_name => 'Geteilt');
select pg_temp.join_as('00000000-0000-0000-0000-0000000169c1', pg_temp.invite('00000000-0000-0000-0000-0000000169a1', 'Geteilt'));
select pg_temp.logout();
select is(public.delete_account('00000000-0000-0000-0000-0000000169a1'), 'deleted',
  'delete_account answers the default household''s fate (Solo, deleted)');
select is((select count(*)::int from public.households where name in ('Solo')), 0,
  'the household he was alone in is deleted');
select results_eq(
  $$ select h.name, m.role from public.household_members m join public.households h on h.id = m.household_id
     where h.name in ('Zuhause', 'Geteilt') order by h.name $$,
  $$ values ('Geteilt', 'owner'), ('Zuhause', 'owner') $$,
  'shared households are kept with an owner: Geteilt passed to Carl, Zuhause to Lea when Peter left it (W2)'
);
select is(pg_temp.default_of('00000000-0000-0000-0000-0000000169c1'), 'Carl',
  'Carl''s default is untouched by the new membership');

select * from finish();
rollback;
