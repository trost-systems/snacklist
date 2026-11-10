-- Legal review N-115: leaving a household or being removed from it unlinks the user from that
-- household's items, lists, history, merges, invites, join decisions and the household row, as
-- deleting the account does. Their other households and the other members keep every link.
begin;
select plan(19);

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

grant execute on all functions in schema pg_temp to authenticated;

\set lea '''00000000-0000-0000-0000-000000178a01'''
\set pia '''00000000-0000-0000-0000-000000178a02'''

insert into auth.users (id, email) values
  (:lea, 'lea178@example.com'),
  (:pia, 'pia178@example.com');

-- Three households of Lea's and Pia's: Lea owns "Weg", Pia owns "Raus" and "Bleibt".
insert into public.households (id, name, created_by) values
  ('00000000-0000-0000-0000-000000178b01', 'Weg', :lea),
  ('00000000-0000-0000-0000-000000178b02', 'Raus', :pia),
  ('00000000-0000-0000-0000-000000178b03', 'Bleibt', :pia);
select public.seed_household(id, false) from public.households where name in ('Weg', 'Raus', 'Bleibt');
insert into public.household_members (household_id, user_id, role) values
  ('00000000-0000-0000-0000-000000178b01', :lea, 'owner'),
  ('00000000-0000-0000-0000-000000178b01', :pia, 'member'),
  ('00000000-0000-0000-0000-000000178b02', :pia, 'owner'),
  ('00000000-0000-0000-0000-000000178b02', :lea, 'member'),
  ('00000000-0000-0000-0000-000000178b03', :pia, 'owner'),
  ('00000000-0000-0000-0000-000000178b03', :lea, 'member');

-- In each household: Lea's item Pia bought, Pia's item Lea bought, Lea's open item and Pia's, a
-- list each, a merge of Lea's row into Pia's, an invite each and one Lea used, a request Lea
-- decided.
create function pg_temp.fill(p_household uuid, p_lea uuid, p_pia uuid, p_tag text) returns void
language plpgsql as $$
declare
  v_lea_bought uuid;
  v_pia_bought uuid;
begin
  perform pg_temp.login(p_lea);
  insert into public.items (household_id, name) values (p_household, 'Milch') returning id into v_lea_bought;
  insert into public.items (household_id, name) values (p_household, 'Senf');
  perform pg_temp.login(p_pia);
  insert into public.items (household_id, name) values (p_household, 'Brot') returning id into v_pia_bought;
  insert into public.items (household_id, name) values (p_household, 'Salz');
  update public.items set status = 'bought' where id = v_lea_bought;
  perform pg_temp.login(p_lea);
  update public.items set status = 'bought' where id = v_pia_bought;
  perform pg_temp.logout();
  insert into public.lists (household_id, name, position, created_by) values
    (p_household, 'Leas Liste', 1, p_lea), (p_household, 'Pias Liste', 2, p_pia);
  insert into public.item_merges (id, household_id, kept_id, kept_before, kept_after, merged_row, merged_by)
  values (gen_random_uuid(), p_household, v_pia_bought,
    jsonb_build_object('added_by', p_pia, 'bought_by', p_lea), '{}',
    jsonb_build_object('added_by', p_lea, 'bought_by', null), p_lea);
  insert into public.invites (household_id, code, created_by, used_by) values
    (p_household, 'LEAKEY' || p_tag, p_lea, null),
    (p_household, 'PMAKEY' || p_tag, p_pia, p_lea);
  insert into public.join_requests (household_id, user_id, decision, decided_at, decided_by) values
    (p_household, p_pia, 'approved', now(), p_lea);
end $$;

select pg_temp.fill('00000000-0000-0000-0000-000000178b01', :lea, :pia, 'A2');
select pg_temp.fill('00000000-0000-0000-0000-000000178b02', :lea, :pia, 'B2');
select pg_temp.fill('00000000-0000-0000-0000-000000178b03', :lea, :pia, 'C2');

-- Every place a user's id sits in a household's content, counted.
create function pg_temp.links(p_household uuid, p_user uuid) returns int language sql as $$
  select (select count(*) from public.items i where i.household_id = p_household and i.added_by = p_user)::int
       + (select count(*) from public.items i where i.household_id = p_household and i.bought_by = p_user)::int
       + (select count(*) from public.item_events e where e.household_id = p_household and e.actor = p_user)::int
       + (select count(*) from public.lists l where l.household_id = p_household and l.created_by = p_user)::int
       + (select count(*) from public.item_merges m where m.household_id = p_household and m.merged_by = p_user)::int
       + (select count(*) from public.item_merges m, jsonb_each_text(m.merged_row) j
          where m.household_id = p_household and j.value = p_user::text)::int
       + (select count(*) from public.item_merges m, jsonb_each_text(m.kept_before) j
          where m.household_id = p_household and j.value = p_user::text)::int
       + (select count(*) from public.invites v where v.household_id = p_household and v.created_by = p_user)::int
       + (select count(*) from public.invites v where v.household_id = p_household and v.used_by = p_user)::int
       + (select count(*) from public.join_requests r where r.household_id = p_household and r.decided_by = p_user)::int
       + (select count(*) from public.households h where h.id = p_household and h.created_by = p_user)::int
$$;

