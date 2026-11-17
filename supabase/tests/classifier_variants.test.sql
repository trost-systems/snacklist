-- Job 32a (Spec #8 Part A): spelling variants, synonyms and typos classify like the word they mean,
-- through every add path; a household's correction holds for its variants; the typed text stays
-- as typed. The word-list rates (AC4) and the latency (AC8) are supabase/classifier/wordlist.sh
-- and latency.sh in the db gate.
begin;
select plan(57);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000032c1', 'carla32@example.com'),
  ('00000000-0000-0000-0000-0000000032d1', 'dora32@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000032d1');
create temp table hd as select id from public.create_household('Dora');
select pg_temp.login('00000000-0000-0000-0000-0000000032c1');
create temp table hc as select id from public.create_household('Carla');
grant select on hc, hd to authenticated;

create function pg_temp.seed(p_category uuid) returns text language sql as $$
  select coalesce(seed_key, name) from public.categories where id = p_category;
$$;

create function pg_temp.cat(p_household uuid, p_seed text) returns uuid language sql as $$
  select id from public.categories where household_id = p_household and seed_key = p_seed;
$$;

-- Carla's category for a name, through the classifier.
create function pg_temp.c(p_name text) returns text language sql as $$
  select pg_temp.seed(public.classify_item((select id from hc), p_name));
$$;

create function pg_temp.via(p_name text) returns text language sql as $$
  select via from public.classify_item_detail((select id from hc), p_name);
$$;

-- AC1: the beta's carrots.
select is(pg_temp.c(x), 'produce', format('%s is Obst & Gemüse', x))
from unnest(array['Karrotten', 'Karotten', 'Karotte', 'Möhre', 'Möhren', 'Mohrrüben']) as x;
select is(
  (select count(distinct public.canonical_key(x))::int
   from unnest(array['Karrotten', 'Karotten', 'Karotte', 'Möhre', 'Möhren', 'Mohrrüben', 'Gelbe Rüben', 'carrots']) as x),
  1, 'and they share one canonical key'
);

-- AC2: case, umlaut and ß spellings, plural and singular, doubled letters.
select is(public.canonical_key(x), public.canonical_key('Möhren'), format('%s folds to Möhren', x))
from unnest(array['MOEHREN', 'moehre', 'Möhre']) as x;
select is(public.canonical_key('Weisskohl'), public.canonical_key('Weißkohl'), 'ss spells ß');
select is(public.canonical_key('Suesskartoffeln'), public.canonical_key('Süßkartoffel'), 'ue and ss, plural and singular');
select is(public.canonical_key('Tomatten'), public.canonical_key('Tomaten'), 'doubled letters fold');
select is(public.canonical_key('Joghurt'), public.canonical_key('Jogurt'), 'gh folds');
select is(public.canonical_key('Broccoli'), public.canonical_key('Brokkoli'), 'c and ck fold to k');
select is(pg_temp.c('Hänchenbrust'), 'meat', 'a dropped h folds: Hänchenbrust');

-- AC3: no fuzzy match between real words, none for short words.
select is(pg_temp.c('Milch'), 'chilled', 'Milch');
select is(pg_temp.c('Mehl'), 'pantry', 'Mehl');
select is(pg_temp.c('Reis'), 'pantry', 'Reis');
select is(pg_temp.c('Eis'), 'frozen', 'Eis');
select is(pg_temp.c('Brot'), 'bakery', 'Brot');
select is(pg_temp.c('Rot'), 'other', 'Rot is not Brot');
select is(pg_temp.c('Mehk'), 'other', 'a 4-letter typo is not guessed');
select is(pg_temp.c('Tisch'), 'other', 'a 5-letter word one letter from a term (Tusche) is not guessed');
select is(pg_temp.c('Kasse'), 'other', 'short words keep their doubled letters: Kasse is not Käse');
select is((public.lexicon_fuzzy('milch')).form, null, 'Milch has no fuzzy neighbour');
select is(
  (select count(*)::int from public.classifier_terms t, public.classifier_words(t.key) w where w.how = 'fuzzy'),
  0, 'no dictionary term is read as a typo of another'
);
select is(pg_temp.c('tea'), 'pantry', 'a 3-letter word matches through the synonym table');
select is(pg_temp.c('Mlich'), 'chilled', 'a swap in a 5-letter word is a typo: Mlich');

-- How each was found.
select results_eq(
  $$ select pg_temp.via(x) from unnest(array['Milch', 'Karrotten', 'Paradeiser', 'Schokolde', 'Quietscheentchen']) as x $$,
  $$ values ('exact'), ('exact'), ('synonym'), ('fuzzy'), ('fallback') $$,
  'via: dictionary, folded spelling, synonym, typo, fallback'
);

-- The lexicon is consistent with the dictionary and the synonyms.
select is(
  (select count(*)::int from (
     select public.fold_key(key) as form from public.classifier_terms group by 1 having count(distinct category) > 1) x
   where not exists (select from public.classifier_lexicon l where l.form = x.form and l.homographs is not null)),
  0, 'dictionary terms of different categories that fold to one form are its homographs (job 282)'
);
select is(
  (select count(*)::int from public.classifier_synonyms s
   where not exists (select from public.classifier_terms t where t.term = s.canonical)),
  0, 'every synonym points to a dictionary term'
);
select is(
  (select count(*)::int from public.classifier_terms t
   join public.classifier_lexicon l on l.form = public.fold_key(t.key)
   where l.category <> t.category
     and not exists (select from jsonb_array_elements(l.homographs) e
                     where e ->> 'surface' = public.surface_word(t.term) and e ->> 'category' = t.category)),
  0, 'every term keeps its category in the lexicon, as its row or one of its homographs'
);

-- AC5 and AC7: every add path stores the text as typed and classifies the same.
insert into public.items (household_id, name) select id, 'Karrotten' from hc;
select results_eq(
  $$ select name, quantity, pg_temp.seed(category_id), canonical_key = public.canonical_key('Möhren'), categorized_via
     from public.items where household_id = (select id from hc) and name = 'Karrotten' $$,
  $$ values ('Karrotten', null::text, 'produce', true, 'exact') $$,
  'the app path (an insert): text as typed, category, canonical key and via'
);
select results_eq(
  $$ select name, quantity, pg_temp.seed(category_id), categorized_via
     from public.add_items((select id from hc), array['2 Paradeiser', 'Schokolde', 'Mohrrüben']) $$,
  $$ values ('Paradeiser', '2', 'produce', 'synonym'), ('Schokolde', null, 'sweets', 'fuzzy'),
            ('Mohrrüben', null, 'produce', 'exact') $$,
  'add_items (MCP, Siri, voice, Alexa) keeps the text and classifies the same'
);
select results_eq(
  $$ select name, pg_temp.seed(category_id) from public.add_item((select id from hc), 'Brokoli') $$,
  $$ values ('Brokoli', 'produce') $$,
  'add_item keeps the text and classifies the same'
);
select results_eq(
  $$ select p.name, pg_temp.seed(p.category_id) from public.parse_item((select id from hc), 'Zuchini') p $$,
  $$ values ('Zuchini', 'produce') $$,
  'parse_item (the add sheet) classifies the same'
);
select results_eq(
  $$ select s.name, pg_temp.seed(s.category_id) from public.suggest_entries((select id from hc), 'Karfiol') s
     where s.source = 'typed' $$,
  $$ values ('Karfiol', 'produce') $$,
  'suggest_entries'' typed row classifies the same'
);
select is(
  (select count(*)::int from public.items where household_id = (select id from hc)
     and name in ('Karrotten', 'Paradeiser', 'Schokolde', 'Mohrrüben', 'Brokoli')),
  5, 'every add wrote its own row with the typed name'
);

-- categorized_via on inserts that bring a category: the guess, or picked.
insert into public.items (household_id, name, category_id)
select id, 'Spagetti', pg_temp.cat(id, 'pantry') from hc;
insert into public.items (household_id, name, category_id)
select id, 'Quark', pg_temp.cat(id, 'sweets') from hc;
select results_eq(
  $$ select name, categorized_via from public.items
     where household_id = (select id from hc) and name in ('Spagetti', 'Quark') order by name $$,
  $$ values ('Quark', 'picked'), ('Spagetti', 'exact') $$,
  'an insert with the guessed category keeps how it was guessed; another one is picked'
);
select is(pg_temp.c('Quark'), 'sweets', 'a picked category is learned as before');
select is(pg_temp.via('Topfen'), 'household', 'and holds for its synonym Topfen');

-- AC6: a household's move of a variant holds for that variant and its variants, only there.
update public.items set category_id = pg_temp.cat((select id from hc), 'drinks') where name = 'Karrotten';
select is(pg_temp.c(x), 'drinks', format('after Carla moved Karrotten, %s goes there too', x))
from unnest(array['Karrotten', 'karroten', 'Karotten', 'Möhren']) as x;
select is(pg_temp.via('Möhren'), 'household', 'via household');
select is(pg_temp.c('Kartoffeln'), 'produce', 'other words are unaffected');
update public.items set category_id = pg_temp.cat((select id from hc), 'household')
where name = 'Brokoli';
select is(pg_temp.c('Brokkoli'), 'household', 'a corrected typo holds for the right spelling');
insert into public.items (household_id, name) select id, 'Quietscheentchen' from hc;
update public.items set category_id = pg_temp.cat((select id from hc), 'sweets') where name = 'Quietscheentchen';
select is(pg_temp.c('Quitscheentchen'), 'sweets', 'a typo of a corrected word the dictionary does not know');
select is(pg_temp.via('Quitscheentchen'), 'fuzzy', 'is found fuzzily in the household''s corrections');

select pg_temp.login('00000000-0000-0000-0000-0000000032d1');
select is(pg_temp.seed(public.classify_item((select id from hd), 'Möhren')), 'produce',
  'another household is unaffected by Carla''s move');
select is(pg_temp.seed(public.classify_item((select id from hd), 'Quitscheentchen')), 'other',
  'nor by her corrections of unknown words');
select throws_ok(
  $$ select public.classify_item_detail((select id from hc), 'Möhren') $$,
  '42501', 'not_a_member', 'classify_item_detail for another household is denied'
);
select pg_temp.login('00000000-0000-0000-0000-0000000032c1');

-- The store memory follows the canonical key too (guess_store, parse_item, the insert).
update public.items set store_id = public.add_store((select id from hc), 'Wochenmarkt')
where name = 'Mohrrüben';
select is(
  (select name from public.stores where id = public.guess_store((select id from hc), 'Karotten', null, null)),
  'Wochenmarkt', 'a store remembered for Mohrrüben is guessed for Karotten'
);
insert into public.items (household_id, name) select id, 'Gelbe Rüben' from hc;
select is(
  (select s.name from public.items i join public.stores s on s.id = i.store_id
   where i.household_id = (select id from hc) and i.name = 'Gelbe Rüben'),
  'Wochenmarkt', 'and an insert of Gelbe Rüben lands there'
);

-- A renamed item gets the new name's canonical key; the text stays as typed.
update public.items set name = 'Erdäpfel' where name = 'Schokolde';
select results_eq(
  $$ select name, canonical_key = public.canonical_key('Kartoffel') from public.items where name = 'Erdäpfel' $$,
  $$ values ('Erdäpfel', true) $$,
  'a rename updates the canonical key'
);

select * from finish();
rollback;
