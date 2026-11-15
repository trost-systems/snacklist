// Job 94: Client ID Metadata Documents end to end against the local stack's Supabase Auth and
// database, through the function's production wiring and the official MCP client in protocol
// 2026-07-28. Only the document host is faked: Supabase refuses to fetch anything but https, and a
// client's document lives on the client's own host. A throwaway account and household, removed
// after. The db gate sets FG_DB_TEST=1, SUPABASE_URL, SUPABASE_DB_URL and
// SUPABASE_SERVICE_ROLE_KEY; without them this is skipped.
import { assert, assertEquals, assertNotEquals } from '@std/assert';
import postgres from 'postgres';
import {
  Client,
  type OAuthClientProvider,
  StreamableHTTPClientTransport,
  UnauthorizedError,
} from '@modelcontextprotocol/client';
import { serviceDb } from '../_shared/db.ts';
import { CimdError, type ClientIdUrl, parseClientMetadata } from './cimd.ts';
import { resolveClient, secretKeyFromEnv, supabaseClientAdmin } from './cimd_clients.ts';
import { handle, productionDeps } from './handler.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';
function env(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`${name} is not set`);
  return value;
}

function locationOf(res: Response): URL {
  const location = res.headers.get('location');
  assert(location, `no location on the ${res.status} answer`);
  return new URL(location);
}

const api = () => env('SUPABASE_URL');
const admin = () => postgres(env('SUPABASE_DB_URL'), { max: 1, prepare: false });
const CALLBACK = 'http://127.0.0.1:8976/callback';
const PASSWORD = `${crypto.randomUUID()}-Aa1`;

/** The documents the fake client host serves, by URL; a test may change one. */
const documents = new Map<string, Record<string, unknown>>();
let fetches = 0;

const deps = {
  ...productionDeps,
  oauth: {
    ...productionDeps.oauth,
    resolveClient: (url: ClientIdUrl) =>
      resolveClient(url, {
        sql: serviceDb,
        admin: supabaseClientAdmin(api(), secretKeyFromEnv()),
        fetchDocument: (u) => {
          fetches++;
          const doc = documents.get(u);
          if (!doc) {
            return Promise.reject(new CimdError('invalid_client', `client metadata: none at ${u}`));
          }
          return Promise.resolve({ metadata: parseClientMetadata(u, doc), maxAgeSeconds: 600 });
        },
      }),
  },
};

const mcpUrl = () => new URL(`${api()}/functions/v1/mcp`);

/** Requests to the function are served in-process by this checkout's handler; the rest is real. */
const routed: typeof fetch = (input, init) => {
  const req = new Request(input, init);
  return req.url.startsWith(mcpUrl().href) ? handle(req, deps) : fetch(req);
};

class Provider implements OAuthClientProvider {
  authorizationUrl?: URL;
  client?: Awaited<ReturnType<OAuthClientProvider['clientInformation']>>;
  saved?: Awaited<ReturnType<OAuthClientProvider['tokens']>>;
  private verifier = '';
  private discovery?: Awaited<ReturnType<NonNullable<OAuthClientProvider['discoveryState']>>>;

  readonly clientMetadataUrl?: string;

  constructor(clientMetadataUrl?: string) {
    if (clientMetadataUrl !== undefined) this.clientMetadataUrl = clientMetadataUrl;
  }

  get redirectUrl() {
    return CALLBACK;
  }

  get clientMetadata() {
    return {
      client_name: 'cimd integration (dynamic registration)',
      redirect_uris: [CALLBACK],
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
    };
  }

  clientInformation() {
    return this.client;
  }

  saveClientInformation(info: NonNullable<Provider['client']>) {
    this.client = info;
  }

  tokens() {
    return this.saved;
  }

  saveTokens(tokens: NonNullable<Provider['saved']>) {
    this.saved = tokens;
  }

  redirectToAuthorization(url: URL) {
    this.authorizationUrl = url;
  }

  saveCodeVerifier(verifier: string) {
    this.verifier = verifier;
  }

