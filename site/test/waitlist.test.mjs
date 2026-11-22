import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'node-html-parser';
import jsQR from 'jsqr';
import { buildSite, htmlRoutes, legal, meta, serve, stageBuild, CONTENT_DIR, REPO_DIR, SITE_DIR } from './helpers.mjs';
import { STORE_URLS, WEB_APP_URL } from '../config/stores.mjs';

const PROD = { VERCEL_ENV: 'production' };
const ACTION_ROUTES = ['/de/warteliste/bestaetigen', '/de/warteliste/abmelden', '/en/waitlist/confirm', '/en/waitlist/unsubscribe'];
const CONSENT_TS = readFileSync(join(REPO_DIR, 'supabase/functions/waitlist/consent.ts'), 'utf8');
const versionsOf = (name) => {
  const found = new RegExp(`${name} = \\{ de: '([^']+)', en: '([^']+)' \\}`).exec(CONSENT_TS);
  assert.ok(found, `supabase/functions/waitlist/consent.ts names ${name}`);
  return { de: found[1], en: found[2] };
};
const legalText = (version) => readFileSync(join(CONTENT_DIR, `legal/consent/${version}.md`), 'utf8').trim().replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');
const waitlist = buildSite();
const beta = stageBuild('beta');
const launch = stageBuild('launch');
const STAGES = { waitlist, beta, launch };

test('the stage comes from site/config/stage.ts, which says waitlist; an unknown stage fails', () => {
  assert.match(readFileSync(join(SITE_DIR, 'config/stage.ts'), 'utf8'), /^export const stage: Stage = 'waitlist';$/m);
  assert.equal(waitlist.page('/de').querySelector('header a.header-cta').text, 'Auf die Warteliste');
  assert.throws(() => buildSite({ stage: 'open' }), /unknown stage "open"; site\/config\/stage\.ts allows waitlist, beta, launch/);
});

