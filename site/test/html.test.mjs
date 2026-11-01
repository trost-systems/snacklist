import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import matter from 'gray-matter';
import { buildSite, guide, htmlRoutes, meta, CONTENT_DIR } from './helpers.mjs';

test('every built page has one h1 and no skipped heading levels', () => {
  const { outDir, page } = buildSite();
  for (const route of htmlRoutes(outDir)) {
    const levels = page(route).querySelectorAll('h1, h2, h3, h4, h5, h6').map((h) => Number(h.tagName[1]));
    assert.equal(levels.filter((l) => l === 1).length, 1, `${route} has one h1`);
    levels.forEach((l, i) => assert.ok(l <= (levels[i - 1] ?? 0) + 1, `${route} skips to h${l}`));
  }
});

const failsWith = (body, pattern) =>
  assert.throws(() => buildSite({ files: { 'guides/en/bad.md': guide({ locale: 'en', slug: 'bad', body }) } }), pattern);

test('a second h1 fails the build', () => failsWith('# One\n\n# Two\n', /bad\.html: expected exactly one <h1>, found 2/));
test('a skipped heading level fails the build', () => failsWith('# One\n\n### Three\n', /bad\.html: heading level skipped: <h3>/));
test('an image without alt text fails the build', () => failsWith('# One\n\n![](/favicon.png)\n', /bad\.html: <img src="\/favicon.png"> has no alt text/));
test('an external image fails the build', () => failsWith('# One\n\n![Logo](https://example.com/x.png)\n', /external resource https:\/\/example.com\/x.png/));
test('an image with alt text builds', () => {
  const { page } = buildSite({ files: { 'guides/en/ok.md': guide({ locale: 'en', slug: 'ok', body: '# One\n\n![Hummlist logo](/favicon.png)\n' }) } });
  assert.equal(page('/en/guides/ok').querySelector('main img').getAttribute('alt'), 'Hummlist logo');
});

test('OG and Twitter tags equal the frontmatter', () => {
  const { page } = buildSite();
  const sources = {
    '/de/anleitungen/siri-kurzbefehl': ['guides/de/siri-kurzbefehl.md', 'article', 'de_DE'],
    '/en/guides/siri-shortcut': ['guides/en/siri-shortcut.md', 'article', 'en_US'],
    '/de/anleitungen': ['indexes/de.md', 'website', 'de_DE'],
    '/en/guides': ['indexes/en.md', 'website', 'en_US'],
    '/impressum': ['legal/impressum.md', 'website', 'de_DE'],
    '/en/imprint': ['legal/imprint.md', 'website', 'en_US'],
  };
  for (const [route, [file, type, locale]] of Object.entries(sources)) {
    const { title, description } = matter(readFileSync(join(CONTENT_DIR, file), 'utf8')).data;
    const doc = page(route);
    assert.equal(meta(doc, 'og:title'), title, route);
    assert.equal(meta(doc, 'twitter:title'), title, route);
    assert.equal(meta(doc, 'og:description'), description, route);
    assert.equal(meta(doc, 'twitter:description'), description, route);
    assert.equal(meta(doc, 'description'), description, route);
    assert.equal(meta(doc, 'og:type'), type, route);
    assert.equal(meta(doc, 'og:locale'), locale, route);
    assert.equal(meta(doc, 'og:url'), `https://hummlist.com${route}`, route);
    assert.equal(meta(doc, 'og:site_name'), 'Hummlist', route);
    assert.equal(meta(doc, 'twitter:card'), 'summary', route);
    assert.equal(doc.querySelector('link[rel="canonical"]').getAttribute('href'), `https://hummlist.com${route}`, route);
  }
});

test('guides show the localized updated date', () => {
  const { page } = buildSite();
  assert.match(page('/de/anleitungen/siri-kurzbefehl').querySelector('main').text, /Aktualisiert: 30\. Oktober 2026/);
  assert.match(page('/en/guides/siri-shortcut').querySelector('main').text, /Updated: October 27, 2026/);
});

test('the root page refreshes to the German landing page and links both landing pages', () => {
  const doc = buildSite().page('/');
  assert.equal(doc.querySelector('html').getAttribute('lang'), 'de');
  assert.equal(doc.querySelector('meta[http-equiv="refresh"]').getAttribute('content'), '0; url=/de');
  assert.deepEqual(doc.querySelectorAll('a').map((a) => a.getAttribute('href')), ['/de', '/en']);
});

test('code blocks and tables can take keyboard focus, since they scroll sideways on phones', () => {
  const doc = buildSite().page('/de/anleitungen/siri-kurzbefehl');
  const scrollers = doc.querySelectorAll('main pre, main table');
  assert.ok(scrollers.length >= 3);
  for (const el of scrollers) assert.equal(el.getAttribute('tabindex'), '0', el.tagName);
});
