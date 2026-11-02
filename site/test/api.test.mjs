import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { clientNetwork, handle } from '../api/_waitlist.mjs';
import * as signupRoute from '../api/waitlist/index.mjs';
import * as confirmRoute from '../api/waitlist/confirm.mjs';
import * as unsubscribeRoute from '../api/waitlist/unsubscribe.mjs';

const ENV = { WAITLIST_UPSTREAM_URL: 'https://ref.supabase.co/functions/v1/waitlist/', WAITLIST_PROXY_SECRET: 'proxy-secret' };
const NOW = new Date('2026-11-02T23:59:59Z');
const IP = '203.0.113.7';
const EMAIL = 'hello+waitlisttest@hummlist.com';
const SIGNUP = { email: EMAIL, platform: 'ios', locale: 'de', launch_news: false, consent_version: 'waitlist-de-v1', website: '', elapsed_ms: 5000 };

const log = mock.method(console, 'log', () => {});
beforeEach(() => log.mock.resetCalls());

function upstream(status = 202, text = '{"status":"ok"}') {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, method: init.method, headers: Object.fromEntries(new Headers(init.headers)), body: JSON.parse(init.body) });
    return new Response(text, { status, headers: { 'content-type': 'application/json' } });
  };
  return { calls, fetch };
}

const PATHS = { signup: '/api/waitlist', confirm: '/api/waitlist/confirm', unsubscribe: '/api/waitlist/unsubscribe' };

function request(route, { method = 'POST', body = SIGNUP, query = '', host = 'hummlist.com', headers = { 'x-real-ip': IP } } = {}) {
  const text = body === undefined || typeof body === 'string' ? body : JSON.stringify(body);
  return new Request(`https://${host}${PATHS[route]}${query}`, {
    method,
    headers: { host, ...(method === 'POST' ? { 'content-type': 'application/json' } : {}), ...headers },
    body: method === 'POST' ? text : undefined,
  });
}

const call = (route, options, { env = ENV, fetch, timeoutMs } = {}) => handle(route, request(route, options), { env, fetch, now: NOW, timeoutMs });

async function read(res) {
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null, type: res.headers.get('content-type'), cache: res.headers.get('cache-control'), res };
}

const clientKey = (ip) => createHmac('sha256', 'proxy-secret').update(`2026-11-02|${ip}`).digest('hex');

test('every route answers 404 not_found and calls no upstream while either env value is unset', async () => {
  const offs = [{ ...ENV, WAITLIST_UPSTREAM_URL: undefined }, { ...ENV, WAITLIST_PROXY_SECRET: '' }, {}];
  const cases = [['signup', {}], ['confirm', { body: { token: 't' } }], ['unsubscribe', { body: { id: 'i', sig: 's' } }], ['unsubscribe', { method: 'GET', query: '?id=i&s=s' }]];
  for (const env of offs) {
    for (const [route, options] of cases) {
      const up = upstream();
      const res = await read(await call(route, options, { env, fetch: up.fetch }));
      const what = `${route} ${options.method ?? 'POST'} with ${JSON.stringify(env)}`;
      assert.equal(res.status, 404, what);
      assert.deepEqual(res.body, { error: 'not_found' }, what);
      assert.equal(res.type, 'application/json', what);
      assert.equal(res.cache, 'no-store', what);
      assert.equal(up.calls.length, 0, `${what}: no upstream call`);
    }
  }
  for (const [route, options] of cases.slice(0, 3)) {
    const up = upstream(200, '{"status":"invalid"}');
    await call(route, options, { fetch: up.fetch });
    assert.equal(up.calls.length, 1, `${route} with both set reaches the upstream`);
  }
});

test('a sign-up goes to <upstream>/signup with the secret, the hashed client, the origin and the region', async () => {
  const up = upstream();
  const res = await read(await call('signup', {}, { fetch: up.fetch }));
  assert.equal(res.status, 202);
  assert.deepEqual(up.calls, [
    {
      url: 'https://ref.supabase.co/functions/v1/waitlist/signup',
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-waitlist-proxy-secret': 'proxy-secret',
        'x-waitlist-client': clientKey(IP),
        'x-waitlist-origin': 'https://hummlist.com',
        'x-region': 'eu-central-1',
      },
      body: SIGNUP,
    },
  ]);
});

