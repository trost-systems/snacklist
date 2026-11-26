// Smoke test for a deployed web app (Vercel production or a local copy of its output):
// SPA routing and cache headers over HTTP, then the real sign-in page up to Google's consent
// screen in Chromium. Exits non-zero on the first failed check.
// Usage: node e2e/web-smoke.mjs <base-url> [screenshot-dir]
// SMOKE_BROWSER_ONLY=1 skips the HTTP checks (for e2e/serve.mjs, which has no Vercel rules).
// SMOKE_SITE=https://snacklist.app also checks the site's association files (job 462).
import { mkdirSync } from 'node:fs';
import process from 'node:process';
import { chromium } from '@playwright/test';

const [url, shots = '/tmp/fg-web-smoke'] = process.argv.slice(2);
if (!url) {
  console.error('usage: node e2e/web-smoke.mjs <base-url> [screenshot-dir]');
  process.exit(2);
}
mkdirSync(shots, { recursive: true });

// A protected Vercel preview opens with a share link (<url>/?_vercel_share=...); it sets a cookie.
const base = new URL(url).origin;
let cookie = '';
if (new URL(url).searchParams.has('_vercel_share')) {
  const res = await fetch(url, { redirect: 'manual' });
  cookie = res.headers.getSetCookie().map((c) => c.split(';')[0]).join('; ');
}

