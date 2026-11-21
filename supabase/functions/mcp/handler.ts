// HTTP face of the MCP server: CORS, Protected Resource Metadata (RFC 9728), Origin checks,
// bearer authentication, then MCP over streamable HTTP for both protocol eras.
import {
  createMcpHandler,
  localhostAllowedOrigins,
  originValidationResponse,
} from '@modelcontextprotocol/server';
import {
  type Auth,
  authenticate,
  AuthError,
  discoverIssuer,
  secretKeyFromEnv,
  sha256Hex,
  supabaseUrl,
} from '../_shared/auth.ts';
import { rowBusy, serviceDb } from '../_shared/db.ts';
import { requirePremiumWith } from '../_shared/premium.ts';
import { userEvents } from '../_shared/user_events.ts';
import { fetchClientMetadata } from './cimd.ts';
import {
  LIMITS,
  lookupClient,
  resolveClient,
  supabaseClientAdmin,
  withinLimits,
} from './cimd_clients.ts';
import { type OAuthDeps, oauthRoute } from './oauth.ts';
import { telemetry } from './telemetry.ts';
import { buildServer, langOf, reportToolCalls } from './tools.ts';

/**
 * Per user, over all MCP requests (job 336, like the API's per key, docs/MCP.md "Limits"): a token
 * bucket of BURST refilled at PER_MINUTE a minute, and PER_DAY a UTC day.
 */
export const BURST = 20;
export const PER_MINUTE = 60;
export const PER_DAY = 1000;

const PRM_SUFFIXES = ['/.well-known/oauth-protected-resource', '/oauth-protected-resource'];

/**
 * Protected Resource Metadata for 2026-era clients: the same resource, with the front in oauth.ts
 * (Client ID Metadata Documents) as its authorization server. 2025-era clients keep Supabase Auth,
 * so the client registrations they keyed by its issuer stay valid (DECISIONS, job 94).
 */
const CIMD_PRM_PATH = '/.well-known/oauth-protected-resource/cimd';

/** The first protocol revision without `initialize`; requests from it on are 2026-era. */
const MODERN_SINCE = '2026-07-28';

/**
 * Authorization Server Metadata (RFC 8414) and OpenID discovery paths under the MCP URL. A client
 * that cannot read the Protected Resource Metadata treats the MCP URL as the authorization server
 * and probes these (MCP TypeScript SDK `buildDiscoveryUrls`). On supabase.co the root-level probes
 * (`/.well-known/...` + path) hit Supabase's API gateway, which answers 401 without an apikey, so
 * only the path-appended one reaches this function. Serving Supabase Auth's metadata here lets a
 * connector on the supabase.co URL find the token endpoint and refresh (2026-10-31 incident).
 */
const AS_SUFFIXES = [
  '/.well-known/oauth-authorization-server',
  '/.well-known/openid-configuration',
];

/** Scopes Supabase's OAuth server knows; it rejects any other. The tools need none of them. */
const SCOPES = ['openid', 'email'];

const cors: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
  'access-control-allow-headers':
    'authorization, content-type, accept, mcp-protocol-version, mcp-method, mcp-name, ' +
    'mcp-session-id, last-event-id',
  'access-control-expose-headers': 'www-authenticate, mcp-session-id, retry-after',
};

export type Endpoints = {
  /** The MCP endpoint a client should use, e.g. https://<ref>.supabase.co/functions/v1/mcp. */
  resource: string;
  metadata: string;
  authorizationServer: string;
  /** The 2026-era metadata URL and its authorization server, the front at <resource>/oauth. */
  cimdMetadata: string;
  cimdAuthorizationServer: string;
};

export type Deps = {
  /** The function's own endpoints on the project host. */
  endpoints: () => Promise<Endpoints>;
  /** Origins of the Vercel proxy in front of the function (mcp-proxy/), e.g. mcp.hummlist.com and mcp.snacklist.app. */
  publicOrigins: () => string[];
  /** Supabase Auth's Authorization Server Metadata (RFC 8414), served unchanged. */
  authServerMetadata: () => Promise<Record<string, unknown>>;
  /** The front's client mapping and token forwarding; it reads authServerMetadata above. */
  oauth: Omit<OAuthDeps, 'authServerMetadata'>;
  authenticate: (req: Request) => Promise<Auth>;
  /**
   * Counts one request for the user: null when it may go ahead, else seconds to wait. Throws
   * AuthError user_deleted when the account went after authentication.
   */
  takeCall: (userId: string) => Promise<number | null>;
  serve: (req: Request, auth: Auth) => Promise<Response>;
  allowedOriginHosts: () => string[];
};

