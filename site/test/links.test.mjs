import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSite, guide, legal, hrefs, alternates, htmlRoutes } from './helpers.mjs';

const SITE = 'https://hummlist.com';
const switchLink = (doc) => {
  const a = doc.querySelector('header nav.lang a');
  return { href: a.getAttribute('href'), lang: a.getAttribute('lang'), hreflang: a.getAttribute('hreflang') };
};

test('the Siri guide pair switches language and lists both alternates', () => {
  const { page } = buildSite();
  const de = page('/de/anleitungen/siri-kurzbefehl');
  const en = page('/en/guides/siri-shortcut');
  assert.equal(de.querySelector('html').getAttribute('lang'), 'de');
  assert.equal(en.querySelector('html').getAttribute('lang'), 'en');
  assert.deepEqual(switchLink(de), { href: '/en/guides/siri-shortcut', lang: 'en', hreflang: 'en' });
  assert.deepEqual(switchLink(en), { href: '/de/anleitungen/siri-kurzbefehl', lang: 'de', hreflang: 'de' });
  const expected = {
    de: `${SITE}/de/anleitungen/siri-kurzbefehl`,
    en: `${SITE}/en/guides/siri-shortcut`,
    'x-default': `${SITE}/de/anleitungen/siri-kurzbefehl`,
  };
  assert.deepEqual(alternates(de), expected);
  assert.deepEqual(alternates(en), expected);
});

test('indexes and the imprint pair with each other', () => {
  const { page } = buildSite();
  assert.deepEqual(switchLink(page('/de/anleitungen')).href, '/en/guides');
  assert.deepEqual(switchLink(page('/en/guides')).href, '/de/anleitungen');
  assert.deepEqual(switchLink(page('/impressum')).href, '/en/imprint');
  assert.deepEqual(alternates(page('/en/imprint')), { de: `${SITE}/impressum`, en: `${SITE}/en/imprint`, 'x-default': `${SITE}/impressum` });
});

test('a guide without translation links to the other index and has no alternate for it', () => {
  const { page } = buildSite({
    files: {
      'guides/en/only-english.md': guide({ locale: 'en', slug: 'only-english' }),
      'guides/de/nur-deutsch.md': guide({ locale: 'de', slug: 'nur-deutsch' }),
    },
  });
  const en = page('/en/guides/only-english');
  assert.equal(switchLink(en).href, '/de/anleitungen');
  assert.deepEqual(alternates(en), { en: `${SITE}/en/guides/only-english`, 'x-default': `${SITE}/en/guides/only-english` });
  const de = page('/de/anleitungen/nur-deutsch');
  assert.equal(switchLink(de).href, '/en/guides');
  assert.deepEqual(alternates(de), { de: `${SITE}/de/anleitungen/nur-deutsch`, 'x-default': `${SITE}/de/anleitungen/nur-deutsch` });
});

test('the site name links to the landing page of its language, in the header and the footer', () => {
  const { page } = buildSite();
  for (const [route, landing] of [['/en/imprint', '/en'], ['/impressum', '/de'], ['/de/anleitungen/alexa', '/de'], ['/en', '/en']]) {
    assert.equal(page(route).querySelector('header a.brand').getAttribute('href'), landing, route);
    assert.equal(page(route).querySelector('footer a.brand').getAttribute('href'), landing, route);
  }
});

test('every page links the guides, the changelog and the web app in the header', () => {
  const { outDir, page } = buildSite();
  for (const route of htmlRoutes(outDir).filter((r) => r !== '/' && r !== '/404')) {
    const doc = page(route);
    const de = doc.querySelector('html').getAttribute('lang') === 'de';
    const nav = doc.querySelectorAll('header nav.nav a').map((a) => [a.text, a.getAttribute('href')]);
    assert.deepEqual(nav, de ? [['Anleitungen', '/de/anleitungen'], ['Neuigkeiten', '/de/changelog']] : [['Guides', '/en/guides'], ["What's new", '/en/changelog']], route);
    assert.equal(doc.querySelector('header a.header-cta').getAttribute('href'), 'https://app.hummlist.com', route);
    assert.equal(doc.querySelector('a.skip').getAttribute('href'), '#inhalt', route);
    assert.ok(doc.querySelector('main#inhalt'), route);
  }
  assert.equal(page('/de/anleitungen').querySelector('header [aria-current="page"]').getAttribute('href'), '/de/anleitungen');
  assert.equal(page('/en/changelog').querySelector('header [aria-current="page"]').getAttribute('href'), '/en/changelog');
  assert.equal(page('/de').querySelector('header [aria-current]'), null);
});

