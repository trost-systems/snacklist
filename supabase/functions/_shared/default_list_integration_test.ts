// Job 207: where an add without a named list goes (public.default_list: the member's choice, else
// the first list), and where a spoken list name sends it, through the production wiring of the
// voice function, the MCP tools and the API against the local stack. Runs with FG_DB_TEST=1 and
// SUPABASE_DB_URL (db gate); skipped without them.
import { assert, assertEquals, assertExists } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import postgres from 'postgres';
import type { Auth } from './auth.ts';
import { asUser, databaseUrl } from './db.ts';
import type { Access } from './premium.ts';
import { telemetryFor } from './telemetry.ts';
import { handle as apiHandle } from '../api/handler.ts';
import { buildServer } from '../mcp/tools.ts';
import { createHandler as voiceHandler } from '../voice/handler.ts';
import { productionDeps as voiceDeps } from '../voice/deps.ts';
import { productionDeps as alexaDeps } from '../alexa/deps.ts';
import { createHandler as alexaHandler } from '../alexa/handler.ts';
import type { Envelope } from '../alexa/verify.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Home = {
  sql: postgres.Sql;
  userId: string;
  householdId: string;
  /** List ids by name: Einkaufsliste (first, seeded), Alltag, Geburtstag. */
  lists: Record<'Einkaufsliste' | 'Alltag' | 'Geburtstag', string>;
};

/** Peter's household with the seeded list first, then Alltag and Geburtstag; no default chosen. */
async function withHome(work: (home: Home) => Promise<void>) {
  const sql = postgres(databaseUrl(), { max: 2, prepare: false, onnotice: () => {} });
  const userId = crypto.randomUUID();
  const log = console.log;
  console.log = () => {};
  try {
    await sql`insert into auth.users (id, email) values (${userId}, ${`${userId}@fg-test.invalid`})`;
    const householdId = await asUser(userId, async (tx) => {
      const [row] = await tx<{ id: string }[]>`
        select id from public.create_household(p_name => '207', p_default_stores => false)`;
      assertExists(row);
      return row.id;
    });
    await sql`insert into public.lists (household_id, name, position) values
      (${householdId}, 'Alltag', 1), (${householdId}, 'Geburtstag', 2)`;
    const rows = await sql<{ id: string; name: string }[]>`
      select id, name from public.lists where household_id = ${householdId} order by position`;
    const id = (name: string) => rows.find((r) => r.name === name)?.id ?? '';
    assertEquals(rows.map((r) => r.name), ['Einkaufsliste', 'Alltag', 'Geburtstag']);
    await work({
      sql,
      userId,
      householdId,
      lists: {
        Einkaufsliste: id('Einkaufsliste'),
        Alltag: id('Alltag'),
        Geburtstag: id('Geburtstag'),
      },
    });
  } finally {
    console.log = log;
    await sql`delete from public.households where created_by = ${userId}`;
    await sql`delete from auth.users where id = ${userId}`;
    await sql.end();
  }
}

/** Where each open item is, by list id. */
const placed = async ({ sql, householdId }: Home) =>
  Object.fromEntries(
    (await sql<{ name: string; list_id: string }[]>`
      select name, list_id from public.items where household_id = ${householdId} and status = 'active'`)
      .map((r) => [r.name, r.list_id]),
  );

const setDefault = (home: Home, list: string) =>
  asUser(home.userId, (tx) => tx`select public.set_default_list(${list})`);

/** POST /voice as native Siri, through productionDeps. */
async function say(home: Home, body: Record<string, unknown>) {
  const auth: Auth = { userId: home.userId, householdId: home.householdId, via: 'siri' };
  const handle = voiceHandler(
    voiceDeps(telemetryFor('voice', { get: () => undefined }), () => Promise.resolve(auth)),
  );
  const res = await handle(
    new Request('http://local/voice', {
      method: 'POST',
      headers: { authorization: 'Bearer test', 'content-type': 'application/json' },
      body: JSON.stringify({ lang: 'de', ...body }),
    }),
  );
  assertEquals(res.status, 200);
  return await res.json() as { speech: string; list: { id: string; name: string } };
}

