-- Job 470: English is a catalog language (Peter: CP4, ML1, Addendum 2). The catalog's German terms
-- stay what released apps get; every other language's words come under 'words'; the classifier
-- files English and German names alike for every household; suggest_entries offers the words of
-- p_lang (else English); put_item keeps the app's category for a word the classifier does not know,
-- without learning it, and never overrides a word it knows. Released apps' calls bind as before.
begin;
select plan(38);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000470a01', 'en470@example.com'),
  ('00000000-0000-0000-0000-000000470b01', 'other470@example.com');
select pg_temp.login('00000000-0000-0000-0000-000000470b01');
create temp table hb as select id from public.create_household('Other 470');
select pg_temp.login('00000000-0000-0000-0000-000000470a01');
create temp table h as select id from public.create_household('English 470');
grant select on h, hb to authenticated;
create temp table cat as
select c.seed_key, c.id from public.categories c where c.household_id = (select id from h);
reset role;
create temp table other_cat as
select c.seed_key, c.id from public.categories c where c.household_id = (select id from hb);
grant select on cat, other_cat to authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000470a01');

create function pg_temp.seed_of(p_name text) returns text language sql as $$
  select c.seed_key from public.categories c
  where c.id = public.classify_item((select id from h), p_name)
$$;

-- The catalog: German terms for released apps, every other language's words apart.
reset role;
select is(
  (select count(*) from jsonb_array_elements(public.catalog_rows() -> 'terms')),
  (select count(*) from public.classifier_terms where lang = 'de'),
  'catalog_rows().terms are the German terms, as released apps read them'
);
select ok(
  exists (select from public.classifier_terms where lang = 'en')
  and not exists (
    select from jsonb_array_elements(public.catalog_rows() -> 'terms') e
    join public.classifier_terms t on t.term = e ->> 0 where t.lang <> 'de'),
  'English concepts of their own are classifier terms, but no catalog term'
);
select is(
  (select e from jsonb_array_elements(public.catalog_rows() -> 'words') e where e ->> 0 = 'en:milk'),
  '["en:milk", "milk", "chilled", false]'::jsonb,
  'milk is an English word on the German concept Milch'
);
select ok(
  exists (select from jsonb_array_elements(public.catalog_rows() -> 'words') e where (e ->> 3)::boolean),
  'words that are concepts of their own say so'
);
select is(
  (select count(distinct split_part(e ->> 0, ':', 1)) from jsonb_array_elements(public.catalog_rows() -> 'words') e),
  1::bigint, 'one language besides German: English'
);

-- The classifier files English and German names, for every household.
select pg_temp.login('00000000-0000-0000-0000-000000470a01');
select is(pg_temp.seed_of('milk'), 'chilled', 'milk is chilled');
select is(pg_temp.seed_of('Milch'), 'chilled', 'Milch is still chilled');
select is(pg_temp.seed_of('peanut butter'), 'pantry', 'peanut butter is pantry, not chilled by its head');
select is(pg_temp.seed_of('orange juice'), 'drinks', 'orange juice is drinks, not produce by orange');
select is(pg_temp.seed_of('eggplant'), 'produce', 'eggplant (US) is produce');
select is(pg_temp.seed_of('aubergine'), 'produce', 'aubergine (UK) is produce');
select is(pg_temp.seed_of('nappies'), 'drugstore', 'nappies (UK) are drugstore');
select is(pg_temp.seed_of('frozen peas'), 'frozen', 'frozen peas are frozen');
select is(pg_temp.seed_of('cat food'), 'household', 'cat food is household');
select is(pg_temp.seed_of('tomatoes'), 'produce', 'a plural is its word');
select is(
  public.canonical_key('milk'), public.canonical_key('Milch'),
  'milk and Milch are one item for the duplicate hint and the store memory'
);

-- suggest_entries: German by default (every released app), else the language's words, else English.
create temp table rows_de as select * from public.suggest_entries((select id from h), 'Mil');
create temp table rows_en as select * from public.suggest_entries((select id from h), 'mil', p_lang => 'en');
create temp table rows_hu as select * from public.suggest_entries((select id from h), 'mil', p_lang => 'hu');
select ok(
  exists (select from rows_de where source = 'catalog' and name = 'Milch'),
  'without p_lang the catalog rows are German, as before'
);
select ok(
  exists (select from rows_en where source = 'catalog' and name = 'Milk')
  and not exists (select from rows_en where source = 'catalog' and name in ('Milch', 'Milchreis', 'Schokolade')),
  'p_lang en offers English words and no German term'
);
select results_eq(
  'select source, name from rows_hu', 'select source, name from rows_en',
  'a language without words gets English, never German (ML1)'
);
select results_eq(
  $$select source, name from public.suggest_entries((select id from h), 'Mil', p_lang => 'de')$$,
  'select source, name from rows_de',
  'p_lang de is the default'
);
select ok(
  exists (
    select from public.suggest_entries((select id from h), 'organic peanut butt', p_lang => 'en')
    where source = 'catalog' and name = 'Organic peanut butter'),
  'an English row capitalises the name only'
);

-- put_item: the app's guess for a word the classifier does not know.
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470c01', p_household => (select id from h),
    p_list => null, p_name => 'Milch', p_category_guess => (select id from cat where seed_key = 'produce'))
