/** Where fixtures go: this instance's local stack (default) or the hosted project, and an HTTP client for it. */

import { type Ctx, FgError, interrupted, type JsonObject, type Shell } from './core.ts';
import { stackEnv } from './stack.ts';

export type TargetKind = 'local' | 'hosted';

export interface Target {
  kind: TargetKind;
  /** For messages: never contains a key. */
  label: string;
  apiUrl: string;
  publishableKey: string;
  /** Service key, held in memory only; never printed, logged or written. */
  secretKey: string;
  /** Run manifests (credentials inside): outside the repo, mode 700. */
  runsDir: string;
}

/** Longest any single Supabase request may take before the command fails with api_timeout. */
export const REQUEST_TIMEOUT_MS = 30_000;

/** The production project; its URL and publishable key are public (app/lib/core/environment.dart). */
export const HOSTED = {
  ref: 'jdwqrallbpdbshrdhenk',
  url: 'https://jdwqrallbpdbshrdhenk.supabase.co',
  publishableKey: 'sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5',
};

export const targetFlag = {
  name: 'target',
  help: 'local (default: the stack of FG_PORT_PREFIX) or hosted (the real project; test accounts only, see docs/TEST_FIXTURES.md).',
  choices: ['local', 'hosted'],
};

export async function resolveTarget(
  ctx: Ctx,
  kind: TargetKind,
  env: Record<string, string | undefined> = Deno.env.toObject(),
): Promise<Target> {
  if (kind === 'local') {
    const local = await stackEnv(ctx.sh, ctx.inst);
    return {
      kind,
      label: `local stack ${ctx.inst.projectId} (${local.apiUrl})`,
      apiUrl: local.apiUrl,
      publishableKey: local.publishableKey,
      secretKey: local.secretKey,
      runsDir: `${ctx.inst.stateDir}/runs`,
    };
  }
  return {
    kind,
    label: `hosted project ${HOSTED.ref}`,
    apiUrl: HOSTED.url,
    publishableKey: HOSTED.publishableKey,
    secretKey: await hostedSecretKey(ctx.sh, env),
    runsDir: `${ctx.inst.cacheRoot}/hosted/runs`,
  };
}

