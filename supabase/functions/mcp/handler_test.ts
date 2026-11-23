import { assertEquals, assertExists, assertMatch, assertStringIncludes } from '@std/assert';
import { type Auth, AuthError } from '../_shared/auth.ts';
import {
  clientAddress,
  type Deps,
  handle,
  publicOriginFromEnv,
  publicOriginsFromEnv,
  refundLocked,
  toolCallsIn,
} from './handler.ts';

function headerOf(res: Response, name: string): string {
  const value = res.headers.get(name);
  assertExists(value, `no ${name} header`);
  return value;
}

const RESOURCE = 'https://ref.supabase.co/functions/v1/mcp';
const METADATA = `${RESOURCE}/.well-known/oauth-protected-resource`;
const ISSUER = 'https://ref.supabase.co/auth/v1';
const PUBLIC = 'https://mcp.hummlist.com';
const PUBLIC_SNACK = 'https://mcp.snacklist.app';
const PUBLIC_METADATA = `${PUBLIC}/.well-known/oauth-protected-resource`;
const PUBLIC_SNACK_METADATA = `${PUBLIC_SNACK}/.well-known/oauth-protected-resource`;
const USER = { userId: 'u', householdId: 'h' };
const AS_METADATA = {
  issuer: ISSUER,
  'authorization_endpoint': `${ISSUER}/oauth/authorize`,
  'token_endpoint': `${ISSUER}/oauth/token`,
  'registration_endpoint': `${ISSUER}/oauth/clients/register`,
  'grant_types_supported': ['authorization_code', 'refresh_token'],
};

function deps(auth: Auth | AuthError): Deps {
  return {
    endpoints: () =>
      Promise.resolve({
        resource: RESOURCE,
        metadata: METADATA,
        authorizationServer: ISSUER,
        cimdMetadata: `${METADATA}/cimd`,
        cimdAuthorizationServer: `${RESOURCE}/oauth`,
      }),
    publicOrigins: () => [PUBLIC, PUBLIC_SNACK],
    authServerMetadata: () => Promise.resolve(AS_METADATA),
    oauth: {
      resolveClient: () => Promise.reject(new Error('no client registry in this test')),
      lookupClient: () => Promise.resolve(null),
      forwardToken: () => Promise.reject(new Error('no token endpoint in this test')),
      allowTokenRequest: () => Promise.resolve(true),
    },
    authenticate: () => auth instanceof AuthError ? Promise.reject(auth) : Promise.resolve(auth),
    refundCalls: () => Promise.resolve(),
    takeCall: () => Promise.resolve(null),
    serve: (_req, a) => Promise.resolve(Response.json({ served: a.via })),
    allowedOriginHosts: () => ['inspector.example'],
  };
}

type Via = { headers?: Record<string, string>; query?: string };

const post = (headers: Record<string, string> = {}, query = '') =>
  new Request(`http://edge/mcp${query}`, { method: 'POST', headers, body: '{}' });

const prm = ({ headers = {}, query = '' }: Via) =>
  new Request(`http://edge/mcp/.well-known/oauth-protected-resource${query}`, { headers });

/** What mcp-proxy/vercel.json sends for mcp.hummlist.com, by either signal. */
const PROXIED: Via[] = [
  { query: '?via=mcp-hummlist' },
  { headers: { 'x-forwarded-host': 'mcp.hummlist.com' } },
  { headers: { 'x-forwarded-host': 'MCP.Hummlist.com:443' } },
  { headers: { 'x-forwarded-host': 'mcp.hummlist.com, edge.internal' } },
  { headers: { 'x-forwarded-host': 'ref.supabase.co' }, query: '?via=mcp-hummlist' },
];

/** What mcp-proxy/vercel.json sends for mcp.snacklist.app. */
const PROXIED_SNACK: Via[] = [
  { query: '?via=mcp-snacklist' },
  { headers: { 'x-forwarded-host': 'mcp.snacklist.app' } },
  { headers: { 'x-forwarded-host': 'MCP.Snacklist.app:443' } },
  { headers: { 'x-forwarded-host': 'mcp.snacklist.app, edge.internal' } },
  { headers: { 'x-forwarded-host': 'ref.supabase.co' }, query: '?via=mcp-snacklist' },
];

