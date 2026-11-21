-- Job 349: the short head terms (ent, gel, kas, ...) stop taking words that merely end like them.

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
  -- A short term matches the end of any word, so a tail hit of one counts only when the typed word
  -- really ends in it: a term that lost its final e to the stem (ente is ent, käse kas) needs its
  -- spelling (Pekingente, Frischkäse, not Medikament or Element), and gel does not follow a vowel
  -- (Duschgel, not Spiegel, Kegel, Vogel). Without such a word the hit is dropped.
  if v_tier = 2 and v_len <= 3 and not exists (
    select from public.classifier_terms t
    cross join regexp_split_to_table(lower(p_name), '[^a-zäöüß]+') as w
    where t.category = v_dict and char_length(t.key) = v_len and w <> ''
      and public.fold_key(public.item_key(w)) like '%' || t.key
      and (t.term !~ 'e$' or char_length(t.term) = char_length(t.key)
           or translate(public.surface_word(w), 'äöü', 'aou') ~ (translate(public.surface_word(t.term), 'äöü', 'aou') || '(e|n|en|s|er|ern)?$'))
      and (t.key <> 'gel' or translate(public.surface_word(w), 'äöü', 'aou') !~ '[aeiou]gel(e|n|en|s)?$')
  ) then
    v_dict := null;
    v_tier := null;
    v_len := null;
  end if;
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
