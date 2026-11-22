-- Job 377: the household-add alert's decisions (20261122213000_push_household_add.sql,
-- docs/PUSH.md). Who is told (never the adder, only members who switched it on), when
-- (batching), what the text says (de and en, one item or a count), and when nobody is told (the
-- server switch off, the adder shopping). The post to the push function is push_add_flush's one
-- line; what it sends is push_add_take's result, which is checked here.
begin;
select plan(29);

\set peter '''00000000-0000-0000-0000-000000377b01'''
\set lea '''00000000-0000-0000-0000-000000377b02'''
\set olga '''00000000-0000-0000-0000-000000377b03'''

insert into auth.users (id, email) values
  (:peter, 'peter377@example.com'), (:lea, 'lea377@example.com'), (:olga, 'olga377@example.com');
update public.profiles set display_name = 'Lea' where id = :lea;
update public.profiles set display_name = 'Peter' where id = :peter;
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', jsonb_build_object('sub', :peter, 'role', 'authenticated')::text, true);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
insert into public.household_members (household_id, user_id, role)
select id, u, 'member' from home, unnest(array[:lea, :olga]::uuid[]) u;
create temp table lst as select id from public.lists where household_id = (select id from home) limit 1;

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
create function pg_temp.add(p_who uuid, p_name text) returns void language sql as $$
  insert into public.items (household_id, list_id, name, added_by)
  values ((select id from home), (select id from lst), p_name, p_who)
$$;
-- Moves everything queued back in time.
create function pg_temp.age(p_by interval) returns void language sql as $$
  update public.push_add_queue set created_at = created_at - p_by
$$;
create function pg_temp.requests() returns jsonb language sql as $$
  select coalesce(jsonb_agg(request), '[]'::jsonb) from public.push_add_take()
$$;

-- Settings ---------------------------------------------------------------------------------------

select pg_temp.login(:peter);
select is((select count(*)::int from public.push_preferences), 0, 'nobody has switched anything: off is no row');
select throws_ok($$ select public.set_push_household_add(true, 'fr') $$, '22023', 'invalid_language', 'de or en');
select throws_ok($$ select public.set_push_household_add(null, 'de') $$, '22023', 'missing_argument', 'on or off');
select throws_ok($$ update public.push_preferences set household_add = true $$, '42501', null, 'no direct write');
select public.set_push_household_add(true, 'de');
select is((select (household_add, language)::text from public.push_preferences), '(t,de)', 'Peter switches it on, in German');
select pg_temp.login(:lea);
select is((select count(*)::int from public.push_preferences), 0, 'Lea reads none of Peter''s settings');
select public.set_push_household_add(true, 'en');
select pg_temp.as_postgres();

-- The server switch --------------------------------------------------------------------------------

select pg_temp.add(:lea, 'Salz');
select is((select count(*)::int from public.push_add_queue), 0, 'server switch off: nothing is queued');
update public.app_switches set enabled = true where key = 'push_household_add';

-- (a) never my own adds ------------------------------------------------------------------------------

select pg_temp.add(:lea, 'Milch');
select is((select count(*)::int from public.push_add_queue), 1, 'Lea''s add is queued for Peter');
select pg_temp.age('3 minutes');
select is((pg_temp.requests() -> 0 -> 'recipients')::text,
  jsonb_build_array(jsonb_build_object('user_id', :peter::uuid, 'title', 'Snacklist', 'body', 'Lea hat Milch hinzugefügt'))::text,
  'one item, in German, to Peter only (Lea herself and Olga, who has not switched it on, are left out)');
select is((select count(*)::int from public.push_add_queue), 0, 'taking empties the queue');

select pg_temp.add(:peter, 'Brot');
select pg_temp.age('3 minutes');
select is((pg_temp.requests() -> 0 -> 'recipients' -> 0 ->> 'user_id'), :lea::text,
  'Peter''s add goes to Lea (switched on), never back to Peter');
select is((pg_temp.requests()), '[]'::jsonb, 'and a second take finds nothing');

select pg_temp.add(:peter, 'Butter');
select pg_temp.age('3 minutes');
select is((pg_temp.requests() -> 0 -> 'recipients' -> 0 ->> 'body'), 'Peter added Butter',
  'Lea reads it in English, as she set');

-- (b) batching ---------------------------------------------------------------------------------------

