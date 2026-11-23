// Job 94: both protocol eras through handle() and the MCP server it serves, the requests
// scripts/mcp-smoke.sh sends. 2025-11-25 (and older): initialize, notifications/initialized, then
// tools/list, stateless as before. 2026-07-28: no initialize; server/discover, the _meta envelope,
// the Mcp-Method/Mcp-Name headers and ttlMs/cacheScope on cacheable results.
import { assert, assertEquals } from '@std/assert';
import { createMcpHandler } from '@modelcontextprotocol/server';
import { type Auth, AuthError } from '../_shared/auth.ts';
import type { Access } from '../_shared/premium.ts';
import { type Deps, handle } from './handler.ts';
import { buildServer } from './tools.ts';

const auth: Auth = {
  userId: 'u',
  householdId: 'h',
  via: 'pat',
  scopes: ['read', 'write'] as const,
};
const MODERN = '2026-07-28';
const LEGACY = '2025-11-25';
const TOOLS = [
  'add_items',
  'get_item',
  'list_categories',
  'list_households',
  'list_items',
  'list_lists',
  'list_recent',
  'list_stores',
  'merge_items',
  'move_item',
  'place_item',
  'remove_items',
  'set_store_order',
  'suggest_items',
  'tick_items',
  'untick_items',
  'update_item',
];

const d: Deps = {
  endpoints: () =>
    Promise.resolve({
      resource: 'https://ref.supabase.co/functions/v1/mcp',
      metadata: 'https://ref.supabase.co/functions/v1/mcp/.well-known/oauth-protected-resource',
      authorizationServer: 'https://ref.supabase.co/auth/v1',
      cimdMetadata:
        'https://ref.supabase.co/functions/v1/mcp/.well-known/oauth-protected-resource/cimd',
      cimdAuthorizationServer: 'https://ref.supabase.co/functions/v1/mcp/oauth',
    }),
  publicOrigins: () => ['https://mcp.snacklist.app'],
  authServerMetadata: () => Promise.resolve({}),
  oauth: {
    resolveClient: () => Promise.reject(new Error('unused')),
    lookupClient: () => Promise.resolve(null),
    forwardToken: () => Promise.reject(new Error('unused')),
    allowTokenRequest: () => Promise.resolve(true),
  },
  authenticate: () => Promise.resolve(auth),
  takeCall: () => Promise.resolve(null),
  // The database is never reached: the gate says locked, so tool calls touch no data.
  serve: (req, a) =>
    createMcpHandler(() =>
      buildServer(
        a,
        () => Promise.resolve<Access>('locked'),
        () => Promise.resolve(),
        'de',
      )
    ).fetch(req),
  allowedOriginHosts: () => [],
};

const envelope = (version = MODERN) => ({
  'io.modelcontextprotocol/protocolVersion': version,
  'io.modelcontextprotocol/clientInfo': { name: 'protocol-test', version: '1' },
  'io.modelcontextprotocol/clientCapabilities': {},
});

type Rpc = {
  method: string;
  params?: Record<string, unknown>;
  id?: number | null;
  version?: string;
  headers?: Record<string, string>;
};

async function rpc({ method, params = {}, id = 1, version = LEGACY, headers = {} }: Rpc) {
  const res = await handle(
    new Request('http://edge/mcp', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        authorization: 'Bearer fgp_x',
        'mcp-protocol-version': version,
        ...headers,
      },
      body: JSON.stringify({ jsonrpc: '2.0', method, params, ...(id === null ? {} : { id }) }),
    }),
    d,
  );
  const text = await res.text();
  const data = text.split('\n').find((l) => l.startsWith('data: '));
  // deno-lint-ignore no-explicit-any -- JSON-RPC answers of many shapes; each test reads its own fields
  const message: any = text ? JSON.parse(data ? data.slice(6) : text) : undefined;
  return { status: res.status, headers: res.headers, message };
}

const modern = (method: string, params: Record<string, unknown> = {}, headers = {}) =>
  rpc({
    method,
    params: { ...params, _meta: envelope() },
    version: MODERN,
    headers: { 'mcp-method': method, ...headers },
  });

Deno.test('2025-11-25: initialize, notifications/initialized and tools/list as today', async () => {
  const init = await rpc({
    method: 'initialize',
    params: { protocolVersion: LEGACY, capabilities: {}, clientInfo: { name: 't', version: '1' } },
  });
  assertEquals(init.status, 200);
  assertEquals(init.message.result.protocolVersion, LEGACY);
  assertEquals(init.message.result.serverInfo.name, 'snacklist');
  assertEquals(init.message.result.capabilities.tools, { listChanged: true });
  // Stateless: no session is created, so a client has none to keep.
  assertEquals(init.headers.get('mcp-session-id'), null);
  const initialized = await rpc({ method: 'notifications/initialized', id: null });
  assertEquals(initialized.status, 202);
  const list = await rpc({ method: 'tools/list' });
  assertEquals(list.status, 200);
  assertEquals(list.message.result.tools.map((t: { name: string }) => t.name).sort(), TOOLS);
  // The 2026 fields never reach a 2025-era answer.
  assertEquals(list.message.result.ttlMs, undefined);
  assertEquals(list.message.result.resultType, undefined);
});