/** The resource and metadata URL a client is told to use: from the PRM and from a 401. */
async function advertised(via: Via, d = deps(new AuthError('missing_token', 'fehlt'))) {
  const body = await (await handle(prm(via), d)).json();
  const challenge = headerOf(await handle(post(via.headers, via.query), d), 'www-authenticate');
  return {
    resource: body.resource,
    authorizationServers: body.authorization_servers,
    metadata: challenge.match(/resource_metadata="([^"]*)"/)?.[1],
  };
}

Deno.test('serves Protected Resource Metadata at the well-known suffix', async () => {
  for (
    const path of ['/mcp/.well-known/oauth-protected-resource', '/mcp/oauth-protected-resource']
  ) {
    const res = await handle(
      new Request(`http://edge${path}`),
      deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const }),
    );
    assertEquals(res.status, 200);
    assertEquals(res.headers.get('access-control-allow-origin'), '*');
    const body = await res.json();
    assertEquals(body.resource, RESOURCE);
    assertEquals(body.authorization_servers, [ISSUER]);
  }
});

Deno.test('a request without a token gets 401 pointing at the metadata', async () => {
  const res = await handle(post(), deps(new AuthError('missing_token', 'fehlt')));
  assertEquals(res.status, 401);
  assertEquals(
    res.headers.get('www-authenticate'),
    `Bearer resource_metadata="${METADATA}", scope="openid email"`,
  );
  assertEquals(
    res.headers.get('access-control-expose-headers'),
    'www-authenticate, mcp-session-id, retry-after',
  );
});

Deno.test('an invalid token gets 401 with error="invalid_token"', async () => {
  const res = await handle(post(), deps(new AuthError('invalid_token', 'abgelaufen')));
  assertEquals(res.status, 401);
  assertMatch(headerOf(res, 'www-authenticate'), /error="invalid_token"/);
});

Deno.test('the challenge stays RFC 6750 ASCII when the message is German', async () => {
  // The hosted gateway drops a WWW-Authenticate header with bytes outside printable ASCII.
  const res = await handle(
    post(),
    deps(new AuthError('invalid_token', 'Token ungültig: "kaputt" \\ Größe')),
  );
  const header = headerOf(res, 'www-authenticate');
  assertMatch(header, /^[\x20-\x7e]+$/);
  assertStringIncludes(header, `error_description="Token ungueltig: 'kaputt'  Groesse"`);
});

Deno.test('a user without a household gets 403', async () => {
  const res = await handle(post(), deps(new AuthError('no_household', 'kein Haushalt')));
  assertEquals(res.status, 403);
});

Deno.test('app session tokens are not accepted as MCP credentials', async () => {
  const res = await handle(post(), deps({ ...USER, via: 'session' }));
  assertEquals(res.status, 401);
  assertMatch(headerOf(res, 'www-authenticate'), /error="invalid_token"/);
});

Deno.test('OAuth and PAT credentials reach the MCP server', async () => {
  for (
    const auth of [{ ...USER, via: 'oauth', clientId: 'c', sessionId: 's' }, {
      ...USER,
      via: 'pat',
      scopes: ['read', 'write'],
    }] as const
  ) {
    const res = await handle(post(), deps(auth));
    assertEquals(await res.json(), { served: auth.via });
  }
});

Deno.test('a request over the limit gets 429 with Retry-After and is not served', async () => {
  const taken: string[] = [];
  let served = 0;
  const d: Deps = {
    ...deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const }),
    refundCalls: () => Promise.resolve(),
    takeCall: (userId) => {
      taken.push(userId);
      return Promise.resolve(taken.length > 2 ? 7 : null);
    },
    serve: () => {
      served++;
      return Promise.resolve(Response.json({}));
    },
  };
  const statuses = [];
  for (let i = 0; i < 3; i++) statuses.push((await handle(post(), d)).status);
  const limited = await handle(post(), d);
  assertEquals([...statuses, limited.status], [200, 200, 429, 429]);
  assertEquals(served, 2);
  assertEquals(taken, ['u', 'u', 'u', 'u']);
  assertEquals(limited.headers.get('retry-after'), '7');
  assertEquals(limited.headers.get('access-control-allow-origin'), '*');
  assertEquals((await limited.json()).error.code, -32000);
});

