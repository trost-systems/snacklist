// Job 94: the authorization server front for 2026-era clients (oauth.ts) as handle() serves it:
// which metadata each era is pointed at, the front's metadata, and how authorize and token map a
// Client ID Metadata Document URL while every other client passes through to Supabase Auth.
import { assertEquals, assertExists, assertMatch, assertStringIncludes } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import { CimdError, type ClientIdUrl } from './cimd.ts';
import type { MappedClient } from './cimd_clients.ts';
import { type Deps, handle } from './handler.ts';

const RESOURCE = 'https://ref.supabase.co/functions/v1/mcp';
const ISSUER = 'https://ref.supabase.co/auth/v1';
const FRONT = `${RESOURCE}/oauth`;
const PUBLIC = 'https://mcp.snacklist.app';
const SUPABASE_AS = {
  issuer: ISSUER,
  'authorization_endpoint': `${ISSUER}/oauth/authorize`,
  'token_endpoint': `${ISSUER}/oauth/token`,
  'registration_endpoint': `${ISSUER}/oauth/clients/register`,
  'jwks_uri': `${ISSUER}/.well-known/jwks.json`,
  'grant_types_supported': ['authorization_code', 'refresh_token'],
  'code_challenge_methods_supported': ['S256', 'plain'],
};
const DOC_URL = 'https://client.example/mcp.json' as ClientIdUrl;
const MAPPED = '7d4f3b8e-1c2a-4c5d-9e6f-0a1b2c3d4e5f';
const REDIRECT = 'http://127.0.0.1:8976/callback';

type Forwarded = { body: URLSearchParams; authorization: string | null };

function deps(clients: Record<string, MappedClient | CimdError> = {}, tokenAllowed = true) {
  const forwarded: Forwarded[] = [];
  const resolved: string[] = [];
  const d: Deps = {
    endpoints: () =>
      Promise.resolve({
        resource: RESOURCE,
        metadata: `${RESOURCE}/.well-known/oauth-protected-resource`,
        authorizationServer: ISSUER,
        cimdMetadata: `${RESOURCE}/.well-known/oauth-protected-resource/cimd`,
        cimdAuthorizationServer: FRONT,
      }),
    publicOrigins: () => [PUBLIC],
    authServerMetadata: () => Promise.resolve(SUPABASE_AS),
    oauth: {
      resolveClient: (url) => {
        resolved.push(url);
        const c = clients[url];
        return c instanceof CimdError || !c
          ? Promise.reject(c ?? new Error('?'))
          : Promise.resolve(c);
      },
      lookupClient: (url) => {
        const c = clients[url];
        return Promise.resolve(c && !(c instanceof CimdError) ? c.authClientId : null);
      },
      forwardToken: (body, authorization) => {
        forwarded.push({ body, authorization });
        return Promise.resolve(
          Response.json({ access_token: 'at', token_type: 'bearer' }, {
            headers: { 'set-cookie': 'x=y' },
          }),
        );
      },
      allowTokenRequest: () => Promise.resolve(tokenAllowed),
    },
    authenticate: () => Promise.reject(new AuthError('missing_token', 'fehlt')),
    takeCall: () => Promise.resolve(null),
    serve: () => Promise.resolve(new Response('served')),
    allowedOriginHosts: () => [],
  };
  return { d, forwarded, resolved };
}

const mcpPost = (version?: string, query = '') =>
  new Request(`http://edge/mcp${query}`, {
    method: 'POST',
    headers: version ? { 'mcp-protocol-version': version } : {},
    body: '{}',
  });

function headerOf(res: Response, name: string): string {
  const value = res.headers.get(name);
  assertExists(value, `no ${name} header`);
  return value;
}

function metadataOf(res: Response): string {
  const metadata = headerOf(res, 'www-authenticate').match(/resource_metadata="([^"]*)"/)?.[1];
  assertExists(metadata, 'no resource_metadata in the challenge');
  return metadata;
}

Deno.test('2026-era requests are pointed at the CIMD metadata, older ones keep Supabase Auth', async () => {
  const { d } = deps();
  for (const version of ['2026-07-28', '2027-01-01']) {
    assertEquals(
      metadataOf(await handle(mcpPost(version), d)),
      `${RESOURCE}/.well-known/oauth-protected-resource/cimd`,
    );
    assertEquals(
      metadataOf(await handle(mcpPost(version, '?via=mcp-snacklist'), d)),
      `${PUBLIC}/.well-known/oauth-protected-resource/cimd`,
    );
  }
  for (const version of [undefined, '2025-11-25', '2025-06-18', '2024-11-05', 'latest']) {
    assertEquals(
      metadataOf(await handle(mcpPost(version), d)),
      `${RESOURCE}/.well-known/oauth-protected-resource`,
      String(version),
    );
  }
});

