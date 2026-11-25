// The local stack this checkout runs (`supabase status`), and the synthetic account the voice
// benchmark drives: one user with a household, 24 open items, an analytics yes, a Siri credential
// and an Alexa account link made by the OAuth flow Alexa runs. Never a hosted project: the API
// must be on 127.0.0.1.
import postgres from 'postgres';
import { CURRENT_CONSENT_TEXT_VERSIONS } from '../../../supabase/functions/_shared/consent_version.ts';

const repo = new URL('../../../', import.meta.url).pathname;

export interface Stack {
  api: string;
  dbUrl: string;
  publishable: string;
  secret: string;
  /** The edge runtime's container, restarted for a cold worker. */
  edgeContainer: string;
  project: string;
}

const text = (out: Uint8Array) => new TextDecoder().decode(out);

export async function stack(): Promise<Stack> {
  const status = await new Deno.Command('supabase', {
    args: ['status', '-o', 'json'],
    cwd: repo,
    stdout: 'piped',
    stderr: 'null',
  }).output();
  const env = JSON.parse(text(status.stdout)) as Record<string, string | undefined>;
  const { API_URL: api, DB_URL: dbUrl, PUBLISHABLE_KEY: publishable, SECRET_KEY: secret } = env;
  if (!api || !dbUrl || !publishable || !secret) throw new Error('no local stack: supabase start');
  if (!api.startsWith('http://127.0.0.1:')) throw new Error(`not a local stack: ${api}`);
  const config = await Deno.readTextFile(`${repo}supabase/config.toml`);
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(config)?.[1];
  if (!project) throw new Error('no project_id in supabase/config.toml');
  return {
    api,
    dbUrl,
    publishable,
    secret,
    edgeContainer: `supabase_edge_runtime_${project}`,
    project,
  };
}

export interface Account {
  userId: string;
  email: string;
  householdId: string;
  listId: string;
  /** The app's "Siri on this iPhone" credential (fgp_...). */
  siriToken: string;
  /** The OAuth access token Alexa got through account linking. */
  alexaToken: string;
  oauthClientId: string;
}

/** Open items the household starts with, so reading the list has something to read. */
const openItems = [
  'Äpfel, Bananen, Tomaten, Gurke, Zwiebeln, Kartoffeln',
  'Butter, Joghurt, Käse, Sahne, Quark, Frischkäse',
  'Nudeln, Reis, Mehl, Zucker, Kaffee, Tee',
  'Klopapier, Spülmittel, Zahnpasta, Duschgel, Shampoo, Taschentücher',
];

const alexaRedirect = 'https://layla.amazon.com/api/skill/link/MBENCHVENDOR';

async function must(res: Response, what: string): Promise<Record<string, unknown>> {
  const body = await res.text();
  if (!res.ok) throw new Error(`${what}: ${res.status} ${body.slice(0, 300)}`);
  return body ? JSON.parse(body) as Record<string, unknown> : {};
}

const str = (v: unknown, what: string): string => {
  if (typeof v !== 'string') throw new Error(`${what}: not a string`);
  return v;
};

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function jwtClaims(token: string): Record<string, unknown> {
  const part = token.split('.')[1];
  if (!part) throw new Error('not a JWT');
  const json = atob(part.replace(/-/g, '+').replace(/_/g, '/'));
  return JSON.parse(json) as Record<string, unknown>;
}

