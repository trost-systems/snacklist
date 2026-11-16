-- Job 272 (ST1, behind the app flag input-stable-rows): a grocery added for the first time, with
-- no remembered store, gets the store the household uses most for its category.
--
-- The app opts in per call with p_category_store; old builds and flag-off builds send nothing and
-- get exactly what they got before. What changed:
--
-- - item_store_cleared (new): an item key whose store was last changed to "Ohne Laden". Only the
--   items triggers write it: items_learn on a change to no store (it already deleted the key's
--   store memory), but not when a deleted store takes it (on delete set null: nobody picked "Ohne
--   Laden"), and items_learn_insert on an add with p_no_store under p_category_store (the
--   transaction-local setting family_groceries.no_store), which may have got no store to clear.
--   A store learned later leaves the row: guess_store reads the memory first, so the memory wins
--   while it lasts, and once it is gone (a change to no store, the 10-minute undo of the add that
--   taught it, its store deleted) the clear is in force again.
-- - category_usual_store (new): the store with the most item_store_memory times among the
--   household's remembered items of that category (memory rows joined to the household's items
--   by canonical_key), ties to the latest. From memory, not items.store_id, so an item being
--   inserted never counts for itself.
-- - guess_store gains p_category_store: when on, after the memory a recorded clear means no
--   store, else the brand's store, then category_usual_store, then category_store (dm, Baumarkt).
--   Off: unchanged.
-- - parse_item gains p_category_store: when on, its store is guess_store's with it (the app
--   parses an add typed on the device and takes that store when the row has none). Off: unchanged,
--   and the two-argument calls (voice, suggest_entries, add_item, add_list_item) are off.
-- - suggest_entries gains p_category_store: when on, every row's store is guess_store's with it
--   (the typed, pack, size and catalog rows too, which otherwise take parse_item's). Off:
--   unchanged.
-- - put_item (both signatures) gains p_category_store: when on, the insert runs with the
--   transaction-local setting family_groceries.category_store = 'on', and with p_no_store also
--   family_groceries.no_store = 'on'.
-- - items_before_write: an insert without a store under that setting takes guess_store(.., true)
--   instead of suggest_store. Otherwise unchanged.
-- - items_learn_insert compares the inserted store against guess_store under the same setting, so
--   the category default is never learned as the item's store while a different pick still is.
--
-- Pinned by supabase/tests/category_usual_store.test.sql.

create table public.item_store_cleared (
  household_id uuid not null references public.households (id) on delete cascade,
  item_key text not null check (item_key <> ''),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (household_id, item_key)
);

comment on table public.item_store_cleared is
  'Job 272: item keys whose store was last changed to none. With p_category_store and no store memory for the key, guess_store gives them no store instead of the category''s usual one. Only the items triggers write it.';

alter table public.item_store_cleared enable row level security;
revoke all on public.item_store_cleared from public, anon, authenticated;
grant select on public.item_store_cleared to authenticated;
create policy item_store_cleared_member on public.item_store_cleared
  for select to authenticated using (public.is_household_member(household_id));

-- Security definer like suggest_store: it scans the household's items of one category, where RLS
-- would call is_household_member once per row.
create function public.category_usual_store(p_household uuid, p_category uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  return (
    select m.store_id
    from public.item_store_memory m
    where m.household_id = p_household
      and m.canonical_key in (
        select i.canonical_key from public.items i
        where i.household_id = p_household and i.category_id = p_category
      )
    group by m.store_id
    order by sum(m.times) desc, max(m.updated_at) desc, m.store_id
    limit 1
  );
end $$;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.guess_store(uuid, text, text, uuid);

create function public.guess_store(
  p_household uuid,
  p_name text,
  p_brand text,
  p_category uuid,
  p_category_store boolean default false
) returns uuid
language sql stable set search_path = '' as $$
  select coalesce(
    public.suggest_store(p_household, p_name),
    case
      when p_category_store and exists (
        select from public.item_store_cleared c
        where c.household_id = p_household and c.item_key = public.item_key(p_name)
      ) then null
      else coalesce(
        (select s.id from public.brands g
         join public.stores s on s.household_id = p_household and s.seed_key = g.store_seed
         where g.key = public.brand_key(p_brand)),
        case when p_category_store then public.category_usual_store(p_household, p_category) end,
        public.category_store(p_household, p_category)
      )
    end
  );
$$;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.parse_item(uuid, text);

-- As in 20261106163919_hardware_categories.sql; with p_category_store the store is guess_store's.
create function public.parse_item(p_household uuid, p_text text, p_category_store boolean default false)
returns table (name text, brand text, properties text, quantity text, store_id uuid, category_id uuid)
language plpgsql stable set search_path = '' as $$
declare
  v_units constant text := public.item_units();
  -- Rolls are an Eigenschaft at the end ("Klopapier 16 Rollen"), a Menge only up front.
  v_trailing_units constant text := replace(v_units, 'rolle|rollen|', '');
  v_number_words constant jsonb := public.item_number_words();
  -- The article forms count only up front: "Trag Milch ein" is no Milch x1.
  v_trailing_words constant text := (
    select string_agg(k, '|') from jsonb_object_keys(v_number_words) k where k not in ('ein', 'eine', 'einen', 'einer'));
  v_text text := regexp_replace(btrim(coalesce(p_text, '')), '\s+', ' ', 'g');
  v_match text[];
  v_tok text[];
  v_low text[];
  v_kind text[];
  v_props text[] := '{}'::text[];
  v_n integer;
  v_i integer;
  v_category uuid;
  v_len integer;
  v_prop text;
  v_t1 text;
  v_t2 text;
  v_brand_at integer;
  v_brand_len integer;
  v_product text;
  v_store_seed text;
  -- The brand found, kept for the store when the brand alone becomes the name.
  v_brand text;
  v_suffix text[];
  v_units_re constant text := '(' || public.item_units() || ')';
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  -- Halves and one and a half up front: "ein halbes Brot" -> 1/2, "ein halbes Kilo" -> 0,5 Kilo,
  -- "anderthalb Liter" -> 1,5 Liter.
  v_text := regexp_replace(v_text, '^(?:(?:ein|eine|einen)\s+)?(?:halbe[snmr]?|halb)\s+(?=' || v_units_re || '\y)', '0,5 ', 'i');
  v_text := regexp_replace(v_text, '^(?:(?:ein|eine|einen)\s+)?(?:halbe[snmr]?|halb)\s+', '1/2 ', 'i');
  v_text := regexp_replace(v_text, '^(?:anderthalb|eineinhalb)\s+', '1,5 ', 'i');
  -- A multipack is one token: "6 x 1,5 l", "6x1,5l", "6×0,5 l" -> "6x1,5l".
  v_text := regexp_replace(v_text, '(^|\s)(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(?:' || v_units_re || '\.?)?(?=\s|$)', '\1\2x\3\4', 'gi');

  -- A leading count or amount is the Menge ("2 Gurken", "zwei Liter Milch", "1/2 Brot"), unless
  -- the number word starts a name ("Drei Glocken Spaghetti", public.item_number_names).
  v_match := regexp_match(
    v_text,
    '^(?:(\d+(?:[.,/]\d+)?)(?:\s*(' || v_units || ')\.?)?|(' || (select string_agg(k, '|') from jsonb_object_keys(v_number_words) k)
      || ')(?:\s+(' || v_units || ')\.?)?)\s+(.+)$',
    'i'
  );
  if v_match[3] is not null
     and exists (select from unnest(public.item_number_names()) n where lower(v_text) ~ ('^' || n || '\y')) then
    v_match := null;
  end if;
  if v_match is not null then
    quantity := concat_ws(' ',
      coalesce(v_match[1], v_number_words ->> lower(v_match[3])),
      case when lower(coalesce(v_match[2], v_match[4], 'x')) <> 'x' then coalesce(v_match[2], v_match[4]) end);
    v_text := v_match[5];
  end if;

  -- A bare count at the end is the Menge when it is 1 to 20 or a number word but no article
  -- form, the word before it is no size or unit word and has no digit, and the rest is a known
  -- name: "Karotten 2", "Gurken zwei", not "Windeln Größe 4", "Büroklammern 100" or "Plimbel 3"
  -- (jobs 61 and 104, supabase/tests/quantity_parse.tsv).
  if quantity is null then
    v_match := regexp_match(v_text, '^(.*\s)?(\S+)\s([1-9]\d?|' || v_trailing_words || ')$', 'i');
    if v_match is not null
       and coalesce(v_number_words ->> lower(v_match[3]), v_match[3])::integer <= 20
       and v_match[2] !~ '\d'
       and lower(rtrim(v_match[2], '.')) !~ ('^(' || v_units || '|größe|grösse|groesse|gr|stufe|nr|no|size|typ|type|klasse|pack|pcs|mah|cl|%)$')
       and public.is_known_name(p_household, coalesce(v_match[1], '') || v_match[2]) then
      quantity := coalesce(v_number_words ->> lower(v_match[3]), v_match[3]);
      v_text := coalesce(v_match[1], '') || v_match[2];
    end if;
  end if;

  -- Words, each with the list punctuation that followed it ("Tomaten, Gurke"): the name keeps it,
  -- the matching does not see it. A decimal comma ("1,5") is part of its word.
  v_tok := array_remove(regexp_split_to_array(regexp_replace(v_text, '\s+([,;]+)(?=\s|$)', '\1', 'g'), '\s+'), '');
  v_n := coalesce(cardinality(v_tok), 0);
  if v_n = 0 then
    name := '';
    return next;
    return;
  end if;
  v_suffix := array_fill(''::text, array[v_n]);
  for v_w in 1..v_n loop
    v_suffix[v_w] := coalesce(substring(v_tok[v_w] from '[,;]+$'), '');
    v_tok[v_w] := regexp_replace(v_tok[v_w], '[,;]+$', '');
  end loop;
  v_low := array(select public.normalize_item_name(t) from unnest(v_tok) with ordinality as u (t, ord) order by ord);
  v_kind := array_fill(null::text, array[v_n]);

  -- Marke: the longest run first, then the leftmost; a global brand before a learned one.
  select r.s, r.l, b.label, b.product, b.store_seed
  into v_brand_at, v_brand_len, brand, v_product, v_store_seed
  from (
    select g.s, gl.l, public.brand_key(array_to_string(v_tok[g.s:g.s + gl.l - 1], ' ')) as k
    from generate_series(1, v_n) as g (s) cross join generate_series(1, 3) as gl (l)
    where g.s + gl.l - 1 <= v_n
  ) r
  join (
    select gb.key as k, gb.brand as label, gb.product, gb.store_seed, 0 as rank from public.brands gb
    union all
    -- A brand learned before its word reached the dictionary is passed over.
    select hb.brand_key, hb.brand, null, null, 1 from public.household_brands hb
    where hb.household_id = p_household and not public.is_ordinary_text(hb.brand)
  ) b on b.k = r.k
  order by r.l desc, r.s, b.rank
  limit 1;
  v_brand := brand;
  if v_brand_at is not null then
    v_kind[v_brand_at:v_brand_at + v_brand_len - 1] := array_fill('brand'::text, array[v_brand_len]);
  end if;

  -- Eigenschaften, left to right.
  v_i := 1;
  while v_i <= v_n loop
    v_len := 0;
    v_prop := null;
    if v_kind[v_i] is null then
      v_t1 := v_low[v_i];
      v_t2 := case when v_i < v_n and v_kind[v_i + 1] is null then v_low[v_i + 1] end;
      if v_t1 ~ '^(groesse|grosse|gr\.?)$' and v_t2 ~ '^(\d+(\+|-\d+)?|x{0,3}s|m|x{0,3}l)$' then
        v_len := 2;
        v_prop := 'Größe ' || upper(v_t2);
      elsif v_t1 ~ '^(groesse|grosse|gr\.?)\d+\+?$' then
        v_len := 1;
        v_prop := 'Größe ' || substring(v_t1 from '\d+\+?$');
      elsif v_t1 ~ '^\d+([.,]\d+)?%$' or (v_t1 ~ '^\d+([.,]\d+)?$' and v_t2 = '%') then
        v_len := case when v_t1 like '%\%' then 1 else 2 end;
        v_prop := replace(rtrim(v_t1, '%'), '.', ',') || ' %';
        if v_i + v_len <= v_n and v_kind[v_i + v_len] is null and v_low[v_i + v_len] in ('fett', 'vol', 'vol.') then
          v_prop := v_prop || ' ' || v_tok[v_i + v_len];
          v_len := v_len + 1;
        end if;
      elsif v_t1 ~ '^\d+er$' and v_t2 in ('pack', 'packung', 'pck', 'box', 'karton') then
        v_len := 2;
        v_prop := v_tok[v_i] || ' ' || v_tok[v_i + 1];
      elsif v_t1 ~ '^\d+er(-?pack)?$' or v_t1 in ('doppelpack', 'vorteilspack', 'sparpack', 'grosspackung', 'familienpackung', 'monatsbox', 'xxl') then
        v_len := 1;
        v_prop := v_tok[v_i];
      elsif v_t1 in ('big', 'maxi', 'mega', 'jumbo', 'standard', 'spar', 'vorteils', 'familien', 'mini', 'duo', 'multi', 'monats', 'xxl', 'xl')
            and v_t2 in ('pack', 'packung', 'box') then
        v_len := 2;
        v_prop := v_tok[v_i] || ' ' || v_tok[v_i + 1];
      elsif v_t1 ~ '^\d+$' and v_t2 in ('rolle', 'rollen') then
        v_len := 2;
        v_prop := v_tok[v_i] || ' ' || v_tok[v_i + 1];
      elsif v_t1 ~ '^\d+-?lagig$' then
        v_len := 1;
        v_prop := substring(v_t1 from '^\d+') || '-lagig';
      elsif v_t1 ~ '^\d+$' and v_t2 = 'lagig' then
        v_len := 2;
        v_prop := v_t1 || '-lagig';
      elsif v_tok[v_i] ~* ('^\d+x\d+([.,]\d+)?' || v_units_re || '?\.?$') then
        -- A multipack: "6x1,5 l".
        v_len := 1;
        v_prop := regexp_replace(v_tok[v_i], '^(\d+x\d+(?:[.,]\d+)?)(.*)$', '\1 \2');
        v_prop := rtrim(v_prop);
      elsif v_t1 ~ '^\d+([.,]\d+)?$' and v_t2 is not null and v_tok[v_i + 1] ~* ('^(' || v_trailing_units || ')\.?$')
            and lower(v_tok[v_i + 1]) <> 'x' then
        v_len := 2;
        v_prop := v_tok[v_i] || ' ' || v_tok[v_i + 1];
      elsif v_tok[v_i] ~* ('^\d+([.,]\d+)?(' || v_trailing_units || ')\.?$') and v_t1 !~ '^\d+x$' then
        v_len := 1;
        v_prop := regexp_replace(v_tok[v_i], '^(\d+(?:[.,]\d+)?)\s*', '\1 ');
      elsif quantity is null and v_t1 ~ '^(\d+x|x\d+)$' then
        -- A count anywhere ("Spülmittel Pril 2x") when none came first.
        quantity := substring(v_t1 from '\d+');
        v_kind[v_i] := 'quantity';
      else
        -- Descriptors and flavours after a name word or the brand ("Joghurt Erdbeere"); the plain
        -- descriptors anywhere ("Bio Eier"). A flavour up front is the name ("Paprika rot").
        select d.label, d.words into v_prop, v_len
        from public.item_descriptors() d
        where d.alias = case when d.words = 2 then v_t1 || ' ' || coalesce(v_t2, '') else v_t1 end
          and (exists (select from unnest(v_kind[1:v_i - 1]) as k (kind) where k.kind is null or k.kind = 'brand')
               or d.alias in ('bio', 'laktosefrei', 'glutenfrei', 'vegan', 'vegetarisch', 'zuckerfrei',
                              'ohne zucker', 'koffeinfrei', 'entkoffeiniert', 'alkoholfrei', 'fettarm'))
        order by d.words desc
        limit 1;
      end if;
    end if;
    if v_prop is not null then
      -- The first amount with a unit is the Menge, wherever it stands ("Äpfel 1 kg bio"), unless
      -- a leading count took it ("2x Cola 0,5 l").
      if quantity is null and v_prop ~* ('^\d+([.,]\d+)? ?(' || v_trailing_units || ')\.?$') then
        quantity := v_prop;
      else
        v_props := v_props || v_prop;
      end if;
      v_kind[v_i:v_i + v_len - 1] := array_fill('property'::text, array[v_len]);
    end if;
    v_i := v_i + 1;
  end loop;

  name := rtrim(array_to_string(array(
    select t || sfx from unnest(v_tok, v_kind, v_suffix) with ordinality as u (t, kind, sfx, ord) where u.kind is null order by ord
  ), ' '), ',; ');
  if v_product is not null and name <> ''
     and (public.dictionary_category(public.item_key(name)) is null
          or (name ~ '^\S+$'
              and public.item_domain(public.dictionary_category(public.item_key(name)))
                  is distinct from public.item_domain(public.dictionary_category(public.item_key(v_product))))) then
    -- "Whiskas Lachs": the one name word is of another kind than the brand's product; "Persil
    -- Color", "Pampers Baby Dry": the dictionary knows none of the name. Either way it is the
    -- variety.
    v_props := name || v_props;
    name := v_product;
  elsif name = '' and v_product is not null then
    name := v_product;
  elsif name = '' and brand is not null then
    -- Only a brand and its properties: the brand is the name ("Nutella", "Nutella 2er Pack").
    name := array_to_string(v_tok[v_brand_at:v_brand_at + v_brand_len - 1], ' ');
    brand := null;
  elsif name = '' then
    -- Nothing but properties ("Größe 3", "Bio"): nothing is split off.
    name := array_to_string(v_tok, ' ');
    v_props := '{}';
  end if;
  -- Never longer than the columns (items: name 120, brand 60, properties 120, quantity 40).
  name := public.cap_text(name, 120);
  brand := public.cap_text(brand, 60);
  properties := public.cap_text(nullif(array_to_string(v_props, ', '), ''), 120);
  quantity := public.cap_text(quantity, 40);

  v_category := public.classify_item(p_household, name);
  category_id := v_category;
  store_id := case
    when p_category_store then public.guess_store(p_household, name, v_brand, v_category, true)
    else coalesce(
      public.suggest_store(p_household, name),
      (select s.id from public.stores s where s.household_id = p_household and s.seed_key = v_store_seed),
      public.category_store(p_household, v_category)
    )
  end;
  return next;
end $$;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.suggest_entries(uuid, text, integer);

create function public.suggest_entries(
  p_household uuid,
  p_text text,
  p_limit integer default 8,
  p_category_store boolean default false
)
returns table (source text, name text, brand text, properties text, quantity text, store_id uuid, category_id uuid)
language plpgsql stable set search_path = '' as $function$
declare
  v_typed record;
  v_norm text;
  v_parts text[];
  v_size integer;
  v_last_key text;
  v_left integer := least(greatest(coalesce(p_limit, 8), 1), 20);
  v_seen text[] := '{}'::text[];
  v_taken jsonb := '{}'::jsonb;
  v_key text;
  v_unserved text[];
  c record;
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if btrim(coalesce(p_text, '')) = '' then
    return;
  end if;
  select * into v_typed from public.parse_item(p_household, p_text);
  if v_typed.name = '' then
    return;
  end if;
  v_norm := public.normalize_item_name(v_typed.name);
  v_parts := coalesce(string_to_array(v_typed.properties, ', '), '{}');
  v_size := (select substring(p from '^Größe (\d+)$')::integer from unnest(v_parts) as p where p ~ '^Größe \d+$' limit 1);
  v_last_key := public.item_key(substring(btrim(p_text) from '\S+$'));
  v_unserved := array(
    select h.seed_key from public.hardware_categories() h
    where not exists (
      select from public.categories k
      where k.household_id = p_household and (k.seed_key = h.seed_key or h.seed_key = any (k.absorbed_seed_keys))
    )
  );

  for c in
    with recent as materialized (
      select * from public.suggest_history(p_household)
    ),
    -- Matched once per name, not once per item.
    names as materialized (
      select n.normalized_name, public.suggest_match(v_norm, n.normalized_name) as tier
      from (select distinct r.normalized_name from recent r) n
    ),
    history as materialized (
      select r.*, n.tier, extensions.similarity(v_norm, r.normalized_name) as sim
      from recent r
      join names n using (normalized_name)
      where n.tier is not null
    ),
    same_name as (
      select h.* from history h where h.normalized_name = v_norm
    ),
    other_parts as (
      select distinct on (lower(p.part)) p.part, h.at
      from same_name h cross join unnest(string_to_array(h.properties, ', ')) as p (part)
      where lower(p.part) <> all (select lower(t) from unnest(v_parts) as t)
        and p.part !~* '^(größe|grösse|groesse|gr\.)(\s|\d)'
      order by lower(p.part), h.at desc
    ),
    other_brands as (
      select distinct on (public.brand_key(b.brand)) b.brand, b.tier, b.at
      from (
        select h.brand, 0 as tier, h.at from same_name h where h.brand is not null
        union all
        select g.brand, 1, null from public.brands g
        where g.product is not null and public.normalize_item_name(g.product) = v_norm
      ) b
      where public.brand_key(b.brand) <> public.brand_key(v_typed.brand)
      order by public.brand_key(b.brand), b.tier, b.at desc nulls last
    ),
    terms as (
      select t.term, t.tier, t.sim from (
        select distinct on (t.key) t.term, m.tier, extensions.similarity(v_last_key, t.key) as sim
        from public.classifier_terms t
        cross join lateral (select public.suggest_match(v_last_key, t.key) as tier) m
        where char_length(v_last_key) >= 2
          and m.tier is not null
          and t.key <> public.item_key(v_typed.name)
          and (t.category <> all (v_unserved) or char_length(v_last_key) >= 4)
          -- Only the last word is replaced, so after other words it takes a prefix or, inside a
          -- one-word term, the typed part: a typo of it would ignore them ("Rote Bete" -> "Rote
          -- Besen") and a phrase found by a later word would repeat them ("Rote Rote Beete").
          and (m.tier < 2 or v_typed.name !~ '\s' or (m.tier = 2 and t.key !~ ' '))
        order by t.key, char_length(t.term), t.term
      ) t
      order by t.tier, case when t.tier >= 2 then -t.sim end, char_length(t.term), t.term
      limit 3
    ),
    candidates as (
      select 'typed' as source, 1 as cap, 1 as ord, 1::bigint as rank,
        v_typed.name, v_typed.brand, v_typed.properties, v_typed.quantity, v_typed.store_id, v_typed.category_id
      union all
      select 'history', 3, 2,
        row_number() over (order by h.tier, case when h.tier >= 2 then -h.sim end, h.at desc, h.name, h.brand, h.properties),
        h.name, h.brand, h.properties, coalesce(v_typed.quantity, h.quantity), null::uuid, null::uuid
      from (
        select distinct on (h.name, h.brand, h.properties) h.*
        from history h
        where char_length(v_norm) >= 2
        order by h.name, h.brand, h.properties, h.at desc
      ) h
      union all
      select case when public.is_pack_property(p.part) then 'pack' else 'variant' end, 2, 3,
        row_number() over (order by p.at desc, p.part),
        v_typed.name, v_typed.brand,
        public.cap_text(array_to_string(
          case when public.is_pack_property(p.part)
            then array(select t from unnest(v_parts) with ordinality as u (t, o)
                       where not public.is_pack_property(u.t) order by u.o)
            else v_parts
          end || p.part, ', '), 120),
        v_typed.quantity, v_typed.store_id, v_typed.category_id
      from other_parts p
      union all
      select 'size', 2, 4, s.rank,
        v_typed.name, v_typed.brand,
        array_to_string(array_replace(v_parts, 'Größe ' || v_size, 'Größe ' || s.size), ', '),
        v_typed.quantity, v_typed.store_id, v_typed.category_id
      from (values (1::bigint, v_size + 1), (2, v_size - 1)) as s (rank, size)
      where s.size between 1 and 8
      union all
      select 'brand', 3, 5, row_number() over (order by b.tier, b.at desc nulls last, lower(b.brand)),
        v_typed.name, b.brand, v_typed.properties, v_typed.quantity, null::uuid, v_typed.category_id
      from other_brands b
      union all
      select 'catalog', 3, 6,
        row_number() over (order by t.tier, case when t.tier >= 2 then -t.sim end, char_length(t.term), t.term),
        p.name, p.brand, p.properties, p.quantity, p.store_id, p.category_id
      from terms t
      -- Written the way a German noun list shows it: "rote bete" -> "Rote Bete".
      cross join lateral public.parse_item(p_household, regexp_replace(btrim(p_text), '\S+$', initcap(t.term))) p
    )
    select * from candidates x order by x.ord, x.rank
  loop
    -- The cap first: keying a row is the costly part, and a fuzzy match brings many history rows.
    continue when coalesce((v_taken ->> c.source)::integer, 0) >= c.cap;
    v_key := public.suggestion_key(c.name, c.brand, c.properties);
    continue when v_key = any (v_seen);
    v_seen := v_seen || v_key;
    v_taken := v_taken || jsonb_build_object(c.source, coalesce((v_taken ->> c.source)::integer, 0) + 1);
    source := c.source;
    name := c.name;
    brand := c.brand;
    properties := c.properties;
    quantity := c.quantity;
    category_id := c.category_id;
    store_id := c.store_id;
    if c.source = 'history' then
      category_id := public.classify_item(p_household, c.name);
    end if;
    if c.source in ('history', 'brand') or p_category_store then
      store_id := public.guess_store(p_household, c.name, c.brand, category_id, p_category_store);
    end if;
    return next;
    v_left := v_left - 1;
    exit when v_left = 0;
  end loop;
end $function$;


-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean);

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
  p_category_store boolean default false
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
drop function public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean);

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
  p_category_store boolean default false
) returns setof public.items
language sql set search_path = '' as $$
  select * from public.put_item(
    p_id => p_id, p_household => p_household, p_list => null, p_name => p_name,
    p_quantity => p_quantity, p_brand => p_brand, p_properties => p_properties,
    p_category => p_category, p_store => p_store, p_sort_key => p_sort_key, p_status => p_status,
    p_no_store => p_no_store, p_category_store => p_category_store)
