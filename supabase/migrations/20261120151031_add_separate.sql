-- Job 324 (AM2, flag add-match-rows): the add sheet shows the items already on the list that are
-- the same thing as the typed text, and its + row (or Enter) adds the typed item as a separate
-- item next to them, also when it is the same name, brand and details. The app asks for that per
-- call with p_separate; old builds and the flag off send nothing and keep job 64's rule (the add
-- answers with the open item it already is).
--
-- - put_item (both signatures) gains p_separate: when on, the insert runs with the
--   transaction-local setting family_groceries.separate = 'on', cleared right after it, as
--   p_category_store does with family_groceries.category_store.
-- - items_skip_duplicate lets the row in when that setting is 'on'. Plain inserts, add_item (MCP,
--   Siri, Alexa) and the rename guard are unchanged.
--
-- Pinned by supabase/tests/add_separate.test.sql.

create or replace function public.items_skip_duplicate() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_open uuid;
begin
  if new.status <> 'active' or current_setting('family_groceries.separate', true) = 'on' then
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

revoke execute on function public.items_skip_duplicate() from public, anon;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean);

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
  p_no_store boolean default false,
  p_category_store boolean default false,
  p_separate boolean default false
) returns setof public.items
language plpgsql set search_path = '' as $$
declare
  v_row public.items;
  v_added boolean;
  v_list uuid := (
    select l.id from public.lists l where l.id = p_list and l.household_id = p_household
  );
begin
  perform set_config('family_groceries.open_duplicate', '', true);
  perform set_config('family_groceries.category_store', case when p_category_store then 'on' else '' end, true);
  perform set_config('family_groceries.no_store', case when p_category_store and p_no_store then 'on' else '' end, true);
  perform set_config('family_groceries.separate', case when p_separate then 'on' else '' end, true);
  insert into public.items
    (id, household_id, list_id, name, quantity, brand, properties, category_id, store_id, sort_key,
     status)
  values
    (p_id, p_household, v_list, p_name, p_quantity, p_brand, p_properties, p_category, p_store,
     p_sort_key, p_status)
  on conflict (id) do nothing
  returning * into v_row;
  v_added := found;
  perform set_config('family_groceries.category_store', '', true);
  perform set_config('family_groceries.no_store', '', true);
  perform set_config('family_groceries.separate', '', true);
  if v_added then
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

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean);

create function public.put_item(
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
  p_no_store boolean default false,
  p_category_store boolean default false,
  p_separate boolean default false
) returns setof public.items
language sql set search_path = '' as $$
  select * from public.put_item(
    p_id => p_id, p_household => p_household, p_list => null, p_name => p_name,
    p_quantity => p_quantity, p_brand => p_brand, p_properties => p_properties,
    p_category => p_category, p_store => p_store, p_sort_key => p_sort_key, p_status => p_status,
    p_no_store => p_no_store, p_category_store => p_category_store, p_separate => p_separate)
$$;

revoke execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean)
from public, anon;
grant execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean)
to authenticated, service_role;