test('the client key falls back to the first x-forwarded-for entry, then the empty string, and never carries the raw IP', async () => {
  const cases = [
    [{ 'x-forwarded-for': ` ${IP} , 10.0.0.1` }, clientKey(IP)],
    [{ 'x-real-ip': IP, 'x-forwarded-for': '198.51.100.1' }, clientKey(IP)],
    [{}, clientKey('')],
  ];
  for (const [headers, key] of cases) {
    const up = upstream();
    await call('signup', { headers }, { fetch: up.fetch });
    const sent = up.calls[0].headers;
    assert.equal(sent['x-waitlist-client'], key, JSON.stringify(headers));
    assert.match(sent['x-waitlist-client'], /^[0-9a-f]{64}$/);
    for (const value of Object.values(sent)) assert.ok(!value.includes(IP) && !value.includes('198.51.100.1'), `raw IP in ${value}`);
  }
});

test('the origin is http for a local preview host and https for any other host', async () => {
  for (const [host, origin] of [
    ['127.0.0.1:55990', 'http://127.0.0.1:55990'],
    ['localhost:3000', 'http://localhost:3000'],
    ['hummlist-site-abc-peter-trost.vercel.app', 'https://hummlist-site-abc-peter-trost.vercel.app'],
    ['127.0.0.1.evil.example', 'https://127.0.0.1.evil.example'],
  ]) {
    const up = upstream();
    await call('signup', { host }, { fetch: up.fetch });
    assert.equal(up.calls[0].headers['x-waitlist-origin'], origin, host);
  }
});

test('upstream statuses and JSON bodies pass through unchanged', async () => {
  const cases = [
    ['signup', 202, '{"status":"ok"}'],
    ['signup', 400, '{"error":"invalid_email"}'],
    ['signup', 429, '{"error":"rate_limited"}'],
    ['confirm', 200, '{"status":"confirmed"}'],
    ['unsubscribe', 200, '{"status":"deleted"}'],
  ];
  for (const [route, status, text] of cases) {
    const up = upstream(status, text);
    const res = await call(route, { body: { token: 't', id: 'i', sig: 's' } }, { fetch: up.fetch });
    assert.equal(res.status, status, `${route} ${text}`);
    assert.equal(await res.text(), text, `${route} ${text}`);
    assert.equal(res.headers.get('content-type'), 'application/json');
    assert.equal(res.headers.get('cache-control'), 'no-store');
  }
  const up = upstream();
  await call('confirm', { body: { token: 'tok' } }, { fetch: up.fetch });
  assert.equal(up.calls[0].url, 'https://ref.supabase.co/functions/v1/waitlist/confirm');
  assert.deepEqual(up.calls[0].body, { token: 'tok' }, 'confirm forwards the token');
});

test('an unreachable, hanging or non-JSON upstream answers 503 unavailable', async () => {
  const fetches = {
    throws: async () => {
      throw new TypeError('fetch failed');
    },
    // AbortSignal.timeout's timer doesn't hold the event loop open (Node 22), a real socket would.
    hangs: (url, init) =>
      new Promise((resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => {
          clearTimeout(socket);
          reject(init.signal.reason);
        });
      }),
    html: async () => new Response('<html>Bad gateway</html>', { status: 502 }),
    empty: async () => new Response(null, { status: 204 }),
  };
  for (const [name, fetch] of Object.entries(fetches)) {
    const res = await read(await call('signup', {}, { fetch, timeoutMs: 20 }));
    assert.equal(res.status, 503, name);
    assert.deepEqual(res.body, { error: 'unavailable' }, name);
    assert.equal(res.cache, 'no-store', name);
  }
});

test('bodies above 2 KB, invalid JSON and non-object JSON answer 400 invalid_request without an upstream call', async () => {
  const sized = (bytes) => {
    const base = JSON.stringify({ ...SIGNUP, pad: '' });
    return JSON.stringify({ ...SIGNUP, pad: 'x'.repeat(bytes - base.length) });
  };
  assert.equal(sized(2048).length, 2048);
  const ok = upstream();
  assert.equal((await call('signup', { body: sized(2048) }, { fetch: ok.fetch })).status, 202, '2048 bytes pass');
  assert.equal(ok.calls.length, 1);
  const cases = {
    '2049 bytes': { body: sized(2049) },
    'a small content-length over a big body': { body: sized(4000), headers: { 'content-length': '10' } },
    'a big content-length': { body: '{}', headers: { 'content-length': '5000' } },
    'invalid JSON': { body: '{"email":' },
    'an array': { body: [SIGNUP] },
    'a string': { body: '"hello"' },
    'null': { body: 'null' },
    'no body': { body: '' },
  };
  for (const [name, options] of Object.entries(cases)) {
    for (const route of ['signup', 'confirm', 'unsubscribe']) {
      const up = upstream();
      const res = await read(await call(route, options, { fetch: up.fetch }));
      assert.equal(res.status, 400, `${route}: ${name}`);
      assert.deepEqual(res.body, { error: 'invalid_request' }, `${route}: ${name}`);
      assert.equal(res.cache, 'no-store', `${route}: ${name}`);
      assert.equal(up.calls.length, 0, `${route}: ${name} reaches no upstream`);
    }
  }
});

