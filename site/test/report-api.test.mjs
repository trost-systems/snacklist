// /api/report (job 275): the Vercel function between the report form and the edge function.
import process from 'node:process';
import { test, mock, beforeEach, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request as httpRequest } from 'node:http';
import { createLimiter, handle, reportUrl } from '../api/_report.mjs';
import * as reportRoute from '../api/report.mjs';
import { startPreview } from '../scripts/preview.mjs';
import { buildSite } from './helpers.mjs';

const ENV = { WAITLIST_UPSTREAM_URL: 'https://ref.supabase.co/functions/v1/waitlist/', WAITLIST_PROXY_SECRET: 'proxy-secret' };
const NOW = new Date('2026-11-16T12:00:00Z');
const HOUR = 60 * 60 * 1000;
const IP = '203.0.113.7';
const REPORT = {
  locale: 'de',
  category: 'hate',
  location: 'Haushalt Brandt, Liste Wocheneinkauf',
  reason: 'Der Eintrag beleidigt eine Person mit Namen.',
  name: '',
  email: 'test+report@snacklist.app',
  'good_faith': true,
  website: '',
};

const log = mock.method(console, 'log', () => {});
beforeEach(() => log.mock.resetCalls());

function upstream(status = 201, text = '{"ref":"M-7K3Q-9XWD"}') {
  const calls = [];
  const fetch = (url, init) => {
    calls.push({ url, method: init.method, headers: Object.fromEntries(new Headers(init.headers)), body: JSON.parse(init.body) });
    return Promise.resolve(new Response(text, { status, headers: { 'content-type': 'application/json' } }));
  };
  return { calls, fetch };
}

function request({ method = 'POST', body = REPORT, headers = { 'x-real-ip': IP } } = {}) {
  const text = body === undefined || typeof body === 'string' ? body : JSON.stringify(body);
  return new Request('https://snacklist.app/api/report', {
    method,
    headers: { ...(method === 'POST' ? { 'content-type': 'application/json' } : {}), ...headers },
    body: method === 'POST' ? text : undefined,
  });
}

const call = (options, { env = ENV, fetch = upstream().fetch, now = NOW, limiter = createLimiter(), timeoutMs } = {}) =>
  handle(request(options), { env, fetch, now, limiter, timeoutMs });

async function read(res) {
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null, type: res.headers.get('content-type'), cache: res.headers.get('cache-control'), allow: res.headers.get('allow') };
}

test('the report URL is the waitlist URL with its last segment waitlist replaced by report', () => {
  assert.equal(reportUrl('https://ref.supabase.co/functions/v1/waitlist'), 'https://ref.supabase.co/functions/v1/report');
  assert.equal(reportUrl('https://ref.supabase.co/functions/v1/waitlist//'), 'https://ref.supabase.co/functions/v1/report');
  assert.equal(reportUrl('http://127.0.0.1:54321/functions/v1/waitlist'), 'http://127.0.0.1:54321/functions/v1/report');
  for (const other of ['https://ref.supabase.co/functions/v1/', 'https://ref.supabase.co/functions/v1/waitlists', 'https://ref.supabase.co/waitlist/signup']) {
    assert.equal(reportUrl(other), null, other);
  }
});

test('a report goes to <project>/functions/v1/report with the secret and the region, the body unchanged, no client address', async () => {
  const up = upstream();
  const headers = { 'x-real-ip': IP, 'x-forwarded-for': `${IP}, 10.0.0.1`, cookie: 'a=b', 'user-agent': 'test' };
  const res = await read(await call({ headers, body: { ...REPORT, extra: 'kept' } }, { fetch: up.fetch }));
  assert.equal(res.status, 201);
  assert.deepEqual(res.body, { ref: 'M-7K3Q-9XWD' });
  assert.deepEqual(up.calls, [
    {
      url: 'https://ref.supabase.co/functions/v1/report',
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-waitlist-proxy-secret': 'proxy-secret', 'x-region': 'eu-central-1' },
      body: { ...REPORT, extra: 'kept' },
    },
  ]);
});

