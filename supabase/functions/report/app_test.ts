import { assert, assertEquals, assertExists } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import {
  APP_LIMITS,
  type AppReport,
  type AppStore,
  configFrom,
  createHandler,
  MAX_APP_BODY,
  MAX_SCREENSHOT,
  type Store,
  type Stored,
} from './handler.ts';
import type { Mail } from '../_shared/resend.ts';

const T0 = new Date('2026-11-17T13:05:00Z');
const USER = '00000000-0000-4000-8000-000000000281';
const TOKEN = 'session-token';
const ITEM = '7C9E6679-7425-40DE-944B-E07FC1F90AE7';
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const base64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

interface Row {
  userId: string;
  report: AppReport;
  id: string;
  ref: string;
  confirmationSentAt: Date | null;
}

/**
 * content_report_submit_app's rules over an array: the limits, and confirm for every address.
 * Also the web store's confirmationSent, which the app route shares.
 */
class FakeAppStore implements AppStore {
  rows: Row[] = [];
  calls = 0;
  failWith: unknown = null;

  submit(
    userId: string,
    report: AppReport,
    _now: Date,
    limits: typeof APP_LIMITS,
  ): Promise<Stored | { refused: 'user' | 'global' }> {
    this.calls++;
    if (this.failWith) return Promise.reject(this.failWith);
    if (this.rows.length >= limits.perHour) return Promise.resolve({ refused: 'global' });
    if (this.rows.filter((r) => r.userId === userId).length >= limits.perUserHour) {
      return Promise.resolve({ refused: 'user' });
    }
    const row: Row = {
      userId,
      report,
      id: crypto.randomUUID(),
      ref: `M-APPS-${String(this.rows.length).padStart(4, '0')}`,
      confirmationSentAt: null,
    };
    this.rows.push(row);
    return Promise.resolve({ id: row.id, ref: row.ref, confirm: report.email !== null });
  }

  confirmationSent(id: string, now: Date): Promise<boolean> {
    const row = this.rows.find((x) => x.id === id);
    if (row) row.confirmationSentAt = now;
    return Promise.resolve(!!row);
  }
}

