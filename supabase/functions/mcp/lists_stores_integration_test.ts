// Job 345: list_recent, suggest_items, list_categories with a store, and the list and store tools
// behind app_switches.mcp_lists_stores (create_list, rename_list, add_store, rename_store,
// set_store_layout), through the SDK's streamable HTTP handler as a client sees it, against the
// local stack (FG_DB_TEST=1 and SUPABASE_DB_URL, like item_ops_integration_test.ts). They go
// through the app's own database functions, so the answers are the app's.
import { assert, assertEquals, assertExists, assertStringIncludes } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import postgres from 'postgres';
import type { Auth } from '../_shared/auth.ts';
import { asUser, databaseUrl } from '../_shared/db.ts';
import type { Access } from '../_shared/premium.ts';
import { productionDeps } from './handler.ts';
import { buildServer, SWITCHED_OFF, type Switches } from './tools.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

const ON: Switches = { listsStores: true };

type Item = { id: string; name: string; listId: string; tickedAt?: string };
type Result = { isError?: boolean; content: { text: string }[] };

async function call(
  auth: Auth,
  name: string,
  args: Record<string, unknown>,
  switches: Switches = ON,
): Promise<{ result?: Result; error?: { message: string } }> {
  const res = await createMcpHandler(() =>
    buildServer(
      auth,
      () => Promise.resolve<Access>('open'),
      () => Promise.resolve(),
      'de',
      switches,
    )
  ).fetch(
    new Request('http://edge/mcp', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        'mcp-protocol-version': '2025-11-25',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name, arguments: args },
      }),
    }),
  );
  assertEquals(res.status, 200);
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  return JSON.parse(data ? data.slice(6) : text);
}

/** The answer of a call that must succeed. */
async function ok<T>(auth: Auth, name: string, args: Record<string, unknown>): Promise<T> {
  const { result } = await call(auth, name, args);
  assertExists(result, name);
  assertEquals(result.isError, undefined, `${name}: ${result.content[0]?.text}`);
  return JSON.parse(result.content[0]?.text ?? 'null') as T;
}

/** The text of a call that must fail as a tool error. */
async function refused(auth: Auth, name: string, args: Record<string, unknown>): Promise<string> {
  const { result } = await call(auth, name, args);
  assertEquals(result?.isError, true, `${name} ${JSON.stringify(args)} must fail`);
  return result?.content[0]?.text ?? '';
}

type Member = { auth: Auth; householdId: string };