test('every call to action follows the stage: waitlist and beta lead to the form, launch to the store badges', () => {
  const want = {
    waitlist: { de: ['Auf die Warteliste', 'warteliste'], en: ['Join the waitlist', 'waitlist'] },
    beta: { de: ['Zur Beta anmelden', 'warteliste'], en: ['Join the beta', 'waitlist'] },
    launch: { de: ['App laden', 'app'], en: ['Get the app', 'app'] },
  };
  for (const [stage, site] of Object.entries(STAGES)) {
    for (const locale of ['de', 'en']) {
      const [label, anchor] = want[stage][locale];
      const doc = site.page(`/${locale}`);
      const header = doc.querySelector('header a.header-cta');
      assert.deepEqual([header.text, header.getAttribute('href')], [label, `#${anchor}`], `${stage} ${locale} header`);
      const other = site.page(locale === 'de' ? '/datenschutz' : '/en/guides').querySelector('header a.header-cta');
      assert.deepEqual([other.text, other.getAttribute('href')], [label, `/${locale}#${anchor}`], `${stage} ${locale} header elsewhere`);
      const target = doc.getElementById(anchor);
      assert.ok(target && target.closest('#test'), `${stage} ${locale}: the anchor is in the closing block`);
      if (stage === 'launch') {
        assert.equal(doc.querySelectorAll('form').length, 0, 'no form at launch');
        for (const block of [doc.querySelector('.hero-actions'), target]) {
          assert.deepEqual(block.querySelectorAll('.store-badge img').map((img) => img.getAttribute('src')), [`/media/badges/app-store-${locale}.svg`, `/media/badges/google-play-${locale}.png`]);
          assert.deepEqual(block.querySelectorAll('.store-badge').map((a) => a.getAttribute('href')), [STORE_URLS.appStore, STORE_URLS.googlePlay], 'the badges go straight to the listings');
        }
        for (const block of [doc.querySelector('.hero-actions'), target]) {
          const web = block.querySelector('.web-app a');
          assert.deepEqual([web.text, web.getAttribute('href')], [locale === 'de' ? 'Snacklist im Browser öffnen' : 'Open Snacklist in your browser', WEB_APP_URL], 'the web app under the badges');
        }
        assert.equal(target.querySelectorAll('.store-qr svg').length, 2, 'both QR codes sit in the closing block');
        assert.equal(doc.querySelector('.hero-actions .store-qr'), null, 'not in the hero');
        assert.match(doc.querySelector('.hero .chip').text, locale === 'de' ? /Jetzt verfügbar/ : /Available now/);
        assert.ok(doc.querySelector('script[src="/get-app.js"]'));
      } else {
        const hero = doc.querySelector('.hero-actions a.hex');
        assert.deepEqual([hero.text, hero.getAttribute('href')], [label, `#${anchor}`], `${stage} ${locale} hero`);
        assert.equal(target.querySelector('button[type="submit"] [data-when="idle"]').text, label, `${stage} ${locale} button`);
        assert.equal(doc.querySelectorAll('.store-badge').length, 0);
      }
      const webApp = doc.querySelectorAll('header a').filter((a) => (a.getAttribute('href') ?? '').startsWith('https://app.snacklist.app'));
      if (stage === 'launch') {
        assert.deepEqual(webApp.map((a) => [a.text, a.getAttribute('href')]), [[locale === 'de' ? 'Web-App' : 'Web app', 'https://app.snacklist.app']], `${stage} ${locale} nav`);
        assert.ok(doc.querySelector('header .nav').querySelectorAll('a').some((a) => a === webApp[0]), 'in the top nav');
      } else {
        for (const a of doc.querySelectorAll('a')) assert.doesNotMatch(a.getAttribute('href') ?? '', /app\.(?:snacklist\.app|hummlist\.com)/, `${stage} ${locale}`);
        assert.match(doc.querySelector('.hero .chip').text, locale === 'de' ? /Beta im November/ : /Beta in November/, `${stage} ${locale} keeps the beta chip`);
        assert.equal(doc.querySelector('script[src="/get-app.js"]'), null);
      }
    }
  }
});

test('the landing page is the one from before the waitlist: same sections plus the founder note, only the calls to action changed', () => {
  for (const locale of ['de', 'en']) {
    const doc = waitlist.page(`/${locale}`);
    assert.deepEqual(doc.querySelectorAll('main > section').map((s) => s.getAttribute('class')), ['hero', 'section features', 'section voice', 'section privacy-section', 'section founder-section', 'section test-section']);
    assert.equal(doc.querySelector('.hero form'), null, 'the hero keeps its button, the form is in the closing block');
    assert.ok(doc.querySelector('[data-copy-id="feature.stores.more"]'), 'the own-stores claim stays');
    assert.match(doc.querySelector('[data-copy-id="privacy.website"]').text, /Supabase in Frankfurt/);
    assert.doesNotMatch(doc.querySelector('body').text, /browser/i, locale);
  }
});