function setup(over: { authenticate?: (req: Request) => Promise<{ userId: string }> } = {}) {
  const store = new FakeAppStore();
  const sent: { to: string; mail: Mail; key: string }[] = [];
  const deferred: (() => Promise<void>)[] = [];
  const handler = createHandler({
    config: configFrom(new Map()).config,
    store: {
      submit: () => Promise.reject(new Error('the web route was called')),
      confirmationSent: (id, now) => store.confirmationSent(id, now),
    } satisfies Store,
    app: {
      authenticate: over.authenticate ?? ((req) => {
        const auth = req.headers.get('authorization') ?? '';
        if (auth === `Bearer ${TOKEN}`) return Promise.resolve({ userId: USER });
        if (auth.startsWith('Bearer ')) {
          return Promise.resolve({ userId: auth.slice('Bearer '.length) });
        }
        return Promise.reject(new AuthError('missing_token', 'Authorization fehlt.'));
      }),
      store,
    },
    mailer: {
      send(to, mail, key) {
        sent.push({ to, mail, key });
        return Promise.resolve();
      },
    },
    now: () => T0,
    random: (n) => new Uint8Array(n),
    defer: (work) => {
      deferred.push(work);
    },
    sleep: () => Promise.resolve(),
  });
  const call = (
    body: unknown,
    init: { path?: string; method?: string; token?: string | null } = {},
  ) =>
    handler(
      new Request(`http://localhost${init.path ?? '/functions/v1/report/app'}`, {
        method: init.method ?? 'POST',
        headers: init.token === null ? {} : { authorization: `Bearer ${init.token ?? TOKEN}` },
        ...(init.method === 'GET' || init.method === 'OPTIONS'
          ? {}
          : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
      }),
    );
  const flush = async () => {
    for (let work = deferred.shift(); work; work = deferred.shift()) await work();
  };
  return { store, sent, deferred, handler, call, flush };
}

const form = (extra: Record<string, unknown> = {}) => ({
  locale: 'en',
  category: 'personal_rights',
  target: { kind: 'item', id: ITEM },
  location: ' item "Foto von Anna" in list "Einkauf", household "WG"  ',
  reason: '  This item names me and my address without my consent.  ',
  name: 'Anna Beispiel',
  email: 'test+report-app@snacklist.app',
  good_faith: true,
  screenshot: base64(PNG),
  ...extra,
});

async function logsOf(work: () => Promise<unknown>): Promise<string[]> {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => lines.push(args.join(' '));
  try {
    await work();
  } finally {
    console.log = original;
  }
  return lines;
}

Deno.test('an app report is stored for the session user with its target and screenshot, without the proxy secret', async () => {
  const { store, call } = setup();
  const res = await call(form());
  assertEquals(res.status, 201);
  assertEquals(res.headers.get('access-control-allow-origin'), '*');
  assertEquals(res.headers.get('cache-control'), 'no-store');
  const [row] = store.rows;
  assertExists(row);
  assertEquals(await res.json(), { ref: row.ref });
  assertEquals(row.userId, USER);
  assertEquals(row.report, {
    locale: 'en',
    category: 'personal_rights',
    location: 'item "Foto von Anna" in list "Einkauf", household "WG"',
    reason: 'This item names me and my address without my consent.',
    name: 'Anna Beispiel',
    email: 'test+report-app@snacklist.app',
    target: { kind: 'item', id: ITEM.toLowerCase() },
    screenshot: PNG,
  });
});

Deno.test('elsewhere has no id, and the screenshot is optional', async () => {
  const { store, call } = setup();
  const { screenshot: _s, ...noShot } = form({ target: { kind: 'elsewhere' } });
  assertEquals((await call(noShot)).status, 201);
  assertEquals(
    (await call(form({ target: { kind: 'elsewhere', id: null }, screenshot: null })))
      .status,
    201,
  );
  assertEquals(
    store.rows.map((r) => [r.report.target, r.report.screenshot]),
    [[{ kind: 'elsewhere' }, null], [{ kind: 'elsewhere' }, null]],
  );
});

Deno.test('the confirmation goes out after the answer, through the web route path', async () => {
  const { store, sent, deferred, call, flush } = setup();
  assertEquals((await call(form())).status, 201);
  assertEquals([sent.length, deferred.length], [0, 1]);
  await flush();
  const [mail] = sent;
  const [row] = store.rows;
  assertExists(mail);
  assertExists(row);
  assertEquals(mail.to, 'test+report-app@snacklist.app');
  assertEquals(mail.key, `report-confirm/${row.id}`);
  assertEquals(mail.mail.subject, `We've received your report to Snacklist (${row.ref})`);
  assertEquals(row.confirmationSentAt, T0);
});

Deno.test('the preflight answers 204 with CORS, before any token', async () => {
  const { store, call } = setup();
  const res = await call(null, { method: 'OPTIONS', token: null });
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('access-control-allow-methods'), 'GET, POST, OPTIONS');
  assertEquals(store.calls, 0);
});

Deno.test('auth failures give the shared answer; nothing is stored', async () => {
  const missing = setup();
  const res = await missing.call(form(), { token: null });
  assertEquals(res.status, 401);
  assertEquals(res.headers.get('www-authenticate'), 'Bearer');
  assertEquals((await res.json()).error, 'missing_token');

  const pat = setup({
    authenticate: () => Promise.reject(new AuthError('session_required', 'Nur in der App.')),
  });
  const refused = await pat.call(form());
  assertEquals(refused.status, 403);
  assertEquals((await refused.json()).error, 'session_required');

  const broken = setup({ authenticate: () => Promise.reject(new Error('db down')) });
  const res503 = await broken.call(form());
  assertEquals(res503.status, 503);
  assertEquals(await res503.json(), { error: 'unavailable' });
  assertEquals([missing.store.calls, pat.store.calls, broken.store.calls], [0, 0, 0]);
});

Deno.test('invalid app bodies answer 400 invalid_request and store nothing', async (t) => {
  const cases: [string, unknown][] = [
    ['no target', form({ target: undefined })],
    ['target not an object', form({ target: 'item' })],
    ['unknown kind', form({ target: { kind: 'photo', id: ITEM } })],
    ['item without id', form({ target: { kind: 'item' } })],
    ['item with a non-uuid id', form({ target: { kind: 'list', id: 'list-1' } })],
    ['elsewhere with an id', form({ target: { kind: 'elsewhere', id: ITEM } })],
    ['screenshot not base64', form({ screenshot: '***' })],
    [
      'screenshot not a PNG',
      form({ screenshot: base64(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8])) }),
    ],
    ['screenshot not a string', form({ screenshot: [1, 2] })],
    ['the shared fields still apply: short reason', form({ reason: 'too short' })],
    ['good_faith missing', form({ good_faith: undefined })],
    ['not json', '{"locale":'],
  ];
  for (const [name, body] of cases) {
    await t.step(name, async () => {
      const { store, call } = setup();
      const res = await call(body);
      assertEquals(res.status, 400);
      assertEquals(await res.json(), { error: 'invalid_request' });
      assertEquals(store.calls, 0);
    });
  }
});

