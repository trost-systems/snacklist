// Job 470: the calls released apps make still bind and answer as before after the catalog's
// languages (20261126170000_catalog_languages.sql). Through PostgREST, as the app sends them, it
// replays every parameter set the app has sent since its first build (git history of
// app/lib/list/list_repository.dart and catalog_loader.dart): put_item with and without
// p_category_store, p_list and p_separate; suggest_entries with and without p_category_store;
// catalog_delta from the version the app bundled before this job. A new overload with the same
// names would fail here with PGRST203, which pgTAP cannot see. Then the new calls: p_lang 'en'
// offers English words, and p_category_guess keeps the app's category for a word the classifier
// does not know. A throwaway account; its rows are removed. The db gate sets FG_DB_TEST=1,
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_DB_URL; without them this is skipped.
import { assert, assertEquals } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
function env(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`${name} is not set`);
  return value;
}

/**
 * Every catalog version an app build has bundled (the history of catalog_index.g.dart on main,
 * job 274 to #748): no build is public yet (releases/releases.json), so the oldest in testers'
 * hands is the first.
 */
const bundledVersions = [
  '772a6413e45444e3',
  '042ff983ddcb1523',
  '5490f9136e87b539',
  'ff7955a4919596be',
  '18bc1465b6697bae',
  '68d2a0aeef557068',
  '93c44a00e91ad2aa',
];

type Row = Record<string, unknown>;

