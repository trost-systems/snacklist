-- Job 349: seven words a short tail, a stem or a synonym sent to the wrong aisle (job 346, B1 to
-- B7). A short head such as gel or ent matches the end of any word, so a word it must not take is
-- listed with its real category; a stem shared with another word (Topf, Topfen) is a homograph.
begin;
select plan(53);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000349a1', 'tilda349@example.com');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000349a1", "role": "authenticated"}', true);
create temp table h as select id from public.create_household('Tilda');
select public.seed_hardware_categories((select id from h));

create function pg_temp.c(p_name text) returns text language sql as $$
  select c.seed_key from public.categories c
  where c.id = public.classify_item((select id from h), p_name);
$$;

select is(pg_temp.c('Spiegel'), 'household', 'B1: Spiegel ends in gel, not a gel');
select is(pg_temp.c('Handspiegel'), 'household', 'B1: and its compounds');
select is(pg_temp.c('Kleiderbügel'), 'household', 'B1: Kleiderbügel');
select is(pg_temp.c('Bratpfanne'), 'household', 'B2: Bratpfanne starts with braten, ends in pfanne');
select is(pg_temp.c('Grillpfanne'), 'household', 'B2: other pans');
select is(pg_temp.c('Topf'), 'household', 'B3: Topf is a pot, not Topfen');
select is(pg_temp.c('Töpfe'), 'household', 'B3: plural');
select is(pg_temp.c('Kochtopf'), 'household', 'B3: compounds');
select is(pg_temp.c('Topfen'), 'chilled', 'B3: Topfen stays quark');
select is(pg_temp.c('Magertopfen'), 'chilled', 'B3: Magertopfen stays quark');
select is(pg_temp.c('Medikament'), 'drugstore', 'B4: Medikament ends in ent, not Ente');
select is(pg_temp.c('Medikamente'), 'drugstore', 'B4: plural');
select is(pg_temp.c('tea lights'), 'household', 'B5: tea lights are candles, not tea');
select is(pg_temp.c('tealight'), 'household', 'B5: tealight');
select is(pg_temp.c('Teelichter'), 'household', 'B5: Teelichter stay household');
select is(pg_temp.c('Kühlpack'), 'household', 'B6: Kühlpack is a cool pack, like Kühlakku');
select is(pg_temp.c('Kühlakku'), 'household', 'B6: Kühlakku stays household');
select is(pg_temp.c('Kühlpad'), 'drugstore', 'B6: Kühlpad stays drugstore');
select is(pg_temp.c('Zeckenzange'), 'drugstore', 'B7: Zeckenzange is a pharmacy item, not a tool');
select is(pg_temp.c('Zange'), 'tools', 'B7: Zange stays tools');

-- What the guards must not break: the heads they sit beside.
select is(pg_temp.c('Duschgel'), 'drugstore', 'Duschgel stays drugstore');
select is(pg_temp.c('Haargel'), 'drugstore', 'Haargel stays drugstore');
select is(pg_temp.c('Ente'), 'meat', 'Ente stays meat');
select is(pg_temp.c('Entenbrust'), 'meat', 'Entenbrust stays meat');
select is(pg_temp.c('Bratwurst'), 'meat', 'Bratwurst stays meat');
select is(pg_temp.c('Braten'), 'meat', 'Braten stays meat');
select is(pg_temp.c('green tea'), 'pantry', 'green tea stays pantry');
select is(pg_temp.c('Tee'), 'pantry', 'Tee stays pantry');
select is(pg_temp.c('Spiegelei'), 'chilled', 'Spiegelei stays with the eggs, not a mirror');
select is(pg_temp.c('Topfpflanze'), 'garden', 'Topfpflanze stays garden');
select is(pg_temp.c('Kühlpacks'), 'household', 'B6: Kühlpacks');
select is(pg_temp.c('Spiegeleier'), 'chilled', 'Spiegeleier stay chilled');
select is(pg_temp.c('Element'), 'other', 'a word that only ends in ent is not an Ente');
select is(pg_temp.c('Pigment'), 'other', 'Pigment');
select is(pg_temp.c('Dokument'), 'other', 'Dokument');
select is(pg_temp.c('Instrument'), 'other', 'Instrument');
select is(pg_temp.c('Vogel'), 'other', 'a word that ends in a vowel and gel is not a gel: Vogel');
select is(pg_temp.c('Igel'), 'other', 'Igel');
select is(pg_temp.c('Kegel'), 'other', 'Kegel');
select is(pg_temp.c('Segel'), 'household', 'Segel is not a gel (it is one typo from Siegel)');
select is(pg_temp.c('Siegel'), 'household', 'Siegel is not a typo of Spiegel or a gel');
select is(pg_temp.c('Bräter'), 'household', 'Bräter is a roasting dish, not a Braten');
select is(pg_temp.c('Bügeleisen'), 'household', 'Bügeleisen is not Eis');
select is(pg_temp.c('Frischkäse'), 'chilled', 'Frischkäse still ends in käse');
select is(pg_temp.c('Frischkase'), 'chilled', 'also typed without the umlaut');
select is(pg_temp.c('Mülltüte'), 'household', 'Mülltüte still ends in tüte');
select is(pg_temp.c('Zuckerrübe'), 'produce', 'Zuckerrübe still ends in rübe');
select is(pg_temp.c('Blumenerde'), 'garden', 'Blumenerde still ends in erde');
select is(pg_temp.c('Pekingente'), 'meat', 'Pekingente still ends in ente');
select is(pg_temp.c('Entenbrust'), 'meat', 'Entenbrust');
select is(pg_temp.c('Massagegel'), 'drugstore', 'Massagegel is still a gel');
select is(pg_temp.c('Zangenschlüssel'), 'tools', 'Zange as a head of a tool word stays tools');
select is(pg_temp.c('Gemüsepfanne'), 'frozen', 'Gemüsepfanne stays frozen');

select * from finish();
rollback;