Deno.test('a screenshot over MAX_SCREENSHOT or a body over MAX_APP_BODY is 413 too_large', async () => {
  const { store, call } = setup();
  const big = new Uint8Array(MAX_SCREENSHOT + 1);
  big.set(PNG);
  let binary = '';
  for (let i = 0; i < big.length; i += 0x8000) {
    binary += String.fromCharCode(...big.subarray(i, i + 0x8000));
  }
  const over = await call(form({ screenshot: btoa(binary) }));
  assertEquals(over.status, 413);
  assertEquals(await over.json(), { error: 'too_large' });
  assertEquals((await call(form({ padding: 'x'.repeat(MAX_APP_BODY) }))).status, 413);
  const atLimit = new Uint8Array(MAX_SCREENSHOT);
  atLimit.set(PNG);
  binary = '';
  for (let i = 0; i < atLimit.length; i += 0x8000) {
    binary += String.fromCharCode(...atLimit.subarray(i, i + 0x8000));
  }
  assertEquals((await call(form({ screenshot: btoa(binary) }))).status, 201, '2 MiB fit');
  assertEquals(store.rows.length, 1);
});

Deno.test('a body declared over MAX_APP_BODY is read to its end before the 413', async () => {
  const { store, handler } = setup();
  const seen = { pulled: 0, cancelled: false };
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (seen.pulled === 3) return controller.close();
      seen.pulled++;
      controller.enqueue(new Uint8Array(1024));
    },
    cancel() {
      seen.cancelled = true;
    },
  }, { highWaterMark: 0 });
  const res = await handler(
    new Request('http://localhost/functions/v1/report/app', {
      method: 'POST',
      headers: { authorization: `Bearer ${TOKEN}`, 'content-length': `${MAX_APP_BODY + 1}` },
      body,
    }),
  );
  assertEquals(res.status, 413);
  assertEquals(
    seen,
    { pulled: 3, cancelled: false },
    'the edge runtime drops answers to unread bodies',
  );
  assertEquals(store.rows.length, 0);
});

Deno.test('the limits: 429 rate_limited with a code saying which; another user still gets through', async () => {
  const { store, call } = setup();
  for (let i = 0; i < APP_LIMITS.perUserHour; i++) assertEquals((await call(form())).status, 201);
  let res: Response | undefined;
  const userLogs = await logsOf(async () => {
    res = await call(form());
  });
  assertEquals(res?.status, 429);
  assertEquals(await res?.json(), { error: 'rate_limited' });
  assertEquals(userLogs, ['report: user_cap_hit', 'report 429']);
  assertEquals((await call(form(), { token: 'another-user' })).status, 201);

  for (let i = store.rows.length; i < APP_LIMITS.perHour; i++) {
    assertEquals((await call(form(), { token: `user-${i}` })).status, 201);
  }
  const globalLogs = await logsOf(async () => {
    res = await call(form(), { token: 'a-third-user' });
  });
  assertEquals(res?.status, 429);
  assertEquals(globalLogs, ['report: global_cap_hit', 'report 429']);
});

Deno.test('a store failure answers 503 and logs the SQLSTATE only', async () => {
  const { store, call } = setup();
  store.failWith = Object.assign(new Error('violates check: test+report-app@snacklist.app'), {
    code: '23514',
  });
  let res: Response | undefined;
  const logs = await logsOf(async () => {
    res = await call(form());
  });
  assertEquals(res?.status, 503);
  assertEquals(logs, ['report: app_failed 23514', 'report 503']);
});

Deno.test('logs are fixed codes: no user id, address, name, ref or body', async () => {
  const { call, flush } = setup();
  const logs = await logsOf(async () => {
    await call(form());
    await flush();
    await call(form({ reason: 'zu kurz' }));
    await call(form(), { token: null });
  });
  assertEquals(logs, [
    'report: app_stored',
    'report: confirmation_sent',
    'report 400',
    'report: missing_token',
    'report 401',
  ]);
  assert(!logs.join('\n').includes(USER));
});

Deno.test('other methods and paths under /report/app are 404; the web route stays behind its secret', async () => {
  const { store, call } = setup();
  assertEquals((await call(null, { method: 'GET' })).status, 404);
  assertEquals((await call(form(), { path: '/report/app/extra' })).status, 404);
  assertEquals((await call(form(), { path: '/report' })).status, 404);
  assertEquals((await call(form(), { path: '/report/app' })).status, 201);
  assertEquals(store.rows.length, 1);
});
