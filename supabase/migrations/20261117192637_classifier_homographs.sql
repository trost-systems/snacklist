-- Job 282 (FX1): words the stemmer folds onto another word's key keep their own category. item_key
-- drops a final e and a plural s and folds umlauts, so "beer" and "Beere" both give "beer", "sage"
-- and "Säge" "sag", "rolls" and "Rolle" "roll", "Schäufele" and "Schaufel" "schaufel". The lexicon
-- kept one of them per form and the dictionary's whole-key rule the other, so no catalog row could
-- file beer with drinks. Now a form shared by words of different categories lists each word's
-- spelling, and the classifier reads the typed text to pick the one it is.

-- For a form that words of different categories share: each one's spelling (public.surface_word),
-- canonical, category and whether it is a synonym. Null for every other form.
alter table public.classifier_lexicon add column homographs jsonb;

-- A word as typed, for telling homographs apart: lowercase, ß -> ss, accents dropped, but umlauts
-- kept (ae, oe and ue written as ä, ö and ü) and nothing stemmed. "Säge" and "Saege" give "säge",
-- "sage" stays "sage".
create function public.surface_word(p_word text) returns text
language sql immutable set search_path = '' as $$
  select replace(replace(replace(replace(
    translate(lower(coalesce(p_word, '')), 'àáâãåçèéêëìíîïñòóôõùúûýÿ', 'aaaaaceeeeiiiinooooouuuyy'),
    'ß', 'ss'), 'ae', 'ä'), 'oe', 'ö'), 'ue', 'ü');
$$;

-- Which of a form's homographs the name means: the last word of the name whose key ends with the
-- form, read as typed, ends with the homograph's spelling and at most an inflection (Beeren is
-- beere + n, beers is beer + s); the longest spelling wins (Beeren is Beere, not beer + en). Null
-- when none fits, and the form's own row stands.
create function public.homograph_pick(p_homographs jsonb, p_name text, p_form text) returns jsonb
language sql stable set search_path = '' as $$
  with word as (
    select t.w
    from regexp_split_to_table(public.surface_word(p_name), '[^a-zäöü]+') with ordinality as t (w, ord)
    where t.w <> '' and public.fold_key(public.item_key(t.w)) like '%' || p_form
    order by t.ord desc
    limit 1
  )
  select e
  from word, jsonb_array_elements(p_homographs) as e
  where word.w ~ ('(' || (e ->> 'surface') || ')(e|n|en|s|es|er|ern|nen)?$')
  order by char_length(e ->> 'surface') desc
  limit 1;
$$;