test('the sign-up form: one email field with its hint, iPhone or Android, no launch-news box, Legal\'s form text v2 under the button', () => {
  const versions = versionsOf('CONSENT_VERSIONS');
  for (const site of [waitlist, beta]) {
    for (const [locale, privacy] of [['de', '/datenschutz'], ['en', '/en/privacy']]) {
      const doc = site.page(`/${locale}`);
      assert.equal(doc.querySelector('html').getAttribute('lang'), locale);
      const form = doc.querySelector('#test form');
      assert.deepEqual([form.getAttribute('method'), form.getAttribute('action')], ['post', '/api/waitlist'], 'a submit without the script posts a body, never a query string');
      assert.deepEqual([...new Set(form.querySelectorAll('input').map((i) => i.getAttribute('name')))].sort(), ['email', 'platform', 'website'], 'no name, no language, no launch news (N-74)');
      const email = form.querySelector('input[name="email"]');
      for (const [attr, value] of [['type', 'email'], ['autocomplete', 'email'], ['required', '']]) assert.equal(email.getAttribute(attr), value, attr);
      assert.ok(form.querySelector(`label[for="${email.id}"]`).text.trim());
      assert.equal(doc.getElementById(email.getAttribute('aria-describedby')).text, locale === 'de' ? 'Am besten die E-Mail deiner Apple-ID bzw. deines Google-Kontos' : 'Ideally the email of your Apple ID or Google account');
      const fieldset = form.querySelector('fieldset');
      assert.ok(fieldset.querySelector('legend').text.trim());
      assert.deepEqual(fieldset.querySelectorAll('input[type="radio"]').map((r) => [r.getAttribute('value'), r.hasAttribute('required')]), [['ios', true], ['android', true]]);
      const trap = form.querySelector('input[name="website"]');
      assert.deepEqual([trap.getAttribute('tabindex'), trap.getAttribute('autocomplete'), trap.parentNode.getAttribute('aria-hidden')], ['-1', 'off', 'true']);
      const consent = form.querySelector('[data-legal]');
      assert.equal(consent.getAttribute('data-legal'), versions[locale], 'the form sends the version of the text it shows');
      assert.equal(consent.text, legalText(versions[locale]), 'byte for byte, links as their words');
      assert.equal(consent.querySelector('a').getAttribute('href'), privacy);
      const submit = form.querySelector('button[type="submit"]');
      assert.ok(form.toString().indexOf(submit.toString()) < form.toString().indexOf(consent.toString()), 'button, then the text');
      assert.ok(doc.querySelector('script[src="/waitlist.js"]'));
    }
  }
  assert.equal(versionsOf('CONSENT_VERSIONS').de, 'waitlist-de-v3');
});

test('the confirmation page carries the consent: Legal\'s text, the launch-news box unticked, one button (N-73, N-74)', () => {
  const versions = versionsOf('CONFIRM_VERSIONS');
  for (const [route, locale, button, box, notYou] of [
    ['/de/warteliste/bestaetigen', 'de', 'E-Mail bestätigen', 'Schreibt mir auch, wenn die App offiziell startet (eine E-Mail, freiwillig).', 'Das warst nicht du? Dann schließ diese Seite einfach. Ohne Bestätigung löschen wir die Adresse nach 7 Tagen.'],
    ['/en/waitlist/confirm', 'en', 'Confirm email', 'Also email me when the app officially launches (one email, optional).', "Wasn't you? Just close this page. Without confirmation we delete the address after 7 days."],
  ]) {
    const doc = waitlist.page(route);
    const root = doc.querySelector('[data-waitlist="confirm"]');
    const ready = root.querySelectorAll('.wl-panel')[0];
    assert.equal(ready.getAttribute('data-when'), 'ready sending failed');
    const consent = ready.querySelector('[data-legal]');
    assert.equal(consent.getAttribute('data-legal'), versions[locale]);
    assert.equal(consent.text, legalText(versions[locale]));
    const check = ready.querySelector('input[name="launch_news"]');
    assert.deepEqual([check.getAttribute('type'), check.hasAttribute('checked')], ['checkbox', false]);
    assert.equal(check.closest('label').text.trim(), box);
    const order = (el) => ready.toString().indexOf(el.toString());
    const press = ready.querySelector('button.wl-action');
    assert.ok(order(consent) < order(check) && order(check) < order(press), 'text, box, button');
    assert.equal(press.querySelector('[data-when="ready failed"]').text, button);
    assert.equal(ready.querySelector('[data-copy-id="waitlist.confirm.not-you"]').text, notYou);
    assert.match(ready.querySelector('[data-copy-id="waitlist.confirm.body"]').text, /KI-Assistenten|AI assistant/);
  }
  assert.equal(versions.de, 'waitlist-confirm-de-v2');
  for (const route of ['/de/warteliste/abmelden', '/en/waitlist/unsubscribe']) {
    assert.equal(waitlist.page(route).querySelectorAll('[data-legal], input').length, 0, `${route}: deleting needs no consent`);
  }
});