/** An AddToListIntent or AddItemIntent as Alexa sends it, through the production deps. */
async function alexa(home: Home, intent: string, slots: Record<string, string>) {
  const handle = alexaHandler(alexaDeps(
    telemetryFor('alexa', { get: () => undefined }),
    (_headers, body) => Promise.resolve(JSON.parse(new TextDecoder().decode(body)) as Envelope),
    () =>
      Promise.resolve({
        userId: home.userId,
        householdId: home.householdId,
        sessionId: crypto.randomUUID(),
      }),
  ));
  const res = await handle(
    new Request('http://local/alexa', {
      method: 'POST',
      body: JSON.stringify({
        version: '1.0',
        context: { System: { application: { applicationId: 'test' }, user: { accessToken: 't' } } },
        request: {
          type: 'IntentRequest',
          timestamp: new Date().toISOString(),
          locale: 'de-DE',
          intent: {
            name: intent,
            slots: Object.fromEntries(
              Object.entries(slots).map(([name, value]) => [name, { name, value }]),
            ),
          },
        },
      }),
    }),
  );
  assertEquals(res.status, 200);
  return ((await res.json()) as { response: { outputSpeech: { text: string } } }).response
    .outputSpeech.text;
}

const test = (name: string, fn: () => Promise<void>) =>
  Deno.test({ name, ignore: !enabled, sanitizeResources: false, sanitizeOps: false, fn });

test('voice without a list: the first list while none is chosen, then the chosen one', () =>
  withHome(async (home) => {
    const first = await say(home, { text: 'Milch' });
    assertEquals(first.speech, 'Hinzugefügt zur Einkaufsliste: Milch.');
    assertEquals(first.list, { id: home.lists.Einkaufsliste, name: 'Einkaufsliste' });
    await setDefault(home, home.lists.Alltag);
    const chosen = await say(home, { text: 'Eier' });
    assertEquals(chosen.speech, 'Hinzugefügt zur Liste Alltag: Eier.');
    assertEquals(await placed(home), { Milch: home.lists.Einkaufsliste, Eier: home.lists.Alltag });
  }));

test('review 0: a list called Einkaufsliste is found by its name, also when Geburtstag is the default', () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Geburtstag);
    const answer = await say(home, { text: 'Servietten zur Einkaufsliste' });
    assertEquals(answer.speech, 'Hinzugefügt zur Einkaufsliste: Servietten.');
    const siriKit = await say(home, { text: 'Teller', list: 'Einkaufsliste' });
    assertEquals(siriKit.speech, 'Hinzugefügt zur Einkaufsliste: Teller.');
    // Alexa's AddItemIntent sample "füg {items} zur einkaufsliste hinzu" sends the items only: the
    // default list, and the answer names it.
    assertEquals(
      await alexa(home, 'AddItemIntent', { items: 'Gabeln' }),
      'Ich habe Gabeln auf die Liste Geburtstag gesetzt.',
    );
    assertEquals(await placed(home), {
      Servietten: home.lists.Einkaufsliste,
      Teller: home.lists.Einkaufsliste,
      Gabeln: home.lists.Geburtstag,
    });
  }));

test("Peter's sentence lands on Geburtstag as Luftballons", () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Alltag);
    const answer = await say(home, { text: 'Luftballons zur Geburtstag Liste' });
    assertEquals(answer.speech, 'Hinzugefügt zur Liste Geburtstag: Luftballons.');
    assertEquals(answer.list, { id: home.lists.Geburtstag, name: 'Geburtstag' });
    assertEquals(await placed(home), { Luftballons: home.lists.Geburtstag });
  }));

test('the default list deleted: the next add goes to the first list, no error', () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Alltag);
    await asUser(home.userId, (tx) => tx`select public.delete_list(${home.lists.Alltag})`);
    const answer = await say(home, { text: 'Brot' });
    assertEquals(answer.speech, 'Hinzugefügt zur Einkaufsliste: Brot.');
    assertEquals(await placed(home), { Brot: home.lists.Einkaufsliste });
    // Siri's yes to Q79 resending the deleted list's id: the default list, and it says so.
    const stale = await say(home, { text: 'Käse', list: home.lists.Alltag });
    assertEquals(
      stale.speech,
      'Diese Liste gibt es nicht mehr. Hinzugefügt zur Einkaufsliste: Käse.',
    );
  }));

