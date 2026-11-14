import { sha256Hex } from '../_shared/auth.ts';
import { assert, assertEquals, assertExists, assertFalse } from '@std/assert';
import { ToolError } from '../_shared/list.ts';
import {
  type Begin,
  beginOf,
  type Deps,
  type Execution,
  handle,
  type Key,
  routePath,
} from './handler.ts';

const BASE = 'http://localhost/api/v1';
const TOKEN = 'fgp_' + 'a'.repeat(43);

const writer: Key = {
  tokenId: '11111111-1111-4111-8111-111111111111',
  userId: '22222222-2222-4222-8222-222222222222',
  householdId: '33333333-3333-4333-8333-333333333333',
  scopes: ['read', 'write'],
};
const reader: Key = { ...writer, scopes: ['read'] };
const ID = '44444444-4444-4444-8444-444444444444';

type Fake = Deps & {
  begun: { tokenHash: string | null; ipHash: string }[];
  executed: Execution[];
  logs: Record<string, unknown>[];
  keysUsed: { key: Key; scope: string }[];
};

function fake(
  { begin = ok(writer), premium = 'open', result = { status: 200, body: { data: [] } } }: {
    begin?: Begin;
    premium?: 'open' | 'locked' | 'throws';
    result?: { status: number; body: unknown } | Error;
  } = {},
): Fake {
  const deps: Fake = {
    begun: [],
    executed: [],
    logs: [],
    keysUsed: [],
    begin: (tokenHash, ipHash) => {
      deps.begun.push({ tokenHash, ipHash });
      return Promise.resolve(begin);
    },
    premium: () =>
      premium === 'throws' ? Promise.reject(new Error('down')) : Promise.resolve(premium),
    used: (key, scope) => {
      deps.keysUsed.push({ key, scope });
      return Promise.resolve();
    },
    execute: (execution) => {
      deps.executed.push(execution);
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve({ ...result, replayed: false });
    },
    report: () => {},
    log: (line) => deps.logs.push(line),
  };
  return deps;
}

function ok(key: Key): Begin {
  return { outcome: 'ok', rate: { limit: 20, remaining: 19, reset: 1 }, key };
}

function call(
  path: string,
  init: RequestInit & { token?: string | null } = {},
): Request {
  const headers = new Headers(init.headers);
  const token = init.token === undefined ? TOKEN : init.token;
  if (token) headers.set('authorization', `Bearer ${token}`);
  if (init.body !== undefined && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }
  return new Request(`${BASE}${path}`, { ...init, headers });
}

async function errorOf(
  res: Response,
): Promise<{ code: string; details?: Record<string, unknown> }> {
  const body = await res.json();
  assertEquals(Object.keys(body), ['error']);
  return body.error;
}

function assertRateHeaders(res: Response, limit: string, remaining: string) {
  assertEquals(res.headers.get('x-ratelimit-limit'), limit);
  assertEquals(res.headers.get('x-ratelimit-remaining'), remaining);
  assert(res.headers.get('x-ratelimit-reset') !== null);
  assert(/^[0-9a-f-]{36}$/.test(res.headers.get('x-request-id') ?? ''));
}

const invalid: Begin = { outcome: 'invalid', rate: { limit: 20, remaining: 17, reset: 590 } };

Deno.test('no key is 401 missing_token, and the failure budget is in the headers', async () => {
  const deps = fake({ begin: invalid });
  const res = await handle(call('/items', { token: null }), deps);
  assertEquals(res.status, 401);
  assertEquals((await errorOf(res)).code, 'missing_token');
  assertRateHeaders(res, '20', '17');
  assertEquals(deps.begun, [{ tokenHash: null, ipHash: await sha256Hex('no-address') }]);
  assertEquals(deps.executed, []);
});

Deno.test('a bad or foreign credential is 401 invalid_token; only fgp_ tokens are looked up', async () => {
  for (const token of [TOKEN, 'eyJhbGciOi.jwt.token']) {
    const deps = fake({ begin: invalid });
    const res = await handle(
      call('/items', { token, headers: { 'x-forwarded-for': '203.0.113.7, 10.0.0.1' } }),
      deps,
    );
    assertEquals(res.status, 401);
    assertEquals((await errorOf(res)).code, 'invalid_token');
    assertRateHeaders(res, '20', '17');
    const [begun] = deps.begun;
    assertExists(begun);
    const { tokenHash, ipHash } = begun;
    assertEquals(tokenHash === null, !token.startsWith('fgp_'));
    assert(/^[0-9a-f]{64}$/.test(ipHash), 'the address goes in only as its hash');
  }
});

