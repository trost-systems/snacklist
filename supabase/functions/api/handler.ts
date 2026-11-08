// HTTP face of the API: CORS, the key and its limits (public.api_begin), the route table, scopes,
// the Premium gate, strict input, then the operation as the key's member, idempotent for POSTs.
// Every answer carries X-Request-Id and, once the limits are known, X-RateLimit-*.
import { PAT_PREFIX, sha256Hex } from '../_shared/auth.ts';
import { asUser, asUserWithin, oneRow, serviceDb } from '../_shared/db.ts';
import { ToolError } from '../_shared/list.ts';
import { type Access, requirePremiumWith } from '../_shared/premium.ts';
import { ApiError, internalError, noSuchEndpoint, unavailable } from './errors.ts';
import {
  AUTH_FAILURE_WINDOW_SECONDS,
  AUTH_FAILURES,
  BODY_BYTES,
  BURST,
  IDEMPOTENCY_HOURS,
  PER_DAY,
  PER_MINUTE,
} from './limits.ts';
import { operations, type Raw, type Run } from './operations.ts';
import { type Route, routes, type Scope } from './routes.ts';
import { telemetry } from './telemetry.ts';

/** An active API key: who it acts as and what it may do. */
export type Key = { tokenId: string; userId: string; householdId: string; scopes: Scope[] };

/** Where the caller stands against the limit closest to running out (docs/API.md "Limits"). */
export type Rate = { limit: number; remaining: number; reset: number };

/** public.api_begin's outcome for one request; `disabled` while app_switches.public_api is off. */
export type Begin =
  | { outcome: 'disabled' }
  | { outcome: 'blocked'; rate: Rate; retryAfter: number }
  | { outcome: 'invalid'; rate: Rate }
  | { outcome: 'limited'; rate: Rate; retryAfter: number; key: Key }
  | { outcome: 'ok'; rate: Rate; key: Key };

export type Execution = {
  key: Key;
  run: Run;
  idempotency: { key: string; requestHash: string } | null;
};

export type Executed = { status: number; body: unknown; replayed: boolean };

export type Deps = {
  /** Checks the address's failure budget, the key (by SHA-256) and its limits; takes a request. */
  begin: (tokenHash: string | null, ipHash: string) => Promise<Begin>;
  premium: (key: Key) => Promise<Access>;
  /** Runs the operation as the key's member; with an Idempotency-Key, at most once per request. */
  execute: (execution: Execution) => Promise<Executed>;
  report: (error: unknown) => void;
  log: (line: Record<string, unknown>) => void;
};

const cors: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PATCH, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, idempotency-key',
  'access-control-expose-headers':
    'x-ratelimit-limit, x-ratelimit-remaining, x-ratelimit-reset, retry-after, x-request-id, ' +
    'idempotent-replayed',
};

type Reply = { status: number; body: unknown; headers: Record<string, string> };

/** What the request log may say about a request: the template and the key id, nothing else. */
type Trace = { route: string | null; tokenId: string | null };

export async function handle(req: Request, deps: Deps = defaultDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  const started = performance.now();
  const requestId = crypto.randomUUID();
  const trace: Trace = { route: null, tokenId: null };
  const reply = await serve(req, deps, trace);
  deps.log({
    fn: 'api',
    requestId,
    method: req.method,
    route: trace.route,
    status: reply.status,
    ms: Math.round(performance.now() - started),
    tokenId: trace.tokenId,
  });
  const headers = new Headers({
    ...cors,
    ...reply.headers,
    'content-type': 'application/json; charset=utf-8',
    'x-request-id': requestId,
  });
  return new Response(JSON.stringify(reply.body), { status: reply.status, headers });
}

async function serve(req: Request, deps: Deps, trace: Trace): Promise<Reply> {
  let begun: Begin;
  try {
    begun = await deps.begin(await tokenHash(req), await ipHash(req));
  } catch (e) {
    deps.report(e);
    return errorReply(unavailable());
  }
  // Switched off, the API looks absent: an unknown path's answer, no limits, nothing traced.
  if (begun.outcome === 'disabled') return errorReply(noSuchEndpoint());
  const rate = {
    'x-ratelimit-limit': String(begun.rate.limit),
    'x-ratelimit-remaining': String(begun.rate.remaining),
    'x-ratelimit-reset': String(begun.rate.reset),
  };
  let reply: Reply;
  try {
    reply = await authorized(req, deps, begun, trace);
  } catch (e) {
    reply = errorReply(asApiError(e, deps));
  }
  return { ...reply, headers: { ...rate, ...reply.headers } };
}