$$;

revoke execute on function
  public.category_usual_store(uuid, uuid),
  public.parse_item(uuid, text, boolean),
  public.guess_store(uuid, text, text, uuid, boolean),
  public.suggest_entries(uuid, text, integer, boolean),
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean)
from public, anon;
grant execute on function
  public.category_usual_store(uuid, uuid),
  public.parse_item(uuid, text, boolean),
  public.guess_store(uuid, text, text, uuid, boolean),
  public.suggest_entries(uuid, text, integer, boolean),
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean)
to authenticated, service_role;

create or replace function public.items_before_write() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_guess record;
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - '{added_by,bought_by}'::text[]) = (to_jsonb(old) - '{added_by,bought_by}'::text[])
     and (new.added_by, new.bought_by) is distinct from (old.added_by, old.bought_by)
     and (new.added_by is not distinct from old.added_by
          or (new.added_by is null
              and (not exists (select from auth.users u where u.id = old.added_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.added_by))))
     and (new.bought_by is not distinct from old.bought_by
          or (new.bought_by is null
              and (not exists (select from auth.users u where u.id = old.bought_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.bought_by))))
  then
    return new;
  end if;
  new.name := btrim(new.name);
  new.quantity := nullif(btrim(new.quantity), '');
  new.brand := nullif(btrim(new.brand), '');
  new.properties := nullif(btrim(new.properties), '');
  new.normalized_name := public.normalize_item_name(new.name);
  if tg_op = 'INSERT' or new.category_id is null then
    v_guess := public.classify_item_detail(new.household_id, new.name);
    new.canonical_key := v_guess.canonical_key;
    if new.category_id is null then
      new.category_id := v_guess.category_id;
      new.categorized_via := v_guess.via;
    elsif tg_op = 'INSERT' then
      new.categorized_via := case when new.category_id = v_guess.category_id then v_guess.via else 'picked' end;
    end if;
  elsif new.name is distinct from old.name then
    new.canonical_key := public.canonical_key(new.name);
  end if;
  if tg_op = 'INSERT' and new.store_id is null then
    new.store_id := case
      when current_setting('family_groceries.category_store', true) = 'on'
        then public.guess_store(new.household_id, new.name, new.brand, new.category_id, true)
      else public.suggest_store(new.household_id, new.name)
    end;
  end if;
  if new.sort_key is null
     or (tg_op = 'UPDATE'
         and (new.store_id, new.category_id) is distinct from (old.store_id, old.category_id)
         and new.sort_key is not distinct from old.sort_key
         and coalesce(current_setting('family_groceries.sort_key', true), '') <> 'keep') then
    new.sort_key := coalesce(
      (select max(i.sort_key) from public.items i
       where i.household_id = new.household_id and i.category_id = new.category_id
         and i.store_id is not distinct from new.store_id and i.id <> new.id),
      0
    ) + 1024;
  end if;
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
    new.added_by := old.added_by;
    new.updated_at := now();
  end if;
  if new.status = 'bought' and (tg_op = 'INSERT' or old.status is distinct from 'bought') then
    new.bought_at := now();
    new.bought_by := auth.uid();
  elsif new.status = 'active' then
    new.bought_at := null;
    new.bought_by := null;
  end if;
  return new;
