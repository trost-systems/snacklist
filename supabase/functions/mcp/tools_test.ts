// Job 50: the integration lock on the MCP tools, through the SDK's streamable HTTP handler as a
// client sees it. Locked: initialize and tools/list work, every tool call is an isError result with
// HTTP 200 and touches no data; a failing check is no premium answer.
import { assert, assertEquals, assertFalse } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import type { Auth } from '../_shared/auth.ts';
import { OutOfTime } from '../_shared/db.ts';
import type { Access } from '../_shared/premium.ts';
import { mcpTools, telemetryFor, withTelemetry } from '../_shared/telemetry.ts';
import {
  buildServer,
  busyNow,
  type CallReason,
  failedNow,
  type Gate,
  langOf,
  planInfoUrl,
  premiumRequired,
  type ReportCall,
  reportToolCalls,
  SWITCHED_OFF,
  type Switches,
  tookTooLong,
  toolAnnotations,
  toolScopes,
  writeScopeRequired,
} from './tools.ts';

const auth: Auth = {
  userId: 'u',
  householdId: 'h',
  via: 'pat',
  scopes: ['read', 'write'] as const,
};

const rpc = (
  method: string,
  params: Record<string, unknown> = {},
  lang: string | undefined = undefined,
) =>
  new Request('http://edge/mcp', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
      'mcp-protocol-version': '2025-11-25',
      ...(lang ? { 'accept-language': lang } : {}),
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });

/** The JSON-RPC message of a JSON or SSE answer. */
interface Message {
  result: {
    serverInfo: { name: string; version: string };
    tools: {
      name: string;
      title?: string;
      inputSchema: { properties?: Record<string, unknown> };
      annotations?: Record<string, boolean>;
    }[];
    isError?: boolean;
    content: { type: string; text: string }[];
    structuredContent?: unknown;
  };
  error?: unknown;
}

async function message(res: Response): Promise<Message> {
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  return JSON.parse(data ? data.slice(6) : text);
}

function serve(gate: Gate, lang?: string, switches: Switches = SWITCHED_OFF, caller: Auth = auth) {
  const asked: string[] = [];
  const counted: Gate = (household) => {
    asked.push(household);
    return gate(household);
  };
  const reports: { tool: string; household: string; reason: CallReason }[] = [];
  const report: ReportCall = (call) => {
    reports.push(call);
    return Promise.resolve();
  };
  const handle = (req: Request) =>
    createMcpHandler(() =>
      buildServer(caller, counted, report, langOf(req.headers.get('accept-language')), switches)
    ).fetch(req);
  return { handle, asked: () => asked.length, households: () => asked, reports, lang };
}

const locked: Gate = () => Promise.resolve<Access>('locked');

/** The tools behind the lock; list_households only lists the user's own households. */
const calls: [string, Record<string, unknown>][] = [
  ['list_lists', {}],
  ['list_items', {}],
  ['add_items', { items: [{ name: 'Milch' }] }],
  ['tick_items', { items: ['Milch'] }],
  ['move_item', { item: 'Milch', store: 'dm' }],
  ['update_item', { item: 'Milch', quantity: null }],
  ['remove_items', { items: ['Milch'] }],
  ['untick_items', { items: ['Milch'] }],
  ['get_item', { item: 'Milch' }],
  ['merge_items', { keep: 'Möhren', merge: 'Karotten' }],
  ['place_item', { item: 'Eier', after: 'Mehl' }],
  ['set_store_order', { store: 'Rewe', items: ['Mehl', 'Eier'] }],
  ['list_categories', {}],
  ['list_stores', {}],
  ['list_recent', {}],
  ['suggest_items', { prefix: 'Mi' }],
];

/** The tools behind app_switches.mcp_lists_stores (job 345), served only while it is on. */
const switched: [string, Record<string, unknown>][] = [
  ['create_list', { name: 'Baumarkt' }],
  ['rename_list', { list: 'Einkaufsliste', name: 'Wocheneinkauf' }],
  ['add_store', { name: 'Rewe' }],
  ['rename_store', { store: 'dm', name: 'dm Drogerie' }],
  ['set_store_layout', { store: 'dm', categories: ['Drogerie'] }],
];

