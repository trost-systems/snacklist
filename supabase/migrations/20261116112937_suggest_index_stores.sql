-- Job 274 review: suggest_index also answers what suggest_entries reads for each row's store, so
-- the device shows the store the server would, offline too. As before, plus:
--   memory: [item_key, canonical_key, store_id] of item_store_memory, newest first (as
--     suggest_store reads it: the item key, else its canonical key).
--   cleared: the item keys of item_store_cleared (guess_store with p_category_store).
--   stores: [seed_key, store_id] of the stores with a seed key (a brand's store, category_store).
--   categories: [category_id, category_usual_store, category_store] of each category that has
--     either.
-- Now security definer, like suggest_store and category_usual_store: every read is of p_household
-- after the membership check, and through RLS the items and memory scans cost a membership check
-- per row (17.5 ms instead of 23 ms on the 5,000-item bench household with 400 memory keys).
create or replace function public.suggest_index(p_household uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
      ) o), '[]'),
    'memory', coalesce((
      select jsonb_agg(jsonb_build_array(m.item_key, m.canonical_key, m.store_id)
        order by m.updated_at desc, m.item_key collate "C", m.store_id)
      from public.item_store_memory m
      where m.household_id = p_household), '[]'),
    'cleared', coalesce((
      select jsonb_agg(c.item_key order by c.item_key collate "C")
      from public.item_store_cleared c
      where c.household_id = p_household), '[]'),
    'stores', coalesce((
      select jsonb_agg(jsonb_build_array(s.seed_key, s.id) order by s.seed_key collate "C")
      from public.stores s
      where s.household_id = p_household and s.seed_key is not null), '[]'),
    -- category_usual_store of every category at once: the store with the most memory times over
    -- the canonical keys of the category's items, ties to the latest, then the smaller id.
    'categories', coalesce((
      with keys as (
        select distinct i.category_id, i.canonical_key
        from public.items i
        where i.household_id = p_household and i.category_id is not null
      ),
      usual as (
        select distinct on (t.category_id) t.category_id, t.store_id
        from (
          select k.category_id, m.store_id, sum(m.times) as times, max(m.updated_at) as at
          from keys k
          join public.item_store_memory m on m.household_id = p_household and m.canonical_key = k.canonical_key
          group by k.category_id, m.store_id
        ) t
        order by t.category_id, t.times desc, t.at desc, t.store_id
      )
      select jsonb_agg(jsonb_build_array(c.id, c.usual, c.seeded) order by c.id::text collate "C")
      from (
        select k.id, u.store_id as usual, public.category_store(p_household, k.id) as seeded
        from public.categories k
        left join usual u on u.category_id = k.id
        where k.household_id = p_household
      ) c
      where c.usual is not null or c.seeded is not null), '[]')
  );
end $$;
