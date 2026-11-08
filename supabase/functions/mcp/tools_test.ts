// Job 50: the integration lock on the MCP tools, through the SDK's streamable HTTP handler as a
// client sees it. Locked: initialize and tools/list work, every tool call is an isError result with
// HTTP 200 and touches no data; a failing check is no premium answer.
import { assert, assertEquals, assertFalse } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import type { Auth } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import { buildServer, type Gate, langOf, premiumRequired } from './tools.ts';

const auth: Auth = { userId: 'u', householdId: 'h', via: 'pat' };

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
      'mcp-protocol-version': '2025-06-18',
      ...(lang ? { 'accept-language': lang } : {}),
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });

/** The JSON-RPC message of a JSON or SSE answer. */
interface Message {
  result: {
    serverInfo: { name: string };
    tools: { name: string; inputSchema: { properties?: Record<string, unknown> } }[];
    isError?: boolean;
    content: { type: string; text: string }[];
  };
  error?: unknown;
}

async function message(res: Response): Promise<Message> {
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  return JSON.parse(data ? data.slice(6) : text);
}

function serve(gate: Gate, lang?: string) {
  const asked: string[] = [];
  const counted: Gate = (household) => {
    asked.push(household);
    return gate(household);
  };
  const handle = (req: Request) =>
    createMcpHandler(() => buildServer(auth, counted, langOf(req.headers.get('accept-language'))))
      .fetch(req);
  return { handle, asked: () => asked.length, households: () => asked, lang };
}

const locked: Gate = () => Promise.resolve<Access>('locked');

/** The tools behind the lock; list_households only lists the user's own households. */
const calls: [string, Record<string, unknown>][] = [
  ['list_items', {}],
  ['add_items', { items: [{ name: 'Milch' }] }],
  ['tick_items', { items: ['Milch'] }],
  ['move_item', { item: 'Milch', store: 'dm' }],
  ['list_categories', {}],
  ['list_stores', {}],
];

Deno.test('locked: initialize and tools/list answer without asking the gate', async () => {
  const s = serve(locked);
  const init = await s.handle(rpc('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'test', version: '1' },
  }));
  assertEquals(init.status, 200);
  assertEquals((await message(init)).result.serverInfo.name, 'hummlist');
  const list = await s.handle(rpc('tools/list'));
  assertEquals(list.status, 200);
  assertEquals(
    (await message(list)).result.tools.map((t) => t.name).sort(),
    ['list_households', ...calls.map(([name]) => name)].sort(),
  );
  assertEquals(s.asked(), 0);
});

Deno.test('locked: every tool call is an isError result with HTTP 200, data untouched', async () => {
  for (const [name, args] of calls) {
    const s = serve(locked);
    // The database is never reached: asUser would fail here without SUPABASE_DB_URL.
    const res = await s.handle(rpc('tools/call', { name, arguments: args }));
    assertEquals(res.status, 200, name);
    const { result, error } = await message(res);
    assertEquals(error, undefined, `${name}: a tool result, not a JSON-RPC error`);
    assertEquals(result.isError, true, name);
    assertEquals(result.content, [{ type: 'text', text: premiumRequired.de }], name);
    assertEquals(s.asked(), 1, name);
    assertEquals(s.households(), ['h'], `${name}: without "household" the credential's household`);
  }
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

Deno.test('locked: English for a client that prefers it', async () => {
  const s = serve(locked);
  const res = await s.handle(
    rpc('tools/call', { name: 'list_items', arguments: {} }, 'en-US,en;q=0.9,de;q=0.5'),
  );
  assertEquals((await message(res)).result.content[0]?.text, premiumRequired.en);
  assert(premiumRequired.en.includes('Hummlist Premium'));
  assert(premiumRequired.de.includes('Hummlist Premium'));
});

Deno.test('the check fails: no premium answer (an error, like any database failure)', async () => {
  const s = serve(() => Promise.reject(new Error('connection refused')));
  const res = await s.handle(rpc('tools/call', { name: 'list_items', arguments: {} }));
  const text = JSON.stringify(await message(res));
  assertFalse(text.includes('Premium'));
  assert(text.includes('error') || text.includes('isError'));
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
