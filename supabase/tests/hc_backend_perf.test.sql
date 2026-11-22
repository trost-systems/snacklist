-- hc-backend-perf (job 106): a one-time proof that the rewritten suggest_items
-- (20261105075541_hc_suggest_items_names.sql) returns exactly what main's body did. The old body
-- (20261023194403_suggest_items.sql, the only one on main before job 106) is copied verbatim as a
-- pg_temp function and compared row for row (order included) on a generated household: a year of
-- trips with undone ticks, deleted typos, names with numbers, umlauts and spelling variants,
-- active items and history older than a year. Delete this file when suggest_items changes on
-- purpose. Job 352 did, in two ways compared around here: last_used comes to the day (both sides
-- are cut to it), and an API caller's p_now is ignored (the comparisons run as postgres).
begin;
select plan(14);
-- Job 352 revoked members' read of item_events; this file checks the history the trigger writes
-- as a member reads it under the policy that still guards it.
grant select on public.item_events to authenticated;

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

-- The rewrite joins events and items to their keys by name; a NULL name would drop out of that
-- join (and a NULL key would empty the `not in` filter). Both columns are NOT NULL.
select col_not_null('public', 'item_events', 'item_name', 'item_events.item_name is NOT NULL (the names join keeps every event)');
select col_not_null('public', 'items', 'name', 'items.name is NOT NULL (the names join keeps every item)');

-- suggest_items before job 106 (20261023194403_suggest_items.sql), verbatim but for the name.
create function pg_temp.suggest_items_old(
  p_household uuid,
  p_prefix text default '',
  p_limit int default 5,
  p_now timestamptz default now()
) returns table (name text, quantity text, uses int, last_used timestamptz, due boolean)
language sql stable security invoker set search_path = '' as $$
  -- Every name is keyed once: item_name_key is too slow to call per pair. A
  -- year of history is enough for usuals and keeps the cost flat as it grows.
  with history as materialized (
    select e.id, e.item_id, e.action, e.item_name, e.created_at, public.item_name_key(e.item_name) as key
    from public.item_events e
    where public.is_household_member(p_household)
      and e.household_id = p_household
      -- 'restored' is read only to drop ticks undone within 10 minutes.
      and e.action in ('added', 'bought', 'restored')
      and e.created_at <= p_now
      and e.created_at > p_now - interval '1 year'
  ),
  rows as materialized (
    select i.id, i.status, i.quantity, coalesce(i.bought_at, i.updated_at) as at, public.item_name_key(i.name) as key
    from public.items i
    where i.household_id = p_household
      and (i.status = 'active' or i.updated_at > p_now - interval '1 year')
  ),
  -- A restore within 10 minutes of the tick is the snackbar's undo, not a purchase.
  -- After a tick, an item's next added/bought/restored event is its restore, if any.
  purchases as (
    select t.id, t.item_id
    from (
      select h.id, h.item_id, h.action, h.created_at,
        lead(h.action) over w as next_action,
        lead(h.created_at) over w as next_at
      from history h
      window w as (partition by h.item_id order by h.created_at, h.id)
    ) t
    where t.action = 'bought'
      and not coalesce(t.next_action = 'restored' and t.next_at <= t.created_at + interval '10 minutes', false)
  ),
  -- An item added and deleted without ever being bought was a typo, not a use.
  counted as materialized (
    select h.id, h.action, h.item_name, h.created_at, h.key
    from history h
    where h.key <> ''
      and ((h.action = 'bought' and h.id in (select p.id from purchases p))
        or (h.action = 'added' and (
              h.item_id in (select r.id from rows r)
              or h.item_id in (select p.item_id from purchases p))))
  ),
  days as (
    select
      c.key,
      (c.created_at at time zone 'Europe/Berlin')::date as day,
      max(c.created_at) as last_at,
      max(c.created_at) filter (where c.action = 'bought') as bought_at
    from counted c
    group by 1, 2
  ),
  keys as (
    select
      d.key,
      count(*)::int as uses,
      max(d.last_at) as last_used,
      sum(power(0.5, extract(epoch from p_now - d.last_at) / 86400 / 30)) as score,
      count(d.bought_at) as purchases,
      max(d.bought_at) as last_bought_at,
      greatest(
        (max(d.day) filter (where d.bought_at is not null) - min(d.day) filter (where d.bought_at is not null))::numeric
          / nullif(count(d.bought_at) - 1, 0),
        1
      ) as gap_days
    from days d
    group by d.key
  ),
  -- The prefix is matched here, once per name, not once per join pair.
  latest_name as materialized (
    select n.key, n.name,
      case
        when btrim(coalesce(p_prefix, '')) = '' then 0
        when starts_with(n.folded, public.normalize_item_name(p_prefix)) then 0
        when exists (
          select 1 from regexp_split_to_table(n.folded, '[ -]+') as w
          where starts_with(w, public.normalize_item_name(p_prefix))
        ) then 1
      end as prefix_rank
    from (
      select distinct on (c.key) c.key, c.item_name as name, public.normalize_item_name(c.item_name) as folded
      from counted c
      order by c.key, c.created_at desc, c.id desc
    ) n
  ),
  latest_quantity as (
    select distinct on (r.key) r.key, r.quantity
    from rows r
    order by r.key, r.at desc
  ),
  ranked as (
    select k.*, n.name, n.prefix_rank, q.quantity
    from keys k
    join latest_name n using (key)
    left join latest_quantity q using (key)
    where n.prefix_rank is not null
      and k.key not in (select r.key from rows r where r.status = 'active')
  )
  select
    r.name,
    r.quantity,
    r.uses,
    r.last_used,
    r.purchases >= 2
      and extract(epoch from p_now - r.last_bought_at) / 86400 between r.gap_days and 4 * r.gap_days
  from ranked r
  order by r.prefix_rank, r.score desc, r.last_used desc, r.name
  limit least(greatest(p_limit, 0), 200);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000106a1', 'ann@example.com'),
  ('00000000-0000-0000-0000-0000000106b2', 'bob@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000106b2');
