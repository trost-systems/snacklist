-- Job 470: English is a catalog language (Peter: CP4, ML1, Addendum 2). The data is
-- dictionary.<lang>.tsv (supabase/classifier/languages.ts); this migration makes room for it.
--
-- - classifier_terms.lang: German terms are 'de'; a word of another language that is no German
--   concept is a term of its language. The classifier reads every language's terms and forms, so
--   a name sorts the same for every member of a household, whatever language it is typed in.
-- - catalog_words: the words each language's catalog offers (German offers its terms). Words on a
--   German concept are its synonyms too (generate_synonyms.ts), so milk and Milch share a key.
-- - catalog_rows(): 'terms' stays the German terms, so apps released before this get the same
--   suggestions; 'words' ([lang:word, key, category, own]: own when the word is a concept of its
--   own, a classifier_terms row) is new, and parseCatalogDelta of released
--   apps reads only the keys it knows. catalog_snapshots and catalog_delta carry the words.
-- - suggest_entries(p_lang): the catalog rows of that language (default 'de', every released
--   app's call), else English.
-- - put_item(p_category_guess): the app's category for an add it lets the server classify. Used
--   only where the classifier answers its fallback, marked categorized_via 'device', not learned.
-- Every released app's calls bind as before: new parameters are last and have defaults.

-- The version every app released so far may bundle keeps a snapshot, so catalog_delta answers it
-- with changes rather than every row.
insert into public.catalog_snapshots (version, terms, forms, brands, homographs)
select public.catalog_digest(r), r -> 'terms', r -> 'forms', r -> 'brands', r -> 'homographs'
from public.catalog_rows() r
on conflict (version) do nothing;

alter table public.classifier_terms
  add column lang text not null default 'de' constraint classifier_terms_lang check (lang ~ '^[a-z]{2}$');

create table public.catalog_words (
  lang text not null check (lang ~ '^[a-z]{2}$' and lang <> 'de'),
  -- Lower-case Latin letters (Latin-1, Extended-A, ș and ț), as the classifier tables hold them.
  word text not null check (word ~ '^[a-zß-öø-ÿā-žșț]+( [a-zß-öø-ÿā-žșț]+)*$'),
  category text not null check (category in (
    'produce', 'bakery', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore',
    'paint', 'plumbing', 'electrical', 'tools', 'fasteners', 'building', 'garden'
  )),
  key text generated always as (public.item_key(word)) stored,
  primary key (lang, word)
);
alter table public.catalog_words enable row level security;
create policy catalog_words_read on public.catalog_words for select to authenticated using (true);
-- suggest_entries runs as the caller and reads it, like classifier_terms.
grant select on public.catalog_words to authenticated, service_role;

create trigger catalog_words_catalog_outgoing
  before insert or update or delete or truncate on public.catalog_words
  for each statement execute function public.catalog_snapshot_outgoing();

-- Null in the snapshots taken before this migration: every word is new to those versions.
alter table public.catalog_snapshots add column words jsonb;

-- As in 20261126150000_catalog_homographs.sql, with the German terms only under 'terms' and every
-- other language's words under 'words'.
create or replace function public.catalog_rows() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'terms', coalesce((
      select jsonb_agg(jsonb_build_array(t.term, t.key, t.category) order by t.term collate "C")
      from public.classifier_terms t where t.lang = 'de'), '[]'),
    'forms', coalesce((
      select jsonb_agg(jsonb_build_array(l.form, l.canonical, l.category, l.synonym) order by l.form collate "C")
      from public.classifier_lexicon l), '[]'),
    'brands', coalesce((
      select jsonb_agg(jsonb_build_array(b.key, b.brand, b.product, b.store_seed) order by b.key collate "C")
      from public.brands b), '[]'),
    'homographs', coalesce((
      select jsonb_agg(
        jsonb_build_array(l.form, e ->> 'surface', e ->> 'canonical', e ->> 'category', (e ->> 'synonym')::boolean)
        order by l.form collate "C", e ->> 'surface' collate "C")
      from public.classifier_lexicon l, jsonb_array_elements(l.homographs) e), '[]'),
    'words', coalesce((
      select jsonb_agg(jsonb_build_array(w.lang || ':' || w.word, w.key, w.category,
          exists (select from public.classifier_terms t where t.term = w.word and t.lang = w.lang))
        order by w.lang || ':' || w.word collate "C")
      from public.catalog_words w), '[]')
  )
