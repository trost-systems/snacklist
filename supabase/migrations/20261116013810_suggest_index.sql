-- Job 274: what of a household public.suggest_entries reads, for the device to rank the add
-- sheet's rows itself in the same frame as the key. Arrays, nulls as JSON null, text sorted in
-- byte order:
--   history: [name, brand, properties, quantity, normalized_name, at] per (name, brand,
--     properties) of suggest_history, the latest row, newest first; what suggest_entries reduces
--     the history to.
--   brands: [brand, brand_key] of household_brands that are not ordinary text (parse_item's).
--   unserved: the hardware seed keys the household has no category for (suggest_entries'
--     v_unserved).
--   known: the normalized names of the household's items older than the history, which
--     is_known_name counts too.
create function public.suggest_index(p_household uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'history', coalesce((
      select jsonb_agg(jsonb_build_array(h.name, h.brand, h.properties, h.quantity, h.normalized_name, h.at)
        order by h.at desc, h.name collate "C", h.brand collate "C", h.properties collate "C")
      from (
        select distinct on (r.name, r.brand, r.properties) r.*
        from public.suggest_history(p_household) r
        order by r.name, r.brand, r.properties, r.at desc
      ) h), '[]'),
    'brands', coalesce((
      select jsonb_agg(jsonb_build_array(b.brand, b.brand_key) order by b.brand collate "C", b.brand_key collate "C")
      from public.household_brands b
      where b.household_id = p_household and not public.is_ordinary_text(b.brand)), '[]'),
    'unserved', coalesce((
      select jsonb_agg(h.seed_key order by h.seed_key collate "C")
      from public.hardware_categories() h
      where not exists (
        select from public.categories k
        where k.household_id = p_household and (k.seed_key = h.seed_key or h.seed_key = any (k.absorbed_seed_keys))
      )), '[]'),
    'known', coalesce((
      select jsonb_agg(o.normalized_name order by o.normalized_name collate "C")
      from (
        select distinct i.normalized_name
        from public.items i
        where i.household_id = p_household and i.updated_at <= now() - interval '1 year'
      ) o), '[]')
  );
end $$;

revoke execute on function public.suggest_index(uuid) from public, anon;
grant execute on function public.suggest_index(uuid) to authenticated, service_role;