Deno.test('a request whose account row is busy gets 503; other count failures throw', async () => {
  const busy = Object.assign(new Error('busy'), { name: 'PostgresError', code: '55P03' });
  const res = await handle(post(), {
    ...deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const }),
    refundCalls: () => Promise.resolve(),
    takeCall: () => Promise.reject(busy),
  });
  assertEquals(res.status, 503);
  assertEquals(res.headers.get('retry-after'), '1');
  const broken = new Error('down');
  let thrown: unknown;
  try {
    await handle(post(), {
      ...deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const }),
      refundCalls: () => Promise.resolve(),
      takeCall: () => Promise.reject(broken),
    });
  } catch (e) {
    thrown = e;
  }
  assertEquals(thrown, broken);
});

Deno.test('an account deleted between authentication and the count gets the 401 challenge', async () => {
  const res = await handle(post(), {
    ...deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const }),
    refundCalls: () => Promise.resolve(),
    takeCall: () => Promise.reject(new AuthError('user_deleted', 'Dieses Konto ist gelöscht.')),
  });
  assertEquals(res.status, 401);
  assertMatch(headerOf(res, 'www-authenticate'), /error="invalid_token"/);
});

Deno.test('a request that fails authentication is not counted', async () => {
  let counted = 0;
  const res = await handle(post(), {
    ...deps(new AuthError('invalid_token', 'abgelaufen')),
    refundCalls: () => Promise.resolve(),
    takeCall: () => {
      counted++;
      return Promise.resolve(null);
    },
  });
  assertEquals(res.status, 401);
  assertEquals(counted, 0);
});

Deno.test('browser origins outside the allowlist get 403; listed and absent origins pass', async () => {
  const pat = deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const });
  assertEquals((await handle(post({ origin: 'https://evil.example' }), pat)).status, 403);
  for (
    const origin of [
      'https://inspector.example',
      'http://localhost:6274',
      'https://ref.supabase.co',
    ]
  ) {
    assertEquals((await handle(post({ origin }), pat)).status, 200, origin);
  }
  assertEquals((await handle(post(), pat)).status, 200);
});

Deno.test('a direct request advertises the project URL', async () => {
  for (const via of [{}, { headers: { 'x-forwarded-host': 'ref.supabase.co' } }]) {
    assertEquals(await advertised(via), {
      resource: RESOURCE,
      authorizationServers: [ISSUER],
      metadata: METADATA,
    });
  }
});

Deno.test('a request through the proxy advertises the public URL, same issuer', async () => {
  for (const via of PROXIED) {
    assertEquals(await advertised(via), {
      resource: PUBLIC,
      authorizationServers: [ISSUER],
      metadata: PUBLIC_METADATA,
    }, JSON.stringify(via));
  }
  for (const via of PROXIED_SNACK) {
    assertEquals(await advertised(via), {
      resource: PUBLIC_SNACK,
      authorizationServers: [ISSUER],
      metadata: PUBLIC_SNACK_METADATA,
    }, JSON.stringify(via));
  }
});

Deno.test('a rejected token through the proxy also points at the public metadata', async () => {
  for (
    const [cases, metadata] of [[PROXIED, PUBLIC_METADATA], [
      PROXIED_SNACK,
      PUBLIC_SNACK_METADATA,
    ]] as const
  ) {
    for (const { headers, query } of cases) {
      for (
        const auth of [new AuthError('invalid_token', 'x'), { ...USER, via: 'session' } as const]
      ) {
        const res = await handle(post(headers, query), deps(auth));
        assertEquals(res.status, 401);
        assertStringIncludes(headerOf(res, 'www-authenticate'), `resource_metadata="${metadata}"`);
      }
      const forbidden = await handle(
        post(headers, query),
        deps(new AuthError('no_household', 'kein Haushalt')),
      );
      assertEquals(forbidden.status, 403);
      assertStringIncludes(headerOf(forbidden, 'www-authenticate'), metadata);
    }
  }
});

