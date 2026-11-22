-- Job 352 (worker B): shopping trips detected from plain ticks. The rule is job 351's final rule
-- (docs/research/351-trip-detection/README.md on branch job/351-trip-detection-heuristics). Its
-- reference code is supabase/functions/_shared/trip_sim/detect.ts (finalRule), and
-- supabase/functions/_shared/trip_detection_integration_test.ts checks that detect_trips finds
-- the same trips and walks on the same ticks. Detection runs only in households whose order_mode
-- is 'learned' (20261122010000_learned_order.sql), from pg_cron every 5 minutes.
--
-- Legal (review of 2026-11-21): N-319 a person's switch takes their ticks out of detection and
-- deletes their unedited detected trips; N-320 others see someone's detected trips only after that
-- person has seen the first-trip card; N-321 no clock times of other members' detected trips and
-- no direct read of item_events, and no detected trip or walk at a pharmacy (GL-2).

-- Ticks ------------------------------------------------------------------------------------------

-- What a tick needs for detection: the tap time, where it came from, the item's store at the tick
-- and how many open items that store had left on the list after it (T3a: "the last open items of
-- its store"; nothing else keeps that count once more items are added).
alter table public.item_events
  add column client_at timestamptz,
  add column source text,
  add column store_id uuid,
  add column store_open_after integer;
alter table public.item_events
  add constraint item_events_source check (source in ('app', 'voice', 'agent')) not valid;
alter table public.item_events validate constraint item_events_source;
comment on column public.item_events.client_at is
  'Job 352: a tick''s tap time on the device (set_item_status), kept only within 7 days before to 24 hours after the commit, else null.';
comment on column public.item_events.source is
  'Job 352: where a tick came from (app, voice, agent); null for other events. Only app ticks are detected.';
comment on column public.item_events.store_id is
  'Job 352: the item''s store at the event. No foreign key: history outlives deleted stores.';
comment on column public.item_events.store_open_after is
  'Job 352: open items of the same list and store after a tick.';

-- Not on profiles: members read each other's profiles, and whether and since when someone
-- switched detection off is theirs. No row: not detected (N-319: a person is detected only once
-- their app has shown the switch; my_trip_detection, which that app calls, adds the row).
create table public.trip_detection_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  detect_ticks_from timestamptz,
  detected_card_at timestamptz
);
alter table public.trip_detection_settings enable row level security;
revoke all on public.trip_detection_settings from public, anon, authenticated;
comment on table public.trip_detection_settings is
  'Job 352: a person''s trip detection switch (detect_ticks_from; null: off, and ticks before it never count; no row: never shown the switch, not detected) and when they saw the first detected trip card. Read and written through set_trip_detection, my_trip_detection and seen_detected_trip_card only.';

-- Whether [p_user]'s ticks count for detection now.
create function public.trip_detection_on(p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select from public.trip_detection_settings p where p.user_id = p_user and p.detect_ticks_from is not null)
$$;
revoke execute on function public.trip_detection_on(uuid) from public, anon, authenticated;

-- Members no longer read the table: suggest_items (below) reads it for them. A member could read
-- every member's ticks to the microsecond through the API (job 351, Legal notes).
revoke select on public.item_events from authenticated;

create or replace function public.items_log_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.items := case when tg_op = 'DELETE' then old else new end;
  v_action text;
  v_client_at timestamptz;
  v_source text;
  v_open integer;
begin
  -- A household or list delete cascades to its items; they leave no "deleted" event each.
  if tg_op = 'DELETE' and (
    not exists (select 1 from public.households where id = old.household_id)
    or not exists (select 1 from public.lists where id = old.list_id)
  ) then
    return null;
  end if;
  if tg_op = 'UPDATE'
     and (new.name, new.quantity, new.brand, new.properties, new.category_id, new.store_id, new.status,
          new.list_id)
         is not distinct from
         (old.name, old.quantity, old.brand, old.properties, old.category_id, old.store_id, old.status,
          old.list_id) then
    return null;
  end if;
  v_action := case
    when tg_op = 'INSERT' then 'added'
    when tg_op = 'DELETE' then 'deleted'
    when new.status = 'bought' and old.status = 'active' then 'bought'
    when new.status = 'active' and old.status = 'bought' then 'restored'
    else 'edited'
  end;
  if v_action in ('bought', 'restored') then
    -- An app build without set_item_status ticks through a plain update: its ticks are app
    -- ticks with commit times only. Edge functions name their source. An app connected over
    -- OAuth (an MCP client calling PostgREST itself, set_item_status included) is an agent.
    v_source := case when auth.jwt() ->> 'client_id' is not null then 'agent'
                     else coalesce(nullif(current_setting('fg.tick_source', true), ''),
                                   case when auth.uid() is not null then 'app' end) end;
    if v_source not in ('app', 'voice', 'agent') then
      v_source := null;
    end if;
    if nullif(current_setting('fg.client_at', true), '') is not null then
      begin
        v_client_at := current_setting('fg.client_at', true)::timestamptz;
      exception when others then
        v_client_at := null;
      end;
    end if;
    -- The tap time is kept only for detection, so only for the app ticks of people who have it
    -- on (N-319). The source stays: it is no time, and tells a Siri or agent tick from the
    -- person's own.
    if not (v_client_at between now() - interval '7 days' and now() + interval '24 hours')
       or v_source is distinct from 'app' or not public.trip_detection_on(auth.uid()) then
      v_client_at := null;
    end if;
    select count(*)::int into v_open from public.items i
    where i.household_id = v_row.household_id and i.status = 'active'
      and i.list_id is not distinct from v_row.list_id and i.store_id is not distinct from v_row.store_id;
  end if;
  insert into public.item_events (household_id, item_id, action, item_name, category_id, list_id,
    client_at, source, store_id, store_open_after)
  values (v_row.household_id, v_row.id, v_action, v_row.name, v_row.category_id, v_row.list_id,
    v_client_at, v_source, v_row.store_id, v_open);
  return null;
end $$;

-- The app's tick and untick: [p_status] 'bought' or 'active', with the tap time [p_ticked_at]
-- (SetStatus.at). Runs as the caller, so the items policies decide. The same call twice changes
-- nothing. Errors: not_authenticated, missing_argument, invalid_status, item_not_found.
create function public.set_item_status(p_item uuid, p_status text, p_ticked_at timestamptz default null)
returns public.items
language plpgsql security invoker set search_path = '' as $$
declare
  v_row public.items;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_item is null or p_status is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if p_status not in ('active', 'bought') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  perform set_config('fg.tick_source', 'app', true);
  perform set_config('fg.client_at', coalesce(p_ticked_at::text, ''), true);
  update public.items i set status = p_status where i.id = p_item returning * into v_row;
  perform set_config('fg.tick_source', '', true);
  perform set_config('fg.client_at', '', true);
  if v_row.id is null then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  return v_row;
end $$;
revoke execute on function public.set_item_status(uuid, text, timestamptz) from public, anon;
grant execute on function public.set_item_status(uuid, text, timestamptz) to authenticated;