async function authorized(
  req: Request,
  deps: Deps,
  begun: Exclude<Begin, { outcome: 'disabled' }>,
  trace: Trace,
): Promise<Reply> {
  switch (begun.outcome) {
    case 'blocked':
      throw new ApiError(
        429,
        'auth_throttled',
        'Too many failed authentications from this address. Retry later.',
        undefined,
        { 'retry-after': String(begun.retryAfter) },
      );
    case 'invalid':
      throw /^Bearer\s+\S/i.test(req.headers.get('authorization') ?? '')
        ? new ApiError(401, 'invalid_token', 'The API key is unknown, revoked or not an API key.')
        : new ApiError(401, 'missing_token', 'Send an API key: "Authorization: Bearer fgp_...".');
    case 'limited':
      trace.tokenId = begun.key.tokenId;
      throw new ApiError(429, 'rate_limited', 'Rate limit reached. Retry later.', undefined, {
        'retry-after': String(begun.retryAfter),
      });
    case 'ok':
      break;
  }
  const { key } = begun;
  trace.tokenId = key.tokenId;

  const url = new URL(req.url);
  const { route, id } = match(req.method, routePath(url.pathname));
  trace.route = route.path;
  if (!key.scopes.includes(route.scope)) {
    throw new ApiError(403, 'insufficient_scope', `This API key lacks the ${route.scope} scope.`, {
      required: route.scope,
    });
  }

  let access: Access;
  try {
    access = await deps.premium(key);
  } catch (e) {
    deps.report(e);
    throw unavailable();
  }
  if (access === 'locked') {
    throw new ApiError(
      402,
      'premium_required',
      'This household needs Hummlist Premium to use the API. Unlock it in the Hummlist app. ' +
        'Nothing was read or changed.',
    );
  }

  const idempotencyKey = route.idempotent ? idempotencyKeyOf(req) : null;
  const raw: Raw = { id, query: queryOf(url), body: await bodyOf(req) };
  const run = operations[route.operation](raw);
  const idempotency = idempotencyKey === null ? null : {
    key: idempotencyKey,
    requestHash: await sha256Hex(
      `${req.method} ${routePath(url.pathname)}\n${canonical(raw.body ?? null)}`,
    ),
  };
  const done = await deps.execute({ key, run, idempotency });
  return {
    status: done.status,
    body: done.body,
    headers: done.replayed ? { 'idempotent-replayed': 'true' } : {},
  };
}

// Routing ------------------------------------------------------------------------------------

/** The path after the function's own prefix: hosted `/functions/v1/api/v1/...`, local `/api/v1/...`. */
export function routePath(pathname: string): string {
  const inFunctions = pathname.startsWith('/functions/v1/')
    ? pathname.slice('/functions/v1'.length)
    : pathname;
  return inFunctions === '/api' || inFunctions.startsWith('/api/')
    ? inFunctions.slice('/api'.length)
    : inFunctions;
}

const compiled = routes.map((route) => ({ route, segments: route.path.split('/') }));

/** The route for [method] and [path], with its {id}; 404 for no such path, 405 for the method. */
function match(method: string, path: string): { route: Route; id: string | null } {
  const segments = path.split('/');
  const candidates = compiled.flatMap(({ route, segments: template }) => {
    if (template.length !== segments.length) return [];
    let id: string | null = null;
    for (const [i, given] of segments.entries()) {
      const part = template[i];
      if (part === '{id}' && given !== '') id = given;
      else if (part !== given) return [];
    }
    return [{ route, id }];
  });
  if (candidates.length === 0) throw noSuchEndpoint();
  const found = candidates.find((c) => c.route.method === method);
  if (found) return found;
  throw new ApiError(
    405,
    'method_not_allowed',
    `${method} is not allowed here.`,
    undefined,
    { allow: candidates.map((c) => c.route.method).join(', ') },
  );
}

// Input --------------------------------------------------------------------------------------

/** The query as one value per name; a name given twice is a validation failure. */
function queryOf(url: URL): Record<string, string> {
  const query: Record<string, string> = {};
  const repeated: string[] = [];
  for (const [name, value] of url.searchParams) {
    if (Object.hasOwn(query, name)) repeated.push(name);
    query[name] = value;
  }
  if (repeated.length > 0) {
    throw new ApiError(400, 'validation_failed', 'The request query is not valid.', {
      issues: [...new Set(repeated)].map((name) => ({
        path: `query.${name}`,
        message: 'Given more than once',
      })),
    });
  }
  return query;
}