Deno.test('older 2025-era revisions still negotiate through initialize', async () => {
  for (const version of ['2025-06-18', '2025-03-26', '2024-11-05']) {
    const init = await rpc({
      method: 'initialize',
      version,
      params: {
        protocolVersion: version,
        capabilities: {},
        clientInfo: { name: 't', version: '1' },
      },
    });
    assertEquals(init.message.result.protocolVersion, version, version);
  }
});

Deno.test('2025-era session operations stay 405 (stateless as before)', async () => {
  for (const method of ['GET', 'DELETE']) {
    const res = await handle(
      new Request('http://edge/mcp', {
        method,
        headers: { authorization: 'Bearer fgp_x', 'mcp-protocol-version': LEGACY },
      }),
      d,
    );
    assertEquals(res.status, 405, method);
    await res.body?.cancel();
  }
});

Deno.test('2026-07-28: server/discover names versions, server, capabilities and cache fields', async () => {
  const { status, message } = await modern('server/discover');
  assertEquals(status, 200);
  const r = message.result;
  assertEquals(r.supportedVersions, [MODERN]);
  assertEquals(r._meta['io.modelcontextprotocol/serverInfo'].name, 'snacklist');
  assertEquals(r.capabilities.tools, { listChanged: true });
  assertEquals(r.resultType, 'complete');
  assertEquals([r.ttlMs, r.cacheScope], [3_600_000, 'private']);
  assert(r.instructions.startsWith('Snacklist'));
});

Deno.test('2026-07-28: tools/list without initialize, cacheable for an hour, private', async () => {
  const { status, message } = await modern('tools/list');
  assertEquals(status, 200);
  const r = message.result;
  assertEquals(r.tools.map((t: { name: string }) => t.name).sort(), TOOLS);
  assertEquals([r.resultType, r.ttlMs, r.cacheScope], ['complete', 3_600_000, 'private']);
  assertEquals(r._meta['io.modelcontextprotocol/serverInfo'].name, 'snacklist');
});

Deno.test('2026-07-28: tools/call needs Mcp-Name; with it the call runs', async () => {
  const call = { name: 'list_items', arguments: {} };
  const named = await modern('tools/call', call, { 'mcp-name': 'list_items' });
  assertEquals(named.status, 200);
  assertEquals(named.message.result.isError, true, 'locked household: the premium answer');
  assertEquals(named.message.result.resultType, 'complete');
  for (const headers of [{}, { 'mcp-name': 'add_items' }]) {
    const res = await modern('tools/call', call, headers);
    assertEquals(res.status, 400, JSON.stringify(headers));
    assertEquals(res.message.error.code, -32020, 'HeaderMismatch');
  }
});

Deno.test('2026-07-28: a missing or wrong Mcp-Method is a header mismatch', async () => {
  for (const method of [undefined, 'tools/call']) {
    const res = await rpc({
      method: 'tools/list',
      params: { _meta: envelope() },
      version: MODERN,
      headers: method ? { 'mcp-method': method } : {},
    });
    assertEquals(res.status, 400, String(method));
    assertEquals(res.message.error.code, -32020);
  }
});

Deno.test('2026-07-28: initialize is not part of it; unknown versions name the supported one', async () => {
  const init = await rpc({
    method: 'initialize',
    version: MODERN,
    headers: { 'mcp-method': 'initialize' },
    params: { protocolVersion: MODERN, capabilities: {}, clientInfo: { name: 't', version: '1' } },
  });
  assertEquals(init.status, 400);
  const unknown = await rpc({
    method: 'server/discover',
    version: '2099-01-01',
    headers: { 'mcp-method': 'server/discover' },
    params: { _meta: envelope('2099-01-01') },
  });
  assertEquals(unknown.message.error.code, -32022, 'UnsupportedProtocolVersion');
  assertEquals(unknown.message.error.data.supported, [MODERN]);
});

Deno.test('both eras need the token: a 2026 request without one gets the CIMD challenge', async () => {
  const res = await handle(
    new Request('http://edge/mcp', {
      method: 'POST',
      headers: { 'mcp-protocol-version': MODERN, 'mcp-method': 'server/discover' },
      body: '{}',
    }),
    {
      ...d,
      authenticate: () => Promise.reject(new AuthError('missing_token', 'fehlt')),
    },
  );
  assertEquals(res.status, 401);
  assert(res.headers.get('www-authenticate')?.includes('/oauth-protected-resource/cimd"'));
});
