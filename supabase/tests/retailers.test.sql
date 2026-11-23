-- Job 313: which chains a store name matches (match_retailers), the answer to "Is this
-- <chain>?" (answer_store_retailer), the questions for older stores (retailer_questions), and who
-- reads the registry.
begin;
select plan(46);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.found(p_name text, p_country text) returns text language sql as $$
  select coalesce(string_agg(chain || '/' || country || case when exact then '' else '~' end, ' '), '')
  from public.match_retailers(p_name, p_country);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000313a01', 'rita313@example.com'),
  ('00000000-0000-0000-0000-000000313b01', 'otto313@example.com');
select pg_temp.login('00000000-0000-0000-0000-000000313b01');
create temp table other as select id from public.create_household(p_name => 'Otto', p_stores => array['Lidl']);
grant select on other to authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000313a01');
create temp table home as
  select id from public.create_household(p_name => 'Rita', p_stores => array['Lidl', 'Aldi', 'Wochenmarkt', 'REWE', 'Globus']);
grant select on home to authenticated;

create function pg_temp.store(p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = (select id from home) and name = p_name;
$$;

-- Matching, as a German phone asks.
select is(pg_temp.found('Lidl', 'DE'), 'lidl/DE', 'Lidl is the German Lidl only');
select is(pg_temp.found('IKEA', 'DE'), 'ikea/DE', 'IKEA matches the chain (job 408)');
select is(pg_temp.found('Ikea', 'DE'), 'ikea/DE', 'Ikea in any case matches it too');
select is(pg_temp.found('ikea Hofheim', 'BE'), 'ikea/BE', 'a store name after the chain still matches, in Belgium too');
select is(pg_temp.found('Hornbach', 'DE'), 'hornbach/DE', 'Hornbach matches the chain (job 410)');
select is(pg_temp.found('OBI Markt Köln', 'DE'), 'obi/DE', 'OBI and a place matches OBI');
select is(pg_temp.found('Toom', 'DE'), 'toom/DE', 'Toom matches through its alias');
select is(pg_temp.found('hagebau', 'DE'), 'hagebau/DE', 'hagebau matches hagebaumarkt through its alias');
select is(pg_temp.found('Globus Bau', 'DE'), 'globus-baumarkt/DE', 'Globus Bau is Globus Baumarkt');
select is(pg_temp.found('Globus', 'DE'), 'globus/DE globus-baumarkt/DE', 'plain Globus is the grocery and the DIY chain: the household picks');
select is(pg_temp.found('Globus Baumarkt Bous', 'DE'), 'globus-baumarkt/DE', 'an explicit Globus Baumarkt is the DIY chain alone');
select is(pg_temp.found('  lidl   am Markt ', 'DE'), 'lidl/DE', 'a chain name and a space, then anything, is that chain');
select is(pg_temp.found('Aldi', 'DE'), 'aldi-nord/DE aldi-sued/DE', 'Aldi is both German Aldis');
select is(pg_temp.found('aldi süd am bahnhof', 'DE'), 'aldi-sued/DE', 'the longest alias wins over plain "aldi"');
select is(pg_temp.found('Aldi Sud', 'DE'), 'aldi-sued/DE', 'umlauts fold: Süd and Sud match');
select is(pg_temp.found('ALDI SUED', 'DE'), 'aldi-sued/DE', 'and so does the ue spelling');
select is(pg_temp.found('Hofer', 'DE'), 'aldi-sued/AT', 'Hofer on a German phone is still Hofer in Austria');
select is(pg_temp.found('Aldi', 'AT'), 'aldi-sued/AT', 'Aldi on an Austrian phone is Hofer');
select is(pg_temp.found('re', 'DE'), 'rewe/DE~', 'two letters find chains starting with them, not as exact');
select is(pg_temp.found('r', 'DE'), '', 'one letter finds nothing');
select is(pg_temp.found('Wochenmarkt', 'DE'), '', 'a name no chain has finds nothing');
select is(pg_temp.found('Lidl-Markt', 'DE'), 'lidl/DE', 'punctuation separates words');
select is(pg_temp.found('E.Leclerc', 'DE'), 'leclerc/FR', 'a foreign chain is found by its name');
select is(pg_temp.found('zabka', 'DE'), 'zabka/PL', 'Ż folds to z');
select is(pg_temp.found('Coop', 'DE'), 'coop-ch/CH coop-it/IT', 'two countries'' Coops when the phone''s has none');
select is((select count(*)::int from public.match_retailers('Lidl', 'US')), 5, 'at most five rows');
select is(
  (select name || ' ' || (apps -> 0 ->> 'name') from public.match_retailers('dm', 'DE')),
  'dm Mein dm', 'a row carries the chain''s name and apps'
);

-- Questions for the household's stores, before any answer.
select is(
  (select string_agg(s.name || ':' || q.chain, ' ' order by s.name, q.chain)
   from public.retailer_questions((select id from home), 'DE') q join public.stores s on s.id = q.store_id),
  'Aldi:aldi-nord Aldi:aldi-sued Globus:globus Globus:globus-baumarkt Lidl:lidl REWE:rewe',
  'every unlinked, unanswered store with an exact chain is asked about, Globus about both of its chains; Wochenmarkt is not'
);

-- Answers.
select lives_ok(
  format($$ select public.answer_store_retailer(%L, 'aldi-sued', 'de') $$, pg_temp.store('Aldi')),
  'a member links a store to a chain'
);
select is(
  (select retailer_chain || '/' || retailer_country || ' ' || retailer_answered || ' ' || coalesce(retailer_app, '-')
   from public.stores where id = pg_temp.store('Aldi')),
  'aldi-sued/DE true -', 'the store keeps the chain, answered, with the default app'
);
select lives_ok(
  format($$ select public.answer_store_retailer(%L, 'lidl', 'DE', 'com.lidl.eci.lidlplus') $$, pg_temp.store('Lidl')),
  'a member picks one of the chain''s apps'
);
select is((select retailer_app from public.stores where id = pg_temp.store('Lidl')), 'com.lidl.eci.lidlplus',
  'the picked app is kept');
select throws_ok(
  format($$ select public.answer_store_retailer(%L, 'lidl', 'DE', 'de.rewe.app.mobile') $$, pg_temp.store('Lidl')),
  '22023', 'unknown_retailer_app', 'an app of another chain is refused'
);
select throws_ok(
  format($$ select public.answer_store_retailer(%L, 'lidl', 'US') $$, pg_temp.store('Lidl')),
  '22023', 'unknown_retailer', 'a chain the registry lacks is refused'
);
select lives_ok(
  format($$ select public.answer_store_retailer(%L, null, null) $$, pg_temp.store('REWE')),
  'a member says no'
);
select is(
  (select coalesce(retailer_chain, '-') || ' ' || retailer_answered from public.stores where id = pg_temp.store('REWE')),
  '- true', 'no leaves the store unlinked but answered'
);
select lives_ok(
  format($$ select public.answer_store_retailer(%L, 'globus-baumarkt', 'DE') $$, pg_temp.store('Globus')),
  'the household picks the DIY chain for a store named Globus (job 410)'
);
select is(
  (select retailer_chain || ' ' || retailer_answered || ' ' || (retailer_app is null) from public.stores where id = pg_temp.store('Globus')),
  'globus-baumarkt true true', 'the choice is stored on the store, with the chain''s default app'
);
select is((select count(*)::int from public.retailer_questions((select id from home), 'DE')), 0,
  'linked and answered stores are not asked about again');

-- Other households.
select is((select count(*)::int from public.retailer_questions((select id from other), 'DE')), 0,
  'an outsider gets no questions for another household''s stores');
select throws_ok(
  format($$ select public.answer_store_retailer(%L, 'lidl', 'DE') $$,
    (select id from public.stores where household_id = (select id from other) limit 1)),
  '42501', 'not_a_member', 'an outsider cannot answer for another household''s store'
);
reset role;
select is(
  (select retailer_answered from public.stores where household_id = (select id from other)),
  false, 'and that store is unchanged'
);

-- A chain that leaves the registry unlinks its stores.
delete from public.retailers where chain = 'aldi-sued' and country = 'DE';
select is((select retailer_chain from public.stores where id = pg_temp.store('Aldi')), null,
  'deleting a chain unlinks its stores');

-- Who reads and writes the registry.
select pg_temp.login('00000000-0000-0000-0000-000000313a01');
select ok((select count(*) from public.retailers) > 50, 'a signed-in user reads the registry');
select throws_ok($$ insert into public.retailers (chain, country, name, apps) values ('x', 'DE', 'X', '[]') $$,
  '42501', null, 'nobody signed in writes the registry');
set local role anon;
select throws_ok($$ select count(*) from public.retailers $$, '42501', null, 'signed out, the registry is not readable');

select * from finish();
rollback;