test('a body that streams past 2 KB without a content-length is cut off', async () => {
  const bytes = new TextEncoder().encode(JSON.stringify({ ...SIGNUP, pad: 'x'.repeat(4096) }));
  let pulled = 0;
  const body = new ReadableStream({
    pull(controller) {
      const chunk = bytes.subarray(pulled * 512, (pulled + 1) * 512);
      pulled += 1;
      if (chunk.length) controller.enqueue(chunk);
      else controller.close();
    },
  });
  const up = upstream();
  const req = new Request('https://hummlist.com/api/waitlist', { method: 'POST', body, duplex: 'half', headers: { host: 'hummlist.com' } });
  const res = await handle('signup', req, { env: ENV, fetch: up.fetch, now: NOW });
  assert.equal(res.status, 400);
  assert.equal(up.calls.length, 0);
  assert.ok(pulled <= 6, `stopped reading after ${pulled} of ${Math.ceil(bytes.length / 512)} chunks`);
});

test('a wrong method answers 405 with allow', async () => {
  for (const [route, method, allow] of [['signup', 'GET', 'POST'], ['confirm', 'PUT', 'POST'], ['unsubscribe', 'DELETE', 'POST, GET']]) {
    const up = upstream();
    const res = await read(await call(route, { method }, { fetch: up.fetch }));
    assert.equal(res.status, 405, `${method} ${route}`);
    assert.deepEqual(res.body, { error: 'method_not_allowed' });
    assert.equal(res.res.headers.get('allow'), allow);
    assert.equal(res.cache, 'no-store');
    assert.equal(up.calls.length, 0);
  }
});

test('unsubscribe forwards {id, sig} from a JSON body', async () => {
  const up = upstream(200, '{"status":"deleted"}');
  await call('unsubscribe', { body: { id: 'row-1', sig: 'abc', extra: 'dropped' } }, { fetch: up.fetch });
  assert.equal(up.calls[0].url, 'https://ref.supabase.co/functions/v1/waitlist/unsubscribe');
  assert.deepEqual(up.calls[0].body, { id: 'row-1', sig: 'abc' });
});

test('a one-click unsubscribe (RFC 8058) forwards id and s from the query', async () => {
  const form = { 'content-type': 'application/x-www-form-urlencoded' };
  const up = upstream(200, '{"status":"deleted"}');
  const res = await call('unsubscribe', { query: '?id=row-1&s=abc', body: 'List-Unsubscribe=One-Click', headers: form }, { fetch: up.fetch });
  assert.equal(res.status, 200);
  assert.deepEqual(up.calls[0].body, { id: 'row-1', sig: 'abc' }, 'form-encoded one-click');
  const plain = upstream(200, '{"status":"deleted"}');
  await call('unsubscribe', { query: '?id=row-2&s=def', body: 'List-Unsubscribe=One-Click', headers: { 'content-type': 'text/plain' } }, { fetch: plain.fetch });
  assert.deepEqual(plain.calls[0].body, { id: 'row-2', sig: 'def' }, 'any non-JSON content type');
  for (const [query, body] of [['?id=row-1', 'List-Unsubscribe=One-Click'], ['?s=abc', 'List-Unsubscribe=One-Click'], ['', 'List-Unsubscribe=One-Click'], ['?id=row-1&s=abc', 'List-Unsubscribe=Yes'], ['?id=row-1&s=abc', '']]) {
    const bad = upstream();
    const res = await read(await call('unsubscribe', { query, body, headers: form }, { fetch: bad.fetch }));
    assert.equal(res.status, 400, `${query} ${body}`);
    assert.deepEqual(res.body, { error: 'invalid_request' });
    assert.equal(bad.calls.length, 0);
  }
});

