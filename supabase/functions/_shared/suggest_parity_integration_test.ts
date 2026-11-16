// Job 274: public.suggest_entries answers every text of supabase/tests/suggest_parity.json with
// the rows written there, for the household there, and public.suggest_index answers that
// household's index there. Each row carries its category's seed key and its store's name, with
// p_category_store off and on; the index names stores and categories the same way, since their
// ids differ per run. Two more tables: texts typed after items the index has not seen yet
// (pending), and texts typed after a term the catalog gained since the app was built (delta, with
// catalog_delta's answer for the bundled version). The app's port of the ranking (app/test/list/suggest_parity_test.dart)
// passes the same file, so the device shows what the server would. Seeds the household from
// supabase/classifier/suggest_parity.ts in a transaction that is rolled back. After a deliberate
// change to the ranking, the parser, the catalog or the texts: SUGGEST_PARITY_WRITE=1 rewrites the
// file from this stack, and the Dart side has to follow. The db gate sets FG_DB_TEST=1.
import { assertEquals } from '@std/assert';
import postgres from 'postgres';
import { asUserWithin, databaseUrl, type Tx } from './db.ts';
import {
  deltaTerm,
  deltaTexts,
  history,
  type HistoryItem,
  pending,
  pendingTexts,
  storeLessons,
  stores,
  texts,
} from '../../classifier/suggest_parity.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
const write = Deno.env.get('SUGGEST_PARITY_WRITE') === '1';
const fixture = new URL('../../tests/suggest_parity.json', import.meta.url);

/** The time the file's ages count from, so its index reads the same every run. */
const fixtureNow = '2026-11-16T12:00:00.000Z';

