-- Job 274: catalog_delta answers a device the changes from the catalog version it bundles: none
-- when it is current, puts and drops from a known version, every row from an unknown one. Only
-- signed-in users may ask, and no client reads or writes the snapshots.
begin;
select plan(17);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000274a01', 'ada274@example.com');
create temp table v0 as select public.catalog_version() as version;
grant select on v0 to authenticated, anon;

select ok(exists (select from public.catalog_snapshots s where s.version = (select version from v0)),
  'the migration snapshots the current version');

select pg_temp.login('00000000-0000-0000-0000-000000274a01');
select is(public.catalog_delta((select version from v0)),
  jsonb_build_object('version', (select version from v0), 'full', false),
  'a current device gets its own version and no changes');
reset role;

insert into public.classifier_terms (term, category) values ('zwurbel', 'produce');
delete from public.classifier_terms where term = 'milch';
insert into public.brands (brand, product) values ('Zwurbelhof', 'Zwurbel');
delete from public.brands where key = 'tempo';

select pg_temp.login('00000000-0000-0000-0000-000000274a01');
create temp table changed as select public.catalog_delta((select version from v0)) as d;
reset role;

select isnt(d ->> 'version', (select version from v0), 'a change makes a new version') from changed;
select is(d ->> 'version', public.catalog_version(), 'the answer names the current one') from changed;
select is(d -> 'full', 'false'::jsonb, 'from a known version only the changes come') from changed;
select is(d -> 'terms' -> 'put',
  jsonb_build_array(jsonb_build_array('zwurbel', (select key from public.classifier_terms where term = 'zwurbel'), 'produce')),
  'the new term is put') from changed;
select is(d -> 'terms' -> 'drop', '["milch"]'::jsonb, 'the deleted term is dropped') from changed;
select is(d -> 'brands' -> 'put',
  jsonb_build_array(jsonb_build_array(public.brand_key('Zwurbelhof'), 'Zwurbelhof', 'Zwurbel', null)),
  'the new brand is put') from changed;
select is(d -> 'brands' -> 'drop', '["tempo"]'::jsonb, 'the deleted brand is dropped') from changed;
select is(d -> 'forms', '{"put": [], "drop": []}'::jsonb, 'an unchanged table has no changes') from changed;
select ok(exists (select from public.catalog_snapshots s where s.version = public.catalog_version()),
  'the call snapshots the new version');

select pg_temp.login('00000000-0000-0000-0000-000000274a01');
create temp table unknown as select public.catalog_delta('0123456789abcdef') as d;
reset role;
select is(d -> 'full', 'true'::jsonb, 'an unknown version gets the full catalog') from unknown;
select is(
  (select array[jsonb_array_length(d -> 'terms' -> 'put'), jsonb_array_length(d -> 'forms' -> 'put'),
     jsonb_array_length(d -> 'brands' -> 'put')] from unknown),
  array[(select count(*)::int from public.classifier_terms), (select count(*)::int from public.classifier_lexicon),
    (select count(*)::int from public.brands)],
  'every row of each table');
select is(public.catalog_rows() -> 'terms', d -> 'terms' -> 'put', 'as catalog_rows lists them') from unknown;

set local role anon;
select throws_ok($$select public.catalog_delta('0123456789abcdef')$$, '42501', null, 'signed out, no catalog');
reset role;

select pg_temp.login('00000000-0000-0000-0000-000000274a01');
select throws_ok('select * from public.catalog_snapshots', '42501', null, 'a client cannot read the snapshots');
select throws_ok($$insert into public.catalog_snapshots (version, terms, forms, brands)
  values ('0123456789abcdef', '[]', '[]', '[]')$$, '42501', null, 'nor write one');
reset role;

select * from finish();
rollback;
