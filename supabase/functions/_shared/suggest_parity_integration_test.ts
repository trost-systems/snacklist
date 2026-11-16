// Job 274: public.suggest_entries answers every text of supabase/tests/suggest_parity.json with
// the rows written there, for the household there, and public.suggest_index answers that
// household's index there. The app's port of the ranking (app/test/list/suggest_parity_test.dart)
// passes the same file, so the device shows what the server would. Seeds the household from
// supabase/classifier/suggest_parity.ts in a transaction that is rolled back. After a deliberate
// change to the ranking, the parser, the catalog or the texts: SUGGEST_PARITY_WRITE=1 rewrites the
// file from this stack, and the Dart side has to follow. The db gate sets FG_DB_TEST=1.
import { assertEquals } from '@std/assert';
import postgres from 'postgres';
import { asUserWithin, databaseUrl, type Tx } from './db.ts';
import { history, texts } from '../../classifier/suggest_parity.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const write = Deno.env.get('SUGGEST_PARITY_WRITE') === '1';
const fixture = new URL('../../tests/suggest_parity.json', import.meta.url);

/** The time the file's ages count from, so its index reads the same every run. */
const fixtureNow = '2026-11-16T12:00:00.000Z';

type Row = [string, string, string | null, string | null, string | null, string | null];
type Case = [string, Row[]];
type Index = {
  history: [string, string | null, string | null, string | null, string, string][];
  brands: [string, string][];
  unserved: string[];
  known: string[];
};
type Parity = {
  now: string;
  categories: string[];
  history: [string, string | null, string | null, string | null, number, string | null][];
  index: Index;
  cases: Case[];
};

class Rollback extends Error {}

/** What this stack answers for the fixture household and every text. */
async function serverAnswer(all: string[]): Promise<Parity> {
  const sql = postgres(databaseUrl(), { max: 1, prepare: false });
  let answer: Parity | undefined;
  try {
    await sql.begin(async (tx) => {
      answer = await seedAndAsk(tx, all);
      throw new Rollback();
    });
  } catch (e) {
    if (!(e instanceof Rollback)) throw e;
  } finally {
    await sql.end();
  }
  if (answer === undefined) throw new Error('no answer');
  return answer;
}