create temp table before_leave as
  select h.id, pg_temp.links(h.id, :lea) as lea, pg_temp.links(h.id, :pia) as pia,
    (select count(*) from public.items i where i.household_id = h.id)::int as items,
    (select count(*) from public.item_events e where e.household_id = h.id)::int as events
  from public.households h where h.name in ('Weg', 'Raus', 'Bleibt');

select ok((select bool_and(lea >= 13 and pia >= 9) from before_leave),
  'every kind of link is there in all three households to start with');

-- Lea leaves "Weg", her own household; Pia becomes its owner.
select pg_temp.login(:lea);
select is(public.leave_household('00000000-0000-0000-0000-000000178b01') ->> 'status', 'left', 'Lea leaves Weg');
select pg_temp.logout();

select is(pg_temp.links('00000000-0000-0000-0000-000000178b01', :lea), 0,
  'leaving takes Lea''s id out of every row of that household');
select is(pg_temp.links('00000000-0000-0000-0000-000000178b01', :pia),
  (select pia from before_leave where id = '00000000-0000-0000-0000-000000178b01'),
  'Pia''s links there stay');
select is((select count(*)::int from public.item_events where household_id = '00000000-0000-0000-0000-000000178b01'),
  (select events from before_leave where id = '00000000-0000-0000-0000-000000178b01'),
  'the history keeps every entry, and the nulling adds none');
select is((select count(*)::int from public.items where household_id = '00000000-0000-0000-0000-000000178b01'),
  4, 'and the items stay for Pia');
select is((select array_agg(name order by name) from public.items
  where household_id = '00000000-0000-0000-0000-000000178b01' and added_by is null), array['Milch', 'Senf'],
  'with Lea''s two items now without an author');
select is((select bought_by from public.items
  where household_id = '00000000-0000-0000-0000-000000178b01' and name = 'Milch'), :pia::uuid,
  'Pia still bought Lea''s Milch');
select is((select kept_before ->> 'added_by' from public.item_merges
  where household_id = '00000000-0000-0000-0000-000000178b01'), :pia,
  'a merge keeps Pia''s id in its stored rows');
select results_eq(
  $$ select id, lea, pia from before_leave where id <> '00000000-0000-0000-0000-000000178b01' order by id $$,
  $$ select id, pg_temp.links(id, '00000000-0000-0000-0000-000000178a01'), pg_temp.links(id, '00000000-0000-0000-0000-000000178a02') from before_leave
     where id <> '00000000-0000-0000-0000-000000178b01' order by id $$,
  'Lea''s other households keep all her links');

-- Pia removes Lea from "Raus".
select pg_temp.login(:pia);
select lives_ok($$ select public.remove_member('00000000-0000-0000-0000-000000178b02', '00000000-0000-0000-0000-000000178a01') $$,
  'Pia removes Lea from Raus');
select pg_temp.logout();

select is(pg_temp.links('00000000-0000-0000-0000-000000178b02', :lea), 0,
  'a removal takes Lea''s id out of every row of that household');
select is(pg_temp.links('00000000-0000-0000-0000-000000178b02', :pia),
  (select pia from before_leave where id = '00000000-0000-0000-0000-000000178b02'),
  'Pia''s links there stay');
select is(pg_temp.links('00000000-0000-0000-0000-000000178b03', :lea),
  (select lea from before_leave where id = '00000000-0000-0000-0000-000000178b03'),
  'Bleibt, where Lea still is a member, keeps hers');

-- The author columns still hold for anyone else's update.
select pg_temp.login(:pia);
update public.items set added_by = null
where household_id = '00000000-0000-0000-0000-000000178b03' and added_by = :lea;
update public.items set added_by = :pia
where household_id = '00000000-0000-0000-0000-000000178b03' and name = 'Senf';
select pg_temp.logout();
select is((select count(*)::int from public.items
  where household_id = '00000000-0000-0000-0000-000000178b03' and added_by = :lea), 2,
  'a member cannot clear a current member''s authorship');

select pg_temp.login(:pia);
update public.items set added_by = null
where household_id = '00000000-0000-0000-0000-000000178b02' and added_by = :pia;
select pg_temp.logout();
select is((select count(*)::int from public.items
  where household_id = '00000000-0000-0000-0000-000000178b02' and added_by = :pia), 2,
  'nor their own');

-- The last member leaving deletes the household as before.
select pg_temp.login(:pia);
select is(public.leave_household('00000000-0000-0000-0000-000000178b01') ->> 'deleted', 'true',
  'the last member leaving still deletes the household');
select pg_temp.logout();

-- The last member archiving keeps their links: the archive is theirs to bring back as it was.
update public.app_switches set enabled = true where key = 'household_archive';
select public.promotional_premium_sync('00000000-0000-0000-0000-000000178b02', true, '2100-01-01');
create temp table raus_before as select pg_temp.links('00000000-0000-0000-0000-000000178b02', :pia) as pia;
select pg_temp.login(:pia);
select is(public.leave_household('00000000-0000-0000-0000-000000178b02', true) ->> 'archived', 'true',
  'Pia, the last member of Raus, archives it');
select pg_temp.logout();
select is(pg_temp.links('00000000-0000-0000-0000-000000178b02', :pia), (select pia from raus_before),
  'and the archived household keeps every link of hers');

select * from finish();
rollback;
