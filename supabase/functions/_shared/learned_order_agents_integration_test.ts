// Job 352: the agents' side of the learned order against the local stack, through the API's
// handle() and the MCP tools as a client calls them: `position` in both order modes, list_items
// and GET /v1/items?order=walk store by store, the v1 default order unchanged, place_item and
// set_store_order with their refusals, and ticks marked as an agent's. Runs with FG_DB_TEST=1 and
// SUPABASE_DB_URL (db gate).
import { assert, assertEquals, assertExists } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import postgres from 'postgres';
import { handle } from '../api/handler.ts';
import { buildServer, type Gate } from '../mcp/tools.ts';
import { asUser, databaseUrl, type Tx } from './db.ts';
import { itemById, setItemStatus, tickItems, untickItems } from './list.ts';
import type { Access } from './premium.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Item = {
  id: string;
  name: string;
  store: string | null;
  storeId: string | null;
  position: number | null;
  status: string;
};

type Household = {
  sql: postgres.Sql;
  userId: string;
  householdId: string;
  token: string;
  /** Item ids by name. */
  ids: Record<string, string>;
};

/** dm 10, Lidl 20, Edeka 30 (the default stores); the items by store, Salz without one. */
const STOCK: Record<string, string[]> = {
  Edeka: ['Mehl', 'Eier', 'Milch', 'Butter'],
  Lidl: ['Brot', 'Äpfel'],
  dm: ['Zahnpasta'],
};

async function withHousehold(work: (h: Household) => Promise<void>) {
  const sql = postgres(databaseUrl(), { max: 2, prepare: false, onnotice: () => {} });
  const userId = crypto.randomUUID();
  const log = console.log;
  console.log = () => {};
  const switches = await sql<{ key: string; enabled: boolean }[]>`
    select key, enabled from public.app_switches where key in ('integration_lock', 'public_api')`;
  try {
    await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`
        select id from public.create_household(p_name => '352', p_default_stores => true)`;
      assertExists(row);
      return row.id;
    });
    await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
    await sql`update public.app_switches set enabled = true where key = 'public_api'`;
    const token = await sql.begin(async (tx) => {
      const claims = { sub: userId, role: 'authenticated', 'session_id': crypto.randomUUID() };
      await tx`select set_config('role', 'authenticated', true),
                      set_config('request.jwt.claims', ${JSON.stringify(claims)}, true)`;
      const [row] = await tx<{ token: string }[]>`
        select token from public.create_api_token('352', ${['read', 'write']})`;
      return row?.token ?? '';
    });
    const h: Household = { sql, userId, householdId, token, ids: {} };
    for (const [store, names] of Object.entries(STOCK)) {
      const res = await api(h, 'POST', '/items', { items: names.map((name) => ({ name, store })) });
      for (const item of (await res.json()).data.added as Item[]) h.ids[item.name] = item.id;
    }
    const salt = await api(h, 'POST', '/items', { items: [{ name: 'Salz' }] });
    const [salz] = (await salt.json()).data.added as Item[];
    assertExists(salz);
    h.ids.Salz = salz.id;
    await (await api(h, 'PATCH', `/items/${salz.id}`, { store: null })).body?.cancel();
    await work(h);
  } finally {
    console.log = log;
    for (const { key, enabled } of switches) {
      await sql`update public.app_switches set enabled = ${enabled} where key = ${key}`;
    }
    await sql`delete from public.households where id in (
      select household_id from public.household_members where user_id = ${userId})`;
    await sql`delete from auth.users where id = ${userId}`;
    await sql.end();
  }
}

function api(h: Household, method: string, path: string, body?: unknown): Promise<Response> {
  return handle(
    new Request(`http://localhost/api/v1${path}`, {
      method,
      headers: {
        authorization: `Bearer ${h.token}`,
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? null : JSON.stringify(body),
    }),
  );
}

async function data<T>(res: Promise<Response>, status = 200): Promise<T> {
  const r = await res;
  const body = await r.json();
  assertEquals(r.status, status, JSON.stringify(body));
  return body.data as T;
}

async function errorCode(res: Promise<Response>, status: number): Promise<string> {
  const r = await res;
  assertEquals(r.status, status);
  return (await r.json()).error.code;
}

const open: Gate = () => Promise.resolve<Access>('open');

/** A tool's result: its JSON, or the error text when isError. */
async function tool(
  h: Household,
  name: string,
  args: Record<string, unknown> = {},
): Promise<{ ok: true; value: unknown } | { ok: false; text: string }> {
  const auth = {
    userId: h.userId,
    householdId: h.householdId,
    via: 'pat' as const,
    scopes: ['read', 'write'] as const,
  };
  const res = await createMcpHandler(() => buildServer(auth, open, () => Promise.resolve())).fetch(
    new Request('http://edge/mcp', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        'mcp-protocol-version': '2025-06-18',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name, arguments: args },
      }),
    }),
  );
  const text = await res.text();
  const line = text.split('\n').find((l) => l.startsWith('data: '));
  const { result } = JSON.parse(line ? line.slice(6) : text) as {
    result: { isError?: boolean; content: { text: string }[] };
  };
  const out = result.content[0]?.text ?? '';
  return result.isError ? { ok: false, text: out } : { ok: true, value: JSON.parse(out) };
}