$$;

-- As in 20261126150000_catalog_homographs.sql, with the words.
create or replace function public.catalog_snapshot_outgoing() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if coalesce(current_setting('family_groceries.catalog_outgoing', true), '') = '' then
    perform set_config('family_groceries.catalog_outgoing', 'taken', true);
    if not exists (select from public.catalog_snapshots s where s.current) then
      v_rows := public.catalog_rows();
      insert into public.catalog_snapshots (version, terms, forms, brands, homographs, words)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands',
        v_rows -> 'homographs', v_rows -> 'words')
      on conflict (version) do nothing;
    end if;
  end if;
  -- Also the row lock that holds catalog_delta's computing until this transaction ends.
  update public.catalog_snapshots s set current = false where s.current;
  return null;
end $$;

-- As in 20261126150000_catalog_homographs.sql, with the words' changes.
create or replace function public.catalog_delta(p_base text, p_have text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
  v_now public.catalog_snapshots;
  v_base public.catalog_snapshots;
begin
  if p_base is null or p_base !~ '^[0-9a-f]{16}$' or p_have !~ '^[0-9a-f]{16}$' then
    raise exception 'invalid_version' using errcode = '22023';
  end if;
  select * into v_now from public.catalog_snapshots s where s.current;
  if not found then
    -- After a catalog change commits, so the rows are the committed ones: its trigger's update
    -- holds this lock until then, and while this one is held the next change waits.
    lock table public.catalog_snapshots in share row exclusive mode;
    select * into v_now from public.catalog_snapshots s where s.current;
    if not found then
      v_rows := public.catalog_rows();
      insert into public.catalog_snapshots as s (version, terms, forms, brands, homographs, words, current)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands',
        v_rows -> 'homographs', v_rows -> 'words', true)
      on conflict (version) do update set current = true
      returning * into v_now;
    end if;
  end if;
  if v_now.version in (p_base, p_have) then
    return jsonb_build_object('version', v_now.version, 'full', false);
  end if;
  select * into v_base from public.catalog_snapshots s where s.version = p_base;
  if not found then
    return jsonb_build_object(
      'version', v_now.version,
      'full', true,
      'terms', jsonb_build_object('put', v_now.terms, 'drop', '[]'::jsonb),
      'forms', jsonb_build_object('put', v_now.forms, 'drop', '[]'::jsonb),
      'brands', jsonb_build_object('put', v_now.brands, 'drop', '[]'::jsonb),
      'homographs', v_now.homographs,
      'words', jsonb_build_object('put', v_now.words, 'drop', '[]'::jsonb)
    );
  end if;
  return jsonb_build_object(
    'version', v_now.version,
    'full', false,
    'terms', public.catalog_changes(v_base.terms, v_now.terms),
    'forms', public.catalog_changes(v_base.forms, v_now.forms),
    'brands', public.catalog_changes(v_base.brands, v_now.brands),
    'homographs', v_now.homographs,
    'words', public.catalog_changes(coalesce(v_base.words, '[]'), v_now.words)
  );
end $$;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.suggest_entries(uuid, text, integer, boolean);