/** source, name, brand, properties, quantity, category seed, store, store with p_category_store. */
type Row = [
  string,
  string,
  string | null,
  string | null,
  string | null,
  string | null,
  string | null,
  string | null,
];
type Case = [string, Row[]];
type IndexHistory = [string, string | null, string | null, string | null, string, string];
type Index = {
  history: IndexHistory[];
  brands: [string, string][];
  unserved: string[];
  known: string[];
  memory: [string, string | null, string][];
  cleared: string[];
  stores: [string, string][];
  categories: [string, string | null, string | null][];
};
type Parity = {
  now: string;
  categories: string[];
  history: [string, string | null, string | null, string | null, number, string | null][];
  index: Index;
  cases: Case[];
  pending: { items: IndexHistory[]; cases: Case[] };
  delta: { answer: unknown; cases: Case[] };
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

/** Runs [work] in a savepoint that is rolled back. */
async function andUndo<T>(tx: Tx, work: (tx: Tx) => Promise<T>): Promise<T> {
  let result: T | undefined;
  try {
    await tx.savepoint(async (sp) => {
      result = await work(sp);
      throw new Rollback();
    });
  } catch (e) {
    if (!(e instanceof Rollback)) throw e;
  }
  if (result === undefined) throw new Error('no result');
  return result;
}

/** Items bought [age] days ago: ages written past the triggers, which stamp the time of the write. */
async function insertItems(
  tx: Tx,
  userId: string,
  householdId: string,
  items: readonly HistoryItem[],
) {
  await asUserWithin(tx, userId, async (tx) => {
    for (const [name, brand, properties, quantity] of items) {
      await tx`
        insert into public.items (household_id, name, brand, properties, quantity, status)
        values (${householdId}, ${name}, ${brand}, ${properties}, ${quantity}, 'bought')`;
    }
  });
}

async function age(tx: Tx, householdId: string, items: readonly HistoryItem[]) {
  await tx`set local session_replication_role = replica`;
  for (const [name, brand, properties, , days] of items) {
    await tx`
      update public.items
      set updated_at = now() - make_interval(secs => ${days * 86400}),
          bought_at = now() - make_interval(secs => ${days * 86400})
      where household_id = ${householdId} and name = ${name}
        and brand is not distinct from ${brand} and properties is not distinct from ${properties}`;
  }
  await tx`set local session_replication_role = origin`;
}

async function seedAndAsk(tx: Tx, all: string[]): Promise<Parity> {
  const userId = crypto.randomUUID();
  await tx`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
  const householdId = await asUserWithin(tx, userId, async (tx) => {
    const [row] = await tx<{ id: string }[]>`
      select id from public.create_household(p_name => '274 parity')`;
    if (row === undefined) throw new Error('no household');
    for (const store of stores) await tx`select public.add_store(${row.id}, ${store})`;
    return row.id;
  });
  await insertItems(tx, userId, householdId, history);
  // The lessons as a member makes them, so the items triggers learn them.
  await asUserWithin(tx, userId, async (tx) => {
    for (const [name, lesson] of storeLessons) {
      if (lesson === 'tick') {
        await tx`update public.items set status = 'active' where household_id = ${householdId} and name = ${name}`;
        await tx`update public.items set status = 'bought' where household_id = ${householdId} and name = ${name}`;
      } else {
        await tx`
          update public.items
          set store_id = (select s.id from public.stores s where s.household_id = ${householdId} and s.name = ${lesson})
          where household_id = ${householdId} and name = ${name}`;
      }
    }
  });
  await age(tx, householdId, history);

  const [{ now } = { now: '' }] = await tx<{ now: string }[]>`
    select to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as now`;
  const shift = Date.parse(fixtureNow) - Date.parse(now);
  const shifted = (rows: IndexHistory[]): IndexHistory[] =>
    rows.map(([name, brand, properties, quantity, normalized, at]) => [
      name,
      brand,
      properties,
      quantity,
      normalized,
      new Date(Math.round((Date.parse(at) + shift) / 1000) * 1000).toISOString(),
    ]);
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
  const names = new Map<string, string>();
  for (
    const r of await tx<{ id: string; name: string }[]>`
    select id::text, seed_key as name from public.categories where household_id = ${householdId}
    union all
    select id::text, name from public.stores where household_id = ${householdId}`
  ) names.set(r.id, r.name);
  const named = (
    id: string | null,
  ): string | null => (id === null ? null : names.get(id) ?? `?${id}`);

  const index = await asUserWithin(tx, userId, async (tx) => {
    const [row] = await tx<
      { index: Index }[]
    >`select public.suggest_index(${householdId}) as index`;
    if (row === undefined) throw new Error('no index');
    return row.index;
  });
  // asUserWithin leaves the app's 8 s per statement; these ask for every text.
  await tx`set local statement_timeout = 0`;
  const ask = (texts: readonly string[]): Promise<Case[]> => answers(tx, householdId, texts, named);
  const cases = await ask(all);

  const pendingAnswer = await andUndo(tx, async (tx) => {
    await insertItems(tx, userId, householdId, pending);
    await age(tx, householdId, pending);
    const items = await tx<{ row: IndexHistory }[]>`
      select jsonb_build_array(i.name, i.brand, i.properties, i.quantity, i.normalized_name,
        coalesce(i.bought_at, i.updated_at)) as row
      from jsonb_array_elements(${
      JSON.stringify(pending)
    }::text::jsonb) with ordinality p (row, ord)
      join public.items i on i.household_id = ${householdId} and i.name = p.row ->> 0
        and i.brand is not distinct from p.row ->> 1 and i.properties is not distinct from p.row ->> 2
      order by p.ord`;
    return {
      items: shifted(items.map((i) => i.row)),
      cases: await answers(tx, householdId, pendingTexts, named),
    };
  });

  const deltaAnswer = await andUndo(tx, async (tx) => {
    const [{ base } = { base: '' }] = await tx<
      { base: string }[]
    >`select public.catalog_version() as base`;
    await tx`insert into public.classifier_terms (term, category) values (${deltaTerm[0]}, ${
      deltaTerm[1]
    })`;
    await tx`select public.refresh_classifier_lexicon()`;
    const answer = await asUserWithin(tx, userId, async (tx) => {
      const [row] = await tx<{ delta: unknown }[]>`select public.catalog_delta(${base}) as delta`;
      return row?.delta;
    });
    return { answer, cases: await answers(tx, householdId, deltaTexts, named) };
  });

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
      history: shifted(index.history),
      memory: index.memory.map(([key, canonical, store]) => [key, canonical, named(store) ?? '']),
      stores: index.stores.map(([seed, store]) => [seed, named(store) ?? '']),
      // suggest_index sorts them by id, which differs per run.
      categories: index.categories.map(([category, usual, seeded]): [
        string,
        string | null,
        string | null,
      ] => [named(category) ?? '', named(usual), named(seeded)])
        .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
    },
    cases,
    pending: pendingAnswer,
    delta: deltaAnswer,
  };
}

/** suggest_entries' rows for every text, with p_category_store off, and the stores with it on. */
async function answers(
  tx: Tx,
  householdId: string,
  texts: readonly string[],
  named: (id: string | null) => string | null,
): Promise<Case[]> {
  type Answer = {
    ord: string;
    source: string;
    name: string;
    brand: string | null;
    properties: string | null;
    quantity: string | null;
    category: string | null;
    store: string | null;
  };
  const ask = (categoryStore: boolean) =>
    tx<Answer[]>`
      select t.ord, s.source, s.name, s.brand, s.properties, s.quantity,
        s.category_id::text as category, s.store_id::text as store
      from jsonb_array_elements_text(${
      JSON.stringify(texts)
    }::text::jsonb) with ordinality t (text, ord)
      cross join lateral public.suggest_entries(${householdId}, t.text, 8, ${categoryStore})
        with ordinality s (source, name, brand, properties, quantity, store_id, category_id, n)
      order by t.ord, s.n`;
  const off = await ask(false);
  const on = await ask(true);
  assertEquals(
    on.map((r) => [r.ord, r.source, r.name, r.brand, r.properties]),
    off.map((r) => [r.ord, r.source, r.name, r.brand, r.properties]),
    'p_category_store changes only the stores',
  );
  const cases: Case[] = texts.map((text) => [text, []]);
  off.forEach((r, i) => {
    cases[Number(r.ord) - 1]?.[1].push([
      r.source,
      r.name,
      r.brand,
      r.properties,
      r.quantity,
      named(r.category),
      named(r.store),
      named(on[i]?.store ?? null),
    ]);
  });
  return cases;
}

/** The file: one history row, index row or case per line. */
function format(parity: Parity): string {
  const rows = (items: readonly unknown[]): string =>
    items.length === 0 ? '[]' : `[\n${items.map((i) => JSON.stringify(i)).join(',\n')}\n]`;
  const { history: indexHistory, memory, ...indexRest } = parity.index;
  return [
    '{',
    `"now": ${JSON.stringify(parity.now)},`,
    `"categories": ${JSON.stringify(parity.categories)},`,
    `"history": ${rows(parity.history)},`,
    `"index": {"history": ${rows(indexHistory)},`,
    `"memory": ${rows(memory)},`,
    ...Object.entries(indexRest).map(([k, v], i, a) =>
      `${JSON.stringify(k)}: ${JSON.stringify(v)}${i < a.length - 1 ? ',' : ''}`
    ),
    '},',
    `"pending": {"items": ${rows(parity.pending.items)},`,
    `"cases": ${rows(parity.pending.cases)}},`,
    `"delta": {"answer": ${JSON.stringify(parity.delta.answer)},`,
    `"cases": ${rows(parity.delta.cases)}},`,
    `"cases": ${rows(parity.cases)}`,
    '}',
    '',
  ].join('\n');
}

/** The cases of [actual] that differ from [expected]'s, by text. */
function differing(actual: Case[], expected: Case[]): Case[] {
  return actual.filter((c, i) => JSON.stringify(c) !== JSON.stringify(expected[i]));
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
    const changed = differing(answer.cases, expected.cases);
    assertEquals(changed.slice(0, 20), [], `${changed.length} texts answer differently`);
    assertEquals(answer.history, expected.history);
    assertEquals(answer.categories, expected.categories);
    assertEquals(answer.index, expected.index);
    assertEquals(answer.pending, expected.pending);
    assertEquals(answer.delta, expected.delta);
  },
});