const ON: Switches = { listsStores: true };

Deno.test('locked: initialize and tools/list answer without asking the gate', async () => {
  const s = serve(locked);
  const init = await s.handle(rpc('initialize', {
    protocolVersion: '2025-11-25',
    capabilities: {},
    clientInfo: { name: 'test', version: '1' },
  }));
  assertEquals(init.status, 200);
  const { serverInfo } = (await message(init)).result;
  assertEquals(serverInfo.name, 'snacklist');
  assertEquals(serverInfo.version, '1.4.0', 'annotations changed since 1.3.0');
  const list = await s.handle(rpc('tools/list'));
  assertEquals(list.status, 200);
  assertEquals(
    (await message(list)).result.tools.map((t) => t.name).sort(),
    ['list_households', ...calls.map(([name]) => name)].sort(),
  );
  assertEquals(s.asked(), 0);
});

Deno.test('locked: every tool call is an isError result with HTTP 200, data untouched', async () => {
  for (const [name, args] of [...calls, ...switched]) {
    const s = serve(locked, undefined, ON);
    // The database is never reached: asUser would fail here without SUPABASE_DB_URL.
    const res = await s.handle(rpc('tools/call', { name, arguments: args }));
    assertEquals(res.status, 200, name);
    const { result, error } = await message(res);
    assertEquals(error, undefined, `${name}: a tool result, not a JSON-RPC error`);
    assertEquals(result.isError, true, name);
    assertEquals(result.content, [{ type: 'text', text: premiumRequired.de }], name);
    assertEquals(result.structuredContent, {
      error: 'premium_required',
      details: { integration: 'mcp', info: planInfoUrl.de },
    }, name);
    assertEquals(s.asked(), 1, name);
    assertEquals(s.households(), ['h'], `${name}: without "household" the credential's household`);
    assertEquals(s.reports, [{ tool: name, household: 'h', reason: 'premium_required' }], name);
  }
});

Deno.test('job 345: with mcp_lists_stores on, the list and store tools are listed too', async () => {
  const s = serve(locked, undefined, ON);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  assertEquals(
    tools.map((t) => t.name).sort(),
    ['list_households', ...calls.map(([name]) => name), ...switched.map(([name]) => name)].sort(),
  );
});

Deno.test('job 345: with mcp_lists_stores off, a list or store write is no tool and runs nothing', async () => {
  for (const [name, args] of switched) {
    const s = serve(locked);
    const { result, error } = await message(
      await s.handle(rpc('tools/call', { name, arguments: args })),
    );
    const text = JSON.stringify(result ?? error);
    assert(text.includes(name) && /not found|unknown/i.test(text), `${name}: ${text}`);
    assertEquals(s.asked(), 0, `${name}: the gate is not asked`);
    assertEquals(s.reports, [], `${name}: no tool call to report`);
  }
});

Deno.test('job 195: mcp_tool_call can name every tool the server lists, no other', async () => {
  const s = serve(locked, undefined, ON);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  assertEquals(tools.map((t) => t.name).sort(), [...mcpTools].sort());
  assertEquals(s.reports, [], 'tools/list is no tool call');
});