-- As in 20261105075541_hc_suggest_items_names.sql, but as the definer: members no longer read
-- item_events. A definer bypasses the items policy too, so membership is checked first. An API
-- caller (role authenticated or anon) gets now() whatever p_now says, and last_used to the day
-- (Berlin): moving p_now to just before each answer changes would walk back every member's tick
-- times to the microsecond (N-321). Tests run as postgres to set the clock.
create or replace function public.suggest_items(
  p_household uuid,
  p_prefix text default '',
  p_limit int default 5,
  p_now timestamptz default now()
) returns table (name text, quantity text, uses int, last_used timestamptz, due boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_now timestamptz := case when current_setting('role', true) in ('authenticated', 'anon') then now()
                            else coalesce(p_now, now()) end;
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  return query
  with events as materialized (
    select e.id, e.item_id, e.action, e.item_name, e.created_at
    from public.item_events e
    where e.household_id = p_household
      -- 'restored' is read only to drop ticks undone within 10 minutes.
      and e.action in ('added', 'bought', 'restored')
      and e.created_at <= v_now
      and e.created_at > v_now - interval '1 year'
  ),
  item_rows as materialized (
    select i.id, i.status, i.quantity, coalesce(i.bought_at, i.updated_at) as at, i.name
    from public.items i
    where i.household_id = p_household
      and (i.status = 'active' or i.updated_at > v_now - interval '1 year')
  ),
  names as materialized (
    select n.name, public.item_name_key(n.name) as key
    from (select ev.item_name as name from events ev union select r.name from item_rows r) n
  ),
  history as (
    select ev.*, n.key from events ev join names n on n.name = ev.item_name
  ),
  rows as materialized (
    select r.id, r.status, r.quantity, r.at, n.key from item_rows r join names n on n.name = r.name
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
      sum(power(0.5, extract(epoch from v_now - d.last_at) / 86400 / 30)) as score,
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
    date_trunc('day', r.last_used, 'Europe/Berlin'),
    r.purchases >= 2
      and extract(epoch from v_now - r.last_bought_at) / 86400 between r.gap_days and 4 * r.gap_days
  from ranked r
  order by r.prefix_rank, r.score desc, r.last_used desc, r.name
  limit least(greatest(p_limit, 0), 200);
end $$;

-- Detected trips -----------------------------------------------------------------------------------

alter table public.trip_sessions drop constraint trip_sessions_source_check;
alter table public.trip_sessions add constraint trip_sessions_source_check
  check (source in ('ask', 'manual', 'detected')) not valid;
alter table public.trip_sessions validate constraint trip_sessions_source_check;
alter table public.trip_sessions
  add column store_id uuid,
  add column tick_ids bigint[],
  add column detected_by uuid[],
  add column frozen_at timestamptz,
  add column walked boolean;
comment on column public.trip_sessions.store_id is
  'Job 352: a detected trip''s store (no foreign key, like trips'' store name it outlives the store).';
comment on column public.trip_sessions.tick_ids is
  'Job 352: the item_events a detected trip was built from. A frozen trip keeps them out of detection.';
comment on column public.trip_sessions.detected_by is
  'Job 352: everyone whose ticks are in a detected trip; a person leaves it with the household or the account.';
comment on column public.trip_sessions.frozen_at is
  'Job 352: when a member edited or removed a detected trip; detection no longer replaces it.';
comment on column public.trip_sessions.walked is
  'Job 352: whether a detected trip came from a walk (false: only a burst of ticks, no duration).';
-- squawk-ignore require-concurrent-index-creation -- trip_sessions holds a few hundred rows; a migration runs in a transaction
create index trip_sessions_detected on public.trip_sessions (household_id, ended_at)
  where source = 'detected';

-- Not on households: members read that row and it is in the realtime publication, so every run
-- would reload each member's catalog and show when someone switched off.
create table public.trip_detection_state (
  household_id uuid primary key references public.households (id) on delete cascade,
  -- The newest app tick (commit time) the last run saw.
  detected_through timestamptz,
  -- Ticks committed before it are never detected: the switch to the learned order.
  detect_from timestamptz
);
alter table public.trip_detection_state enable row level security;
revoke all on public.trip_detection_state from public, anon, authenticated;
-- No grant: the policy only says whose row it would be.
create policy trip_detection_state_member on public.trip_detection_state for select to authenticated
  using (public.is_household_member(household_id));
comment on table public.trip_detection_state is
  'Job 352: where trip detection stands per household. Written by detect_trips, set_trip_detection and set_order_mode; no client access.';

-- TD-Q5 (Peter): „Nein, nur abgehakt" on the trip question, or closing it, means that run of ticks
-- is no shop: detection leaves it out (detect_undeclined). One row per answered tick.
create table public.shop_declines (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The person's tick the question asked about (item_events.id).
  tick_id bigint not null,
  declined_at timestamptz not null default now(),
  -- The tap time on the device, within the bounds items_log_event keeps.
  client_at timestamptz,
  unique (user_id, tick_id)
);
create index shop_declines_household on public.shop_declines (household_id);
create index shop_declines_declined_at on public.shop_declines (declined_at);
alter table public.shop_declines enable row level security;
revoke all on public.shop_declines from public, anon, authenticated;
-- No grant: the policy only says whose row it would be.
create policy shop_declines_member on public.shop_declines for select to authenticated
  using (public.is_household_member(household_id));
comment on table public.shop_declines is
  'Job 352, TD-Q5: the ticks whose trip question a person answered „Nein, nur abgehakt" (or closed). detect_trips leaves out their run. Written by decline_shop, deleted after 15 days (purge_shop_declines), when the person switches detection off, leaves the household or deletes the account; no client access.';

-- The rule ---------------------------------------------------------------------------------------
-- Each function below is the function of the same name in trip_sim/detect.ts, step for step, so a
-- reader can hold one against the other. Ticks come in sorted by (t, id).

-- t: the time detection believes (corrected tap time, else commit time); key: the item's
-- canonical key; kind: 'bought' or 'restored'; open_after: store_open_after.
create type public.detect_tick as (
  id bigint, item_id uuid, key text, actor uuid, kind text, t timestamptz, store_id uuid, open_after integer
);
create type public.detect_block as (store_id uuid, xs public.detect_tick[]);
-- walk: a walk (H1, or T3a's small store); else a burst. steps: the keys of each step, in order.
create type public.detect_piece as (store_id uuid, walk boolean, xs public.detect_tick[], steps jsonb);
create type public.detect_trip as (store_id uuid, actors uuid[], xs public.detect_tick[], walked boolean);

-- T5a: a bought tick the same person restored within ten minutes counts as never made, and so
-- does the restore.
create function public.detect_kept(p_ticks public.detect_tick[]) returns public.detect_tick[]
language plpgsql immutable set search_path = '' as $$
declare
  v_dropped bigint[] := '{}'::bigint[];
  v_x public.detect_tick;
  v_y public.detect_tick;
begin
  for i in 1 .. coalesce(array_length(p_ticks, 1), 0) loop
    v_x := p_ticks[i];
    continue when v_x.kind <> 'restored';
    for j in reverse i - 1 .. 1 loop
      v_y := p_ticks[j];
      exit when v_x.t - v_y.t > interval '10 minutes';
      if v_y.kind = 'bought' and v_y.item_id = v_x.item_id and v_y.actor = v_x.actor and not v_y.id = any(v_dropped) then
        v_dropped := v_dropped || v_y.id;
        exit;
      end if;
    end loop;
  end loop;
  return array(
    select row(x.*)::public.detect_tick from unnest(p_ticks) x
    where x.kind = 'bought' and not x.id = any(v_dropped)
    order by x.t, x.id);
end $$;
revoke execute on function public.detect_kept(public.detect_tick[]) from public, anon, authenticated;

-- TD-Q5: [p_ticks] without declined runs. A tick in [p_declined] and the same person's ticks after
-- it, up to their first gap of more than 30 minutes (TD-Q2's same trip), are no shop.
create function public.detect_undeclined(p_ticks public.detect_tick[], p_declined bigint[])
returns public.detect_tick[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(row(d.id, d.item_id, d.key, d.actor, d.kind, d.t, d.store_id, d.open_after)::public.detect_tick
    order by d.t, d.id), '{}')
  from (
    select s.*, bool_or(s.id = any(p_declined)) over (partition by s.actor, s.span order by s.t, s.id) as declined
    from (
      select g.*, count(*) filter (where g.gap) over (partition by g.actor order by g.t, g.id) as span
      from (
        select x.*, x.t - lag(x.t) over (partition by x.actor order by x.t, x.id) > interval '30 minutes' as gap
        from unnest(p_ticks) x
      ) g
    ) s
  ) d
  where not d.declined
$$;
revoke execute on function public.detect_undeclined(public.detect_tick[], bigint[]) from public, anon, authenticated;

-- The store most of [p_xs] are tagged with (a tie: the one ticked first), null when none is, and
-- its share of the tagged ticks.
create function public.detect_majority(p_xs public.detect_tick[], out store_id uuid, out share double precision)
language sql immutable set search_path = '' as $$
  select (array_agg(c.store_id order by c.n desc, c.first))[1],
    coalesce(max(c.n)::double precision / nullif(sum(c.n), 0), 0)
  from (
    select x.store_id, count(*) as n, min(x.ordinality) as first
    from unnest(p_xs) with ordinality as x
    where x.store_id is not null
    group by x.store_id
  ) c
$$;
revoke execute on function public.detect_majority(public.detect_tick[]) from public, anon, authenticated;

-- Block [p_from]'s ticks join block [p_into] (byStore's join).
create function public.detect_join(p_blocks public.detect_block[], p_from integer, p_into integer)
returns public.detect_block[]
language plpgsql immutable set search_path = '' as $$
declare
  v_into public.detect_block := p_blocks[p_into];
  v_from public.detect_block := p_blocks[p_from];
begin
  v_into.xs := array(
    select row(x.*)::public.detect_tick from unnest(v_into.xs || v_from.xs) x order by x.t, x.id);
  p_blocks[p_into] := v_into;
  return p_blocks[1 : p_from - 1] || p_blocks[p_from + 1 :];
end $$;
revoke execute on function public.detect_join(public.detect_block[], integer, integer) from public, anon, authenticated;

-- byStore: splits one run where the person moved to another store. Blocks of one store in a row;
-- a block between two blocks of one store belongs to that store; a lone tick at either end joins
-- its neighbour unless it finished its store's open items; a store change needs 2 minutes.
create function public.detect_by_store(p_run public.detect_tick[]) returns public.detect_block[]
language plpgsql immutable set search_path = '' as $$
declare
  v_blocks public.detect_block[] := '{}'::public.detect_block[];
  v_last public.detect_block;
  v_block public.detect_block;
  v_n integer;
  v_changed boolean;
  v_x public.detect_tick;
  i integer;
begin
  foreach v_x in array p_run loop
    v_n := coalesce(array_length(v_blocks, 1), 0);
    v_last := case when v_n > 0 then v_blocks[v_n] end;
    if v_n > 0 and (v_x.store_id is null or v_x.store_id = v_last.store_id or v_last.store_id is null) then
      v_last.xs := v_last.xs || v_x;
      if v_last.store_id is null then
        v_last.store_id := v_x.store_id;
      end if;
      v_blocks[v_n] := v_last;
    else
      v_blocks := v_blocks || row(v_x.store_id, array[v_x])::public.detect_block;
    end if;
  end loop;
  loop
    v_changed := false;
    v_n := coalesce(array_length(v_blocks, 1), 0);
    for k in 1 .. v_n loop
      v_block := v_blocks[k];
      if k > 1 and k < v_n and (v_blocks[k - 1]).store_id is not distinct from (v_blocks[k + 1]).store_id then
        v_blocks := public.detect_join(v_blocks, k, k - 1);
        v_blocks := public.detect_join(v_blocks, k, k - 1);
        v_changed := true;
        exit;
      end if;
      if (k = 1 or k = v_n) and v_n > 1 and array_length(v_block.xs, 1) = 1
         and (v_block.xs[1]).open_after is distinct from 0 then
        v_blocks := public.detect_join(v_blocks, k, case when k = 1 then k + 1 else k - 1 end);
        v_changed := true;
        exit;
      end if;
      if k > 1 and (v_blocks[k - 1]).store_id is not distinct from v_block.store_id then
        v_blocks := public.detect_join(v_blocks, k, k - 1);
        v_changed := true;
        exit;
      end if;
    end loop;
    exit when not v_changed;
  end loop;
  i := 2;
  while i <= coalesce(array_length(v_blocks, 1), 0) loop
    v_last := v_blocks[i - 1];
    v_block := v_blocks[i];
    if (v_block.xs[1]).t - (v_last.xs[array_length(v_last.xs, 1)]).t < interval '2 minutes' then
      v_blocks := public.detect_join(v_blocks, i, i - 1);
    else
      i := i + 1;
    end if;
  end loop;
  return v_blocks;
end $$;
revoke execute on function public.detect_by_store(public.detect_tick[]) from public, anon, authenticated;

-- One piece of a run: a walk (3 steps of ticks under 6 s apart with a median of at least 20 s
-- between steps, H1 and F3; or T3a: 1 or 2 ticks of one store within 5 minutes that leave it no
-- open item) or a burst.
create function public.detect_piece_of(p_xs public.detect_tick[])
returns public.detect_piece
language plpgsql stable set search_path = '' as $$
declare
  v_store uuid;
  v_steps jsonb := '[]'::jsonb;
  v_step jsonb;
  v_gaps interval[] := '{}'::interval[];
  v_prev timestamptz;
  v_first public.detect_tick := p_xs[1];
  v_last public.detect_tick := p_xs[array_length(p_xs, 1)];
  v_small boolean;
  v_walked boolean;
  v_x public.detect_tick;
begin
  v_store := (public.detect_majority(p_xs)).store_id;
  foreach v_x in array p_xs loop
    if v_step is not null and v_x.t - v_prev < interval '6 seconds' then
      v_step := v_step || to_jsonb(v_x.key);
    else
      if v_step is not null then
        v_steps := v_steps || jsonb_build_array(v_step);
        v_gaps := v_gaps || (v_x.t - v_prev);
      end if;
      v_step := jsonb_build_array(v_x.key);
    end if;
    v_prev := v_x.t;
  end loop;
  v_steps := v_steps || jsonb_build_array(v_step);
  v_small := array_length(p_xs, 1) < 3 and v_store is not null
    and v_last.t - v_first.t <= interval '5 minutes' and v_last.open_after = 0
    and not exists (select from unnest(p_xs) y where y.store_id is distinct from v_store);
  v_walked := jsonb_array_length(v_steps) >= 3 and (
    select g from unnest(v_gaps) g order by g offset array_length(v_gaps, 1) / 2 limit 1
  ) >= interval '20 seconds';
  return row(v_store, coalesce(v_walked or v_small, false), p_xs, v_steps)::public.detect_piece;
end $$;
revoke execute on function public.detect_piece_of(public.detect_tick[]) from public, anon, authenticated;

-- finalRule's first half: per person (in the order they first ticked), runs of ticks at most 10
-- minutes apart (T1a), split by store, as pieces.
create function public.detect_pieces(p_ticks public.detect_tick[])
returns public.detect_piece[]
language plpgsql stable set search_path = '' as $$
declare
  v_pieces public.detect_piece[] := '{}'::public.detect_piece[];
  v_run public.detect_tick[];
  v_own public.detect_tick[];
  v_actor uuid;
  v_block public.detect_block;
  v_x public.detect_tick;
begin
  for v_actor in
    select a.actor from unnest(p_ticks) with ordinality as a group by a.actor order by min(a.ordinality)
  loop
    v_own := array(select p_ticks[i] from generate_subscripts(p_ticks, 1) i
                   where (p_ticks[i]).actor = v_actor order by i);
    v_run := '{}';
    for i in 1 .. array_length(v_own, 1) + 1 loop
      v_x := case when i <= array_length(v_own, 1) then v_own[i] end;
      if v_x.id is null or (array_length(v_run, 1) > 0 and v_x.t - (v_run[array_length(v_run, 1)]).t > interval '10 minutes') then
        foreach v_block in array public.detect_by_store(v_run) loop
          v_pieces := v_pieces || public.detect_piece_of(v_block.xs);
        end loop;
        v_run := '{}';
      end if;
      if v_x.id is not null then
        v_run := v_run || v_x;
      end if;
    end loop;
  end loop;
  return v_pieces;
end $$;
revoke execute on function public.detect_pieces(public.detect_tick[]) from public, anon, authenticated;

-- finalRule's second half: a person's next piece at the same store (a burst: or none) within 30
-- minutes of the trip's last tick continues that trip, walk or burst, in either order (TD-Q2, a
-- pause: F5); a trip with no walk counts from 5 ticks (TD-Q1, F6); trips of different people at
-- one store that overlap (plus 10 minutes) are one (T2a). Each trip carries its walks (store,
-- start, steps): the walks with a store and 2 steps or more. Bursts never teach.
create function public.detect_rule(p_ticks public.detect_tick[])
returns table (store_id uuid, actors uuid[], xs public.detect_tick[], walked boolean, walks jsonb)
language plpgsql stable set search_path = '' as $$
#variable_conflict use_column
declare
  v_pieces public.detect_piece[] := public.detect_pieces(p_ticks);
  v_trips public.detect_trip[] := '{}'::public.detect_trip[];
  v_out public.detect_trip[] := '{}'::public.detect_trip[];
  v_walks jsonb := '[]'::jsonb;
  v_piece public.detect_piece;
  v_trip public.detect_trip;
  v_other public.detect_trip;
  v_start timestamptz;
  v_end timestamptz;
  v_hit integer;
begin
  foreach v_piece in array v_pieces loop
    if v_piece.walk and v_piece.store_id is not null and jsonb_array_length(v_piece.steps) >= 2 then
      v_walks := v_walks || jsonb_build_array(jsonb_build_object(
        'first', (v_piece.xs[1]).id, 'store_id', v_piece.store_id, 'at', (v_piece.xs[1]).t,
        'steps', v_piece.steps));
    end if;
  end loop;
  foreach v_piece in array array(
    select v_pieces[i] from generate_subscripts(v_pieces, 1) i order by ((v_pieces[i]).xs[1]).t, i)
  loop
    v_start := (v_piece.xs[1]).t;
    v_hit := null;
    for k in 1 .. coalesce(array_length(v_trips, 1), 0) loop
      v_trip := v_trips[k];
      if (v_trip.xs[1]).actor = (v_piece.xs[1]).actor
         and (v_trip.store_id is not distinct from v_piece.store_id
              or (not v_piece.walk and v_piece.store_id is null))
         and v_start >= (v_trip.xs[1]).t
         and v_start - (v_trip.xs[array_length(v_trip.xs, 1)]).t <= interval '30 minutes' then
        v_hit := k;
        exit;
      end if;
    end loop;
    if v_hit is not null then
      v_trip := v_trips[v_hit];
      v_trip.xs := v_trip.xs || v_piece.xs;
      v_trip.walked := v_trip.walked or v_piece.walk;
      v_trips[v_hit] := v_trip;
    else
      v_trips := v_trips || row(v_piece.store_id, null, v_piece.xs, v_piece.walk)::public.detect_trip;
    end if;
  end loop;
  v_trips := array(
    select row(t.store_id, t.actors, t.xs, t.walked)::public.detect_trip
    from unnest(v_trips) with ordinality as t (store_id, actors, xs, walked, n)
    where t.walked or array_length(t.xs, 1) >= 5 order by t.n);
  -- tripOf, then mergeHousehold.
  foreach v_trip in array array(
    select v_trips[i] from generate_subscripts(v_trips, 1) i
    order by (select min(x.t) from unnest((v_trips[i]).xs) x), i)
  loop
    v_trip.xs := array(select row(x.*)::public.detect_tick from unnest(v_trip.xs) x order by x.t, x.id);
    v_trip.actors := array(
      select a.actor from unnest(v_trip.xs) with ordinality as a group by a.actor order by min(a.ordinality));
    v_start := (v_trip.xs[1]).t;
    v_end := (v_trip.xs[array_length(v_trip.xs, 1)]).t;
    v_hit := null;
    for k in 1 .. coalesce(array_length(v_out, 1), 0) loop
      v_other := v_out[k];
      if v_other.store_id is not null and v_other.store_id = v_trip.store_id
         and v_start <= (select max(x.t) from unnest(v_other.xs) x) + interval '10 minutes'
         and (select min(x.t) from unnest(v_other.xs) x) <= v_end + interval '10 minutes'
         and not v_trip.actors <@ v_other.actors then
        v_hit := k;
        exit;
      end if;
    end loop;
    if v_hit is null then
      v_out := v_out || v_trip;
    else
      v_other := v_out[v_hit];
      v_other.actors := v_other.actors
        || array(select a from unnest(v_trip.actors) a where not a = any(v_other.actors));
      v_other.xs := v_other.xs || v_trip.xs;
      v_other.walked := v_other.walked or v_trip.walked;
      v_out[v_hit] := v_other;
    end if;
  end loop;
  return query
  select tr.store_id, tr.actors,
    array(select row(x.*)::public.detect_tick from unnest(tr.xs) x order by x.t, x.id), tr.walked,
    coalesce((
      select jsonb_agg(w - 'first' order by (w ->> 'at')::timestamptz, w ->> 'first')
      from jsonb_array_elements(v_walks) w
      where (w ->> 'first')::bigint in (select x.id from unnest(tr.xs) x)
    ), '[]')
  from unnest(v_out) tr;
end $$;
revoke execute on function public.detect_rule(public.detect_tick[]) from public, anon, authenticated;

-- Running it ---------------------------------------------------------------------------------------

-- One household's detection runs at a time: a run, a removal, a switch-off.
create function public.lock_trip_detection(p_household uuid) returns void
language sql set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('trip_detection:' || p_household::text, 0))
$$;
revoke execute on function public.lock_trip_detection(uuid) from public, anon, authenticated;

-- The pharmacies among [p_household]'s stores (GL-2), by name and seed key.
create function public.detect_pharmacies(p_household uuid) returns uuid[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(s.id), '{}') from public.stores s
  where s.household_id = p_household and public.is_pharmacy_store(concat_ws(' ', s.name, s.seed_key))
$$;
revoke execute on function public.detect_pharmacies(uuid) from public, anon, authenticated;

-- The stores whose walks differ between [p_old] and [p_new] (arrays of walks), which still exist.
create function public.detect_changed_stores(p_household uuid, p_old jsonb, p_new jsonb) returns setof uuid
language sql stable set search_path = '' as $$
  with o as (select (w ->> 'store_id')::uuid as store_id, w from jsonb_array_elements(p_old) w),
  n as (select (w ->> 'store_id')::uuid as store_id, w from jsonb_array_elements(p_new) w)
  select s.id from public.stores s
  where s.household_id = p_household
    and s.id in (select o.store_id from o union select n.store_id from n)
    and (select coalesce(jsonb_agg(o.w order by o.w::text), '[]') from o where o.store_id = s.id)
      is distinct from (select coalesce(jsonb_agg(n.w order by n.w::text), '[]') from n where n.store_id = s.id)
$$;
revoke execute on function public.detect_changed_stores(uuid, jsonb, jsonb) from public, anon, authenticated;

-- Detects [p_household]'s trips anew where ticks arrived since the last run (job 351, "For job
-- 352", reconciliation), and returns how many detected trips it wrote.
--
-- Input: app ticks of people who have detection on (since they switched it on), without the runs
-- they declined as a shop (TD-Q5), without ticks at a
-- pharmacy (GL-2: they join no other store's trip, walk or order either), without the ticks
-- of detected trips it keeps (frozen, removed, or older than the window) and a trip-mode trip's
-- starter's ticks during it. Times: the tap time shifted by the person's usual offset to the
-- server, the 10th percentile of (commit - tap) over their ticks from 7 days before to 36 hours
-- after the tick; else the commit time.
-- Window: 36 hours before the newest tick, and back to the earliest tick committed up to 36 hours
-- before one that came in since the last run (its offset may have moved), widened until no trip and no tick within 30 minutes crosses its start, so every rule
-- (pauses, catch-ups, T2a) sees what it would on the whole history; but never before the
-- household's switch to the learned order nor more than 14 days before the newest tick (a backlog
-- costs quadratic time; older trips stay as they are). Unfrozen detected trips starting in the
-- window are replaced, each new one under the id of the old one it shares the most ticks with, so
-- an open trip page and the first-trip card keep their trip. Trip-mode trips in the window get
-- their walks from their starter's ticks. Then every store whose walks changed is replayed
-- (replay_store_order).
create function public.detect_trips(p_household uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_through timestamptz;
  v_from timestamptz;
  v_currency text;
  v_newest timestamptz;
  v_moved timestamptz;
  v_lower timestamptz;
  v_start timestamptz;
  v_next timestamptz;
  v_pharmacies uuid[];
  v_all public.detect_tick[];
  v_input public.detect_tick[];
  v_replaced jsonb;
  v_old jsonb;
  v_new jsonb := '[]'::jsonb;
  v_trips public.detect_trip[];
  v_trip_walks jsonb[];
  v_ids uuid[];
  v_pair record;
  v_walks jsonb;
  v_lines jsonb;
  v_id uuid;
  v_store uuid;
  v_trip public.detect_trip;
  v_session public.trip_sessions;
begin
  perform public.lock_trip_detection(p_household);
  select h.currency into v_currency
  from public.households h where h.id = p_household and h.order_mode = 'learned';
  if not found then
    return 0;
  end if;
  select st.detected_through, st.detect_from into v_through, v_from
  from public.trip_detection_state st where st.household_id = p_household;
  select max(e.created_at) into v_newest from public.item_events e
  where e.household_id = p_household and e.source = 'app' and e.action in ('bought', 'restored');
  if v_newest is null then
    return 0;
  end if;
  v_from := greatest(coalesce(v_from, '-infinity'), v_newest - interval '14 days');
  -- A new tick moves the offset of every tick committed up to 36 hours before it.
  v_moved := least(v_newest, (
    select min(e.created_at) from public.item_events e
    where e.household_id = p_household and e.source = 'app' and e.action in ('bought', 'restored')
      and e.created_at > coalesce(v_through, '-infinity'))) - interval '36 hours';
  -- Commit times reach back at most 7 days before a tick's tap time, plus slack for the offset.
  v_lower := greatest(v_moved - interval '8 days', v_from);
  v_pharmacies := public.detect_pharmacies(p_household);

  with ev as materialized (
    select e.id, e.item_id, e.action, e.actor, e.source, e.created_at, e.store_id, e.store_open_after,
      e.item_name,
      case when e.client_at between e.created_at - interval '7 days' and e.created_at + interval '24 hours'
           then e.client_at end as client_at
    from public.item_events e
    join public.trip_detection_settings p on p.user_id = e.actor and e.created_at >= p.detect_ticks_from
    where e.household_id = p_household and e.action in ('bought', 'restored')
      and e.created_at >= v_lower - interval '7 days'
  )
  select coalesce(array_agg(s.x order by (s.x).t, (s.x).id), '{}') into v_all
  from (
    select row(ev.id, ev.item_id,
      coalesce(nullif(i.canonical_key, ''), public.item_key(coalesce(i.name, ev.item_name))),
      ev.actor, ev.action, coalesce(ev.client_at + (
        select (array_agg(o.created_at - o.client_at order by o.created_at - o.client_at))[
          floor(count(*) * 0.1)::integer + 1]
        from ev o
        where o.actor = ev.actor and o.client_at is not null
          and o.created_at between ev.created_at - interval '7 days' and ev.created_at + interval '36 hours'
      ), ev.created_at), ev.store_id, ev.store_open_after)::public.detect_tick as x
    from ev
    left join public.items i on i.id = ev.item_id
    where ev.source = 'app' and ev.created_at >= v_lower
  ) s;
  -- Pharmacy ticks count for a declined run's gaps (TD-Q5), then leave (GL-2).
  v_all := array(
    select row(x.*)::public.detect_tick
    from unnest(public.detect_undeclined(v_all, array(
      select d.tick_id from public.shop_declines d where d.household_id = p_household))) x
    where not coalesce(x.store_id = any(v_pharmacies), false)
    order by x.t, x.id);

  v_start := greatest(least(
    coalesce((select max(x.t) from unnest(v_all) x), v_newest) - interval '36 hours',
    (select min(x.t) from unnest(v_all) x where x.id in (
       select e.id from public.item_events e
       where e.household_id = p_household and e.created_at >= v_moved))), v_from);
  loop
    v_next := greatest(least(v_start,
      (select min(s.started_at) from public.trip_sessions s
       where s.household_id = p_household and s.ended_at >= v_start and s.removed_at is null
         and (s.source <> 'detected' or s.frozen_at is null)),
      (select min(x.t) from unnest(v_all) x
       where x.t >= v_start - interval '30 minutes' and x.t < v_start)), v_from);
    exit when v_next >= v_start;
    v_start := v_next;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'at', s.started_at, 'ticks', to_jsonb(s.tick_ids))), '[]'),
         coalesce((select jsonb_agg(w) from public.trip_sessions o, jsonb_array_elements(o.walks) w
                   where o.household_id = p_household and o.source = 'detected' and o.frozen_at is null
                     and o.started_at >= v_start), '[]')
  into v_replaced, v_old
  from public.trip_sessions s
  where s.household_id = p_household and s.source = 'detected' and s.frozen_at is null
    and s.started_at >= v_start;
  delete from public.trips t using public.trip_sessions s
  where t.session_id = s.id and t.household_id = p_household
    and s.household_id = p_household and s.source = 'detected' and s.frozen_at is null
    and s.started_at >= v_start;
  delete from public.trip_sessions s
  where s.household_id = p_household and s.source = 'detected' and s.frozen_at is null
    and s.started_at >= v_start;

  v_input := public.detect_kept(array(
    select row(x.*)::public.detect_tick from unnest(v_all) x
    where x.t >= v_start
      and not exists (
        select from public.trip_sessions s
        where s.household_id = p_household and s.source = 'detected' and s.ended_at >= v_start
          and x.id = any(s.tick_ids))
      and not exists (
        select from public.trip_sessions s
        where s.household_id = p_household and s.source <> 'detected' and s.started_by = x.actor
          and x.t between s.started_at and s.ended_at)
    order by x.t, x.id));

  select coalesce(array_agg(row(r.store_id, r.actors, r.xs, r.walked)::public.detect_trip order by r.n), '{}'),
         coalesce(array_agg(r.walks order by r.n), '{}')
  into v_trips, v_trip_walks
  from public.detect_rule(v_input) with ordinality as r (store_id, actors, xs, walked, walks, n);

  -- Each old trip's id goes to the new trip sharing the most ticks with it (a tie: the older old
  -- trip, then the earlier new one).
  v_ids := array_fill(null::uuid, array[cardinality(v_trips)]);
  for v_pair in
    select k, (o ->> 'id')::uuid as id
    from generate_subscripts(v_trips, 1) k, jsonb_array_elements(v_replaced) o,
      lateral (select count(*) as n from jsonb_array_elements_text(o -> 'ticks') t
               where t::bigint in (select x.id from unnest((v_trips[k]).xs) x)) shared
    where shared.n > 0
    order by shared.n desc, (o ->> 'at')::timestamptz, o ->> 'id', k
  loop
    continue when v_ids[v_pair.k] is not null or v_pair.id = any(v_ids);
    v_ids[v_pair.k] := v_pair.id;
  end loop;

  for k in 1 .. cardinality(v_trips) loop
    v_trip := v_trips[k];
    v_id := coalesce(v_ids[k], gen_random_uuid());
    v_store := (select s.id from public.stores s where s.id = v_trip.store_id and s.household_id = p_household);
    -- One line per key, in tick order, all bought at the trip's store.
    select coalesce(jsonb_agg(l.line order by l.first_t, l.first_id), '[]') into v_lines
    from (
      select distinct on (x.key) x.t as first_t, x.id as first_id, jsonb_build_object(
        'key', x.key, 'name', e.item_name, 'planned', true, 'bought', true,
        'quantity', i.quantity, 'store_id', v_store, 'store_name', st.name,
        'marked_planned', false, 'by_other', false, 'added_by', null,
        'planned_cents', null, 'paid_cents', null) as line
      from unnest(v_trip.xs) x
      join public.item_events e on e.id = x.id
      left join public.items i on i.id = x.item_id
      left join public.stores st on st.id = v_store
      order by x.key, x.t, x.id
    ) l;
    v_lines := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_lines) with ordinality as a (e, o)
                         where o <= 400), '[]');
    insert into public.trip_sessions (id, household_id, list_id, started_by, started_at, ended_at,
      active_seconds, end_reason, source, currency, shopped_on, pauses, lines, store_id, tick_ids,
      detected_by, walked, walks)
    values (v_id, p_household,
      (select e.list_id from public.item_events e where e.id = (v_trip.xs[1]).id),
      v_trip.actors[1], (v_trip.xs[1]).t, (v_trip.xs[array_length(v_trip.xs, 1)]).t,
      case when v_trip.walked
           then floor(extract(epoch from (v_trip.xs[array_length(v_trip.xs, 1)]).t - (v_trip.xs[1]).t))::integer
           else 0 end,
      'auto', 'detected', v_currency, ((v_trip.xs[1]).t at time zone 'Europe/Berlin')::date, '[]', v_lines,
      v_trip.store_id, array(select x.id from unnest(v_trip.xs) x order by x.id), v_trip.actors,
      v_trip.walked, v_trip_walks[k]);
    if jsonb_array_length(v_lines) > 0 then
      insert into public.trips (id, household_id, store_id, store_name, shopped_on, items, session_id, logged_by)
      select md5(v_id::text || ':' || coalesce(v_store::text, '-'))::uuid, p_household, v_store,
        (select st.name from public.stores st where st.id = v_store),
        ((v_trip.xs[1]).t at time zone 'Europe/Berlin')::date,
        jsonb_agg(jsonb_build_object('name', l ->> 'name', 'quantity', l -> 'quantity',
          'canonical_key', nullif(public.canonical_key(l ->> 'name'), '')) order by o),
        v_id, null
      from jsonb_array_elements(v_lines) with ordinality as a (l, o)
      where o <= 200;
    end if;
    v_new := v_new || v_trip_walks[k];
  end loop;

  for v_session in
    select * from public.trip_sessions s
    where s.household_id = p_household and s.source <> 'detected' and s.removed_at is null
      and s.started_at >= v_start and s.ended_at >= v_start
  loop
    select coalesce(jsonb_agg(w order by (w ->> 'at')::timestamptz), '[]') into v_walks
    from public.detect_rule(public.detect_kept(array(
        select row(x.*)::public.detect_tick from unnest(v_all) x
        where x.actor = v_session.started_by and x.t between v_session.started_at and v_session.ended_at
          and not exists (
            select from jsonb_array_elements(v_session.pauses) p
            where x.t >= (p ->> 'from')::timestamptz and x.t < coalesce((p ->> 'to')::timestamptz, 'infinity'))
        order by x.t, x.id))) r,
      jsonb_array_elements(r.walks) w;
    if v_walks is distinct from v_session.walks then
      v_old := v_old || v_session.walks;
      v_new := v_new || v_walks;
      update public.trip_sessions s set walks = v_walks where s.id = v_session.id;
    end if;
  end loop;

  for v_store in select public.detect_changed_stores(p_household, v_old, v_new) loop
    perform public.replay_store_order(p_household, v_store);
  end loop;
  insert into public.trip_detection_state as st (household_id, detected_through) values (p_household, v_newest)
  on conflict (household_id) do update set detected_through = excluded.detected_through
    where st.detected_through is distinct from excluded.detected_through;
  return cardinality(v_trips);