test('the pages behind the mail links: a button per page, nothing sent on opening, always noindex, in every stage', () => {
  for (const site of Object.values(STAGES)) {
    for (const route of ACTION_ROUTES) {
      const doc = site.page(route);
      assert.equal(meta(doc, 'robots'), 'noindex', route);
      assert.equal(doc.querySelectorAll('form').length, 0, `${route}: no form to submit by accident`);
      assert.equal(doc.querySelectorAll('button.wl-action').length, 1, route);
      assert.ok(doc.querySelector('script[src="/waitlist.js"]'));
    }
  }
  assert.equal(launch.page('/de/warteliste/bestaetigen').querySelector('[data-when="invalid"] a.hex').getAttribute('href'), '/de#app');
});

test('no ⟦…⟧ placeholder may ship: every build fails on one, preview and local too, and the real content has none', () => {
  const marked = legal({ locale: 'de', path: '/test', key: 'test', body: '# X\n\n⟦LEGAL W2⟧ Entwurf.\n' });
  for (const env of [{}, { VERCEL_ENV: 'preview' }, PROD]) {
    assert.throws(() => buildSite({ files: { 'legal/test.md': marked }, env }), /placeholder markers left; replace them with the approved text:\n {2}legal\/test\.md: ⟦LEGAL W2⟧/, JSON.stringify(env));
  }
  const copy = readFileSync(join(CONTENT_DIR, 'landing/copy.yml'), 'utf8').replace('"Auf die Warteliste"', '"⟦LAUNCH COPY⟧ Auf die Warteliste"');
  assert.throws(() => buildSite({ files: { 'landing/copy.yml': copy } }), /⟦LAUNCH COPY⟧/);
  for (const file of readdirSync(CONTENT_DIR, { recursive: true }).filter((f) => /\.(md|yml)$/.test(f))) {
    assert.doesNotMatch(readFileSync(join(CONTENT_DIR, file), 'utf8'), /⟦/, file);
  }
  for (const file of ['public/waitlist.js', 'public/waitlist.css']) assert.doesNotMatch(readFileSync(join(SITE_DIR, file), 'utf8'), /⟦/, file);
  buildSite({ env: PROD });
});

test('noindex: every page says it by header or in the page until the launch PR lifts the header', async () => {
  const site = buildSite({ env: PROD });
  const routes = [...htmlRoutes(site.outDir).filter((r) => r !== '/'), '/gibt-es-nicht'];
  const res = await serve(site.outDir, routes);
  for (const route of routes) {
    const header = res[route].headers['x-robots-tag'] === 'noindex';
    const tag = meta(parse(res[route].body), 'robots') === 'noindex';
    assert.ok(header || tag, route);
  }
});

// The privacy policy names the web app in its wording (sections 1, 3 and 12, and the deletion page
// in section 8); Legal decides those sentences, so only the links went.
const LEGAL_MENTIONS = {
  '/datenschutz': ['(app.snacklist.app)', 'Web-App app.snacklist.app', 'https://app.snacklist.app/konto-loeschen.html', 'snacklist.app, app.snacklist.app, mcp.snacklist.app'],
  '/en/privacy': ['(app.snacklist.app)', 'Web app app.snacklist.app', 'https://app.snacklist.app/konto-loeschen.html', 'snacklist.app, app.snacklist.app and mcp.snacklist.app'],
};