Deno.test('any other forwarded host or marker gets the project URL', async () => {
  for (
    const via of [
      { headers: { 'x-forwarded-host': 'evil.example' } },
      { headers: { 'x-forwarded-host': 'mcp.hummlist.com.evil.example' } },
      { headers: { 'x-forwarded-host': 'mcp.snacklist.app.evil.example' } },
      { headers: { 'x-forwarded-host': 'evil.example, mcp.hummlist.com' } },
      { headers: { 'x-forwarded-host': 'evil.example, mcp.snacklist.app' } },
      { query: '?via=evil.example' },
      { query: '?via=__proto__' },
      { query: '?mcp-hummlist' },
    ]
  ) {
    assertEquals((await advertised(via)).resource, RESOURCE, JSON.stringify(via));
  }
});

Deno.test('MCP_PUBLIC_URL replaces the public origin', async () => {
  try {
    Deno.env.delete('MCP_PUBLIC_URL');
    assertEquals(publicOriginFromEnv(), PUBLIC);
    assertEquals(publicOriginsFromEnv(), [PUBLIC, PUBLIC_SNACK]);
    Deno.env.set('MCP_PUBLIC_URL', 'https://mcp.example.test/');
    assertEquals(publicOriginsFromEnv(), ['https://mcp.example.test']);
    const d = { ...deps(new AuthError('missing_token', 'x')), publicOrigins: publicOriginsFromEnv };
    const expected = {
      resource: 'https://mcp.example.test',
      authorizationServers: [ISSUER],
      metadata: 'https://mcp.example.test/.well-known/oauth-protected-resource',
    };
    assertEquals(
      await advertised({ headers: { 'x-forwarded-host': 'mcp.example.test' } }, d),
      expected,
    );
    assertEquals(await advertised({ query: '?via=mcp-hummlist' }, d), expected);
    assertEquals(
      (await advertised({ headers: { 'x-forwarded-host': 'mcp.hummlist.com' } }, d)).resource,
      RESOURCE,
    );
    assertEquals(
      (await advertised({ query: '?via=mcp-snacklist' }, d)).resource,
      RESOURCE,
    );
  } finally {
    Deno.env.delete('MCP_PUBLIC_URL');
  }
});

Deno.test('the public origin is an allowed browser origin', async () => {
  const pat = deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const });
  assertEquals((await handle(post({ origin: PUBLIC }), pat)).status, 200);
  assertEquals((await handle(post({ origin: PUBLIC_SNACK }), pat)).status, 200);
  for (const { headers, query } of [{}, ...PROXIED]) {
    assertEquals(
      (await handle(post({ ...headers, origin: 'https://evil.example' }, query), pat)).status,
      403,
    );
  }
});

Deno.test('CORS preflight answers without auth', async () => {
  const res = await handle(
    new Request('http://edge/mcp', { method: 'OPTIONS' }),
    deps(new AuthError('missing_token', 'x')),
  );
  assertEquals(res.status, 204);
  assertMatch(headerOf(res, 'access-control-allow-headers'), /mcp-protocol-version/);
});

// 2026-10-31: a connector on the supabase.co URL refreshes without the 401's resource_metadata hint.
// Its RFC 9728 probe (/.well-known/oauth-protected-resource/functions/v1/mcp) and the root-level
// RFC 8414 / OIDC probes hit Supabase's gateway (401, no apikey); only
// <mcp>/.well-known/openid-configuration reaches the function. It got 401, found no token
// endpoint and never refreshed. These discovery documents must be public.
Deno.test('serves Supabase Auth metadata at the discovery paths without a token', async () => {
  for (const base of ['http://edge/mcp', 'http://edge/mcp/']) {
    for (
      const suffix of ['.well-known/openid-configuration', '.well-known/oauth-authorization-server']
    ) {
      for (const query of ['', '?via=mcp-hummlist', '?via=mcp-snacklist']) {
        const url = `${base.replace(/\/$/, '')}/${suffix}${query}`;
        const res = await handle(
          new Request(url),
          deps(new AuthError('missing_token', 'fehlt')),
        );
        assertEquals(res.status, 200, url);
        assertEquals(res.headers.get('access-control-allow-origin'), '*');
        assertEquals(res.headers.get('www-authenticate'), null);
        const body = await res.json();
        assertEquals(body.token_endpoint, `${ISSUER}/oauth/token`);
        assertEquals(body.grant_types_supported, ['authorization_code', 'refresh_token']);
      }
    }
  }
});