end $function$;

create or replace function public.items_learn() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_key text := public.item_key(new.name);
begin
  if v_key = '' or coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  if new.category_id is distinct from old.category_id then
    insert into public.category_memory as m (household_id, item_key, category_id)
    values (new.household_id, v_key, new.category_id)
    on conflict (household_id, item_key, category_id)
      do update set corrections = m.corrections + 1, updated_at = clock_timestamp();
  end if;
  if new.store_id is distinct from old.store_id and new.store_id is null then
    delete from public.item_store_memory where household_id = new.household_id and item_key = v_key;
    -- A store deleted takes its items' store away (on delete set null); nobody picked "Ohne Laden".
    if exists (select from public.stores s where s.id = old.store_id) then
      insert into public.item_store_cleared as c (household_id, item_key)
      values (new.household_id, v_key)
      on conflict (household_id, item_key) do update set updated_at = clock_timestamp();
    end if;
  elsif new.store_id is distinct from old.store_id
     or (new.store_id is not null and new.status = 'bought' and old.status = 'active') then
    insert into public.item_store_memory as m (household_id, item_key, store_id)
    values (new.household_id, v_key, new.store_id)
    on conflict (household_id, item_key, store_id)
      do update set times = m.times + 1, updated_at = clock_timestamp();
  end if;
  return null;
