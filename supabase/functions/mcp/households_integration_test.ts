// Job 169b: the MCP tools for a user in several households, through the SDK's streamable HTTP
// handler as a client sees it. list_households names them; "household" (id or name in any case) picks
// one, the default without it; a personal access token stays in its own household; the premium
// gate asks about the household a call acts in. Runs with FG_DB_TEST=1 and SUPABASE_DB_URL (db gate).
import { assert, assertEquals } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import postgres from 'postgres';
import type { Auth } from '../_shared/auth.ts';
import { databaseUrl } from '../_shared/db.ts';
import type { Access } from '../_shared/premium.ts';
import { buildServer, type Gate, premiumRequired } from './tools.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Result = { isError?: boolean; content: { text: string }[] };

async function call(
  auth: Auth,
  gate: Gate,
  name: string,
  args: Record<string, unknown> = {},
): Promise<Result> {
  const res = await createMcpHandler(() => buildServer(auth, gate, () => Promise.resolve())).fetch(
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
  assertEquals(res.status, 200);
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  return JSON.parse(data ? data.slice(6) : text).result as Result;
}

const open: Gate = () => Promise.resolve<Access>('open');

/** Peter in Zuhause (default) and Sommerfest (with Lea); Lea's own household Bei Lea. */
async function withPeter(
  work: (s: { peter: string; ids: Record<string, string> }) => Promise<void>,
) {
  const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
  const peter = crypto.randomUUID();
  const lea = crypto.randomUUID();
  const ids: Record<string, string> = {};
  try {
    for (const id of [peter, lea]) {
      await sql`insert into auth.users (id, email) values (${id}, ${`${id}@fg-test.invalid`})`;
    }
    for (
      const [name, owner, others] of [
        ['Zuhause', peter, []],
        ['Sommerfest', peter, [lea]],
        ['Bei Lea', lea, []],
      ] as const
    ) {
      const [row] = await sql<{ id: string }[]>`
        insert into public.households (name, created_by) values (${name}, ${owner}) returning id`;
      const id = row?.id ?? '';
      ids[name] = id;
      await sql`insert into public.household_members (household_id, user_id, role, joined_at)
        values (${id}, ${owner}, 'owner', now() - make_interval(days => ${
        3 - Object.keys(ids).length
      }))`;
      for (const other of others) {
        await sql`insert into public.household_members (household_id, user_id) values (${id}, ${other})`;
      }
      await sql`select public.seed_household(${id}, false)`;
    }
    await sql`insert into public.items (household_id, name) values
      (${ids.Zuhause ?? ''}, 'Milch'), (${ids.Sommerfest ?? ''}, 'Bratwurst')`;
    await work({ peter, ids });
  } finally {
    await sql`delete from public.households where created_by in (${peter}, ${lea})`;
    await sql`delete from auth.users where id in (${peter}, ${lea})`;
    await sql.end();
  }
}

const oauth = (userId: string, householdId: string): Auth => ({
  userId,
  householdId,
  via: 'oauth',
  clientId: 'c',
  sessionId: crypto.randomUUID(),
});

const items = (r: Result) =>
  (JSON.parse(r.content[0]?.text ?? '{}') as { items: { name: string }[] }).items.map((i) =>
    i.name
  );

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('list_households names every household with members and the default', () =>
  withPeter(async ({ peter, ids }) => {
    const r = await call(oauth(peter, ids.Zuhause ?? ''), open, 'list_households');
    assertEquals(r.isError, undefined);
    assertEquals(JSON.parse(r.content[0]?.text ?? '[]'), [
      { id: ids.Zuhause, name: 'Zuhause', members: 1, default: true },
      { id: ids.Sommerfest, name: 'Sommerfest', members: 2, default: false },
    ]);
  }));

test('household picks the list by name in any case or id; without it the default', () =>
  withPeter(async ({ peter, ids }) => {
    const auth = oauth(peter, ids.Zuhause ?? '');
    assertEquals(items(await call(auth, open, 'list_items')), ['Milch']);
    assertEquals(items(await call(auth, open, 'list_items', { household: 'Sommerfest' })), [
      'Bratwurst',
    ]);
    assertEquals(items(await call(auth, open, 'list_items', { household: ids.Sommerfest })), [
      'Bratwurst',
    ]);
    for (const household of ['sommerfest', ' SOMMERFEST ']) {
      assertEquals(items(await call(auth, open, 'list_items', { household })), ['Bratwurst']);
    }
    const added = await call(auth, open, 'add_items', {
      items: [{ name: 'Senf' }],
      household: 'Sommerfest',
    });
    assertEquals(added.isError, undefined);
    assertEquals(
      items(await call(auth, open, 'list_items', { household: 'Sommerfest' })).sort(),
      ['Bratwurst', 'Senf'],
    );
    assertEquals(items(await call(auth, open, 'list_items')), ['Milch'], 'the default untouched');
  }));

test('a household the user is not in, or a loose name, is a tool error naming theirs', () =>
  withPeter(async ({ peter, ids }) => {
    const auth = oauth(peter, ids.Zuhause ?? '');
    for (const household of ['Bei Lea', ids['Bei Lea'] ?? '', 'Sommer']) {
      const r = await call(auth, open, 'list_stores', { household });
      assertEquals(r.isError, true, household);
      assertEquals(
        r.content[0]?.text,
        `Kein Haushalt "${household}". Deine Haushalte: Zuhause, Sommerfest`,
      );
    }
  }));

test('a personal access token stays in the household it was made in', () =>
  withPeter(async ({ peter, ids }) => {
    const auth: Auth = {
      userId: peter,
      householdId: ids.Sommerfest ?? '',
      via: 'pat',
      scopes: ['read', 'write'] as const,
    };
    const listed = await call(auth, open, 'list_households');
    assertEquals(JSON.parse(listed.content[0]?.text ?? '[]'), [
      { id: ids.Sommerfest, name: 'Sommerfest', members: 2, default: true },
    ]);
    assertEquals(items(await call(auth, open, 'list_items')), ['Bratwurst']);
    const r = await call(auth, open, 'list_items', { household: 'Zuhause' });
    assertEquals(r.isError, true);
    assertEquals(r.content[0]?.text, 'Dieser Zugriffstoken gilt nur für den Haushalt Sommerfest.');
  }));

test('list_households answers with a locked default, so an unlocked household can be found', () =>
  withPeter(async ({ peter, ids }) => {
    const locked: Gate = () => Promise.resolve('locked');
    const r = await call(oauth(peter, ids.Zuhause ?? ''), locked, 'list_households');
    assertEquals(r.isError, undefined);
    assertEquals(
      (JSON.parse(r.content[0]?.text ?? '[]') as { name: string }[]).map((h) => h.name),
      ['Zuhause', 'Sommerfest'],
    );
  }));

test('the premium gate asks about the household the call acts in', () =>
  withPeter(async ({ peter, ids }) => {
    const asked: string[] = [];
    const onlySommerfest: Gate = (household) => {
      asked.push(household);
      return Promise.resolve(household === ids.Sommerfest ? 'open' : 'locked');
    };
    const auth = oauth(peter, ids.Zuhause ?? '');
    const locked = await call(auth, onlySommerfest, 'list_items');
    assertEquals([locked.isError, locked.content[0]?.text], [true, premiumRequired.de]);
    const unlocked = await call(auth, onlySommerfest, 'list_items', { household: 'Sommerfest' });
    assert(!unlocked.isError);
    assertEquals(asked, [ids.Zuhause, ids.Sommerfest]);
  }));

// Job 169b W3: several lists per household.
const text = (r: Result) => JSON.parse(r.content[0]?.text ?? '{}');

test('list_lists names the lists; "list" picks one, the default list (none chosen: the first) without it', () =>
  withPeter(async ({ peter, ids }) => {
    const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    try {
      await sql`insert into public.lists (household_id, name, position) values
        (${ids.Sommerfest ?? ''}, 'Getränke', 1), (${ids['Bei Lea'] ?? ''}, 'Leas Liste', 1)`;
    } finally {
      await sql.end();
    }
    const auth = oauth(peter, ids.Zuhause ?? '');
    const lists = await call(auth, open, 'list_lists', { household: 'Sommerfest' });
    assertEquals(
      text(lists).map((l: { name: string; default: boolean }) => [l.name, l.default]),
      [['Einkaufsliste', true], ['Getränke', false]],
    );

    const added = await call(auth, open, 'add_items', {
      household: 'Sommerfest',
      list: 'getränke',
      items: [{ name: 'Bratwurst' }, { name: 'Apfelschorle' }],
    });
    const { added: fresh, alreadyOnList } = text(added);
    assertEquals(
      fresh.map((i: { name: string }) => i.name),
      ['Bratwurst', 'Apfelschorle'],
      'Bratwurst is open on the default list, not on Getränke: added there',
    );
    assertEquals(alreadyOnList, []);
    const getraenke = text(lists).find((l: { name: string }) => l.name === 'Getränke').id;
    assert(fresh.every((i: { listId: string }) => i.listId === getraenke), 'items carry listId');

    assertEquals(items(await call(auth, open, 'list_items', { household: 'Sommerfest' })), [
      'Bratwurst',
    ]);
    const drinks = await call(auth, open, 'list_items', {
      household: 'Sommerfest',
      list: getraenke,
    });
    assertEquals(text(drinks).list, 'Getränke');
    assertEquals(items(drinks).sort(), ['Apfelschorle', 'Bratwurst']);
    assertEquals(text(drinks).counts, { open: 2, checkedLast24h: 0 }, "counts are the list's");

    const ticked = await call(auth, open, 'tick_items', {
      household: 'Sommerfest',
      list: 'Getränke',
      items: ['Bratwurst'],
    });
    assertEquals(text(ticked).ticked.map((i: { listId: string }) => i.listId), [getraenke]);
    assertEquals(
      items(await call(auth, open, 'list_items', { household: 'Sommerfest' })),
      ['Bratwurst'],
      "ticking on Getränke leaves the default list's Bratwurst open",
    );

    // An id from list_items with "list" works without it; a name means the default list.
    const schorle = text(drinks).items.find((i: { name: string }) => i.name === 'Apfelschorle').id;
    const byName = await call(auth, open, 'tick_items', {
      household: 'Sommerfest',
      items: ['Apfelschorle'],
    });
    assertEquals(text(byName).ticked, [], 'Apfelschorle is not on the default list');
    const moved = await call(auth, open, 'move_item', {
      household: 'Sommerfest',
      item: schorle,
      category: 'Getränke',
    });
    assert(!moved.isError, moved.content[0]?.text);
    assertEquals([text(moved).id, text(moved).category], [schorle, 'Getränke']);
    const byId = await call(auth, open, 'tick_items', {
      household: 'Sommerfest',
      items: [schorle],
    });
    assertEquals(text(byId).ticked.map((i: { id: string }) => i.id), [schorle]);
    assertEquals(text(byId).notFound, []);
    const sommerfestBratwurst =
      text(await call(auth, open, 'list_items', { household: 'Sommerfest' }))
        .items[0].id;
    const elsewhere = await call(auth, open, 'tick_items', {
      household: 'Zuhause',
      items: [sommerfestBratwurst],
    });
    assertEquals(text(elsewhere).ticked, [], "another household's item id is not found");

    const foreign = await call(auth, open, 'list_items', {
      household: 'Sommerfest',
      list: 'Leas Liste',
    });
    assertEquals(foreign.isError, true, "another household's list is not found");
    assert(
      foreign.content[0]?.text.includes('Einkaufsliste, Getränke'),
      'the error names the lists',
    );
  }));