test('upstream statuses and JSON bodies pass through unchanged, with no-store', async () => {
  for (const [status, text] of [[201, '{"ref":"M-0000-0000"}'], [400, '{"error":"invalid_request"}'], [429, '{"error":"rate_limited"}'], [503, '{"error":"unavailable"}'], [404, '{"error":"not_found"}']]) {
    const res = await call({}, { fetch: upstream(status, text).fetch });
    assert.equal(res.status, status, text);
    assert.equal(await res.text(), text);
    assert.equal(res.headers.get('content-type'), 'application/json');
    assert.equal(res.headers.get('cache-control'), 'no-store');
  }
});

test('an unreachable, hanging or non-JSON upstream answers 503 unavailable', async () => {
  const fetches = {
    throws: () => Promise.reject(new TypeError('fetch failed')),
    hangs: (_url, init) =>
      new Promise((_resolve, reject) => {
        const socket = setTimeout(() => {}, 60_000);
        init.signal.addEventListener('abort', () => {
          clearTimeout(socket);
          reject(init.signal.reason);
        });
      }),
    html: () => Promise.resolve(new Response('<html>Bad gateway</html>', { status: 502 })),
    empty: () => Promise.resolve(new Response(null, { status: 204 })),
  };
  for (const [name, fetch] of Object.entries(fetches)) {
    const res = await read(await call({}, { fetch, timeoutMs: 20 }));
    assert.equal(res.status, 503, name);
    assert.deepEqual(res.body, { error: 'unavailable' }, name);
    assert.equal(res.cache, 'no-store', name);
  }
});

test('unset env or an upstream URL not ending in /waitlist answers 404 and calls nothing', async () => {
  for (const env of [{}, { ...ENV, WAITLIST_UPSTREAM_URL: '' }, { ...ENV, WAITLIST_PROXY_SECRET: undefined }, { ...ENV, WAITLIST_UPSTREAM_URL: 'https://ref.supabase.co/functions/v1/' }]) {
    for (const method of ['POST', 'GET']) {
      const up = upstream();
      const res = await read(await call({ method }, { env, fetch: up.fetch }));
      assert.equal(res.status, 404, JSON.stringify(env));
      assert.deepEqual(res.body, { error: 'not_found' });
      assert.equal(res.cache, 'no-store');
      assert.equal(up.calls.length, 0);
    }
  }
});