-- As in 20261115205907_category_usual_store.sql, plus p_lang.
create function public.suggest_entries(
  p_household uuid,
  p_text text,
  p_limit integer default 8,
  p_category_store boolean default false,
  p_lang text default 'de'
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
  -- The catalog's language: German, else p_lang when it has words, else English (Peter, ML1).
  v_lang text := case
    when coalesce(p_lang, 'de') = 'de' then 'de'
    when exists (select from public.catalog_words w where w.lang = p_lang) then p_lang
    else 'en'
  end;
  -- Another language's catalog (job 470 review): the typed text's words, whether its last word is
  -- one the lexicon knows (then no typo rows: "Milch" offers no "Mulch"), and whether the name's
  -- words before it are descriptors, the only words a one-word catalog word completes after
  -- ("bio mil"); anything else completes as a phrase of the catalog ("toilet p").
  v_words text[];
  v_name_words text[];
  v_known boolean := false;
  v_after_descriptors boolean := true;
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
  if v_lang <> 'de' then
    v_words := regexp_split_to_array(btrim(p_text), '\s+');
    v_known := exists (select from public.classifier_lexicon l where l.form = public.fold_key(v_last_key));
    v_name_words := regexp_split_to_array(btrim(v_typed.name), '\s+');
    v_after_descriptors := not exists (
      select from unnest(v_name_words[:array_length(v_name_words, 1) - 1]) w
      where public.normalize_item_name(w) not in (
        select d.alias from public.item_descriptors() d where d.words = 1));
  end if;
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
      select t.term, t.tier, t.sim, t.n from (
        (select distinct on (t.key) t.term, m.tier, extensions.similarity(v_last_key, t.key) as sim, 1 as n
        from (
          select d.term, d.key, d.category from public.classifier_terms d
          where v_lang = 'de' and d.lang = 'de'
          union all
          select w.word, w.key, w.category from public.catalog_words w where w.lang = v_lang
        ) t
        cross join lateral (select public.suggest_match(v_last_key, t.key) as tier) m
        where char_length(v_last_key) >= 2
          and m.tier is not null
          and t.key <> public.item_key(v_typed.name)
          and (t.category <> all (v_unserved) or char_length(v_last_key) >= 4)
          -- Only the last word is replaced, so after other words it takes a prefix or, inside a
          -- one-word term, the typed part: a typo of it would ignore them ("Rote Bete" -> "Rote
          -- Besen") and a phrase found by a later word would repeat them ("Rote Rote Beete").
          and (m.tier < 2 or v_typed.name !~ '\s' or (m.tier = 2 and t.key !~ ' '))
          and (v_lang = 'de'
            or ((m.tier < 3 or not v_known) and (v_typed.name !~ '\s' or v_after_descriptors)))
        order by t.key, char_length(t.term), t.term)
        union all
        -- Another language's phrases complete from their first words: when the text's last n words
        -- start one ("toilet p", "chicken br"), it takes their place.
        (select distinct on (w.key) w.word, case when w.key = s.tail then 0 else 1 end, 0::real, s.n
        from public.catalog_words w
        join (
          select g.n, public.item_key(array_to_string(v_words[array_length(v_words, 1) - g.n + 1:], ' ')) as tail
          from generate_series(2, case when v_lang = 'de' then 0 else coalesce(array_length(v_words, 1), 0) end) g (n)
        ) s on starts_with(w.key, s.tail)
        where v_lang <> 'de' and w.lang = v_lang
          and coalesce(array_length(string_to_array(s.tail, ' '), 1), 0) = s.n
          and w.key <> public.item_key(v_typed.name)
          and (w.category <> all (v_unserved) or char_length(s.tail) >= 4)
        order by w.key, s.n desc, char_length(w.word), w.word)
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
        case when v_lang = 'de' then p.name else upper(left(p.name, 1)) || substr(p.name, 2) end,
        p.brand, p.properties, p.quantity, p.store_id, p.category_id
      from terms t
      -- Written the way a German noun list shows it: "rote bete" -> "Rote Bete". Another
      -- language's list capitalises the name only: "Peanut butter", "Organic peanut butter".
      cross join lateral public.parse_item(p_household, regexp_replace(btrim(p_text),
        case when t.n = 1 then '\S+$' else '(\S+\s+){' || (t.n - 1) || '}\S+$' end,
        case when v_lang = 'de' then initcap(t.term) else t.term end)) p
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

revoke execute on function public.suggest_entries(uuid, text, integer, boolean, text) from public, anon;
grant execute on function public.suggest_entries(uuid, text, integer, boolean, text) to authenticated, service_role;

-- squawk-ignore ban-drop-function -- replaced in this migration by a signature that takes every old call
drop function public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean);

-- As in 20261120151031_add_separate.sql, plus p_category_guess.
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
  p_separate boolean default false,
  p_category_guess uuid default null
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
  perform set_config('family_groceries.category_guess', coalesce(p_category_guess::text, ''), true);
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
  perform set_config('family_groceries.category_guess', '', true);
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
drop function public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean);

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
  p_separate boolean default false,
  p_category_guess uuid default null
) returns setof public.items
language sql set search_path = '' as $$
  select * from public.put_item(
    p_id => p_id, p_household => p_household, p_list => null, p_name => p_name,
    p_quantity => p_quantity, p_brand => p_brand, p_properties => p_properties,
    p_category => p_category, p_store => p_store, p_sort_key => p_sort_key, p_status => p_status,
    p_no_store => p_no_store, p_category_store => p_category_store, p_separate => p_separate,
    p_category_guess => p_category_guess)