-- The lexicon as before, plus each shared form's homographs. A shared form's own row is the
-- dictionary term's, not a synonym's, so readers without the typed text (stored memories, the
-- app's bundled catalog) read the German word as before.
create or replace function public.refresh_classifier_lexicon() returns void
language plpgsql set search_path = '' as $$
begin
  delete from public.classifier_lexicon;
  with x as (
    -- A variant's canonical wins over the term itself (karotte -> möhre).
    select public.fold_key(public.item_key(s.variant)) as form, public.fold_key(t.key) as canonical, t.category,
      0 as rank, public.surface_word(s.variant) as surface
    from public.classifier_synonyms s
    join public.classifier_terms t on t.term = s.canonical
    union all
    select public.fold_key(t.key), public.fold_key(t.key), t.category, 1, public.surface_word(t.term)
    from public.classifier_terms t
  ),
  spellings as (
    select distinct on (x.form, x.surface) x.form, x.surface, x.canonical, x.category,
      x.rank = 0 and not exists (select from public.classifier_terms t where public.surface_word(t.term) = x.surface) as synonym
    from x
    where x.form <> '' and x.form not like '% %'
    order by x.form, x.surface, x.rank, x.canonical
  ),
  shared as (
    select s.form,
      jsonb_agg(jsonb_build_object('surface', s.surface, 'canonical', s.canonical, 'category', s.category, 'synonym', s.synonym)
        order by s.surface) as homographs
    from spellings s
    group by s.form
    having count(distinct s.category) > 1
  )
  insert into public.classifier_lexicon (form, canonical, category, synonym, homographs)
  select distinct on (x.form) x.form, x.canonical, x.category,
    not exists (select from public.classifier_terms t where public.fold_key(t.key) = x.form),
    sh.homographs
  from x
  left join shared sh on sh.form = x.form
  where x.form <> ''
  order by x.form, sh.form is not null and x.rank = 0, x.rank, x.canonical, x.category;

  update public.category_memory set canonical_key = public.canonical_of_key(item_key);
  update public.item_store_memory set canonical_key = public.canonical_of_key(item_key);
end $$;

-- public.classifier_words with the name the key came from: a word whose form has homographs takes
-- the one the typed word spells (public.homograph_pick).
create function public.classifier_words(p_key text, p_name text)
returns table (ord integer, word text, canonical text, category text, how text, len integer)
language plpgsql stable set search_path = '' as $$
declare
  v_words text[] := string_to_array(public.fold_key(p_key), ' ');
  v_folded text;
  v_phrases public.classifier_lexicon[] := '{}'::public.classifier_lexicon[];
  v_phrase public.classifier_lexicon;
  v_hit public.classifier_lexicon;
  v_fuzzy public.classifier_lexicon;
  v_pick jsonb;
  v_word text;
  v_n integer := 0;
begin
  if coalesce(cardinality(v_words), 0) = 0 or v_words = '{""}' then
    return;
  end if;
  -- Phrases first, longest first; each becomes one token (#n).
  if cardinality(v_words) > 1 then
    v_folded := ' ' || array_to_string(v_words, ' ') || ' ';
    for v_phrase in
      select l.* from public.classifier_lexicon l
      where l.form = any (array(
        select array_to_string(v_words[a:b], ' ')
        from generate_series(1, cardinality(v_words)) as a cross join generate_series(a + 1, cardinality(v_words)) as b
      ))
      order by l.len desc
    loop
      continue when v_folded not like '% ' || v_phrase.form || ' %';
      v_phrases := v_phrases || v_phrase;
      v_folded := replace(v_folded, ' ' || v_phrase.form || ' ', ' #' || cardinality(v_phrases) || ' ');
    end loop;
    v_words := string_to_array(btrim(v_folded), ' ');
  end if;

  foreach v_word in array v_words loop
    v_n := v_n + 1;
    ord := v_n;
    word := v_word;
    canonical := v_word;
    category := null;
    how := null;
    len := null;
    v_hit := null;
    v_fuzzy := null;
    if v_word ~ '^#[0-9]+$' then
      v_hit := v_phrases[substr(v_word, 2)::integer];
      word := v_hit.form;
    else
      -- The word, else the longest form of 4+ letters it ends with (a compound).
      select l.* into v_hit from public.classifier_lexicon l
      where l.form = any (array(
        select substr(v_word, i) from generate_series(1, greatest(char_length(v_word) - 3, 1)) as i
      ))
      order by l.len desc
      limit 1;
      if v_hit.homographs is not null and p_name is not null then
        v_pick := public.homograph_pick(v_hit.homographs, p_name, v_hit.form);
        if v_pick is not null then
          v_hit.canonical := v_pick ->> 'canonical';
          v_hit.category := v_pick ->> 'category';
          v_hit.synonym := (v_pick ->> 'synonym')::boolean;
        end if;
      end if;
      if v_hit.form is null or char_length(v_word) - v_hit.len >= 4 then
        select f.form, f.canonical, f.category into v_fuzzy.form, v_fuzzy.canonical, v_fuzzy.category
        from public.lexicon_fuzzy(v_word, case when v_hit.form is null then 2 else 1 end) f
        where v_hit.form is null or (f.len >= v_hit.len + 4 and f.form not like '%' || v_hit.form);
      end if;
    end if;
    if v_fuzzy.form is not null then
      canonical := v_fuzzy.canonical;
      category := v_fuzzy.category;
      how := 'fuzzy';
      len := char_length(v_fuzzy.form);
    elsif v_hit.form is not null then
      canonical := case when v_word ~ '^#' then v_hit.canonical
                        else left(v_word, char_length(v_word) - v_hit.len) || v_hit.canonical end;
      category := v_hit.category;
      how := case when v_hit.synonym then 'synonym' else 'exact' end;
      len := v_hit.len;
    end if;
    return next;
  end loop;
end $$;

create or replace function public.classifier_words(p_key text)
returns table (ord integer, word text, canonical text, category text, how text, len integer)
language sql stable set search_path = '' as $$
  select * from public.classifier_words(p_key, null);
$$;

create or replace function public.classify_item_detail(
  p_household uuid, p_name text, out category_id uuid, out via text, out canonical_key text
) returns record
language plpgsql stable security definer set search_path = '' as $$
declare
  v_key text := public.item_key(p_name);
  v_dict text;
  v_tier integer;
  v_len integer;
  v_word record;
  v_exact_category text;
  v_exact_how text;
  v_exact_len integer;
  v_exact_ord integer;
  v_exact_form text;
  v_fuzzy_category text;
  v_fuzzy_len integer;
  v_fuzzy_ord integer;
  v_seed text;
  v_max integer;
  v_canonical text;
begin
  -- Signed-in callers may classify only for their own household; service role and the database
  -- itself (no auth.uid()) are trusted server paths.
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  -- One reading of the words: the canonical key, the head the lexicon recognizes exactly or as a
  -- synonym, and the head it recognizes fuzzily.
  for v_word in select * from public.classifier_words(v_key, p_name) w order by w.ord loop
    v_canonical := concat_ws(' ', v_canonical, v_word.canonical);
    if v_word.how in ('exact', 'synonym') then
      v_exact_category := v_word.category;
      v_exact_how := v_word.how;
      v_exact_len := v_word.len;
      v_exact_ord := v_word.ord;
      v_exact_form := right(v_word.word, v_word.len);
    elsif v_word.how = 'fuzzy' then
      v_fuzzy_category := v_word.category;
      v_fuzzy_len := v_word.len;
      v_fuzzy_ord := v_word.ord;
    end if;
  end loop;
  v_canonical := coalesce(v_canonical, '');
  canonical_key := v_canonical;

  select m.category_id into category_id
  from public.category_memory m
  where m.household_id = p_household and m.item_key = v_key
  order by m.updated_at desc, m.corrections desc
  limit 1;
  if category_id is null and v_canonical <> '' then
    select m.category_id into category_id
    from public.category_memory m
    where m.household_id = p_household and m.canonical_key = v_canonical
    order by m.updated_at desc, m.corrections desc
    limit 1;
  end if;
  if category_id is not null then
    via := 'household';
    return;
  end if;

  select h.category, h.tier, h.len into v_dict, v_tier, v_len from public.dictionary_hit(v_key) h;
  -- The dictionary's strong rules win. Its hit on a homograph's form loses to the homograph the
  -- typed text spells (beer is not Beere). A compound it matched only by its end loses to a longer
  -- form the lexicon recognizes after folding (Erdnusbutter is Erdnussbutter, pantry, not
  -- butter), or to a much longer one a typo away (Feuchttüscher).
  if v_tier in (2, 4) and v_exact_len >= v_len and v_exact_category <> v_dict
     and exists (select from public.classifier_lexicon l where l.form = v_exact_form and l.homographs is not null) then
    v_seed := v_exact_category;
    via := v_exact_how;
  elsif v_tier = 2 and v_exact_len > v_len then
    v_seed := v_exact_category;
    via := v_exact_how;
  elsif v_tier = 2 and v_fuzzy_len >= v_len + 4 and v_fuzzy_ord >= coalesce(v_exact_ord, 0) then
    v_seed := v_fuzzy_category;
    via := 'fuzzy';
  elsif v_tier >= 2 then
    v_seed := v_dict;
    via := 'exact';
  elsif v_exact_category is not null then
    v_seed := v_exact_category;
    via := v_exact_how;
  end if;

  if v_seed is null and char_length(v_canonical) >= 6 then
    v_max := case when char_length(v_canonical) >= 8 then 2 else 1 end;
    with nearest as (
      select m.category_id, extensions.levenshtein_less_equal(v_canonical, m.canonical_key, v_max) as distance
      from public.category_memory m
      where m.household_id = p_household and left(m.canonical_key, 1) = left(v_canonical, 1)
        and abs(char_length(m.canonical_key) - char_length(v_canonical)) <= v_max
    )
    select min(n.category_id::text)::uuid into category_id
    from nearest n
    where n.distance = (select min(distance) from nearest) and n.distance <= v_max
    having count(distinct n.category_id) = 1;
    if category_id is not null then
      via := 'fuzzy';
      return;
    end if;
  end if;

  if v_seed is null and v_fuzzy_category is not null then
    v_seed := v_fuzzy_category;
    via := 'fuzzy';
  end if;

  if v_seed is null and v_tier = 1 then
    v_seed := v_dict;
    via := 'exact';
  end if;

  category_id := (
    select c.id from public.categories c
    where c.household_id = p_household and v_seed is not null
      and (c.seed_key = v_seed or v_seed = any (c.absorbed_seed_keys))
    order by c.seed_key = v_seed desc
    limit 1
  );
  -- Without the Baumarkt's categories a DIY word goes where it went before them: Haushalt.
  if category_id is null and exists (select from public.hardware_categories() h where h.seed_key = v_seed) then
    category_id := (
      select c.id from public.categories c
      where c.household_id = p_household and (c.seed_key = 'household' or 'household' = any (c.absorbed_seed_keys))
      order by c.seed_key = 'household' desc
      limit 1
    );
  end if;
  if category_id is null then
    category_id := (select c.id from public.categories c where c.household_id = p_household and c.seed_key = 'other');
    via := 'fallback';
  end if;
end $$;

revoke execute on function
  public.surface_word(text),
  public.homograph_pick(jsonb, text, text),
  public.classifier_words(text, text)
from public, anon;
grant execute on function
  public.surface_word(text),
  public.homograph_pick(jsonb, text, text),
  public.classifier_words(text, text)
to authenticated;

select public.refresh_classifier_lexicon();
