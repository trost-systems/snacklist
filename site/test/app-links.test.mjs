// The guides open in the installed app (job 462): snacklist.app serves the association files for
// the guide paths, and guide pages and indexes offer the hand-off on phones (public/open-in-app.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, htmlRoutes, serve, REPO_DIR, SITE_DIR } from './helpers.mjs';
import { LOCALES } from '../build.mjs';

const site = buildSite();
const readJson = (rel) => JSON.parse(readFileSync(join(site.outDir, rel), 'utf8'));

test('the AASA claims exactly the guide indexes and guides, for the Snacklist app only', () => {
  const aasa = readJson('.well-known/apple-app-site-association');
  assert.equal(aasa.applinks.details.length, 1);
  const [details] = aasa.applinks.details;
  assert.deepEqual(details.appIDs, ['VCZSHMZY25.com.snacklist.app']);
  const guidePaths = Object.values(LOCALES).flatMap(({ guidesBase }) => [guidesBase, `${guidesBase}/*`]);
  assert.deepEqual(details.components.map((c) => c['/']), guidePaths);
  for (const component of details.components) assert.ok(component.comment?.trim(), `${component['/']} has a comment`);
});

test('assetlinks.json is the app host\'s com.snacklist.app statement, nothing else', () => {
  const app = JSON.parse(readFileSync(join(REPO_DIR, 'app/web/.well-known/assetlinks.json'), 'utf8'));
  const snacklist = app.filter((s) => s.target.package_name === 'com.snacklist.app');
  assert.equal(snacklist.length, 1);
  assert.deepEqual(readJson('.well-known/assetlinks.json'), snacklist);
});

test('the association files are served as JSON, the AASA also at the root path, without a redirect', async () => {
  const res = await serve(site.outDir, ['/.well-known/apple-app-site-association', '/apple-app-site-association', '/.well-known/assetlinks.json']);
  for (const [path, { status, headers }] of Object.entries(res)) {
    assert.equal(status, 200, path);
    assert.match(headers['content-type'], /^application\/json/, path);
  }
  assert.equal(res['/apple-app-site-association'].body, res['/.well-known/apple-app-site-association'].body);
  assert.deepEqual(JSON.parse(res['/apple-app-site-association'].body), readJson('.well-known/apple-app-site-association'));
});

test('guide pages and guide indexes carry the hidden hand-off below the title; no other page does', () => {
  const routes = htmlRoutes(site.outDir);
  const guides = routes.filter((r) => Object.values(LOCALES).some(({ guidesBase }) => r === guidesBase || r.startsWith(`${guidesBase}/`)));
  assert.ok(guides.length >= 12, `${guides.length} guide pages and indexes`);
  for (const route of routes) {
    const doc = site.page(route);
    const script = doc.querySelector('script[src="/open-in-app.js"]');
    const link = doc.querySelector('[data-open-in-app]');
    if (!guides.includes(route)) {
      assert.equal(script, null, `${route} has no hand-off script`);
      assert.equal(link, null, `${route} has no hand-off link`);
      continue;
    }
    const lang = doc.querySelector('html').getAttribute('lang');
    assert.ok(script, `${route} loads open-in-app.js`);
    assert.equal(link.text, LOCALES[lang].ui.openInApp, route);
    assert.equal(link.getAttribute('href'), undefined, `${route}: no href until the script knows the platform`);
    let holder = doc.querySelector('h1').nextElementSibling;
    if (holder.classList.contains('since-note')) holder = holder.nextElementSibling;
    assert.ok(holder.hasAttribute('hidden') && holder.querySelector('[data-open-in-app]'), `${route}: hidden, right below the h1 and its version note`);
  }
});

test('the hand-off stays out of the Markdown twins', () => {
  for (const locale of Object.values(LOCALES)) {
    const twin = readFileSync(join(site.outDir, `${locale.guidesBase.slice(1)}.md`), 'utf8');
    assert.ok(!twin.includes(locale.ui.openInApp), locale.guidesBase);
  }
});

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36';
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15';

// Runs open-in-app.js on a page at `url` and returns the link's href and whether it shows.
function handoff(userAgent, url, maxTouchPoints = 0) {
  const code = readFileSync(join(SITE_DIR, 'public/open-in-app.js'), 'utf8');
  const holder = { hidden: true, removeAttribute: (name) => name === 'hidden' && (holder.hidden = false) };
  const link = { href: undefined, closest: (selector) => (selector === '[hidden]' && holder.hidden ? holder : null) };
  const document = { querySelectorAll: (selector) => (selector === 'a[data-open-in-app]' ? [link] : []) };
  new Function('navigator', 'location', 'document', 'addEventListener', code)({ userAgent, maxTouchPoints }, new URL(url), document, () => {});
  return { href: link.href, shown: !holder.hidden };
}

test('open-in-app.js opens the app scheme on iOS, an intent with this page as fallback on Android, nothing on desktop', () => {
  const url = 'https://snacklist.app/de/anleitungen/alexa?ref=mail';
  assert.deepEqual(handoff(IPHONE, url), { href: 'com.snacklist.app://open/de/anleitungen/alexa?ref=mail', shown: true });
  assert.deepEqual(handoff(MAC, url, 5), { href: 'com.snacklist.app://open/de/anleitungen/alexa?ref=mail', shown: true }, 'iPadOS in desktop mode');
  assert.deepEqual(handoff(ANDROID, url), {
    href: 'intent://snacklist.app/de/anleitungen/alexa?ref=mail#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=https%3A%2F%2Fsnacklist.app%2Fde%2Fanleitungen%2Falexa%3Fref%3Dmail;end',
    shown: true,
  });
  // A section rides along on iOS; an intent's `#` is its own, so Android opens the guide.
  assert.equal(handoff(IPHONE, `${url}#schritt-1`).href, 'com.snacklist.app://open/de/anleitungen/alexa?ref=mail#schritt-1');
  assert.match(handoff(ANDROID, `${url}#schritt-1`).href, /^intent:\/\/snacklist\.app\/de\/anleitungen\/alexa\?ref=mail#Intent;/);
  assert.deepEqual(handoff(MAC, url), { href: undefined, shown: false });
  assert.deepEqual(handoff('Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/133.0', url), { href: undefined, shown: false });
});