  codeVerifier() {
    return this.verifier;
  }

  saveDiscoveryState(state: NonNullable<Provider['discovery']>) {
    this.discovery = state;
  }

  discoveryState() {
    return this.discovery;
  }
}

const transport = (provider: Provider) =>
  new StreamableHTTPClientTransport(mcpUrl(), { authProvider: provider, fetch: routed });

const modernClient = () =>
  new Client({ name: 'cimd-integration', version: '1' }, {
    versionNegotiation: { mode: { pin: '2026-07-28' } },
  });

type User = { id: string; email: string; token: string; householdId: string };

async function signUp(): Promise<User> {
  const key = env('SUPABASE_ANON_KEY');
  const email = `cimd-${crypto.randomUUID()}@fg-test.invalid`;
  const res = await fetch(`${api()}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: key, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  const session = await res.json();
  assert(session.access_token, JSON.stringify(session));
  const household = await fetch(`${api()}/rest/v1/rpc/create_household`, {
    method: 'POST',
    headers: {
      apikey: key,
      authorization: `Bearer ${session.access_token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ p_name: 'CIMD' }),
  });
  assertEquals(household.status, 200, await household.clone().text());
  const sql = admin();
  try {
    const [row] = await sql<{ household_id: string }[]>`
      select household_id from public.household_members where user_id = ${session.user.id}`;
    assert(row, 'the new household has a membership');
    return {
      id: session.user.id,
      email,
      token: session.access_token,
      householdId: row.household_id,
    };
  } finally {
    await sql.end();
  }
}

/**
 * What the user's browser does with the authorization URL: the front, then Supabase's authorize,
 * then the consent page, where the user approves (the app calls the same endpoint). Returns the
 * consent details Supabase showed and the callback's query.
 */
async function consent(url: URL, user: User) {
  const front = await routed(url, { redirect: 'manual' });
  assertEquals(front.status, 302, await front.clone().text());
  const authorize = locationOf(front);
  const supabase = await fetch(authorize, { redirect: 'manual' });
  await supabase.body?.cancel();
  const page = locationOf(supabase);
  const id = page.searchParams.get('authorization_id');
  assert(id, `consent page: ${page}`);
  const headers = {
    apikey: env('SUPABASE_ANON_KEY'),
    authorization: `Bearer ${user.token}`,
    'content-type': 'application/json',
  };
  const details = await (await fetch(`${api()}/auth/v1/oauth/authorizations/${id}`, { headers }))
    .json();
  // A client the user already granted skips the consent: Supabase answers with the redirect.
  const approved = details.redirect_url ? details : await (await fetch(
    `${api()}/auth/v1/oauth/authorizations/${id}/consent`,
    { method: 'POST', headers, body: JSON.stringify({ action: 'approve' }) },
  )).json();
  return { authorize, details, callback: new URL(approved.redirect_url).searchParams };
}

/** Connects through the whole OAuth flow; returns the connected client and what it went through. */
async function connect(provider: Provider, user: User) {
  const first = modernClient();
  // A client finishes on the transport that got the 401, which knows the metadata it named.
  const opening = transport(provider);
  let unauthorized = false;
  try {
    await first.connect(opening);
  } catch (e) {
    unauthorized = e instanceof UnauthorizedError;
    if (!unauthorized) throw e;
  }
  assert(unauthorized && provider.authorizationUrl, 'the SDK asked for authorization');
  const flow = await consent(provider.authorizationUrl, user);
  assertEquals(flow.callback.get('iss'), null, 'no foreign issuer in the authorization response');
  const code = flow.callback.get('code');
  assert(code, 'the callback carries a code');
  await opening.finishAuth(code);
  const client = modernClient();
  await client.connect(transport(provider));
  return { client, flow };
}

/** The Supabase client's name and redirect URIs, as the consent page would show them. */
async function authClient(id: string) {
  const key = secretKeyFromEnv();
  const res = await fetch(`${api()}/auth/v1/admin/oauth/clients/${id}`, {
    headers: { apikey: key, authorization: `Bearer ${key}` },
  });
  return await res.json() as { client_name: string; redirect_uris: string[] };
}

