import { assertEquals } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import type { HouseholdFate } from '../_shared/db.ts';
import { AFTER_DELETION_MS, createHandler, type Deps } from './handler.ts';

const USER = 'u-1';

/** A fake backend: "Bearer session" is a live session, "Bearer gone" a deleted user's. */
function fakeDeps(
  overrides: Partial<Deps> = {},
  fate: HouseholdFate = 'kept',
  afterDeletionMs: number = AFTER_DELETION_MS,
) {
  const deleted: string[] = [];
  const revoked: { code: string | null; subject: string }[] = [];
  const deps: Deps = {
    authenticate: (req) => {
      const auth = req.headers.get('authorization');
      if (auth === 'Bearer session') return Promise.resolve({ userId: USER });
      if (auth === 'Bearer fgp_token' || auth === 'Bearer oauth') {
        return Promise.reject(new AuthError('session_required', 'nope'));
      }
      if (auth === 'Bearer gone') return Promise.reject(new AuthError('user_deleted', 'gone'));
      if (!auth) return Promise.reject(new AuthError('missing_token', 'missing'));
      return Promise.reject(new AuthError('invalid_token', 'invalid'));
    },
    appleSubject: () => Promise.resolve(null),
    revokeApple: (grant) => {
      revoked.push(grant);
      return Promise.resolve('revoked');
    },
    deleteAccount: (userId) => {
      deleted.push(userId);
      return Promise.resolve(fate);
    },
    ...overrides,
  };
  return { handle: createHandler(deps, afterDeletionMs), deleted, revoked };
}

const call = (
  init: { token?: string | undefined; method?: string; body?: string; path?: string } = {},
) =>
  new Request(`http://local${init.path ?? '/account/delete'}`, {
    method: init.method ?? 'POST',
    headers: init.token === undefined ? {} : { authorization: `Bearer ${init.token}` },
    body: init.body ?? null,
  });

Deno.test('a session deletes the account and reports the household fate', async () => {
  for (const fate of ['kept', 'deleted', 'none'] as const) {
    const { handle, deleted } = fakeDeps({}, fate);
    const res = await handle(call({ token: 'session' }));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { deleted: true, household: fate, apple: 'not_linked' });
    assertEquals(deleted, [USER]);
  }
});

Deno.test('a personal access token or an OAuth app may not delete the account', async () => {
  for (const token of ['fgp_token', 'oauth']) {
    const { handle, deleted } = fakeDeps();
    const res = await handle(call({ token }));
    assertEquals(res.status, 403);
    assertEquals((await res.json()).error, 'session_required');
    assertEquals(deleted, []);
  }
});

Deno.test('a missing or invalid token is 401 and deletes nothing', async () => {
  for (const token of [undefined, 'forged']) {
    const { handle, deleted } = fakeDeps();
    const res = await handle(call({ token }));
    assertEquals(res.status, 401);
    assertEquals(res.headers.get('www-authenticate'), 'Bearer');
    assertEquals(deleted, []);
  }
});

Deno.test('a retry after the account is gone answers like the first success', async () => {
  const { handle, deleted } = fakeDeps();
  const res = await handle(call({ token: 'gone' }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true, household: 'none', apple: 'manual' });
  assertEquals(deleted, []);
});

Deno.test('an Apple account is revoked with the code, after the delete', async () => {
  const order: string[] = [];
  const { handle } = fakeDeps({
    appleSubject: () => Promise.resolve('apple-sub'),
    revokeApple: (grant) => {
      order.push(`revoke ${grant.code} ${grant.subject}`);
      return Promise.resolve('revoked');
    },
    deleteAccount: () => {
      order.push('delete');
      return Promise.resolve('deleted');
    },
  });
  const res = await handle(
    call({ token: 'session', body: JSON.stringify({ apple_authorization_code: 'c0de' }) }),
  );
  assertEquals(await res.json(), { deleted: true, household: 'deleted', apple: 'revoked' });
  assertEquals(order, ['delete', 'revoke c0de apple-sub']);
});

