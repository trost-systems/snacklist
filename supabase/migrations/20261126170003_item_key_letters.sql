-- Job 470 review: a language besides German and English is data only (Addendum 2). The classifier's
-- words may hold the lower-case letters of Latin-1 and Latin Extended-A (and Romanian ș, ț), and
-- item_key folds them as it folds French accents, where it used to split the word at them
-- (őszibarack was "szibarack", smør "sm r"). The app's itemKey (app/lib/list/entry.dart) folds the
-- same; supabase/tests/item_keys.tsv is the table both pass.
--
-- Items named with such letters get their new canonical key, and the household's memory of them
-- (categories, stores, cleared stores, order) moves to the new keys where one name gives one new
-- key and the new key has no row yet; other rows stay under the old key and are learned again.

alter table public.classifier_terms drop constraint classifier_terms_term_check;
alter table public.classifier_terms add constraint classifier_terms_term_check
  check (term ~ '^[a-zß-öø-ÿā-žșț]+( [a-zß-öø-ÿā-žșț]+)*$') not valid;
alter table public.classifier_terms validate constraint classifier_terms_term_check;
alter table public.classifier_synonyms drop constraint classifier_synonyms_variant_check;
alter table public.classifier_synonyms add constraint classifier_synonyms_variant_check
  check (variant ~ '^[a-zß-öø-ÿā-žșț]+( [a-zß-öø-ÿā-žșț]+)*$') not valid;
alter table public.classifier_synonyms validate constraint classifier_synonyms_variant_check;
alter table public.classifier_synonyms drop constraint classifier_synonyms_canonical_check;
alter table public.classifier_synonyms add constraint classifier_synonyms_canonical_check
  check (canonical ~ '^[a-zß-öø-ÿā-žșț]+( [a-zß-öø-ÿā-žșț]+)*$') not valid;
alter table public.classifier_synonyms validate constraint classifier_synonyms_canonical_check;

-- The names whose key changes, with their keys before.
create temp table item_key_moves as
select distinct i.household_id, i.name, public.item_key(i.name) as old_key, i.canonical_key as old_canonical,
  null::text as new_key, null::text as new_canonical
from public.items i
where i.name ~ '[æœðþøĳŋØÆŒÐÞĲŊĀ-ſȘșȚțİ]';

-- As in 20261022233800_classifier_stores.sql, with the letters of other languages folded.
create or replace function public.item_key(p_name text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v text := lower(coalesce(p_name, ''));
begin
  v := replace(replace(replace(replace(v, 'ä', 'a'), 'ö', 'o'), 'ü', 'u'), 'ß', 'ss');
  -- chr(775): the dot lower() leaves of a Turkish İ.
  v := replace(replace(replace(replace(replace(replace(replace(replace(v,
    'æ', 'ae'), 'œ', 'oe'), 'ð', 'd'), 'þ', 'th'), 'ĳ', 'ij'), 'ŋ', 'ng'), 'ŉ', 'n'), chr(775), '');
  v := translate(v, 'àáâãåçèéêëìíîïñòóôõùúûýÿ', 'aaaaaceeeeiiiinooooouuuyy');
  -- Apart from the line above, whose two strings differ in length (ù is o, ý u) and whose keys
  -- are stored: Latin Extended-A, ø, ș and ț.
  v := translate(v, 'āăąćĉċčďđēĕėęěĝğġģĥħĩīĭįıĵķĺļľŀłńņňōŏőŕŗřśŝşšţťŧũūŭůűųŵŷźżžøșț', 'aaaccccddeeeeegggghhiiiiijklllllnnnooorrrsssstttuuuuuuwyzzzost');
  v := replace(replace(replace(v, 'ae', 'a'), 'oe', 'o'), 'ue', 'u');
  v := regexp_replace(
    v,
    '(^|[^a-z0-9])[0-9]+([.,][0-9]+)?\s*(x|kg|gr|g|ml|l|stk|stuck|pck|packungen|packung|dosen|dose|flaschen|flasche|bund|becher|glaser|glas|tuten|tute|beutel|netz|kisten|kiste|kasten|pfund|liter|kilo|gramm|rollen|rolle|tafeln|tafel|stangen|stange|%)?(?![a-z])',
    ' ', 'g'
  );
  v := regexp_replace(v, '[^a-z]+', ' ', 'g');
  return coalesce(
    (select string_agg(public.stem_word(w), ' ' order by ord)
     from unnest(string_to_array(btrim(v), ' ')) with ordinality as t (w, ord)
     where w <> ''),
    ''
  );
end $$;

update item_key_moves set new_key = public.item_key(name), new_canonical = public.canonical_key(name);

create temp table item_key_map as
select household_id, old_key, min(new_key) as new_key
from item_key_moves where old_key <> new_key and new_key <> ''
group by household_id, old_key having count(distinct new_key) = 1;
create temp table canonical_key_map as
select household_id, old_canonical as old_key, min(new_canonical) as new_key
from item_key_moves where old_canonical <> new_canonical and new_canonical <> ''
group by household_id, old_canonical having count(distinct new_canonical) = 1;

update public.category_memory m set item_key = k.new_key
from item_key_map k
where m.household_id = k.household_id and m.item_key = k.old_key
  and not exists (select from public.category_memory o
                  where o.household_id = m.household_id and o.item_key = k.new_key and o.category_id = m.category_id);
update public.item_store_memory m set item_key = k.new_key
from item_key_map k
where m.household_id = k.household_id and m.item_key = k.old_key
  and not exists (select from public.item_store_memory o
                  where o.household_id = m.household_id and o.item_key = k.new_key and o.store_id = m.store_id);
update public.item_store_cleared m set item_key = k.new_key
from item_key_map k
where m.household_id = k.household_id and m.item_key = k.old_key
  and not exists (select from public.item_store_cleared o where o.household_id = m.household_id and o.item_key = k.new_key);
-- Its key is the canonical key (public.item_order_key).
update public.item_order_memory m set item_key = k.new_key
from canonical_key_map k
where m.household_id = k.household_id and m.item_key = k.old_key
  and not exists (select from public.item_order_memory o
                  where o.household_id = m.household_id and o.item_key = k.new_key
                    and o.store_id is not distinct from m.store_id);

alter table public.items disable trigger user;
update public.items i set canonical_key = public.canonical_key(i.name)
where i.name ~ '[æœðþøĳŋØÆŒÐÞĲŊĀ-ſȘșȚțİ]';
alter table public.items enable trigger user;

-- The memory's canonical keys follow its item keys.
select public.refresh_classifier_lexicon();

-- squawk-ignore ban-drop-table -- the temp tables this migration made, not part of the schema
drop table item_key_moves, item_key_map, canonical_key_map;
