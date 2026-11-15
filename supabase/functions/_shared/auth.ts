// Bearer authentication shared by the edge functions (MCP, Siri).
// Accepts three credentials, all scoped to the caller's household:
//   oauth   - an access token Supabase's OAuth 2.1 server issued to a client (has client_id);
//   session - the app's own Supabase session token;
// Both JWT kinds are accepted only while their Supabase session exists, so disconnecting an app
// in "Zugänge" (revokeGrant deletes its sessions) or signing out cuts access off at once instead
// of when the access token expires.
//   pat     - a personal access token (fgp_...), checked by hash against the database;
//   siri    - the app's "Siri on this iPhone" credential: the same token format, valid while the
//             session that minted it exists. Only functions that pass { siri: true } take it.
// authenticateSession accepts only the app's own session token, household or not: for account
// actions no connected app or token may take.
import { createRemoteJWKSet, errors, type JWTPayload, jwtVerify } from 'jose';
import { householdOf, resolveAccessToken, sessionActive, userExists } from './db.ts';

/** The project's internal URL; the runtime always sets it. */
export function supabaseUrl(): string {
  const url = Deno.env.get('SUPABASE_URL');
  if (url === undefined) throw new Error('SUPABASE_URL is not set');
  return url;
}

/** The project's secret key: the new-style default secret key, else the legacy service role key. */
export function secretKeyFromEnv(): string {
  const keys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>;
      if (parsed.default) return parsed.default;
    } catch {
      // Not JSON: fall through to the service role key.
    }
  }
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!legacy) throw new Error('neither SUPABASE_SECRET_KEYS nor SUPABASE_SERVICE_ROLE_KEY set');
  return legacy;
}

export type Auth =
  & { userId: string; householdId: string }
  & (
    /** sessionId: the Supabase session behind the token (Alexa revokes it, job 31). */
    | { via: 'oauth'; clientId: string; sessionId: string }
    | { via: 'pat' }
    | { via: 'siri' }
    | { via: 'session' }
  );

export type Via = Auth['via'];

export type AuthFailure =
  | 'missing_token'
  | 'invalid_token'
  | 'no_household'
  | 'session_required'
  /** A genuine session token whose user has since been deleted. */
  | 'user_deleted';

/**
 * Which check an invalid_token failed, for logs only (Alexa's request line, job 170b): responses
 * keep the bare reason. Closed, so a log never carries the token or the verifier's message.
 */
export type InvalidTokenDetail =
  | 'expired'
  | 'issuer'
  | 'audience'
  | 'signature'
  /** A required claim is missing, or the role is not a signed-in user's. */
  | 'claims'
  | 'malformed'
  /** Anything else the verifier threw, a key set that would not load among them. */
  | 'unverified'
  /** Signed out, disconnected in "Zugänge", revoked, or the user deleted. */
  | 'session_ended'
  /** A personal access token or Siri credential that is unknown, revoked or not taken here. */
  | 'unknown_key'
  /** A valid credential, but not an OAuth client's (Alexa takes only its account link). */
  | 'not_oauth';

export class AuthError extends Error {
  constructor(
    readonly reason: AuthFailure,
    message: string,
    readonly detail?: InvalidTokenDetail,
  ) {
    super(message);
  }

  /** 401 for a missing or bad credential, 403 for a valid credential that may not do this. */
  get status(): 401 | 403 {
    return this.reason === 'no_household' || this.reason === 'session_required' ? 403 : 401;
  }
}

/** Where the token's issuer lives, as browsers and the tokens' `iss` see it. */
export type Issuer = { issuer: string; jwksUri: URL };

export type AuthDeps = {
  issuer: () => Promise<Issuer>;
  jwks: (issuer: Issuer) => Parameters<typeof jwtVerify>[1];
  householdOf: (userId: string) => Promise<string | null>;
  sessionActive: (
    session: { id: string; userId: string; clientId: string | null },
  ) => Promise<boolean>;
  resolvePat: (tokenHash: string) => Promise<ResolvedToken | null>;
};

export type ResolvedToken = { userId: string; householdId: string; kind: 'pat' | 'siri' };

export type AuthOptions = { siri?: boolean };

export const PAT_PREFIX = 'fgp_';

const bearer = /^Bearer\s+(?<token>\S+)\s*$/i;

function bearerToken(req: Request): string {
  const token = bearer.exec(req.headers.get('authorization') ?? '')?.groups?.token;
  if (token === undefined) {
    throw new AuthError('missing_token', 'Authorization: Bearer <token> fehlt.');
  }
  return token;
}