async function cleanUp(user: User | undefined, documentUrls: string[], dcrClients: string[]) {
  const sql = admin();
  try {
    const mapped = await sql<{ auth_client_id: string }[]>`
      delete from public.oauth_cimd_clients where client_id = any(${documentUrls})
      returning auth_client_id`;
    const ids = [...mapped.map((r) => r.auth_client_id), ...dcrClients];
    if (ids.length) await sql`delete from auth.oauth_clients where id = any(${ids}::uuid[])`;
    // The hosts' hourly counts go too: a third run of this file within the hour would be refused.
    const counted = documentUrls.map((url) => new URL(url).host)
      .flatMap((host) => [`new:${host}`, `fetch:${host}`]);
    await sql`delete from public.oauth_cimd_rate where key = any(${counted})`;
    if (user) {
      await sql`delete from public.households where id = ${user.householdId}`;
      await sql`delete from auth.users where id = ${user.id}`;
    }
  } finally {
    await sql.end();
  }
}

Deno.test({
  name: 'CIMD: a 2026 client signs in with its document URL as client_id and uses the tools',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const documentUrl = `https://client.example/${crypto.randomUUID()}/mcp.json`;
    documents.set(documentUrl, {
      client_id: documentUrl,
      client_name: 'Example Agent',
      redirect_uris: [CALLBACK],
      token_endpoint_auth_method: 'none',
    });
    let user: User | undefined;
    try {
      user = await signUp();
      const provider = new Provider(documentUrl);
      const { client, flow } = await connect(provider, user);
      const authorizationUrl = provider.authorizationUrl;
      assert(authorizationUrl, 'the SDK asked for authorization');

      assertEquals(authorizationUrl.searchParams.get('client_id'), documentUrl);
      assertEquals(
        `${authorizationUrl.origin}${authorizationUrl.pathname}`,
        `${mcpUrl()}/oauth/authorize`,
      );
      const mapped = flow.authorize.searchParams.get('client_id');
      assert(mapped, 'the front sent a client_id on');
      assertNotEquals(mapped, documentUrl);
      assertEquals(flow.details.client.name, 'Example Agent', 'the consent page names the client');
      assertEquals(flow.details.redirect_uri, CALLBACK);
      assertEquals(provider.client?.client_id, documentUrl, 'no dynamic registration');

      const tools = await client.listTools();
      assert(tools.tools.some((t) => t.name === 'add_items'));
      const listed = await client.callTool({ name: 'list_items', arguments: {} });
      assertEquals(listed.isError, undefined, JSON.stringify(listed));
      await client.close();

      // The refresh goes through the front too, mapped to the same Supabase client.
      const refreshToken = provider.saved?.refresh_token;
      assert(refreshToken, 'the SDK saved a refresh token');
      const refreshed = await routed(`${mcpUrl()}/oauth/token`, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: refreshToken,
          client_id: documentUrl,
        }),
      });
      const tokens = await refreshed.json();
      assertEquals(refreshed.status, 200, JSON.stringify(tokens));
      assert(tokens.access_token);

      // A changed document updates the same Supabase client once the cached copy is stale.
      documents.set(documentUrl, {
        ...documents.get(documentUrl),
        client_name: 'Example Agent 2',
        redirect_uris: [CALLBACK, 'http://localhost:8976/callback'],
      });
      const before = fetches;
      const cached = await consent(authorizationUrl, user);
      assertEquals(fetches, before, 'a fresh document is not fetched again');
      assertEquals(cached.authorize.searchParams.get('client_id'), mapped);
      assertEquals((await authClient(mapped)).client_name, 'Example Agent');
      const sql = admin();
      try {
        await sql`update public.oauth_cimd_clients set fresh_until = now() - interval '1 second'
          where client_id = ${documentUrl}`;
      } finally {
        await sql.end();
      }
      const updated = await consent(authorizationUrl, user);
      assertEquals(fetches, before + 1);
      assertEquals(updated.authorize.searchParams.get('client_id'), mapped, 'same client');
      assertEquals(await authClient(mapped), {
        ...await authClient(mapped),
        client_name: 'Example Agent 2',
        redirect_uris: [CALLBACK, 'http://localhost:8976/callback'],
      });
      assert(updated.callback.get('code'), 'the granted client signs in again without consent');
    } finally {
      await cleanUp(user, [documentUrl], []);
    }
  },
});