async function seedAndAsk(tx: Tx, all: string[]): Promise<Parity> {
  const userId = crypto.randomUUID();
  await tx`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
  const householdId = await asUserWithin(tx, userId, async (tx) => {
    const [row] = await tx<{ id: string }[]>`
      select id from public.create_household(p_name => '274 parity')`;
    if (row === undefined) throw new Error('no household');
    for (const [name, brand, properties, quantity] of history) {
      await tx`
        insert into public.items (household_id, name, brand, properties, quantity, status)
        values (${row.id}, ${name}, ${brand}, ${properties}, ${quantity}, 'bought')`;
    }
    return row.id;
  });
  // The ages: written past the triggers, which stamp updated_at with the time of the write.
  await tx`set local session_replication_role = replica`;
  for (const [name, brand, properties, , age] of history) {
    await tx`
      update public.items
      set updated_at = now() - make_interval(secs => ${age * 86400}),
          bought_at = now() - make_interval(secs => ${age * 86400})
      where household_id = ${householdId} and name = ${name}
        and brand is not distinct from ${brand} and properties is not distinct from ${properties}`;
  }
  await tx`set local session_replication_role = origin`;

  const [{ now } = { now: '' }] = await tx<{ now: string }[]>`
    select to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as now`;
  const shift = Date.parse(fixtureNow) - Date.parse(now);
  const categories = await tx<{ seed_key: string }[]>`
    select seed_key from public.categories
    where household_id = ${householdId} and seed_key is not null order by seed_key collate "C"`;
  const seeds = await tx<{ seed_key: string | null }[]>`
    select k.seed_key from jsonb_array_elements(${
    JSON.stringify(history)
  }::text::jsonb) with ordinality h (row, ord)
    left join public.items i on i.household_id = ${householdId} and i.name = h.row ->> 0
      and i.brand is not distinct from h.row ->> 1 and i.properties is not distinct from h.row ->> 2
    left join public.categories k on k.id = i.category_id
    order by h.ord`;
  const index = await asUserWithin(tx, userId, async (tx) => {
    const [row] = await tx<
      { index: Index }[]
    >`select public.suggest_index(${householdId}) as index`;
    if (row === undefined) throw new Error('no index');
    return row.index;
  });
  // asUserWithin leaves the app's 8 s per statement; this one asks for every text.
  await tx`set local statement_timeout = 0`;
  const rows = await tx<
    {
      ord: string;
      source: string;
      name: string;
      brand: string | null;
      properties: string | null;
      quantity: string | null;
      seed_key: string | null;
    }[]
  >`
    select t.ord, s.source, s.name, s.brand, s.properties, s.quantity, k.seed_key
    from jsonb_array_elements_text(${
    JSON.stringify(all)
  }::text::jsonb) with ordinality t (text, ord)
    cross join lateral public.suggest_entries(${householdId}, t.text)
      with ordinality s (source, name, brand, properties, quantity, store_id, category_id, n)
    left join public.categories k on k.id = s.category_id
    order by t.ord, s.n`;
  const cases: Case[] = all.map((text) => [text, []]);
  for (const r of rows) {
    cases[Number(r.ord) - 1]?.[1].push([
      r.source,
      r.name,
      r.brand,
      r.properties,
      r.quantity,
      r.seed_key,
    ]);
  }
  return {
    now: fixtureNow,
    categories: categories.map((c) => c.seed_key),
    history: history.map(([name, brand, properties, quantity, age], i) => [
      name,
      brand,
      properties,
      quantity,
      age,
      seeds[i]?.seed_key ?? null,
    ]),
    index: {
      ...index,
      history: index.history.map(([name, brand, properties, quantity, normalized, at]) => [
        name,
        brand,
        properties,
        quantity,
        normalized,
        new Date(Math.round((Date.parse(at) + shift) / 1000) * 1000).toISOString(),
      ]),
    },
    cases,
  };
}

/** The file: one history row, index row or case per line. */
function format(parity: Parity): string {
  const rows = (items: readonly unknown[]): string =>
    items.length === 0 ? '[]' : `[\n${items.map((i) => JSON.stringify(i)).join(',\n')}\n]`;
  const { history: indexHistory, ...indexRest } = parity.index;
  return [
    '{',
    `"now": ${JSON.stringify(parity.now)},`,
    `"categories": ${JSON.stringify(parity.categories)},`,
    `"history": ${rows(parity.history)},`,
    `"index": {"history": ${rows(indexHistory)},`,
    ...Object.entries(indexRest).map(([k, v], i, a) =>
      `${JSON.stringify(k)}: ${JSON.stringify(v)}${i < a.length - 1 ? ',' : ''}`
    ),
    '},',
    `"cases": ${rows(parity.cases)}`,
    '}',
    '',
  ].join('\n');
}

Deno.test({
  name: 'suggest_entries answers every text of suggest_parity.json with its rows',
  ignore: !enabled,
  sanitizeResources: false,
  fn: async () => {
    const all = await texts();
    const answer = await serverAnswer(all);
    if (write) {
      await Deno.writeTextFile(fixture, format(answer));
      return;
    }
    const expected = JSON.parse(await Deno.readTextFile(fixture)) as Parity;
    assertEquals(
      expected.cases.map(([text]) => text),
      all,
      'the texts changed: rewrite the file with SUGGEST_PARITY_WRITE=1',
    );
    const differing = answer.cases.filter((c, i) =>
      JSON.stringify(c) !== JSON.stringify(expected.cases[i])
    );
    assertEquals(differing.slice(0, 20), [], `${differing.length} texts answer differently`);
    assertEquals(answer.history, expected.history);
    assertEquals(answer.categories, expected.categories);
    assertEquals(answer.index, expected.index);
  },
});