Deno.test("the address is the gateway's X-Real-IP; a forged X-Forwarded-For changes nothing", async () => {
  const hashes = [];
  for (const forwarded of ['198.51.100.1', '198.51.100.2, 10.0.0.1']) {
    const deps = fake({ begin: invalid });
    await handle(
      call('/items', {
        token: TOKEN,
        headers: { 'x-real-ip': '203.0.113.7', 'x-forwarded-for': forwarded },
      }),
      deps,
    );
    hashes.push(deps.begun[0]?.ipHash);
  }
  assertEquals(hashes, [await sha256Hex('203.0.113.7'), await sha256Hex('203.0.113.7')]);
});

Deno.test('a throttled address gets 429 auth_throttled with Retry-After', async () => {
  const deps = fake({
    begin: { outcome: 'blocked', rate: { limit: 20, remaining: 0, reset: 312 }, retryAfter: 312 },
  });
  const res = await handle(call('/items'), deps);
  assertEquals(res.status, 429);
  assertEquals((await errorOf(res)).code, 'auth_throttled');
  assertEquals(res.headers.get('retry-after'), '312');
  assertRateHeaders(res, '20', '0');
});

Deno.test('a key over its limit gets 429 rate_limited with Retry-After and X-RateLimit-*', async () => {
  const deps = fake({
    begin: {
      outcome: 'limited',
      rate: { limit: 20, remaining: 0, reset: 20 },
      retryAfter: 1,
      key: writer,
    },
  });
  const res = await handle(call('/items'), deps);
  assertEquals(res.status, 429);
  assertEquals((await errorOf(res)).code, 'rate_limited');
  assertEquals(res.headers.get('retry-after'), '1');
  assertEquals(res.headers.get('x-ratelimit-reset'), '20');
  assertRateHeaders(res, '20', '0');
  assertEquals(deps.executed, []);
});

Deno.test('a read key cannot write: 403 insufficient_scope names the scope', async () => {
  for (
    const req of [
      call('/items', { method: 'POST', body: JSON.stringify({ items: [{ name: 'Milch' }] }) }),
      call(`/items/${ID}/tick`, { method: 'POST' }),
      call(`/items/${ID}`, { method: 'PATCH', body: JSON.stringify({ store: null }) }),
    ]
  ) {
    const deps = fake({ begin: ok(reader) });
    const res = await handle(req, deps);
    assertEquals(res.status, 403);
    const error = await errorOf(res);
    assertEquals(error.code, 'insufficient_scope');
    assertEquals(error.details, { required: 'write' });
    assertEquals(deps.executed, []);
  }
  const deps = fake({ begin: ok(reader) });
  assertEquals((await handle(call('/items'), deps)).status, 200, 'it can read');
});

Deno.test('a household without Premium under the lock gets 402 and nothing runs', async () => {
  const deps = fake({ premium: 'locked' });
  const res = await handle(
    call('/items', { method: 'POST', body: JSON.stringify({ items: [{ name: 'Milch' }] }) }),
    deps,
  );
  assertEquals(res.status, 402);
  assertEquals((await errorOf(res)).code, 'premium_required');
  assertEquals(deps.executed, []);
  assertRateHeaders(res, '20', '19');
});

Deno.test('api_key_used (job 195): once per request let through, with its scope only', async () => {
  const read = fake();
  await handle(call('/items'), read);
  assertEquals(read.keysUsed, [{ key: writer, scope: 'read' }]);
  const write = fake();
  await handle(call(`/items/${ID}/tick`, { method: 'POST' }), write);
  assertEquals(write.keysUsed, [{ key: writer, scope: 'write' }]);
  const failing = fake({ result: new Error('down') });
  assertEquals((await handle(call('/items'), failing)).status, 500);
  assertEquals(failing.keysUsed.length, 1, 'authorized, then the operation failed');

  const refused: [string, Fake, Request][] = [
    ['no key', fake({ begin: invalid }), call('/items', { token: null })],
    ['unknown key', fake({ begin: invalid }), call('/items')],
    ['disabled', fake({ begin: { outcome: 'disabled' } }), call('/items')],
    ['missing scope', fake({ begin: ok(reader) }), call(`/items/${ID}/tick`, { method: 'POST' })],
    ['locked', fake({ premium: 'locked' }), call('/items')],
    ['gate down', fake({ premium: 'throws' }), call('/items')],
    ['no route', fake(), call('/nothing')],
  ];
  for (const [why, deps, req] of refused) {
    await handle(req, deps);
    assertEquals(deps.keysUsed, [], why);
  }
});