Deno.test('the CIMD metadata names the same resource with the front as authorization server', async () => {
  const { d } = deps();
  for (
    const [query, resource, front] of [
      ['', RESOURCE, FRONT],
      ['?via=mcp-snacklist', PUBLIC, `${PUBLIC}/oauth`],
    ]
  ) {
    const res = await handle(
      new Request(`http://edge/mcp/.well-known/oauth-protected-resource/cimd${query}`),
      d,
    );
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.resource, resource);
    assertEquals(body.authorization_servers, [front]);
    assertEquals(body.scopes_supported, ['openid', 'email']);
  }
  const legacy = await (await handle(
    new Request('http://edge/mcp/.well-known/oauth-protected-resource'),
    d,
  )).json();
  assertEquals(legacy.authorization_servers, [ISSUER]);
});

Deno.test('the front serves its metadata at every discovery path, CIMD on, DCR kept', async () => {
  const { d } = deps();
  for (
    const [path, query, issuer] of [
      ['/mcp/oauth/.well-known/oauth-authorization-server', '', FRONT],
      ['/mcp/oauth/.well-known/openid-configuration', '', FRONT],
      ['/functions/v1/mcp/oauth/.well-known/openid-configuration', '', FRONT],
      [
        '/mcp/.well-known/oauth-authorization-server/oauth',
        '?via=mcp-snacklist',
        `${PUBLIC}/oauth`,
      ],
      ['/mcp/.well-known/openid-configuration/oauth', '?via=mcp-snacklist', `${PUBLIC}/oauth`],
    ]
  ) {
    const res = await handle(new Request(`http://edge${path}${query}`), d);
    assertEquals(res.status, 200, path);
    assertEquals(res.headers.get('access-control-allow-origin'), '*');
    assertEquals(await res.json(), {
      ...SUPABASE_AS,
      issuer,
      authorization_endpoint: `${issuer}/authorize`,
      token_endpoint: `${issuer}/token`,
      code_challenge_methods_supported: ['S256'],
      client_id_metadata_document_supported: true,
    }, path);
  }
  // The hint-less paths of 2026-10-31 still serve Supabase Auth's own document.
  const own = await handle(new Request('http://edge/mcp/.well-known/openid-configuration'), d);
  assertEquals((await own.json()).issuer, ISSUER);
});

const authorize = (params: Record<string, string>, query = '') =>
  new Request(`http://edge/mcp/oauth/authorize?${new URLSearchParams(params)}${query}`);

const PKCE = {
  'response_type': 'code',
  'redirect_uri': REDIRECT,
  'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
  'code_challenge_method': 'S256',
  state: 's-1',
  scope: 'openid email',
  resource: PUBLIC,
};

Deno.test('authorize: a registered client id passes through to Supabase unchanged', async () => {
  const { d, resolved } = deps();
  const res = await handle(authorize({ ...PKCE, client_id: MAPPED }, '&via=mcp-snacklist'), d);
  assertEquals(res.status, 302);
  const location = new URL(headerOf(res, 'location'));
  assertEquals(`${location.origin}${location.pathname}`, `${ISSUER}/oauth/authorize`);
  assertEquals(Object.fromEntries(location.searchParams), { ...PKCE, client_id: MAPPED });
  assertEquals(resolved, []);
});

Deno.test('authorize: a metadata document URL becomes its Supabase client', async () => {
  const { d, resolved } = deps({
    [DOC_URL]: { authClientId: MAPPED, redirectUris: [REDIRECT, 'http://localhost:8976/cb'] },
  });
  const res = await handle(authorize({ ...PKCE, client_id: DOC_URL }), d);
  assertEquals(res.status, 302);
  const location = new URL(headerOf(res, 'location'));
  assertEquals(Object.fromEntries(location.searchParams), { ...PKCE, client_id: MAPPED });
  assertEquals(resolved, [DOC_URL]);
});

Deno.test('authorize: refusals are shown, never redirected', async () => {
  const { d } = deps({
    [DOC_URL]: { authClientId: MAPPED, redirectUris: ['http://127.0.0.1:1/other', REDIRECT] },
    'https://broken.example/m.json': new CimdError('invalid_client', 'client metadata: bad'),
    'https://busy.example/m.json': new CimdError('temporarily_unavailable', 'later'),
  });
  const cases: [Record<string, string>, number, string][] = [
    [
      { ...PKCE, client_id: DOC_URL, redirect_uri: 'http://127.0.0.1:2/elsewhere' },
      400,
      'invalid_request',
    ],
    [{ ...PKCE, client_id: DOC_URL, redirect_uri: '' }, 400, 'invalid_request'],
    [{ ...PKCE, client_id: 'https://broken.example/m.json' }, 400, 'invalid_client'],
    [{ ...PKCE, client_id: 'https://busy.example/m.json' }, 503, 'temporarily_unavailable'],
    [{ ...PKCE, client_id: 'http://client.example/mcp.json' }, 400, 'invalid_client'],
    [{ ...PKCE, client_id: 'https://client.example/' }, 400, 'invalid_client'],
    [
      { ...PKCE, client_id: DOC_URL, redirect_uri: REDIRECT, code_challenge_method: 'plain' },
      400,
      'invalid_request',
    ],
    [
      { ...PKCE, client_id: DOC_URL, redirect_uri: REDIRECT, code_challenge: '' },
      400,
      'invalid_request',
    ],
  ];
  for (const [params, status, error] of cases) {
    const res = await handle(authorize(params), d);
    assertEquals(res.status, status, params.client_id);
    assertEquals(res.headers.get('location'), null);
    assertEquals((await res.json()).error, error, params.client_id);
  }
});

