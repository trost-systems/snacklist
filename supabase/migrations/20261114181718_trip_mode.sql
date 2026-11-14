-- Job 234: trip mode. A finished shopping trip (a "session": start, end, pauses, and the summary's
-- lines, what was planned and what came in since) as the app computed it at the end. The running
-- trip lives on the device only; the server learns of it when it ends.
-- Written through save_trip_session, mark_trip_line_planned and delete_trip_session, read through
-- trip_session only (which withholds the lines without Premium, PB3a). Not in the realtime
-- publication, not on the public API or MCP.
--
-- With the grocery log (p_log), a save also writes one public.trips row per store of the bought
-- lines, linked by trips.session_id. Its id is md5(<session id> ':' <store id>)::uuid, for a gone
-- store md5(<session id> ':name:' <store name>), without a store md5(<session id> ':-'): a
-- re-save ("Weiter einkaufen", then Beenden again, or a retried save) updates the same rows.

create table public.trip_sessions (
  id uuid primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  -- No foreign key: a list deleted before a retried save must not make the save fail forever.
  list_id uuid,
  started_by uuid references auth.users (id) on delete set null default auth.uid(),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  active_seconds integer not null check (active_seconds >= 0),
  end_reason text not null check (end_reason in ('user', 'auto')),
  source text not null check (source in ('ask', 'manual')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  shopped_on date not null,
  pauses jsonb not null default '[]' check (jsonb_typeof(pauses) = 'array'),
  lines jsonb not null default '[]'
    check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) <= 400),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at >= started_at),
  unique (id, household_id)
);
create index trip_sessions_household on public.trip_sessions (household_id, started_at desc);
alter table public.trip_sessions enable row level security;
revoke all on public.trip_sessions from public, anon, authenticated;
-- No grant: the policy stays so that a grant added later still keeps households apart.
create policy trip_sessions_member on public.trip_sessions for select to authenticated
  using (public.is_household_member(household_id));

comment on table public.trip_sessions is
  'Job 234: finished shopping trips (times, pauses, what was planned and what came in). Who started it and who added a line are nulled when they leave or delete the account.';

alter table public.trips add column session_id uuid;
alter table public.trips add constraint trips_session_fkey
  foreign key (session_id, household_id) references public.trip_sessions (id, household_id)
  on delete set null (session_id);
-- squawk-ignore require-concurrent-index-creation -- the column is new and empty, so the build is instant
create index trips_session on public.trips (session_id) where session_id is not null;
comment on column public.trips.session_id is
  'Job 234: the trip-mode session this log entry was written by (one per store); null for a trip logged by hand.';

