import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHmac } from 'node:crypto';
import { buildSite } from './helpers.mjs';
import { startPreview } from '../scripts/preview.mjs';

const KEYS = ['WAITLIST_UPSTREAM_URL', 'WAITLIST_PROXY_SECRET'];
const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
const seen = [];
let upstream;
let preview;
let base;

before(async () => {
  upstream = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8').on('data', (c) => (body += c)).on('end', () => {
      seen.push({ path: req.url, headers: req.headers, body: JSON.parse(body) });
      res.writeHead(202, { 'content-type': 'application/json' }).end('{"status":"ok"}');
    });
  });
  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  preview = await startPreview({ dir: buildSite().outDir, port: 0 });
  base = `http://127.0.0.1:${preview.address().port}`;
});

after(() => {
  for (const key of KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
  upstream.close();
  preview.close();
});

const send = (path, { method = 'POST', body, headers = {} } = {}) =>
  new Promise((resolve, reject) => {
    const req = request(base + path, { method, headers }, (res) => {
      let text = '';
      res.setEncoding('utf8').on('data', (c) => (text += c)).on('end', () => resolve({ status: res.statusCode, headers: res.headers, text }));
    });
    req.on('error', reject).end(body);
  });

const signup = JSON.stringify({ email: 'hello+preview@hummlist.com', platform: 'android', locale: 'en', launch_news: true, consent_version: 'waitlist-en-v1', website: '', elapsed_ms: 4000 });

test('the preview serves /api/waitlist through the function to the upstream', async () => {
  process.env.WAITLIST_UPSTREAM_URL = `http://127.0.0.1:${upstream.address().port}/`;
  process.env.WAITLIST_PROXY_SECRET = 'preview-secret';
  seen.length = 0;
  const res = await send('/api/waitlist', { body: signup, headers: { 'content-type': 'application/json', 'x-real-ip': '198.51.100.9' } });
  assert.equal(res.status, 202);
  assert.equal(res.text, '{"status":"ok"}');
  assert.equal(res.headers['content-type'], 'application/json');
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.match(res.headers['content-security-policy'], /^default-src 'self'/, 'vercel.json headers apply to the function');
  assert.equal(seen.length, 1, 'the upstream got one request');
  const [hit] = seen;
  assert.equal(hit.path, '/signup');
  assert.equal(hit.headers['x-waitlist-proxy-secret'], 'preview-secret');
  const socketKey = createHmac('sha256', 'preview-secret').update(`${new Date().toISOString().slice(0, 10)}|127.0.0.1`).digest('hex');
  assert.equal(hit.headers['x-waitlist-client'], socketKey, 'the client key hashes the socket address, not the client-sent x-real-ip');
  assert.equal(hit.headers['x-waitlist-origin'], base, 'a local preview origin is http://127.0.0.1:<port>');
  assert.deepEqual(hit.body, JSON.parse(signup));
  assert.ok(!Object.values(hit.headers).some((v) => String(v).includes('198.51.100.9')), 'a client-sent x-real-ip is replaced and never forwarded');

  const page = await send('/api/waitlist/unsubscribe?id=row-1&s=abc&l=en', { method: 'GET' });
  assert.equal(page.status, 303);
  assert.equal(page.headers.location, '/en/waitlist/unsubscribe#id=row-1&s=abc');
  const wrong = await send('/api/waitlist/confirm', { method: 'GET' });
  assert.equal(wrong.status, 405, 'an unexported method gets the handler 405');
  assert.equal(wrong.headers.allow, 'POST');
  assert.equal((await send('/api/other', { method: 'GET' })).status, 404, 'other /api paths stay 404');
});

test('with the env unset the preview answers 404 on every waitlist path', async () => {
  for (const key of KEYS) delete process.env[key];
  seen.length = 0;
  for (const [path, method] of [['/api/waitlist', 'POST'], ['/api/waitlist/confirm', 'POST'], ['/api/waitlist/unsubscribe', 'POST'], ['/api/waitlist/unsubscribe?id=a&s=b', 'GET']]) {
    const res = await send(path, { method, body: method === 'POST' ? signup : undefined, headers: { 'content-type': 'application/json' } });
    assert.equal(res.status, 404, `${method} ${path}`);
    assert.deepEqual(JSON.parse(res.text), { error: 'not_found' });
    assert.equal(res.headers['cache-control'], 'no-store');
  }
  assert.equal(seen.length, 0);
});
