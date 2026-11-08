-- Job 169b wave 3, part K: several lists per household (docs/households/W3.md). Stores,
-- categories and the classifier stay per household; an item belongs to one list. Every household
-- has at least one list: the migration gives each one "Einkaufsliste", a trigger gives every new
-- household its first list, and delete_list keeps the last one. Writers that know no list (old
-- store builds, Siri, Alexa, the API and MCP without a list) land in the household's first list:
-- a before-insert trigger fills items.list_id. The open-item duplicate rule (job 64) is per list.

-- Lists -------------------------------------------------------------------------------------------

create table public.lists (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  unique (id, household_id)
);
create index lists_household on public.lists (household_id, position, created_at);
alter table public.lists enable row level security;
revoke all on public.lists from public, anon, authenticated;
grant select on public.lists to authenticated;
create policy lists_member on public.lists for select to authenticated
  using (public.is_household_member(household_id));
alter publication supabase_realtime add table public.lists;

comment on table public.lists is
  'Job 169b: a household''s shopping lists. Written through create_list, rename_list, delete_list and move_list only.';

insert into public.lists (household_id, name, position, created_at, created_by)
select h.id, 'Einkaufsliste', 0, h.created_at, h.created_by from public.households h;

-- The list a write without one goes to: the household's first by position, then age.
create function public.first_list(p_household uuid) returns uuid
language sql stable set search_path = '' as $$
  select l.id from public.lists l
  where l.household_id = p_household
  order by l.position, l.created_at, l.id
  limit 1
$$;
revoke execute on function public.first_list(uuid) from public, anon;
grant execute on function public.first_list(uuid) to authenticated, service_role;

-- Every way a household comes about (create_household's signatures, fixtures, tests) gives it
-- its first list.
create function public.households_first_list() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.lists (household_id, name, position, created_at, created_by)
  values (new.id, 'Einkaufsliste', 0, new.created_at, new.created_by);
  return null;
end $$;
revoke execute on function public.households_first_list() from public, anon, authenticated;
create trigger households_first_list after insert on public.households
  for each row execute function public.households_first_list();

-- Items -------------------------------------------------------------------------------------------

alter table public.items add column list_id uuid;
-- The backfill touches no item's content: the triggers (updated_at, sort keys, history) stay out.
alter table public.items disable trigger user;
update public.items i set list_id = l.id from public.lists l where l.household_id = i.household_id;
alter table public.items enable trigger user;
-- squawk-ignore adding-not-nullable-field -- old store builds never send list_id: the items_fill_list trigger below fills every insert without one, so no released build's write fails
alter table public.items alter column list_id set not null;
alter table public.items add constraint items_list_fkey foreign key (list_id, household_id)
  references public.lists (id, household_id) on delete cascade;
create index items_list_idx on public.items (list_id);

-- Trigger order is by name: this runs after items_before_write and before items_skip_duplicate,
-- which needs the list.
create function public.items_fill_list() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.list_id := public.first_list(new.household_id);
  return new;
end $$;
revoke execute on function public.items_fill_list() from public, anon, authenticated;
create trigger items_fill_list before insert on public.items
  for each row when (new.list_id is null) execute function public.items_fill_list();

-- Job 64's rule, per list: the same name may be open on two lists.
create or replace function public.items_skip_duplicate() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_open uuid;
begin
  if new.status <> 'active' then
    return new;
  end if;
  perform public.lock_household_items(new.household_id);
  select i.id into v_open from public.items i
  where i.household_id = new.household_id
    and i.normalized_name = new.normalized_name
    and i.list_id = new.list_id
    and i.status = 'active'
    and i.id <> new.id
    and public.open_item_key(i.name, i.brand, i.properties)
      = public.open_item_key(new.name, new.brand, new.properties)
  order by i.created_at
  limit 1;
  if found then
    -- Read by put_item and add_item: the row this add is.
    perform set_config('family_groceries.open_duplicate', v_open::text, true);
    return null;
  end if;
  return new;
end $$;

-- Job 104's rename guard, per list, and for a move to another list too.
create or replace function public.items_rename_duplicate() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_key text;
begin
  if new.status <> 'active' then
    return new;
  end if;
  v_key := public.open_item_key(new.name, new.brand, new.properties);
  if v_key = public.open_item_key(old.name, old.brand, old.properties) and new.list_id = old.list_id then
    return new;
  end if;
  perform public.lock_household_items(new.household_id);
  if exists (
    select from public.items i
    where i.household_id = new.household_id
      and i.normalized_name = new.normalized_name
      and i.list_id = new.list_id
      and i.status = 'active'
      and i.id <> new.id
      and public.open_item_key(i.name, i.brand, i.properties) = v_key
  ) then
    raise exception 'already_on_list' using errcode = '23505',
      detail = 'Another open item on this list has this name, brand and details.';
  end if;
  return new;
end $$;
drop trigger items_rename_duplicate on public.items;
create trigger items_rename_duplicate before update of name, brand, properties, list_id on public.items
  for each row execute function public.items_rename_duplicate();

-- The new app's add: p_list (no default, so the old named call still reaches the old signature)
-- is the list shown. A list deleted while the add waited offline sends it to the first list.
create function public.put_item(
  p_id uuid,
  p_household uuid,
  p_list uuid,
  p_name text,
  p_quantity text default null,
  p_brand text default null,
  p_properties text default null,
  p_category uuid default null,
  p_store uuid default null,
  p_sort_key double precision default null,
  p_status text default 'active',
  p_no_store boolean default false
) returns setof public.items
language plpgsql set search_path = '' as $$
declare
  v_row public.items;
  v_list uuid := (
    select l.id from public.lists l where l.id = p_list and l.household_id = p_household
  );
begin
  perform set_config('family_groceries.open_duplicate', '', true);
  insert into public.items
    (id, household_id, list_id, name, quantity, brand, properties, category_id, store_id, sort_key,
     status)
  values
    (p_id, p_household, v_list, p_name, p_quantity, p_brand, p_properties, p_category, p_store,
     p_sort_key, p_status)
  on conflict (id) do nothing
  returning * into v_row;
  if found then
    if p_no_store and v_row.store_id is not null then
      update public.items set store_id = null where id = p_id returning * into v_row;
    end if;
    return next v_row;
    return;
  end if;
  return query select * from public.items where id = p_id;
  if found then
    return;
  end if;
  return query select * from public.items
    where id = nullif(current_setting('family_groceries.open_duplicate', true), '')::uuid;
end $$;
revoke execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean)
from public, anon;
grant execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean)
to authenticated;