export async function handle(req: Request, deps: Deps = productionDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  const direct = await deps.endpoints();
  const publicOrigins = deps.publicOrigins();
  const publicOrigin = publicOriginFor(req, publicOrigins);
  const endpoints = publicOrigin ? proxied(publicOrigin, direct) : direct;
  const path = new URL(req.url).pathname;
  const subpath = path.replace(/^(?:\/functions\/v1)?\/mcp(?=\/|$)/, '').replace(/\/$/, '');

  const cimdPrm = subpath === CIMD_PRM_PATH;
  if (cimdPrm || PRM_SUFFIXES.some((suffix) => path.endsWith(suffix))) {
    if (req.method !== 'GET') return withCors(new Response(null, { status: 405 }));
    // A 2026-era client that rediscovers without the 401's hint names its version here too.
    const front = cimdPrm || isModern(req);
    return withCors(Response.json({
      resource: endpoints.resource,
      authorization_servers: [
        front ? endpoints.cimdAuthorizationServer : endpoints.authorizationServer,
      ],
      scopes_supported: SCOPES,
      bearer_methods_supported: ['header'],
      resource_name: 'Snacklist',
      resource_documentation:
        'https://github.com/trost-systems/family-groceries/blob/main/docs/MCP.md',
    }, { headers: { vary: 'mcp-protocol-version' } }));
  }

  try {
    const front = await oauthRoute(req, subpath, endpoints.cimdAuthorizationServer, {
      ...deps.oauth,
      authServerMetadata: deps.authServerMetadata,
    });
    if (front) return withCors(front);
  } catch (e) {
    console.error('mcp oauth front:', e);
    return withCors(Response.json(
      { error: 'temporarily_unavailable', error_description: 'authorization server unavailable' },
      { status: 502 },
    ));
  }

  if (AS_SUFFIXES.some((suffix) => path.endsWith(suffix))) {
    if (req.method !== 'GET') return withCors(new Response(null, { status: 405 }));
    try {
      return withCors(Response.json(await deps.authServerMetadata()));
    } catch {
      return withCors(Response.json(
        { error: 'temporarily_unavailable', error_description: 'auth discovery failed' },
        { status: 502 },
      ));
    }
  }

  const rejected = originValidationResponse(req, [
    ...localhostAllowedOrigins(),
    new URL(direct.resource).hostname,
    ...publicOrigins.map((origin) => new URL(origin).hostname),
    ...deps.allowedOriginHosts(),
  ]);
  if (rejected) return withCors(rejected);

  let auth: Auth;
  let retryAfter: number | null;
  try {
    auth = await deps.authenticate(req);
    if (auth.via === 'session') {
      throw new AuthError(
        'invalid_token',
        'App-Sitzungen gelten hier nicht: per OAuth verbinden oder einen Zugriffstoken nutzen.',
      );
    }
    retryAfter = await deps.takeCall(auth.userId);
  } catch (e) {
    if (rowBusy(e)) return withCors(refused(503, 'Temporarily unavailable. Retry later.', 1));
    if (!(e instanceof AuthError)) throw e;
    return withCors(challenge(e, isModern(req) ? endpoints.cimdMetadata : endpoints.metadata));
  }
  if (retryAfter !== null) {
    return withCors(refused(429, 'Rate limit reached. Retry later.', retryAfter));
  }
  return withCors(await deps.serve(req, auth));
}

/** Query markers mcp-proxy/vercel.json adds, mapped to the public origin that host should advertise. */
const PROXY_ORIGINS: Record<string, string> = {
  'mcp-hummlist': 'https://mcp.hummlist.com',
  'mcp-snacklist': 'https://mcp.snacklist.app',
};

const DEFAULT_PUBLIC_ORIGINS = Object.values(PROXY_ORIGINS);

/**
 * The allow-listed public origin this request should advertise, if it came through the proxy.
 * The query marker is what works in production (Supabase's gateway replaces x-forwarded-host);
 * the forwarded host is still accepted for the same allow-listed names. A spoofed signal can at
 * most make the function advertise one of those URLs.
 */