Deno.test({
  name: 'CIMD: a redirect_uri outside the document is refused before Supabase sees it',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const documentUrl = `https://client.example/${crypto.randomUUID()}/mcp.json`;
    documents.set(documentUrl, {
      client_id: documentUrl,
      client_name: 'Narrow',
      redirect_uris: ['http://127.0.0.1:1/only'],
    });
    try {
      const res = await routed(
        `${mcpUrl()}/oauth/authorize?${new URLSearchParams({
          response_type: 'code',
          client_id: documentUrl,
          redirect_uri: CALLBACK,
          code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          code_challenge_method: 'S256',
        })}`,
        { redirect: 'manual' },
      );
      assertEquals(res.status, 400);
      assertEquals((await res.json()).error, 'invalid_request');
    } finally {
      await cleanUp(undefined, [documentUrl], []);
    }
  },
});

Deno.test({
  name: 'CIMD: over its hourly limits a host gets no new client, then no fetch',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const host = `${crypto.randomUUID()}.example`;
    const documentUrl = `https://${host}/mcp.json`;
    documents.set(documentUrl, {
      client_id: documentUrl,
      client_name: 'Limited',
      redirect_uris: [CALLBACK],
    });
    const authorize = () =>
      routed(
        `${mcpUrl()}/oauth/authorize?${new URLSearchParams({
          response_type: 'code',
          client_id: documentUrl,
          redirect_uri: CALLBACK,
          code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          code_challenge_method: 'S256',
        })}`,
        { redirect: 'manual' },
      );
    const sql = admin();
    try {
      await sql`insert into public.oauth_cimd_rate (key, window_start, hits)
        values (${`new:${host}`}, date_trunc('hour', now()), 5)`;
      const before = fetches;
      const refusedNew = await authorize();
      assertEquals(refusedNew.status, 503);
      assertEquals((await refusedNew.json()).error, 'temporarily_unavailable');
      assertEquals(fetches, before + 1, 'fetched, but not registered');
      assertEquals(
        (await sql`select 1 from public.oauth_cimd_clients where client_id = ${documentUrl}`)
          .length,
        0,
      );
      await sql`insert into public.oauth_cimd_rate (key, window_start, hits)
        values (${`fetch:${host}`}, date_trunc('hour', now()), 30)
        on conflict (key, window_start) do update set hits = 30`;
      const refusedFetch = await authorize();
      assertEquals(refusedFetch.status, 503);
      await refusedFetch.body?.cancel();
      assertEquals(fetches, before + 1, 'no fetch over the limit');
    } finally {
      await sql`delete from public.oauth_cimd_rate where key in (${`new:${host}`}, ${`fetch:${host}`})`;
      await sql.end();
      await cleanUp(undefined, [documentUrl], []);
    }
  },
});