function check(ok, message) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${message}`);
  if (!ok) process.exit(1);
}

async function head(path, origin = base) {
  const res = await fetch(new URL(path, origin), { redirect: 'manual', headers: cookie && origin === base ? { cookie } : {} });
  return { status: res.status, type: res.headers.get('content-type') ?? '', cache: res.headers.get('cache-control') ?? '', body: await res.text() };
}

const httpChecks = !process.env.SMOKE_BROWSER_ONLY;
const id = '4f9c2e1a-7b3d-4c8e-9a6f-2d1e0b5c8a7f';
for (const path of httpChecks ? ['/', '/oauth/consent', '/settings', '/lists/a.b',
  // Job 66 and 462: every app link (docs/DEEP_LINKS.md) opens the web app where the app is not installed.
  '/list', '/add', `/stores/${id}`, '/more', '/more/invites', '/more/settings', '/history', `/history/trip/${id}`, '/edit', '/edit/none', `/trip/${id}`] : []) {
  const r = await head(path);
  check(r.status === 200 && r.type.startsWith('text/html') && r.body.includes('flutter_bootstrap.js'), `${path} serves index.html (${r.status}, ${r.type})`);
  check(/no-cache/.test(r.cache), `${path} Cache-Control: ${r.cache}`);
}
// Job 169b: an invite link opens the static join page, not the web app.
for (const path of httpChecks ? ['/join/ABC123', '/join/AB.CD'] : []) {
  const r = await head(path);
  check(r.status === 200 && r.type.startsWith('text/html') && r.body.includes('/join/join.js') && !r.body.includes('flutter_bootstrap.js'), `${path} serves the join page (${r.status}, ${r.type})`);
}
for (const path of httpChecks ? ['/flutter_bootstrap.js', '/flutter_service_worker.js', '/version.json'] : []) {
  const r = await head(path);
  check(r.status === 200 && /no-cache/.test(r.cache), `${path} ${r.status}, Cache-Control: ${r.cache}`);
}
if (httpChecks) {
  const js = await head('/main.dart.js');
  check(js.status === 200 && js.type.includes('javascript') && /max-age=0/.test(js.cache), `/main.dart.js ${js.status}, ${js.type}, Cache-Control: ${js.cache}`);
  // Job 28: the wasm build and its JS support module. Streaming compilation needs application/wasm.
  const wasm = await head('/main.dart.wasm');
  check(wasm.status === 200 && wasm.type.startsWith('application/wasm') && /max-age=0/.test(wasm.cache), `/main.dart.wasm ${wasm.status}, ${wasm.type}, Cache-Control: ${wasm.cache}`);
  const mjs = await head('/main.dart.mjs');
  check(mjs.status === 200 && mjs.type.includes('javascript') && /max-age=0/.test(mjs.cache), `/main.dart.mjs ${mjs.status}, ${mjs.type}, Cache-Control: ${mjs.cache}`);
  // Job 22 and 66: universal links (iOS) and App Links (Android) for the paths of
  // docs/DEEP_LINKS.md. Apple fetches the association without following redirects and wants JSON.
  // Job 462: also at the root, where Apple looked before .well-known.
  for (const path of ['/.well-known/apple-app-site-association', '/apple-app-site-association']) {
    const aasa = await head(path);
    const details = aasa.status === 200 ? JSON.parse(aasa.body).applinks.details[0] : null;
    check(aasa.type.startsWith('application/json') && ['VCZSHMZY25.com.snacklist.app', 'VCZSHMZY25.com.hummlist.app'].every((id) => details?.appIDs.includes(id))
      && details.components.some((c) => c['/'] === '/more/*'),
      `${path} ${aasa.status}, ${aasa.type}, claims /more/*`);
  }
  const links = await head('/.well-known/assetlinks.json');
  check(links.status === 200 && links.type.startsWith('application/json') && JSON.parse(links.body).map((l) => l.target.package_name).join() === 'com.snacklist.app,com.hummlist.app',
    `/.well-known/assetlinks.json ${links.status}, ${links.type}`);
  for (const path of ['/does-not-exist.js', '/missing.js', '/assets/x.png', '/canvaskit/missing.wasm']) {
    const missing = await head(path);
    check(missing.status === 404, `${path} is a 404, not index.html (${missing.status})`);
  }
}

// Job 462: snacklist.app's guides open the Snacklist app (not Hummlist), so the site serves its own files.
if (process.env.SMOKE_SITE) {
  const site = new URL(process.env.SMOKE_SITE).origin;
  for (const path of ['/.well-known/apple-app-site-association', '/apple-app-site-association']) {
    const aasa = await head(path, site);
    const details = aasa.status === 200 ? JSON.parse(aasa.body).applinks.details[0] : null;
    check(aasa.type.startsWith('application/json') && details?.appIDs.join() === 'VCZSHMZY25.com.snacklist.app'
      && details.components.some((c) => c['/'] === '/en/guides/*'),
      `${site}${path} ${aasa.status}, ${aasa.type}, claims /en/guides/*`);
  }
  const links = await head('/.well-known/assetlinks.json', site);
  check(links.status === 200 && links.type.startsWith('application/json') && JSON.parse(links.body).map((l) => l.target.package_name).join() === 'com.snacklist.app',
    `${site}/.well-known/assetlinks.json ${links.status}, ${links.type}`);
}

const browser = await chromium.launch();
try {
  const context = await browser.newContext({ viewport: { width: 420, height: 860 }, locale: 'de-DE' });
  if (cookie) {
    await context.addCookies(cookie.split('; ').map((c) => {
      const [name, ...value] = c.split('=');
      return { name, value: value.join('='), url: base };
    }));
  }
  const page = await context.newPage();
  const entrypoints = [];
  page.on('request', (r) => { if (/\/main\.dart\.(wasm|js)$/.test(r.url())) entrypoints.push(new URL(r.url()).pathname); });
  await page.goto(new URL('/oauth/consent?authorization_id=smoke', base).href);
  const google = page.getByRole('button', { name: 'Mit Google anmelden' });
  await google.waitFor({ timeout: 60_000 });
  check(true, 'deep link /oauth/consent boots the app and shows the sign-in page');
  check(entrypoints.join() === '/main.dart.wasm', `Chromium runs the wasm build (loaded ${entrypoints.join(', ') || 'no entry point'})`);
  check(await page.getByRole('button', { name: 'Mit Apple anmelden' }).isVisible(), 'Apple button is visible');
  await page.screenshot({ path: `${shots}/1-sign-in.png` });

  await google.click();
  await page.waitForURL(/accounts\.google\.com/, { timeout: 30_000 });
  const url = new URL(page.url());
  check(url.hostname === 'accounts.google.com', `Google sign-in reached ${url.hostname}${url.pathname}`);
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.screenshot({ path: `${shots}/2-google-consent.png` });
  const clientId = url.searchParams.get('client_id') ?? new URLSearchParams(url.searchParams.get('continue') ?? '').get('client_id');
  console.log(`     client_id=${clientId ?? '(inside continue param)'}`);

  const applePage = await context.newPage();
  await applePage.goto(base);
  await applePage.getByRole('button', { name: 'Mit Apple anmelden' }).click({ timeout: 60_000 });
  await applePage.waitForURL(/appleid\.apple\.com/, { timeout: 30_000 });
  check(new URL(applePage.url()).searchParams.get('client_id') === 'com.petertrost.familygroceries.web', `Apple sign-in reached ${new URL(applePage.url()).hostname} for the Services ID`);
  await applePage.waitForLoadState('networkidle').catch(() => {});
  await applePage.screenshot({ path: `${shots}/3-apple-sign-in.png` });
  console.log(`screenshots in ${shots}`);
} finally {
  await browser.close();
}