Deno.test('authorize: a registry failure is a 502, other methods 405', async () => {
  const { d } = deps();
  const down = await handle(authorize({ ...PKCE, client_id: 'https://down.example/m.json' }), d);
  assertEquals(down.status, 502);
  const post = await handle(new Request('http://edge/mcp/oauth/authorize', { method: 'POST' }), d);
  assertEquals(post.status, 405);
});

const tokenRequest = (form: Record<string, string>, headers: Record<string, string> = {}) =>
  new Request('http://edge/mcp/oauth/token?via=mcp-snacklist', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(form),
  });

Deno.test('token: a metadata document URL is swapped for its client, the rest forwarded', async () => {
  const { d, forwarded } = deps({ [DOC_URL]: { authClientId: MAPPED, redirectUris: [REDIRECT] } });
  for (const grant of ['authorization_code', 'refresh_token']) {
    const form: Record<string, string> = grant === 'authorization_code'
      ? { grant_type: grant, code: 'c', code_verifier: 'v', redirect_uri: REDIRECT }
      : { grant_type: grant, refresh_token: 'r' };
    const res = await handle(tokenRequest({ ...form, client_id: DOC_URL }), d);
    assertEquals(res.status, 200);
    assertEquals(res.headers.get('cache-control'), 'no-store');
    assertEquals(res.headers.get('set-cookie'), null);
    assertEquals((await res.json()).access_token, 'at');
    assertEquals(Object.fromEntries(forwarded.at(-1)?.body ?? []), { ...form, client_id: MAPPED });
  }
});

Deno.test('token: other clients pass through, credentials included', async () => {
  const { d, forwarded } = deps();
  const form = { 'grant_type': 'refresh_token', 'refresh_token': 'r', 'client_id': MAPPED };
  await handle(tokenRequest(form, { authorization: 'Basic abc' }), d);
  assertEquals(Object.fromEntries(forwarded[0]?.body ?? []), form);
  assertEquals(forwarded[0]?.authorization, 'Basic abc');
});

Deno.test('token: an unknown document URL or one with a secret is refused unforwarded', async () => {
  const { d, forwarded } = deps({ [DOC_URL]: { authClientId: MAPPED, redirectUris: [REDIRECT] } });
  const unknown = await handle(
    tokenRequest({
      grant_type: 'refresh_token',
      refresh_token: 'r',
      client_id: 'https://x.example/m',
    }),
    d,
  );
  assertEquals(unknown.status, 401);
  assertEquals((await unknown.json()).error, 'invalid_client');
  const secret = await handle(
    tokenRequest({ grant_type: 'refresh_token', refresh_token: 'r', client_id: DOC_URL }, {
      authorization: 'Basic abc',
    }),
    d,
  );
  assertEquals(secret.status, 400);
  assertStringIncludes((await secret.json()).error_description, 'PKCE');
  assertEquals(forwarded.length, 0);
  const get = await handle(new Request('http://edge/mcp/oauth/token'), d);
  assertEquals(get.status, 405);
});

Deno.test('the front needs no token and is not origin-checked (top-level navigation)', async () => {
  const { d } = deps();
  const res = await handle(
    new Request(
      `http://edge/mcp/oauth/authorize?${new URLSearchParams({ ...PKCE, client_id: MAPPED })}`,
      { headers: { origin: 'https://claude.ai' } },
    ),
    d,
  );
  assertEquals(res.status, 302);
  assertMatch(
    headerOf(res, 'location'),
    /^https:\/\/ref\.supabase\.co\/auth\/v1\/oauth\/authorize\?/,
  );
});

Deno.test('token: over the per-address limit, 429 and nothing forwarded', async () => {
  const { d, forwarded } = deps({}, false);
  const res = await handle(
    tokenRequest({ grant_type: 'refresh_token', refresh_token: 'r', client_id: MAPPED }),
    d,
  );
  assertEquals(res.status, 429);
  assertEquals((await res.json()).error, 'temporarily_unavailable');
  assertEquals(forwarded.length, 0);
});