/** The personal access token from the environment or the ops env file; never echoed. */
async function accessToken(sh: Shell, env: Record<string, string | undefined>): Promise<string> {
  if (env.SUPABASE_ACCESS_TOKEN) return env.SUPABASE_ACCESS_TOKEN;
  const file = env.FG_OPS_ENV ?? `${env.HOME ?? ''}/groceries-ops/env`;
  if (await sh.exists(file)) {
    const line = (await sh.readText(file)).split('\n').find((l) => /^(export\s+)?SUPABASE_ACCESS_TOKEN=/.test(l));
    const value = line?.replace(/^(export\s+)?SUPABASE_ACCESS_TOKEN=/, '').trim().replace(/^["']|["']$/g, '');
    if (value) return value;
  }
  throw new FgError(
    'no_access_token',
    'The hosted target needs SUPABASE_ACCESS_TOKEN (a Supabase personal access token) and none is set.',
    `Export it, or put SUPABASE_ACCESS_TOKEN=... into ${file} (mode 600). Without it, use --target local.`,
  );
}

/** Fetches the project's secret key through the Management API at runtime. */
async function hostedSecretKey(sh: Shell, env: Record<string, string | undefined>): Promise<string> {
  const token = await accessToken(sh, env);
  const res = await sh.fetch(`https://api.supabase.com/v1/projects/${HOSTED.ref}/api-keys?reveal=true`, {
    headers: { authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  }).catch((e) => {
    throw new FgError(
      'management_api_failed',
      `The Management API did not answer: ${(e as Error).message}.`,
      'Check the network, then retry.',
    );
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new FgError(
      'management_api_failed',
      `The Management API refused the key lookup (HTTP ${res.status}).`,
      'The access token may lack access to the project or be expired; see docs/NEEDS_PETER.md.',
    );
  }
  const keys = (await res.json()) as { type: string; name: string; api_key?: string }[];
  const key = keys.find((k) => k.type === 'secret')?.api_key ?? keys.find((k) => k.name === 'service_role')?.api_key;
  if (!key) throw new FgError('management_api_failed', 'The project reports no secret key.', 'Create one in the dashboard (API keys).');
  return key;
}

/** PostgREST and GoTrue calls with the service key or a user session. Errors never include keys or tokens. */
export class Api {
  /**
   * stop: a command's stop signal; requests made with it end at once when it
   * aborts. Every request also ends after REQUEST_TIMEOUT_MS, so a hung
   * connection can never hold a command (and the e2e lock) forever.
   */
  constructor(private sh: Shell, readonly target: Target, private stop?: AbortSignal, private timeoutMs = REQUEST_TIMEOUT_MS) {}

  /** Fetch with the timeout and the stop signal; a stop or timeout becomes an FgError naming the request. */
  private async send(what: string, url: string, init: RequestInit): Promise<Response> {
    const timeout = AbortSignal.timeout(this.timeoutMs);
    try {
      return await this.sh.fetch(url, { ...init, signal: this.stop ? AbortSignal.any([timeout, this.stop]) : timeout });
    } catch (e) {
      if (this.stop?.aborted) throw interrupted(what);
      if (timeout.aborted) {
        throw new FgError(
          'api_timeout',
          `${what} did not answer within ${this.timeoutMs / 1000} s.`,
          `Is the ${this.target.label} reachable? Retry; \`fg doctor\` for the local stack.`,
        );
      }
      throw new FgError('api_failed', `${what}: ${(e as Error).message}`, `Is the ${this.target.label} reachable? \`fg doctor\`.`);
    }
  }

  private headers(token?: string, extra: Record<string, string> = {}): Record<string, string> {
    // No token: the service role. An empty token: anonymous (sign-in).
    const auth = token === undefined
      ? { apikey: this.target.secretKey, authorization: `Bearer ${this.target.secretKey}` }
      : { apikey: this.target.publishableKey, ...(token ? { authorization: `Bearer ${token}` } : {}) };
    return { ...auth, 'content-type': 'application/json', ...extra };
  }

  async call(path: string, init: RequestInit & { token?: string | undefined; prefer?: string } = {}): Promise<unknown> {
    const { token, prefer, ...rest } = init;
    const res = await this.send(`${rest.method ?? 'GET'} ${path.split('?')[0]}`, `${this.target.apiUrl}${path}`, {
      ...rest,
      headers: { ...this.headers(token, prefer ? { prefer } : {}), ...(rest.headers as Record<string, string> | undefined) },
    });
    const text = await res.text();
    if (!res.ok) {
      throw new FgError(
        'api_failed',
        `${rest.method ?? 'GET'} ${path.split('?')[0]} as ${token ? 'user' : 'service role'}: HTTP ${res.status} ${text.slice(0, 400)}`,
        `Check the message; \`fg doctor\` shows whether the ${this.target.label} is healthy.`,
        1,
        { status: res.status },
      );
    }
    return text ? JSON.parse(text) : null;
  }

  rest(path: string, init: RequestInit & { token?: string | undefined } = {}): Promise<unknown> {
    return this.call(`/rest/v1/${path}`, { prefer: 'return=representation', ...init });
  }

  rpc(fn: string, body: JsonObject, token?: string): Promise<unknown> {
    return this.call(`/rest/v1/rpc/${fn}`, { method: 'POST', body: JSON.stringify(body), token });
  }

  /** Exact row count through the service role, or through RLS as `token`'s user; reads no row content. */
  async count(table: string, filter: string, token?: string): Promise<number> {
    const res = await this.send(
      `Counting ${table}`,
      `${this.target.apiUrl}/rest/v1/${table}?select=*&limit=0${filter ? `&${filter}` : ''}`,
      {
        method: 'HEAD',
        headers: this.headers(token, { prefer: 'count=exact' }),
      },
    );
    await res.body?.cancel();
    if (!res.ok) throw new FgError('api_failed', `Counting ${table}: HTTP ${res.status}.`, `\`fg doctor\` on the ${this.target.label}.`);
    return Number(res.headers.get('content-range')?.split('/')[1] ?? 'NaN');
  }

  async signIn(email: string, password: string): Promise<{ token: string; userId: string }> {
    const body = (await this.call('/auth/v1/token?grant_type=password', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
      token: '',
    }).catch((e) => {
      throw new FgError(
        'login_failed',
        `${email} cannot sign in (${(e as FgError).message.replace(/^.*HTTP/, 'HTTP')}).`,
        'The run may be torn down: `fg runs`.',
      );
    })) as JsonObject;
    return { token: body.access_token as string, userId: (body.user as JsonObject).id as string };
  }

  /** Every auth user (id, email, created_at, app_metadata), paged. */
  async users(): Promise<{ id: string; email: string; created_at: string; app_metadata: JsonObject }[]> {
    const all: { id: string; email: string; created_at: string; app_metadata: JsonObject }[] = [];
    for (let page = 1;; page++) {
      const body = (await this.call(`/auth/v1/admin/users?page=${page}&per_page=500`)) as { users: typeof all };
      all.push(
        ...body.users.map((u) => ({ id: u.id, email: u.email ?? '', created_at: u.created_at, app_metadata: u.app_metadata ?? {} })),
      );
      if (body.users.length < 500) return all;
    }
  }
}
