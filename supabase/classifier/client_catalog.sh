#!/usr/bin/env bash
# Job 274: writes app/lib/list/catalog/catalog_index.g.dart, the catalog the app bundles for its
# on-device suggestions and category guess: public.catalog_rows() (classifier_terms,
# classifier_lexicon, brands, and since job 473 the lexicon's homographs) with
# public.catalog_version(), and the parser's fixed vocabulary (item_units, item_number_words,
# item_number_names, item_descriptors, hardware_categories). It replaces job 61's
# client_lexicon.sh. The lines come out as dart format writes them. With --check (the db gate) it
# fails when the file is not what this stack's migrations give.
# CLASSIFIER_PSQL="psql -h ... -d ..." runs it against another database (default: the local stack).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="$here/../../app/lib/list/catalog/catalog_index.g.dart"
project_id="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$here/../config.toml")"
db() {
  if [[ -n ${CLASSIFIER_PSQL:-} ]]; then $CLASSIFIER_PSQL "$@"; else docker exec -i "supabase_db_$project_id" psql -U postgres "$@"; fi
}
generated="$(db -v ON_ERROR_STOP=1 -At -q <<'SQL'
-- A Dart string literal (or null).
create function pg_temp.lit(t text) returns text language sql immutable as $$
  select case when t is null then 'null'
    else '''' || replace(replace(replace(t, '\', '\\'), '''', '\'''), '$', '\$') || '''' end
$$;
-- One list element: on one line when it fits in 80 columns, else one field per line.
create function pg_temp.rec(f text[]) returns text language sql immutable as $$
  select case when char_length('  (' || array_to_string(f, ', ') || '),') <= 80
    then '  (' || array_to_string(f, ', ') || '),'
    else E'  (\n' || (select string_agg('    ' || x || ',', E'\n' order by o) from unnest(f) with ordinality u (x, o)) || E'\n  ),'
  end
$$;
with rows as (select public.catalog_rows() as r),
lines (part, ord, line) as (
  select 0, 0, '/// public.catalog_version() of [catalogTerms], [catalogForms], [catalogBrands]'
  union all select 0, 1, '/// and [catalogHomographs].'
  union all select 0, 2, 'const catalogVersion = ' || pg_temp.lit(public.catalog_version()) || ';'
  union all select 1, 0, E'\n/// public.classifier_terms: (term, key, category seed key).'
  union all select 1, 1, 'const catalogTerms = <(String, String, String)>['
  union all select 1, 2 + o::integer, pg_temp.rec(array[pg_temp.lit(e ->> 0), pg_temp.lit(e ->> 1), pg_temp.lit(e ->> 2)])
    from rows, jsonb_array_elements(r -> 'terms') with ordinality j (e, o)
  union all select 1, 1000000, '];'
  union all select 2, 0, E'\n/// public.classifier_lexicon, the forms public.classifier_words matches, as'
  union all select 2, 1, '/// public.item_key and public.fold_key write them: (form, canonical, category'
  union all select 2, 2, '/// seed key, synonym).'
  union all select 2, 3, 'const catalogForms = <(String, String, String, bool)>['
  union all select 2, 4 + o::integer, pg_temp.rec(array[pg_temp.lit(e ->> 0), pg_temp.lit(e ->> 1), pg_temp.lit(e ->> 2), e ->> 3])
    from rows, jsonb_array_elements(r -> 'forms') with ordinality j (e, o)
  union all select 2, 1000000, '];'
  union all select 3, 0, E'\n/// public.brands: (key, brand, product, store seed key).'
  union all select 3, 1, 'const catalogBrands = <(String, String, String?, String?)>['
  union all select 3, 2 + o::integer, pg_temp.rec(array[pg_temp.lit(e ->> 0), pg_temp.lit(e ->> 1), pg_temp.lit(e ->> 2), pg_temp.lit(e ->> 3)])
    from rows, jsonb_array_elements(r -> 'brands') with ordinality j (e, o)
  union all select 3, 1000000, '];'
  union all select 4, 0, E'\n/// public.classifier_lexicon.homographs, a row per spelling of a form words of'
  union all select 4, 1, '/// different categories share: (form, spelling as public.surface_word writes'
  union all select 4, 2, '/// it, canonical, category seed key, synonym).'
  union all select 4, 3, 'const catalogHomographs = <(String, String, String, String, bool)>['
  union all select 4, 4 + o::integer, pg_temp.rec(array[pg_temp.lit(e ->> 0), pg_temp.lit(e ->> 1), pg_temp.lit(e ->> 2), pg_temp.lit(e ->> 3), e ->> 4])
    from rows, jsonb_array_elements(r -> 'homographs') with ordinality j (e, o)
  union all select 4, 1000000, '];'
  union all select 5, 0, E'\n/// public.item_units(), in its order: the units an amount can have.'
  union all select 5, 1, 'const units = ['
  union all select 5, 2 + o::integer, '  ' || pg_temp.lit(u) || ','
    from unnest(string_to_array(public.item_units(), '|')) with ordinality x (u, o)
  union all select 5, 1000000, '];'
  union all select 6, 0, E'\n/// public.item_number_words(): count words a typed line reads as a Menge,'
  union all select 6, 1, '/// German and English.'
  union all select 6, 2, 'const numberWords = <String, int>{'
  union all select 6, 3 + (row_number() over (order by w.value::integer, w.key collate "C"))::integer,
      '  ' || pg_temp.lit(w.key) || ': ' || w.value || ','
    from jsonb_each_text(public.item_number_words()) w
  union all select 6, 1000000, '};'
  union all select 7, 0, E'\n/// public.item_number_names(): names that start with a number word and'
  union all select 7, 1, '/// keep it ("Drei Glocken Spaghetti").'
  union all select 7, 2, 'const numberNames = ['
  union all select 7, 3 + o::integer, '  ' || pg_temp.lit(n) || ','
    from unnest(public.item_number_names()) with ordinality x (n, o)
  union all select 7, 1000000, '];'
  union all select 8, 0, E'\n/// public.item_descriptors(), in its order: (alias, label, words).'
  union all select 8, 1, 'const descriptors = <(String, String, int)>['
  union all select 8, 2 + o::integer, pg_temp.rec(array[pg_temp.lit(d.alias), pg_temp.lit(d.label), d.words::text])
    from public.item_descriptors() with ordinality d (alias, label, words, o)
  union all select 8, 1000000, '];'
  union all select 9, 0, E'\n/// public.hardware_categories(), in the Baumarkt''s walk: their seed keys.'
  union all select 9, 1, 'const hardwareSeedKeys = ['
  union all select 9, 2 + h.walk, '  ' || pg_temp.lit(h.seed_key) || ','
    from public.hardware_categories() h
  union all select 9, 1000000, '];'
)
select line from lines order by part, ord;
SQL
)"
generated="$(
  echo '// Generated by supabase/classifier/client_catalog.sh from the local stack.'
  echo '// Do not edit; rerun the script after a classifier or item parser migration.'
  echo
  printf '%s\n' "$generated"
)"
rel=app/lib/list/catalog/catalog_index.g.dart
if [[ ${1:-} == --check ]]; then
  if ! diff -u "$target" - <<<"$generated" >/dev/null; then
    echo "$rel is out of date: run supabase/classifier/client_catalog.sh" >&2
    exit 1
  fi
  echo "$rel matches this stack (catalog $(sed -n "s/^const catalogVersion = '\(.*\)';$/\1/p" "$target"))"
else
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$generated" >"$target"
  echo "wrote $rel"
fi
