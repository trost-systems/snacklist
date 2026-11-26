// Smoke test for a deployed web app (Vercel production or a local copy of its output):
// SPA routing and cache headers over HTTP, then the real sign-in page up to Google's consent
// screen in Chromium. Exits non-zero on the first failed check.
// Usage: node e2e/web-smoke.mjs <base-url> [screenshot-dir]
// SMOKE_BROWSER_ONLY=1 skips the HTTP checks (for e2e/serve.mjs, which has no Vercel rules).
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

async function head(path) {
  const res = await fetch(new URL(path, base), { redirect: 'manual', headers: cookie ? { cookie } : {} });
  return { status: res.status, type: res.headers.get('content-type') ?? '', cache: res.headers.get('cache-control') ?? '', body: await res.text() };
}

const httpChecks = !process.env.SMOKE_BROWSER_ONLY;
for (const path of httpChecks ? ['/', '/oauth/consent', '/join/ABC123', '/settings', '/join/AB.CD', '/lists/a.b',
  // Job 66: every app link (docs/DEEP_LINKS.md) opens the web app where the app is not installed.
  '/list', '/add', '/stores/4f9c2e1a-7b3d-4c8e-9a6f-2d1e0b5c8a7f', '/more', '/more/invites', '/more/settings',
  // Job 462: the screens the app host claims since (`/join` is the join page's folder, which hands
  // it to the web app).
  '/edit', '/edit/none', '/history', '/history/trip/4f9c2e1a', '/trip/4f9c2e1a', '/households/new'] : []) {
  const r = await head(path);
  check(r.status === 200 && r.type.startsWith('text/html') && r.body.includes('flutter_bootstrap.js'), `${path} serves index.html (${r.status}, ${r.type})`);
  check(/no-cache/.test(r.cache), `${path} Cache-Control: ${r.cache}`);
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
  const aasa = await head('/.well-known/apple-app-site-association');
  const details = aasa.status === 200 ? JSON.parse(aasa.body).applinks.details[0] : null;
  check(aasa.type.startsWith('application/json') && ['VCZSHMZY25.com.snacklist.app', 'VCZSHMZY25.com.hummlist.app'].every((id) => details?.appIDs.includes(id))
    && details.components.some((c) => c['/'] === '/more/*'),
    `/.well-known/apple-app-site-association ${aasa.status}, ${aasa.type}, claims /more/*`);
  // Job 462: older iOS versions ask at the root; the same file there, never index.html or a redirect.
  const rootAasa = await head('/apple-app-site-association');
  check(rootAasa.status === 200 && rootAasa.type.startsWith('application/json') && rootAasa.body === aasa.body,
    `/apple-app-site-association ${rootAasa.status}, ${rootAasa.type}, the same file`);
  const links = await head('/.well-known/assetlinks.json');
  check(links.status === 200 && links.type.startsWith('application/json') && JSON.parse(links.body).map((l) => l.target.package_name).join() === 'com.snacklist.app,com.hummlist.app',
    `/.well-known/assetlinks.json ${links.status}, ${links.type}`);
  for (const path of ['/does-not-exist.js', '/missing.js', '/assets/x.png', '/canvaskit/missing.wasm']) {
    const missing = await head(path);
    check(missing.status === 404, `${path} is a 404, not index.html (${missing.status})`);
  }
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
