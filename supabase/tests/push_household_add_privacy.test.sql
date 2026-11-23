-- Job 377, Legal N-401 and the review of 2026-11-22: what a push may say and which inserts are
-- adds. Items of a drugstore category, or of a pharmacy or drugstore store (dm among them), never
-- put their name in a push; a mixed batch is a count; an add deleted before the send, an item
-- that arrives ticked, an undo of a delete and a tick's undo are not pushed, and an item put back
-- from "Zuletzt verwendet" is. A member's name can be left out (Art. 21).
begin;
select plan(38);

\set peter '''00000000-0000-0000-0000-000000377c01'''
\set lea '''00000000-0000-0000-0000-000000377c02'''

insert into auth.users (id, email) values (:peter, 'peter377c@example.com'), (:lea, 'lea377c@example.com');
update public.profiles set display_name = 'Lea' where id = :lea;
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select public.set_push_household_add(true, 'de');
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
insert into public.household_members (household_id, user_id, role) select id, :lea, 'member' from home;
update public.app_switches set enabled = true where key = 'push_household_add';
create temp table lst as select id from public.lists where household_id = (select id from home) limit 1;
create temp table stores_ as
  with s as (insert into public.stores (household_id, name, seed_key, sort_order)
    select id, v.name, v.seed, v.ord from home, (values
      ('Linden-Apotheke', null, 1), ('dm', 'dm', 2), ('Rossmann', null, 3), ('Rewe', 'rewe', 4)) v (name, seed, ord)
    returning id, name)
  select * from s;

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
create function pg_temp.id(p_store text) returns uuid language sql as $$
  select id from stores_ where name = p_store $$;
create function pg_temp.add(p_name text, p_store text default null, p_status text default 'active',
  p_id uuid default gen_random_uuid()) returns uuid language sql as $$
  insert into public.items (id, household_id, list_id, name, added_by, status, store_id)
  values (p_id, (select id from home), (select id from lst), p_name, '00000000-0000-0000-0000-000000377c02',
    p_status, case when p_store is not null then pg_temp.id(p_store) end)
  returning id
$$;
create function pg_temp.age(p_by interval) returns void language sql as $$
  update public.push_add_queue set created_at = created_at - p_by $$;
create function pg_temp.body(p_i integer default 0) returns text language sql as $$
  select (request -> 'recipients' -> 0 ->> 'body') from (select request, row_number() over () n from public.push_add_take()) t
  where n = p_i + 1 $$;
create function pg_temp.sent() returns jsonb language sql as $$
  select coalesce(jsonb_agg(request), '[]'::jsonb) from public.push_add_take() $$;

-- The normal named path ---------------------------------------------------------------------------

select pg_temp.add('Milch');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat Milch hinzugefügt', 'a grocery is named');

-- Pharmacy and drugstore: never named ----------------------------------------------------------------

select pg_temp.add('Zahnpasta');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'an item of the Drogerie category is not named');

select pg_temp.add('Milch2', 'Linden-Apotheke');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'an item of a pharmacy is not named, whatever its category');

select pg_temp.add('Milch3', 'dm');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'an item of the drugstore store dm is not named');

select pg_temp.add('Milch4', 'Rossmann');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'an item of the drugstore Rossmann is not named');

select pg_temp.add('Milch5', 'Rewe');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat Milch5 hinzugefügt', 'a supermarket is named');


select pg_temp.login(:peter); select public.set_push_household_add(true, 'en'); select pg_temp.as_postgres();
select pg_temp.add('Zahnpasta2');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea added something to the list', 'and in English');
select pg_temp.add('Milch6');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea added Milch6', 'a named item in English');
select pg_temp.login(:peter); select public.set_push_household_add(true, 'de'); select pg_temp.as_postgres();

-- Batches -----------------------------------------------------------------------------------------------

select pg_temp.add('Milch7'); select pg_temp.add('Zahnpasta3');
select pg_temp.age('3 minutes');
with r as (select pg_temp.sent() as j)
select is(r.j -> 0 -> 'recipients' -> 0 ->> 'body', 'Lea hat etwas zur Liste hinzugefügt', 'a mixed batch is generic, no count (N-440)')
from r;
select pg_temp.add('Milch8'); select pg_temp.add('Zahnpasta4');
select pg_temp.age('3 minutes');
select ok(pg_temp.sent()::text !~ '(Milch|Zahnpasta)', 'and carries no item name');
select pg_temp.add('Zahnpasta5'); select pg_temp.add('Zahnpasta6');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'a batch of drugstore items is generic too');
select pg_temp.login(:peter); select public.set_push_household_add(true, 'en'); select pg_temp.as_postgres();
select pg_temp.add('Milch7e'); select pg_temp.add('Zahnpasta7e');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea added something to the list', 'English: a mixed batch is generic');
select pg_temp.login(:peter); select public.set_push_household_add(true, 'de'); select pg_temp.as_postgres();
select pg_temp.add('Milch9'); select pg_temp.add('Milch10');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat 2 Einträge hinzugefügt', 'a batch of groceries is a count');

-- An edit inside the window counts: the name is read when the group is sent.
select pg_temp.add('Milch11');
update public.items set store_id = pg_temp.id('dm') where name = 'Milch11';
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'an item moved to dm before the send is not named');

