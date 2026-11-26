import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { request } from 'node:http';
import { buildSite, htmlRoutes } from './helpers.mjs';
import { startPreview } from '../scripts/preview.mjs';

let server;
let site;
let base;

before(async () => {
  site = buildSite();
  server = await startPreview({ dir: site.outDir, port: 0 });
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

// node:http instead of fetch, which adds its own Accept-Language header.
const get = (path, headers = {}) =>
  new Promise((resolve, reject) => {
    request(base + path, { headers }, (res) => {
      let body = '';
      res.setEncoding('utf8').on('data', (c) => (body += c)).on('end', () =>
        resolve({ status: res.statusCode, headers: { get: (k) => res.headers[k] ?? null }, text: () => Promise.resolve(body) }),
      );
    }).on('error', reject).end();
  });

test('the root redirects by Accept-Language to the landing pages', async () => {
  const cases = [
    ['de-DE,de;q=0.9', '/de'],
    ['de', '/de'],
    ['  de-AT', '/de'],
    ['en-US,en;q=0.9,de;q=0.8', '/en'],
    ['fr', '/en'],
    [undefined, '/de'],
  ];
  for (const [language, location] of cases) {
    const res = await get('/', language === undefined ? {} : { 'Accept-Language': language });
    assert.equal(res.status, 307, `${language}`);
    assert.equal(res.headers.get('location'), location, `${language}`);
    assert.equal(res.headers.get('vary'), 'Accept-Language');
  }
});

test('hummlist.com and www.hummlist.com redirect to snacklist.app, keeping path and query, except /data/ and /api/', async () => {
  for (const host of ['hummlist.com', 'www.hummlist.com']) {
    for (const [path, location] of [['/', 'https://snacklist.app/'], ['/datenschutz', 'https://snacklist.app/datenschutz'], ['/de/anleitungen/alexa?x=1', 'https://snacklist.app/de/anleitungen/alexa?x=1']]) {
      const res = await get(path, { Host: host });
      assert.equal(res.status, 308, `${host}${path}`);
      assert.equal(res.headers.get('location'), location, `${host}${path}`);
    }
    const data = await get('/data/item-icons.v1.json', { Host: host });
    assert.notEqual(data.status, 308, `${host} /data/ stays`);
    const api = await get('/api/waitlist/unsubscribe', { Host: host });
    assert.notEqual(api.status, 308, `${host} /api/ stays`);
    const root = await get('/', { Host: host, 'Accept-Language': 'de-DE' });
    assert.equal(root.headers.get('location'), 'https://snacklist.app/', `${host} / goes to snacklist.app first`);
  }
  const own = await get('/datenschutz', { Host: 'snacklist.app' });
  assert.equal(own.status, 200, 'snacklist.app itself serves');
});

test('the privacy policy pages are served and /privacy goes to the English one', async () => {
  for (const [path, h1] of [['/datenschutz', 'Datenschutzerklärung'], ['/en/privacy', 'Privacy policy']]) {
    const res = await get(path);
    assert.equal(res.status, 200, path);
    assert.match(await res.text(), new RegExp(`<h1>${h1}</h1>`), path);
  }
  const old = await get('/privacy');
  assert.equal(old.status, 308);
  assert.equal(old.headers.get('location'), '/en/privacy');
});

test('clean URLs, trailing slashes and 404', async () => {
  const page = await get('/de/anleitungen/siri-kurzbefehl');
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /text\/html/);
  assert.match(await page.text(), /<h1>Snacklist per Siri: Kurzbefehl einrichten<\/h1>/);
  const html = await get('/de/anleitungen/siri-kurzbefehl.html');
  assert.equal(html.status, 308);
  assert.equal(html.headers.get('location'), '/de/anleitungen/siri-kurzbefehl');
  const slash = await get('/en/guides/');
  assert.equal(slash.status, 308);
  assert.equal(slash.headers.get('location'), '/en/guides');
  const missing = await get('/de/anleitungen/gibt-es-nicht');
  assert.equal(missing.status, 404);
  assert.match(await missing.text(), /Seite nicht gefunden/);
  assert.equal((await get('/styles.css')).status, 200);
});

test('every page and file carries the privacy headers, noindex included, and no cookie', async () => {
  const files = readdirSync(site.outDir, { recursive: true, withFileTypes: true })
    .filter((f) => f.isFile() && !f.name.endsWith('.html'))
    .map((f) => `/${join(f.parentPath, f.name).slice(site.outDir.length + 1)}`);
  for (const file of ['/landing.css', '/demo.js', '/tokens.css', '/favicon.svg', '/fonts/inter-latin-wght-normal.woff2', '/media/hero-de-wide.webp']) {
    assert.ok(files.includes(file), file);
  }
  const paths = [...htmlRoutes(site.outDir).filter((r) => r !== '/'), '/', '/de', '/en', ...files, '/nope'];
  for (const path of paths) {
    const res = await get(path);
    assert.equal(res.headers.get('set-cookie'), null, path);
    assert.equal(res.headers.get('x-robots-tag'), 'noindex', path);
    assert.match(res.headers.get('content-security-policy'), /^default-src 'self'/, path);
    assert.equal(res.headers.get('x-frame-options'), 'DENY', path);
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer', path);
  }
});

test('the landing pages load /demo.js, /stores.js and /waitlist.js, the mail-link pages /waitlist.js, the report pages /report.js, the guides /open-app.js; no file in the build has an inline script but JSON-LD, or an external resource', () => {
  const files = readdirSync(site.outDir, { recursive: true }).filter((f) => /\.(html|css)$/.test(f));
  assert.ok(files.length >= 9);
  for (const file of files) {
    const text = readFileSync(join(site.outDir, file), 'utf8').replace(/<script type="application\/ld\+json">[^<]*<\/script>/g, '');
    const scripts = [...text.matchAll(/<script[^>]*>/gi)].map((m) => m[0]);
    const waitlist = '<script src="/waitlist.js" defer>';
    const want = ['de.html', 'en.html'].includes(file)
      ? ['<script src="/demo.js" defer>', '<script type="module" src="/stores.js">', waitlist]
      : /^(de\/warteliste|en\/waitlist)\//.test(file)
        ? [waitlist]
        : ['inhalte-melden.html', 'en/report.html'].includes(file)
          ? ['<script type="module" src="/report.js">']
          : /^(de\/anleitungen|en\/guides)(\/|\.html$)/.test(file)
            ? ['<script src="/open-app.js" defer>']
            : [];
    assert.deepEqual(scripts, want, file);
    assert.doesNotMatch(text, /<script[^>]*>[^<]/i, file);
    assert.doesNotMatch(text, /<iframe/i, file);
    assert.doesNotMatch(text, /(src|srcset)="(https?:)?\/\//i, file);
    assert.doesNotMatch(text, /url\(\s*['"]?(https?:)?\/\//i, file);
    assert.doesNotMatch(text, /@import/i, file);
    for (const [, rel, href] of text.matchAll(/<link rel="([^"]+)" [^>]*href="([^"]+)"/g)) {
      if (!['canonical', 'alternate'].includes(rel)) assert.doesNotMatch(href, /^(https?:)?\/\//, `${file} ${href}`);
    }
  }
});