async function signUp(): Promise<{ id: string; token: string }> {
  const res = await fetch(`${env('SUPABASE_URL')}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: env('SUPABASE_ANON_KEY'), 'content-type': 'application/json' },
    body: JSON.stringify({
      email: `catalog-languages-${crypto.randomUUID()}@fg-test.invalid`,
      password: `${crypto.randomUUID()}-Aa1`,
    }),
  });
  const session = await res.json();
  assert(session.access_token, JSON.stringify(session));
  return { id: session.user.id, token: session.access_token };
}

async function rpc(token: string, fn: string, body: Row): Promise<unknown> {
  const res = await fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: env('SUPABASE_ANON_KEY'),
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const answer = await res.json();
  assertEquals(res.status, 200, `${fn} ${JSON.stringify(body)}: ${JSON.stringify(answer)}`);
  return answer;
}

function rows(answer: unknown): Row[] {
  assert(Array.isArray(answer), JSON.stringify(answer));
  return answer as Row[];
}

const suggestionKeys = [
  'brand',
  'category_id',
  'name',
  'properties',
  'quantity',
  'source',
  'store_id',
];

Deno.test({
  name: 'released apps calls bind and answer as before; p_lang and p_category_guess work',
  ignore: !enabled,
  async fn() {
    const sql = postgres(databaseUrl(), { max: 2, prepare: false });
    const user = await signUp();
    try {
      const created = await rpc(user.token, 'create_household', { p_name: 'Contract 470' });
      const row = Array.isArray(created) ? created[0] : created;
      assert(typeof row === 'object' && row !== null && 'id' in row, JSON.stringify(created));
      const householdId = String(row.id);
      const seeds = new Map(
        (await sql<{ id: string; seed_key: string | null }[]>`
          select id, seed_key from public.categories where household_id = ${householdId}`)
          .map((c) => [c.id, c.seed_key]),
      );
      const list = (await sql<{ id: string }[]>`
        select id from public.lists where household_id = ${householdId} limit 1`)[0]?.id;
      assert(list !== undefined, 'the household has a list');

      const base = (name: string): Row => ({
        p_id: crypto.randomUUID(),
        p_household: householdId,
        p_name: name,
        p_quantity: null,
        p_brand: null,
        p_properties: null,
        p_category: null,
        p_store: null,
        p_sort_key: null,
        p_status: 'active',
        p_no_store: false,
      });
      const shapes: [string, string, Row][] = [
        ['Milch', 'chilled', base('Milch')],
        ['Brot', 'bakery', { ...base('Brot'), p_list: list }],
        ['Käse', 'chilled', { ...base('Käse'), p_category_store: true, p_list: list }],
        ['Bananen', 'produce', {
          ...base('Bananen'),
          p_category_store: true,
          p_separate: true,
          p_list: list,
        }],
        ['Kaffee', 'pantry', { ...base('Kaffee'), p_category_store: true }],
      ];
      for (const [name, seed, body] of shapes) {
        const [item] = rows(await rpc(user.token, 'put_item', body));
        assert(item !== undefined, `put_item ${Object.keys(body).join(',')} answers its row`);
        assertEquals(item['name'], name);
        assertEquals(
          seeds.get(String(item['category_id'])),
          seed,
          `${name} is classified as before`,
        );
      }

      for (const body of [{ p_text: 'Tomat' }, { p_text: 'Tomat', p_category_store: true }]) {
        const answer = rows(
          await rpc(user.token, 'suggest_entries', { p_household: householdId, ...body }),
        );
        for (const row of answer) assertEquals(Object.keys(row).sort(), suggestionKeys);
        const catalog = answer.filter((r) => r['source'] === 'catalog').map((r) => r['name']);
        assert(
          catalog.includes('Tomatenmark') && !catalog.includes('Tomatoes'),
          `released apps get the German catalog: ${catalog}`,
        );
      }

      for (const version of bundledVersions) {
        const delta = await rpc(user.token, 'catalog_delta', {
          p_base: version,
          p_have: version,
        });
        assert(typeof delta === 'object' && delta !== null);
        const answer = delta as Row;
        assertEquals(
          answer['full'],
          false,
          `${version} has a snapshot: changes, not every row`,
        );
        const table = (key: string) => answer[key] as { put: unknown[][]; drop: unknown[] };
        // What a released app's parseCatalogDelta accepts: exact row lengths and types.
        for (const row of table('terms').put) {
          assert(row.length === 3 && row.every((f) => typeof f === 'string'), JSON.stringify(row));
        }
        for (const row of table('forms').put) {
          assert(row.length === 4 && typeof row[3] === 'boolean', JSON.stringify(row));
        }
        for (const row of table('brands').put) assert(row.length === 4, JSON.stringify(row));
        assert(
          table('terms').put.every((row) =>
            !['milk', 'eggplant', 'peanut butter'].includes(String(row[0]))
          ),
          'no English word reaches a released app as a German term',
        );
        assert(
          table('words').put.some((row) => row[0] === 'en:milk'),
          'the English words come as words',
        );
      }

      const english = rows(
        await rpc(user.token, 'suggest_entries', {
          p_household: householdId,
          p_text: 'mil',
          p_lang: 'en',
        }),
      );
      const englishCatalog = english.filter((r) => r['source'] === 'catalog').map((r) => r['name']);
      assert(englishCatalog.includes('Milk'), `p_lang en offers Milk: ${englishCatalog}`);
      assert(!englishCatalog.includes('Milch'), `and no German term: ${englishCatalog}`);
      const phrase = rows(
        await rpc(user.token, 'suggest_entries', {
          p_household: householdId,
          p_text: 'toilet p',
          p_lang: 'en',
        }),
      ).filter((r) => r['source'] === 'catalog').map((r) => r['name']);
      assertEquals(phrase, ['Toilet paper'], 'an English phrase completes from its first words');

      const produce = [...seeds].find(([, seed]) => seed === 'produce')?.[0];
      const [unknown] = rows(
        await rpc(user.token, 'put_item', {
          ...base('Zwurbelquix'),
          p_list: list,
          p_category_guess: produce,
        }),
      );
      assertEquals(
        seeds.get(String(unknown?.['category_id'])),
        'produce',
        'an unknown word keeps the guess',
      );
      assertEquals(unknown?.['categorized_via'], 'device');
    } finally {
      await sql`delete from auth.users where id = ${user.id}`;
      await sql.end();
    }
  },
});
