// The Supabase OAuth client behind each Client ID Metadata Document URL (public.oauth_cimd_clients).
// One client per URL for good: refresh tokens are bound to the Supabase client, so a changed
// document updates that client instead of registering another.
import type { Sql, Tx } from '../_shared/db.ts';
import {
  CimdError,
  type ClientIdUrl,
  type ClientMetadata,
  type fetchClientMetadata,
  freshForSeconds,
} from './cimd.ts';

/** The Supabase client a document URL maps to, and the redirect URIs its document allows. */
export type MappedClient = { authClientId: string; redirectUris: string[] };

/** Supabase Auth's admin API for OAuth clients (`/auth/v1/admin/oauth/clients`). */
export type AuthClientAdmin = {
  create: (metadata: ClientMetadata) => Promise<string>;
  /** False when the client no longer exists. */
  update: (authClientId: string, metadata: ClientMetadata) => Promise<boolean>;
  delete: (authClientId: string) => Promise<void>;
};

export type RegistryDeps = {
  sql: () => Sql;
  admin: AuthClientAdmin;
  fetchDocument: (url: ClientIdUrl) => ReturnType<typeof fetchClientMetadata>;
};

/**
 * Hourly limits of the front, per host of the document URL and in all. Anyone may send any
 * client_id URL to authorize, so fetches and registrations are bounded before they happen.
 * A URL that is already a client has its own fetch limit: strangers can use up a host's and the
 * overall one, and that must not keep a known client's users from signing in. Its count starts
 * again whenever the document could be fetched: it bounds fetches that fail in a row, and those
 * under way before the first one finishes, not how many a stale document gets while requests
 * pour in.
 */
export const LIMITS = {
  fetchPerHost: 30,
  fetchAll: 600,
  fetchPerClient: 30,
  newPerHost: 5,
  newAll: 100,
  tokenPerAddress: 120,
} as const;

/** Counts one hit per key; false when any key is over its limit this hour. */
export async function withinLimits(sql: Sql | Tx, limits: [string, number][]): Promise<boolean> {
  const [row] = await sql<{ ok: boolean }[]>`
    select public.oauth_cimd_rate_hit(${limits.map(([key]) => key)}::text[],
      ${limits.map(([, limit]) => limit)}::integer[]) as ok`;
  return row?.ok === true;
}

const busy = () => new CimdError('temporarily_unavailable', 'too many requests, try again later');

type Row = {
  'auth_client_id': string;
  'client_name': string;
  'redirect_uris': string[];
  'client_uri': string | null;
};

/**
 * For an authorization request: the mapped client, after fetching the document again once it is
 * stale and registering or updating the Supabase client to match it.
 */
