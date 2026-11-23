import { assertEquals, assertRejects } from '@std/assert';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import {
  type AuthDeps,
  authenticate,
  authenticateSession,
  AuthError,
  type AuthFailure,
  type InvalidTokenDetail,
  type SessionDeps,
  sha256Hex,
} from './auth.ts';

const ISSUER = 'http://127.0.0.1:54621/auth/v1';
const USER = '11111111-1111-1111-1111-111111111111';
const HOUSEHOLD = '22222222-2222-2222-2222-222222222222';
const PAT = 'fgp_valid-token';
const SIRI = 'fgp_siri-on-this-iphone';
const SESSION = '44444444-4444-4444-4444-444444444444';
const ENDED = '55555555-5555-5555-5555-555555555555';

const { publicKey, privateKey } = await generateKeyPair('ES256');
const jwks = createLocalJWKSet({
  keys: [{ ...(await exportJWK(publicKey)), kid: 'k1', alg: 'ES256' }],
});
const other = await generateKeyPair('ES256');

const deps: AuthDeps = {
  issuer: () => Promise.resolve({ issuer: ISSUER, jwksUri: new URL('http://unused') }),
  jwks: () => jwks,
  householdOf: (userId) => Promise.resolve(userId === USER ? HOUSEHOLD : null),
  sessionActive: ({ id }) => Promise.resolve(id !== ENDED),
  resolvePat: async (hash) => {
    if (hash === await sha256Hex(PAT)) {
      return {
        userId: USER,
        householdId: HOUSEHOLD,
        kind: 'pat',
        scopes: ['read', 'write'] as const,
      };
    }
    if (hash === await sha256Hex(SIRI)) {
      return { userId: USER, householdId: HOUSEHOLD, kind: 'siri' };
    }
    return null;
  },
};

function token(
  claims: Record<string, unknown> = {},
  opts: { key?: CryptoKey; exp?: string; aud?: string; iss?: string; sub?: string } = {},
) {
  return new SignJWT({ role: 'authenticated', session_id: SESSION, ...claims })
    .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
    .setSubject(opts.sub ?? USER)
    .setIssuer(opts.iss ?? ISSUER)
    .setAudience(opts.aud ?? 'authenticated')
    .setIssuedAt()
    .setExpirationTime(opts.exp ?? '1h')
    .sign(opts.key ?? privateKey);
}

const bearer = (value: string) =>
  new Request('http://local/mcp', { headers: { authorization: `Bearer ${value}` } });

async function failsWith(req: Request, reason: AuthFailure, detail?: InvalidTokenDetail) {
  const error = await assertRejects(() => authenticate(req, deps), AuthError);
  assertEquals([error.reason, error.detail], [reason, detail]);
}

Deno.test('an OAuth access token authenticates as its user, household and client', async () => {
  const auth = await authenticate(bearer(await token({ client_id: 'c-1', scope: 'openid' })), deps);
  assertEquals(auth, {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'oauth',
    clientId: 'c-1',
    sessionId: SESSION,
  });
});

Deno.test('an app session token authenticates as a session', async () => {
  assertEquals(await authenticate(bearer(await token()), deps), {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'session',
  });
});

Deno.test('a JWT whose session ended (app disconnected, signed out) is invalid', async () => {
  await failsWith(
    bearer(await token({ client_id: 'c-1', session_id: ENDED })),
    'invalid_token',
    'session_ended',
  );
  await failsWith(bearer(await token({ session_id: ENDED })), 'invalid_token', 'session_ended');
  await failsWith(bearer(await token({ session_id: undefined })), 'invalid_token', 'claims');
});

Deno.test('a personal access token authenticates by its hash', async () => {
  assertEquals(await authenticate(bearer(PAT), deps), {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'pat',
    scopes: ['read', 'write'],
  });
});

Deno.test('a Siri credential authenticates as siri only where the function opts in', async () => {
  assertEquals(await authenticate(bearer(SIRI), deps, { siri: true }), {
    userId: USER,
    householdId: HOUSEHOLD,
    via: 'siri',
  });
  assertEquals((await authenticate(bearer(PAT), deps, { siri: true })).via, 'pat');
  await failsWith(bearer(SIRI), 'invalid_token', 'unknown_key');
  const error = await assertRejects(
    () => authenticateSession(bearer(SIRI), sessionDeps),
    AuthError,
  );
  assertEquals(error.reason, 'session_required');
});