Deno.test('N-147: a tool call sends no mcp_tool_call while capture is off', async () => {
  const sent: string[] = [];
  const fetchImpl = (_url: string | URL | Request, init?: RequestInit) => {
    sent.push(...JSON.parse(String(init?.body)).batch.map((e: { event: string }) => e.event));
    return Promise.resolve(new Response('{}'));
  };
  const telemetry = telemetryFor(
    'mcp',
    {
      get: (k) =>
        ({
          POSTHOG_PROJECT_API_KEY: 'phc_testprojectkey0123456789',
          POSTHOG_HOST: 'https://eu.i.posthog.com',
        })[k],
    },
    fetchImpl as typeof fetch,
  );
  const consenting = (
    _u: string,
    _household: string,
    event: string,
    properties: Record<string, unknown>,
  ) => {
    telemetry.event(event, {
      installId: '0b6f7a52-6c1e-4f4e-9d55-3f1f0c2a9e01',
      householdId: '7d1e4f0a-2b3c-4d5e-8f90-a1b2c3d4e5f6',
    }, properties);
    return Promise.resolve();
  };
  const slowLock: Gate = () => new Promise((r) => setTimeout(() => r('locked'), 50));
  const serve = withTelemetry(
    'mcp',
    (req) =>
      createMcpHandler(() => buildServer(auth, slowLock, reportToolCalls(consenting, 'u'))).fetch(
        req,
      ),
    telemetry,
  );
  const res = await serve(rpc('tools/call', { name: 'list_items', arguments: {} }));
  assertEquals((await message(res)).result.isError, true);
  assertEquals(sent, [], 'N-147: mcp_tool_call capture is off');
});

Deno.test('job 169b: list_households does not ask the gate', async () => {
  const s = serve(locked);
  // Without SUPABASE_DB_URL the database read fails; the gate must not have been asked first.
  const res = await s.handle(rpc('tools/call', { name: 'list_households', arguments: {} }));
  assertFalse(JSON.stringify(await message(res)).includes('Premium'));
  assertEquals(s.asked(), 0);
});

Deno.test('job 169b: every list tool takes an optional household, list_households none', async () => {
  const s = serve(locked);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  for (const tool of tools) {
    const takes = Object.keys(tool.inputSchema.properties ?? {}).includes('household');
    assertEquals(takes, tool.name !== 'list_households', tool.name);
  }
});

Deno.test('job 169b W3: the item tools take an optional list', async () => {
  const s = serve(locked);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  const takes = tools.filter((t) => Object.keys(t.inputSchema.properties ?? {}).includes('list'));
  assertEquals(
    takes.map((t) => t.name).sort(),
    [
      'add_items',
      'get_item',
      'list_items',
      'list_recent',
      'merge_items',
      'move_item',
      'place_item',
      'remove_items',
      'set_store_order',
      'tick_items',
      'untick_items',
      'update_item',
    ],
  );
});

Deno.test('job 415: every tool declares all four hints, as toolAnnotations says', async () => {
  const s = serve(locked, undefined, ON);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  assertEquals(tools.length, Object.keys(toolAnnotations).length);
  for (const tool of tools) {
    const want = toolAnnotations[tool.name as keyof typeof toolAnnotations];
    assertEquals(tool.annotations, want, tool.name);
    assertEquals(typeof tool.title, 'string', `${tool.name}: title`);
  }
});

Deno.test('job 415: the hints are honest for the tools a review looks at', async () => {
  const s = serve(locked, undefined, ON);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  const hints = Object.fromEntries(tools.map((t) => [t.name, t.annotations]));
  const write = { readOnlyHint: false, openWorldHint: false };
  assertEquals(hints.add_items, { ...write, destructiveHint: false, idempotentHint: false });
  assertEquals(hints.move_item, { ...write, destructiveHint: false, idempotentHint: true });
  assertEquals(hints.tick_items, { ...write, destructiveHint: false, idempotentHint: true });
  assertEquals(hints.update_item, { ...write, destructiveHint: true, idempotentHint: true });
  assertEquals(hints.remove_items, { ...write, destructiveHint: true, idempotentHint: true });
  assertEquals(hints.merge_items, { ...write, destructiveHint: true, idempotentHint: false });
  assertEquals(hints.get_item, {
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  });
});

Deno.test('job 344: update_item takes the fields to change and the list to move to', async () => {
  const s = serve(locked);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  const update = tools.find((t) => t.name === 'update_item');
  assertEquals(Object.keys(update?.inputSchema.properties ?? {}).sort(), [
    'brand',
    'category',
    'household',
    'item',
    'list',
    'name',
    'properties',
    'quantity',
    'store',
    'toList',
  ]);
});