function publicOriginFor(req: Request, origins: string[]): string | undefined {
  const via = new URL(req.url).searchParams.get('via');
  if (via !== null) {
    const marked = PROXY_ORIGINS[via];
    if (marked !== undefined) {
      const listed = origins.find((origin) => origin === marked);
      if (listed !== undefined) return listed;
      // MCP_PUBLIC_URL replaces the default list with one origin; the historical marker still
      // means the request came through that (only) proxy.
      if (via === 'mcp-hummlist' && origins.length === 1) return origins[0];
    }
  }
  const [forwarded] = req.headers.get('x-forwarded-host')?.split(',') ?? [];
  const host = forwarded?.trim().toLowerCase().replace(/:\d+$/, '');
  if (!host) return undefined;
  return origins.find((origin) => new URL(origin).hostname === host);
}

/**
 * The caller's address for per-address limits. Through the proxy Supabase's gateway sees
 * Vercel, so X-Real-IP would put every proxied client in one bucket; Vercel sets
 * x-vercel-forwarded-for to the client's address and overwrites a client's own forwarding
 * headers. Directly on supabase.co the gateway's X-Real-IP is the client (X-Forwarded-For is
 * client-forgeable there). A direct caller adding the proxy marker can pick its own key, which
 * only gets around this limit, as many addresses would; Supabase's own limit still applies.
 */
export function clientAddress(req: Request, proxied: boolean): string {
  const first = (name: string) => req.headers.get(name)?.split(',')[0]?.trim() || undefined;
  return (proxied ? first('x-vercel-forwarded-for') : undefined) ?? first('x-real-ip') ??
    first('x-forwarded-for') ?? 'unknown';
}

/** The proxy serves the function at its root and the metadata at the RFC 9728 root path. */
function proxied(publicOrigin: string, direct: Endpoints): Endpoints {
  return {
    resource: publicOrigin,
    metadata: `${publicOrigin}${PRM_SUFFIXES[0]}`,
    authorizationServer: direct.authorizationServer,
    cimdMetadata: `${publicOrigin}${CIMD_PRM_PATH}`,
    cimdAuthorizationServer: `${publicOrigin}/oauth`,
  };
}

/** Whether the request names a 2026-era protocol revision (MCP-Protocol-Version). */
function isModern(req: Request): boolean {
  const version = req.headers.get('mcp-protocol-version') ?? '';
  return /^\d{4}-\d{2}-\d{2}$/.test(version) && version >= MODERN_SINCE;
}

/** 401 (or 403 without a household) pointing the client at the Protected Resource Metadata. */
function challenge(error: AuthError, metadata: string): Response {
  const params = [
    `resource_metadata="${metadata}"`,
    `scope="${SCOPES.join(' ')}"`,
    ...(error.reason === 'missing_token' ? [] : [
      `error="${error.reason === 'no_household' ? 'insufficient_scope' : 'invalid_token'}"`,
      `error_description="${headerSafe(error.message)}"`,
    ]),
  ];
  return Response.json(
    { error: error.reason, error_description: error.message },
    { status: error.status, headers: { 'www-authenticate': `Bearer ${params.join(', ')}` } },
  );
}

/** A JSON-RPC error without an id: the request was not read. */
function refused(status: 429 | 503, message: string, retryAfter: number): Response {
  return Response.json(
    { jsonrpc: '2.0', id: null, error: { code: -32000, message } },
    { status, headers: { 'retry-after': String(retryAfter) } },
  );
}

const UMLAUTS: Record<string, string> = {
  ä: 'ae',
  ö: 'oe',
  ü: 'ue',
  Ä: 'Ae',
  Ö: 'Oe',
  Ü: 'Ue',
  ß: 'ss',
  '"': "'",
};

/** RFC 6750 error_description charset; the hosted gateway drops a header with other bytes. */
function headerSafe(text: string): string {
  return text.replace(/[äöüÄÖÜß"]/g, (c) => UMLAUTS[c] ?? c).replace(
    /[^\x20-\x21\x23-\x5b\x5d-\x7e]/g,
    '',
  );
}

function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [key, value] of Object.entries(cors)) headers.set(key, value);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