-- The name stopgap: medicine words match, a recipe or a dishwasher tablet does not
select is(public.push_item_sensitive(null, null, null, 'Insulin Pen'), true, 'Insulin is sensitive');
select is(public.push_item_sensitive(null, null, null, 'Rezeptfreie Salbe'), true, 'rezeptfrei is sensitive');
select is(public.push_item_sensitive(null, null, null, 'Kochrezept Lasagne'), false, 'a cooking recipe is not');
select is(public.push_item_sensitive(null, null, null, 'Spülmaschinentabletten'), false, 'a dishwasher tablet is not');

-- Inserts that are not adds ---------------------------------------------------------------------------------

delete from public.push_add_queue;
select pg_temp.add('Gekauft1', null, 'bought');
select is((select count(*)::int from public.push_add_queue), 0, 'an item that arrives ticked is not an add');

select pg_temp.add('Quark1');
select pg_temp.age('1 minute');
select is((select count(*)::int from public.push_add_queue), 1, 'a new item is queued');
delete from public.push_add_queue;
create temp table gone as select pg_temp.add('Quark2') as id;
delete from public.push_add_queue;
delete from public.items where id = (select id from gone);
select pg_temp.add('Quark2', null, 'active', (select id from gone));
select is((select count(*)::int from public.push_add_queue), 0, 'the undo of a delete (same id, within 10 minutes) is not an add');
delete from public.items where id = (select id from gone);
update public.item_events set created_at = now() - interval '11 minutes' where item_id = (select id from gone);
select pg_temp.add('Quark2', null, 'active', (select id from gone));
select is((select count(*)::int from public.push_add_queue), 1, 'later it is');
delete from public.push_add_queue;

-- Deleted before the send ---------------------------------------------------------------------------------------

select pg_temp.add('Schwangerschaftstest');
delete from public.items where name = 'Schwangerschaftstest';
select pg_temp.age('3 minutes');
select is(pg_temp.sent(), '[]'::jsonb, 'an add deleted before the send is not sent');
select is((select count(*)::int from public.push_add_queue), 0, 'and leaves nothing queued');
select pg_temp.add('Tee1'); select pg_temp.add('Tee2');
delete from public.items where name = 'Tee1';
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat Tee2 hinzugefügt', 'with one of two deleted, the other is named alone');
select pg_temp.add('Tee3');
update public.items set status = 'bought', bought_at = now() where name = 'Tee3';
select pg_temp.age('3 minutes');
select is(pg_temp.sent(), '[]'::jsonb, 'an add ticked off before the send is not sent');

-- An item put back from Zuletzt verwendet -------------------------------------------------------------------------------

select pg_temp.add('Reis1');
delete from public.push_add_queue;
update public.items set status = 'bought' where name = 'Reis1';
update public.items set status = 'active' where name = 'Reis1';
select is((select count(*)::int from public.push_add_queue), 0, 'a tick and its undo within 10 minutes: not an add');
update public.items set status = 'bought' where name = 'Reis1';
update public.items set bought_at = now() - interval '20 minutes' where name = 'Reis1';
update public.items set status = 'active' where name = 'Reis1';
select is((select count(*)::int from public.push_add_queue), 1, 'put back from Zuletzt verwendet later: an add');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat Reis1 hinzugefügt', 'and named');

-- Medicines the classifier files as Sonstiges (review 1) ------------------------------------------------

select pg_temp.add('Insulin');
select isnt((select c.seed_key from public.items i join public.categories c on c.id = i.category_id
  where i.name = 'Insulin'), 'drugstore', 'the classifier does not file Insulin under Drogerie (why the name list exists)');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'Insulin is not named');
select pg_temp.add('Antibabypille');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'Antibabypille is not named');
select pg_temp.add('Ovulationstest');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Lea hat etwas zur Liste hinzugefügt', 'Ovulationstest is not named');

-- (d) again at the send ------------------------------------------------------------------------------------

select pg_temp.add('Linsen');
insert into public.item_events (household_id, item_id, action, item_name, actor, source)
values ((select id from home), gen_random_uuid(), 'bought', 'Hafer', :lea, 'app');
select pg_temp.age('3 minutes');
select is(pg_temp.sent(), '[]'::jsonb, 'an adder who ticked since the add is shopping: nothing is sent');
delete from public.item_events where item_name = 'Hafer';

-- Art. 21: a member's name left out ---------------------------------------------------------------------------------------

select pg_temp.login(:lea); select public.set_push_name_hidden(true);
select is((select name_hidden from public.push_preferences), true, 'Lea hides her name, without switching an alert on');
select pg_temp.as_postgres();
select pg_temp.add('Birnen');
select pg_temp.age('3 minutes');
select is(pg_temp.body(), 'Jemand hat Birnen hinzugefügt', 'others read "Jemand" for her adds');
select pg_temp.login(:lea); select public.set_push_name_hidden(false); select pg_temp.as_postgres();
select throws_ok($$ select public.set_push_name_hidden(null) $$, '28000', 'not_authenticated', 'a call without a session is refused');

-- The list's deletion takes its queue ---------------------------------------------------------------------------------------------

select pg_temp.add('Honig1');
delete from public.items where household_id = (select id from home);
select pg_temp.age('3 minutes');
select is(pg_temp.sent(), '[]'::jsonb, 'nothing is left of an emptied household');

select * from finish();
rollback;
