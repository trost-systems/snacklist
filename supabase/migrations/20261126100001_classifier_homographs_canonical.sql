-- Job 282 review 0: the canonical key reads homographs the way the classifier does. canonical_key
-- (name) went through the key alone, so "beer" kept Beere's key wherever items.canonical_key is
-- written outside classify_item_detail (a rename, every catalog migration's backfill, the grocery
-- log): the duplicate hint offered to merge beer into Beeren. And two dictionary terms of different
-- categories on one form shared its canonical (Schäufele and Schaufel), so the hint offered to
-- merge the pork shoulder into the shovel.

-- A homograph's spelling ends the typed word, plus at most an inflection, compared as text (a
-- spelling is never read as a pattern).
create or replace function public.homograph_pick(p_homographs jsonb, p_name text, p_form text) returns jsonb
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
  where exists (
    select from unnest(array['', 'e', 'n', 'en', 's', 'es', 'er', 'ern', 'nen']) as i (ending)
    where right(word.w, char_length(e ->> 'surface') + char_length(i.ending)) = (e ->> 'surface') || i.ending
  )
  order by char_length(e ->> 'surface') desc
  limit 1;
$$;

-- As before, but dictionary terms of different categories on one form share its canonical only
-- for the first category (the form's own row); the others take their spelling, folded but not
-- stemmed (schäufele: "schaufele"), and so do their synonyms (Schäuferle).
create or replace function public.refresh_classifier_lexicon() returns void
language plpgsql set search_path = '' as $$
begin
  delete from public.classifier_lexicon;
  with terms as (
    select t.term, t.category, public.fold_key(t.key) as form, public.surface_word(t.term) as surface,
      case when t.category = min(t.category) over (partition by public.fold_key(t.key)) then public.fold_key(t.key)
           else public.fold_key(translate(public.surface_word(t.term), 'äöü', 'aou')) end as canonical
    from public.classifier_terms t
  ),
  x as (
    -- A variant's canonical wins over the term itself (karotte -> möhre).
    select public.fold_key(public.item_key(s.variant)) as form, t.canonical, t.category,
      0 as rank, public.surface_word(s.variant) as surface
    from public.classifier_synonyms s
    join terms t on t.term = s.canonical
    union all
    select t.form, t.canonical, t.category, 1, t.surface
    from terms t
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
  order by x.form, sh.form is not null and x.rank = 0, x.rank, x.category, x.canonical;

  update public.category_memory set canonical_key = public.canonical_of_key(item_key);
  update public.item_store_memory set canonical_key = public.canonical_of_key(item_key);
end $$;

-- One canonical reading for a name: the classifier's (classify_item_detail's canonical_key).
-- canonical_of_key stays for memory rows, which keep only the key.
create or replace function public.canonical_key(p_name text) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    (select string_agg(w.canonical, ' ' order by w.ord) from public.classifier_words(public.item_key(p_name), p_name) w),
    ''
  );
$$;

select public.refresh_classifier_lexicon();

alter table public.items disable trigger user;
update public.items set canonical_key = public.canonical_key(name)
where canonical_key is distinct from public.canonical_key(name);
alter table public.items enable trigger user;