test('any method but POST answers 405 with allow: POST', async () => {
  for (const method of ['GET', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']) {
    const up = upstream();
    const res = await read(await call({ method }, { fetch: up.fetch }));
    assert.equal(res.status, 405, method);
    assert.deepEqual(res.body, { error: 'method_not_allowed' });
    assert.equal(res.allow, 'POST');
    assert.equal(up.calls.length, 0);
  }
});

test('bodies above 64 KiB, invalid JSON and non-object JSON answer 400 invalid_request without an upstream call', async () => {
  const sized = (bytes) => {
    const base = JSON.stringify({ ...REPORT, pad: '' });
    return JSON.stringify({ ...REPORT, pad: 'x'.repeat(bytes - base.length) });
  };
  const ok = upstream();
  assert.equal((await call({ body: sized(65536) }, { fetch: ok.fetch })).status, 201, '64 KiB pass');
  for (const [name, options] of Object.entries({
    '64 KiB + 1': { body: sized(65537) },
    'a big content-length': { body: '{}', headers: { 'content-length': '70000' } },
    'invalid JSON': { body: '{"category":' },
    'an array': { body: [REPORT] },
    'a string': { body: '"hello"' },
    'null': { body: 'null' },
    'no body': { body: '' },
  })) {
    const up = upstream();
    const res = await read(await call(options, { fetch: up.fetch }));
    assert.equal(res.status, 400, name);
    assert.deepEqual(res.body, { error: 'invalid_request' }, name);
    assert.equal(up.calls.length, 0, name);
  }
});

test("only the site's own page may send: cross-site, a foreign origin or a non-JSON body answer 403 without an upstream call or a limiter hit", async () => {
  const limiter = createLimiter();
  for (const [name, headers] of Object.entries({
    'cross-site fetch': { 'x-real-ip': IP, 'sec-fetch-site': 'cross-site', origin: 'https://evil.example' },
    'same-site but another subdomain': { 'x-real-ip': IP, 'sec-fetch-site': 'same-site' },
    'a foreign origin without fetch metadata': { 'x-real-ip': IP, origin: 'https://evil.example' },
    'an opaque origin': { 'x-real-ip': IP, origin: 'null' },
    'a text/plain form post': { 'x-real-ip': IP, 'content-type': 'text/plain', 'sec-fetch-site': 'same-origin' },
  })) {
    const up = upstream();
    const res = await read(await call({ headers }, { fetch: up.fetch, limiter }));
    assert.equal(res.status, 403, name);
    assert.deepEqual(res.body, { error: 'forbidden' }, name);
    assert.equal(up.calls.length, 0, name);
  }
  assert.equal(limiter.size, 0, "refused requests use no one's budget");
  for (const headers of [{ 'sec-fetch-site': 'same-origin', origin: 'https://snacklist.app' }, { origin: 'https://snacklist.app' }, {}]) {
    assert.equal((await call({ headers: { 'x-real-ip': IP, ...headers } })).status, 201, JSON.stringify(headers));
  }
});

test('five requests per client network in a rolling hour, the sixth is 429 without an upstream call', async () => {
  const limiter = createLimiter();
  const up = upstream();
  const at = (ms) => new Date(NOW.getTime() + ms);
  const send = (headers, ms) => call({ headers }, { fetch: up.fetch, limiter, now: at(ms) });
  for (let i = 0; i < 5; i++) assert.equal((await send({ 'x-real-ip': IP }, i * 60_000)).status, 201, `request ${i + 1}`);
  const sixth = await read(await send({ 'x-real-ip': IP }, 10 * 60_000));
  assert.equal(sixth.status, 429);
  assert.deepEqual(sixth.body, { error: 'rate_limited' });
  assert.equal(sixth.cache, 'no-store');
  assert.equal(up.calls.length, 5);
  assert.equal((await send({ 'x-real-ip': '203.0.113.8' }, 10 * 60_000)).status, 201, 'another network is not limited');
  assert.equal((await send({ 'x-forwarded-for': `${IP}, 10.0.0.1` }, 10 * 60_000)).status, 429, 'without x-real-ip the first x-forwarded-for entry counts');
  assert.equal((await send({ 'x-real-ip': IP }, HOUR - 1)).status, 429, 'the first request is still inside the hour');
  assert.equal((await send({ 'x-real-ip': IP }, HOUR)).status, 201, 'an hour after the first, one more fits');
  assert.equal((await send({ 'x-real-ip': IP }, HOUR + 1)).status, 429, 'the second is still inside its hour');
  assert.equal((await send({ 'x-real-ip': IP }, HOUR + 4 * 60_000)).status, 201, 'the requests of the first hour have all expired');
});

test('an IPv6 client counts as its /64', async () => {
  const limiter = createLimiter();
  const send = (ip) => call({ headers: { 'x-real-ip': ip } }, { limiter });
  for (let i = 1; i <= 5; i++) assert.equal((await send(`2001:db8:aa:bb::${i}`)).status, 201);
  assert.equal((await send('2001:db8:aa:bb:ffff:1:2:3')).status, 429, 'same /64');
  assert.equal((await send('2001:db8:aa:bc::1')).status, 201, 'the next /64');
});

test('the limiter forgets networks after an hour and never holds more than its cap', () => {
  const limiter = createLimiter({ limit: 5, windowMs: HOUR, maxKeys: 100 });
  for (let i = 0; i < 250; i++) assert.ok(limiter.take(`net-${i}`, i));
  assert.equal(limiter.size, 100, 'capped');
  assert.ok(limiter.take('net-249', 300), 'a recent network keeps its count');
  limiter.take('late', HOUR + 400);
  assert.equal(limiter.size, 1, 'a sweep drops networks quiet for an hour');
  for (let i = 0; i < 5; i++) limiter.take('busy', HOUR + 500);
  assert.equal(limiter.take('busy', HOUR + 501), false);
  for (let i = 0; i < 200; i++) limiter.take(`flood-${i}`, HOUR + 600);
  assert.equal(limiter.size, 100);
  assert.equal(limiter.take('busy', HOUR + 700), true, 'a flood of new networks evicts the least recently seen first');
});

test('each request logs one line with the status only', async () => {
  const limiter = createLimiter({ limit: 1 });
  await call({}, { limiter });
  await call({}, { limiter });
  await call({ method: 'GET' });
  await call({ body: '{' });
  await call({}, { fetch: () => Promise.reject(new Error(`connect failed for ${REPORT.email} from ${IP}`)) });
  const lines = log.mock.calls.map((c) => c.arguments.join(' '));
  assert.deepEqual(lines, ['report 201', 'report 429', 'report 405', 'report 400', 'report 503']);
});

test('the route file calls the handler with process.env and the global fetch', async () => {
  const saved = { env: { ...process.env }, fetch: globalThis.fetch };
  const up = upstream();
  Object.assign(process.env, ENV);
  globalThis.fetch = up.fetch;
  try {
    assert.equal((await reportRoute.POST(request({ headers: { 'x-real-ip': '198.51.100.77' } }))).status, 201);
    assert.equal(up.calls[0].url, 'https://ref.supabase.co/functions/v1/report');
    delete process.env.WAITLIST_PROXY_SECRET;
    assert.equal((await reportRoute.POST(request())).status, 404, 'env is read per request');
  } finally {
    process.env = saved.env;
    globalThis.fetch = saved.fetch;
  }
});

// The preview serves /api/report the way Vercel does, with x-real-ip from the socket.
const KEYS = ['WAITLIST_UPSTREAM_URL', 'WAITLIST_PROXY_SECRET'];
const savedEnv = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
const seen = [];
let fake;
let preview;

before(async () => {
  fake = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8').on('data', (c) => (body += c)).on('end', () => {
      seen.push({ path: req.url, headers: req.headers, body: JSON.parse(body) });
      res.writeHead(201, { 'content-type': 'application/json' }).end('{"ref":"M-7K3Q-9XWD"}');
    });
  });
  await new Promise((resolve) => fake.listen(0, '127.0.0.1', resolve));
  preview = await startPreview({ dir: buildSite().outDir, port: 0 });
});