$$, 'German word with a wrong guess');
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470c02', p_household => (select id from h),
    p_list => null, p_name => 'milk', p_category_guess => (select id from cat where seed_key = 'produce'))
$$, 'English word with a wrong guess');
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470c03', p_household => (select id from h),
    p_list => null, p_name => 'Zwurbelquix', p_category_guess => (select id from cat where seed_key = 'produce'))
$$, 'unknown word with a guess');
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470c04', p_household => (select id from h),
    p_list => null, p_name => 'Quorpelquox')
$$, 'unknown word without a guess');
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470c05', p_household => (select id from h),
    p_list => null, p_name => 'Flimsenquax', p_category_guess => (select id from other_cat where seed_key = 'produce'))
$$, 'unknown word with another household''s category');
select results_eq(
  $$select i.name, c.seed_key, i.categorized_via from public.items i join public.categories c on c.id = i.category_id
    where i.id::text like '00000000-0000-0000-0000-000000470c0%' order by i.id$$,
  $$values ('Milch', 'chilled', 'exact'), ('milk', 'chilled', 'synonym'), ('Zwurbelquix', 'produce', 'device'),
    ('Quorpelquox', 'other', 'fallback'), ('Flimsenquax', 'other', 'fallback')$$,
  'a known word gets its category, an unknown one the app''s guess (device), else Sonstiges'
);
select is(
  (select count(*) from public.category_memory m where m.household_id = (select id from h)),
  0::bigint, 'a guess kept is no correction: the household learns nothing'
);

-- Released apps' calls bind as before (the legacy put_item, no p_lang, no p_category_guess).
select lives_ok($$
  select public.put_item(p_id => '00000000-0000-0000-0000-000000470d01', p_household => (select id from h),
    p_name => 'Brot', p_quantity => null, p_brand => null, p_properties => null, p_category => null,
    p_store => null, p_sort_key => null, p_status => 'active', p_no_store => false)
$$, 'the first put_item call the app made still binds');
select is(
  (select c.seed_key from public.items i join public.categories c on c.id = i.category_id
   where i.id = '00000000-0000-0000-0000-000000470d01'),
  'bakery', 'and classifies as before'
);
select lives_ok(
  $$select * from public.suggest_entries(p_household => (select id from h), p_text => 'Mil', p_category_store => true)$$,
  'suggest_entries without p_lang binds'
);

reset role;
-- The oldest and the newest catalog an app build bundled (job 274, #748).
create temp table released as
select v, public.catalog_delta(v, v) as d from (values ('772a6413e45444e3'), ('93c44a00e91ad2aa')) x (v);
select is(
  (select array_agg((d ->> 'full')::boolean order by v) from released), array[false, false],
  'the versions released apps bundle get changes, not every row'
);
select is(
  (select count(*) from released, jsonb_array_elements(d -> 'terms' -> 'put') e
   where jsonb_array_length(e) <> 3 or e ->> 0 in (select word from public.catalog_words where lang = 'en'
     except select term from public.classifier_terms where lang = 'de')),
  0::bigint, 'their terms are rows of three, and none is an English word'
);
select ok(
  (select bool_and(exists (select from jsonb_array_elements(d -> 'words' -> 'put') e where e ->> 0 = 'en:milk'))
   from released),
  'and the English words come as words'
);

-- English phrases complete from their first words; after other words nothing else attaches.
select pg_temp.login('00000000-0000-0000-0000-000000470a01');
select results_eq(
  $$select x.t, coalesce(string_agg(s.name, ', ' order by s.n), '') from (values ('toilet p'), ('chicken br'), ('ice cr'), ('oat milk'), ('Milch')) x (t)
    left join lateral public.suggest_entries((select id from h), x.t, p_lang => 'en')
      with ordinality s (source, name, brand, properties, quantity, store_id, category_id, n) on s.source = 'catalog'
    group by x.t order by x.t$$,
  $$values ('chicken br', 'Chicken breast'), ('ice cr', 'Ice cream, Ice cream cake'), ('Milch', ''),
    ('oat milk', ''), ('toilet p', 'Toilet paper')$$,
  'toilet p offers Toilet paper, chicken br Chicken breast (not Chicken brie), Milch no Mulch'
);

-- A language besides German and English is data (Addendum 2): Hungarian rows, letters and all.
reset role;
insert into public.classifier_terms (term, category, lang) values ('őszibarack', 'produce', 'hu');
insert into public.catalog_words (lang, word, category) values ('hu', 'őszibarack', 'produce'), ('hu', 'tejföl', 'chilled');
insert into public.classifier_synonyms (variant, canonical) values ('tejföl', 'saure sahne');
select public.refresh_classifier_lexicon();
select pg_temp.login('00000000-0000-0000-0000-000000470a01');
select is(pg_temp.seed_of('Őszibarack'), 'produce', 'a Hungarian word is classified, its ő folded, not split');
select is(pg_temp.seed_of('2 tejföl'), 'chilled', 'a Hungarian word on a German concept takes its aisle');
select ok(
  exists (select from public.suggest_entries((select id from h), 'ősz', p_lang => 'hu')
          where source = 'catalog' and name = 'Őszibarack'),
  'p_lang hu offers its words once they exist'
);

select * from finish();
rollback;