/** The JSON body, read up to the limit; undefined when there is none. */
async function bodyOf(req: Request): Promise<unknown> {
  if (!req.body) return undefined;
  const tooLarge = () =>
    new ApiError(413, 'payload_too_large', `The body is over ${BODY_BYTES / 1024} KiB.`);
  if (Number(req.headers.get('content-length') ?? 0) > BODY_BYTES) {
    await req.body.cancel();
    throw tooLarge();
  }
  const chunks: Uint8Array[] = [];
  let size = 0;
  const reader = req.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > BODY_BYTES) {
      await reader.cancel();
      throw tooLarge();
    }
    chunks.push(value);
  }
  if (size === 0) return undefined;
  const [type = ''] = (req.headers.get('content-type') ?? '').split(';');
  if (type.trim().toLowerCase() !== 'application/json') {
    throw new ApiError(415, 'unsupported_media_type', 'Send the body as application/json.');
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    throw new ApiError(400, 'invalid_json', 'The body is not valid JSON.');
  }
}

function idempotencyKeyOf(req: Request): string | null {
  const key = req.headers.get('idempotency-key');
  if (key === null) return null;
  if (!/^[\x21-\x7e]{1,255}$/.test(key)) {
    throw new ApiError(
      400,
      'invalid_idempotency_key',
      'The Idempotency-Key must be 1 to 255 printable ASCII characters.',
    );
  }
  return key;
}

/** JSON with object keys sorted, so the same body hashes the same however it was written. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

// Credentials --------------------------------------------------------------------------------

/** SHA-256 of a well-formed `Bearer fgp_...` token; null for anything else. */
async function tokenHash(req: Request): Promise<string | null> {
  const token = /^Bearer\s+(\S+)\s*$/i.exec(req.headers.get('authorization') ?? '')?.[1];
  return token?.startsWith(PAT_PREFIX) ? await sha256Hex(token) : null;
}

/**
 * SHA-256 of the caller's address, never the address itself. X-Real-IP is what the gateway saw:
 * hosted Supabase and the local Kong overwrite whatever a client sends in it, while hosted Supabase
 * passes X-Forwarded-For on exactly as the client wrote it (checked 2026-11-02, DECISIONS "Job
 * 73"). Without the header every caller shares one budget, so the throttle is never off.
 */
async function ipHash(req: Request): Promise<string> {
  return await sha256Hex(req.headers.get('x-real-ip')?.trim() || 'no-address');
}

// Errors -------------------------------------------------------------------------------------

function errorReply(error: ApiError): Reply {
  return { status: error.status, body: error.body, headers: error.headers };
}

const listErrors = {
  store: { not_found: 'store_not_found', ambiguous: 'ambiguous_store', label: 'Store' },
  category: { not_found: 'category_not_found', ambiguous: 'ambiguous_category', label: 'Category' },
  list: { not_found: 'list_not_found', ambiguous: 'ambiguous_list', label: 'List' },
} as const;

/** SQLSTATE classes of a database that is down, full or shutting down. */
const UNAVAILABLE_STATES = /^(08|53|57P)/;

/** The answer for anything a request threw. */
function asApiError(e: unknown, deps: Deps): ApiError {
  if (e instanceof ApiError) return e;
  if (e instanceof ToolError) {
    if (e.subject === 'item' && e.reason === 'not_found') {
      return new ApiError(404, 'item_not_found', 'No such item in this household.');
    }
    if (
      (e.subject === 'store' || e.subject === 'category' || e.subject === 'list') &&
      e.reason !== 'invalid'
    ) {
      const kind = listErrors[e.subject];
      return new ApiError(
        422,
        kind[e.reason],
        e.reason === 'not_found'
          ? `${kind.label} "${e.query}" not found.`
          : `${kind.label} "${e.query}" matches several.`,
        { candidates: e.candidates },
      );
    }
  }
  const code = (e as { code?: unknown } | null)?.code;
  const fromPostgres = (e as { name?: unknown } | null)?.name === 'PostgresError';
  if (fromPostgres && code === '23505') {
    return new ApiError(409, 'conflict', "The change clashes with the list's current state.");
  }
  deps.report(e);
  if (
    (fromPostgres && typeof code === 'string' && UNAVAILABLE_STATES.test(code)) ||
    (!fromPostgres && typeof code === 'string' && /^(CONNECT|CONNECTION)_/.test(code)) ||
    (e instanceof Error && e.name === 'ConnectionRefused')
  ) {
    return unavailable();
  }
  return internalError();
}

