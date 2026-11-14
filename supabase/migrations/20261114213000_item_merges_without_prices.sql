-- Job 246: item_merges keeps no prices (Legal P-2, NEEDS_LEAD job 243, option i). A merge stored
-- both rows whole, so a price lived on there after a member cleared it or deleted the item. Now
-- merge_items stores both rows without the five price columns, the rows already stored lose them,
-- and a daily job deletes merges older than 30 days (before, only the household's next merge did).
-- Undo brings the merged-in row back without a price; the kept row's price was never touched by a
-- merge or its undo.

-- [p_row] (an items row as JSON) without the price columns of 20261113094500_prices_and_currency.sql.
create function public.item_row_without_price(p_row jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select p_row - array['price_unit_micros', 'price_basis', 'price_per', 'price_currency', 'priced_at']
$$;
revoke execute on function public.item_row_without_price(jsonb) from public, anon, authenticated;

-- As in 20261105060950_rename_open_duplicate.sql, with both rows stored without their prices and
-- without the household's purge (purge_item_merges does it daily).
create or replace function public.merge_items(p_merge uuid, p_keep uuid, p_other uuid) returns jsonb
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

update public.item_merges set
  kept_before = public.item_row_without_price(kept_before),
  merged_row = public.item_row_without_price(merged_row)
where kept_before <> public.item_row_without_price(kept_before)
   or merged_row <> public.item_row_without_price(merged_row);

-- Deletes merges older than 30 days, in every household; returns how many.
create function public.purge_item_merges() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.item_merges where created_at < now() - interval '30 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.purge_item_merges() from public, anon, authenticated;

select public.purge_item_merges();

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('purge-item-merges', '53 3 * * *', 'select public.purge_item_merges()');

comment on table public.item_merges is
  'Duplicate-hint merges (job 32b) with both rows as they were, without prices (job 246), so '
  'unmerge_items restores them. Written only by merge_items/unmerge_items; deleted after 30 days '
  '(purge_item_merges, pg_cron).';
