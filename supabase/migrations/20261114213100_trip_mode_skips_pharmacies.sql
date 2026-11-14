-- Job 246: Legal GL-2 for trip mode. Nothing bought at a pharmacy is logged unless the user logs
-- it by hand (save_trip). A trip-mode session dropped no line: its pharmacy lines (with prices and
-- who added them) stayed in trip_sessions, and with the grocery log save_trip_session wrote a
-- trips row for the pharmacy too. Now save_trip_session drops a pharmacy's lines before it stores
-- or logs anything, so old apps are covered, and the sessions and automatic log rows already
-- stored lose them. The app drops them too (finishTrip, app/lib/trip/summary.dart).

-- Whether [p_words] (a store's name, seed key or both) names a pharmacy: the six words of
-- Store.pharmacyWords (app/lib/list/model.dart), in any case. Drugstores (dm, Rossmann) are not.
create function public.is_pharmacy_store(p_words text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(p_words, '') ~* '(apotheke|pharmacy|pharmacie|farmacia|apteka|eczane)'
$$;
revoke execute on function public.is_pharmacy_store(text) from public, anon, authenticated;

-- [p_lines] (trip_sessions.lines of [p_household]) without the lines of a pharmacy: by the
-- household's store of the line (its name and seed key now) or by the store name the line carries.
create function public.trip_lines_without_pharmacy(p_household uuid, p_lines jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(e order by o), '[]')
  from jsonb_array_elements(p_lines) with ordinality as x (e, o)
  left join public.stores st on st.id = (e ->> 'store_id')::uuid and st.household_id = p_household
  where not public.is_pharmacy_store(concat_ws(' ', st.name, st.seed_key, e ->> 'store_name'))
$$;
revoke execute on function public.trip_lines_without_pharmacy(uuid, jsonb) from public, anon, authenticated;

-- As in 20261114181718_trip_mode.sql, with a pharmacy's lines dropped from the session, and so
-- from its log rows.
create or replace function public.save_trip_session(p_household uuid, p_trip jsonb, p_log boolean) returns jsonb
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
  v_row.lines := public.trip_lines_without_pharmacy(p_household, v_row.lines);
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

update public.trip_sessions s set
  lines = public.trip_lines_without_pharmacy(s.household_id, s.lines),
  updated_at = now()
where s.lines <> public.trip_lines_without_pharmacy(s.household_id, s.lines);

delete from public.trips t
where t.session_id is not null
  and public.is_pharmacy_store(concat_ws(' ', t.store_name, (
    select concat_ws(' ', st.name, st.seed_key) from public.stores st
    where st.id = t.store_id and st.household_id = t.household_id)));
