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
  supabaseUrl,
} from '../_shared/auth.ts';
import { requirePremiumWith } from '../_shared/premium.ts';
import { telemetry } from './telemetry.ts';
import { buildServer, langOf } from './tools.ts';

const PRM_SUFFIXES = ['/.well-known/oauth-protected-resource', '/oauth-protected-resource'];

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
  'access-control-expose-headers': 'www-authenticate, mcp-session-id',
};

export type Endpoints = {
  /** The MCP endpoint a client should use, e.g. https://<ref>.supabase.co/functions/v1/mcp. */
  resource: string;
  metadata: string;
  authorizationServer: string;
};

export type Deps = {
  /** The function's own endpoints on the project host. */
  endpoints: () => Promise<Endpoints>;
  /** Origin of the Vercel proxy in front of the function (mcp-proxy/), e.g. https://mcp.hummlist.com. */
  publicOrigin: () => string;
  /** Supabase Auth's Authorization Server Metadata (RFC 8414), served unchanged. */
  authServerMetadata: () => Promise<Record<string, unknown>>;
  authenticate: (req: Request) => Promise<Auth>;
  serve: (req: Request, auth: Auth) => Promise<Response>;
  allowedOriginHosts: () => string[];
};

export async function handle(req: Request, deps: Deps = defaultDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  const direct = await deps.endpoints();
  const publicOrigin = deps.publicOrigin();
  const endpoints = viaProxy(req, publicOrigin) ? proxied(publicOrigin, direct) : direct;
  const path = new URL(req.url).pathname;

  if (PRM_SUFFIXES.some((suffix) => path.endsWith(suffix))) {
    if (req.method !== 'GET') return withCors(new Response(null, { status: 405 }));
    return withCors(Response.json({
      resource: endpoints.resource,
      authorization_servers: [endpoints.authorizationServer],
      scopes_supported: SCOPES,
      bearer_methods_supported: ['header'],
      resource_name: 'Hummlist',
      resource_documentation:
        'https://github.com/trost-systems/family-groceries/blob/main/docs/MCP.md',
    }));
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
    new URL(publicOrigin).hostname,
    ...deps.allowedOriginHosts(),
  ]);
  if (rejected) return withCors(rejected);

  let auth: Auth;
  try {
    auth = await deps.authenticate(req);
    if (auth.via === 'session') {
      throw new AuthError(
        'invalid_token',
        'App-Sitzungen gelten hier nicht: per OAuth verbinden oder einen Zugriffstoken nutzen.',
      );
    }
  } catch (e) {
    if (!(e instanceof AuthError)) throw e;
    return withCors(challenge(e, endpoints));
  }
  return withCors(await deps.serve(req, auth));
}

/** The query parameter mcp-proxy/vercel.json adds to every request it forwards. */
const PROXY_MARKER = ['via', 'mcp-hummlist'] as const;

/**
 * Whether the request came through the proxy: its marker, or the public host as the forwarded
 * host (a gateway may overwrite that header). Either only selects the allow-listed public URL, so
 * a spoofed one can at most make the function advertise that URL.
 */
function viaProxy(req: Request, publicOrigin: string): boolean {
  if (new URL(req.url).searchParams.get(PROXY_MARKER[0]) === PROXY_MARKER[1]) return true;
  const [forwarded] = req.headers.get('x-forwarded-host')?.split(',') ?? [];
  return forwarded?.trim().toLowerCase().replace(/:\d+$/, '') === new URL(publicOrigin).hostname;
}

/** The proxy serves the function at its root and the metadata at the RFC 9728 root path. */
function proxied(publicOrigin: string, direct: Endpoints): Endpoints {
  return {
    resource: publicOrigin,
    metadata: `${publicOrigin}${PRM_SUFFIXES[0]}`,
    authorizationServer: direct.authorizationServer,
  };
}

/** 401 (or 403 without a household) pointing the client at the Protected Resource Metadata. */
function challenge(error: AuthError, endpoints: Endpoints): Response {
  const params = [
    `resource_metadata="${endpoints.metadata}"`,
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
  };
}

/** The origin of `MCP_PUBLIC_URL` (the proxy serves no path), default https://mcp.hummlist.com. */
export function publicOriginFromEnv(): string {
  return new URL(Deno.env.get('MCP_PUBLIC_URL') || 'https://mcp.hummlist.com').origin;
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

const defaultDeps: Deps = {
  endpoints: projectEndpoints,
  authServerMetadata: supabaseAuthServerMetadata,
  publicOrigin: publicOriginFromEnv,
  authenticate,
  serve: (req, auth) =>
    createMcpHandler(() =>
      buildServer(
        auth,
        (householdId) => requirePremium({ userId: auth.userId, householdId }, 'mcp'),
        langOf(req.headers.get('accept-language')),
      )
    ).fetch(req),
  allowedOriginHosts: () =>
    (Deno.env.get('MCP_ALLOWED_ORIGIN_HOSTS') ?? '').split(',').map((h) => h.trim()).filter(
      Boolean,
    ),
};