-- [p_trip] as a trip_sessions row of [p_household], or an error: invalid_trip (a field missing or
-- of the wrong kind, an end before the start, more active time than the trip lasted),
-- too_many_lines (over 400), invalid_line (a line without a key of 1 to 64 characters or a name
-- of 1 to 120, a quantity over 40, a store name over 60, cents beyond +-999999, a key twice),
-- day_in_future (a day after tomorrow). Names and quantities are trimmed; a line's added_by stays
-- only while that user is a member of the household. The JSON is FinishedTrip.toJson in
-- app/lib/trip/model.dart.
create function public.trip_session_from_json(p_household uuid, p_trip jsonb)
returns public.trip_sessions
language plpgsql stable set search_path = '' as $$
declare
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_row public.trip_sessions;
begin
  if jsonb_typeof(p_trip) is distinct from 'object'
     or jsonb_typeof(p_trip -> 'id') is distinct from 'string' or p_trip ->> 'id' !~ c_uuid
     or jsonb_typeof(coalesce(p_trip -> 'list_id', 'null')) not in ('string', 'null')
     or coalesce(p_trip ->> 'list_id', '00000000-0000-0000-0000-000000000000') !~ c_uuid
     or jsonb_typeof(p_trip -> 'started_at') is distinct from 'string'
     or jsonb_typeof(p_trip -> 'ended_at') is distinct from 'string'
     or jsonb_typeof(p_trip -> 'active_seconds') is distinct from 'number'
     or p_trip ->> 'end_reason' is null or p_trip ->> 'end_reason' not in ('user', 'auto')
     or p_trip ->> 'source' is null or p_trip ->> 'source' not in ('ask', 'manual')
     or jsonb_typeof(p_trip -> 'currency') is distinct from 'string'
     or p_trip ->> 'currency' !~ '^[A-Z]{3}$'
     or jsonb_typeof(p_trip -> 'shopped_on') is distinct from 'string'
     or jsonb_typeof(coalesce(p_trip -> 'pauses', '[]')) is distinct from 'array'
     or jsonb_array_length(coalesce(p_trip -> 'pauses', '[]')) > 200
     or jsonb_typeof(p_trip -> 'lines') is distinct from 'array'
     or exists (
       select from jsonb_array_elements(coalesce(p_trip -> 'pauses', '[]')) p
       where jsonb_typeof(p) is distinct from 'object'
          or jsonb_typeof(p -> 'from') is distinct from 'string'
          or jsonb_typeof(coalesce(p -> 'to', 'null')) not in ('string', 'null')
          or jsonb_typeof(coalesce(p -> 'auto', 'false')) is distinct from 'boolean')
  then
    raise exception 'invalid_trip' using errcode = '22023';
  end if;
  if jsonb_array_length(p_trip -> 'lines') > 400 then
    raise exception 'too_many_lines' using errcode = '22023';
  end if;
  if exists (
    select from jsonb_array_elements(p_trip -> 'lines') e
    where jsonb_typeof(e) is distinct from 'object'
       or jsonb_typeof(e -> 'key') is distinct from 'string'
       or char_length(e ->> 'key') not between 1 and 64
       or jsonb_typeof(e -> 'name') is distinct from 'string'
       or char_length(btrim(e ->> 'name')) not between 1 and 120
       or jsonb_typeof(e -> 'planned') is distinct from 'boolean'
       or jsonb_typeof(e -> 'bought') is distinct from 'boolean'
       or jsonb_typeof(coalesce(e -> 'quantity', 'null')) not in ('string', 'null')
       or char_length(btrim(e ->> 'quantity')) > 40
       or jsonb_typeof(coalesce(e -> 'store_id', 'null')) not in ('string', 'null')
       or e ->> 'store_id' !~ c_uuid
       or jsonb_typeof(coalesce(e -> 'store_name', 'null')) not in ('string', 'null')
       or char_length(btrim(e ->> 'store_name')) > 60
       or jsonb_typeof(coalesce(e -> 'marked_planned', 'false')) is distinct from 'boolean'
       or jsonb_typeof(coalesce(e -> 'by_other', 'false')) is distinct from 'boolean'
       or jsonb_typeof(coalesce(e -> 'added_by', 'null')) not in ('string', 'null')
       or e ->> 'added_by' !~ c_uuid
       or case jsonb_typeof(coalesce(e -> 'planned_cents', 'null'))
            when 'null' then false
            when 'number' then (e ->> 'planned_cents')::numeric <> trunc((e ->> 'planned_cents')::numeric)
                            or abs((e ->> 'planned_cents')::numeric) > 999999
            else true end
       or case jsonb_typeof(coalesce(e -> 'paid_cents', 'null'))
            when 'null' then false
            when 'number' then (e ->> 'paid_cents')::numeric <> trunc((e ->> 'paid_cents')::numeric)
                            or abs((e ->> 'paid_cents')::numeric) > 999999
            else true end
  ) or (
    select count(distinct e ->> 'key') <> count(*) from jsonb_array_elements(p_trip -> 'lines') e
  ) then
    raise exception 'invalid_line' using errcode = '22023';
  end if;

  begin
    v_row.started_at := (p_trip ->> 'started_at')::timestamptz;
    v_row.ended_at := (p_trip ->> 'ended_at')::timestamptz;
    v_row.shopped_on := (p_trip ->> 'shopped_on')::date;
    v_row.pauses := coalesce((
      select jsonb_agg(jsonb_build_object(
        'from', (p ->> 'from')::timestamptz,
        'to', (p ->> 'to')::timestamptz,
        'auto', coalesce((p -> 'auto')::boolean, false)
      ) order by o)
      from jsonb_array_elements(coalesce(p_trip -> 'pauses', '[]')) with ordinality as x (p, o)
    ), '[]');
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_trip' using errcode = '22023';
  end;
  if not isfinite(v_row.started_at) or not isfinite(v_row.ended_at) or not isfinite(v_row.shopped_on)
     or exists (
       select from jsonb_array_elements(v_row.pauses) p
       where not isfinite((p ->> 'from')::timestamptz) or not isfinite((p ->> 'to')::timestamptz))
  then
    raise exception 'invalid_trip' using errcode = '22023';
  end if;
  if (p_trip ->> 'active_seconds')::numeric <> trunc((p_trip ->> 'active_seconds')::numeric)
     or (p_trip ->> 'active_seconds')::numeric < 0
     or (p_trip ->> 'active_seconds')::numeric > 2147483647
     or v_row.ended_at < v_row.started_at
     or (p_trip ->> 'active_seconds')::numeric > ceil(extract(epoch from v_row.ended_at - v_row.started_at))
     or exists (
       select from jsonb_array_elements(v_row.pauses) p
       where (p ->> 'to')::timestamptz < (p ->> 'from')::timestamptz)
  then
    raise exception 'invalid_trip' using errcode = '22023';
  end if;
  if v_row.shopped_on > current_date + 1 then
    raise exception 'day_in_future' using errcode = '22023';
  end if;

  v_row.id := (p_trip ->> 'id')::uuid;
  v_row.household_id := p_household;
  v_row.list_id := (p_trip ->> 'list_id')::uuid;
  v_row.active_seconds := (p_trip ->> 'active_seconds')::integer;
  v_row.end_reason := p_trip ->> 'end_reason';
  v_row.source := p_trip ->> 'source';
  v_row.currency := p_trip ->> 'currency';
  v_row.lines := coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', e ->> 'key',
      'name', btrim(e ->> 'name'),
      'planned', (e -> 'planned')::boolean,
      'bought', (e -> 'bought')::boolean,
      'quantity', nullif(btrim(e ->> 'quantity'), ''),
      'store_id', (e ->> 'store_id')::uuid,
      'store_name', nullif(btrim(e ->> 'store_name'), ''),
      'marked_planned', coalesce((e -> 'marked_planned')::boolean, false),
      'by_other', coalesce((e -> 'by_other')::boolean, false),
      'added_by', (select m.user_id from public.household_members m
                   where m.household_id = p_household and m.user_id = (e ->> 'added_by')::uuid),
      'planned_cents', (e ->> 'planned_cents')::integer,
      'paid_cents', (e ->> 'paid_cents')::integer
    ) order by o)
    from jsonb_array_elements(p_trip -> 'lines') with ordinality as x (e, o)
  ), '[]');
  return v_row;