export async function authenticate(
  req: Request,
  deps: AuthDeps = defaultDeps,
  options: AuthOptions = {},
): Promise<Auth> {
  const token = bearerToken(req);

  if (token.startsWith(PAT_PREFIX)) {
    const owner = await deps.resolvePat(await sha256Hex(token));
    if (!owner || (owner.kind === 'siri' && !options.siri)) {
      throw new AuthError('invalid_token', 'Token unbekannt oder widerrufen.', 'unknown_key');
    }
    return { userId: owner.userId, householdId: owner.householdId, via: owner.kind };
  }

  const claims = await verifyJwt(token, deps);
  const clientId = typeof claims.client_id === 'string' ? claims.client_id : null;
  const [active, householdId] = await Promise.all([
    deps.sessionActive({ id: claims.session_id, userId: claims.sub, clientId }),
    deps.householdOf(claims.sub),
  ]);
  if (!active) {
    throw new AuthError('invalid_token', 'Sitzung beendet oder Zugang getrennt.', 'session_ended');
  }
  if (!householdId) throw new AuthError('no_household', 'Dieses Konto gehört zu keinem Haushalt.');
  return clientId
    ? { userId: claims.sub, householdId, via: 'oauth', clientId, sessionId: claims.session_id }
    : { userId: claims.sub, householdId, via: 'session' };
}

export type SessionDeps = Pick<AuthDeps, 'issuer' | 'jwks' | 'sessionActive'> & {
  userExists: (userId: string) => Promise<boolean>;
};

/** The app's own signed-in session; PATs and OAuth tokens get 403 session_required. */
export async function authenticateSession(
  req: Request,
  deps: SessionDeps = defaultSessionDeps,
): Promise<{ userId: string }> {
  const token = bearerToken(req);
  const required = () =>
    new AuthError('session_required', 'Nur in der App angemeldet möglich, nicht mit einem Zugang.');

  if (token.startsWith(PAT_PREFIX)) throw required();
  const claims = await verifyJwt(token, deps);
  if (claims.client_id !== undefined) throw required();
  if (await deps.sessionActive({ id: claims.session_id, userId: claims.sub, clientId: null })) {
    return { userId: claims.sub };
  }
  if (!await deps.userExists(claims.sub)) {
    throw new AuthError('user_deleted', 'Dieses Konto ist gelöscht.');
  }
  throw new AuthError('invalid_token', 'Sitzung beendet.', 'session_ended');
}

async function verifyJwt(
  token: string,
  deps: Pick<AuthDeps, 'issuer' | 'jwks'>,
): Promise<JWTPayload & { sub: string; session_id: string }> {
  const issuer = await deps.issuer();
  try {
    const { payload } = await jwtVerify(token, deps.jwks(issuer), {
      issuer: issuer.issuer,
      // Supabase issues user and OAuth access tokens for this audience; it ignores RFC 8707.
      audience: 'authenticated',
      algorithms: ['ES256', 'RS256'],
      requiredClaims: ['sub', 'exp', 'session_id'],
    });
    const { sub, role, session_id } = payload;
    if (typeof sub !== 'string' || typeof session_id !== 'string' || role !== 'authenticated') {
      throw new AuthError('invalid_token', 'Token ungültig: not a user token', 'claims');
    }
    return { ...payload, sub, session_id };
  } catch (e) {
    if (e instanceof AuthError) throw e;
    throw new AuthError('invalid_token', `Token ungültig: ${(e as Error).message}`, detailOf(e));
  }
}

/** jose's error code (and failed claim) as an InvalidTokenDetail. */
function detailOf(e: unknown): InvalidTokenDetail {
  if (!(e instanceof errors.JOSEError)) return 'unverified';
  if (e instanceof errors.JWTExpired) return 'expired';
  if (e instanceof errors.JWTClaimValidationFailed) {
    return e.claim === 'iss' ? 'issuer' : e.claim === 'aud' ? 'audience' : 'claims';
  }
  if (
    e instanceof errors.JWSSignatureVerificationFailed || e instanceof errors.JWKSNoMatchingKey ||
    e instanceof errors.JOSEAlgNotAllowed
  ) return 'signature';
  if (e instanceof errors.JWSInvalid || e instanceof errors.JWTInvalid) return 'malformed';
  return 'unverified';
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * The public issuer, read from Supabase Auth's discovery document through the internal URL.
 * Inside the local stack SUPABASE_URL is http://kong:8000 while tokens carry the public URL.
 */
let issuerCache: Promise<Issuer> | undefined;
export function discoverIssuer(): Promise<Issuer> {
  issuerCache ??= (async () => {
    const internal = supabaseUrl();
    const res = await fetch(`${internal}/auth/v1/.well-known/openid-configuration`);
    if (!res.ok) throw new Error(`auth discovery failed: ${res.status}`);
    const { issuer } = await res.json() as { issuer: string };
    return { issuer, jwksUri: new URL(`${internal}/auth/v1/.well-known/jwks.json`) };
  })().catch((e) => {
    issuerCache = undefined;
    throw e;
  });
  return issuerCache;
}

let jwksCache: ReturnType<typeof createRemoteJWKSet> | undefined;

const defaultDeps: AuthDeps = {
  issuer: discoverIssuer,
  jwks: (issuer) => (jwksCache ??= createRemoteJWKSet(issuer.jwksUri)),
  householdOf,
  sessionActive,
  resolvePat: resolveAccessToken,
};

const defaultSessionDeps: SessionDeps = { ...defaultDeps, userExists };