select public.create_household('Bob');
select pg_temp.login('00000000-0000-0000-0000-0000000106a1');
create temp table h as select id from public.create_household('Ann');
grant select on h to authenticated;
set local role postgres;

alter table public.items disable trigger items_log_event;
create temp table clock as select '2026-06-15 12:00:00+02'::timestamptz as t;
grant select on clock to authenticated;
create temp table names (n int, name text);
insert into names values
  (1, 'Milch'), (2, 'Bio-Milch'), (3, 'Hafer Milch'), (4, 'Hafermilch'), (5, 'Käse'), (6, 'Kaese'),
  (7, 'Windeln Größe 4'), (8, 'Windeln Größe 5'), (9, 'Brot'), (10, 'Brötchen'), (11, 'Eier'),
  (12, 'Ei'), (13, 'Gurke'), (14, 'Gurken'), (15, 'Tomaten'), (16, 'Mehl 405'), (17, 'Mehl 550'),
  (18, 'Kaffee'), (19, 'Zimt'), (20, 'Äpfel'), (21, 'Apfel'), (22, 'Müsli'), (23, 'Spülmittel'),
  (24, 'Zahnpasta'), (25, 'Duschgel'), (26, 'Nudeln'), (27, 'Reis'), (28, 'Joghurt'),
  (29, 'Butter'), (30, 'butter'), (31, 'Wasser 1,5 l'), (32, 'Sekt'), (33, 'Bananen'),
  (34, 'Grillkohle'), (35, 'Quark'), (36, 'Milhc'), (37, 'Senf'), (38, 'Ketchup');

-- 400 items over 420 days, each with an added and a bought event; every 9th tick is undone
-- 5 minutes later (no purchase), every 13th 20 minutes later (purchase stands), every 11th item
-- was a typo (added, deleted, row gone), and every 17th is on the list again.
select setseed(0.106);
create temp table plan as
select g,
  a.names[1 + floor(random() * 38)::int] as name,
  (select t from clock) - (random() * 420) * interval '1 day' as at,
  case when random() < 0.3 then (1 + floor(random() * 4))::text end as quantity
from generate_series(1, 400) g, (select array_agg(name order by n) as names from names) a;
insert into public.items (id, household_id, name, quantity, status, created_at, updated_at, bought_at)
select md5('item' || g)::uuid, (select id from h), name, quantity,
  case when g % 17 = 0 then 'active' else 'bought' end, at - interval '1 hour', at,
  case when g % 17 = 0 then null else at end