-- Old store builds: the household's first list.
create or replace function public.put_item(
  p_id uuid,
  p_household uuid,
  p_name text,
  p_quantity text default null,
  p_brand text default null,
  p_properties text default null,
  p_category uuid default null,
  p_store uuid default null,
  p_sort_key double precision default null,
  p_status text default 'active',
  p_no_store boolean default false
) returns setof public.items
language sql set search_path = '' as $$
  select * from public.put_item(
    p_id => p_id, p_household => p_household, p_list => null, p_name => p_name,
    p_quantity => p_quantity, p_brand => p_brand, p_properties => p_properties,
    p_category => p_category, p_store => p_store, p_sort_key => p_sort_key, p_status => p_status,
    p_no_store => p_no_store)
$$;

-- The shared add path (MCP, the API, Siri, Alexa) with a list; null is the first list. Its own
-- name, not an add_item overload: the edge functions call add_item with untyped positional
-- parameters, which two overloads would make ambiguous.
create function public.add_list_item(
  p_household uuid,
  p_list uuid,
  p_text text,
  p_store uuid default null,
  p_brand text default null,
  p_properties text default null,
  p_quantity text default null
) returns setof public.items
language plpgsql set search_path = '' as $$
declare
  v_list uuid;
  v_parsed record;
  v_brand text;
  v_properties text;
  v_row public.items;
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if p_list is null then
    v_list := public.first_list(p_household);
  else
    select l.id into v_list from public.lists l where l.id = p_list and l.household_id = p_household;
    if v_list is null then
      raise exception 'list_not_found' using errcode = 'P0002';
    end if;
  end if;
  if char_length(btrim(p_brand)) > 60 or char_length(btrim(p_properties)) > 120 or char_length(btrim(p_quantity)) > 40 then
    raise exception 'value_too_long: brand <= 60, properties <= 120, quantity <= 40 characters'
      using errcode = '22001';
  end if;
  select * into v_parsed from public.parse_item(p_household, p_text);
  if v_parsed.name = '' then
    return;
  end if;
  v_brand := coalesce(p_brand, v_parsed.brand);
  v_properties := coalesce(p_properties, v_parsed.properties);
  perform public.lock_household_items(p_household);
  select * into v_row from public.items i
  where i.household_id = p_household and i.list_id = v_list and i.status = 'active'
    and public.item_name_key(concat_ws(' ', i.name, i.brand, i.properties))
      = public.item_name_key(concat_ws(' ', v_parsed.name, nullif(btrim(v_brand), ''), nullif(btrim(v_properties), '')))
  order by i.created_at
  limit 1;
  if found then
    return next v_row;
    return;
  end if;
  perform set_config('family_groceries.open_duplicate', '', true);
  insert into public.items (household_id, list_id, name, brand, properties, quantity, store_id)
  values (p_household, v_list, v_parsed.name, v_brand, v_properties,
          coalesce(p_quantity, v_parsed.quantity), coalesce(p_store, v_parsed.store_id))
  returning * into v_row;
  if found then
    return next v_row;
    return;
  end if;
  -- items_skip_duplicate found the same item with its details in another order.
  return query select * from public.items
    where id = nullif(current_setting('family_groceries.open_duplicate', true), '')::uuid;