after(() => {
  for (const key of KEYS) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
  fake.close();
  preview.close();
});

const send = (path, { method = 'POST', body, headers = {} } = {}) =>
  new Promise((resolve, reject) => {
    const req = httpRequest(`http://127.0.0.1:${preview.address().port}${path}`, { method, headers }, (res) => {
      let text = '';
      res.setEncoding('utf8').on('data', (c) => (text += c)).on('end', () => resolve({ status: res.statusCode, headers: res.headers, text }));
    });
    req.on('error', reject).end(body);
  });

test('the preview serves /api/report through the function to <upstream>/report', async () => {
  process.env.WAITLIST_UPSTREAM_URL = `http://127.0.0.1:${fake.address().port}/functions/v1/waitlist`;
  process.env.WAITLIST_PROXY_SECRET = 'preview-secret';
  const res = await send('/api/report', { body: JSON.stringify(REPORT), headers: { 'content-type': 'application/json', 'x-real-ip': '198.51.100.9' } });
  assert.equal(res.status, 201);
  assert.equal(res.text, '{"ref":"M-7K3Q-9XWD"}');
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.match(res.headers['content-security-policy'], /^default-src 'self'/);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].path, '/functions/v1/report');
  assert.equal(seen[0].headers['x-waitlist-proxy-secret'], 'preview-secret');
  assert.deepEqual(seen[0].body, REPORT);
  assert.ok(!Object.values(seen[0].headers).some((v) => /198\.51\.100\.9|127\.0\.0\.1(?!:)/.test(String(v))), 'no client address upstream');
  const wrong = await send('/api/report', { method: 'GET' });
  assert.equal(wrong.status, 405);
  assert.equal(wrong.headers.allow, 'POST');
});