/** Two users, each with a fresh household with dm, Lidl and Edeka, removed afterwards. */
async function withTwo(
  work: (sql: postgres.Sql, mine: Member, theirs: Member) => Promise<void>,
) {
  const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
  const users = [crypto.randomUUID(), crypto.randomUUID()];
  const log = console.log;
  console.log = () => {};
  try {
    const members = [];
    for (const userId of users) {
      await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
      const householdId = await asUser(userId, async (tx) => {
        const [row] = await tx<{ id: string }[]>`
          select id from public.create_household(p_name => '345', p_default_stores => true)`;
        assertExists(row);
        return row.id;
      });
      members.push({
        auth: { userId, householdId, via: 'pat', scopes: ['read', 'write'] as const } as Auth,
        householdId,
      });
    }
    const [mine, theirs] = members;
    assertExists(mine);
    assertExists(theirs);
    await work(sql, mine, theirs);
  } finally {
    console.log = log;
    for (const userId of users) {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${userId})`;
      await sql`delete from auth.users where id = ${userId}`;
    }
    await sql.end();
  }
}

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('list_recent shows the ticked things once, newest first; suggest_items the usuals', () =>
  withTwo(async (_sql, { auth }, theirs) => {
    const { added } = await ok<{ added: Item[] }>(auth, 'add_items', {
      items: [{ name: 'Milch' }, { name: 'Brot' }, { name: 'Brötchen' }],
    });
    await ok(auth, 'tick_items', { items: ['Milch'] });
    await ok(auth, 'tick_items', { items: ['Brot'] });
    await ok(auth, 'tick_items', { items: ['Brötchen'] });
    await ok(auth, 'add_items', { items: [{ name: 'Brötchen' }] });

    const recent = await ok<{ list: string; items: Item[] }>(auth, 'list_recent', {});
    assertEquals(recent.list, 'Einkaufsliste');
    assertEquals(recent.items.map((i) => i.name), ['Brot', 'Milch'], 'Brötchen is open again');
    assert(recent.items.every((i) => typeof i.tickedAt === 'string'));
    assertEquals(
      recent.items.map((i) => i.id).sort(),
      added.filter((i) => i.name !== 'Brötchen').map((i) => i.id).sort(),
      'the ticked rows, by id, for untick_items',
    );
    assertEquals((await ok<{ items: Item[] }>(auth, 'list_recent', { limit: 1 })).items.length, 1);
    assertEquals((await ok<{ items: Item[] }>(theirs.auth, 'list_recent', {})).items, []);

    const usuals = await ok<{ name: string; due: boolean; uses: number }[]>(
      auth,
      'suggest_items',
      { prefix: 'br' },
    );
    assertEquals(usuals.map((u) => u.name), ['Brot'], 'Brötchen is open, Milch has no br');
    assertEquals((await ok<unknown[]>(theirs.auth, 'suggest_items', {})).length, 0);
  }));

test("suggest_items due: true is the app's due set, not the due ones among the first limit", () =>
  withTwo(async (sql, { auth, householdId }) => {
    const daily = Array.from({ length: 12 }, (_, i) => `Tagesding${i}`);
    const due = ['Käse', 'Milch', 'Joghurt'];
    const { added } = await ok<{ added: Item[] }>(auth, 'add_items', {
      items: [...daily, ...due].map((name) => ({ name })),
    });
    // Twelve daily usuals outrank three due ones (gap 10 days, last bought 10 days ago).
    for (const item of added) {
      const days = daily.includes(item.name) ? [0, 1, 2, 3, 4] : [20, 10];
      await sql`update public.items set status = 'bought', bought_at = now() where id = ${item.id}`;
      await sql`delete from public.item_events where item_id = ${item.id} and action = 'bought'`;
      for (const d of days) {
        await sql`insert into public.item_events (household_id, item_id, action, item_name, created_at)
          values (${householdId}, ${item.id}, 'bought', ${item.name},
                  now() - ${d} * interval '1 day' - interval '1 minute')`;
      }
    }
    const usuals = (args: Record<string, unknown>) =>
      ok<{ name: string; due: boolean }[]>(auth, 'suggest_items', args);
    const top = await usuals({});
    assert(!due.every((n) => top.some((u) => u.name === n && u.due)), 'the first 10 miss some');
    const dueOnly = await usuals({ due: true });
    assertEquals(dueOnly.map((u) => u.name).sort(), [...due].sort());
    assert(dueOnly.every((u) => u.due));
    assertEquals((await usuals({ due: true, limit: 2 })).length, 2);
  }));

test('create_list and rename_list make and change lists like the app, one household only', () =>
  withTwo(async (sql, { auth, householdId }, theirs) => {
    const made = await ok<{ id: string; name: string }>(auth, 'create_list', {
      name: '  Bau  markt ',
    });
    assertEquals(made.name, 'Bau markt');
    const renamed = await ok<{ id: string; name: string }>(auth, 'rename_list', {
      list: 'bau markt',
      name: 'Baumarkt',
    });
    assertEquals(renamed, { id: made.id, name: 'Baumarkt' });
    assertEquals(
      await ok<{ id: string; name: string }>(auth, 'rename_list', {
        list: made.id,
        name: 'Baumarkt',
      }),
      renamed,
      'a repeat changes nothing',
    );
    const lists = await ok<{ name: string }[]>(auth, 'list_lists', {});
    assertEquals(lists.map((l) => l.name), ['Einkaufsliste', 'Baumarkt']);

    const [their] = await sql<{ id: string; name: string }[]>`
      select id, name from public.lists where household_id = ${theirs.householdId}`;
    assertExists(their);
    assertStringIncludes(
      await refused(auth, 'rename_list', { list: their.id, name: 'Meins' }),
      'nicht gefunden',
    );
    assertStringIncludes(
      await refused(auth, 'create_list', { name: 'x', household: theirs.householdId }),
      'gilt nur für den Haushalt',
    );
    const [still] = await sql<
      { name: string }[]
    >`select name from public.lists where id = ${their.id}`;
    assertEquals(still?.name, their.name);

    await sql`insert into public.lists (household_id, name, position)
              select ${householdId}, 'Liste ' || n, 1 + n from generate_series(1, 48) n`;
    assertStringIncludes(await refused(auth, 'create_list', { name: 'Zu viel' }), '50 Listen');
  }));

test('add_store, rename_store and set_store_layout: plain names, the walk order, one household', () =>
  withTwo(async (sql, { auth, householdId }, theirs) => {
    const rewe = await ok<{ id: string; name: string; created: boolean }>(auth, 'add_store', {
      name: 'Rewe',
    });
    assertEquals([rewe.name, rewe.created], ['Rewe', true]);
    assertEquals(
      await ok(auth, 'add_store', { name: 'REWE' }),
      { ...rewe, created: false },
      'a known name is that store',
    );
    await ok(auth, 'add_store', { name: 'Aldi', chain: 'aldi-sued', country: 'DE' });
    assertEquals(
      [
        ...await sql`select retailer_chain, retailer_country, retailer_app from public.stores
                    where household_id = ${householdId} and name = 'Aldi'`,
      ],
      [{ retailer_chain: null, retailer_country: null, retailer_app: null }],
      'a chain field is dropped: the store is its plain name',
    );
    await sql`delete from public.stores where household_id = ${householdId} and name = 'Aldi'`;
    assertEquals(
      await ok(auth, 'rename_store', { store: 'rewe', name: 'Rewe City' }),
      { id: rewe.id, name: 'Rewe City' },
    );
    assertStringIncludes(
      await refused(auth, 'rename_store', { store: 'Rewe City', name: 'dm' }),
      'heißt schon',
    );

    const layout = await ok<{ store: string; categories: { name: string; hidden: boolean }[] }>(
      auth,
      'set_store_layout',
      { store: 'Rewe City', categories: ['Getränke', 'kühlregal'], hidden: ['Drogerie'] },
    );
    assertEquals(layout.store, 'Rewe City');
    assertEquals(layout.categories.slice(0, 2).map((c) => c.name), ['Getränke', 'Kühlregal']);
    assertEquals(layout.categories.length, 11);
    assertEquals(layout.categories.filter((c) => c.hidden).map((c) => c.name), ['👶 Drogerie']);
    const read = await ok<{ name: string; hidden: boolean }[]>(auth, 'list_categories', {
      store: 'Rewe City',
    });
    assertEquals(
      read.map((c) => [c.name, c.hidden]),
      layout.categories.map((c) => [c.name, c.hidden]),
    );

    await ok(auth, 'add_items', {
      items: [{ name: 'Brot' }, { name: 'Milch' }, { name: 'Wasser' }],
    });
    const { items } = await ok<{ items: Item[] }>(auth, 'list_items', { store: 'Rewe City' });
    assertEquals(items.map((i) => i.name), ['Wasser', 'Milch', 'Brot'], 'list_items walks it');
    assertStringIncludes(
      await refused(auth, 'set_store_layout', {
        store: 'Rewe City',
        categories: ['Getränke', 'getraenke'],
      }),
      'doppelt',
    );

    const [their] = await sql<{ id: string }[]>`
      select id from public.stores where household_id = ${theirs.householdId} and name = 'dm'`;
    assertExists(their);
    for (
      const [tool, args] of [
        ['rename_store', { store: their.id, name: 'Meins' }],
        ['set_store_layout', { store: their.id, categories: ['Kühlregal'] }],
        ['list_categories', { store: their.id }],
      ] as const
    ) {
      assertStringIncludes(await refused(auth, tool, args), 'nicht gefunden', tool);
    }
    const [dm] = await sql<
      { name: string }[]
    >`select name from public.stores where id = ${their.id}`;
    assertEquals(dm?.name, 'dm');

    await sql`insert into public.stores (household_id, name, sort_order)
              select ${householdId}, 'Laden ' || n, 100 + n from generate_series(1, 46) n`;
    assertStringIncludes(await refused(auth, 'add_store', { name: 'Penny' }), '50 Läden');
    assertEquals(
      (await sql`select 1 from public.stores where household_id = ${householdId}`).length,
      50,
    );
  }));

test('mcp_lists_stores off: the list and store writes are no tools and change nothing', () =>
  withTwo(async (sql, { auth, householdId }) => {
    for (
      const [tool, args] of [
        ['create_list', { name: 'Baumarkt' }],
        ['rename_list', { list: 'Einkaufsliste', name: 'Woche' }],
        ['add_store', { name: 'Rewe' }],
        ['rename_store', { store: 'dm', name: 'dm Markt' }],
        ['set_store_layout', { store: 'dm', categories: ['Kühlregal'] }],
      ] as const
    ) {
      const { result, error } = await call(auth, tool, args, SWITCHED_OFF);
      const text = JSON.stringify(result ?? error);
      assert(/not found|unknown/i.test(text), `${tool}: ${text}`);
    }
    const [lists] = await sql<{ n: number }[]>`
      select count(*)::int as n from public.lists where household_id = ${householdId}`;
    const [stores] = await sql<{ n: number; names: string }[]>`
      select count(*)::int as n, string_agg(name, ',' order by name) as names
      from public.stores where household_id = ${householdId}`;
    assertEquals([lists?.n, stores?.n, stores?.names], [1, 3, 'dm,Edeka,Lidl']);
    const [order] = await sql<{ n: number }[]>`
      select count(*)::int as n from public.store_category_order o
      join public.stores s on s.id = o.store_id
      where s.household_id = ${householdId} and s.name = 'dm' and o.sort_order = 10`;
    assertEquals(order?.n, 1, 'dm keeps its seeded first category');
  }));

test('production reads app_switches.mcp_lists_stores per request: off it lists none, on all five', () =>
  withTwo(async (sql, { auth }) => {
    const [before] = await sql<{ enabled: boolean }[]>`
      select enabled from public.app_switches where key = 'mcp_lists_stores'`;
    const listed = async () => {
      const res = await productionDeps.serve(
        new Request('http://edge/mcp', {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            accept: 'application/json, text/event-stream',
            'mcp-protocol-version': '2025-11-25',
          },
          body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
        }),
        auth,
      );
      const text = await res.text();
      const data = text.split('\n').find((l) => l.startsWith('data: '));
      const { result } = JSON.parse(data ? data.slice(6) : text);
      return (result.tools as { name: string }[]).map((t) => t.name)
        .filter((n) => SWITCHED_TOOLS.includes(n)).sort();
    };
    try {
      await sql`update public.app_switches set enabled = false where key = 'mcp_lists_stores'`;
      assertEquals(await listed(), []);
      await sql`update public.app_switches set enabled = true where key = 'mcp_lists_stores'`;
      assertEquals(await listed(), [...SWITCHED_TOOLS].sort());
    } finally {
      await sql`update public.app_switches set enabled = ${before?.enabled ?? false}
                where key = 'mcp_lists_stores'`;
    }
  }));

const SWITCHED_TOOLS = [
  'create_list',
  'rename_list',
  'add_store',
  'rename_store',
  'set_store_layout',
];

test('review 0: a member of two households acts in the one a call names, else its default', () =>
  withTwo(async (sql, mine, theirs) => {
    // RLS lets this member see both households: only the household filters keep a call in one.
    await sql`insert into public.household_members (household_id, user_id, role)
              values (${theirs.householdId}, ${mine.auth.userId}, 'member')`;
    const auth = { ...mine.auth, via: 'oauth' } as Auth;
    const there = { household: theirs.householdId };
    await ok(theirs.auth, 'add_items', { items: [{ name: 'Fremdbrot' }] });
    await ok(theirs.auth, 'tick_items', { items: ['Fremdbrot'] });
    await ok(auth, 'add_items', { items: [{ name: 'Eigenmilch' }] });
    await ok(auth, 'tick_items', { items: ['Eigenmilch'] });

    const recent = async (args: Record<string, unknown>) =>
      (await ok<{ items: Item[] }>(auth, 'list_recent', args)).items.map((i) => i.name);
    assertEquals(await recent({}), ['Eigenmilch'], 'list_recent: the default household');
    assertEquals(await recent(there), ['Fremdbrot'], 'list_recent: the household named');
    const usual = async (args: Record<string, unknown>) =>
      (await ok<{ name: string }[]>(auth, 'suggest_items', args)).map((u) => u.name);
    assertEquals(await usual({}), ['Eigenmilch']);
    assertEquals(await usual(there), ['Fremdbrot']);

    const [theirList] = await sql<{ id: string; name: string }[]>`
      select id, name from public.lists where household_id = ${theirs.householdId}`;
    const [theirStore] = await sql<{ id: string }[]>`
      select id from public.stores where household_id = ${theirs.householdId} and name = 'dm'`;
    assertExists(theirList);
    assertExists(theirStore);
    for (
      const [tool, args] of [
        ['rename_list', { list: theirList.id, name: 'Gekapert' }],
        ['rename_store', { store: theirStore.id, name: 'Gekapert' }],
        ['set_store_layout', { store: theirStore.id, categories: ['Sonstiges'] }],
        ['list_categories', { store: theirStore.id }],
      ] as const
    ) {
      assertStringIncludes(
        await refused(auth, tool, args),
        'nicht gefunden',
        `${tool} by id, no household`,
      );
    }
    const [stillList] = await sql<
      { name: string }[]
    >`select name from public.lists where id = ${theirList.id}`;
    const [stillStore] = await sql<
      { name: string }[]
    >`select name from public.stores where id = ${theirStore.id}`;
    assertEquals([stillList?.name, stillStore?.name], [theirList.name, 'dm']);

    const made = await ok<{ id: string }>(auth, 'create_list', { name: 'Baumarkt' });
    const shop = await ok<{ id: string }>(auth, 'add_store', { name: 'Rewe' });
    const madeThere = await ok<{ id: string }>(auth, 'create_list', { name: 'Garten', ...there });
    const homeOf = async (table: 'lists' | 'stores', id: string) =>
      (await sql<{ h: string }[]>`select household_id as h from public.${
        sql(table)
      } where id = ${id}`)[0]?.h;
    assertEquals(
      [
        await homeOf('lists', made.id),
        await homeOf('stores', shop.id),
        await homeOf('lists', madeThere.id),
      ],
      [mine.householdId, mine.householdId, theirs.householdId],
      'without household the default one, with it the one named',
    );
  }));