Deno.test({
  name: 'CIMD: a known client signs in while strangers have used up the host and overall limits',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const host = `${crypto.randomUUID()}.example`;
    const documentUrl = `https://${host}/mcp.json`;
    const strangerUrl = `https://${host}/other.json`;
    for (const url of [documentUrl, strangerUrl]) {
      documents.set(url, { client_id: url, client_name: 'Known', redirect_uris: [CALLBACK] });
    }
    const authorize = (clientId: string) =>
      routed(
        `${mcpUrl()}/oauth/authorize?${new URLSearchParams({
          response_type: 'code',
          client_id: clientId,
          redirect_uri: CALLBACK,
          code_challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          code_challenge_method: 'S256',
        })}`,
        { redirect: 'manual' },
      );
    // The 31 requests at the end count in one hourly window: start after the turn of the hour.
    const untilTheHour = 3_600_000 - Date.now() % 3_600_000;
    if (untilTheHour < 30_000) await new Promise((r) => setTimeout(r, untilTheHour + 1_000));
    const sql = admin();
    // Limits are used up in this window and the next, should the hour turn all the same.
    const [{ hour } = { hour: '' }] = await sql<{ hour: string }[]>`
      select date_trunc('hour', now())::text as hour`;
    const useUp = (key: string, hits: number) =>
      sql`insert into public.oauth_cimd_rate (key, window_start, hits)
        values (${key}, ${hour}::timestamptz, ${hits}),
          (${key}, ${hour}::timestamptz + interval '1 hour', ${hits})
        on conflict (key, window_start) do update set hits = excluded.hits`;
    const expire = () =>
      sql`update public.oauth_cimd_clients set fresh_until = now() - interval '1 minute'
        where client_id = ${documentUrl}`;
    const [overall] = await sql<{ hits: number }[]>`select hits from public.oauth_cimd_rate
      where key = 'fetch:all' and window_start = ${hour}::timestamptz`;
    try {
      const first = await authorize(documentUrl);
      assertEquals(first.status, 302);
      await expire();
      await useUp(`fetch:${host}`, 30);
      await useUp('fetch:all', 600);
      const before = fetches;

      const known = await authorize(documentUrl);
      assertEquals(known.status, 302, 'the known client still signs in');
      assertEquals(fetches, before + 1, 'from its document, fetched again');

      const stranger = await authorize(strangerUrl);
      assertEquals(stranger.status, 503, 'a new URL on that host is still refused');
      await stranger.body?.cancel();
      assertEquals(fetches, before + 1);

      // Parallel sign-ins at the moment the document went stale each fetch it, up to the limit.
      await expire();
      const burst = await Promise.all(Array.from({ length: 30 }, () => authorize(documentUrl)));
      assertEquals(burst.map((res) => res.status), Array.from({ length: 30 }, () => 302));
      await expire();
      const afterBurst = await authorize(documentUrl);
      assertEquals(afterBurst.status, 302, 'fetches that worked do not use the limit up');

      await expire();
      documents.delete(documentUrl);
      const failed = fetches;
      for (let n = 1; n <= 31; n++) {
        const res = await authorize(documentUrl);
        assertEquals(res.status, n === 31 ? 503 : 400, `fetch ${n} of a document that is gone`);
        await res.body?.cancel();
      }
      assertEquals(
        fetches,
        failed + 30,
        'its own limit holds while the document cannot be fetched',
      );
    } finally {
      try {
        await sql`delete from public.oauth_cimd_rate
          where key in (${`fetch:${host}`}, ${`fetch:${documentUrl}`}, ${`new:${host}`})`;
        await sql`delete from public.oauth_cimd_rate
          where key = 'fetch:all' and window_start >= ${hour}::timestamptz`;
        if (overall) {
          await sql`insert into public.oauth_cimd_rate (key, window_start, hits)
            values ('fetch:all', ${hour}::timestamptz, ${overall.hits})`;
        }
      } finally {
        await sql.end();
        await cleanUp(undefined, [documentUrl, strangerUrl], []);
      }
    }
  },
});

Deno.test({
  name: 'DCR still works for a 2026 client without a document, through the same front',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    let user: User | undefined;
    const provider = new Provider();
    try {
      user = await signUp();
      const { client, flow } = await connect(provider, user);
      const registered = provider.client?.client_id;
      assert(registered && !registered.startsWith('https://'), 'registered dynamically');
      assertEquals(flow.authorize.searchParams.get('client_id'), registered, 'passed through');
      assert((await client.listTools()).tools.length > 0);
      await client.close();
    } finally {
      await cleanUp(user, [], provider.client?.client_id ? [provider.client.client_id] : []);
    }
  },
});