Deno.test('api_key_used: the answer waits for the event, also when the body is refused', async () => {
  for (
    const [why, req, status] of [
      ['ok', call('/items'), 200],
      ['bad body', call('/items', { method: 'POST', body: '{"items":"Milch"}' }), 400],
    ] as const
  ) {
    const deps = fake();
    let queued = false;
    deps.used = () =>
      new Promise((r) =>
        setTimeout(() => {
          queued = true;
          r();
        }, 20)
      );
    assertEquals((await handle(req, deps)).status, status, why);
    assert(queued, `${why}: queued before the answer, so the flush sends it`);
  }
});

Deno.test('an unlocked household runs the operation and gets its answer', async () => {
  const deps = fake({ result: { status: 201, body: { data: { added: [] } } } });
  const res = await handle(
    call('/items', {
      method: 'POST',
      body: JSON.stringify({ items: [{ name: '2 Gurken', store: 'Lidl' }] }),
    }),
    deps,
  );
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { data: { added: [] } });
  assertEquals(deps.executed.length, 1);
  assertEquals(deps.executed[0]?.key, writer);
  assertEquals(deps.executed[0]?.idempotency, null, 'no Idempotency-Key, no claim');
  assertRateHeaders(res, '20', '19');
});

Deno.test('a failing Premium check is 503 unavailable, never locked or open', async () => {
  const deps = fake({ premium: 'throws' });
  const res = await handle(call('/items'), deps);
  assertEquals(res.status, 503);
  assertEquals((await errorOf(res)).code, 'unavailable');
  assertEquals(res.headers.get('retry-after'), '5');
  assertEquals(deps.executed, []);
});

async function rejected(req: Request, status: number, code: string) {
  const deps = fake();
  const res = await handle(req, deps);
  assertEquals(res.status, status, code);
  const error = await errorOf(res);
  assertEquals(error.code, code);
  assertEquals(deps.executed, [], `${code}: nothing ran`);
  assertRateHeaders(res, '20', '19');
  return error;
}

const post = (body: string, headers: Record<string, string> = {}) =>
  call('/items', { method: 'POST', body, headers });

Deno.test('unknown fields and query parameters are 400 validation_failed, values not echoed', async () => {
  const unknownField = await rejected(
    post(JSON.stringify({ items: [{ name: 'Milch', colour: 'Rotkohl-geheim' }] })),
    400,
    'validation_failed',
  );
  const issues = unknownField.details?.issues as { path: string; message: string }[];
  assertEquals(issues.map((i) => i.path), ['body.items.0']);
  assertFalse(JSON.stringify(issues).includes('Rotkohl-geheim'));

  const unknownParam = await rejected(call('/items?sort=name'), 400, 'validation_failed');
  assertEquals((unknownParam.details?.issues as { path: string }[])[0]?.path, 'query');
  await rejected(call('/items?store=dm&store=Lidl'), 400, 'validation_failed');
  await rejected(call('/items?limit=0'), 400, 'validation_failed');
  await rejected(call('/items?limit=101'), 400, 'validation_failed');
  await rejected(call('/categories?limit=5'), 400, 'validation_failed');
});

Deno.test('field limits: name 1 to 120, quantity non-empty, batch 1 to 50', async () => {
  const name = await rejected(
    post(JSON.stringify({ items: [{ name: 'x'.repeat(121) }] })),
    400,
    'validation_failed',
  );
  assertEquals((name.details?.issues as { path: string }[])[0]?.path, 'body.items.0.name');
  await rejected(post(JSON.stringify({ items: [{ name: '   ' }] })), 400, 'validation_failed');
  await rejected(
    post(JSON.stringify({ items: [{ name: 'Milch', quantity: ' ' }] })),
    400,
    'validation_failed',
  );
  await rejected(
    post(JSON.stringify({ items: [{ name: 'Milch', store: 's'.repeat(61) }] })),
    400,
    'validation_failed',
  );
  await rejected(post(JSON.stringify({ items: [] })), 400, 'validation_failed');
  const items = Array.from({ length: 51 }, (_, i) => ({ name: `Item ${i}` }));
  await rejected(post(JSON.stringify({ items })), 400, 'validation_failed');
  await rejected(call('/items', { method: 'POST' }), 400, 'validation_failed');
  await rejected(
    call(`/items/${ID}`, { method: 'PATCH', body: '{}' }),
    400,
    'validation_failed',
  );

  const deps = fake();
  const fifty = Array.from({ length: 50 }, (_, i) => ({ name: `Item ${i}` }));
  assertEquals((await handle(post(JSON.stringify({ items: fifty })), deps)).status, 200);
  assertEquals(deps.executed.length, 1, '50 items are fine');
});