Deno.test('auth metadata: other methods get 405, an upstream failure 502', async () => {
  const d = deps({ ...USER, via: 'pat', scopes: ['read', 'write'] as const });
  const put = await handle(
    new Request('http://edge/mcp/.well-known/openid-configuration', { method: 'POST', body: '{}' }),
    d,
  );
  assertEquals(put.status, 405);
  const down = await handle(new Request('http://edge/mcp/.well-known/openid-configuration'), {
    ...d,
    authServerMetadata: () => Promise.reject(new Error('down')),
  });
  assertEquals(down.status, 502);
  assertEquals((await down.json()).error, 'temporarily_unavailable');
});

// Job 94 review: the token limit is per client address, also behind the Vercel proxy, where
// Supabase's gateway sees Vercel's address in X-Real-IP.
Deno.test("the client address: Vercel's header through the proxy, X-Real-IP directly", () => {
  const req = (headers: Record<string, string>) => new Request('http://edge/mcp', { headers });
  const proxied = req({
    'x-real-ip': '76.76.21.9',
    'x-vercel-forwarded-for': '203.0.113.7',
    'x-forwarded-for': '203.0.113.7, 76.76.21.9',
  });
  assertEquals(clientAddress(proxied, true), '203.0.113.7');
  assertEquals(clientAddress(proxied, false), '76.76.21.9');
  const direct = req({ 'x-real-ip': '198.51.100.4', 'x-vercel-forwarded-for': '203.0.113.99' });
  assertEquals(clientAddress(direct, false), '198.51.100.4', 'a forged Vercel header is ignored');
  assertEquals(clientAddress(req({ 'x-real-ip': '198.51.100.4' }), true), '198.51.100.4');
  assertEquals(
    clientAddress(req({ 'x-forwarded-for': '192.0.2.1, 10.0.0.1' }), false),
    '192.0.2.1',
  );
  assertEquals(clientAddress(req({}), true), 'unknown');
});

Deno.test('toolCallsIn: only tools/call counts, each one of a batch', async () => {
  const post = (body: string) =>
    new Request('https://x.test/mcp', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
    });
  const call = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'list_items' } };
  assertEquals(await toolCallsIn(post(JSON.stringify(call))), 1);
  assertEquals(await toolCallsIn(post(JSON.stringify({ ...call, method: 'initialize' }))), 0);
  assertEquals(await toolCallsIn(post(JSON.stringify({ ...call, method: 'tools/list' }))), 0);
  assertEquals(await toolCallsIn(post(JSON.stringify({ ...call, method: 'ping' }))), 0);
  assertEquals(
    await toolCallsIn(
      post(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })),
    ),
    0,
  );
  assertEquals(
    await toolCallsIn(
      post(JSON.stringify([call, { ...call, id: 2 }, { ...call, method: 'ping' }])),
    ),
    2,
  );
  assertEquals(await toolCallsIn(post('not json')), 0);
  assertEquals(await toolCallsIn(new Request('https://x.test/mcp')), 0);
});

Deno.test('refundLocked: a call the plan gate refused is given back, any other stays counted', async () => {
  const log: string[] = [];
  const report = refundLocked(
    (c) => {
      log.push(`report ${c.reason}`);
      return Promise.resolve();
    },
    () => {
      log.push('refund');
      return Promise.resolve();
    },
  );
  await report({ tool: 'list_items', household: 'h', reason: 'premium_required' });
  await report({ tool: 'list_items', household: 'h', reason: 'done' });
  await report({ tool: 'list_items', household: 'h', reason: 'tool_error' });
  assertEquals(log, [
    'refund',
    'report premium_required',
    'report done',
    'report tool_error',
  ]);
});
