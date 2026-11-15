-- Job 253: what refuses a call comes before the call's first lock.
--
-- These functions locked a row, or took a user's or a household's advisory lock, and then decided
-- whether the caller may do what they ask. They now decide first, by reading, and once more under
-- the lock, so what a call is told stays the same. A call that is refused no longer waits for
-- rows of a household the caller is not in, and never holds them. remove_member did this for the
-- caller's own role (20261108133253_households_invite_loop.sql); it now does it for every check.
--
-- lock_household_items runs as the writer of an item, so the app's role may call it. For that
-- role it takes the lock for a member of the household only. Every write of the app that reaches
-- it is a member's (the items policies), and the server's own writes take it as before.
--
-- Joining by a code follows the same rule (claim_invite, at the end): a guest who is told no, or
-- whose request is already open, is answered before the household's row lock.
--
-- Pinned by supabase/tests/refusals_take_no_locks.test.sql (a refused call takes no lock), by
-- supabase/functions/_shared/outsiders_integration_test.ts, which sweeps every function and table
-- the API roles may use from outside a household, and by
-- supabase/functions/_shared/checks_under_lock_integration_test.ts (the check under the lock).

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

create or replace function public.set_member_role(p_household uuid, p_user uuid, p_role text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_mine text;
  v_theirs text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_role is null or p_role not in ('admin', 'member') then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  -- Twice: before the household's row is locked, so only a change that goes through holds it,
  -- and under the lock.
  for v_round in 1 .. 2 loop
    if v_round = 2 then
      perform from public.households h where h.id = p_household for update;
    end if;
    v_mine := public.my_role_in(p_household);
    if v_mine is null then
      raise exception 'not_member' using errcode = '42501';
    elsif v_mine <> 'owner' then
      raise exception 'not_owner' using errcode = '42501';
    end if;
    select m.role into v_theirs from public.household_members m
    where m.household_id = p_household and m.user_id = p_user;
    if v_theirs is null then
      raise exception 'not_member' using errcode = '42501';
    elsif v_theirs = 'owner' then
      raise exception 'cannot_change_owner' using errcode = '42501';
    end if;
  end loop;
  update public.household_members m set role = p_role
  where m.household_id = p_household and m.user_id = p_user;
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
      -- leave_household_as's lock order: the removed user's memberships, then the household.
      perform public.lock_memberships(p_user);
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

create or replace function public.claim_item(p_item uuid, p_quantity text)
returns public.item_claims
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.items;
  v_quantity text := nullif(btrim(p_quantity), '');
  v_claim public.item_claims;
  v_household uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_quantity) > 40 then
    raise exception 'value_too_long: quantity <= 40 characters' using errcode = '22001';
  end if;
  -- Whose item it is, before the locks and again under them.
  select i.household_id into v_household from public.items i where i.id = p_item;
  if not found then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  -- The membership lock waits for a leave or removal in flight, the share lock for a tick or
  -- delete: a claim outlives none of them.
  perform public.lock_memberships(auth.uid());
  select * into v_item from public.items i where i.id = p_item for share;
  if not found then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_item.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_item.status <> 'active' then
    raise exception 'not_open' using errcode = '22023';
  end if;
  insert into public.item_claims as c (item_id, household_id, user_id, quantity)
  values (p_item, v_item.household_id, auth.uid(), v_quantity)
  on conflict (item_id, user_id) do update set quantity = excluded.quantity
    where c.quantity is distinct from excluded.quantity;
  select * into v_claim from public.item_claims c where c.item_id = p_item and c.user_id = auth.uid();
  return v_claim;
end $$;

