// Job 344: update_item, remove_items, untick_items, get_item and merge_items through the SDK's
// streamable HTTP handler as a client sees it, against the local stack (FG_DB_TEST=1 and
// SUPABASE_DB_URL, like households_integration_test.ts). They make the app's own writes, so the
// household learns, refuses twins and merges quantities as the app does.
import { assert, assertEquals, assertExists, assertStringIncludes } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import postgres from 'postgres';
import type { Auth } from '../_shared/auth.ts';
import { asUser, databaseUrl } from '../_shared/db.ts';
import type { Access } from '../_shared/premium.ts';
import { buildServer } from './tools.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Item = {
  id: string;
  name: string;
  quantity: string | null;
  brand: string | null;
  properties: string | null;
  category: string;
  listId: string;
};
type Result = { isError?: boolean; content: { text: string }[] };

async function call(auth: Auth, name: string, args: Record<string, unknown>): Promise<Result> {
  const res = await createMcpHandler(() =>
    buildServer(auth, () => Promise.resolve<Access>('open'), () => Promise.resolve())
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
  return JSON.parse(data ? data.slice(6) : text).result as Result;
}

/** The answer of a call that must succeed. */
async function ok<T>(auth: Auth, name: string, args: Record<string, unknown>): Promise<T> {
  const r = await call(auth, name, args);
  assertEquals(r.isError, undefined, `${name}: ${r.content[0]?.text}`);
  return JSON.parse(r.content[0]?.text ?? 'null') as T;
}

/** The text of a call that must fail as a tool error. */
async function refused(auth: Auth, name: string, args: Record<string, unknown>): Promise<string> {
  const r = await call(auth, name, args);
  assertEquals(r.isError, true, `${name} ${JSON.stringify(args)} must fail`);
  return r.content[0]?.text ?? '';
}

type Member = { auth: Auth; householdId: string };

/** Two users, each with a fresh household, removed afterwards. */
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
        const [row] = await tx<{ id: string }[]>`select id from public.create_household('344')`;
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

async function add(auth: Auth, ...names: string[]): Promise<Item[]> {
  const { added } = await ok<{ added: Item[] }>(auth, 'add_items', {
    items: names.map((name) => ({ name })),
  });
  return added;
}

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('update_item edits the given fields and moves to another list; a twin is refused', () =>
  withTwo(async (sql, { auth, householdId }, theirs) => {
    await asUser(
      auth.userId,
      (tx) => tx`select public.create_list(${householdId}, 'Baumarkt', gen_random_uuid())`,
    );
    const [gurken, hafer] = await add(auth, '2 Gurken', 'Hafermilch', 'Milch');
    assertExists(gurken);
    assertExists(hafer);

    const edited = await ok<Item>(auth, 'update_item', {
      item: 'gurken',
      name: 'Salatgurken',
      quantity: null,
      brand: 'Bio',
    });
    assertEquals(
      [edited.id, edited.name, edited.quantity, edited.brand],
      [gurken.id, 'Salatgurken', null, 'Bio'],
    );
    const moved = await ok<Item>(auth, 'update_item', {
      item: 'Salatgurken',
      toList: 'Baumarkt',
      category: 'Kühlregal',
      brand: '',
    });
    const [hardware] = await sql<{ id: string }[]>`
      select id from public.lists where household_id = ${householdId} and name = 'Baumarkt'`;
    assertEquals([moved.listId, moved.category, moved.brand], [hardware?.id, 'Kühlregal', null]);
    const found = await ok<Item>(auth, 'update_item', {
      item: 'salatgurken',
      list: 'Baumarkt',
      quantity: '4',
    });
    assertEquals(found.quantity, '4', '"list" says where it is now');

    const twin = await refused(auth, 'update_item', { item: 'Hafermilch', name: 'milch' });
    assertEquals(twin, '„milch“ steht schon offen auf der Liste.');
    const [still] = await sql<
      { name: string }[]
    >`select name from public.items where id = ${hafer.id}`;
    assertEquals(still?.name, 'Hafermilch');

    assertStringIncludes(
      await refused(auth, 'update_item', { item: 'Hafermilch' }),
      'Gib an, was sich ändern soll.',
    );
    assertStringIncludes(
      await refused(theirs.auth, 'update_item', { item: hafer.id, name: 'Fremd' }),
      'nicht gefunden',
    );
  }));

test('remove_items deletes open items, reports the rest, and the household keeps its lesson', () =>
  withTwo(async (sql, { auth }, theirs) => {
    const [basil, bread] = await add(auth, 'Basilikum', 'Brot');
    assertExists(basil);
    assertExists(bread);
    assert(basil.category !== 'Kühlregal');
    await ok(auth, 'move_item', { item: 'Basilikum', category: 'Kühlregal' });

    const other = await ok<{ removed: Item[]; notFound: { item: string }[] }>(
      theirs.auth,
      'remove_items',
      { items: [bread.id] },
    );
    assertEquals([other.removed, other.notFound.map((n) => n.item)], [[], [bread.id]]);

    const removed = await ok<{ removed: Item[]; notFound: { item: string }[] }>(
      auth,
      'remove_items',
      { items: ['basilikum', 'Wein'] },
    );
    assertEquals(removed.removed.map((i) => [i.id, i.category]), [[basil.id, 'Kühlregal']]);
    assertEquals(removed.notFound.map((n) => n.item), ['Wein']);
    const again = await ok<{ removed: Item[] }>(auth, 'remove_items', { items: [basil.id] });
    assertEquals(again.removed, [], 'a second call changes nothing');

    const [back] = await add(auth, 'Basilikum');
    assertEquals(back?.category, 'Kühlregal', 'the delete kept the lesson');
    const left = await sql<{ id: string }[]>`select id from public.items where id = ${bread.id}`;
    assertEquals(left.length, 1, "the other household's call deleted nothing");
  }));

test('untick_items: a name finds the latest ticked row of it, an id any ticked item', () =>
  withTwo(async (sql, { auth, householdId }, theirs) => {
    const [early, late] = await sql<{ id: string }[]>`
      insert into public.items (household_id, name, status) values
        (${householdId}, 'Milch', 'bought'), (${householdId}, 'Milch', 'bought')
      returning id`;
    assertExists(early);
    assertExists(late);
    // The status trigger stamps bought_at with now(); the late row was ticked an hour ago.
    for (const [id, ago] of [[early.id, '2 days'], [late.id, '1 hour']] as const) {
      await sql`update public.items set bought_at = now() - ${ago}::interval where id = ${id}`;
    }
    const [open] = await add(auth, 'Brot');
    assertExists(open);

    const foreign = await ok<{ unticked: Item[]; notFound: unknown[] }>(
      theirs.auth,
      'untick_items',
      { items: [early.id] },
    );
    assertEquals([foreign.unticked, foreign.notFound.length], [[], 1]);

    const byName = await ok<{ unticked: Item[]; notFound: { item: string; reason: string }[] }>(
      auth,
      'untick_items',
      { items: ['milch', open.id] },
    );
    assertEquals(byName.unticked.map((i) => i.id), [late.id], 'the most recently ticked Milch');
    assertEquals(byName.notFound, [
      { item: open.id, reason: `Eintrag „${open.id}“ ist nicht abgehakt.` },
    ]);
    const again = await ok<{ unticked: Item[]; notFound: { item: string; reason: string }[] }>(
      auth,
      'untick_items',
      { items: ['Milch'] },
    );
    assertEquals(again.unticked, [], 'a repeat brings back no older ticked twin');
    assertEquals(again.notFound, [{
      item: 'Milch',
      reason: '„Milch“ steht schon offen auf der Liste.',
    }]);
    const stillTicked = await sql<{ status: string }[]>`
      select status from public.items where id = ${early.id}`;
    assertEquals(stillTicked.map((r) => r.status), ['bought']);
    const byId = await ok<{ unticked: Item[] }>(auth, 'untick_items', { items: [early.id] });
    assertEquals(byId.unticked.map((i) => i.id), [early.id]);
    const rows = await sql<{ status: string }[]>`
      select status from public.items where id in (${early.id}, ${late.id})`;
    assertEquals(rows.map((r) => r.status), ['active', 'active']);
  }));

test('get_item shows an item with its status; another household finds nothing', () =>
  withTwo(async (_sql, { auth }, theirs) => {
    const [milk] = await add(auth, '2 Milch');
    assertExists(milk);
    const byName = await ok<Item & { status: string; addedAt: string }>(auth, 'get_item', {
      item: 'milch',
    });
    assertEquals([byName.id, byName.quantity, byName.status], [milk.id, '2', 'open']);
    assert(/^\d{4}-\d{2}-\d{2}T/.test(byName.addedAt));
    await ok(auth, 'tick_items', { items: [milk.id] });
    const ticked = await ok<{ status: string }>(auth, 'get_item', { item: milk.id });
    assertEquals(ticked.status, 'ticked');
    assertStringIncludes(await refused(auth, 'get_item', { item: 'Milch' }), 'nicht gefunden');
    assertStringIncludes(
      await refused(theirs.auth, 'get_item', { item: milk.id }),
      'nicht gefunden',
    );
  }));

test('merge_items adds the quantities into the kept item and deletes the other', () =>
  withTwo(async (sql, { auth }, theirs) => {
    const [moehren, karotten] = await add(auth, '2 Möhren', '3 Karotten');
    assertExists(moehren);
    assertExists(karotten);

    assertStringIncludes(
      await refused(theirs.auth, 'merge_items', { keep: moehren.id, merge: karotten.id }),
      'nicht gefunden',
    );
    assertStringIncludes(
      await refused(auth, 'merge_items', { keep: 'Möhren', merge: moehren.id }),
      'derselbe Eintrag',
    );

    const merged = await ok<{ kept: Item; merged: Item }>(auth, 'merge_items', {
      keep: 'möhren',
      merge: 'Karotten',
    });
    assertEquals(
      [merged.kept.id, merged.kept.name, merged.kept.quantity],
      [moehren.id, 'Möhren', '5'],
    );
    assertEquals([merged.merged.id, merged.merged.quantity], [karotten.id, '3']);
    const gone = await sql`select 1 from public.items where id = ${karotten.id}`;
    assertEquals(gone.length, 0, 'the merged row is gone');

    const [a, b] = await add(auth, 'Haferflocken', 'Dinkelflocken');
    assertExists(a);
    assertExists(b);
    await ok(auth, 'update_item', { item: a.id, quantity: 'eine große Packung fürs Wochenende' });
    await ok(auth, 'update_item', { item: b.id, quantity: 'zwei kleine Tüten' });
    assertEquals(
      await refused(auth, 'merge_items', { keep: a.id, merge: b.id }),
      'Die zusammengeführte Menge wäre zu lang (höchstens 40 Zeichen).',
    );
    const both = await sql`select 1 from public.items where id in (${a.id}, ${b.id})`;
    assertEquals(both.length, 2, 'the refused merge changed nothing');
  }));

test('merge_items refuses two items on different lists, like the app', () =>
  withTwo(async (sql, { auth, householdId }) => {
    await asUser(
      auth.userId,
      (tx) => tx`select public.create_list(${householdId}, 'Baumarkt', gen_random_uuid())`,
    );
    const [milk] = await add(auth, '2 Milch');
    assertExists(milk);
    const there = await ok<{ added: Item[] }>(auth, 'add_items', {
      items: [{ name: 'Hafermilch', quantity: '3' }],
      list: 'Baumarkt',
    });
    const oat = there.added[0];
    assertExists(oat);
    assert(oat.listId !== milk.listId);
    assertStringIncludes(
      await refused(auth, 'merge_items', { keep: milk.id, merge: oat.id }),
      'verschiedenen Listen',
    );
    const rows = await sql<{ id: string; quantity: string }[]>`
      select id, quantity from public.items where id in (${milk.id}, ${oat.id}) order by quantity`;
    assertEquals(rows.map((r) => [r.id, r.quantity]), [[milk.id, '2'], [oat.id, '3']]);
  }));