Deno.test('a body must be JSON, application/json and at most 64 KiB', async () => {
  await rejected(
    post('{"items":[{"name":"Milch"}]}', { 'content-type': 'text/plain' }),
    415,
    'unsupported_media_type',
  );
  await rejected(post('{"items": [', {}), 400, 'invalid_json');
  const huge = JSON.stringify({ items: [{ name: 'Milch', properties: 'x'.repeat(70_000) }] });
  await rejected(post(huge), 413, 'payload_too_large');

  // A body streamed without Content-Length is counted while it is read.
  const chunk = new TextEncoder().encode('x'.repeat(16 * 1024));
  let sent = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (sent++ < 8) controller.enqueue(chunk);
      else controller.close();
    },
  });
  await rejected(post(stream as unknown as string), 413, 'payload_too_large');
});

Deno.test('an {id} that is not a UUID is 400 invalid_id', async () => {
  await rejected(call('/items/milch'), 400, 'invalid_id');
  await rejected(call('/items/milch/tick', { method: 'POST' }), 400, 'invalid_id');
});

Deno.test('unknown paths are 404 not_found, wrong methods 405 with Allow', async () => {
  await rejected(call('/shops'), 404, 'not_found');
  await rejected(call('/items/'), 404, 'not_found');
  await rejected(
    new Request('http://localhost/api/v2/items', {
      headers: { authorization: `Bearer ${TOKEN}` },
    }),
    404,
    'not_found',
  );
  const deps = fake();
  const res = await handle(call('/items', { method: 'DELETE' }), deps);
  assertEquals(res.status, 405);
  assertEquals((await errorOf(res)).code, 'method_not_allowed');
  assertEquals(res.headers.get('allow'), 'GET, POST');
  const one = await handle(call(`/items/${ID}`, { method: 'PUT', body: '{}' }), fake());
  assertEquals(one.headers.get('allow'), 'GET, PATCH');
});

Deno.test('a broken cursor is 400 invalid_cursor before anything runs', async () => {
  await rejected(call('/items?cursor=not-a-cursor'), 400, 'invalid_cursor');
  const forged = btoa(JSON.stringify({ v: 2, f: [null, null], k: [1, 'x', '1', 'y', ID] }));
  await rejected(call(`/items?cursor=${encodeURIComponent(forged)}`), 400, 'invalid_cursor');
  const injected = btoa(JSON.stringify({
    v: 1,
    f: [null, null],
    k: [1, 'Kühlregal', "1'; drop table items; --", '2026-11-02T08:00:00+00:00', ID],
  }));
  await rejected(call(`/items?cursor=${encodeURIComponent(injected)}`), 400, 'invalid_cursor');
});

Deno.test('a cursor passes only with a position the database can compare', async () => {
  const withPosition = (k: unknown[]) =>
    call(`/items?cursor=${
      encodeURIComponent(
        btoa(
          String.fromCharCode(
            ...new TextEncoder().encode(JSON.stringify({ v: 1, f: [null, null], k })),
          ),
        ),
      )
    }`);
  const at = '2026-11-02T08:00:00.123456+00:00';
  for (
    const k of [
      [10, 'Kühlregal', '1024', at, ID],
      [10, 'Kühlregal', '100352.0009765625', at, ID],
      [10, 'Kühlregal', 'Infinity', at, ID],
      [-3, 'Kühlregal', '-1e+21', '2024-02-29T23:59:59-11:30', ID],
    ]
  ) {
    const deps = fake();
    assertEquals((await handle(withPosition(k), deps)).status, 200, JSON.stringify(k));
    assertEquals(deps.executed.length, 1);
  }
  for (
    const k of [
      [2 ** 31, 'Kühlregal', '1024', at, ID],
      [1.5, 'Kühlregal', '1024', at, ID],
      [10, 'Kühl\u0000regal', '1024', at, ID],
      [10, 'Kühlregal', "1'; drop table items; --", at, ID],
      [10, 'Kühlregal', '1e999', at, ID],
      [10, 'Kühlregal', '1e-400', at, ID],
      [10, 'Kühlregal', '1024.0', at, ID],
      [10, 'Kühlregal', '', at, ID],
      [10, 'Kühlregal', '1024', '2026-02-30T08:00:00+00:00', ID],
      [10, 'Kühlregal', '1024', '2026-13-02T08:00:00+00:00', ID],
      [10, 'Kühlregal', '1024', '2026-11-02T24:00:00+00:00', ID],
      [10, 'Kühlregal', '1024', '0000-01-01T00:00:00+00:00', ID],
      [10, 'Kühlregal', '1024', '2026-11-02T08:00:00+16:00', ID],
      [10, 'Kühlregal', '1024', '2026-11-02T08:00:00Z', ID],
    ]
  ) {
    await rejected(withPosition(k), 400, 'invalid_cursor');
  }
});

