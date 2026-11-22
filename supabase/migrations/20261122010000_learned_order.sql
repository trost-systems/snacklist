-- Job 352 (IO4): the learned walk order, server side. A household in order_mode 'learned' sorts
-- each store section by one sequence per (household, store, item key) in item_order_memory,
-- seeded from today's category walk order, moved by the walks of detected and manual trips
-- (trip_sessions.walks, job 351's F8 trade with its shuffle gate) and by manual places. Every
-- other household keeps the category order, server side included.
--
-- Lock order: the advisory lock 'item_order:' || household, then items rows, then
-- item_order_memory rows. The items trigger only reads memory or inserts a missing row.

alter table public.households
  add column order_mode text not null default 'categories' check (order_mode in ('categories', 'learned'));

alter table public.trip_sessions add column walks jsonb not null default '[]';
alter table public.trip_sessions add column removed_at timestamptz;

create table public.item_order_memory (
  household_id uuid not null references public.households (id) on delete cascade,
  -- Null is "No store": only manual places move it.
  store_id uuid,
  item_key text not null,
  position double precision not null,
  seed_position double precision not null,
  source text not null check (source in ('learned', 'manual')),
  manual_position double precision,
  manual_at timestamptz,
  -- Walks in a row that ordered a manual key against its place; the third releases it.
  contradictions integer not null default 0,
  updated_at timestamptz not null default now(),
  unique nulls not distinct (household_id, store_id, item_key),
  foreign key (store_id, household_id) references public.stores (id, household_id) on delete cascade
);
alter table public.item_order_memory enable row level security;
revoke all on public.item_order_memory from public, anon, authenticated;
-- No grant: the app never reads it, and manual_at and updated_at tell when someone placed an item
-- or a trip ended. The policy only says whose row it would be.
create policy item_order_memory_member on public.item_order_memory for select to authenticated
  using (public.is_household_member(household_id));

comment on table public.item_order_memory is
  'Job 352: the learned walk order of a household, one position per store (null: no store) and item key. Written by definer functions only.';

-- The key an item's place is remembered under.
create function public.item_order_key(p_canonical text, p_name text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(p_canonical, public.item_key(p_name));
$$;

-- 0-based rank of p_category in the walking order of p_store, as the app's walkingOrder has it:
-- the store's layout rows by sort_order, then the other categories in route order. No store
-- (null) walks route order.
create function public.category_walk_rank(p_household uuid, p_store uuid, p_category uuid)
returns integer
language sql stable set search_path = '' as $$
  select r from (
    select c.id, (row_number() over (
      order by o.sort_order is null, o.sort_order, c.sort_order, c.id) - 1)::integer as r
    from public.categories c
    left join public.store_category_order o on o.store_id = p_store and o.category_id = c.id
    where c.household_id = p_household
  ) w
  where w.id = p_category;
$$;

-- Where a key the store has no memory of starts: the end of its category's block in seed space.
create function public.item_order_prior(p_household uuid, p_store uuid, p_category uuid)
returns double precision
language sql stable set search_path = '' as $$
  with b as (
    select coalesce(public.category_walk_rank(p_household, p_store, p_category), 0)::double precision * 1e6 as low
  )
  select coalesce(
    (select max(m.seed_position) from public.item_order_memory m
     where m.household_id = p_household and m.store_id is not distinct from p_store
       and m.seed_position >= b.low and m.seed_position < b.low + 1e6),
    b.low) + 1
  from b;
$$;

-- The remembered position of (p_store, p_key); a key the store has none of gets its prior.
create function public.item_order_place(p_household uuid, p_store uuid, p_key text, p_category uuid)
returns double precision
language plpgsql security definer set search_path = '' as $$
declare
  v_position double precision;
begin
  select m.position into v_position from public.item_order_memory m
  where m.household_id = p_household and m.store_id is not distinct from p_store and m.item_key = p_key;
  if found then
    return v_position;
  end if;
  v_position := public.item_order_prior(p_household, p_store, p_category);
  insert into public.item_order_memory as m (household_id, store_id, item_key, position, seed_position, source)
  values (p_household, p_store, p_key, v_position, v_position, 'learned')
  on conflict (household_id, store_id, item_key) do nothing;
  if not found then
    select m.position into v_position from public.item_order_memory m
    where m.household_id = p_household and m.store_id is not distinct from p_store and m.item_key = p_key;
  end if;
  return v_position;
end $$;

-- A manual place of p_key in p_store at p_position, and the sort_key of its items there. The
-- same place again changes nothing, so manual_at keeps the first one's moment.
create function public.item_order_remember(
  p_household uuid, p_store uuid, p_key text, p_category uuid, p_position double precision
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform from public.items i
  where i.household_id = p_household and i.store_id is not distinct from p_store
    and public.item_order_key(i.canonical_key, i.name) = p_key
  order by i.id
  for update;
  insert into public.item_order_memory as m
    (household_id, store_id, item_key, position, seed_position, source, manual_position, manual_at)
  values (p_household, p_store, p_key, p_position,
          public.item_order_prior(p_household, p_store, p_category), 'manual', p_position, now())
  on conflict (household_id, store_id, item_key) do update
    set position = excluded.position, source = 'manual', manual_position = excluded.position,
        manual_at = excluded.manual_at, contradictions = 0, updated_at = now()
    where (m.position, m.source, m.manual_position, m.contradictions)
      is distinct from (excluded.position, 'manual', excluded.position, 0);
  update public.items i set sort_key = p_position
  where i.household_id = p_household and i.store_id is not distinct from p_store
    and public.item_order_key(i.canonical_key, i.name) = p_key
    and i.sort_key is distinct from p_position;
end $$;

-- Recomputes the store's order from scratch: every row back to its seed, then in time order every
-- walk of the store in trip_sessions.walks (sessions not removed) and every manual place. Then the
-- sort_key of the store's items, open and bought, follows. Walks never teach "No store" (null).
--
-- A walk is job 351's trade (docs/research/351-trip-detection/sim/learn.ts, F8): its keys take the
-- positions they already hold, sorted, in the order the walk ticked them (a step of tied keys
-- shares its slots' mean), and move halfway there. Keys of different steps that land on one
-- position (two swapped keys both land on their midpoint, and every later walk would keep them
-- tied) are spread in walk order by a tiny offset, so the latest walk decides. After 3 taught
-- walks, one whose pairs agree with the current order less than 60 % of the time is a shuffle and
-- teaches nothing. A manual key
-- holds its place; a walk that orders it against its place counts a contradiction, one that agrees
-- resets the count, and the third in a row releases it to the trade.
create function public.replay_store_order(p_household uuid, p_store uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_keys text[];
  v_pos double precision[];
  v_manual boolean[];
  v_contra integer[];
  v_event record;
  v_taught integer := 0;
  -- One walk: its keys in tick order (as indexes into v_keys) and their step numbers.
  v_at integer[];
  v_step integer[];
  v_steps integer;
  v_step_json jsonb;
  v_key text;
  v_i integer;
  v_category uuid;
  v_pairs integer;
  v_same integer;
  v_against integer;
  v_trade integer[];
  v_trade_step integer[];
  v_slots double precision[];
  v_target double precision[];
  -- The walk's traded keys by their new position, and their steps.
  v_order integer[];
  v_order_step integer[];
  v_base double precision;
  v_off double precision;
  v_sum double precision;
  v_mean double precision;
  v_from integer;
  v_to integer;
  v_prev text := current_setting('family_groceries.sort_key', true);
begin
  perform pg_advisory_xact_lock(hashtextextended('item_order:' || p_household::text, 0));
  perform from public.items i
  where i.household_id = p_household and i.store_id is not distinct from p_store
  order by i.id
  for update;

  select coalesce(array_agg(m.item_key order by m.item_key), '{}'),
         coalesce(array_agg(m.seed_position order by m.item_key), '{}')
  into v_keys, v_pos
  from public.item_order_memory m
  where m.household_id = p_household and m.store_id is not distinct from p_store;
  v_manual := array_fill(false, array[cardinality(v_keys)]);
  v_contra := array_fill(0, array[cardinality(v_keys)]);

  for v_event in
    select e.kind, e.steps, e.key, e.position
    from (
      select 0 as kind, (w.walk ->> 'at')::timestamptz as at, s.id::text as tie, w.n,
             w.walk -> 'steps' as steps, null::text as key, null::double precision as position
      from public.trip_sessions s
      cross join lateral jsonb_array_elements(s.walks) with ordinality as w (walk, n)
      where p_store is not null and s.household_id = p_household and s.removed_at is null
        and w.walk ->> 'store_id' = p_store::text
      union all
      select 1, m.manual_at, m.item_key, 0, null, m.item_key, m.manual_position
      from public.item_order_memory m
      where m.household_id = p_household and m.store_id is not distinct from p_store
        and m.manual_at is not null
    ) e
    order by e.at, e.kind, e.tie, e.n
  loop
    if v_event.kind = 1 then
      v_i := array_position(v_keys, v_event.key);
      v_pos[v_i] := v_event.position;
      v_manual[v_i] := true;
      v_contra[v_i] := 0;
      continue;
    end if;

    v_at := '{}';
    v_step := '{}';
    v_steps := 0;
    for v_step_json in select x from jsonb_array_elements(v_event.steps) with ordinality as t (x, n) order by n loop
      v_from := cardinality(v_at);
      for v_key in select k from jsonb_array_elements_text(v_step_json) with ordinality as t (k, n) order by n loop
        v_i := array_position(v_keys, v_key);
        if v_i is null then
          select i.category_id into v_category from public.items i
          where i.household_id = p_household and public.item_order_key(i.canonical_key, i.name) = v_key
          order by i.store_id is not distinct from p_store desc, i.updated_at desc, i.id
          limit 1;
          if found then
            v_keys := v_keys || v_key;
            v_pos := v_pos || public.item_order_place(p_household, p_store, v_key, v_category);
            v_manual := v_manual || false;
            v_contra := v_contra || 0;
            v_i := cardinality(v_keys);
          end if;
        end if;
        if v_i is not null then
          if cardinality(v_at) = v_from then
            v_steps := v_steps + 1;
          end if;
          v_at := v_at || v_i;
          v_step := v_step || v_steps;
        end if;
      end loop;
    end loop;
    continue when v_steps < 2;

    v_pairs := 0;
    v_same := 0;
    for a in 1..cardinality(v_at) loop
      for b in a + 1..cardinality(v_at) loop
        if v_step[a] < v_step[b] then
          v_pairs := v_pairs + 1;
          if v_pos[v_at[a]] < v_pos[v_at[b]] then
            v_same := v_same + 1;
          end if;
        end if;
      end loop;
    end loop;
    continue when v_taught >= 3 and v_same::double precision / v_pairs::double precision < 0.6;
    v_taught := v_taught + 1;

    for v_i in select distinct x from unnest(v_at) x where v_manual[x] loop
      v_pairs := 0;
      v_against := 0;
      for a in 1..cardinality(v_at) loop
        continue when v_at[a] <> v_i;
        for b in 1..cardinality(v_at) loop
          continue when v_at[b] = v_i or v_step[b] = v_step[a];
          v_pairs := v_pairs + 1;
          if (v_step[a] < v_step[b]) is distinct from (v_pos[v_i] < v_pos[v_at[b]]) then
            v_against := v_against + 1;
          end if;
        end loop;
      end loop;
      if v_pairs > 0 and v_against = 0 then
        v_contra[v_i] := 0;
      elsif v_against > 0 then
        v_contra[v_i] := v_contra[v_i] + 1;
        if v_contra[v_i] >= 3 then
          v_manual[v_i] := false;
          v_contra[v_i] := 0;
        end if;
      end if;
    end loop;

    v_trade := '{}';
    v_trade_step := '{}';
    for a in 1..cardinality(v_at) loop
      if not v_manual[v_at[a]] then
        v_trade := v_trade || v_at[a];
        v_trade_step := v_trade_step || v_step[a];
      end if;
    end loop;
    continue when (select count(distinct x) from unnest(v_trade_step) x) < 2;

    select array_agg(v_pos[x] order by v_pos[x]) into v_slots from unnest(v_trade) x;
    v_target := array_fill(null::double precision, array[cardinality(v_keys)]);
    v_from := 1;
    while v_from <= cardinality(v_trade) loop
      v_to := v_from;
      while v_to < cardinality(v_trade) and v_trade_step[v_to + 1] = v_trade_step[v_from] loop
        v_to := v_to + 1;
      end loop;
      v_sum := 0;
      for v_j in v_from..v_to loop
        v_sum := v_sum + v_slots[v_j];
      end loop;
      v_mean := v_sum / (v_to - v_from + 1);
      for v_j in v_from..v_to loop
        v_target[v_trade[v_j]] := v_mean;
      end loop;
      v_from := v_to + 1;
    end loop;
    for v_j in 1..cardinality(v_keys) loop
      if v_target[v_j] is not null then
        v_pos[v_j] := v_pos[v_j] + 0.5::double precision * (v_target[v_j] - v_pos[v_j]);
      end if;
    end loop;

    select array_agg(t.k order by v_pos[t.k], t.s), array_agg(t.s order by v_pos[t.k], t.s)
    into v_order, v_order_step
    from (select u.k, min(u.s) as s from unnest(v_trade, v_trade_step) as u (k, s) group by u.k) t;
    v_from := 1;
    while v_from <= cardinality(v_order) loop
      v_to := v_from;
      while v_to < cardinality(v_order)
        and v_pos[v_order[v_to + 1]] - v_pos[v_order[v_to]]
          <= abs(v_pos[v_order[v_to]]) * 1e-14::double precision + 1e-12::double precision loop
        v_to := v_to + 1;
      end loop;
      if (select count(distinct x) from unnest(v_order_step[v_from:v_to]) x) > 1 then
        v_base := v_pos[v_order[v_from]];
        v_off := abs(v_base) * 1e-12::double precision + 1e-9::double precision;
        for v_j in v_from..v_to loop
          v_pos[v_order[v_j]] := v_base + v_off
            * (select count(distinct x) from unnest(v_order_step[v_from:v_to]) x where x < v_order_step[v_j]);
        end loop;
      end if;
      v_from := v_to + 1;
    end loop;
  end loop;

  update public.item_order_memory m
  set position = u.position,
      source = case when u.manual then 'manual' else 'learned' end,
      contradictions = u.contradictions,
      updated_at = now()
  from unnest(v_keys, v_pos, v_manual, v_contra) as u (key, position, manual, contradictions)
  where m.household_id = p_household and m.store_id is not distinct from p_store and m.item_key = u.key
    and (m.position, m.source, m.contradictions)
      is distinct from (u.position, case when u.manual then 'manual' else 'learned' end, u.contradictions);

  perform set_config('family_groceries.sort_key', 'keep', true);
  update public.items i set sort_key = m.position
  from public.item_order_memory m
  where i.household_id = p_household and i.store_id is not distinct from p_store
    and m.household_id = p_household and m.store_id is not distinct from p_store
    and m.item_key = public.item_order_key(i.canonical_key, i.name)
    and i.sort_key is distinct from m.position;
  perform set_config('family_groceries.sort_key', coalesce(v_prev, ''), true);
end $$;

-- Switches the household's order. To 'learned': every (store, key) of its items, open and bought,
-- gets its seed, the place it has in today's order: its category's rank in that store's walking
-- order times 1e6 plus its rank by (sort_key, created_at) in its (store, category) group. A key
-- with items in two groups takes an open item's seed. Then every store is replayed, which sets
-- each item's sort_key to its position. Returns the mode in force.
create function public.set_order_mode(p_household uuid, p_mode text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_mode text;
  v_store uuid;
begin
  if p_mode is null or p_mode not in ('categories', 'learned') then
    raise exception 'invalid_order_mode' using errcode = '22023';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  select h.order_mode into v_mode from public.households h where h.id = p_household;
  if v_mode = p_mode then
    return v_mode;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('item_order:' || p_household::text, 0));
  select h.order_mode into v_mode from public.households h where h.id = p_household;
  if v_mode = p_mode then
    return v_mode;
  end if;

  if p_mode = 'learned' then
    with walk as (
      select s.id as store_id, c.id as category_id,
             row_number() over (
               partition by s.id order by o.sort_order is null, o.sort_order, c.sort_order, c.id) - 1 as r
      from (select st.id from public.stores st where st.household_id = p_household
            union all select null::uuid) s
      cross join public.categories c
      left join public.store_category_order o on o.store_id = s.id and o.category_id = c.id
      where c.household_id = p_household
    ),
    ranked as (
      select i.store_id, public.item_order_key(i.canonical_key, i.name) as key, i.status,
             w.r::double precision * 1e6 + row_number() over (
               partition by i.store_id, i.category_id order by i.sort_key, i.created_at, i.id) as seed
      from public.items i
      join walk w on w.store_id is not distinct from i.store_id and w.category_id = i.category_id
      where i.household_id = p_household
    )
    insert into public.item_order_memory as m (household_id, store_id, item_key, position, seed_position, source)
    select p_household, r.store_id, r.key, r.seed, r.seed, 'learned'
    from (
      select x.store_id, x.key, coalesce(min(x.seed) filter (where x.status = 'active'), min(x.seed)) as seed
      from ranked x group by x.store_id, x.key
    ) r
    on conflict (household_id, store_id, item_key) do update set seed_position = excluded.seed_position
      where m.seed_position is distinct from excluded.seed_position;
  end if;

  update public.households h set order_mode = p_mode where h.id = p_household;
  if p_mode = 'learned' then
    -- Trip detection (20261122020000_trip_detection.sql) starts at the switch: ticks from before
    -- it are never detected.
    insert into public.trip_detection_state as st (household_id, detect_from) values (p_household, now())
    on conflict (household_id) do update set detect_from = excluded.detect_from;
    for v_store in
      select st.id from public.stores st where st.household_id = p_household
      union all select null::uuid
    loop
      perform public.replay_store_order(p_household, v_store);
    end loop;
  end if;
  return p_mode;
end $$;

-- Puts p_items (open items of p_store, null for no store) first in the store's order, in that
-- order, as manual places; the store's other open items keep their places after them.
create function public.set_store_order(p_household uuid, p_store uuid, p_items uuid[]) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_keys text[];
  v_categories uuid[];
  v_old double precision[];
  v_floor double precision;
  v_n integer;
  v_in_place boolean;
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if (select h.order_mode from public.households h where h.id = p_household) <> 'learned' then
    raise exception 'order_mode' using errcode = '55000';
  end if;
  if p_store is not null
     and not exists (select from public.stores s where s.id = p_store and s.household_id = p_household) then
    raise exception 'store_not_found' using errcode = 'P0002';
  end if;
  if p_items is null
     or cardinality(p_items) <> (select count(distinct x) from unnest(p_items) x)
     or exists (
       select from unnest(p_items) x
       where not exists (
         select from public.items i
         where i.id = x and i.household_id = p_household and i.store_id is not distinct from p_store
           and i.status = 'active')) then
    raise exception 'invalid_items' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('item_order:' || p_household::text, 0));

  select array_agg(k.key order by k.first), array_agg(k.category_id order by k.first),
         array_agg(k.sort_key order by k.first)
  into v_keys, v_categories, v_old
  from (
    select distinct on (public.item_order_key(i.canonical_key, i.name))
           public.item_order_key(i.canonical_key, i.name) as key, t.n as first, i.category_id, i.sort_key
    from unnest(p_items) with ordinality as t (id, n)
    join public.items i on i.id = t.id
    order by public.item_order_key(i.canonical_key, i.name), t.n
  ) k;
  v_n := coalesce(cardinality(v_keys), 0);
  if v_n = 0 then
    return;
  end if;
  select min(i.sort_key) into v_floor from public.items i
  where i.household_id = p_household and i.store_id is not distinct from p_store and i.status = 'active'
    and public.item_order_key(i.canonical_key, i.name) <> all (v_keys);
  v_in_place := (v_floor is null or v_old[v_n] < v_floor)
    and not exists (select from generate_series(1, v_n - 1) g where v_old[g] >= v_old[g + 1]);
  if v_floor is null then
    v_floor := (select max(x) from unnest(v_old) x) + 1024;
  end if;
  for v_i in 1..v_n loop
    perform public.item_order_remember(p_household, p_store, v_keys[v_i], v_categories[v_i],
      case when v_in_place then v_old[v_i] else v_floor - (v_n - v_i + 1) * 1024 end);
  end loop;
end $$;

-- items_before_write from 20261121120100_items_created_at_bounds.sql; a learned household takes
-- sort_key from item_order_memory on insert and on a store change (a category change alone keeps
-- the place).
create or replace function public.items_before_write() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_guess record;
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - '{added_by,bought_by}'::text[]) = (to_jsonb(old) - '{added_by,bought_by}'::text[])
     and (new.added_by, new.bought_by) is distinct from (old.added_by, old.bought_by)
     and (new.added_by is not distinct from old.added_by
          or (new.added_by is null
              and (not exists (select from auth.users u where u.id = old.added_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.added_by))))
     and (new.bought_by is not distinct from old.bought_by
          or (new.bought_by is null
              and (not exists (select from auth.users u where u.id = old.bought_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.bought_by))))
  then
    return new;
  end if;
  new.name := btrim(new.name);
  new.quantity := nullif(btrim(new.quantity), '');
  new.brand := nullif(btrim(new.brand), '');
  new.properties := nullif(btrim(new.properties), '');
  new.normalized_name := public.normalize_item_name(new.name);
  if tg_op = 'INSERT' or new.category_id is null then
    v_guess := public.classify_item_detail(new.household_id, new.name);
    new.canonical_key := v_guess.canonical_key;
    if new.category_id is null then
      new.category_id := v_guess.category_id;
      new.categorized_via := v_guess.via;
    elsif tg_op = 'INSERT' then
      new.categorized_via := case when new.category_id = v_guess.category_id then v_guess.via else 'picked' end;
    end if;
  elsif new.name is distinct from old.name then
    new.canonical_key := public.canonical_key(new.name);
  end if;
  if tg_op = 'INSERT' and new.store_id is null then
    new.store_id := case
      when current_setting('family_groceries.category_store', true) = 'on'
        then public.guess_store(new.household_id, new.name, new.brand, new.category_id, true)
      else public.suggest_store(new.household_id, new.name)
    end;
  end if;
  if (select h.order_mode from public.households h where h.id = new.household_id) = 'learned' then
    if tg_op = 'INSERT' or new.sort_key is null
       or (new.store_id is distinct from old.store_id
           and coalesce(current_setting('family_groceries.sort_key', true), '') <> 'keep') then
      new.sort_key := public.item_order_place(new.household_id, new.store_id,
        public.item_order_key(new.canonical_key, new.name), new.category_id);
    end if;
  elsif new.sort_key is null
     or (tg_op = 'UPDATE'
         and (new.store_id, new.category_id) is distinct from (old.store_id, old.category_id)
         and new.sort_key is not distinct from old.sort_key
         and coalesce(current_setting('family_groceries.sort_key', true), '') <> 'keep') then
    new.sort_key := coalesce(
      (select max(i.sort_key) from public.items i
       where i.household_id = new.household_id and i.category_id = new.category_id
         and i.store_id is not distinct from new.store_id and i.id <> new.id),
      0
    ) + 1024;
  end if;
  if tg_op = 'INSERT' and new.created_at not between '2000-01-01 00:00:00+00' and now() + interval '1 day' then
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    new.created_at := case when old.created_at between '2000-01-01 00:00:00+00' and now() + interval '1 day' then old.created_at else now() end;
    new.added_by := old.added_by;
    -- Strictly after the row's last write: the app keeps the newer of two echoes of a row, and a
    -- write whose transaction began before the last one committed (a replay in a long detection
    -- run, a tick that waited for the replay's row lock) would otherwise carry an older time.
    new.updated_at := greatest(now(), old.updated_at + interval '1 microsecond');
  end if;
  if new.status = 'bought' and (tg_op = 'INSERT' or old.status is distinct from 'bought') then
    new.bought_at := now();
    new.bought_by := auth.uid();
  elsif new.status = 'active' then
    new.bought_at := null;
    new.bought_by := null;
  end if;
  return new;
end $function$;

-- place_item from 20261025212052_item_details.sql. It runs as its owner now, so that a learned
-- household's place reaches item_order_memory; the items it reads are the ones RLS showed it
-- before (is_household_member), so a stranger still gets item_not_found. In a learned household
-- the anchor is an open item of the same store section (else anchor_in_other_store), the place is
-- the midpoint to the anchor's open neighbour on that edge (the anchor's key -+ 1024 at an end),
-- remembered as a manual place, and the category stays.
create or replace function public.place_item(p_item uuid, p_anchor uuid, p_edge text) returns public.items
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.items;
  v_anchor public.items;
  v_neighbour double precision;
  v_key double precision;
begin
  if p_edge is null or p_edge not in ('before', 'after') then
    raise exception 'invalid_edge' using errcode = '22023';
  end if;
  select * into v_item from public.items i where i.id = p_item and public.is_household_member(i.household_id);
  if not found then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  select * into v_anchor from public.items where id = p_anchor and household_id = v_item.household_id;
  if not found then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if v_anchor.id = v_item.id or v_anchor.status <> 'active' then
    raise exception 'invalid_anchor' using errcode = '22023';
  end if;

  if (select h.order_mode from public.households h where h.id = v_item.household_id) = 'learned' then
    if v_anchor.store_id is distinct from v_item.store_id then
      raise exception 'anchor_in_other_store' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('item_order:' || v_item.household_id::text, 0));
    -- Again under the lock: either may have moved, been ticked or deleted while it waited.
    select * into v_item from public.items where id = p_item and household_id = v_item.household_id;
    if not found then
      raise exception 'item_not_found' using errcode = 'P0002';
    end if;
    select * into v_anchor from public.items where id = p_anchor and household_id = v_item.household_id;
    if not found then
      raise exception 'item_not_found' using errcode = 'P0002';
    end if;
    if v_anchor.status <> 'active' then
      raise exception 'invalid_anchor' using errcode = '22023';
    end if;
    if v_anchor.store_id is distinct from v_item.store_id then
      raise exception 'anchor_in_other_store' using errcode = '22023';
    end if;
    -- The neighbour is the next other place: the anchor's twins (its key on another list) share
    -- its sort_key, and the item's own twins move with it.
    if p_edge = 'before' then
      select i.sort_key into v_neighbour from public.items i
      where i.household_id = v_anchor.household_id and i.store_id is not distinct from v_anchor.store_id
        and i.status = 'active' and i.sort_key < v_anchor.sort_key
        and public.item_order_key(i.canonical_key, i.name) <> public.item_order_key(v_item.canonical_key, v_item.name)
      order by i.sort_key desc
      limit 1;
    else
      select i.sort_key into v_neighbour from public.items i
      where i.household_id = v_anchor.household_id and i.store_id is not distinct from v_anchor.store_id
        and i.status = 'active' and i.sort_key > v_anchor.sort_key
        and public.item_order_key(i.canonical_key, i.name) <> public.item_order_key(v_item.canonical_key, v_item.name)
      order by i.sort_key
      limit 1;
    end if;
    v_key := case
      when not found then v_anchor.sort_key + case when p_edge = 'before' then -1024 else 1024 end
      else (v_anchor.sort_key + v_neighbour) / 2
    end;
    perform public.item_order_remember(v_item.household_id, v_item.store_id,
      public.item_order_key(v_item.canonical_key, v_item.name), v_item.category_id, v_key);
    select * into v_item from public.items where id = p_item;
    return v_item;
  end if;

  for v_round in 1..2 loop
    if p_edge = 'before' then
      select i.sort_key into v_neighbour from public.items i
      where i.household_id = v_anchor.household_id and i.category_id = v_anchor.category_id
        and i.store_id is not distinct from v_anchor.store_id and i.id <> p_item
        and (i.sort_key, i.created_at, i.id) < (v_anchor.sort_key, v_anchor.created_at, v_anchor.id)
      order by i.sort_key desc, i.created_at desc, i.id desc
      limit 1;
    else
      select i.sort_key into v_neighbour from public.items i
      where i.household_id = v_anchor.household_id and i.category_id = v_anchor.category_id
        and i.store_id is not distinct from v_anchor.store_id and i.id <> p_item
        and (i.sort_key, i.created_at, i.id) > (v_anchor.sort_key, v_anchor.created_at, v_anchor.id)
      order by i.sort_key, i.created_at, i.id
      limit 1;
    end if;
    if not found then
      v_key := v_anchor.sort_key + case when p_edge = 'before' then -1024 else 1024 end;
      exit;
    elsif abs(v_anchor.sort_key - v_neighbour) >= 0.001 then
      v_key := (v_anchor.sort_key + v_neighbour) / 2;
      exit;
    end if;
    update public.items i set sort_key = r.n * 1024
    from (
      select g.id, row_number() over (order by g.sort_key, g.created_at, g.id) as n
      from public.items g
      where g.household_id = v_anchor.household_id and g.category_id = v_anchor.category_id
        and g.store_id is not distinct from v_anchor.store_id and g.id <> p_item
    ) r
    where i.id = r.id and i.sort_key is distinct from r.n * 1024;
    select i.sort_key into v_anchor.sort_key from public.items i where i.id = p_anchor;
  end loop;

  -- The new key may equal the old one by chance; the trigger must not treat that as a plain edit.
  perform set_config('family_groceries.sort_key', 'keep', true);
  update public.items set store_id = v_anchor.store_id, category_id = v_anchor.category_id, sort_key = v_key
  where id = p_item
  returning * into v_item;
  perform set_config('family_groceries.sort_key', '', true);
  return v_item;
end $$;

revoke execute on function
  public.item_order_key(text, text),
  public.category_walk_rank(uuid, uuid, uuid),
  public.item_order_prior(uuid, uuid, uuid),
  public.item_order_place(uuid, uuid, text, uuid),
  public.item_order_remember(uuid, uuid, text, uuid, double precision),
  public.replay_store_order(uuid, uuid)
from public, anon, authenticated;
revoke execute on function
  public.set_order_mode(uuid, text),
  public.set_store_order(uuid, uuid, uuid[])
from public, anon;
grant execute on function
  public.set_order_mode(uuid, text),
  public.set_store_order(uuid, uuid, uuid[])
to authenticated;