end $$;
revoke execute on function public.trip_session_from_json(uuid, jsonb) from public, anon, authenticated;

-- [p_session] as trip_session answers: the row's columns, pauses, lines (null unless
-- [p_premium]), bought (how many lines were ticked off) and stores (the bought lines' store
-- names: the household's stores in their order, then gone stores by name, then null for the
-- lines without a store), and premium.
create function public.trip_session_json(p_session public.trip_sessions, p_premium boolean) returns jsonb
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
    'premium', p_premium
  )
$$;
revoke execute on function public.trip_session_json(public.trip_sessions, boolean) from public, anon, authenticated;

-- Saves session [p_trip] (FinishedTrip.toJson) of [p_household] by its id: creates it, or replaces
-- everything but who started it and when it was created; the same call twice changes nothing.
-- With [p_log], also logs it: one trips row per store of the bought lines (store name as now,
-- items the bought lines' names and quantities in line order, at most 200, on shopped_on), and
-- deletes the session's rows of stores no longer bought from. Without it the log is untouched.
-- Returns the session as trip_session does.
-- Errors: not_authenticated, missing_argument, not_a_member, other_household (the id is another
-- household's session), and those of trip_session_from_json.
create function public.save_trip_session(p_household uuid, p_trip jsonb, p_log boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.trip_sessions;
  v_row public.trip_sessions;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_household is null or p_trip is null or p_log is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  -- Waits for a leave or removal in flight, whose trigger forgets the user in the sessions.
  perform public.lock_memberships(auth.uid());
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  v_row := public.trip_session_from_json(p_household, p_trip);
  select * into v_old from public.trip_sessions s where s.id = v_row.id for update;
  if found and v_old.household_id <> p_household then
    raise exception 'other_household' using errcode = '22023';
  end if;

  insert into public.trip_sessions as s (id, household_id, list_id, started_at, ended_at,
    active_seconds, end_reason, source, currency, shopped_on, pauses, lines)
  values (v_row.id, p_household, v_row.list_id, v_row.started_at, v_row.ended_at,
    v_row.active_seconds, v_row.end_reason, v_row.source, v_row.currency, v_row.shopped_on,
    v_row.pauses, v_row.lines)
  on conflict (id) do update set
    list_id = excluded.list_id,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    active_seconds = excluded.active_seconds,
    end_reason = excluded.end_reason,
    source = excluded.source,
    currency = excluded.currency,
    shopped_on = excluded.shopped_on,
    pauses = excluded.pauses,
    lines = excluded.lines,
    updated_at = now()
  where (s.list_id, s.started_at, s.ended_at, s.active_seconds, s.end_reason, s.source, s.currency,
         s.shopped_on, s.pauses, s.lines)
    is distinct from (excluded.list_id, excluded.started_at, excluded.ended_at,
         excluded.active_seconds, excluded.end_reason, excluded.source, excluded.currency,
         excluded.shopped_on, excluded.pauses, excluded.lines);

  if p_log then
    with bought as (
      select e, o, st.id as store_id, st.name as store_name,
        case when st.id is null then e ->> 'store_name' end as gone_name
      from jsonb_array_elements(v_row.lines) with ordinality as x (e, o)
      left join public.stores st on st.id = (e ->> 'store_id')::uuid and st.household_id = p_household
      where (e ->> 'bought')::boolean
    ), numbered as (
      select b.*, row_number() over (partition by b.store_id, b.gone_name order by b.o) as n
      from bought b
    ), stores as (
      select md5(v_row.id::text || ':' || coalesce(n.store_id::text, 'name:' || n.gone_name, '-'))::uuid as id,
        n.store_id, coalesce(n.store_name, n.gone_name) as store_name,
        jsonb_agg(jsonb_build_object(
          'name', n.e ->> 'name',
          'quantity', n.e -> 'quantity',
          'canonical_key', nullif(public.canonical_key(n.e ->> 'name'), '')
        ) order by n.o) as items
      from numbered n where n.n <= 200
      group by n.store_id, n.gone_name, n.store_name
    ), logged as (
      insert into public.trips as t (id, household_id, store_id, store_name, shopped_on, items, session_id)
      select st.id, p_household, st.store_id, st.store_name, v_row.shopped_on, st.items, v_row.id
      from stores st
      on conflict (id) do update set
        store_id = excluded.store_id,
        store_name = excluded.store_name,
        shopped_on = excluded.shopped_on,
        items = excluded.items,
        session_id = excluded.session_id,
        updated_at = now()
      where t.household_id = excluded.household_id
        and (t.store_id, t.store_name, t.shopped_on, t.items, t.session_id)
          is distinct from (excluded.store_id, excluded.store_name, excluded.shopped_on,
                            excluded.items, excluded.session_id)
      returning t.id
    )
    delete from public.trips t
    where t.session_id = v_row.id and t.household_id = p_household
      and t.id not in (select st.id from stores st);
  end if;

  select * into v_row from public.trip_sessions s where s.id = v_row.id;
  return public.trip_session_json(v_row,
    public.household_has_premium(p_household) or public.user_has_premium(auth.uid()));
end $$;
revoke execute on function public.save_trip_session(uuid, jsonb, boolean) from public, anon;
grant execute on function public.save_trip_session(uuid, jsonb, boolean) to authenticated;

-- Session [p_id] of [p_household] for a member (the shape is trip_session_json's). Premium is the
-- household's or the user's own, as in trip_history.
-- Errors: not_authenticated, missing_argument, not_a_member, trip_not_found.
create function public.trip_session(p_household uuid, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.trip_sessions;
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
  select * into v_row from public.trip_sessions s where s.id = p_id and s.household_id = p_household;
  if not found then
    raise exception 'trip_not_found' using errcode = 'P0002';
  end if;
  return public.trip_session_json(v_row,
    public.household_has_premium(p_household) or public.user_has_premium(auth.uid()));
end $$;
revoke execute on function public.trip_session(uuid, uuid) from public, anon;
grant execute on function public.trip_session(uuid, uuid) to authenticated;

-- "War geplant": marks line [p_key] of session [p_id] as planned or not. An unknown key changes
-- nothing. Errors: not_authenticated, missing_argument, trip_not_found, not_a_member,
-- premium_required.
create function public.mark_trip_line_planned(p_id uuid, p_key text, p_planned boolean) returns void
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
  select s.household_id into v_household from public.trip_sessions s where s.id = p_id for update;
  if not found then
    raise exception 'trip_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
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
    updated_at = now()
  where s.id = p_id
    and exists (select from jsonb_array_elements(s.lines) e
                where e ->> 'key' = p_key and (e -> 'marked_planned')::boolean is distinct from p_planned);
end $$;
revoke execute on function public.mark_trip_line_planned(uuid, text, boolean) from public, anon;
grant execute on function public.mark_trip_line_planned(uuid, text, boolean) to authenticated;

-- Deletes session [p_id] and its log entries; a missing one is no error, so a retry succeeds.
create function public.delete_trip_session(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
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
revoke execute on function public.delete_trip_session(uuid) from public, anon;
grant execute on function public.delete_trip_session(uuid) to authenticated;

-- Deleting the last log entry of a session deletes the session too. Otherwise unchanged from
-- 20261113070349_grocery_log.sql.
create or replace function public.delete_trip(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_session uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select t.household_id, t.session_id into v_household, v_session
  from public.trips t where t.id = p_id for update;
  if not found then
    return;
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  delete from public.trips t where t.id = p_id;
  if v_session is not null
     and not exists (select from public.trips t where t.session_id = v_session) then
    delete from public.trip_sessions s where s.id = v_session;
  end if;
end $$;

-- A line's added_by without [p_user]: the forgetting below and on account deletion.
create function public.trip_lines_forget_user(p_lines jsonb, p_user text) returns jsonb
language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(case when e ->> 'added_by' = p_user
                                 then e || '{"added_by": null}'::jsonb else e end order by o), '[]')
  from jsonb_array_elements(p_lines) with ordinality as x (e, o)
$$;
revoke execute on function public.trip_lines_forget_user(jsonb, text) from public, anon, authenticated;

-- Leaving or being removed also forgets who started the household's trip sessions and who added
-- their lines. Otherwise unchanged from 20261113070349_grocery_log.sql.
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
    lines = public.trip_lines_forget_user(s.lines, v_user)
  where s.household_id = old.household_id
    and (s.started_by = old.user_id
         or s.lines @> jsonb_build_array(jsonb_build_object('added_by', v_user)));
  update public.households h set created_by = null
  where h.id = old.household_id and h.created_by = old.user_id;
  return null;
end $$;

-- Account deletion: the deleted user's id leaves the lines too (started_by is set null by its
-- foreign key). The membership trigger above does it in the households that stay, this one also
-- where nobody is left (an auth.users delete from the dashboard leaves such a household behind).
create function public.trip_sessions_forget_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_user text := old.id::text;
begin
  update public.trip_sessions s set lines = public.trip_lines_forget_user(s.lines, v_user)
  where s.lines @> jsonb_build_array(jsonb_build_object('added_by', v_user));
  return null;
end $$;
revoke execute on function public.trip_sessions_forget_user() from public, anon, authenticated;

create trigger trip_sessions_forget_user
  after delete on auth.users
  for each row execute function public.trip_sessions_forget_user();


-- The export adds the trip sessions the user started: times, duration, pauses, stores and lines,
-- without item, store or other members' ids. Otherwise unchanged from
-- 20261113221639_default_list.sql.
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
        'created_at', e.created_at
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
        'is_internal', f.is_internal
      ) order by f.created_at, f.id)
      from public.feedback f
      where f.user_id = v_user
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
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'created_at', s.created_at)
        order by s.started_at, s.id)
      from public.trip_sessions s where s.started_by = v_user
    ), '[]'::jsonb)
  );
end $$;