const SITE_LINKS = {
  de: [['Anleitungen', '/de/anleitungen'], ['Neuigkeiten', '/de/changelog']],
  en: [['Guides', '/en/guides'], ["What's new", '/en/changelog']],
};
const footer = (doc) => doc.querySelectorAll('footer nav a').map((a) => [a.text, a.getAttribute('href')]);

const LEGAL_PATHS = ['/datenschutz', '/en/privacy', '/privacy', '/support', '/en/support'];

test('with nothing published the footer links only the imprint', () => {
  const { outDir, page } = buildSite({ config: { privacyPublished: false, supportPublished: false } });
  assert.deepEqual(footer(page('/de/anleitungen/siri-kurzbefehl')), [...SITE_LINKS.de, ['Impressum', '/impressum']]);
  assert.deepEqual(footer(page('/en/guides')), [...SITE_LINKS.en, ['Imprint', '/en/imprint']]);
  assert.deepEqual(footer(page('/de')), [...SITE_LINKS.de, ['Impressum', '/impressum']]);
  for (const route of htmlRoutes(outDir)) {
    const links = page(route).querySelectorAll('footer a').map((a) => a.getAttribute('href'));
    for (const path of LEGAL_PATHS) assert.ok(!links.includes(path), `${route} links ${path} in the footer`);
    assert.equal(page(route).querySelectorAll('footer li').filter((li) => !li.text.trim()).length, 0, `${route} has empty footer items`);
  }
});

test('the published privacy policy is in the footer of every page, support is not', () => {
  const { outDir, page } = buildSite({ config: { privacyPublished: true, supportPublished: false } });
  for (const route of htmlRoutes(outDir).filter((r) => r !== '/' && r !== '/404')) {
    const locale = page(route).querySelector('html').getAttribute('lang');
    const expected = locale === 'de'
      ? [...SITE_LINKS.de, ['Impressum', '/impressum'], ['Datenschutz', '/datenschutz']]
      : [...SITE_LINKS.en, ['Imprint', '/en/imprint'], ['Privacy', '/en/privacy']];
    assert.deepEqual(footer(page(route)), expected, route);
  }
});

test('the privacy policy pair switches language and has the rights anchor', () => {
  const { page } = buildSite();
  assert.equal(switchLink(page('/datenschutz')).href, '/en/privacy');
  assert.equal(switchLink(page('/en/privacy')).href, '/datenschutz');
  assert.deepEqual(alternates(page('/en/privacy')), { de: `${SITE}/datenschutz`, en: `${SITE}/en/privacy`, 'x-default': `${SITE}/datenschutz` });
  assert.match(page('/datenschutz').querySelector('#rechte').text, /^15\. Deine Rechte$/);
  assert.match(page('/en/privacy').querySelector('#rights').text, /^15\. Your rights$/);
});

test('with support published and its page present the footer links it too', () => {
  const { page } = buildSite({
    config: { privacyPublished: true, supportPublished: true },
    files: { 'legal/support.md': legal({ locale: 'de', path: '/support', key: 'support' }) },
  });
  assert.deepEqual(footer(page('/de/anleitungen')), [...SITE_LINKS.de, ['Impressum', '/impressum'], ['Datenschutz', '/datenschutz'], ['Hilfe', '/support']]);
  assert.deepEqual(footer(page('/en/guides')), [...SITE_LINKS.en, ['Imprint', '/en/imprint'], ['Privacy', '/en/privacy'], ['Support', '/en/support']]);
});

test('a published flag without its page fails the build on the broken link', () => {
  // Production leaving the drafts out breaks the link the same way (draft.test.mjs).
  assert.throws(() => buildSite({ config: { supportPublished: true }, files: { 'legal/support.md': null, 'legal/support-en.md': null } }), /broken internal link \/(en\/)?support/);
  assert.throws(
    () => buildSite({ config: { privacyPublished: true }, files: { 'legal/privacy.md': null } }),
    /broken internal link \/en\/privacy/,
  );
});

test('a broken internal link in content fails the build', () => {
  const body = '# Broken\n\nSee [missing](/de/anleitungen/gibt-es-nicht#teil).\n';
  assert.throws(
    () => buildSite({ files: { 'guides/de/kaputt.md': guide({ locale: 'de', slug: 'kaputt', body }) } }),
    /de\/anleitungen\/kaputt\.html: broken internal link \/de\/anleitungen\/gibt-es-nicht#teil/,
  );
});