from plan where g % 11 <> 0;
-- The insert trigger stamps every row with the transaction's time; real rows carry their own.
-- Both bodies pick an arbitrary quantity among rows of a name with the same time.
alter table public.items disable trigger items_before_write;
update public.items i set updated_at = p.at, bought_at = case when p.g % 17 = 0 then null else p.at end
from plan p where i.id = md5('item' || p.g)::uuid;
alter table public.items enable trigger items_before_write;
insert into public.item_events (household_id, item_id, action, item_name, created_at)
select (select id from h), md5('item' || g)::uuid, e.action, p.name, p.at + e.offs
from plan p, lateral (values
  ('added', interval '-1 hour', true),
  ('bought', interval '0', p.g % 11 <> 0),
  ('restored', interval '5 minutes', p.g % 9 = 0 and p.g % 11 <> 0),
  ('restored', interval '20 minutes', p.g % 13 = 0 and p.g % 11 <> 0),
  ('deleted', interval '-50 minutes', p.g % 11 = 0),
  ('edited', interval '-30 minutes', p.g % 7 = 0)
) as e (action, offs, keep)
where e.keep;

select pg_temp.login('00000000-0000-0000-0000-0000000106a1');
set local role postgres;

create function pg_temp.same_usuals(p_prefix text, p_limit int, p_after interval) returns text
language sql as $$
  select format($q$ select name, quantity, uses, date_trunc('day', last_used, 'Europe/Berlin'), due
                    from public.suggest_items(%L, %L, %s, %L) $q$,
    (select id from h), p_prefix, p_limit, (select t from clock) + p_after);
$$;
create function pg_temp.old_usuals(p_prefix text, p_limit int, p_after interval) returns text
language sql as $$
  select format($q$ select name, quantity, uses, date_trunc('day', last_used, 'Europe/Berlin'), due
                    from pg_temp.suggest_items_old(%L, %L, %s, %L) $q$,
    (select id from h), p_prefix, p_limit, (select t from clock) + p_after);
$$;

select ok((select count(*) from public.suggest_items((select id from h), '', 200, (select t from clock))) >= 10,
  'the generated household has at least 10 usuals');
select results_eq(pg_temp.same_usuals('', 200, '0'), pg_temp.old_usuals('', 200, '0'),
  'suggest_items: every usual, as before');
select results_eq(pg_temp.same_usuals('', 5, '0'), pg_temp.old_usuals('', 5, '0'),
  'suggest_items: the default limit, as before');
select results_eq(pg_temp.same_usuals('m', 10, '0'), pg_temp.old_usuals('m', 10, '0'),
  'suggest_items: prefix m, as before');
select results_eq(pg_temp.same_usuals('milch', 10, '0'), pg_temp.old_usuals('milch', 10, '0'),
  'suggest_items: word starts, as before');
select results_eq(pg_temp.same_usuals('KAE', 10, '0'), pg_temp.old_usuals('KAE', 10, '0'),
  'suggest_items: folded umlaut prefix, as before');
select results_eq(pg_temp.same_usuals('mehl 5', 10, '0'), pg_temp.old_usuals('mehl 5', 10, '0'),
  'suggest_items: a prefix with a number, as before');
select results_eq(pg_temp.same_usuals('', 200, '-100 days'), pg_temp.old_usuals('', 200, '-100 days'),
  'suggest_items: an earlier clock, as before');
select results_eq(pg_temp.same_usuals('', 200, '30 days'), pg_temp.old_usuals('', 200, '30 days'),
  'suggest_items: a later clock (due changes), as before');
select results_eq(pg_temp.same_usuals('', 0, '0'), pg_temp.old_usuals('', 0, '0'),
  'suggest_items: a zero limit, as before');
select results_eq(pg_temp.same_usuals('zz', 10, '0'), pg_temp.old_usuals('zz', 10, '0'),
  'suggest_items: no match, as before');

select pg_temp.login('00000000-0000-0000-0000-0000000106b2');
-- Job 352: suggest_items runs as its definer and refuses a non-member, where the old body gave nothing.
select throws_ok($$ select public.suggest_items((select id from h), '', 200, (select t from clock)) $$, '42501',
  'not_a_member', 'suggest_items: another household''s member is refused');
select * from finish();
rollback;