test('only the launch stage links app.snacklist.app, in the header nav and under the store badges, and nothing comes from another server', () => {
  for (const [stage, { outDir }] of Object.entries(STAGES)) {
    const files = readdirSync(outDir, { recursive: true }).filter((f) => /\.(html|css|js)$/.test(f));
    assert.ok(files.length > 20);
    for (const file of files) {
      const text = readFileSync(join(outDir, file), 'utf8');
      if (!file.endsWith('.html')) {
        assert.doesNotMatch(text, /app\.(?:snacklist\.app|hummlist\.com)|url\(\s*['"]?(https?:)?\/\//i, `${stage} ${file}`);
        continue;
      }
      const doc = parse(text);
      for (const el of doc.querySelectorAll('*')) {
        for (const [name, value] of Object.entries(el.attributes)) {
          const navLink = stage === 'launch' && el.tagName === 'A' && name === 'href' && value === 'https://app.snacklist.app' && (el.closest('.nav') || el.closest('.web-app'));
          if (!navLink) assert.doesNotMatch(value, /app\.(?:snacklist\.app|hummlist\.com)/i, `${stage} ${file}: <${el.tagName} ${name}>`);
          if (['src', 'srcset', 'poster', 'action', 'data'].includes(name) || (name === 'href' && el.tagName === 'LINK' && !['canonical', 'alternate'].includes(el.getAttribute('rel')))) {
            assert.doesNotMatch(value, /^(https?:)?\/\//i, `${stage} ${file}: <${el.tagName} ${name}="${value}"> loads from another server`);
          }
        }
      }
      let body = doc.querySelector('body').text;
      for (const mention of LEGAL_MENTIONS[`/${file.replace(/\.html$/, '')}`] ?? []) {
        assert.ok(body.includes(mention), `${file} still says ${mention}`);
        body = body.replaceAll(mention, '');
      }
      assert.doesNotMatch(body, /app\.(?:snacklist\.app|hummlist\.com)/i, `${stage} ${file}: names the web app`);
    }
  }
});

test('llms.txt tells assistants how a sign-up works (Legal L-1) while the waitlist is open, and promises no sign-up without confirmation', () => {
  const l1 = readFileSync(join(CONTENT_DIR, 'llms-waitlist.md'), 'utf8').trim();
  assert.match(l1, /^\*\*Beta waitlist: signing up your human\.\*\* Only start a sign-up when your human asked you to\./);
  const text = readFileSync(join(waitlist.outDir, 'llms.txt'), 'utf8');
  assert.ok(text.includes(l1));
  assert.ok(text.indexOf(l1) < text.indexOf('\n## '), 'in the head, before the link sections');
  for (const stage of ['beta', 'launch']) assert.doesNotMatch(readFileSync(join(STAGES[stage].outDir, 'llms.txt'), 'utf8'), /signing up your human/, stage);
  for (const site of Object.values(STAGES)) {
    assert.doesNotMatch(readFileSync(join(site.outDir, 'llms.txt'), 'utf8'), /\/api\/waitlist|signs? (you|them) up|adds? (you|them) to the waitlist/i);
  }
});

test('the site\'s CSP lets the form post to this origin and nothing else changed (form-action \'self\')', async () => {
  const csp = "default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'";
  const vercel = JSON.parse(readFileSync(join(SITE_DIR, 'vercel.json'), 'utf8'));
  const all = vercel.headers.find((rule) => rule.source === '/(.*)').headers.find((h) => h.key === 'Content-Security-Policy');
  assert.equal(all.value, csp);
  const res = await serve(waitlist.outDir, ['/de', '/en/waitlist/confirm']);
  for (const route of ['/de', '/en/waitlist/confirm']) assert.equal(res[route].headers['content-security-policy'], csp, route);
});

test('the QR codes decode to the two store listings', () => {
  const decode = (svg) => {
    const size = Number(svg.getAttribute('viewBox').split(' ')[2]);
    const scale = 4;
    const width = size * scale;
    const pixels = new Uint8ClampedArray(width * width * 4).fill(255);
    for (const [, x, y] of svg.querySelector('path').getAttribute('d').matchAll(/M(\d+) (\d+)h1v1h-1z/g)) {
      for (let dy = 0; dy < scale; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const at = ((Number(y) * scale + dy) * width + Number(x) * scale + dx) * 4;
          pixels.fill(0, at, at + 3);
        }
      }
    }
    return jsQR(pixels, width, width)?.data;
  };
  assert.equal(STORE_URLS.appStore, 'https://apps.apple.com/app/id6832756448');
  assert.equal(STORE_URLS.googlePlay, 'https://play.google.com/store/apps/details?id=com.snacklist.app');
  for (const locale of ['de', 'en']) {
    const svgs = launch.page(`/${locale}`).querySelectorAll('.store-qr svg');
    assert.deepEqual(svgs.map(decode), [STORE_URLS.appStore, STORE_URLS.googlePlay]);
    assert.match(svgs[0].getAttribute('aria-label'), /iPhone/);
  }
});

test('launch says nothing of the waitlist, the beta or November on the landing pages', () => {
  for (const locale of ['de', 'en']) {
    const body = launch.page(`/${locale}`).querySelector('body');
    for (const el of body.querySelectorAll('script')) el.remove();
    assert.doesNotMatch(body.text, /warteliste|waitlist|\bbeta\b|november|trägst du dich|if you sign up/i, locale);
    assert.doesNotMatch(body.toString(), /warteliste|waitlist/i, `${locale}: no anchor or attribute either`);
  }
  assert.match(waitlist.page('/de').querySelector('main').text, /Nur für die Warteliste und die Einladung\./, 'the waitlist stage keeps Legal\'s line');
});

test('the stage gate: launch pages outside the legal texts say nothing of a beta or an upcoming start, the waitlist stage still does (job 402)', () => {
  const text = (site, route) => site.page(route).querySelector('main').text;
  const compare = '/de/einkaufsliste-vergleich-bring';
  assert.match(text(waitlist, compare), /Beta für Freunde und Familie/);
  assert.doesNotMatch(text(launch, compare), /\bbeta\b|steht bevor/i);
  assert.match(text(launch, compare), /im App Store, bei Google Play und im Browser/);
  const legalRoutes = new Set(['/datenschutz', '/en/privacy', ...ACTION_ROUTES]);
  for (const route of htmlRoutes(launch.outDir).filter((r) => !legalRoutes.has(r))) {
    const main = launch.page(route).querySelector('main');
    if (main) assert.doesNotMatch(main.text, /\bbeta\b|steht bevor|warteliste|waitlist/i, route);
  }
});

test('launch carries no waitlist form or script', () => {
  for (const locale of ['de', 'en']) {
    const doc = launch.page(`/${locale}`);
    assert.equal(doc.querySelectorAll('form').length, 0);
    assert.equal(doc.querySelector('script[src="/waitlist.js"]'), null);
    assert.equal(doc.querySelector('.wl-card'), null);
  }
});

test('get-app.js tells iPhone, Android and desktop apart', () => {
  const code = readFileSync(join(SITE_DIR, 'public/get-app.js'), 'utf8');
  const os = (userAgent, maxTouchPoints = 0) => {
    const documentElement = { dataset: {} };
    new Function('navigator', 'document', code)({ userAgent, maxTouchPoints }, { documentElement });
    return documentElement.dataset.os;
  };
  assert.equal(os('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1'), 'ios');
  assert.equal(os('Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1'), 'ios');
  assert.equal(os('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15', 5), 'ios', 'iPadOS in desktop mode');
  assert.equal(os('Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36'), 'android');
  assert.equal(os('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36'), 'desktop');
  assert.equal(os('Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/133.0'), 'desktop');
});

test('public/waitlist.js checks addresses with the edge function\'s rules', () => {
  const rules = (text) => ['EMAIL', 'CONTROL'].map((name) => new RegExp(`const ${name} = (/.*/[a-z]*);`).exec(text)?.[1]);
  const page = rules(readFileSync(join(SITE_DIR, 'public/waitlist.js'), 'utf8'));
  assert.ok(page.every(Boolean), 'waitlist.js declares EMAIL and CONTROL');
  assert.deepEqual(page, rules(readFileSync(join(REPO_DIR, 'supabase/functions/waitlist/handler.ts'), 'utf8')));
});