async function toolValue<T>(h: Household, name: string, args: Record<string, unknown> = {}) {
  const r = await tool(h, name, args);
  if (!r.ok) throw new Error(`${name}: ${r.text}`);
  return r.value as T;
}

type Listed = { order: string; items: Item[] };

const learn = (h: Household) =>
  asUser(h.userId, (tx) => tx`select public.set_order_mode(${h.householdId}, 'learned')`);

/** The names of one store's items in a list, in their order. */
const inStore = (items: Item[], store: string | null) =>
  items.filter((i) => i.store === store).map((i) => i.name);

/**
 * Store by store (dm, Lidl, Edeka, then none), and inside each store positions 1, 2, 3...: the
 * walk order is the order of `position`.
 */
function assertWalk(items: Item[]) {
  const stores = [...new Set(items.map((i) => i.store))];
  assertEquals(stores, ['dm', 'Lidl', 'Edeka', null].filter((s) => stores.includes(s)));
  for (const store of stores) {
    const section = items.filter((i) => i.store === store);
    assertEquals(section.map((i) => i.position), section.map((_, n) => n + 1), `${store}`);
  }
}

/** The v1 default order, written out independently of list.ts: categories, then the walk. */
async function aisleOrder(h: Household): Promise<string[]> {
  const rows = await h.sql<{ name: string }[]>`
    select i.name from public.items i join public.categories c on c.id = i.category_id
    where i.household_id = ${h.householdId} and i.status = 'active'
    order by c.sort_order, c.name, coalesce(i.sort_key, 'Infinity'::float8), i.created_at, i.id`;
  return rows.map((r) => r.name);
}

/** Every page of GET /v1/items with [query], two items a page. */
async function pages(h: Household, query: string): Promise<Item[]> {
  const all: Item[] = [];
  let cursor: string | null = null;
  do {
    const page: Response = await api(
      h,
      'GET',
      `/items?limit=2${query}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`,
    );
    const body = await page.json();
    assertEquals(page.status, 200, JSON.stringify(body));
    all.push(...body.data);
    cursor = body.nextCursor;
  } while (cursor);
  return all;
}

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('categories household: list_items keeps the aisle order, items carry their store position', () =>
  withHousehold(async (h) => {
    const listed = await toolValue<Listed>(h, 'list_items');
    assertEquals(listed.order, 'aisle');
    assertEquals(listed.items.map((i) => i.name), await aisleOrder(h));
    const walk = await pages(h, '&order=walk');
    assertWalk(walk);
    const byId = new Map(walk.map((i) => [i.id, i.position]));
    for (const item of listed.items) assertEquals(item.position, byId.get(item.id), item.name);
    const ticked = await data<Item>(api(h, 'POST', `/items/${h.ids.Brot}/tick`));
    assertEquals(ticked.position, null, 'a ticked item has no position');
    assertEquals((await data<Item>(api(h, 'GET', `/items/${h.ids.Äpfel}`))).position, 1);
  }));

test('learned household: list_items and order=walk go store by store in walk order', () =>
  withHousehold(async (h) => {
    await learn(h);
    const listed = await toolValue<Listed>(h, 'list_items');
    assertEquals(listed.order, 'walk');
    assertWalk(listed.items);
    assertEquals(listed.items.length, 8);
    assertEquals((await pages(h, '&order=walk')).map((i) => i.id), listed.items.map((i) => i.id));
    const edeka = await toolValue<Listed>(h, 'list_items', { store: 'Edeka' });
    assertEquals(edeka.items.map((i) => i.store), ['Edeka', 'Edeka', 'Edeka', 'Edeka', null]);
  }));

test('v1 default order is the aisle order in both modes, its cursors as before', () =>
  withHousehold(async (h) => {
    assertEquals((await pages(h, '')).map((i) => i.name), await aisleOrder(h));
    await learn(h);
    assertEquals((await pages(h, '')).map((i) => i.name), await aisleOrder(h));
    assertEquals((await pages(h, '&order=aisle')).map((i) => i.name), await aisleOrder(h));
  }));

