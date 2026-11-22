begin;
select plan(27);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'peter@example.com'),
  ('00000000-0000-0000-0000-0000000000c2', 'bob@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select public.create_household('Bob');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
create temp table h as select id from public.create_household('Peter');
grant select on h to authenticated;
set local role postgres;

-- History is written explicitly with a fixed clock, so the trigger stays out.
alter table public.items disable trigger items_log_event;
create temp table clock as select '2026-06-15 12:00:00+02'::timestamptz as t;
grant select on clock to authenticated;

create function pg_temp.item(p_name text, p_quantity text default null, p_status text default 'bought')
returns uuid language sql as $$
  insert into public.items (household_id, name, quantity, status)
  select id, p_name, p_quantity, p_status from h
  returning id;
$$;

create function pg_temp.event(p_item uuid, p_action text, p_name text, p_at timestamptz) returns void
language sql as $$
  insert into public.item_events (household_id, item_id, action, item_name, created_at)
  select id, p_item, p_action, p_name, p_at from h;
$$;

-- An item bought once on each of the given days before the clock.
create function pg_temp.bought(p_name text, p_days int[]) returns void language sql as $$
  with i as (select pg_temp.item(p_name) as id)
  select pg_temp.event(i.id, a.action, p_name, (select t from clock) - d * interval '1 day' + a.offs)
  from i, unnest(p_days) as d,
    (values ('added', interval '-1 hour'), ('bought', interval '0')) as a (action, offs);
$$;

select pg_temp.bought('Milch', array[1, 3, 5, 8, 10, 12]);
select pg_temp.bought('Mehl', array[20]);
select pg_temp.bought('Mineralwasser', array[40]);
select pg_temp.bought('Bio-Milch', array[0, 1, 2, 3, 4, 5, 6, 7]);
select pg_temp.bought('Hafer Milch', array[2]);
select pg_temp.bought('Hafermilch', array[2]);
select pg_temp.bought('Käse', array[2]);
select pg_temp.bought('Windeln Größe 4', array[9]);
select pg_temp.bought('Windeln Größe 5', array[9]);
select pg_temp.bought('Brot', array[14, 7, 0]);
select pg_temp.bought('Eier', array[7, 0]);
select pg_temp.bought('Butter', array[10]);
select pg_temp.bought('Zimt', array[400]);
select pg_temp.item('butter', null, 'active');

-- Gurken with 2 bought 10 days ago, then Gurke with 3 bought 3 days ago.
with g as (select pg_temp.item('Gurken', '2') as id)
select pg_temp.event(id, 'bought', 'Gurken', (select t from clock) - interval '10 days') from g;
update public.items set bought_at = (select t from clock) - interval '10 days' where name = 'Gurken' and household_id = (select id from h);
with g as (select pg_temp.item('Gurke', '3') as id)
select pg_temp.event(id, 'bought', 'Gurke', (select t from clock) - interval '3 days') from g;
update public.items set bought_at = (select t from clock) - interval '3 days' where name = 'Gurke' and household_id = (select id from h);

-- A classifier move on another day is not a use.
select pg_temp.event((select id from public.items where name = 'Mehl' and household_id = (select id from h)), 'edited', 'Mehl', (select t from clock) - interval '1 day');
with s as (select pg_temp.item('Senf') as id)
select pg_temp.event(id, 'edited', 'Senf', (select t from clock) - interval '3 days') from s;

-- Quark: real purchases 14 and 7 days ago, a tick undone after 5 minutes 2 days ago.
with q as (select pg_temp.item('Quark') as id)
select pg_temp.event(q.id, e.action, 'Quark', (select t from clock) + e.at)
from q, (values
  ('bought', interval '-14 days'),
  ('bought', interval '-7 days'),
  ('bought', interval '-2 days'),
  ('restored', interval '-2 days' + interval '5 minutes')
) as e (action, at);

-- Joghurt: restored 15 minutes after the tick, so the purchase stands.
with j as (select pg_temp.item('Joghurt') as id)
select pg_temp.event(j.id, e.action, 'Joghurt', (select t from clock) + e.at)
from j, (values ('bought', interval '-5 days'), ('restored', interval '-5 days' + interval '15 minutes')) as e (action, at);

-- A typo: added and deleted, never bought; the items row is gone.
create temp table typo as select gen_random_uuid() as id;
select pg_temp.event(id, 'added', 'Milhc', (select t from clock) - interval '1 hour') from typo;
select pg_temp.event(id, 'deleted', 'Milhc', (select t from clock) - interval '59 minutes') from typo;

-- Kaffee at 23:30 and 08:00 UTC: different UTC dates, one Berlin day.
with k as (select pg_temp.item('Kaffee') as id)
select pg_temp.event(k.id, 'bought', 'Kaffee', at)
from k, (values ('2026-06-10 23:30:00+00'::timestamptz), ('2026-06-11 08:00:00+00')) as e (at);

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
-- Peter's claims, but as postgres: an API caller's p_now is ignored (job 352), the tests' clock is not.
set local role postgres;

create function pg_temp.names(p_prefix text, p_limit int default 5, p_now timestamptz default null)
returns text[] language sql as $$
  select coalesce(array_agg(s.name), '{}')
  from public.suggest_items((select id from h), p_prefix, p_limit, coalesce(p_now, (select t from clock))) as s;
$$;

create function pg_temp.due(p_name text, p_after interval) returns boolean language sql as $$
  select s.due
  from public.suggest_items((select id from h), p_name, 1, (select t from clock) + p_after) as s
  where s.name = p_name;
$$;

-- Ranking and prefixes.
select is(pg_temp.names('m', 2), array['Milch', 'Mehl'], 'Milch (many uses) ranks before Mehl for m');
select is(pg_temp.names('Mi', 2), array['Milch', 'Mineralwasser'], 'Mi finds Milch first');
select is(pg_temp.names('milch'), array['Milch', 'Bio-Milch', 'Hafer Milch'],
  'word starts match after the whole-name match, word middles (Hafermilch) do not');
select is(pg_temp.names('kä'), array['Käse'], 'an umlaut prefix finds Käse');
select is(pg_temp.names('KAE'), array['Käse'], 'the prefix folds case and umlauts like the name');
select is(cardinality(pg_temp.names('')), 5, 'an empty prefix returns the default limit of 5');
select is(pg_temp.names('', 0), '{}'::text[], 'a zero limit returns nothing');
select is(pg_temp.names('', -1), '{}'::text[], 'a negative limit returns nothing');
select is(cardinality(pg_temp.names('', 1000)), 15, 'a large limit returns every suggestion');

-- Grouping and the row's fields.
select results_eq(
  $$ select name, quantity, uses from public.suggest_items((select id from h), 'gurk', 5, (select t from clock)) $$,
  $$ values ('Gurke', '3', 2) $$,
  'Gurke and Gurken are one row named after the latest use, with the last quantity'
);
select is(pg_temp.names('windeln'), array['Windeln Größe 4', 'Windeln Größe 5'], 'Windeln Größe 4 and 5 are two rows');
select results_eq(
  $$ select uses, last_used from public.suggest_items((select id from h), 'kaffee', 5, (select t from clock)) $$,
  $$ values (1, '2026-06-10 22:00:00+00'::timestamptz) $$,
  'uses count Berlin days, not UTC dates; last_used is that day'
);

-- What does not count.
select results_eq(
  $$ select uses, last_used from public.suggest_items((select id from h), 'mehl', 5, (select t from clock)) $$,
  $$ select 1, date_trunc('day', t - interval '20 days', 'Europe/Berlin') from clock $$,
  'an edited event is no use'
);
select is(pg_temp.names('senf'), '{}'::text[], 'an item with only edited events is not suggested');
select results_eq(
  $$ select uses, due from public.suggest_items((select id from h), 'quark', 5, (select t from clock)) $$,
  $$ values (2, true) $$,
  'a tick undone within 10 minutes is no purchase and no use'
);
select results_eq(
  $$ select uses from public.suggest_items((select id from h), 'joghurt', 5, (select t from clock)) $$,
  $$ values (1) $$,
  'a restore after more than 10 minutes leaves the purchase'
);
select is(pg_temp.names('milh'), '{}'::text[], 'a deleted, never bought typo is not suggested');
select is(pg_temp.names('butter'), '{}'::text[], 'an item on the list right now is left out');
select is(pg_temp.names('bio', 5, (select t from clock) - interval '3 days'), array['Bio-Milch'],
  'events after p_now are not history');

-- Due: Brot bought 14, 7 and 0 days before the clock, Eier 7 and 0, Mehl once.
select is(pg_temp.due('Brot', interval '3 days'), false, 'not due 3 days after the last of 3 weekly purchases');
select is(pg_temp.due('Brot', interval '7 days'), true, 'due 7 days after');
select is(pg_temp.due('Brot', interval '28 days'), true, 'still due at 4 times the gap');
select is(pg_temp.due('Brot', interval '29 days'), false, 'not due 29 days after: they stopped buying it');
select is(pg_temp.due('Eier', interval '7 days'), true, 'two purchases suffice');
select is(
  (select bool_or(pg_temp.due('Mehl', d * interval '1 day')) from unnest(array[0, 1, 7, 20, 40, 80]) as d),
  false, 'one purchase is never due'
);

select is(pg_temp.names('zimt'), '{}'::text[], 'history older than a year is not used');

-- Members only.
select pg_temp.login('00000000-0000-0000-0000-0000000000c2');
select throws_ok($$ select pg_temp.names('', 200) $$, '42501', 'not_a_member',
  'another household''s member is refused');

select * from finish();
rollback;
