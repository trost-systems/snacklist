import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'node-html-parser';
import { buildSite, guide, htmlRoutes, legal, meta, serve, CONTENT_DIR, REPO_DIR, SITE_DIR } from './helpers.mjs';

const ON = { HUMMLIST_WAITLIST: 'on' };
const PROD = { VERCEL_ENV: 'production' };
const ACTION_ROUTES = ['/de/warteliste/bestaetigen', '/de/warteliste/abmelden', '/en/waitlist/confirm', '/en/waitlist/unsubscribe'];
const MARKER = /⟦[^⟧]*⟧ ?/g;

// The real content with every approval marker and [PETER: …] gone, as it will be once Peter has
// approved the copy and the legal texts.
function approved() {
  return Object.fromEntries(
    readdirSync(CONTENT_DIR, { recursive: true })
      .filter((f) => /\.(md|yml)$/.test(f))
      .map((f) => [f, readFileSync(join(CONTENT_DIR, f), 'utf8').replace(MARKER, '').replace(/\[PETER:[^\]]*\]/g, 'filled')]),
  );
}

const main = (doc) => doc.querySelector('main').toString();

test('waitlist mode is on in preview and local builds, off in production unless HUMMLIST_WAITLIST says otherwise', () => {
  const cases = [
    [{ HUMMLIST_WAITLIST: undefined }, true],
    [{ HUMMLIST_WAITLIST: undefined, VERCEL_ENV: 'preview' }, true],
    [{ HUMMLIST_WAITLIST: 'off', VERCEL_ENV: 'preview' }, false],
    [{ HUMMLIST_WAITLIST: '', ...PROD }, false],
    [{ HUMMLIST_WAITLIST: 'off', ...PROD }, false],
  ];
  for (const [env, on] of cases) {
    const site = buildSite({ env });
    assert.equal(site.waitlist, on, JSON.stringify(env));
    assert.equal(site.routes.includes('/de/warteliste/bestaetigen'), on, JSON.stringify(env));
    assert.equal(site.page('/de').querySelector('form[novalidate]') !== null, on, JSON.stringify(env));
  }
  assert.throws(() => buildSite({ env: { HUMMLIST_WAITLIST: 'yes' } }), /HUMMLIST_WAITLIST must be "on" or "off" \(or unset\), got "yes"/);
});

test('a production build in waitlist mode fails while a copy or legal placeholder is left, and builds once they are gone', () => {
  assert.throws(
    () => buildSite({ env: { ...PROD, ...ON } }),
    (e) => ['⟦LAUNCH COPY⟧', '⟦LAUNCH COPY FAQ⟧', '⟦LEGAL W1⟧', '⟦LEGAL W2⟧', '⟦LEGAL privacy.website⟧'].every((m) => e.message.includes(m)) && /placeholders left in published pages/.test(e.message),
  );
  const withPeter = approved();
  withPeter['legal/impressum.md'] = withPeter['legal/impressum.md'].replace('# Impressum', '# Impressum\n\n[PETER: Telefon]');
  assert.throws(() => buildSite({ files: withPeter, env: { ...PROD, ...ON } }), /legal\/impressum\.md: \[PETER: Telefon\]/);
  const site = buildSite({ files: approved(), env: { ...PROD, ...ON } });
  assert.equal(site.waitlist, true);
  assert.deepEqual(site.warnings, []);
});

test('outside production the placeholders show as tags in the page text, never inside attributes or the head', () => {
  const { page, warnings } = buildSite({ env: ON });
  assert.match(warnings.join('\n'), /⟦LEGAL W2⟧/);
  const de = page('/de');
  const tags = de.querySelectorAll('mark.placeholder').map((m) => m.text);
  for (const marker of ['⟦LAUNCH COPY⟧', '⟦LAUNCH COPY FAQ⟧', '⟦LEGAL W2⟧', '⟦LEGAL privacy.website⟧']) assert.ok(tags.includes(marker), marker);
  assert.ok(page('/datenschutz').querySelectorAll('mark.placeholder').some((m) => m.text === '⟦LEGAL W1⟧'));
  assert.doesNotMatch(de.querySelector('head').toString(), /<mark/);
  for (const el of de.querySelectorAll('*')) {
    for (const value of Object.values(el.attributes)) assert.doesNotMatch(value, /<mark/, el.tagName);
  }
});