Deno.test('text with U+0000, which the database cannot store, is 400 validation_failed', async () => {
  const name = await rejected(
    post(JSON.stringify({ items: [{ name: 'Mi\u0000lch' }] })),
    400,
    'validation_failed',
  );
  assertEquals((name.details?.issues as { path: string }[])[0]?.path, 'body.items.0.name');
  for (const field of ['quantity', 'brand', 'properties', 'category', 'store']) {
    await rejected(
      post(JSON.stringify({ items: [{ name: 'Milch', [field]: 'a\u0000b' }] })),
      400,
      'validation_failed',
    );
  }
  await rejected(
    post(JSON.stringify({ list: '\u0000', items: [{ name: 'Milch' }] })),
    400,
    'validation_failed',
  );
  await rejected(call('/items?store=d%00m'), 400, 'validation_failed');
  await rejected(
    call(`/items/${ID}`, { method: 'PATCH', body: JSON.stringify({ category: 'a\u0000' }) }),
    400,
    'validation_failed',
  );
});

Deno.test('Idempotency-Key: printable ASCII, 1 to 255; the same request hashes the same', async () => {
  const body = JSON.stringify({ items: [{ name: 'Milch', quantity: '2' }] });
  await rejected(
    post(body, { 'idempotency-key': 'x'.repeat(256) }),
    400,
    'invalid_idempotency_key',
  );
  await rejected(
    post(body, { 'idempotency-key': 'mit leerzeichen' }),
    400,
    'invalid_idempotency_key',
  );

  const deps = fake();
  await handle(post(body, { 'idempotency-key': 'k-1' }), deps);
  await handle(
    post('{ "items": [ { "quantity": "2", "name": "Milch" } ] }', { 'idempotency-key': 'k-1' }),
    deps,
  );
  await handle(
    post(JSON.stringify({ items: [{ name: 'Brot' }] }), { 'idempotency-key': 'k-1' }),
    deps,
  );
  await handle(
    call(`/items/${ID}/tick`, { method: 'POST', headers: { 'idempotency-key': 'k-1' } }),
    deps,
  );
  const [a, b, c, d] = deps.executed.map((e) => e.idempotency);
  assertExists(a);
  assertExists(b);
  assertExists(c);
  assertExists(d);
  assertEquals(a.key, 'k-1');
  assertEquals(a.requestHash, b.requestHash, 'key order and spacing do not matter');
  assert(a.requestHash !== c.requestHash, 'another body is another request');
  assert(a.requestHash !== d.requestHash, 'another path is another request');

  await handle(call('/items', { headers: { 'idempotency-key': 'k-1' } }), deps);
  assertEquals(deps.executed[4]?.idempotency, null, 'a GET takes no key');
});