Deno.test('an Apple revocation that fails still deletes, flagged manual', async () => {
  const { handle, deleted } = fakeDeps({
    appleSubject: () => Promise.resolve('apple-sub'),
    revokeApple: () => Promise.resolve('manual'),
  });
  const res = await handle(call({ token: 'session' }));
  assertEquals(await res.json(), { deleted: true, household: 'kept', apple: 'manual' });
  assertEquals(deleted, [USER]);
});

Deno.test('without a code an Apple account is still revoked with null', async () => {
  const { handle, revoked } = fakeDeps({ appleSubject: () => Promise.resolve('apple-sub') });
  await handle(call({ token: 'session', body: '{}' }));
  assertEquals(revoked, [{ code: null, subject: 'apple-sub' }]);
});

Deno.test('a malformed body is 400 and deletes nothing', async () => {
  for (const body of ['nope', '[]', '{"apple_authorization_code": 7}']) {
    const { handle, deleted } = fakeDeps();
    const res = await handle(call({ token: 'session', body }));
    assertEquals(res.status, 400, body);
    assertEquals((await res.json()).error, 'bad_request');
    assertEquals(deleted, []);
  }
});

Deno.test('a database failure is a 500 JSON error and leaves the Apple code unspent', async () => {
  const { handle, revoked } = fakeDeps({
    appleSubject: () => Promise.resolve('apple-sub'),
    deleteAccount: () => Promise.reject(new Error('boom')),
  });
  const res = await handle(
    call({ token: 'session', body: JSON.stringify({ apple_authorization_code: 'c0de' }) }),
  );
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, 'server');
  assertEquals(revoked, []);
});

Deno.test('only POST /account/delete deletes; other methods and paths do not', async () => {
  const { handle, deleted } = fakeDeps();
  const get = await handle(call({ token: 'session', method: 'GET' }));
  assertEquals(get.status, 405);
  assertEquals((await get.json()).error, 'method');
  const other = await handle(call({ token: 'session', path: '/account/export' }));
  assertEquals(other.status, 404);
  await other.body?.cancel();
  const preflight = await handle(call({ method: 'OPTIONS' }));
  assertEquals(preflight.status, 204);
  assertEquals(deleted, []);
});

Deno.test('the screenshot sweep runs after a deletion and never changes the answer', async () => {
  const outcomes: [string, () => Promise<unknown>][] = [
    ['succeeds', () => Promise.resolve(3)],
    ['fails', () => Promise.reject(new Error('storage down'))],
    ['hangs', () => new Promise(() => {})],
    // index.ts reads the secret key and URL before its first await: a missing one throws here.
    ['throws before any await', () => {
      throw new Error('SUPABASE_SECRET_KEY is not set');
    }],
  ];
  for (const [name, sweep] of outcomes) {
    const order: string[] = [];
    const { handle } = fakeDeps(
      {
        deleteAccount: () => {
          order.push('delete');
          return Promise.resolve('kept');
        },
        afterDeletion: () => {
          order.push('sweep');
          return sweep();
        },
      },
      'kept',
      20,
    );
    const res = await handle(call({ token: 'session' }));
    assertEquals(res.status, 200, name);
    assertEquals(await res.json(), { deleted: true, household: 'kept', apple: 'not_linked' }, name);
    assertEquals(order, ['delete', 'sweep'], name);
  }
});

Deno.test('a failed deletion runs no sweep', async () => {
  let swept = false;
  const { handle } = fakeDeps({
    deleteAccount: () => Promise.reject(new Error('boom')),
    afterDeletion: () => {
      swept = true;
      return Promise.resolve();
    },
  });
  const res = await handle(call({ token: 'session' }));
  assertEquals(res.status, 500);
  await res.body?.cancel();
  assertEquals(swept, false);
});