test('GET unsubscribe answers 303 to the locale page with the values in the fragment and calls no upstream', async () => {
  const cases = [
    ['?id=row-1&s=abc&l=de', '/de/warteliste/abmelden#id=row-1&s=abc'],
    ['?id=row-1&s=abc&l=en', '/en/waitlist/unsubscribe#id=row-1&s=abc'],
    ['?id=row-1&s=abc', '/de/warteliste/abmelden#id=row-1&s=abc'],
    ['?id=row-1&s=abc&l=fr', '/de/warteliste/abmelden#id=row-1&s=abc'],
    ['?id=a%26b%23c&s=x%20y%2Bz%3D&l=en', '/en/waitlist/unsubscribe#id=a%26b%23c&s=x%20y%2Bz%3D'],
  ];
  for (const [query, location] of cases) {
    const up = upstream();
    const res = await call('unsubscribe', { method: 'GET', query }, { fetch: up.fetch });
    assert.equal(res.status, 303, query);
    assert.equal(res.headers.get('location'), location, query);
    assert.equal(res.headers.get('content-type'), 'application/json');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(up.calls.length, 0, `${query} never deletes`);
  }
  for (const query of ['?id=row-1', '?s=abc&l=en', '', '?id=&s=abc']) {
    const res = await read(await call('unsubscribe', { method: 'GET', query }, { fetch: upstream().fetch }));
    assert.equal(res.status, 400, query);
    assert.deepEqual(res.body, { error: 'invalid_request' });
  }
});

test('each request logs one line with the route and status only', async () => {
  const runs = [
    () => call('signup', {}, { fetch: upstream().fetch }),
    () => call('signup', { body: '{' }, { fetch: upstream().fetch }),
    () => call('confirm', { body: { token: 'secret-token' } }, { fetch: upstream(200, '{"status":"confirmed"}').fetch }),
    () => call('unsubscribe', { method: 'GET', query: '?id=row-1&s=sig-1' }, { fetch: upstream().fetch }),
    () => call('signup', {}, {
      fetch: async () => {
        throw new Error(`connect failed for ${EMAIL} from ${IP}`);
      },
    }),
  ];
  for (const run of runs) await run();
  const lines = log.mock.calls.map((c) => c.arguments.join(' '));
  assert.deepEqual(lines, ['waitlist signup 202', 'waitlist signup 400', 'waitlist confirm 200', 'waitlist unsubscribe 303', 'waitlist signup 503']);
  for (const line of lines) {
    assert.match(line, /^waitlist (signup|confirm|unsubscribe) \d{3}$/);
    for (const secret of [EMAIL, IP, 'secret-token', 'sig-1', 'row-1', 'proxy-secret']) assert.ok(!line.includes(secret), `${secret} in ${line}`);
  }
});

test('the route files call the handler with process.env and the global fetch', async () => {
  const saved = { env: { ...process.env }, fetch: globalThis.fetch };
  const up = upstream(200, '{"status":"invalid"}');
  Object.assign(process.env, ENV);
  globalThis.fetch = up.fetch;
  try {
    await signupRoute.POST(request('signup'));
    await confirmRoute.POST(request('confirm', { body: { token: 't' } }));
    await unsubscribeRoute.POST(request('unsubscribe', { body: { id: 'i', sig: 's' } }));
    const page = await unsubscribeRoute.GET(request('unsubscribe', { method: 'GET', query: '?id=i&s=s&l=en' }));
    assert.equal(page.headers.get('location'), '/en/waitlist/unsubscribe#id=i&s=s');
    assert.deepEqual(up.calls.map((c) => c.url.split('/').pop()), ['signup', 'confirm', 'unsubscribe']);
    delete process.env.WAITLIST_PROXY_SECRET;
    assert.equal((await signupRoute.POST(request('signup'))).status, 404, 'env is read per request');
  } finally {
    process.env = saved.env;
    globalThis.fetch = saved.fetch;
  }
});

test('an IPv6 client counts as its /64, an IPv4 client as its address', () => {
  assert.equal(clientNetwork('203.0.113.7'), '203.0.113.7');
  assert.equal(clientNetwork('2001:db8:aa:bb:1:2:3:4'), '2001:db8:aa:bb::/64');
  assert.equal(clientNetwork('2001:db8:aa:bb::9'), '2001:db8:aa:bb::/64');
  assert.equal(clientNetwork('2001:0db8::1'), '2001:db8:0:0::/64');
  assert.equal(clientNetwork('2001:db8:aa:bb:ffff::1'), clientNetwork('2001:db8:aa:bb:1::2'));
});
