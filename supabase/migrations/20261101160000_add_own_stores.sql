-- Job 58: the household adds, renames and deletes its own stores (add_store, rename_store,
-- delete_store). Store names are unique per household ignoring case and spacing; a new store
-- starts from the household's route order, every category shown. Decisions: docs/DECISIONS.md,
-- "Job 58".

-- The identity of a store name: trimmed, inner whitespace collapsed, case folded.
create function public.store_name_key(p_name text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(btrim(p_name), '\s+', ' ', 'g'));
$$;

-- Names that clash under the new key keep their store, items and layout: every one but the first
-- (by sort order) gets a number, "Lidl (2)", which the household can rename or delete.
update public.stores s set name = left(btrim(s.name), 54) || ' (' || d.n || ')'
from (
  select id, row_number() over (
    partition by household_id, public.store_name_key(name) order by sort_order, created_at, id
  ) as n
  from public.stores
) d
where d.id = s.id and d.n > 1;

create unique index stores_household_name_key on public.stores (household_id, public.store_name_key(name));

-- The name as stored: trimmed and collapsed; null when empty, an error past 40 characters (the
-- table allows 60, for the names households already have).
create function public.store_name(p_name text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  if v_name = '' then
    raise exception 'store_name_empty' using errcode = '22023';
  end if;
  if char_length(v_name) > 40 then
    raise exception 'store_name_too_long' using errcode = '22001';
  end if;
  return v_name;
end $$;

-- Creates the store after the household's last one, or returns the store that already has the
-- name (any case or spacing): creating and selecting a store is one idempotent step.
create function public.add_store(p_household uuid, p_name text) returns uuid
language plpgsql set search_path = '' as $$
declare
  v_name text := public.store_name(p_name);
  v_store uuid;
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  insert into public.stores (household_id, name, sort_order)
  values (
    p_household, v_name,
    coalesce((select max(sort_order) from public.stores where household_id = p_household), 0) + 10
  )
  on conflict (household_id, public.store_name_key(name)) do nothing
  returning id into v_store;

  if v_store is null then
    return (
      select id from public.stores
      where household_id = p_household and public.store_name_key(name) = public.store_name_key(v_name)
    );
  end if;

  insert into public.store_category_order (household_id, store_id, category_id, sort_order, hidden)
  select p_household, v_store, c.id, row_number() over (order by c.sort_order, c.name) * 10, false
  from public.categories c
  where c.household_id = p_household;
  return v_store;
end $$;

-- A preset store renamed to another name stops being that chain: its seed key goes, so the
-- chain's brand defaults (Balea -> dm) no longer pick it. A change of case or spacing keeps it.
create function public.rename_store(p_store uuid, p_name text) returns void
language plpgsql set search_path = '' as $$
declare
  v_store public.stores := (select s from public.stores s where s.id = p_store);
  v_name text := public.store_name(p_name);
begin
  if v_store.id is null or not public.is_household_member(v_store.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.stores
    where household_id = v_store.household_id and id <> p_store
      and public.store_name_key(name) = public.store_name_key(v_name)
  ) then
    raise exception 'store_name_taken' using errcode = '23505';
  end if;
  update public.stores
  set name = v_name,
      seed_key = case when public.store_name_key(v_name) = public.store_name_key(v_store.name) then seed_key end
  where id = p_store and (name, seed_key) is distinct from (
    v_name, case when public.store_name_key(v_name) = public.store_name_key(v_store.name) then seed_key end
  );
end $$;

-- Its items, open and bought, fall back to no store; its layout and memories go with it.
create function public.delete_store(p_store uuid) returns void
language plpgsql set search_path = '' as $$
declare
  v_household uuid := (select household_id from public.stores where id = p_store);
begin
  if v_household is null or not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  delete from public.stores where id = p_store;
end $$;

revoke execute on function
  public.store_name_key(text),
  public.store_name(text),
  public.add_store(uuid, text),
  public.rename_store(uuid, text),
  public.delete_store(uuid)
from public, anon;
grant execute on function
  public.store_name_key(text),
  public.store_name(text),
  public.add_store(uuid, text),
  public.rename_store(uuid, text),
  public.delete_store(uuid)
to authenticated;