test('the sign-up form: one email field with its hint, iPhone or Android, the launch-news box above the button, the consent text under it', () => {
  const { page } = buildSite({ env: ON });
  const versions = /CONSENT_VERSIONS = \{ de: '([^']+)', en: '([^']+)' \}/.exec(readFileSync(join(REPO_DIR, 'supabase/functions/waitlist/consent.ts'), 'utf8'));
  assert.ok(versions, 'supabase/functions/waitlist/consent.ts names the consent versions');
  for (const [locale, version, privacy, button] of [['de', versions[1], '/datenschutz', 'Auf die Warteliste'], ['en', versions[2], '/en/privacy', 'Join the waitlist']]) {
    const doc = page(`/${locale}`);
    assert.equal(doc.querySelector('html').getAttribute('lang'), locale);
    const form = doc.querySelector('.hero form');
    assert.ok(form, `${locale}: the form is in the hero`);
    assert.deepEqual([...new Set(form.querySelectorAll('input').map((i) => i.getAttribute('name')))].sort(), ['email', 'launch_news', 'platform', 'website'], 'no name, no language field');
    const email = form.querySelector('input[name="email"]');
    for (const [attr, value] of [['type', 'email'], ['autocomplete', 'email'], ['required', '']]) assert.equal(email.getAttribute(attr), value, attr);
    assert.equal(form.querySelector(`label[for="${email.id}"]`).text.trim().length > 0, true, 'labelled');
    const hint = doc.getElementById(email.getAttribute('aria-describedby'));
    assert.equal(hint.text, locale === 'de' ? 'Am besten die E-Mail deiner Apple-ID bzw. deines Google-Kontos' : 'Ideally the email of your Apple ID or Google account');
    const fieldset = form.querySelector('fieldset');
    assert.ok(fieldset.querySelector('legend').text.trim());
    assert.deepEqual(fieldset.querySelectorAll('input[type="radio"]').map((r) => [r.getAttribute('name'), r.getAttribute('value'), r.hasAttribute('required')]), [['platform', 'ios', true], ['platform', 'android', true]]);
    assert.deepEqual(fieldset.querySelectorAll('label').map((l) => l.text.trim()), ['iPhone', 'Android']);
    const box = form.querySelector('input[name="launch_news"]');
    assert.equal(box.getAttribute('type'), 'checkbox');
    assert.equal(box.hasAttribute('checked'), false, 'not ticked');
    const trap = form.querySelector('input[name="website"]');
    assert.deepEqual([trap.getAttribute('tabindex'), trap.getAttribute('autocomplete'), trap.parentNode.getAttribute('aria-hidden')], ['-1', 'off', 'true']);
    const submit = form.querySelector('button[type="submit"]');
    assert.equal(submit.querySelector('[data-when="idle"]').text, button);
    const consent = form.querySelector('[data-legal]');
    assert.equal(consent.getAttribute('data-legal'), version, 'the form sends the version of the text it shows');
    const file = readFileSync(join(CONTENT_DIR, `legal/consent/${version}.md`), 'utf8').trim();
    assert.equal(consent.text, file.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1'));
    assert.ok(consent.text.includes(`„${button}“`) || consent.text.includes(`"${button}"`), 'the consent text names the button');
    assert.equal(consent.querySelector('a').getAttribute('href'), privacy);
    const order = (el) => form.toString().indexOf(el.toString());
    assert.ok(order(box) < order(submit) && order(submit) < order(consent), 'box, button, consent text');
    assert.ok(doc.querySelector('script[src="/waitlist.js"]'));
  }
});

test('in waitlist mode the header button and the closing block lead to the form, the test block and the browser are gone', () => {
  const { page, outDir } = buildSite({ env: ON });
  for (const [locale, anchor] of [['de', 'warteliste'], ['en', 'waitlist']]) {
    const doc = page(`/${locale}`);
    assert.equal(doc.querySelector('header a.header-cta').getAttribute('href'), `#${anchor}`);
    assert.ok(doc.getElementById(anchor).querySelector('form'));
    assert.equal(doc.querySelector('#test'), null);
    assert.ok(doc.querySelector('#faq details summary'));
    assert.ok(doc.querySelectorAll('main a').some((a) => a.getAttribute('href') === `#${anchor}` && a.closest('.cta')));
    assert.doesNotMatch(doc.querySelector('body').text, /browser/i, locale);
    assert.equal(doc.querySelector('[data-copy-id="privacy.website"]'), null);
    assert.match(doc.querySelector('[data-copy-id="waitlist.privacy-website"]').text, /Supabase in Frankfurt/);
    assert.ok(doc.querySelector('[data-copy-id="feature.stores.more"]'), 'the own-stores claim stays');
  }
  for (const route of htmlRoutes(outDir).filter((r) => !['/', '/404', '/de', '/en'].includes(r))) {
    const doc = page(route);
    const landing = doc.querySelector('html').getAttribute('lang') === 'de' ? '/de#warteliste' : '/en#waitlist';
    assert.equal(doc.querySelector('header a.header-cta').getAttribute('href'), landing, route);
    assert.equal(doc.querySelector('footer .tagline').getAttribute('data-copy-id'), 'waitlist.footer-tagline', route);
  }
});

test('the pages behind the mail links: a button per page, nothing sent on opening, always noindex, only in waitlist mode', () => {
  const { page, routes } = buildSite({ env: ON });
  const expected = {
    '/de/warteliste/bestaetigen': ['confirm', 'E-Mail bestätigen'],
    '/de/warteliste/abmelden': ['unsubscribe', 'Eintrag löschen'],
    '/en/waitlist/confirm': ['confirm', 'Confirm email'],
    '/en/waitlist/unsubscribe': ['unsubscribe', 'Delete my sign-up'],
  };
  for (const [route, [action, button]] of Object.entries(expected)) {
    assert.ok(routes.includes(route), route);
    const doc = page(route);
    assert.equal(doc.querySelector('html').getAttribute('lang'), route.slice(1, 3));
    assert.equal(meta(doc, 'robots'), 'noindex', route);
    const root = doc.querySelector(`[data-waitlist="${action}"]`);
    assert.equal(root.getAttribute('data-state'), 'ready');
    assert.equal(root.querySelector('button[type="button"] [data-when="ready failed"]').text, button, route);
    assert.equal(doc.querySelectorAll('form').length, 0, `${route}: no form to submit by accident`);
    assert.ok(doc.querySelector('script[src="/waitlist.js"]'));
  }
  assert.equal(page('/de/warteliste/bestaetigen').querySelector('nav.lang a').getAttribute('href'), '/en/waitlist/confirm');
  const prod = buildSite({ files: approved(), env: { ...PROD, ...ON } });
  for (const route of ACTION_ROUTES) assert.equal(meta(prod.page(route), 'robots'), 'noindex', `${route} in production`);
  const classic = buildSite();
  for (const route of ACTION_ROUTES) assert.ok(!classic.routes.includes(route), route);
});

test('noindex: every page says it by header or in the page, except /de and /en of a production build in waitlist mode', async () => {
  const classic = buildSite({ env: PROD });
  const preview = buildSite({ files: approved(), env: { VERCEL_ENV: 'preview', HUMMLIST_WAITLIST: undefined } });
  const live = buildSite({ files: approved(), env: { ...PROD, ...ON } });
  assert.deepEqual([classic.waitlist, preview.waitlist, live.waitlist], [false, true, true]);
  for (const [site, indexable] of [[classic, []], [preview, []], [live, ['/de', '/en']]]) {
    const routes = [...htmlRoutes(site.outDir).filter((r) => r !== '/'), '/gibt-es-nicht'];
    const res = await serve(site.outDir, routes);
    for (const route of routes) {
      const header = res[route].headers['x-robots-tag'] === 'noindex';
      const tag = meta(parse(res[route].body), 'robots') === 'noindex';
      assert.equal(header || tag, !indexable.includes(route), `${route} (waitlist ${site.waitlist})`);
    }
  }
});

test('::: waitlist and ::: classic blocks render in their mode only, also inside a list item', () => {
  const body = '# X\n\nVorher.\n\n::: waitlist\nNur Warteliste.\n:::\n\n::: classic\nNur klassisch.\n:::\n\n- Eins\n\n  ::: waitlist\n  Im Punkt.\n  :::\n\nNachher.\n';
  const files = { 'guides/de/x.md': guide({ locale: 'de', slug: 'x', body }), 'legal/test.md': legal({ locale: 'de', path: '/test', key: 'test', body }) };
  for (const route of ['/de/anleitungen/x', '/test']) {
    const on = main(buildSite({ files, env: ON }).page(route));
    assert.match(on, /Nur Warteliste\./);
    assert.match(on, /Im Punkt\./);
    assert.doesNotMatch(on, /Nur klassisch|:::/);
    const off = main(buildSite({ files }).page(route));
    assert.match(off, /Nur klassisch\./);
    assert.doesNotMatch(off, /Nur Warteliste|Im Punkt|:::/);
    assert.match(off, /Vorher\.[\s\S]*Nachher\./);
  }
  const at = (text) => ({ 'legal/test.md': legal({ locale: 'de', path: '/test', key: 'test', body: text }) });
  assert.throws(() => buildSite({ files: at('# X\n\n::: waitlist\nY\n') }), /legal\/test\.md: "::: waitlist" is not closed; end it with a line ":::"/);
  assert.throws(() => buildSite({ files: at('# X\n\n::: waitlist\n~~~\n:::\n~~~\n:::\n') }), /a code fence inside "::: waitlist" holds a ":::" line/);
  assert.throws(() => buildSite({ files: at('# X\n\n::: warteliste\nY\n:::\n') }), /"::: warteliste" is not a block this site knows/);
});

// The privacy policy names the web app in its wording (sections 1, 3 and 12, and the deletion page
// in section 8); Legal decides those sentences, so waitlist mode drops only the links.
const LEGAL_MENTIONS = {
  '/datenschutz': ['(app.hummlist.com)', 'Web-App app.hummlist.com', 'https://app.hummlist.com/konto-loeschen.html', 'hummlist.com, app.hummlist.com, mcp.hummlist.com'],
  '/en/privacy': ['(app.hummlist.com)', 'Web app app.hummlist.com', 'https://app.hummlist.com/konto-loeschen.html', 'hummlist.com, app.hummlist.com and mcp.hummlist.com'],
};

test('in waitlist mode no page links, loads or names a URL of app.hummlist.com, and nothing comes from another server', () => {
  const { outDir } = buildSite({ env: ON });
  const files = readdirSync(outDir, { recursive: true }).filter((f) => /\.(html|css|js)$/.test(f));
  assert.ok(files.length > 20);
  for (const file of files) {
    const text = readFileSync(join(outDir, file), 'utf8');
    if (!file.endsWith('.html')) {
      assert.doesNotMatch(text, /app\.hummlist\.com|url\(\s*['"]?(https?:)?\/\//i, file);
      continue;
    }
    const doc = parse(text);
    for (const el of doc.querySelectorAll('*')) {
      for (const [name, value] of Object.entries(el.attributes)) {
        assert.doesNotMatch(value, /app\.hummlist\.com/i, `${file}: <${el.tagName} ${name}>`);
        if (['src', 'srcset', 'poster', 'action', 'data'].includes(name) || (name === 'href' && el.tagName === 'LINK' && !['canonical', 'alternate'].includes(el.getAttribute('rel')))) {
          assert.doesNotMatch(value, /^(https?:)?\/\//i, `${file}: <${el.tagName} ${name}="${value}"> loads from another server`);
        }
      }
    }
    const route = `/${file.replace(/\.html$/, '')}`;
    let body = doc.querySelector('body').text;
    for (const mention of LEGAL_MENTIONS[route] ?? []) {
      assert.ok(body.includes(mention), `${route} still says ${mention}`);
      body = body.replaceAll(mention, '');
    }
    assert.doesNotMatch(body, /app\.hummlist\.com/i, `${file}: names the web app`);
  }
});

test('without waitlist mode the build ships none of it: no script, styles, pages or placeholders', () => {
  const { outDir, page } = buildSite({ env: PROD });
  for (const file of ['waitlist.js', 'waitlist.css', 'de/warteliste/bestaetigen.html', 'en/waitlist/unsubscribe.html']) assert.ok(!existsSync(join(outDir, file)), file);
  for (const file of readdirSync(outDir, { recursive: true }).filter((f) => f.endsWith('.html'))) {
    assert.doesNotMatch(readFileSync(join(outDir, file), 'utf8'), /⟦|waitlist|warteliste/i, file);
  }
  assert.equal(page('/de').querySelector('header a.header-cta').getAttribute('href'), 'https://app.hummlist.com');
  assert.ok(page('/de').querySelector('#test'));
});

test('public/waitlist.js checks addresses with the edge function\'s rules', () => {
  const rules = (text) => ['EMAIL', 'CONTROL'].map((name) => new RegExp(`const ${name} = (/.*/[a-z]*);`).exec(text)?.[1]);
  const page = rules(readFileSync(join(SITE_DIR, 'public/waitlist.js'), 'utf8'));
  assert.ok(page.every(Boolean), 'waitlist.js declares EMAIL and CONTROL');
  assert.deepEqual(page, rules(readFileSync(join(REPO_DIR, 'supabase/functions/waitlist/handler.ts'), 'utf8')));
});
