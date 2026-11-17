-- Job 282 (FX1): words the stemmer folds onto another word's key keep their own category. "beer"
-- and "Beere" both give the key "beer", "sage" and "Säge" give "sag", "rolls" and "Rolle" give
-- "roll", "Schäufele" and "Schaufel" give "schaufel"; the typed spelling decides between them.
begin;
select plan(40);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000282a1', 'hanna282@example.com');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000282a1", "role": "authenticated"}', true);
create temp table h as select id from public.create_household('Hanna');
select public.seed_hardware_categories((select id from h));

create function pg_temp.c(p_name text) returns text language sql as $$
  select c.seed_key from public.categories c
  where c.id = public.classify_item((select id from h), p_name);
$$;

select is(pg_temp.c('beer'), 'drinks', 'beer is beer, not Beere');
select is(pg_temp.c('Beer'), 'drinks', 'whatever its case');
select is(pg_temp.c('beers'), 'drinks', 'and in the plural');
select is(pg_temp.c('craft beer'), 'drinks', 'and as the head of a phrase');
select is(pg_temp.c('Bier'), 'drinks', 'Bier stays drinks');
select is(pg_temp.c('Beere'), 'produce', 'Beere stays produce');
select is(pg_temp.c('Beeren'), 'produce', 'Beeren stay produce');
select is(pg_temp.c('Waldbeeren'), 'produce', 'a compound on Beeren stays produce');

select is(pg_temp.c('rolls'), 'bakery', 'rolls are bread rolls, not Rolle');
select is(pg_temp.c('bread rolls'), 'bakery', 'bread rolls too');
select is(pg_temp.c('Brötchen'), 'bakery', 'Brötchen stay bakery');
select is(pg_temp.c('Rolle Küchenpapier'), 'household', 'Rolle Küchenpapier stays household');
select is(pg_temp.c('Küchenrolle'), 'household', 'Küchenrolle stays household');
select is(pg_temp.c('Rollen'), 'household', 'Rollen stay household');

select is(pg_temp.c('sage'), 'produce', 'sage is the herb, not Säge');
select is(pg_temp.c('Salbei'), 'produce', 'Salbei stays produce');
select is(pg_temp.c('Säge'), 'tools', 'Säge stays tools');
select is(pg_temp.c('Saege'), 'tools', 'also typed without the umlaut key');
select is(pg_temp.c('Sägen'), 'tools', 'and in the plural');

select is(pg_temp.c('Schäufele'), 'meat', 'Schäufele is the pork shoulder, not Schaufel');
select is(pg_temp.c('Schaufel'), 'garden', 'Schaufel stays garden');
select is(pg_temp.c('Schaufeln'), 'garden', 'and in the plural');
select is(pg_temp.c('Kuchenschaufel'), 'household', 'Kuchenschaufel stays household');

select is(pg_temp.c('Rohrnudeln'), 'bakery', 'Rohrnudeln are a baked yeast bun');
select is(pg_temp.c('Nudeln'), 'pantry', 'Nudeln stay pantry');

-- The canonical key follows the reading, so the duplicate hint and store memory do too.
select is((public.classify_item_detail((select id from h), 'beer')).canonical_key,
  (public.classify_item_detail((select id from h), 'Bier')).canonical_key, 'beer shares Bier''s key');
select isnt((public.classify_item_detail((select id from h), 'sage')).canonical_key,
  (public.classify_item_detail((select id from h), 'Säge')).canonical_key, 'sage does not share Säge''s key');
select is((public.classify_item_detail((select id from h), 'sage')).via, 'synonym', 'sage is found as a synonym');
select isnt((public.classify_item_detail((select id from h), 'Schäufele')).canonical_key,
  (public.classify_item_detail((select id from h), 'Schaufel')).canonical_key, 'Schäufele does not share Schaufel''s key');
select is((public.classify_item_detail((select id from h), 'Schäuferle')).canonical_key,
  (public.classify_item_detail((select id from h), 'Schäufele')).canonical_key, 'Schäuferle is Schäufele');
select is(pg_temp.c('Schäuferla'), 'meat', 'and so is Schäuferla');
select is(pg_temp.c('spring rolls'), 'frozen', 'spring rolls are Frühlingsrollen, not bread rolls');
select is(pg_temp.c('cinnamon rolls'), 'bakery', 'cinnamon rolls are bread rolls');

-- Review 0: one canonical reading. canonical_key(name), which renames, catalog backfills and the
-- grocery log write, equals the classifier's for every dictionary term, synonym and homograph.
select is(
  (select count(*)::int from (
     select n from (
       select term as n from public.classifier_terms
       union select variant from public.classifier_synonyms
       union select unnest(array['beer', 'beers', 'Beeren', 'rolls', 'Rollen', 'sage', 'Säge', 'Saege',
                                 'Schäufele', 'Schaufel', 'Schaufeln', 'Waldbeeren', 'craft beer'])
     ) names
     where public.canonical_key(n) is distinct from (public.classify_item_detail((select id from h), n)).canonical_key
   ) x),
  0, 'canonical_key(name) is the classifier''s canonical key'
);
insert into public.items (household_id, name) select id, 'Bier' from h;
update public.items set name = 'beer' where household_id = (select id from h) and name = 'Bier';
select is((select canonical_key from public.items where household_id = (select id from h) and name = 'beer'),
  public.canonical_key('Bier'), 'Bier renamed to beer keeps Bier''s key');
select isnt((select canonical_key from public.items where household_id = (select id from h) and name = 'beer'),
  public.canonical_key('Beeren'), 'not Beeren''s');
insert into public.items (household_id, name) select id, 'Schaufel' from h;
select isnt((select canonical_key from public.items where household_id = (select id from h) and name = 'Schaufel'),
  public.canonical_key('Schäufele'), 'a Schaufel on the list is not the Schäufele about to be added');
select is(public.canonical_key('sage'), 'salbei', 'sage keeps Salbei''s key');

-- The lexicon keeps one row per form, the dictionary term's, so readers without the typed text
-- (stored memories, the app's bundled catalog) read the German word as before.
select is((select category from public.classifier_lexicon where form = 'beer'), 'produce', 'the form beer is Beere''s');
select is(
  (select count(*)::int from public.classifier_lexicon l
   where l.homographs is not null
     and (select count(distinct e ->> 'category') from jsonb_array_elements(l.homographs) e) < 2),
  0, 'homographs are listed only for forms shared by words of different categories'
);
select * from finish();
rollback;