end $function$;

create or replace function public.items_learn_insert() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_now timestamptz := clock_timestamp();
begin
  if coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  with added as materialized (
    select n.id, n.household_id, public.item_key(n.name) as key, n.category_id, n.store_id,
      n.categorized_via = 'picked' as picked_category,
      public.guess_store(n.household_id, n.name, n.brand, n.category_id,
        coalesce(current_setting('family_groceries.category_store', true), '') = 'on') as guessed_store
    from new_items n
    where not exists (
      select from public.item_events e
      where e.household_id = n.household_id and e.created_at > now() - interval '1 day'
        and e.item_id = n.id and e.action = 'deleted'
    )
  ),
  corrections as (
    insert into public.category_memory as m
      (household_id, item_key, category_id, corrections, updated_at, undo_item, undo_by, undo_prev_at, undo_at)
    select a.household_id, a.key, a.category_id, count(*), v_now,
      case when count(*) = 1 then (array_agg(a.id))[1] end, count(*), null, v_now
    from added a
    where a.key <> '' and a.picked_category
    group by a.household_id, a.key, a.category_id
    on conflict (household_id, item_key, category_id)
      do update set corrections = m.corrections + excluded.corrections, updated_at = v_now,
        undo_item = excluded.undo_item, undo_by = excluded.undo_by, undo_prev_at = m.updated_at, undo_at = v_now
  ),
  cleared as (
    insert into public.item_store_cleared as c (household_id, item_key)
    select distinct a.household_id, a.key from added a
    where a.key <> '' and coalesce(current_setting('family_groceries.no_store', true), '') = 'on'
    on conflict (household_id, item_key) do update set updated_at = v_now
  )
  insert into public.item_store_memory as m
    (household_id, item_key, store_id, times, updated_at, undo_item, undo_by, undo_prev_at, undo_at)
  select a.household_id, a.key, a.store_id, count(*), v_now,
    case when count(*) = 1 then (array_agg(a.id))[1] end, count(*), null, v_now
  from added a
  where a.key <> '' and a.store_id is not null and a.store_id is distinct from a.guessed_store
  group by a.household_id, a.key, a.store_id
  on conflict (household_id, item_key, store_id)
    do update set times = m.times + excluded.times, updated_at = v_now,
      undo_item = excluded.undo_item, undo_by = excluded.undo_by, undo_prev_at = m.updated_at, undo_at = v_now;
  return null;
end $function$;