Deno.test('locked: English for a client that prefers it', async () => {
  const s = serve(locked);
  const res = await s.handle(
    rpc('tools/call', { name: 'list_items', arguments: {} }, 'en-US,en;q=0.9,de;q=0.5'),
  );
  assertEquals((await message(res)).result.content[0]?.text, premiumRequired.en);
  for (const lang of ['de', 'en'] as const) {
    const text = premiumRequired[lang];
    assert(text.includes(planInfoUrl[lang]), `${lang}: links the info page`);
    assertFalse(
      /premium|€|eur|preis|price|kauf|buy|upgrade|freischalt|unlock|abo|subscri/i.test(text),
      `${lang}: neutral, no price or call to action: ${text}`,
    );
  }
});

Deno.test('the check fails: no premium answer (an error, like any database failure)', async () => {
  const s = serve(() => Promise.reject(new Error('connection refused')));
  const res = await s.handle(rpc('tools/call', { name: 'list_items', arguments: {} }));
  const { result } = await message(res);
  assertEquals(result.isError, true);
  assertEquals(result.content[0]?.text, failedNow.de);
  assertEquals(s.reports, [{ tool: 'list_items', household: 'h', reason: 'server' }]);
});

Deno.test("a failure's own message never reaches the client", async () => {
  const internal = Object.assign(new Error('invalid byte sequence for encoding "UTF8": 0x00'), {
    name: 'PostgresError',
    code: '22021',
  });
  const s = serve(() => Promise.reject(internal));
  const res = await s.handle(
    rpc('tools/call', { name: 'list_items', arguments: {} }, 'en-US,en;q=0.9'),
  );
  const text = JSON.stringify(await message(res));
  assertFalse(text.includes('UTF8'));
  assert(text.includes(failedNow.en));
});

Deno.test('U+0000 in any text argument is refused before the database sees it', async () => {
  const s = serve(locked);
  for (
    const [name, args] of [
      ['add_items', { items: [{ name: 'Milch\u0000' }] }],
      ['add_items', { items: [{ name: 'Milch', brand: 'Ja\u0000' }] }],
      ['list_items', { store: 'dm\u0000' }],
      ['tick_items', { items: ['Milch\u0000'] }],
      ['place_item', { item: 'Eier', before: 'Mehl\u0000' }],
      ['set_store_order', { store: 'Rewe', items: ['Mehl', 'Ei\u0000er'] }],
      ['list_lists', { household: 'Zuhause\u0000' }],
    ] as const
  ) {
    const { result } = await message(await s.handle(rpc('tools/call', { name, arguments: args })));
    assertEquals(result.isError, true, name);
    assert(result.content[0]?.text.includes('U+0000'), `${name}: ${result.content[0]?.text}`);
  }
  assertEquals(s.reports, []);
});

Deno.test('a call that ran out of its time is a tool error saying so, not a server failure', async () => {
  const cancelled = Object.assign(new Error('cancelled'), { name: 'PostgresError', code: '57014' });
  for (
    const [thrown, lang, text] of [
      [new OutOfTime(), undefined, tookTooLong.de],
      [cancelled, 'en', tookTooLong.en],
    ] as const
  ) {
    const s = serve(() => Promise.reject(thrown));
    const res = await s.handle(rpc('tools/call', {
      name: 'add_items',
      arguments: {
        items: [{ name: 'Milch' }],
      },
    }, lang));
    assertEquals(res.status, 200);
    const { result, error } = await message(res);
    assertEquals(error, undefined, 'a tool result, not a JSON-RPC error');
    assertEquals(result.isError, true);
    assertEquals(result.content, [{ type: 'text', text }]);
    assertEquals(s.reports, [{ tool: 'add_items', household: 'h', reason: 'tool_error' }]);
  }
});