create or replace function public.merge_items(p_merge uuid, p_keep uuid, p_other uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_done public.item_merges;
  v_keep public.items;
  v_other public.items;
  v_before jsonb;
begin
  if p_merge is null or p_keep is null or p_other is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  select * into v_done from public.item_merges where id = p_merge;
  if found then
    if not public.is_household_member(v_done.household_id) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
    return public.merge_result(v_done.kept_id, (v_done.merged_row ->> 'id')::uuid);
  end if;
  if p_keep = p_other then
    raise exception 'same_item' using errcode = '22023';
  end if;
  -- Whose items they are, before the locks and again under them.
  if exists (
    select from public.items i
    where i.id in (p_keep, p_other) and not public.is_household_member(i.household_id)
  ) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if (select count(*) from public.items i where i.id in (p_keep, p_other)) < 2 then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  -- Both rows locked in id order, so two merges of the same pair cannot deadlock.
  perform from public.items where id in (p_keep, p_other) order by id for update;
  select * into v_keep from public.items where id = p_keep;
  select * into v_other from public.items where id = p_other;
  if v_keep.id is null or v_other.id is null then
    if (v_keep.id is not null and not public.is_household_member(v_keep.household_id))
       or (v_other.id is not null and not public.is_household_member(v_other.household_id)) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_keep.household_id)
     or not public.is_household_member(v_other.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_keep.household_id <> v_other.household_id then
    raise exception 'other_household' using errcode = '22023';
  end if;
  if v_keep.status <> 'active' or v_other.status <> 'active' then
    raise exception 'not_open' using errcode = '22023';
  end if;

  v_before := public.item_row_without_price(to_jsonb(v_keep));
  perform set_config('family_groceries.learning', 'off', true);
  -- The other row goes first: with it still open, filling in its brand or details would give the
  -- kept row its key, which items_rename_duplicate refuses.
  delete from public.items where id = p_other;
  update public.items set
    quantity = public.merge_quantities(v_keep.quantity, v_other.quantity),
    brand = coalesce(v_keep.brand, v_other.brand),
    properties = coalesce(v_keep.properties, v_other.properties)
  where id = p_keep
  returning * into v_keep;
  perform set_config('family_groceries.learning', '', true);
  insert into public.item_merges (id, household_id, kept_id, kept_before, kept_after, merged_row)
  values (
    p_merge, v_keep.household_id, p_keep,
    v_before,
    jsonb_build_object('quantity', v_keep.quantity, 'brand', v_keep.brand, 'properties', v_keep.properties),
    public.item_row_without_price(to_jsonb(v_other))
  );
  return public.merge_result(p_keep, p_other);
end $$;

create or replace function public.unmerge_items(p_merge uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_merge public.item_merges;
  v_row public.items;
begin
  -- Twice: read, then locked.
  for v_round in 1 .. 2 loop
    if v_round = 1 then
      select * into v_merge from public.item_merges where id = p_merge;
    else
      select * into v_merge from public.item_merges where id = p_merge for update;
    end if;
    if not found then
      raise exception 'merge_not_found' using errcode = 'P0002';
    end if;
    if not public.is_household_member(v_merge.household_id) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
  end loop;
  if v_merge.undone_at is null then
    perform set_config('family_groceries.learning', 'off', true);
    update public.items i set
      quantity = v_merge.kept_before ->> 'quantity',
      brand = v_merge.kept_before ->> 'brand',
      properties = v_merge.kept_before ->> 'properties'
    where i.id = v_merge.kept_id
      and (i.quantity, i.brand, i.properties) is not distinct from
          (v_merge.kept_after ->> 'quantity', v_merge.kept_after ->> 'brand', v_merge.kept_after ->> 'properties');
    v_row := jsonb_populate_record(null::public.items, v_merge.merged_row);
    v_row.updated_at := now();
    if not exists (select from public.categories c where c.id = v_row.category_id and c.household_id = v_row.household_id) then
      v_row.category_id := null;
    end if;
    if not exists (select from public.stores s where s.id = v_row.store_id and s.household_id = v_row.household_id) then
      v_row.store_id := null;
    end if;
    if not exists (select from public.lists l where l.id = v_row.list_id and l.household_id = v_row.household_id) then
      v_row.list_id := null;
    end if;
    if not exists (select from auth.users u where u.id = v_row.added_by) then
      v_row.added_by := null;
    end if;
    insert into public.items select (v_row).* on conflict (id) do nothing;
    -- The insert trigger decides categorized_via afresh; the row had one already.
    update public.items i set categorized_via = v_row.categorized_via
    where i.id = v_row.id and i.categorized_via is distinct from v_row.categorized_via
      and i.category_id = v_row.category_id;
    perform set_config('family_groceries.learning', '', true);
    update public.item_merges set undone_at = now() where id = p_merge;
  end if;
  return public.merge_result(v_merge.kept_id, (v_merge.merged_row ->> 'id')::uuid);
end $$;

create or replace function public.revoke_invite(p_invite uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_invite public.invites;
begin
  -- Twice: read, then locked.
  for v_round in 1 .. 2 loop
    if v_round = 1 then
      select * into v_invite from public.invites i where i.id = p_invite;
    else
      select * into v_invite from public.invites i where i.id = p_invite for update;
    end if;
    if v_invite.id is null or not public.is_household_member(v_invite.household_id) then
      raise exception 'not_a_member' using errcode = '42501';
    elsif v_invite.kind = 'group' and public.my_role_in(v_invite.household_id) = 'member' then
      raise exception 'not_admin' using errcode = '42501';
    end if;
  end loop;
  update public.invites i set revoked_at = coalesce(i.revoked_at, now()) where i.id = p_invite;
end $$;

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

create or replace function public.delete_trip_session(p_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
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
      return;
    end if;
    if not public.is_household_member(v_household) then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
  end loop;
  delete from public.trips t where t.session_id = p_id and t.household_id = v_household;
  delete from public.trip_sessions s where s.id = p_id;
end $$;

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
    updated_at = now()
  where s.id = p_id
    and exists (select from jsonb_array_elements(s.lines) e
                where e ->> 'key' = p_key and (e -> 'marked_planned')::boolean is distinct from p_planned);
end $$;

create or replace function public.save_trip(
  p_household uuid,
  p_id uuid,
  p_store uuid,
  p_day date,
  p_items jsonb
)
returns public.trips
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.trips;
  v_store_name text;
  v_items jsonb;
  v_trip public.trips;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_id is null or p_day is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  -- Waits for a leave or removal in flight, whose trigger forgets the user in the trips.
  perform public.lock_memberships(auth.uid());
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  -- Another household's trip: refused before its row is locked, and again under the lock.
  if exists (select from public.trips t where t.id = p_id and t.household_id <> p_household) then
    raise exception 'other_household' using errcode = '22023';
  end if;
  select * into v_old from public.trips t where t.id = p_id for update;
  if found and v_old.household_id <> p_household then
    raise exception 'other_household' using errcode = '22023';
  end if;
  if p_store is not null then
    select s.name into v_store_name from public.stores s where s.id = p_store and s.household_id = p_household;
    if not found then
      raise exception 'store_not_found' using errcode = 'P0002';
    end if;
  elsif v_old.store_id is null then
    v_store_name := v_old.store_name;
  end if;
  if p_day > current_date + 1 then
    raise exception 'day_in_future' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'no_items' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'no_items' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 200 then
    raise exception 'too_many_items' using errcode = '22023';
  end if;
  if exists (
    select from jsonb_array_elements(p_items) e
    where jsonb_typeof(e) is distinct from 'object'
       or jsonb_typeof(e -> 'name') is distinct from 'string'
       or char_length(btrim(e ->> 'name')) not between 1 and 120
       or jsonb_typeof(coalesce(e -> 'quantity', 'null')) not in ('string', 'null')
       or char_length(btrim(e ->> 'quantity')) > 40
  ) then
    raise exception 'invalid_item' using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object(
    'name', btrim(e ->> 'name'),
    'quantity', nullif(btrim(e ->> 'quantity'), ''),
    'canonical_key', nullif(public.canonical_key(btrim(e ->> 'name')), '')
  ) order by o)
  into v_items
  from jsonb_array_elements(p_items) with ordinality as x (e, o);

  insert into public.trips as t (id, household_id, store_id, store_name, shopped_on, items, logged_by)
  values (p_id, p_household, p_store, v_store_name, p_day, v_items, auth.uid())
  on conflict (id) do update set
    store_id = excluded.store_id,
    store_name = excluded.store_name,
    shopped_on = excluded.shopped_on,
    items = excluded.items,
    updated_at = now()
  where (t.store_id, t.store_name, t.shopped_on, t.items)
    is distinct from (excluded.store_id, excluded.store_name, excluded.shopped_on, excluded.items);
  select * into v_trip from public.trips t where t.id = p_id;
  return v_trip;
end $$;

create or replace function public.save_trip_session(p_household uuid, p_trip jsonb, p_log boolean)
returns jsonb
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
  -- Another household's trip: refused before its row is locked, and again under the lock.
  if exists (
    select from public.trip_sessions s where s.id = v_row.id and s.household_id <> p_household
  ) then
    raise exception 'other_household' using errcode = '22023';
  end if;
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

-- One household's adds and renames, one after the other (20261019120000_item_dedupe.sql). The
-- app's role gets the lock for a household it is a member of; asked for another one, it gets
-- nothing and does not wait.
create or replace function public.lock_household_items(p_household uuid)
returns void
language sql set search_path = '' as $$
  select case when current_user <> 'authenticated' or public.is_household_member(p_household)
    then pg_advisory_xact_lock(hashtextextended('items:' || p_household::text, 0)) end;
$$;

-- Joining by a code. A guest who is told no (declined within the day, at the household cap) or
-- who repeats a request that is already open took the household's row lock first. They are now
-- answered before it. A first request and a join write to the household and take it as before.
--
-- The cap is refuse_household_over_cap's question. A join that adds a household (p_adding) or asks
-- for approval is stopped by it; one that replaces the user's default household leaves that one
-- first and has room. So the function needs to know which join it is: the two accept_invite
-- variants now say so, and the one-argument form stays for the replacing join.
create or replace function public.claim_invite(
  p_code text,
  p_adding boolean,
  out status text,
  out household_id uuid
)
language plpgsql security definer set search_path = '' as $$
-- The conflict target names the column, not the out parameter.
#variable_conflict use_column
declare
  v_check record;
  v_approval boolean;
begin
  select * into v_check from public.check_invite(p_code);
  if v_check.status = 'member' then
    status := 'member';
    household_id := v_check.household_id;
    return;
  elsif v_check.status <> 'ok' then
    status := v_check.status;
    return;
  end if;
  -- Twice: read, then under the household's row and the user's memberships.
  for v_round in 1 .. 2 loop
    if v_round = 1 then
      select h.join_approval into v_approval from public.households h
      where h.id = v_check.household_id and h.archived_at is null;
    else
      -- Its last member may be archiving it right now: wait for that, then don't join an
      -- archived one.
      select h.join_approval into v_approval from public.households h
      where h.id = v_check.household_id and h.archived_at is null
      for share;
    end if;
    if not found then
      status := 'invalid_invite';
      return;
    end if;
    if v_round = 2 then
      perform public.lock_memberships(auth.uid());
    end if;
    if public.is_household_member(v_check.household_id) then
      status := 'member';
      household_id := v_check.household_id;
      return;
    end if;
    -- A decline holds for a day: no new request until then, so a declined user can't ask again
    -- and again. household_id stays null, so the oldest builds' join_household answers null.
    if v_approval and exists (
      select from public.join_requests r
      where r.household_id = v_check.household_id and r.user_id = auth.uid()
        and r.decision = 'declined' and r.decided_at > now() - interval '24 hours'
    ) and not exists (
      select from public.join_requests r
      where r.household_id = v_check.household_id and r.user_id = auth.uid() and r.decision is null
    ) then
      status := 'declined_recently';
      return;
    end if;
    -- refuse_household_over_cap's question, asked here so that its no comes before the lock.
    -- Under the lock the trigger asks it, when the request or the membership goes in.
    if v_round = 1
       and (v_approval or p_adding or public.default_household_of(auth.uid()) is null)
       and (select count(*) from public.household_members m where m.user_id = auth.uid())
           >= public.household_cap() then
      raise exception 'too_many_households' using errcode = 'P0001';
    end if;
    -- Asked again through the same invite: the request stands as it is. An admin who decides it
    -- right now holds the asker's memberships (decide_join_request), so the asker's own lock waits
    -- for the decision, and the request is read under it. Decided meanwhile, the second round
    -- answers.
    if v_round = 1 and v_approval then
      for v_look in 1 .. 2 loop
        exit when not exists (
          select from public.join_requests r
          where r.household_id = v_check.household_id and r.user_id = auth.uid()
            and r.decision is null and r.invite_id = v_check.invite_id
        );
        if v_look = 2 then
          status := 'requested';
          household_id := v_check.household_id;
          return;
        end if;
        perform public.lock_memberships(auth.uid());
      end loop;
    end if;
  end loop;

  if v_approval then
    insert into public.join_requests (household_id, user_id, invite_id)
    values (v_check.household_id, auth.uid(), v_check.invite_id)
    -- A request waiting on a used-up invite moves to the newer one it was sent (invite_full).
    on conflict (household_id, user_id) where decision is null
    do update set invite_id = excluded.invite_id;
    status := 'requested';
    household_id := v_check.household_id;
    return;
  end if;

  update public.invites i set
    use_count = i.use_count + 1,
    used_at = case when i.use_count + 1 = i.max_uses then now() end,
    used_by = case when i.kind = 'person' then auth.uid() end
  where i.id = v_check.invite_id and i.use_count < i.max_uses and i.revoked_at is null
    and i.expires_at > now()
  returning i.household_id into household_id;
  if household_id is null then
    -- Lost the race to another user.
    delete from public.invite_attempts a where a.at < now() - interval '1 day';
    insert into public.invite_attempts (user_id) values (auth.uid());
    status := 'invalid_invite';
    return;
  end if;
  -- Someone who left and comes back through the same link keeps one row, with the new time.
  insert into public.invite_uses as u (invite_id, household_id, user_id)
  values (v_check.invite_id, v_check.household_id, auth.uid())
  on conflict (invite_id, user_id) do update set joined_at = now();
  -- check_invite let only an owner's or admin's invite made after the removal through: welcome back.
  delete from public.household_removals r
  where r.household_id = v_check.household_id and r.user_id = auth.uid();
  status := 'ok';
end $$;
revoke execute on function public.claim_invite(text, boolean) from public, anon, authenticated;

create or replace function public.claim_invite(p_code text, out status text, out household_id uuid)
language sql security definer set search_path = '' as $$
  select c.status, c.household_id from public.claim_invite(p_code, false) c
$$;

create or replace function public.accept_invite(p_code text, p_archive boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_claim record;
  v_previous text;
begin
  select * into v_claim from public.claim_invite(p_code, false);
  if v_claim.status <> 'ok' then
    return jsonb_build_object('status', v_claim.status, 'household_id', v_claim.household_id);
  end if;
  v_previous := public.leave_current_household(p_archive);
  insert into public.household_members (household_id, user_id, role)
  values (v_claim.household_id, auth.uid(), 'member');
  perform public.make_default_household(auth.uid(), v_claim.household_id);
  return jsonb_build_object('status', 'joined', 'household_id', v_claim.household_id, 'previous', v_previous);
end $$;

create or replace function public.accept_invite(p_code text, p_mode text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_claim record;
begin
  if p_mode is distinct from 'add' then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;
  select * into v_claim from public.claim_invite(p_code, true);
  if v_claim.status <> 'ok' then
    return jsonb_build_object('status', v_claim.status, 'household_id', v_claim.household_id);
  end if;
  insert into public.household_members (household_id, user_id, role)
  values (v_claim.household_id, auth.uid(), 'member');
  return jsonb_build_object('status', 'joined', 'household_id', v_claim.household_id);
end $$;