test('order=walk pages; a cursor of the other order or from before a mode switch is invalid_cursor', () =>
  withHousehold(async (h) => {
    const whole = await data<Item[]>(api(h, 'GET', '/items?order=walk'));
    assertEquals((await pages(h, '&order=walk')).map((i) => i.id), whole.map((i) => i.id));
    const first = await (await api(h, 'GET', '/items?order=walk&limit=2')).json();
    const walkCursor = encodeURIComponent(first.nextCursor);
    const aisle = await (await api(h, 'GET', '/items?limit=2')).json();
    const aisleCursor = encodeURIComponent(aisle.nextCursor);
    assertEquals(
      await errorCode(api(h, 'GET', `/items?limit=2&cursor=${walkCursor}`), 400),
      'invalid_cursor',
    );
    assertEquals(
      await errorCode(api(h, 'GET', `/items?order=walk&limit=2&cursor=${aisleCursor}`), 400),
      'invalid_cursor',
    );
    await learn(h);
    assertEquals(
      await errorCode(api(h, 'GET', `/items?order=walk&limit=2&cursor=${walkCursor}`), 400),
      'invalid_cursor',
      'the household switched to the learned order while paging',
    );
    const after = await data<Item[]>(api(h, 'GET', `/items?limit=2&cursor=${aisleCursor}`));
    assertEquals(after.length, 2, 'an aisle cursor still works after the switch');
  }));

test('place_item by name: "Eier hinter Mehl" in a learned household, idempotent', () =>
  withHousehold(async (h) => {
    await learn(h);
    const placed = await toolValue<Item>(h, 'place_item', { item: 'Butter', after: 'Mehl' });
    assertEquals(placed.name, 'Butter');
    const edeka = async () => inStore((await toolValue<Listed>(h, 'list_items')).items, 'Edeka');
    const once = await edeka();
    assertEquals(once[once.indexOf('Mehl') + 1], 'Butter');
    await toolValue<Item>(h, 'place_item', { item: 'Butter', after: 'Mehl' });
    assertEquals(await edeka(), once, 'placing again changes nothing');

    const before = await toolValue<Item>(h, 'place_item', { item: 'Milch', before: 'Mehl' });
    const now = await edeka();
    assertEquals(now[now.indexOf('Mehl') - 1], 'Milch');
    const mehl = await data<Item>(api(h, 'GET', `/items/${h.ids.Mehl}`));
    assertEquals(before.position, (mehl.position ?? 0) - 1);

    const byApi = await data<Item>(
      api(h, 'POST', `/items/${h.ids.Eier}/place`, { before: h.ids.Milch }),
    );
    const milch = await data<Item>(api(h, 'GET', `/items/${h.ids.Milch}`));
    assertEquals(byApi.position, (milch.position ?? 0) - 1);

    const neither = await tool(h, 'place_item', { item: 'Butter' });
    assert(!neither.ok && neither.text.includes('genau eines'));
    const itself = await tool(h, 'place_item', { item: 'Butter', after: 'Butter' });
    assert(!itself.ok && itself.text.includes('neben sich selbst'));
  }));

test('an anchor in another store: 422 anchor_in_other_store, a tool error naming move_item', () =>
  withHousehold(async (h) => {
    await learn(h);
    const before = await data<Item[]>(api(h, 'GET', '/items?order=walk'));
    assertEquals(
      await errorCode(api(h, 'POST', `/items/${h.ids.Butter}/place`, { after: h.ids.Brot }), 422),
      'anchor_in_other_store',
    );
    const r = await tool(h, 'place_item', { item: 'Butter', after: 'Brot' });
    assert(!r.ok && r.text.includes('move_item'), JSON.stringify(r));
    assertEquals(await data<Item[]>(api(h, 'GET', '/items?order=walk')), before, 'nothing moved');
    assertEquals(
      await errorCode(
        api(h, 'POST', `/items/${h.ids.Butter}/place`, { after: crypto.randomUUID() }),
        422,
      ),
      'anchor_not_found',
    );
  }));

test("categories household: place takes the anchor's store and category, as a drag does", () =>
  withHousehold(async (h) => {
    const placed = await data<Item>(
      api(h, 'POST', `/items/${h.ids.Butter}/place`, { after: h.ids.Brot }),
    );
    assertEquals(placed.store, 'Lidl');
    const brot = await data<Item>(api(h, 'GET', `/items/${h.ids.Brot}`));
    assertEquals(placed.position, (brot.position ?? 0) + 1);
  }));

