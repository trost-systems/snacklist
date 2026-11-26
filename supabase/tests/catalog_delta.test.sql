-- Job 274: catalog_delta answers a device the changes from the catalog version it bundles: none
-- when it is current, puts and drops from a known version, every row from an unknown one. Only
-- signed-in users may ask, only with versions, and no client reads or writes the snapshots. A
-- catalog change snapshots the version it replaces, once per transaction (review 0). Job 473: an
-- answer with tables also carries every homograph row, which apps before it ignore.
begin;
select plan(38);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000274a01', 'ada274@example.com');
create temp table v0 as select public.catalog_version() as version;
grant select on v0 to authenticated, anon;

-- A catalog migration after job 274's leaves its new version without a snapshot until the first
-- catalog_delta call or the next catalog change takes one (both below); no other version is marked.
select ok(not exists (select from public.catalog_snapshots s where s.current and s.version <> (select version from v0)),
  'no snapshot but the current version''s is marked current');

select pg_temp.login('00000000-0000-0000-0000-000000274a01');
select is(public.catalog_delta((select version from v0)),
  jsonb_build_object('version', (select version from v0), 'full', false),
  'a current device gets its own version and no changes');
select throws_ok($$select public.catalog_delta('0123456789ABCDEF')$$, '22023', 'invalid_version',
  'a base that is no version is refused');
select throws_ok($$select public.catalog_delta(null)$$, '22023', 'invalid_version', 'and none');
select throws_ok($$select public.catalog_delta(repeat('a', 10000))$$, '22023', 'invalid_version',
  'and a long one');
select throws_ok($$select public.catalog_delta('0123456789abcdef', 'x')$$, '22023', 'invalid_version',
  'and a p_have that is no version');
reset role;
select is((select array_agg(s.version) from public.catalog_snapshots s where s.current), array[(select version from v0)],
  'the answer marks the current version, so the next call reads its snapshot');

-- As if no device had asked while v0 was live: no snapshot of it.
delete from public.catalog_snapshots s where s.version = (select version from v0);
create temp table before_change as select count(*) as n from public.catalog_snapshots;

insert into public.classifier_terms (term, category) values ('zwurbel', 'produce');
delete from public.classifier_terms where term = 'milch';
insert into public.brands (brand, product) values ('Zwurbelhof', 'Zwurbel');
delete from public.brands where key = 'tempo';

select ok(exists (select from public.catalog_snapshots s where s.version = (select version from v0)),
  'the first change snapshots the version it replaces');
select is((select count(*) from public.catalog_snapshots), (select n + 1 from before_change),
  'one snapshot for four statements: none of the versions in between');

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
select ok(public.catalog_rows() -> 'homographs' @> '[["schaufel", "schäufele", "schaufele", "meat", false]]',
  'the catalog carries the lexicon''s homographs, a row per spelling');
select is(d -> 'homographs', public.catalog_rows() -> 'homographs', 'an answer with changes has every homograph row')
from changed;
select ok(d ?& array['version', 'full', 'terms', 'forms', 'brands'], 'and still every key an older app reads')
from changed;

-- A snapshot taken before job 473 has no homographs; it still answers with changes.
update public.catalog_snapshots s set homographs = null where s.version = (select version from v0);
select pg_temp.login('00000000-0000-0000-0000-000000274a01');
create temp table old_base as select public.catalog_delta((select version from v0)) as d;
reset role;
select is(d -> 'terms' -> 'drop', '["milch"]'::jsonb, 'a base snapshot without homographs still gets changes')
from old_base;
select is(d -> 'homographs', public.catalog_rows() -> 'homographs', 'and every homograph row') from old_base;

insert into public.classifier_terms (term, category) values ('zwurbelbrot', 'bakery');
select ok(not exists (select from public.catalog_snapshots s where s.current),
  'a later change in the same transaction unmarks the current version');
select pg_temp.login('00000000-0000-0000-0000-000000274a01');
select is(public.catalog_delta((select version from v0)) -> 'terms' -> 'put' -> 1 ->> 0, 'zwurbelbrot',
  'and the next call answers the catalog as it is now');
reset role;
delete from public.classifier_terms where term = 'zwurbelbrot';

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
select is(d -> 'homographs', public.catalog_rows() -> 'homographs', 'the full catalog has the homographs too')
from unknown;

create temp table v1 as select public.catalog_version() as version;
grant select on v1 to authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000274a01');
select is(public.catalog_delta('0123456789abcdef', (select version from v1)),
  jsonb_build_object('version', (select version from v1), 'full', false),
  'a device that has the current version applied gets no rows, also from an unknown base');
select is(public.catalog_delta('0123456789abcdef', (select version from v0)) -> 'full', 'true'::jsonb,
  'one that has an older version applied gets the rows');
select is(public.catalog_delta((select version from v0), null) -> 'terms' -> 'drop', '["milch"]'::jsonb,
  'without p_have the changes come as before');
reset role;

-- The version covers the homographs: a change to them alone reaches the devices.
create temp table v2 as select public.catalog_version() as version;
grant select on v2 to authenticated;
update public.classifier_lexicon set homographs = null where form = 'topf';
select isnt(public.catalog_version(), (select version from v2), 'a homograph change alone makes a new version');
select pg_temp.login('00000000-0000-0000-0000-000000274a01');
create temp table h2 as select public.catalog_delta((select version from v2)) as d;
reset role;
select is(d -> 'forms', '{"put": [], "drop": []}'::jsonb, 'with no row changes') from h2;
select ok(d -> 'homographs' @> '[["schaufel"]]' and not d -> 'homographs' @> '[["topf"]]',
  'and the homographs as they are now') from h2;

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