select pg_temp.add(:lea, 'Eier');
select is(pg_temp.requests(), '[]'::jsonb, 'a fresh add waits for the quiet window');
select pg_temp.age('1 minute');
select pg_temp.add(:lea, 'Mehl');
select pg_temp.age('1 minute 30 seconds');
select is(pg_temp.requests(), '[]'::jsonb, 'a newer add keeps the group open (newest 1:30 old)');
select pg_temp.age('1 minute');
select is((pg_temp.requests() -> 0 -> 'recipients' -> 0 ->> 'body'), 'Lea hat 2 Einträge hinzugefügt',
  'two adds are one push with a count, once quiet for 2 minutes');

select pg_temp.add(:lea, 'a1'); select pg_temp.age('4 minutes');
select pg_temp.add(:lea, 'a2'); select pg_temp.age('30 seconds');
select pg_temp.add(:lea, 'a3'); select pg_temp.age('30 seconds');
select pg_temp.add(:lea, 'a4'); select pg_temp.age('30 seconds');
select is((pg_temp.requests() -> 0 -> 'recipients' -> 0 ->> 'body'), 'Lea hat 4 Einträge hinzugefügt',
  'a group never waits longer than 5 minutes for its oldest add, and says "4 Einträge"');

select pg_temp.add(:lea, 'b1'); select pg_temp.add(:lea, 'b2'); select pg_temp.add(:lea, 'b3'); select pg_temp.add(:lea, 'b4');
select pg_temp.age('3 minutes');
select pg_temp.add(:peter, 'Tee1'); -- a later group of another adder
select is(jsonb_array_length(pg_temp.requests()), 1, 'only the due group goes out');
select is((select count(*)::int from public.push_add_queue), 1, 'the newer add stays queued');
delete from public.push_add_queue;

select pg_temp.add(:lea, 'Reis');
select pg_temp.add(:peter, 'Honig');
select pg_temp.age('3 minutes');
select is(jsonb_array_length(pg_temp.requests()), 2, 'two adders are two groups');

-- (d) no push while the adder is shopping ---------------------------------------------------------------

insert into public.item_events (household_id, item_id, action, item_name, actor, source, created_at)
values ((select id from home), gen_random_uuid(), 'bought', 'Hafer', :lea, 'app', now() - interval '4 minutes');
select pg_temp.add(:lea, 'Quark1');
select is((select count(*)::int from public.push_add_queue), 0, 'Lea ticked 4 minutes ago: she is shopping, no push for her add');
select pg_temp.add(:peter, 'Tee2');
select is((select count(*)::int from public.push_add_queue), 1, 'Peter, who is not shopping, still gets pushed to Lea');
delete from public.push_add_queue;
update public.item_events set created_at = now() - interval '11 minutes' where item_name = 'Hafer';
select pg_temp.add(:lea, 'Quark3');
select is((select count(*)::int from public.push_add_queue), 1, 'ten minutes after her last tick the trip is over');
delete from public.push_add_queue;
update public.item_events set source = 'voice', created_at = now() - interval '1 minute' where item_name = 'Hafer';
select pg_temp.add(:lea, 'Quark4');
select is((select count(*)::int from public.push_add_queue), 1, 'a Siri tick is no trip (only app ticks count, as in detection)');

-- Who is left out -------------------------------------------------------------------------------------

delete from public.push_add_queue;
select pg_temp.login(:peter);
select public.set_push_household_add(false, 'de');
select pg_temp.login(:lea);
select public.set_push_household_add(false, 'en');
select pg_temp.as_postgres();
select pg_temp.add(:lea, 'Milch5');
select is((select count(*)::int from public.push_add_queue), 0, 'nobody wants it: nothing is stored, not even the item name');
select pg_temp.login(:peter); select public.set_push_household_add(true, 'de'); select pg_temp.as_postgres();
select pg_temp.add(:lea, 'Milch6');
delete from public.household_members where user_id = :peter;
select pg_temp.age('3 minutes');
select is(pg_temp.requests(), '[]'::jsonb, 'someone who left the household is not told');

delete from public.push_add_queue;
select pg_temp.add(:lea, 'Milch7');
update public.push_add_queue set created_at = now() - interval '2 hours';
select pg_temp.requests();
select is((select count(*)::int from public.push_add_queue), 0, 'an add older than an hour is dropped, not sent');

-- Export and account deletion ---------------------------------------------------------------------------

select pg_temp.login(:olga);
select public.set_push_household_add(true, 'de');
select is((public.export_my_data() -> 'push_preferences' ->> 'household_add'), 'true', 'the export lists the setting');
select pg_temp.as_postgres();
delete from auth.users where id = :olga;
select is((select count(*)::int from public.push_preferences where user_id = :olga), 0, 'it goes with the account');

select * from finish();
rollback;