$$;

revoke execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean, uuid),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean, uuid)
from public, anon;
grant execute on function
  public.put_item(uuid, uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean, uuid),
  public.put_item(uuid, uuid, text, text, text, text, uuid, uuid, double precision, text, boolean, boolean, boolean, uuid)
to authenticated, service_role;

alter table public.items drop constraint items_categorized_via_check;
alter table public.items add constraint items_categorized_via_check
  check (categorized_via in ('household', 'exact', 'synonym', 'fuzzy', 'fallback', 'picked', 'device')) not valid;
alter table public.items validate constraint items_categorized_via_check;

-- As in 20261122010000_learned_order.sql, plus the app's guess for a word the classifier does not know.
create or replace function public.items_before_write() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_guess record;
  v_device uuid;
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
      -- A word the classifier does not know keeps the category the app guessed (put_item's
      -- p_category_guess), when it is one of the household's; it is no correction to learn.
      if tg_op = 'INSERT' and v_guess.via = 'fallback' then
        v_device := nullif(current_setting('family_groceries.category_guess', true), '')::uuid;
        if v_device is distinct from v_guess.category_id and exists (
          select from public.categories c
          where c.id = v_device and c.household_id = new.household_id
        ) then
          new.category_id := v_device;
          new.categorized_via := 'device';
        end if;
      end if;
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
  if (select h.order_mode from public.households h where h.id = new.household_id) = 'learned' then
    if tg_op = 'INSERT' or new.sort_key is null
       or (new.store_id is distinct from old.store_id
           and coalesce(current_setting('family_groceries.sort_key', true), '') <> 'keep') then
      new.sort_key := public.item_order_place(new.household_id, new.store_id,
        public.item_order_key(new.canonical_key, new.name), new.category_id);
    end if;
  elsif new.sort_key is null
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
  if tg_op = 'INSERT' and new.created_at not between '2000-01-01 00:00:00+00' and now() + interval '1 day' then
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    new.created_at := case when old.created_at between '2000-01-01 00:00:00+00' and now() + interval '1 day' then old.created_at else now() end;
    new.added_by := old.added_by;
    -- Strictly after the row's last write: the app keeps the newer of two echoes of a row, and a
    -- write whose transaction began before the last one committed (a replay in a long detection
    -- run, a tick that waited for the replay's row lock) would otherwise carry an older time.
    new.updated_at := greatest(now(), old.updated_at + interval '1 microsecond');
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

-- The current snapshot's version was taken without the words: the next call takes the new one.
update public.catalog_snapshots s set current = false where s.current;