end $$;
revoke execute on function public.add_list_item(uuid, uuid, text, uuid, text, text, text) from public, anon;
grant execute on function public.add_list_item(uuid, uuid, text, uuid, text, text, text)
  to authenticated, service_role;

-- The first list.
create or replace function public.add_item(
  p_household uuid,
  p_text text,
  p_store uuid default null,
  p_brand text default null,
  p_properties text default null,
  p_quantity text default null
) returns setof public.items
language sql set search_path = '' as $$
  select * from public.add_list_item(
    p_household => p_household, p_list => null, p_text => p_text, p_store => p_store,
    p_brand => p_brand, p_properties => p_properties, p_quantity => p_quantity)
$$;

-- Spelling variants and synonyms on the same list only, like the duplicate rule.
create or replace function public.similar_items(p_item uuid) returns setof public.items
language sql stable set search_path = '' as $$
  select o.* from public.items i
  join public.items o
    on o.household_id = i.household_id and o.list_id = i.list_id
      and o.canonical_key = i.canonical_key and o.id <> i.id
  where i.id = p_item and o.status = 'active' and coalesce(i.canonical_key, '') <> ''
    and not public.details_differ(i.brand, i.properties, o.brand, o.properties)
  order by o.created_at, o.id;
$$;

-- As in 20261030160000_dedupe_merge.sql; a merged row whose list is gone comes back on the first
-- list (items_fill_list), and one saved before this migration has no list_id at all.
create or replace function public.unmerge_items(p_merge uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_merge public.item_merges;
  v_row public.items;
begin
  select * into v_merge from public.item_merges where id = p_merge for update;
  if not found then
    raise exception 'merge_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_merge.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
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

-- History ----------------------------------------------------------------------------------------

-- The item's list at the time, for history; no foreign key, so a deleted list's history stays.
alter table public.item_events add column list_id uuid;
update public.item_events e set list_id = l.id from public.lists l where l.household_id = e.household_id;

create or replace function public.items_log_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.items := case when tg_op = 'DELETE' then old else new end;
  v_action text;
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
  insert into public.item_events (household_id, item_id, action, item_name, category_id, list_id)
  values (v_row.household_id, v_row.id, v_action, v_row.name, v_row.category_id, v_row.list_id);
  return null;
end $$;

-- The lists' interface ---------------------------------------------------------------------------

-- Serializes list changes of one household: positions, the last-list check.
create function public.lock_household_lists(p_household uuid) returns void
language sql set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('lists:' || p_household::text, 0))
$$;
revoke execute on function public.lock_household_lists(uuid) from public, anon, authenticated;