async function projectEndpoints(): Promise<Endpoints> {
  const { issuer } = await discoverIssuer();
  const resource = `${issuer.replace(/\/auth\/v1\/?$/, '')}/functions/v1/mcp`;
  return {
    resource,
    metadata: `${resource}${PRM_SUFFIXES[0]}`,
    authorizationServer: issuer,
    cimdMetadata: `${resource}${CIMD_PRM_PATH}`,
    cimdAuthorizationServer: `${resource}/oauth`,
  };
}

/**
 * Public proxy origins. `MCP_PUBLIC_URL` (the proxy serves no path) replaces the defaults
 * with that single origin; otherwise both mcp.hummlist.com and mcp.snacklist.app are listed.
 */
export function publicOriginsFromEnv(): string[] {
  const fromEnv = Deno.env.get('MCP_PUBLIC_URL');
  if (fromEnv) return [new URL(fromEnv).origin];
  return [...DEFAULT_PUBLIC_ORIGINS];
}

/** First public origin, kept for callers and tests that only need the default. */
export function publicOriginFromEnv(): string {
  const [origin] = publicOriginsFromEnv();
  if (origin === undefined) throw new Error('MCP public origins list is empty');
  return origin;
}

let asMetadataCache: Promise<Record<string, unknown>> | undefined;

/** Supabase Auth's own metadata document, fetched once per isolate (retried after a failure). */
function supabaseAuthServerMetadata(): Promise<Record<string, unknown>> {
  asMetadataCache ??= (async () => {
    const internal = supabaseUrl();
    const res = await fetch(`${internal}/auth/v1/.well-known/oauth-authorization-server`);
    if (!res.ok) throw new Error(`auth server metadata: ${res.status}`);
    const body = await res.json() as Record<string, unknown>;
    if (typeof body.token_endpoint !== 'string') {
      throw new Error('auth server metadata: no token_endpoint');
    }
    return body;
  })().catch((e) => {
    asMetadataCache = undefined;
    throw e;
  });
  return asMetadataCache;
}

const requirePremium = requirePremiumWith(telemetry);
const sendEvent = userEvents(telemetry);

export const productionDeps: Deps = {
  endpoints: projectEndpoints,
  authServerMetadata: supabaseAuthServerMetadata,
  oauth: {
    resolveClient: (url) =>
      resolveClient(url, {
        sql: serviceDb,
        admin: supabaseClientAdmin(supabaseUrl(), secretKeyFromEnv()),
        fetchDocument: (u) =>
          fetchClientMetadata(u, {
            fetch,
            resolve: async (host) => [
              ...await Deno.resolveDns(host, 'A').catch(() => []),
              ...await Deno.resolveDns(host, 'AAAA').catch(() => []),
            ],
          }),
      }),
    lookupClient: (url) => lookupClient(url, serviceDb()),
    allowTokenRequest: async (req) => {
      const address = clientAddress(
        req,
        publicOriginFor(req, publicOriginsFromEnv()) !== undefined,
      );
      return await withinLimits(serviceDb(), [[
        `token:${await sha256Hex(address)}`,
        LIMITS.tokenPerAddress,
      ]]);
    },
    forwardToken: (body, authorization) =>
      fetch(`${supabaseUrl()}/auth/v1/oauth/token`, {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          accept: 'application/json',
          ...(authorization ? { authorization } : {}),
        },
        body,
      }),
  },
  publicOrigins: publicOriginsFromEnv,
  authenticate,
  takeCall: async (userId) => {
    try {
      const [row] = await serviceDb()<{ retry: number | null }[]>`
        select public.mcp_take_call(${userId}::uuid, ${BURST}, ${PER_MINUTE}, ${PER_DAY}) as retry`;
      return row?.retry ?? null;
    } catch (e) {
      if ((e as { code?: unknown })?.code === 'P0002') {
        throw new AuthError('user_deleted', 'Dieses Konto ist gelöscht.');
      }
      throw e;
    }
  },
  serve: (req, auth) =>
    createMcpHandler(() =>
      buildServer(
        auth,
        (householdId) => requirePremium({ userId: auth.userId, householdId }, 'mcp'),
        reportToolCalls(sendEvent, auth.userId),
        langOf(req.headers.get('accept-language')),
      )
    ).fetch(req),
  allowedOriginHosts: () =>
    (Deno.env.get('MCP_ALLOWED_ORIGIN_HOSTS') ?? '').split(',').map((h) => h.trim()).filter(
      Boolean,
    ),
};