end $$;
revoke execute on function public.detect_trips(uuid) from public, anon, authenticated;

-- Learned households with an app tick no run has seen and none in the last 10 minutes (T1a: a
-- trip may still be going on), by id.
create function public.detect_due_households() returns setof uuid
language sql stable set search_path = '' as $$
  select h.id from public.households h
  left join public.trip_detection_state st on st.household_id = h.id
  where h.order_mode = 'learned'
    and exists (
      select from public.item_events e
      where e.household_id = h.id and e.source = 'app' and e.action in ('bought', 'restored')
        and e.created_at > coalesce(st.detected_through, '-infinity'))
    and not exists (
      select from public.item_events e
      where e.household_id = h.id and e.source = 'app' and e.action in ('bought', 'restored')
        and e.created_at > now() - interval '10 minutes')
  order by h.id
$$;
revoke execute on function public.detect_due_households() from public, anon, authenticated;

-- Runs every due household in one transaction, for tests and by hand. One household's failure
-- skips only it.
create function public.detect_due_trips() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_runs integer := 0;
begin
  for v_household in select public.detect_due_households() loop
    begin
      perform public.detect_trips(v_household);
      v_runs := v_runs + 1;
    exception when others then
      raise warning 'detect_trips(%) failed: % %', v_household, sqlstate, sqlerrm;
    end;
  end loop;
  return v_runs;