create function public.list_name(p_name text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
begin
  if char_length(v_name) not between 1 and 60 then
    raise exception 'invalid_name' using errcode = '22023', detail = 'A list name has 1 to 60 characters.';
  end if;
  return v_name;
end $$;
revoke execute on function public.list_name(text) from public, anon, authenticated;

-- A list the caller's household has, locked for a change; list_not_found when there is no such
-- list, not_a_member when it is another household's.
create function public.list_to_change(p_list uuid) returns public.lists
language plpgsql security definer set search_path = '' as $$
declare
  v_list public.lists;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_list from public.lists l where l.id = p_list;
  if not found then
    raise exception 'list_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_list.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  perform public.lock_household_lists(v_list.household_id);
  select * into v_list from public.lists l where l.id = p_list;
  if not found then
    raise exception 'list_not_found' using errcode = 'P0002';
  end if;
  return v_list;
end $$;
revoke execute on function public.list_to_change(uuid) from public, anon, authenticated;

-- A new list at the end. p_id is the app's id: a retry with it returns the same list.
-- At most 50 lists per household (too_many_lists), an abuse guard.
create function public.create_list(p_household uuid, p_name text, p_id uuid) returns public.lists
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := public.list_name(p_name);
  v_list public.lists;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_id is null then
    raise exception 'id_required' using errcode = '22023';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  perform public.lock_household_lists(p_household);
  select * into v_list from public.lists l where l.id = p_id;
  if found then
    if v_list.household_id <> p_household then
      raise exception 'not_a_member' using errcode = '42501';
    end if;
    return v_list;
  end if;
  if (select count(*) from public.lists l where l.household_id = p_household) >= 50 then
    raise exception 'too_many_lists' using errcode = 'P0001';
  end if;
  insert into public.lists (id, household_id, name, position, created_by)
  values (
    p_id, p_household, v_name,
    coalesce((select max(l.position) + 1 from public.lists l where l.household_id = p_household), 0),
    auth.uid()
  )
  returning * into v_list;
  return v_list;
end $$;
revoke execute on function public.create_list(uuid, text, uuid) from public, anon;
grant execute on function public.create_list(uuid, text, uuid) to authenticated;

create function public.rename_list(p_list uuid, p_name text) returns public.lists
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := public.list_name(p_name);
  v_list public.lists := public.list_to_change(p_list);
begin
  update public.lists l set name = v_name where l.id = v_list.id and l.name <> v_name;
  select * into v_list from public.lists l where l.id = p_list;
  return v_list;
end $$;
revoke execute on function public.rename_list(uuid, text) from public, anon;
grant execute on function public.rename_list(uuid, text) to authenticated;

-- Deletes a list with its items (and their claims). A list already gone is done; the household's
-- only list is not deleted (last_list).
create function public.delete_list(p_list uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_list public.lists;
begin
  if not exists (select from public.lists l where l.id = p_list) then
    return;
  end if;
  v_list := public.list_to_change(p_list);
  if not exists (
    select from public.lists l where l.household_id = v_list.household_id and l.id <> v_list.id
  ) then
    raise exception 'last_list' using errcode = 'P0001';
  end if;
  delete from public.lists l where l.id = v_list.id;
end $$;
revoke execute on function public.delete_list(uuid) from public, anon;
grant execute on function public.delete_list(uuid) to authenticated;

-- Puts a list at [p_position] (0 is first; past the end is last) and numbers the household's
-- lists 0, 1, 2... in their order.
create function public.move_list(p_list uuid, p_position integer) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_list public.lists := public.list_to_change(p_list);
begin
  if p_position is null then
    raise exception 'invalid_position' using errcode = '22023';
  end if;
  with others as (
    select x.id, (row_number() over (order by x.position, x.created_at, x.id) - 1)::int as i
    from public.lists x
    where x.household_id = v_list.household_id and x.id <> v_list.id
  ), target as (
    select least(greatest(p_position, 0), (select count(*) from others))::int as p
  ), ranked as (
    select o.id, case when o.i < t.p then o.i else o.i + 1 end as position from others o, target t
    union all
    select v_list.id, t.p from target t
  )
  update public.lists l set position = r.position
  from ranked r
  where l.id = r.id and l.position <> r.position;
end $$;
revoke execute on function public.move_list(uuid, integer) from public, anon;
grant execute on function public.move_list(uuid, integer) to authenticated;