/** Creates the synthetic account. */
export async function seed(s: Stack): Promise<Account> {
  const tag = crypto.randomUUID().slice(0, 8);
  const email = `voice-bench-${tag}@fg-bench.invalid`;
  const password = `bench-${crypto.randomUUID()}`;
  const admin = { apikey: s.secret, authorization: `Bearer ${s.secret}` };
  const user = await must(
    await fetch(`${s.api}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { ...admin, 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, email_confirm: true }),
    }),
    'create user',
  );
  const userId = str(user.id, 'user id');
  const session = await must(
    await fetch(`${s.api}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: s.publishable, 'content-type': 'application/json' },
      body: JSON.stringify({ email, password }),
    }),
    'sign in',
  );
  const appToken = str(session.access_token, 'access token');
  const sessionId = str(jwtClaims(appToken).session_id, 'session_id');

  const sql = postgres(s.dbUrl, { max: 1, prepare: false, onnotice: () => {} });
  let householdId: string;
  let listId: string;
  let siriToken: string;
  try {
    const claims = JSON.stringify({ sub: userId, role: 'authenticated', session_id: sessionId });
    [householdId, listId, siriToken] = await sql.begin(async (tx) => {
      await tx`select set_config('role', 'authenticated', true),
                      set_config('request.jwt.claims', ${claims}, true)`;
      const [h] = await tx<{ id: string }[]>`select id from public.create_household('Bench')`;
      const [cred] = await tx<
        { token: string }[]
      >`select token from public.create_siri_credential()`;
      if (!h || !cred) throw new Error('household or Siri credential not created');
      const [l] = await tx<{ id: string }[]>`
        select id from public.lists where household_id = ${h.id} order by position limit 1`;
      if (!l) throw new Error('no list');
      return [h.id, l.id, cred.token] as const;
    });
    const version = CURRENT_CONSENT_TEXT_VERSIONS[0] ?? null;
    await sql`insert into public.analytics_consents (user_id, install_id, consent, consent_text_version)
              values (${userId}, ${crypto.randomUUID()}, true, ${version})`;
  } finally {
    await sql.end();
  }

  for (const text of openItems) {
    await must(
      await fetch(`${s.api}/functions/v1/voice`, {
        method: 'POST',
        headers: { authorization: `Bearer ${siriToken}`, 'content-type': 'application/json' },
        body: JSON.stringify({ text, lang: 'de' }),
      }),
      'seed items',
    );
  }

  const { clientId, alexaToken } = await linkAlexa(s, appToken);
  return {
    userId,
    email,
    householdId,
    listId,
    siriToken,
    alexaToken,
    oauthClientId: clientId,
  };
}

/** Account linking as Alexa runs it: a confidential client, PKCE S256, the user's consent. */
async function linkAlexa(s: Stack, appToken: string) {
  const issuer = `${s.api}/auth/v1`;
  const client = await must(
    await fetch(`${issuer}/oauth/clients/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        client_name: 'Voice Bench Alexa',
        redirect_uris: [alexaRedirect],
        grant_types: ['authorization_code', 'refresh_token'],
        response_types: ['code'],
        token_endpoint_auth_method: 'client_secret_basic',
      }),
    }),
    'register client',
  );
  const clientId = str(client.client_id, 'client_id');
  const clientSecret = str(client.client_secret, 'client_secret');
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(48)));
  const challenge = b64url(
    new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))),
  );
  const authorize = new URL(`${issuer}/oauth/authorize`);
  authorize.search = new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: alexaRedirect,
    state: 'bench',
    code_challenge: challenge,
    code_challenge_method: 'S256',
  }).toString();
  const redirect = await fetch(authorize, { redirect: 'manual' });
  await redirect.body?.cancel();
  const consentUrl = new URL(redirect.headers.get('location') ?? '', authorize);
  const authorizationId = consentUrl.searchParams.get('authorization_id');
  if (!authorizationId) throw new Error(`authorize: no authorization_id (${redirect.status})`);
  const asUser = {
    apikey: s.publishable,
    authorization: `Bearer ${appToken}`,
    'content-type': 'application/json',
  };
  // The consent page reads the request first, which ties it to the signed-in user.
  await must(
    await fetch(`${issuer}/oauth/authorizations/${authorizationId}`, { headers: asUser }),
    'authorization details',
  );
  const consent = await must(
    await fetch(`${issuer}/oauth/authorizations/${authorizationId}/consent`, {
      method: 'POST',
      headers: asUser,
      body: JSON.stringify({ action: 'approve' }),
    }),
    'consent',
  );
  const code = new URL(str(consent.redirect_url, 'redirect_url')).searchParams.get('code');
  if (!code) throw new Error('consent: no code');
  const tokens = await must(
    await fetch(`${issuer}/oauth/token`, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: alexaRedirect,
        code_verifier: verifier,
      }),
    }),
    'token',
  );
  return { clientId, alexaToken: str(tokens.access_token, 'access_token') };
}

/** Removes the account, its household and its OAuth client. */
export async function teardown(s: Stack, a: Account): Promise<void> {
  const sql = postgres(s.dbUrl, { max: 1, prepare: false, onnotice: () => {} });
  try {
    await sql`delete from public.households where id = ${a.householdId}`;
    await sql`delete from auth.users where id = ${a.userId}`;
    await sql`delete from auth.oauth_clients where id = ${a.oauthClientId}`;
  } finally {
    await sql.end();
  }
}