Deno.test('missing or malformed Authorization headers are missing tokens', async () => {
  await failsWith(new Request('http://local/mcp'), 'missing_token');
  await failsWith(
    new Request('http://local/mcp', { headers: { authorization: 'Basic abc' } }),
    'missing_token',
  );
});

Deno.test('unknown or revoked personal access tokens are invalid', async () => {
  await failsWith(bearer('fgp_revoked'), 'invalid_token', 'unknown_key');
});

Deno.test('tokens that fail signature, expiry, audience, issuer or role checks are invalid', async () => {
  await failsWith(bearer(await token({}, { key: other.privateKey })), 'invalid_token', 'signature');
  await failsWith(bearer(await token({}, { exp: '-1m' })), 'invalid_token', 'expired');
  await failsWith(bearer(await token({}, { aud: 'someone-else' })), 'invalid_token', 'audience');
  await failsWith(
    bearer(await token({}, { iss: 'https://evil.example/auth/v1' })),
    'invalid_token',
    'issuer',
  );
  await failsWith(bearer(await token({ role: 'anon' })), 'invalid_token', 'claims');
  await failsWith(bearer('not-a-jwt'), 'invalid_token', 'malformed');
  const legacy = await new SignJWT({ role: 'authenticated', session_id: SESSION })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(USER)
    .setIssuer(ISSUER)
    .setAudience('authenticated')
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode('the legacy jwt secret, at least 32 chars'));
  await failsWith(bearer(legacy), 'invalid_token', 'signature');
});

Deno.test('a valid user without a household is refused with 403', async () => {
  const req = bearer(
    await new SignJWT({ role: 'authenticated', session_id: SESSION })
      .setProtectedHeader({ alg: 'ES256', kid: 'k1' })
      .setSubject('33333333-3333-3333-3333-333333333333')
      .setIssuer(ISSUER)
      .setAudience('authenticated')
      .setExpirationTime('1h')
      .sign(privateKey),
  );
  const error = await assertRejects(() => authenticate(req, deps), AuthError);
  assertEquals([error.reason, error.status], ['no_household', 403]);
});

const DELETED = '66666666-6666-6666-6666-666666666666';
const sessionDeps: SessionDeps = {
  ...deps,
  // A deleted user's sessions are gone with them.
  sessionActive: ({ id, userId }) => Promise.resolve(id !== ENDED && userId !== DELETED),
  userExists: (userId) => Promise.resolve(userId !== DELETED),
};

async function sessionFailsWith(req: Request, reason: AuthFailure, status: 401 | 403) {
  const error = await assertRejects(() => authenticateSession(req, sessionDeps), AuthError);
  assertEquals([error.reason, error.status], [reason, status]);
}

Deno.test('authenticateSession accepts the app session, with or without a household', async () => {
  assertEquals(await authenticateSession(bearer(await token()), sessionDeps), { userId: USER });
  const loner = await token({}, { sub: '77777777-7777-7777-7777-777777777777' });
  assertEquals(await authenticateSession(bearer(loner), sessionDeps), {
    userId: '77777777-7777-7777-7777-777777777777',
  });
});

Deno.test('authenticateSession refuses personal access tokens and OAuth apps with 403', async () => {
  await sessionFailsWith(bearer(PAT), 'session_required', 403);
  await sessionFailsWith(bearer(await token({ client_id: 'c-1' })), 'session_required', 403);
});

Deno.test('authenticateSession: bad, ended and deleted-user tokens', async () => {
  await sessionFailsWith(new Request('http://local/account'), 'missing_token', 401);
  await sessionFailsWith(bearer(await token({}, { key: other.privateKey })), 'invalid_token', 401);
  await sessionFailsWith(bearer(await token({ session_id: ENDED })), 'invalid_token', 401);
  await sessionFailsWith(bearer(await token({}, { sub: DELETED })), 'user_deleted', 401);
});