end $$;
revoke execute on function public.detect_due_trips() from public, anon, authenticated;

-- pg_cron, every 5 minutes: detect_due_trips with a commit after each household, so a run holds
-- one household's locks (detection, item order, its items) at a time and never for the whole run;
-- the app's writes wait at most for one household. A procedure that commits runs as its caller
-- (pg_cron's postgres) and takes no search_path setting, hence every name qualified.
create procedure public.detect_due_trips_each()
language plpgsql as $$
declare
  v_household uuid;
begin
  for v_household in select public.detect_due_households() loop
    begin
      perform public.detect_trips(v_household);
    exception when others then
      raise warning 'detect_trips(%) failed: % %', v_household, sqlstate, sqlerrm;
    end;
    commit;
  end loop;
end $$;
revoke execute on procedure public.detect_due_trips_each() from public, anon, authenticated;

select cron.schedule('detect-trips', '*/5 * * * *', 'call public.detect_due_trips_each()');

-- Reading and fixing ---------------------------------------------------------------------------

-- N-320: whether everyone in [p_detected_by] but the caller has seen the first detected trip
-- card, so the caller may see the trip: a co-detected member waits for the others' cards too.
create function public.detected_trip_shown(p_detected_by uuid[]) returns boolean
language sql stable set search_path = '' as $$
  select not exists (
    select from unnest(coalesce(p_detected_by, '{}')) d
    where d is distinct from auth.uid() and not exists (
      select from public.trip_detection_settings p where p.user_id = d and p.detected_card_at is not null))
$$;
revoke execute on function public.detected_trip_shown(uuid[]) from public, anon, authenticated;

-- Removes detected trip [p_id] of [p_household] ("Kein Einkauf", GL-3): a tombstone without lines
-- or walks, frozen, so detection never finds its ticks again; its log rows go, its stores are
-- replayed. Removing it again changes nothing.
create function public.detect_remove(p_household uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_walks jsonb;
  v_store uuid;
begin
  perform public.lock_trip_detection(p_household);
  select s.walks into v_walks from public.trip_sessions s
  where s.id = p_id and s.household_id = p_household and s.source = 'detected' and s.removed_at is null
  for update;
  if not found then
    return;
  end if;
  update public.trip_sessions s set removed_at = now(), frozen_at = coalesce(s.frozen_at, now()),
    lines = '[]', walks = '[]', updated_at = now()
  where s.id = p_id;
  delete from public.trips t where t.session_id = p_id and t.household_id = p_household;
  for v_store in select public.detect_changed_stores(p_household, v_walks, '[]') loop
    perform public.replay_store_order(p_household, v_store);
  end loop;
end $$;
revoke execute on function public.detect_remove(uuid, uuid) from public, anon, authenticated;

-- "Kein Einkauf": any member removes a detected trip. A removed one is no error, so a retry
-- succeeds. Errors: not_authenticated, missing_argument, trip_not_found, not_a_member,
-- not_detected (a trip-mode trip: delete_trip_session).
create function public.remove_detected_trip(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_source text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_id is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  select s.household_id, s.source into v_household, v_source from public.trip_sessions s where s.id = p_id;
  if not found then
    raise exception 'trip_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_source <> 'detected' then
    raise exception 'not_detected' using errcode = '22023';
  end if;
  perform public.detect_remove(v_household, p_id);
end $$;
revoke execute on function public.remove_detected_trip(uuid) from public, anon;
grant execute on function public.remove_detected_trip(uuid) to authenticated;

-- As in 20261115130000_checks_before_locks.sql; a detected trip is removed instead (a deleted one
-- would be detected again).
create or replace function public.delete_trip_session(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_source text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select s.household_id, s.source into v_household, v_source from public.trip_sessions s where s.id = p_id;
  if not found then
    return;
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_source = 'detected' then
    perform public.detect_remove(v_household, p_id);
    return;
  end if;
  select s.household_id into v_household from public.trip_sessions s where s.id = p_id for update;
  if not found then
    return;
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  delete from public.trips t where t.session_id = p_id and t.household_id = v_household;
  delete from public.trip_sessions s where s.id = p_id;
end $$;

-- As in 20261115130000_checks_before_locks.sql; deleting a detected trip's log row removes the
-- trip.
create or replace function public.delete_trip(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_session uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- Twice: read, then locked.
  for v_round in 1 .. 2 loop
    if v_round = 1 then
      select t.household_id, t.session_id into v_household, v_session
      from public.trips t where t.id = p_id;
    else
      if exists (select from public.trip_sessions s where s.id = v_session and s.source = 'detected') then
        perform public.detect_remove(v_household, v_session);
        return;
      end if;
      select t.household_id, t.session_id into v_household, v_session
      from public.trips t where t.id = p_id for update;
    end if;
    if not found then
      return;
    end if;
    if not public.is_household_member(v_household) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
  end loop;
  delete from public.trips t where t.id = p_id;
  if v_session is not null
     and not exists (select from public.trips t where t.session_id = v_session) then
    delete from public.trip_sessions s where s.id = v_session;
  end if;
end $$;

-- As in 20261115130000_checks_before_locks.sql; marking a line of a detected trip freezes it, so
-- detection keeps it as edited.
create or replace function public.mark_trip_line_planned(p_id uuid, p_key text, p_planned boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_id is null or p_key is null or p_planned is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  -- Twice: read, then locked.
  for v_round in 1 .. 2 loop
    if v_round = 1 then
      select s.household_id into v_household from public.trip_sessions s where s.id = p_id;
    else
      select s.household_id into v_household from public.trip_sessions s where s.id = p_id
      for update;
    end if;
    if not found then
      raise exception 'trip_not_found' using errcode = 'P0002';
    end if;
    if not public.is_household_member(v_household) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
  end loop;
  if not (public.household_has_premium(v_household) or public.user_has_premium(auth.uid())) then
    raise exception 'premium_required' using errcode = '42501';
  end if;
  update public.trip_sessions s set
    lines = (
      select jsonb_agg(case when e ->> 'key' = p_key
                            then jsonb_set(e, '{marked_planned}', to_jsonb(p_planned)) else e end
                       order by o)
      from jsonb_array_elements(s.lines) with ordinality as x (e, o)
    ),
    frozen_at = case when s.source = 'detected' then coalesce(s.frozen_at, now()) end,
    updated_at = now()
  where s.id = p_id
    and exists (select from jsonb_array_elements(s.lines) e
                where e ->> 'key' = p_key and (e -> 'marked_planned')::boolean is distinct from p_planned);
end $$;

-- As in 20261114181718_trip_mode.sql, plus detected_by, walked and mine (the caller started the
-- trip or is in detected_by), so save_trip_session and trip_session answer alike.
create or replace function public.trip_session_json(p_session public.trip_sessions, p_premium boolean) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_session.id,
    'household_id', p_session.household_id,
    'list_id', p_session.list_id,
    'started_by', p_session.started_by,
    'started_at', p_session.started_at,
    'ended_at', p_session.ended_at,
    'active_seconds', p_session.active_seconds,
    'end_reason', p_session.end_reason,
    'source', p_session.source,
    'currency', p_session.currency,
    'shopped_on', p_session.shopped_on,
    'pauses', p_session.pauses,
    'lines', case when p_premium then p_session.lines end,
    'bought', (select count(*)::int from jsonb_array_elements(p_session.lines) e
               where (e ->> 'bought')::boolean),
    'stores', coalesce((
      select jsonb_agg(g.name order by g.sort_order nulls last, g.name nulls last)
      from (
        select e ->> 'store_name' as name, min(s.sort_order) as sort_order
        from jsonb_array_elements(p_session.lines) e
        left join public.stores s
          on s.id = (e ->> 'store_id')::uuid and s.household_id = p_session.household_id
        where (e ->> 'bought')::boolean
        group by e ->> 'store_name'
      ) g
    ), '[]'),
    'premium', p_premium,
    'detected_by', p_session.detected_by,
    'walked', p_session.walked,
    'mine', coalesce(p_session.started_by = auth.uid(), false)
      or coalesce(auth.uid() = any(p_session.detected_by), false)
  )
$$;

-- Session [p_id] of [p_household] for a member (trip_session_json). Of a detected trip that is not
-- the caller's alone, no clock times (started_at, ended_at, pauses null: N-321; a shared trip's
-- start and end are the others' ticks too), and none at all until everyone else in it has seen
-- the first-trip card (N-320). A removed trip is not found.
-- Errors: not_authenticated, missing_argument, not_a_member, trip_not_found.
create or replace function public.trip_session(p_household uuid, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.trip_sessions;
  v_json jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_household is null or p_id is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  select * into v_row from public.trip_sessions s
  where s.id = p_id and s.household_id = p_household and s.removed_at is null;
  if v_row.id is null or (v_row.source = 'detected' and not public.detected_trip_shown(v_row.detected_by)) then
    raise exception 'trip_not_found' using errcode = 'P0002';
  end if;
  v_json := public.trip_session_json(v_row,
    public.household_has_premium(p_household) or public.user_has_premium(auth.uid()));
  if v_row.source = 'detected' and v_row.detected_by is distinct from array[auth.uid()] then
    v_json := v_json || '{"started_at": null, "ended_at": null, "pauses": null}';
  end if;
  return v_json;
end $$;

-- As in 20261113070349_grocery_log.sql, without detected trips: app builds before job 352 know
-- nothing of them.
create or replace function public.trip_history(p_household uuid, p_today date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_premium boolean;
  v_since date;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_household is null or p_today is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  v_premium := public.household_has_premium(p_household) or public.user_has_premium(auth.uid());
  if not v_premium then
    v_since := least(greatest(p_today, current_date - 1), current_date + 1) - 27;
  end if;
  return jsonb_build_object(
    'trips', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.shopped_on desc, t.created_at desc, t.id desc)
      from public.trips t
      where t.household_id = p_household and (v_since is null or t.shopped_on >= v_since)
        and not exists (select from public.trip_sessions s where s.id = t.session_id and s.source = 'detected')
    ), '[]'::jsonb),
    'premium', v_premium,
    'since', v_since,
    'locked', (
      select count(*)::int from public.trips t
      where t.household_id = p_household and t.shopped_on < v_since
        and not exists (select from public.trip_sessions s where s.id = t.session_id and s.source = 'detected')
    )
  );
end $$;

-- trip_history with detected trips. Each trip also carries session_source ('ask', 'manual',
-- 'detected', or null for one logged by hand), detected_by and walked (null but for detected
-- trips). A detected trip shows only once everyone else in it has seen the first-trip card
-- (N-320); unless it is the caller's alone, with created_at and updated_at at its day's midnight
-- UTC, and after the day's other trips, by id (N-321: the order would tell which came first).
-- Errors: not_authenticated, missing_argument, not_a_member.
create function public.trip_history_v2(p_household uuid, p_today date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_premium boolean;
  v_since date;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_household is null or p_today is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  v_premium := public.household_has_premium(p_household) or public.user_has_premium(auth.uid());
  if not v_premium then
    v_since := least(greatest(p_today, current_date - 1), current_date + 1) - 27;
  end if;
  return (
    with visible as (
      select t, s.source, s.detected_by, s.walked,
        s.source = 'detected' and s.detected_by is distinct from array[auth.uid()] as others
      from public.trips t
      left join public.trip_sessions s on s.id = t.session_id and s.household_id = t.household_id
      where t.household_id = p_household
        and (s.source is distinct from 'detected'
             or (s.removed_at is null and public.detected_trip_shown(s.detected_by)))
    )
    select jsonb_build_object(
      'trips', coalesce((
        select jsonb_agg(
          to_jsonb(v.t)
          || jsonb_build_object('session_source', v.source, 'detected_by', v.detected_by, 'walked', v.walked)
          || case when v.others then jsonb_build_object(
               'created_at', (v.t).shopped_on::timestamp at time zone 'UTC',
               'updated_at', (v.t).shopped_on::timestamp at time zone 'UTC') else '{}' end
          order by (v.t).shopped_on desc, case when not v.others then (v.t).created_at end desc nulls last,
            (v.t).id desc)
        from visible v where v_since is null or (v.t).shopped_on >= v_since
      ), '[]'::jsonb),
      'premium', v_premium,
      'since', v_since,
      'locked', (select count(*)::int from visible v where (v.t).shopped_on < v_since)
    )
  );
end $$;
revoke execute on function public.trip_history_v2(uuid, date) from public, anon;
grant execute on function public.trip_history_v2(uuid, date) to authenticated;

-- N-319: the caller's switch. Off: their ticks leave detection (none before a later switch-on
-- ever counts again) and lose their tap times, their unedited detected trips go in every
-- household with their log rows, so do the "Kein Einkauf" tombstones of their trips (a shared
-- one only loses them), their trip-mode trips lose their walks, the stores are replayed, and each
-- household's next run detects the others' ticks of those trips again, and their „Nein" answers
-- (shop_declines) go. On: from now.
-- Every household of the caller is locked first (in id order, as detect_trips locks one, before
-- any row): a run going on finishes and is cleaned up here, a later one reads the switch.
-- Errors: not_authenticated, missing_argument.
create function public.set_trip_detection(p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_household uuid;
  v_walks jsonb;
  v_from timestamptz;
  v_store uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_on is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if p_on then
    insert into public.trip_detection_settings as p (user_id, detect_ticks_from) values (v_user, now())
    on conflict (user_id) do update set detect_ticks_from = now() where p.detect_ticks_from is null;
    return;
  end if;
  for v_household in
    select m.household_id from public.household_members m where m.user_id = v_user order by m.household_id
  loop
    perform public.lock_trip_detection(v_household);
  end loop;
  insert into public.trip_detection_settings as p (user_id, detect_ticks_from) values (v_user, null)
  on conflict (user_id) do update set detect_ticks_from = null where p.detect_ticks_from is not null;
  update public.item_events e set client_at = null where e.actor = v_user and e.client_at is not null;
  delete from public.shop_declines d where d.user_id = v_user;
  delete from public.trip_sessions s
  where s.source = 'detected' and s.removed_at is not null and s.detected_by = array[v_user];
  update public.trip_sessions s set detected_by = array_remove(s.detected_by, v_user)
  where s.source = 'detected' and s.removed_at is not null and v_user = any(s.detected_by);
  for v_household in
    select s.household_id from public.trip_sessions s
    where (s.source = 'detected' and s.frozen_at is null and v_user = any(s.detected_by))
       or (s.source <> 'detected' and s.started_by = v_user and s.walks <> '[]')
    group by s.household_id order by s.household_id
  loop
    perform public.lock_trip_detection(v_household);
    select coalesce(jsonb_agg(w), '[]') into v_walks
    from public.trip_sessions s, jsonb_array_elements(s.walks) w
    where s.household_id = v_household
      and ((s.source = 'detected' and s.frozen_at is null and v_user = any(s.detected_by))
           or (s.source <> 'detected' and s.started_by = v_user));
    select min(e.created_at) into v_from
    from public.trip_sessions s, public.item_events e
    where s.household_id = v_household and s.source = 'detected' and s.frozen_at is null
      and v_user = any(s.detected_by) and e.id = any(s.tick_ids);
    delete from public.trips t using public.trip_sessions s
    where t.session_id = s.id and t.household_id = v_household and s.household_id = v_household
      and s.source = 'detected' and s.frozen_at is null and v_user = any(s.detected_by);
    delete from public.trip_sessions s
    where s.household_id = v_household and s.source = 'detected' and s.frozen_at is null
      and v_user = any(s.detected_by);
    update public.trip_sessions s set walks = '[]'
    where s.household_id = v_household and s.source <> 'detected' and s.started_by = v_user
      and s.walks <> '[]';
    update public.trip_detection_state st set detected_through = v_from - interval '1 microsecond'
    where st.household_id = v_household and v_from is not null
      and coalesce(st.detected_through, 'infinity') >= v_from;
    for v_store in select public.detect_changed_stores(v_household, v_walks, '[]') loop
      perform public.replay_store_order(v_household, v_store);
    end loop;
  end loop;
end $$;
revoke execute on function public.set_trip_detection(boolean) from public, anon;
grant execute on function public.set_trip_detection(boolean) to authenticated;

-- The caller's detection: {on, card_seen, first_trip}. first_trip, while the card is unseen: the
-- newest detected trip the caller is in, {id, household_id, store_name}, or null. Only an app that
-- shows the switch calls it, so its first call switches detection on for the caller's ticks from
-- then on (N-319: nobody is detected without the switch in front of them).
create function public.my_trip_detection() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_settings public.trip_detection_settings;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  insert into public.trip_detection_settings (user_id, detect_ticks_from) values (auth.uid(), now())
  on conflict (user_id) do nothing;
  select * into v_settings from public.trip_detection_settings p where p.user_id = auth.uid();
  return jsonb_build_object(
    'on', v_settings.detect_ticks_from is not null,
    'card_seen', v_settings.detected_card_at is not null,
    'first_trip', case when v_settings.detected_card_at is null then (
      select jsonb_build_object('id', s.id, 'household_id', s.household_id, 'store_name', st.name)
      from public.trip_sessions s
      left join public.stores st on st.id = s.store_id and st.household_id = s.household_id
      where s.source = 'detected' and s.removed_at is null and auth.uid() = any(s.detected_by)
        and public.is_household_member(s.household_id)
      -- One the caller can open first; else a shared one, which opens once the others saw their
      -- card: two people whose only trips are shared would otherwise never get theirs.
      order by public.detected_trip_shown(s.detected_by) desc, s.started_at desc, s.id
      limit 1) end);
end $$;
revoke execute on function public.my_trip_detection() from public, anon;
grant execute on function public.my_trip_detection() to authenticated;

-- The caller has seen the first detected trip card; others may now see their detected trips.
create function public.seen_detected_trip_card() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- Only a row my_trip_detection made: the card follows it, and a row made here would leave the
  -- switch in a state its owner never chose.
  update public.trip_detection_settings p set detected_card_at = now()
  where p.user_id = auth.uid() and p.detected_card_at is null;
end $$;
revoke execute on function public.seen_detected_trip_card() from public, anon;
grant execute on function public.seen_detected_trip_card() to authenticated;

-- TD-Q5: the caller answered the trip question for their tick of [p_item] „Nein, nur abgehakt" (or
-- closed it) at [p_at] on their device: detection leaves that run out (detect_undeclined), also
-- when it already ran over it. Stores nothing for a household without the learned order, for a
-- caller whose detection is off, or without a tick of theirs. The same answer twice changes
-- nothing. Errors: not_authenticated, missing_argument, item_not_found (also another
-- household's item).
create function public.decline_shop(p_item uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_household uuid;
  v_tick bigint;
  v_ticked timestamptz;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_item is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  select i.household_id into v_household from public.items i where i.id = p_item;
  if not found or not public.is_household_member(v_household) then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if not exists (select from public.households h where h.id = v_household and h.order_mode = 'learned')
     or not public.trip_detection_on(v_user) then
    return;
  end if;
  perform public.lock_trip_detection(v_household);
  select e.id, e.created_at into v_tick, v_ticked from public.item_events e
  where e.household_id = v_household and e.item_id = p_item and e.actor = v_user and e.action = 'bought'
  order by e.created_at desc, e.id desc
  limit 1;
  if not found then
    return;
  end if;
  insert into public.shop_declines (household_id, user_id, tick_id, client_at)
  values (v_household, v_user, v_tick,
    case when p_at between now() - interval '7 days' and now() + interval '24 hours' then p_at end)
  on conflict (user_id, tick_id) do nothing;
  if found then
    update public.trip_detection_state st set detected_through = v_ticked - interval '1 microsecond'
    where st.household_id = v_household and st.detected_through >= v_ticked;
  end if;
end $$;
revoke execute on function public.decline_shop(uuid, timestamptz) from public, anon;
grant execute on function public.decline_shop(uuid, timestamptz) to authenticated;

-- Declines older than detection ever looks back (14 days before the newest tick), plus a day.
create function public.purge_shop_declines() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.shop_declines d where d.declined_at < now() - interval '15 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.purge_shop_declines() from public, anon, authenticated;

select cron.schedule('purge-shop-declines', '37 3 * * *', 'select public.purge_shop_declines()');

-- Leaving or being removed also takes the user out of the detected trips they were in and deletes
-- their „Nein" answers there (shop_declines). Otherwise
-- unchanged from 20261114181718_trip_mode.sql.
create or replace function public.household_member_forget_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_user text := old.user_id::text;
begin
  -- A deleted household takes its rows with it. The last member leaving archives or deletes it
  -- (leave_household_as): an archive is theirs to bring back as it was, and a delete goes anyway.
  if not exists (select from public.households h where h.id = old.household_id)
     or not exists (select from public.household_members m where m.household_id = old.household_id) then
    return null;
  end if;
  update public.items i set
    added_by = case when i.added_by = old.user_id then null else i.added_by end,
    bought_by = case when i.bought_by = old.user_id then null else i.bought_by end
  where i.household_id = old.household_id and old.user_id in (i.added_by, i.bought_by);
  update public.item_events e set actor = null
  where e.household_id = old.household_id and e.actor = old.user_id;
  update public.lists l set created_by = null
  where l.household_id = old.household_id and l.created_by = old.user_id;
  update public.item_merges m set
    merged_by = case when m.merged_by = old.user_id then null else m.merged_by end,
    merged_row = public.forget_user_in_row(m.merged_row, v_user),
    kept_before = public.forget_user_in_row(m.kept_before, v_user)
  where m.household_id = old.household_id
    and (m.merged_by = old.user_id
         or v_user in (m.merged_row ->> 'added_by', m.merged_row ->> 'bought_by',
                       m.kept_before ->> 'added_by', m.kept_before ->> 'bought_by'));
  update public.invites v set
    created_by = case when v.created_by = old.user_id then null else v.created_by end,
    used_by = case when v.used_by = old.user_id then null else v.used_by end
  where v.household_id = old.household_id and old.user_id in (v.created_by, v.used_by);
  update public.join_requests r set decided_by = null
  where r.household_id = old.household_id and r.decided_by = old.user_id;
  update public.trips t set logged_by = null
  where t.household_id = old.household_id and t.logged_by = old.user_id;
  update public.trip_sessions s set
    started_by = case when s.started_by = old.user_id then null else s.started_by end,
    lines = public.trip_lines_forget_user(s.lines, v_user),
    detected_by = array_remove(s.detected_by, old.user_id)
  where s.household_id = old.household_id
    and (s.started_by = old.user_id
         or s.lines @> jsonb_build_array(jsonb_build_object('added_by', v_user))
         or old.user_id = any(s.detected_by));
  update public.households h set created_by = null
  where h.id = old.household_id and h.created_by = old.user_id;
  delete from public.shop_declines d where d.household_id = old.household_id and d.user_id = old.user_id;
  return null;
end $$;

-- Leaving, a removal and an account deletion take each household's detection lock before any row
-- lock, as detect_trips and set_trip_detection do. They lock the household row, then items and
-- trip_sessions (household_member_forget_user, cascades); a run holds those and needs a key share
-- on the household row for its trip_sessions inserts, so each would wait for the other. Otherwise
-- unchanged from
-- 20261115130000_checks_before_locks.sql and 20261113155327_revenuecat_known_customers.sql.
create or replace function public.leave_household_as(
  p_user uuid,
  p_household uuid,
  p_archive boolean
)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
begin
  -- No membership, no locks. The delete below asks again under them.
  if not exists (
    select from public.household_members m
    where m.user_id = p_user and m.household_id = p_household
  ) then
    return 'none';
  end if;
  perform public.lock_memberships(p_user);
  perform public.lock_trip_detection(p_household);
  perform from public.households h where h.id = p_household for update;
  delete from public.household_members m where m.user_id = p_user and m.household_id = p_household
  returning m.role into v_role;
  if not found then
    return 'none';
  end if;
  if exists (select from public.household_members where household_id = p_household) then
    if v_role = 'owner' then
      perform public.hand_over_ownership(p_household, p_user);
    end if;
    return 'left';
  end if;
  if p_archive and public.household_has_premium(p_household) then
    if not public.app_switch('household_archive') then
      raise exception 'archive_disabled'
        using hint = 'Archiving households is switched off on this server (app_switches).';
    end if;
    update public.households set archived_at = now(), archived_by = p_user where id = p_household;
    return 'archived';
  end if;
  delete from public.households where id = p_household;
  return 'deleted';
end $$;

create or replace function public.remove_member(p_household uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_mine text;
  v_theirs text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- Twice: before the locks, so only a removal that goes through holds the user's memberships
  -- and the household's row, and under them.
  for v_round in 1 .. 2 loop
    if v_round = 2 then
      -- leave_household_as's lock order: the removed user's memberships, the household's
      -- detection, then the household.
      perform public.lock_memberships(p_user);
      perform public.lock_trip_detection(p_household);
      perform from public.households h where h.id = p_household for update;
    end if;
    v_mine := public.my_role_in(p_household);
    if v_mine is null then
      raise exception 'not_member' using errcode = '42501';
    elsif v_mine = 'member' then
      raise exception 'not_admin' using errcode = '42501';
    elsif p_user = auth.uid() then
      raise exception 'cannot_remove_self' using errcode = '22023';
    end if;
    select m.role into v_theirs from public.household_members m
    where m.household_id = p_household and m.user_id = p_user;
    if v_theirs is null then
      raise exception 'not_member' using errcode = '42501';
    elsif v_theirs = 'owner' then
      raise exception 'cannot_remove_owner' using errcode = '42501';
    elsif v_theirs = 'admin' and v_mine <> 'owner' then
      raise exception 'cannot_remove_admin' using errcode = '42501';
    end if;
  end loop;
  perform public.leave_household_as(p_user, p_household, false);
  insert into public.household_removals as r (household_id, user_id) values (p_household, p_user)
  on conflict (household_id, user_id) do update set removed_at = now();
end $$;

create or replace function public.delete_account(p_user uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_default uuid := public.default_household_of(p_user);
  v_household uuid;
  v_role text;
  v_this text;
  v_fate text := 'none';
begin
  perform public.purchase_user_lock(p_user);
  perform public.lock_memberships(p_user);
  for v_household in
    select m.household_id from public.household_members m where m.user_id = p_user
    union
    select h.id from public.households h where h.archived_by = p_user
    order by 1
  loop
    perform public.lock_trip_detection(v_household);
  end loop;
  -- The household row locks serialize with joins (their membership insert takes a key share lock
  -- on the household) and with another member deleting their account at once. Household id
  -- order, so two deletions sharing households lock them in the same order.
  for v_household, v_role in
    select h.id, m.role
    from public.households h
    join public.household_members m on m.household_id = h.id
    where m.user_id = p_user
    order by h.id
    for update of h
  loop
    if exists (
      select from public.household_members m
      where m.household_id = v_household and m.user_id <> p_user
    ) then
      v_this := 'kept';
      if v_role = 'owner' then
        perform public.hand_over_ownership(v_household, p_user);
      end if;
    else
      v_this := 'deleted';
      delete from public.households where id = v_household;
    end if;
    if v_household = v_default then
      v_fate := v_this;
    end if;
  end loop;

  -- Job 43: the households they archived have no one else to come back to them.
  delete from public.households where archived_by = p_user;
  update public.item_events set actor = null where actor = p_user;
  delete from auth.users where id = p_user;
  return v_fate;
end $$;

-- Account deletion: out of detected_by too (started_by goes with its foreign key). Otherwise
-- unchanged from 20261114181718_trip_mode.sql.
create or replace function public.trip_sessions_forget_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_user text := old.id::text;
begin
  update public.trip_sessions s set lines = public.trip_lines_forget_user(s.lines, v_user)
  where s.lines @> jsonb_build_array(jsonb_build_object('added_by', v_user));
  update public.trip_sessions s set detected_by = array_remove(s.detected_by, old.id)
  where old.id = any(s.detected_by);
  return null;
end $$;

-- Data export: the detected trips the user is in (trips_detected, not under trip_sessions_started;
-- a shared one without clock times),
-- their detection switch with their „Nein" answers (shops_declined), and the tap time and source of
-- their ticks. Otherwise unchanged from
-- 20261121121147_tester_groups.sql.
create or replace function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- An app connected over OAuth (MCP) acts on the list, not on the account.
  if auth.jwt() ->> 'client_id' is not null then
    raise exception 'session_required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'format', 'family-groceries-export',
    'version', 1,
    'exported_at', now(),
    'account', (
      select jsonb_build_object(
        'id', u.id,
        'email', u.email,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'providers', coalesce(
          (select jsonb_agg(distinct i.provider) from auth.identities i where i.user_id = u.id),
          '[]'::jsonb
        )
      )
      from auth.users u where u.id = v_user
    ),
    'profile', (
      select jsonb_build_object('display_name', p.display_name, 'created_at', p.created_at)
      from public.profiles p where p.id = v_user
    ),
    'household', (
      select jsonb_build_object('id', h.id, 'name', h.name, 'role', m.role, 'joined_at', m.joined_at,
        'currency', h.currency)
      from public.household_members m
      join public.households h on h.id = m.household_id
      where m.user_id = v_user and m.is_default
    ),
    'invite_uses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', u.household_id, 'invite_id', u.invite_id, 'joined_at', u.joined_at
      ) order by u.joined_at)
      from public.invite_uses u where u.user_id = v_user
    ), '[]'::jsonb),
    'household_removals', coalesce((
      select jsonb_agg(jsonb_build_object('household_id', r.household_id, 'removed_at', r.removed_at)
        order by r.removed_at, r.household_id)
      from public.household_removals r where r.user_id = v_user
    ), '[]'::jsonb),
    'households', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'name', h.name,
        'kind', h.kind,
        'role', m.role,
        'joined_at', m.joined_at,
        'is_default', m.is_default,
        'default_list', (select l.name from public.lists l where l.id = m.default_list_id),
        'currency', h.currency
      ) order by m.joined_at, h.id)
      from public.household_members m
      join public.households h on h.id = m.household_id
      where m.user_id = v_user
    ), '[]'::jsonb),
    'items_added', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', i.name,
        'brand', i.brand,
        'properties', i.properties,
        'quantity', i.quantity,
        'status', i.status,
        'category', c.name,
        'store', s.name,
        'list', l.name,
        'created_at', i.created_at,
        'bought_at', i.bought_at,
        'price_unit_micros', i.price_unit_micros,
        'price_basis', i.price_basis,
        'price_per', i.price_per,
        'price_currency', i.price_currency,
        'priced_at', i.priced_at
      ) order by i.created_at, i.id)
      from public.items i
      join public.household_members m on m.household_id = i.household_id and m.user_id = v_user
      left join public.categories c on c.id = i.category_id
      left join public.stores s on s.id = i.store_id
      left join public.lists l on l.id = i.list_id
      where i.added_by = v_user
    ), '[]'::jsonb),
    'lists_created', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', l.household_id, 'name', l.name, 'created_at', l.created_at
      ) order by l.created_at, l.id)
      from public.lists l where l.created_by = v_user
    ), '[]'::jsonb),
    'item_claims', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', c.household_id, 'item_name', i.name, 'quantity', c.quantity,
        'created_at', c.created_at
      ) order by c.created_at, c.item_id)
      from public.item_claims c join public.items i on i.id = c.item_id
      where c.user_id = v_user
    ), '[]'::jsonb),
    'join_requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', r.household_id, 'created_at', r.created_at, 'decision', r.decision,
        'decided_at', r.decided_at
      ) order by r.created_at, r.id)
      from public.join_requests r where r.user_id = v_user
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', e.action,
        'item_name', e.item_name,
        'category', c.name,
        'created_at', e.created_at,
        'client_at', e.client_at,
        'source', e.source
      ) order by e.created_at, e.id)
      from public.item_events e
      left join public.categories c on c.id = e.category_id
      where e.actor = v_user
    ), '[]'::jsonb),
    'access_tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', t.name,
        'token_hint', t.token_hint,
        'created_at', t.created_at,
        'last_used_at', t.last_used_at,
        'revoked_at', t.revoked_at
      ) order by t.created_at, t.id)
      from public.personal_access_tokens t
      where t.user_id = v_user
    ), '[]'::jsonb),
    'invites_created', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', iv.code,
        'kind', iv.kind,
        'max_uses', iv.max_uses,
        'use_count', iv.use_count,
        'created_at', iv.created_at,
        'expires_at', iv.expires_at,
        'used_at', iv.used_at,
        'revoked_at', iv.revoked_at
      ) order by iv.created_at, iv.id)
      from public.invites iv
      where iv.created_by = v_user
    ), '[]'::jsonb),
    'feedback', coalesce((
      select jsonb_agg(jsonb_build_object(
        'created_at', f.created_at,
        'message', f.message,
        'category', f.category,
        'contact_ok', f.contact_ok,
        'screen', f.screen,
        'platform', f.platform,
        'app_version', f.app_version,
        'build', f.build,
        'os_version', f.os_version,
        'locale', f.locale,
        'household_id', f.household_id,
        'is_internal', f.is_internal,
        'screenshot', f.screenshot,
        'status', f.status,
        'fixed_in', f.fixed_in,
        'reply', f.reply,
        'replied_at', f.replied_at,
        'answered_at', f.answered_at,
        'seen_at', f.seen_at
      ) order by f.created_at, f.id)
      from public.feedback f
      where f.user_id = v_user
    ), '[]'::jsonb),
    'feedback_idea_votes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', v.household_id,
        'title_de', i.title_de,
        'title_en', i.title_en,
        'created_at', v.created_at
      ) order by v.created_at, v.household_id, v.idea_id)
      from public.feedback_idea_votes v
      join public.feedback_ideas i on i.id = v.idea_id
      join public.household_members m on m.household_id = v.household_id and m.user_id = v_user
    ), '[]'::jsonb),
    'connected_apps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'client_name', oc.client_name,
        'scopes', c.scopes,
        'granted_at', c.granted_at,
        'revoked_at', c.revoked_at,
        'device', d.device
      ) order by c.granted_at, c.id)
      from auth.oauth_consents c
      join auth.oauth_clients oc on oc.id = c.client_id
      left join public.oauth_app_devices d on d.user_id = c.user_id and d.client_id = c.client_id
      where c.user_id = v_user
    ), '[]'::jsonb),
    'analytics_decisions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'install_id', a.install_id,
        'consent', a.consent,
        'internal', a.internal,
        'decided_at', a.decided_at,
        'consent_text_version', a.consent_text_version
      ) order by a.decided_at, a.install_id)
      from public.analytics_consents a
      where a.user_id = v_user
    ), '[]'::jsonb),
    'alexa_links', coalesce((
      select jsonb_agg(jsonb_build_object('last_seen', l.last_seen) order by l.last_seen)
      from public.alexa_links l
      where l.user_id = v_user
    ), '[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'store', p.store,
        'product_id', p.product_id,
        'plan', p.plan,
        'transaction_id', p.transaction_id,
        'environment', p.environment,
        'purchased_at', p.purchased_at,
        'expires_at', p.expires_at,
        'auto_renew', p.auto_renew,
        'revoked_at', p.revoked_at,
        'price', p.price,
        'currency', p.currency,
        'country', p.country,
        'unlocks_household', (select e.household_id from public.entitlements e where e.purchase_id = p.id),
        'belongs_to_household', p.bound_household
      ) order by p.purchased_at, p.id)
      from public.purchases p
      where p.user_id = v_user
    ), '[]'::jsonb),
    'archived_households', coalesce((
      select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'archived_at', h.archived_at)
        order by h.archived_at, h.id)
      from public.households h where h.archived_by = v_user
    ), '[]'::jsonb),
    'trips_logged', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', t.household_id,
        'store_name', t.store_name,
        'shopped_on', t.shopped_on,
        'items', (select jsonb_agg(jsonb_build_object('name', i ->> 'name', 'quantity', i -> 'quantity') order by o)
                  from jsonb_array_elements(t.items) with ordinality as x (i, o)),
        'created_at', t.created_at
      ) order by t.created_at, t.id)
      from public.trips t where t.logged_by = v_user
    ), '[]'::jsonb),
    'trip_sessions_started', coalesce((
      select jsonb_agg(
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium,detected_by,walked,mine}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'created_at', s.created_at)
        order by s.started_at, s.id)
      from public.trip_sessions s where s.started_by = v_user and s.source <> 'detected'
    ), '[]'::jsonb),
    'trips_detected', coalesce((
      select jsonb_agg(
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium,detected_by,walked,mine}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'walked', s.walked,
          'with_others', cardinality(s.detected_by) > 1,
          'created_at', s.created_at)
        -- A shared trip's clock times are the others' ticks too (N-321).
        || case when s.detected_by <> array[v_user] then
             '{"started_at": null, "ended_at": null, "pauses": null, "created_at": null}'::jsonb else '{}' end
        order by s.started_at, s.id)
      from public.trip_sessions s
      where s.source = 'detected' and s.removed_at is null and v_user = any(s.detected_by)
    ), '[]'::jsonb),
    'trip_detection', (
      select jsonb_build_object('on', p.detect_ticks_from is not null,
        'counts_ticks_from', case when isfinite(p.detect_ticks_from) then p.detect_ticks_from end,
        'card_seen_at', p.detected_card_at,
        'shops_declined', coalesce((
          select jsonb_agg(jsonb_build_object('household_id', d.household_id, 'item_name', e.item_name,
            'ticked_at', e.created_at, 'declined_at', d.declined_at, 'client_at', d.client_at)
            order by d.declined_at, d.id)
          from public.shop_declines d left join public.item_events e on e.id = d.tick_id
          where d.user_id = v_user), '[]'::jsonb))
      from public.trip_detection_settings p where p.user_id = v_user
    ),
    'tester_groups', coalesce((
      select jsonb_agg(jsonb_build_object('group_name', g.group_name, 'added_at', g.added_at)
        order by g.group_name collate "C")
      from public.tester_groups g where g.user_id = v_user
    ), '[]'::jsonb)
  );
end $$;

-- A detected trip stays detected: save_trip_session upserts by the client's id, and a save onto a
-- detected trip's id would turn it into a trip-mode trip that detection never replaces or removes.
create function public.trip_sessions_keep_detected() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.source = 'detected' and new.source is distinct from 'detected' then
    raise exception 'trip_not_found' using errcode = 'P0002';
  end if;
  return new;
end $$;
revoke execute on function public.trip_sessions_keep_detected() from public, anon, authenticated;
create trigger trip_sessions_keep_detected before update of source on public.trip_sessions
  for each row execute function public.trip_sessions_keep_detected();

-- An edit of a detected trip's log row (save_trip; History opens the trip sheet without trip mode)
-- freezes the trip, as a marked line does: the next run would otherwise replace it unedited.
create function public.trips_freeze_detected() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.trip_sessions s set frozen_at = now()
  where s.id = new.session_id and s.source = 'detected' and s.frozen_at is null;
  return null;
end $$;
revoke execute on function public.trips_freeze_detected() from public, anon, authenticated;
create trigger trips_freeze_detected after update of store_id, store_name, shopped_on, items on public.trips
  for each row when (new.session_id is not null) execute function public.trips_freeze_detected();