test('an unknown name lands on the default list and the speech says so', () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Alltag);
    const answer = await say(home, { text: 'Luftballons zur Weihnachten Liste' });
    assertEquals(
      answer.speech,
      'Eine Liste „Weihnachten“ habe ich nicht gefunden. Hinzugefügt zur Liste Alltag: Luftballons.',
    );
    assertEquals(await placed(home), { Luftballons: home.lists.Alltag });
  }));

/** One MCP tools/call through the SDK's HTTP handler, as a client sees it. */
async function mcp(home: Home, args: Record<string, unknown>) {
  const auth: Auth = {
    userId: home.userId,
    householdId: home.householdId,
    via: 'oauth',
    clientId: 'c',
    sessionId: crypto.randomUUID(),
  };
  const open = () => Promise.resolve<Access>('open');
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
        params: { name: 'add_items', arguments: args },
      }),
    }),
  );
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  const result = JSON.parse(data ? data.slice(6) : text).result as {
    isError?: boolean;
    content: { text: string }[];
  };
  assert(!result.isError, result.content[0]?.text);
}

test('MCP add_items: the default list without "list", the named one with an id or a name', () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Alltag);
    await mcp(home, { items: [{ name: 'Milch' }] });
    await mcp(home, { items: [{ name: 'Kerzen' }], list: home.lists.Geburtstag });
    await mcp(home, { items: [{ name: 'Nudeln' }], list: 'Einkaufsliste' });
    assertEquals(await placed(home), {
      Milch: home.lists.Alltag,
      Kerzen: home.lists.Geburtstag,
      Nudeln: home.lists.Einkaufsliste,
    });
  }));

test('API POST /items without a list: the default list', () =>
  withHome(async (home) => {
    const { sql } = home;
    const switches = await sql<{ key: string; enabled: boolean }[]>`
      select key, enabled from public.app_switches where key in ('integration_lock', 'public_api')`;
    try {
      await sql`update public.app_switches set enabled = false where key = 'integration_lock'`;
      await sql`update public.app_switches set enabled = true where key = 'public_api'`;
      await setDefault(home, home.lists.Alltag);
      const claims = JSON.stringify({
        sub: home.userId,
        role: 'authenticated',
        session_id: crypto.randomUUID(),
      });
      const key = await sql.begin(async (tx) => {
        await tx`select set_config('role', 'authenticated', true),
                        set_config('request.jwt.claims', ${claims}, true)`;
        const [row] = await tx<{ token: string }[]>`
          select token from public.create_api_token('test', ${['read', 'write']})`;
        return row;
      }) as { token: string };
      const res = await apiHandle(
        new Request('http://localhost/api/v1/items', {
          method: 'POST',
          headers: { authorization: `Bearer ${key.token}`, 'content-type': 'application/json' },
          body: JSON.stringify({ items: [{ name: 'Zahnpasta' }] }),
        }),
      );
      assertEquals(res.status, 201);
      assertEquals(await placed(home), { Zahnpasta: home.lists.Alltag });
    } finally {
      for (const { key, enabled } of switches) {
        await sql`update public.app_switches set enabled = ${enabled} where key = ${key}`;
      }
    }
  }));

test("Alexa: Peter's sentence with the list slot, the same swallowed into the items, and none", () =>
  withHome(async (home) => {
    await setDefault(home, home.lists.Alltag);
    assertEquals(
      await alexa(home, 'AddToListIntent', { itemphrase: 'Luftballons', list: 'Geburtstag Liste' }),
      'Ich habe Luftballons auf die Liste Geburtstag gesetzt.',
    );
    assertEquals(
      await alexa(home, 'AddItemIntent', { items: 'Kerzen zur Geburtstag Liste' }),
      'Ich habe Kerzen auf die Liste Geburtstag gesetzt.',
    );
    assertEquals(
      await alexa(home, 'AddToListIntent', { itemphrase: 'Konfetti', list: 'Party' }),
      'Eine Liste „Party“ habe ich nicht gefunden. Ich habe Konfetti auf die Liste Alltag gesetzt.',
    );
    assertEquals(
      await alexa(home, 'AddItemIntent', { items: 'Milch' }),
      'Ich habe Milch auf die Liste Alltag gesetzt.',
    );
    assertEquals(await placed(home), {
      Luftballons: home.lists.Geburtstag,
      Kerzen: home.lists.Geburtstag,
      Konfetti: home.lists.Alltag,
      Milch: home.lists.Alltag,
    });
  }));
