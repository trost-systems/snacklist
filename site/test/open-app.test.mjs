import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, htmlRoutes, SITE_DIR } from './helpers.mjs';

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const IPOD = 'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1';
const IPAD = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15';
const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const ANDROID_TABLET = 'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const DESKTOP = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const site = buildSite();
const isGuidePage = (route) => /^\/(de\/anleitungen|en\/guides)(\/|$)/.test(route);

test('guides and the guide indexes carry „In der App öffnen“, hidden until open-app.js shows it; no other page does', () => {
  const routes = htmlRoutes(site.outDir);
  const guides = routes.filter(isGuidePage);
  assert.ok(guides.includes('/de/anleitungen') && guides.includes('/en/guides'), 'both indexes');
  assert.ok(guides.length >= 4, `guides found: ${guides}`);
  for (const route of routes) {
    const doc = site.page(route);
    const box = doc.querySelector('.open-app');
    const script = doc.querySelector('script[src="/open-app.js"]');
    if (!isGuidePage(route)) {
      assert.equal(box, null, route);
      assert.equal(script, null, route);
      continue;
    }
    assert.ok(box?.hasAttribute('hidden'), `${route}: hidden without the script`);
    assert.equal(box.closest('main'), null, `${route}: outside <main>, so the Markdown twin has none`);
    assert.equal(box.querySelector('a').text, route.startsWith('/de') ? 'In der App öffnen' : 'Open in the app', route);
    assert.ok(script?.hasAttribute('defer'), route);
  }
});

test("the guides' Markdown twins, which the app shows, have no app button", () => {
  for (const route of htmlRoutes(site.outDir).filter(isGuidePage)) {
    const twin = readFileSync(join(site.outDir, `${route}.md`), 'utf8');
    assert.doesNotMatch(twin, /In der App öffnen|Open in the app|com\.snacklist\.app|intent:/, route);
  }
});

/** What open-app.js makes of the page's button on a browser with `userAgent` at `url`. */
function opening(userAgent, url) {
  const code = readFileSync(join(SITE_DIR, 'public/open-app.js'), 'utf8');
  const link = { href: '/x' };
  const box = { hidden: true, querySelector: () => link };
  const { pathname, href } = new URL(url);
  new Function('navigator', 'location', 'document', code)({ userAgent }, { pathname, href }, { querySelector: () => box });
  return box.hidden ? null : link.href;
}

test('open-app.js opens the app by its scheme on an iPhone, by an intent for the App Link on an Android phone, and stays hidden elsewhere', () => {
  const page = 'https://snacklist.app/de/anleitungen/widget';
  for (const ua of [IPHONE, IPOD]) assert.equal(opening(ua, page), 'com.snacklist.app://open/de/anleitungen/widget', ua);
  assert.equal(opening(IPHONE, 'https://snacklist.app/en/guides'), 'com.snacklist.app://open/en/guides');
  assert.equal(
    opening(ANDROID, page),
    'intent://snacklist.app/de/anleitungen/widget#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=https%3A%2F%2Fsnacklist.app%2Fde%2Fanleitungen%2Fwidget;end',
  );
  for (const ua of [IPAD, ANDROID_TABLET, DESKTOP]) assert.equal(opening(ua, page), null, ua);
});

test("open-app.js leaves a page's query out of the app's link", () => {
  assert.equal(opening(IPHONE, 'https://snacklist.app/en/guides/widget?code=x#top'), 'com.snacklist.app://open/en/guides/widget');
});