export async function resolveClient(url: ClientIdUrl, deps: RegistryDeps): Promise<MappedClient> {
  const sql = deps.sql();
  const [known] = await sql<{ auth_client_id: string; redirect_uris: string[]; fresh: boolean }[]>`
    select auth_client_id, redirect_uris, fresh_until > now() as fresh
    from public.oauth_cimd_clients where client_id = ${url}`;
  if (known?.fresh) {
    return { authClientId: known.auth_client_id, redirectUris: known.redirect_uris };
  }
  const host = new URL(url).hostname;
  const limits: [string, number][] = known
    ? [[`fetch:${url}`, LIMITS.fetchPerClient]]
    : [[`fetch:${host}`, LIMITS.fetchPerHost], ['fetch:all', LIMITS.fetchAll]];
  if (!await withinLimits(sql, limits)) throw busy();
  const { metadata, maxAgeSeconds } = await deps.fetchDocument(url);
  const freshFor = `${freshForSeconds(maxAgeSeconds)} seconds`;
  return await sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(${url}, 94))`;
    if (known) await tx`delete from public.oauth_cimd_rate where key = ${`fetch:${url}`}`;
    const [row] = await tx<Row[]>`
      select auth_client_id, client_name, redirect_uris, client_uri from public.oauth_cimd_clients where client_id = ${url}`;
    if (row && !changed(row, metadata)) {
      await tx`update public.oauth_cimd_clients
        set fresh_until = now() + ${freshFor}::interval where client_id = ${url}`;
      return { authClientId: row.auth_client_id, redirectUris: row.redirect_uris };
    }
    if (row && await deps.admin.update(row.auth_client_id, metadata)) {
      await tx`update public.oauth_cimd_clients
        set client_name = ${metadata.clientName}, redirect_uris = ${metadata.redirectUris},
            client_uri = ${metadata.clientUri},
            fresh_until = now() + ${freshFor}::interval, updated_at = now()
        where client_id = ${url}`;
      return { authClientId: row.auth_client_id, redirectUris: metadata.redirectUris };
    }
    if (
      !row &&
      !await withinLimits(tx, [[`new:${host}`, LIMITS.newPerHost], ['new:all', LIMITS.newAll]])
    ) throw busy();
    const authClientId = await deps.admin.create(metadata);
    try {
      await tx`insert into public.oauth_cimd_clients
          (client_id, auth_client_id, client_name, redirect_uris, client_uri, fresh_until)
        values (${url}, ${authClientId}, ${metadata.clientName}, ${metadata.redirectUris},
          ${metadata.clientUri}, now() + ${freshFor}::interval)
        on conflict (client_id) do update set auth_client_id = excluded.auth_client_id,
          client_name = excluded.client_name, redirect_uris = excluded.redirect_uris,
          client_uri = excluded.client_uri, fresh_until = excluded.fresh_until, updated_at = now()`;
    } catch (e) {
      // The transaction rolls back; without the row nothing would ever use this client again.
      await deps.admin.delete(authClientId).catch(() => {});
      throw e;
    }
    return { authClientId, redirectUris: metadata.redirectUris };
  });
}

/** For a token request: the Supabase client a document URL already maps to, without a fetch. */
export async function lookupClient(url: ClientIdUrl, sql: Sql): Promise<string | null> {
  const [row] = await sql<{ auth_client_id: string }[]>`
    select auth_client_id from public.oauth_cimd_clients where client_id = ${url}`;
  return row?.auth_client_id ?? null;
}

function changed(row: Row, metadata: ClientMetadata): boolean {
  return row.client_name !== metadata.clientName ||
    row.client_uri !== metadata.clientUri ||
    JSON.stringify(row.redirect_uris) !== JSON.stringify(metadata.redirectUris);
}

/** The admin API with the function's secret key, against the project's internal URL. */
export function supabaseClientAdmin(
  internalUrl: string,
  secretKey: string,
  doFetch: typeof fetch = fetch,
): AuthClientAdmin {
  const base = `${internalUrl}/auth/v1/admin/oauth/clients`;
  const headers = {
    apikey: secretKey,
    authorization: `Bearer ${secretKey}`,
    'content-type': 'application/json',
  };
  const fields = (m: ClientMetadata) => ({
    client_name: m.clientName,
    redirect_uris: m.redirectUris,
    client_uri: m.clientUri,
  });
  return {
    async create(m) {
      const res = await doFetch(base, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          ...fields(m),
          client_type: 'public',
          token_endpoint_auth_method: 'none',
          grant_types: ['authorization_code', 'refresh_token'],
          response_types: ['code'],
        }),
      });
      const created = await res.json().catch(() => ({})) as { client_id?: string };
      if (!res.ok || typeof created.client_id !== 'string') {
        throw new Error(`auth admin: creating an OAuth client answered ${res.status}`);
      }
      return created.client_id;
    },
    async update(id, m) {
      const res = await doFetch(`${base}/${encodeURIComponent(id)}`, {
        method: 'PUT',
        headers,
        body: JSON.stringify(fields(m)),
      });
      await res.body?.cancel();
      if (res.status === 404) return false;
      if (!res.ok) throw new Error(`auth admin: updating an OAuth client answered ${res.status}`);
      return true;
    },
    async delete(id) {
      const res = await doFetch(`${base}/${encodeURIComponent(id)}`, { method: 'DELETE', headers });
      await res.body?.cancel();
      if (!res.ok && res.status !== 404) {
        throw new Error(`auth admin: deleting an OAuth client answered ${res.status}`);
      }
    },
  };
}