Deno.test('list errors map to their codes; a unique violation is 409; the rest 500', async () => {
  const cases: [Error, number, string][] = [
    [new ToolError('x', 'not_found', 'item', [], ID), 404, 'item_not_found'],
    [new ToolError('x', 'not_found', 'store', ['dm', 'Lidl'], 'Rewe'), 422, 'store_not_found'],
    [new ToolError('x', 'not_found', 'category', [], 'Deko'), 422, 'category_not_found'],
    [
      new ToolError('x', 'ambiguous', 'store', ['Aldi Süd', 'Aldi Sued'], 'aldi'),
      422,
      'ambiguous_store',
    ],
    [new ToolError('x', 'ambiguous', 'category', ['a', 'b'], 'x'), 422, 'ambiguous_category'],
    [new ToolError('x', 'not_found', 'list', ['Einkaufsliste'], 'Baumarkt'), 422, 'list_not_found'],
    [new ToolError('x', 'ambiguous', 'list', ['a', 'b'], 'Fest'), 422, 'ambiguous_list'],
    [Object.assign(new Error('dup'), { name: 'PostgresError', code: '23505' }), 409, 'conflict'],
    [
      Object.assign(new Error('gone'), { name: 'PostgresError', code: '57P01' }),
      503,
      'unavailable',
    ],
    [Object.assign(new Error('closed'), { code: 'CONNECTION_CLOSED' }), 503, 'unavailable'],
    [new TypeError('boom'), 500, 'internal_error'],
  ];
  for (const [thrown, status, code] of cases) {
    const res = await handle(call('/items'), fake({ result: thrown }));
    assertEquals(res.status, status, code);
    const error = await errorOf(res);
    assertEquals(error.code, code);
    if (code === 'store_not_found') assertEquals(error.details, { candidates: ['dm', 'Lidl'] });
  }
});

Deno.test('one log line per request: template, status, key id; never the id or a query value', async () => {
  const deps = fake();
  await handle(call(`/items/${ID}?store=Geheimladen`), deps);
  await handle(call(`/items/${ID}`), deps);
  assertEquals(deps.logs.length, 2);
  const [first, second] = deps.logs;
  assertExists(first);
  assertExists(second);
  assertEquals(first.route, '/v1/items/{id}');
  assertEquals(first.status, 400, 'an unknown query parameter');
  assertEquals(second.fn, 'api');
  assertEquals(second.route, '/v1/items/{id}');
  assertEquals(second.status, 200);
  assertEquals(second.method, 'GET');
  assertEquals(second.tokenId, writer.tokenId);
  const text = JSON.stringify(deps.logs);
  assertFalse(text.includes(ID));
  assertFalse(text.includes('Geheimladen'));
});

Deno.test('switched off, every request answers like an unknown path: 404, no limits, nothing runs', async () => {
  const absent = await (await handle(call('/shops'), fake())).json();
  assertEquals(absent, { error: { code: 'not_found', message: 'No such endpoint.' } });
  for (
    const req of [
      call('/items'),
      call('/items', { token: null }),
      post(JSON.stringify({ items: [{ name: 'Milch' }] })),
    ]
  ) {
    const deps = fake({ begin: { outcome: 'disabled' }, premium: 'throws' });
    const res = await handle(req, deps);
    assertEquals(res.status, 404, `${req.method} ${req.url}`);
    assertEquals(await res.json(), absent);
    assertEquals([...res.headers.keys()].filter((h) => h.startsWith('x-ratelimit-')), []);
    assertEquals(res.headers.get('retry-after'), null);
    assert(/^[0-9a-f-]{36}$/.test(res.headers.get('x-request-id') ?? ''));
    assertEquals(res.headers.get('access-control-allow-origin'), '*');
    assertEquals(deps.executed, []);
    assertEquals(deps.logs.map((l) => [l.status, l.route, l.tokenId]), [[404, null, null]]);
  }
  const preflight = fake({ begin: { outcome: 'disabled' } });
  const res = await handle(new Request(`${BASE}/items`, { method: 'OPTIONS' }), preflight);
  assertEquals(res.status, 204);
});

Deno.test("api_begin's disabled row carries no key and no rate", () => {
  assertEquals(
    beginOf({
      outcome: 'disabled',
      token_id: null,
      user_id: null,
      household_id: null,
      scopes: null,
      rate_limit: 0,
      rate_remaining: 0,
      rate_reset: 0,
      retry_after: null,
    }),
    { outcome: 'disabled' },
  );
});

Deno.test('OPTIONS answers CORS for the API headers without touching the key', async () => {
  const deps = fake();
  const res = await handle(new Request(`${BASE}/items`, { method: 'OPTIONS' }), deps);
  assertEquals(res.status, 204);
  assert(res.headers.get('access-control-allow-headers')?.includes('idempotency-key'));
  assert(res.headers.get('access-control-expose-headers')?.includes('x-ratelimit-remaining'));
  assertEquals(deps.begun, []);
});

Deno.test('the route path drops the hosted and the local function prefix', () => {
  assertEquals(routePath('/functions/v1/api/v1/items'), '/v1/items');
  assertEquals(routePath('/api/v1/items/x/tick'), '/v1/items/x/tick');
  assertEquals(routePath('/v1/items'), '/v1/items');
  assertEquals(routePath('/apix/v1/items'), '/apix/v1/items');
});