test('set_store_order: 409 order_mode for categories; learned: listed first, the rest after', () =>
  withHousehold(async (h) => {
    const edekaId = (await data<Item>(api(h, 'GET', `/items/${h.ids.Mehl}`))).storeId;
    assertExists(edekaId);
    const order = { items: [h.ids.Butter, h.ids.Milch] };
    assertEquals(
      await errorCode(api(h, 'PUT', `/stores/${edekaId}/order`, order), 409),
      'order_mode',
    );
    const refused = await tool(h, 'set_store_order', { store: 'Edeka', items: ['Butter'] });
    assert(!refused.ok && refused.text.includes('place_item'), JSON.stringify(refused));

    await learn(h);
    const rest = inStore((await toolValue<Listed>(h, 'list_items')).items, 'Edeka')
      .filter((n) => n !== 'Butter' && n !== 'Milch');
    const set = await data<Item[]>(api(h, 'PUT', `/stores/${edekaId}/order`, order));
    assertEquals(set.map((i) => i.name), ['Butter', 'Milch', ...rest]);
    assertEquals(set.map((i) => i.position), [1, 2, 3, 4]);
    assertEquals(await data<Item[]>(api(h, 'PUT', `/stores/${edekaId}/order`, order)), set);

    const byName = await toolValue<{ store: string; items: Item[] }>(h, 'set_store_order', {
      store: 'edeka',
      items: ['Eier', 'Mehl'],
    });
    assertEquals(byName.store, 'Edeka');
    assertEquals(byName.items.map((i) => i.name), ['Eier', 'Mehl', 'Butter', 'Milch']);
    assertEquals(
      inStore((await toolValue<Listed>(h, 'list_items')).items, 'Edeka'),
      ['Eier', 'Mehl', 'Butter', 'Milch'],
    );

    const wrong = await api(h, 'PUT', `/stores/${edekaId}/order`, { items: [h.ids.Brot] });
    assertEquals(wrong.status, 422);
    assertEquals((await wrong.json()).error, {
      code: 'items_not_in_store',
      message: 'Some items are not open items of this store.',
      details: { items: [h.ids.Brot] },
    });
    assertEquals(
      await errorCode(api(h, 'PUT', `/stores/${crypto.randomUUID()}/order`, order), 404),
      'store_not_found',
    );
  }));

test('MCP and API ticks and unticks run with fg.tick_source agent', () =>
  withHousehold(async (h) => {
    const sourceAfter = (work: (tx: Tx) => Promise<unknown>) =>
      asUser(h.userId, async (tx) => {
        await work(tx);
        const [row] = await tx<{ source: string | null }[]>`
          select current_setting('fg.tick_source', true) as source`;
        return row?.source;
      });
    const { householdId, ids } = h;
    const mehl = ids.Mehl ?? '';
    assertEquals(await sourceAfter((tx) => tickItems(tx, householdId, ['Brot'])), 'agent');
    assertEquals(await sourceAfter((tx) => untickItems(tx, householdId, ['Brot'])), 'agent');
    assertEquals(
      await sourceAfter((tx) => setItemStatus(tx, householdId, mehl, 'bought')),
      'agent',
    );
    assertEquals(
      await sourceAfter((tx) => setItemStatus(tx, householdId, mehl, 'active')),
      'agent',
    );
    assert(
      await sourceAfter((tx) => itemById(tx, householdId, mehl)) !== 'agent',
      'a read in a new transaction is no tick',
    );
  }));

test('a tick and an untick through MCP and the API are stored as source agent', () =>
  withHousehold(async (h) => {
    await toolValue(h, 'tick_items', { items: ['Brot'] });
    await toolValue(h, 'untick_items', { items: ['Brot'] });
    await data<Item>(api(h, 'POST', `/items/${h.ids.Mehl}/tick`));
    await data<Item>(api(h, 'POST', `/items/${h.ids.Mehl}/untick`));
    const names = new Map(Object.entries(h.ids).map(([name, id]) => [id, name]));
    const rows = await h.sql<{ item_id: string; action: string; source: string | null }[]>`
      select item_id, action, source from public.item_events
      where household_id = ${h.householdId} and action in ('bought', 'restored')
      order by id`;
    assertEquals(rows.map((r) => [names.get(r.item_id), r.action, r.source]), [
      ['Brot', 'bought', 'agent'],
      ['Brot', 'restored', 'agent'],
      ['Mehl', 'bought', 'agent'],
      ['Mehl', 'restored', 'agent'],
    ]);
  }));

test('learned household: an item moved to another store and back takes its place there again', () =>
  withHousehold(async (h) => {
    await learn(h);
    const edeka = async () => inStore((await toolValue<Listed>(h, 'list_items')).items, 'Edeka');
    const [first] = (await edeka()).filter((n) => n !== 'Milch');
    await toolValue<Item>(h, 'place_item', { item: 'Milch', before: first });
    const placed = await edeka();
    assertEquals(placed[0], 'Milch');
    await toolValue<Item>(h, 'update_item', { item: 'Milch', store: 'Lidl' });
    assertEquals(await edeka(), placed.filter((n) => n !== 'Milch'));
    const back = await data<Item>(api(h, 'PATCH', `/items/${h.ids.Milch}`, { store: 'Edeka' }));
    assertEquals(back.position, 1);
    assertEquals(await edeka(), placed, 'its manual place in Edeka, not the end of its group');
  }));