Deno.test('a call that met a household being changed is a tool error saying so', async () => {
  const busy = Object.assign(new Error('could not obtain lock on row in relation "households"'), {
    name: 'PostgresError',
    code: '55P03',
  });
  for (const [lang, text] of [[undefined, busyNow.de], ['en', busyNow.en]] as const) {
    const s = serve(() => Promise.reject(busy));
    const res = await s.handle(rpc('tools/call', { name: 'list_items', arguments: {} }, lang));
    assertEquals(res.status, 200);
    const { result, error } = await message(res);
    assertEquals(error, undefined, 'a tool result, not a JSON-RPC error');
    assertEquals(result.isError, true);
    assertEquals(result.content, [{ type: 'text', text }], 'no text from the database');
    assertEquals(s.reports, [{ tool: 'list_items', household: 'h', reason: 'tool_error' }]);
  }
});

Deno.test('langOf: English only when preferred over German', () => {
  assertEquals(langOf(null), 'de');
  assertEquals(langOf(''), 'de');
  assertEquals(langOf('en'), 'en');
  assertEquals(langOf('en-GB'), 'en');
  assertEquals(langOf('de-DE,en;q=0.8'), 'de');
  assertEquals(langOf('fr,en;q=0.5'), 'en');
  assertEquals(langOf('de;q=0.4,en;q=0.9'), 'en');
  assertEquals(langOf('fr'), 'de');
  assertEquals(langOf('en;q=0'), 'de');
});

const readOnly: Auth = { userId: 'u', householdId: 'h', via: 'pat', scopes: ['read'] as const };

const legalWriteScopeText = {
  de:
    'Dieser Zugriffsschlüssel darf nur lesen. Erstelle in der Snacklist-App unter Mehr › Zugänge einen Schlüssel zum Lesen und Schreiben. Es wurde nichts geändert.',
  en:
    'This access key can only read. Create a key that can read and write in the Snacklist app under More › Access. Nothing was changed.',
} as const;

Deno.test('job 397: a read-only key gets a tool error saying it can only read, data untouched', async () => {
  for (const lang of ['de', 'en'] as const) {
    for (const [name, args] of [...calls, ...switched]) {
      if (toolScopes[name as keyof typeof toolScopes] !== 'write') continue;
      const s = serve(locked, lang, ON, readOnly);
      const res = await s.handle(rpc('tools/call', { name, arguments: args }, lang));
      assertEquals(res.status, 200, name);
      const { result, error } = await message(res);
      assertEquals(error, undefined, `${name}: a tool result, not a JSON-RPC error`);
      assertEquals(result.isError, true, name);
      assertEquals(result.content, [{ type: 'text', text: writeScopeRequired[lang] }], name);
      assertEquals(writeScopeRequired[lang], legalWriteScopeText[lang], 'Legal N-410 wording');
      assertEquals(result.structuredContent, {
        error: 'insufficient_scope',
        details: { required: 'write' },
      }, name);
      assertEquals(s.asked(), 0, `${name}: refused before the Premium check`);
      assertEquals(s.reports, [{ tool: name, household: 'h', reason: 'tool_error' }], name);
    }
  }
});

Deno.test('job 397: a read-only key reaches every read tool', async () => {
  for (const [name, args] of calls) {
    if (toolScopes[name as keyof typeof toolScopes] !== 'read') continue;
    const s = serve(locked, undefined, ON, readOnly);
    const { result } = await message(await s.handle(rpc('tools/call', { name, arguments: args })));
    assertEquals(result.structuredContent, {
      error: 'premium_required',
      details: { integration: 'mcp', info: planInfoUrl.de },
    }, `${name}: past the scope check, at the gate`);
  }
});

Deno.test('job 397: a tool needs read exactly when it is marked read-only', async () => {
  const s = serve(locked, undefined, ON);
  const { tools } = (await message(await s.handle(rpc('tools/list')))).result;
  for (const tool of tools) {
    assertEquals(
      toolScopes[tool.name as keyof typeof toolScopes],
      tool.annotations?.readOnlyHint ? 'read' : 'write',
      tool.name,
    );
  }
});