// Production wiring ---------------------------------------------------------------------------

/** api_begin's row; the key's ids and scopes are set exactly when the outcome is limited or ok. */
type BeginRow =
  & { rate_limit: number; rate_remaining: number; rate_reset: number; retry_after: number | null }
  & (
    | {
      outcome: 'disabled' | 'blocked' | 'invalid';
      token_id: string | null;
      user_id: string | null;
      household_id: string | null;
      scopes: Scope[] | null;
    }
    | {
      outcome: 'limited' | 'ok';
      token_id: string;
      user_id: string;
      household_id: string;
      scopes: Scope[];
    }
  );

export function beginOf(row: BeginRow): Begin {
  const rate = { limit: row.rate_limit, remaining: row.rate_remaining, reset: row.rate_reset };
  switch (row.outcome) {
    case 'disabled':
      return { outcome: 'disabled' };
    case 'blocked':
      return { outcome: 'blocked', rate, retryAfter: row.retry_after ?? rate.reset };
    case 'invalid':
      return { outcome: 'invalid', rate };
    case 'limited':
    case 'ok': {
      const key = {
        tokenId: row.token_id,
        userId: row.user_id,
        householdId: row.household_id,
        scopes: row.scopes,
      };
      return row.outcome === 'ok'
        ? { outcome: 'ok', rate, key }
        : { outcome: 'limited', rate, key, retryAfter: row.retry_after ?? 1 };
    }
  }
}

/**
 * One service transaction: claim the key (a concurrent duplicate waits on the row lock, then
 * reads what the first stored), run the operation as the member, store its answer. An operation
 * error rolls the claim back, so nothing is stored and a retry runs again.
 */
async function executeIdempotent(
  { key, run, idempotency }: Execution & { idempotency: NonNullable<Execution['idempotency']> },
): Promise<Executed> {
  return await serviceDb().begin(async (tx) => {
    const [claimed] = await tx`
      insert into public.api_idempotency as r (token_id, key, request_hash, status, body)
      values (${key.tokenId}, ${idempotency.key}, ${idempotency.requestHash}, 200, '{}'::json)
      on conflict (token_id, key) do update
        set request_hash = excluded.request_hash, status = 200, body = '{}'::json,
            created_at = now()
        where r.created_at < now() - make_interval(hours => ${IDEMPOTENCY_HOURS})
      returning 1`;
    if (!claimed) {
      const [stored] = await tx<{ request_hash: string; status: number; body: unknown }[]>`
        select request_hash, status, body from public.api_idempotency
        where token_id = ${key.tokenId} and key = ${idempotency.key}`;
      if (!stored) {
        throw new ApiError(409, 'conflict', 'The Idempotency-Key was just released. Retry.');
      }
      if (stored.request_hash !== idempotency.requestHash) {
        throw new ApiError(
          422,
          'idempotency_key_reused',
          'This Idempotency-Key came with a different request.',
        );
      }
      return { status: stored.status, body: stored.body, replayed: true };
    }
    const result = await asUserWithin(tx, key.userId, (tx) => run(tx, key.householdId));
    await tx`update public.api_idempotency
             set status = ${result.status}, body = ${JSON.stringify(result.body)}::text::json
             where token_id = ${key.tokenId} and key = ${idempotency.key}`;
    return { ...result, replayed: false };
  }) as Executed;
}

const requirePremium = requirePremiumWith(telemetry);

const defaultDeps: Deps = {
  begin: async (tokenHash, ipHash) => {
    const rows = await serviceDb()<BeginRow[]>`
      select * from public.api_begin(${tokenHash}::text, ${ipHash}::text, ${BURST}, ${PER_MINUTE},
        ${PER_DAY}, ${AUTH_FAILURES}, ${AUTH_FAILURE_WINDOW_SECONDS})`;
    return beginOf(oneRow(rows, 'api_begin'));
  },
  premium: (key) => requirePremium({ userId: key.userId, householdId: key.householdId }, 'api'),
  execute: async (execution) => {
    const { idempotency } = execution;
    if (idempotency) return await executeIdempotent({ ...execution, idempotency });
    const result = await asUser(
      execution.key.userId,
      (tx) => execution.run(tx, execution.key.householdId),
    );
    return { ...result, replayed: false };
  },
  report: (error) => {
    console.error('api: error', (error as Error)?.name, (error as { code?: unknown })?.code);
    telemetry.exception(error);
  },
  log: (line) => console.log(JSON.stringify(line)),
};
