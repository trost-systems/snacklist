import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, alternates, hrefs, htmlRoutes, meta, record, serve } from './helpers.mjs';
import { RecordError } from '../releases.mjs';

const PROD = { VERCEL_ENV: 'production' };
const DE = '/de/changelog';
const EN = '/en/changelog';
const SITE = 'https://hummlist.com';
const EMPTY_DE = 'Die erste Version von Hummlist ist bald in den Stores. Hier steht dann, was jede neue Version bringt.';
const EMPTY_EN = "Hummlist's first version is coming to the stores soon. This page will then list what each new version brings.";
const SHA = (c) => c.repeat(40);

const item = (de, en, pr, sha) => ({ de, en, pr, sha });
const changelog = ({ title = { de: '', en: '' }, items = {} } = {}) => ({
  title,
  items: { new: [], improved: [], fixed: [], ...items },
  store: { app_store: { de: 'Neu: Listen teilen.', en: 'New: share lists.' }, play: { de: 'Neu: Listen teilen.', en: 'New: share lists.' } },
});
const draft = (version, body = changelog()) =>
  `${JSON.stringify({ version, status: 'draft', generated_from: { previous_sha: SHA('a'), sha: SHA('f') }, ...body }, null, 2)}\n`;

// 1.0.0 (2026-11-01) without a changelog, 1.1.0 (2026-11-02) with a title and every category.
const RECORD = record(['1.0.0', '1.1.0'], (data) => {
  data.releases[1].changelog = changelog({
    title: { de: 'Gemeinsam einkaufen', en: 'Shopping together' },
    items: {
      new: [item('Listen <teilen>', 'Share <lists>', 141, SHA('b')), item('Einladungslink', 'Invite link', null, SHA('c'))],
      improved: [item('Schnellere Suche', 'Faster search', 142, SHA('d'))],
      fixed: [item('Umlaute in Siri', 'Umlauts in Siri', 143, SHA('e'))],
    },
  });
  return data;
});
const DRAFTS = {
  '1.2.0.json': draft('1.2.0', changelog({ items: { new: [item('Kategorien sortieren', 'Sort categories', 150, SHA('9'))] } })),
  '1.1.0.json': draft('1.1.0', changelog({ items: { new: [item('Alter Entwurf', 'Old draft', 151, SHA('8'))] } })),
  'README.md': 'not a draft',
};
const FIXTURE = { record: RECORD, drafts: DRAFTS };

const sections = (doc) =>
  doc.querySelectorAll('main section').map((s) => ({
    id: s.id,
    heading: s.querySelector('h2').text,
    banner: s.querySelector('.draft-banner')?.text ?? null,
    date: s.querySelector('time')?.text ?? null,
    title: s.querySelector('.release-title')?.text ?? null,
    categories: s.querySelectorAll('h3').map((h) => [h.text, h.nextElementSibling.querySelectorAll('li').map((li) => li.text)]),
    text: s.querySelectorAll(':scope > p:not(.draft-banner):not(.release-date):not(.release-title)').map((p) => p.text),
  }));
const raw = (outDir, route) => readFileSync(join(outDir, `${route.slice(1)}.html`), 'utf8');

const RELEASED_DE = [
  {
    id: 'v1-1-0',
    heading: 'Version 1.1.0',
    banner: null,
    date: '2. November 2026',
    title: 'Gemeinsam einkaufen',
    categories: [
      ['Neu', ['Listen <teilen>', 'Einladungslink']],
      ['Verbessert', ['Schnellere Suche']],
      ['Behoben', ['Umlaute in Siri']],
    ],
    text: [],
  },
  { id: 'v1-0-0', heading: 'Version 1.0.0', banner: null, date: '1. November 2026', title: null, categories: [], text: ['Fehlerbehebungen und Verbesserungen.'] },
];
const RELEASED_EN = [
  {
    id: 'v1-1-0',
    heading: 'Version 1.1.0',
    banner: null,
    date: 'November 2, 2026',
    title: 'Shopping together',
    categories: [
      ['New', ['Share <lists>', 'Invite link']],
      ['Improved', ['Faster search']],
      ['Fixed', ['Umlauts in Siri']],
    ],
    text: [],
  },
  { id: 'v1-0-0', heading: 'Version 1.0.0', banner: null, date: 'November 1, 2026', title: null, categories: [], text: ['Bug fixes and improvements.'] },
];

test('production with no public release shows the empty state in both languages', async () => {
  const { outDir, page } = buildSite({ env: PROD });
  const de = page(DE);
  const en = page(EN);
  assert.equal(de.querySelector('h1').text, 'Neuigkeiten');
  assert.equal(en.querySelector('h1').text, "What's new");
  assert.deepEqual(de.querySelectorAll('main p').map((p) => p.text), [EMPTY_DE]);
  assert.deepEqual(en.querySelectorAll('main p').map((p) => p.text), [EMPTY_EN]);
  assert.equal(de.querySelector('title').text, 'Neuigkeiten | Hummlist');
  assert.equal(meta(de, 'description'), 'Was jede Version von Hummlist neu bringt, verbessert und behebt.');
  assert.equal(meta(en, 'description'), 'What each version of Hummlist adds, improves and fixes.');
  const res = await serve(outDir, [DE, EN]);
  assert.equal(res[DE].status, 200);
  assert.equal(res[EN].status, 200);
});

test('production lists the public releases newest first, localized, without drafts or commit data', () => {
  const { outDir, page } = buildSite({ env: PROD, repo: FIXTURE });
  assert.deepEqual(sections(page(DE)), RELEASED_DE);
  assert.deepEqual(sections(page(EN)), RELEASED_EN);
  for (const route of [DE, EN]) {
    const html = raw(outDir, route);
    assert.doesNotMatch(html, /Entwurf|Draft|Kategorien sortieren|Sort categories|Alter Entwurf|Old draft|1\.2\.0/, `${route}: no draft`);
    assert.doesNotMatch(html, /14[123]|bbbbbbbb|cccccccc|dddddddd|eeeeeeee/, `${route}: no PR number or sha`);
    assert.match(html, /<li>Listen &lt;teilen&gt;<\/li>|<li>Share &lt;lists&gt;<\/li>/, `${route}: text is escaped`);
    assert.equal(meta(page(route), 'robots'), undefined, `${route}: indexable`);
  }
});

test('preview and local builds put a draft for an unrecorded version on top with the banner', () => {
  for (const env of [{}, { VERCEL_ENV: 'preview' }]) {
    const { page } = buildSite({ env, repo: FIXTURE });
    const de = sections(page(DE));
    const en = sections(page(EN));
    assert.deepEqual(de[0], {
      id: 'v1-2-0',
      heading: 'Version 1.2.0',
      banner: 'Entwurf, noch nicht im Store',
      date: null,
      title: null,
      categories: [['Neu', ['Kategorien sortieren']]],
      text: [],
    });
    assert.equal(en[0].banner, 'Draft, not in the stores yet');
    assert.deepEqual(en[0].categories, [['New', ['Sort categories']]]);
    assert.deepEqual(de.slice(1), RELEASED_DE, 'the draft for the recorded 1.1.0 is skipped');
    assert.deepEqual(en.slice(1), RELEASED_EN);
    assert.equal(meta(page(DE), 'robots'), undefined, 'a banner, no page-level noindex');
  }
});

// Job 40: held items (a draft's `held`, pending.json) and the store-text override never reach a page.
test('held items, pending.json and an override are never rendered, preview included', () => {
  const held = { category: 'new', de: 'Mit Alexa fügst du Artikel hinzu.', en: 'Add items with Alexa.', flag: null, hold: 'alexa-certification', pr: 152, sha: SHA('7') };
  const body = changelog({ items: { new: [{ ...item('Widget', 'Widget', 153, SHA('6')), hold: 'ios-widget' }] } });
  const drafts = {
    '1.2.0.json': draft('1.2.0', { ...body, held: [held] }),
    'pending.json': `${JSON.stringify({ items: [held] }, null, 2)}\n`,
    '1.2.0.override.md': '## de\ntitle: Alexa\n\nAlexa\n\n## en\ntitle: Alexa\n\nAlexa\n',
  };
  for (const env of [{}, { VERCEL_ENV: 'preview' }, PROD]) {
    const { page } = buildSite({ env, repo: { record: RECORD, drafts } });
    for (const route of [DE, EN]) {
      assert.doesNotMatch(page(route).toString(), /Alexa|alexa-certification|ios-widget/, `${env.VERCEL_ENV ?? 'local'} ${route}`);
    }
    if (env !== PROD) assert.deepEqual(sections(page(EN))[0].categories, [['New', ['Widget']]], 'the open item shows, without its hold');
  }
});

test('a draft without items shows the neutral sentence; drafts sort by version', () => {
  const drafts = { '1.10.0.json': draft('1.10.0'), '1.9.0.json': draft('1.9.0') };
  const de = sections(buildSite({ repo: { drafts } }).page(DE));
  assert.deepEqual(de.map((s) => s.heading), ['Version 1.10.0', 'Version 1.9.0']);
  assert.deepEqual(de[0].text, ['Fehlerbehebungen und Verbesserungen.']);
});

test('a malformed or misnamed draft fails every build, production included', () => {
  for (const env of [{}, PROD]) {
    assert.throws(
      () => buildSite({ env, repo: { drafts: { '1.3.0.json': '{"version": "1.3.0"}' } } }),
      (e) => e instanceof RecordError && /^releases\/changelog\/1\.3\.0\.json: /.test(e.message),
    );
    assert.throws(() => buildSite({ env, repo: { drafts: { '1.3.0.json': '{' } } }), /releases\/changelog\/1\.3\.0\.json: not valid JSON/);
    assert.throws(
      () => buildSite({ env, repo: { drafts: { '1.3.json': draft('1.3.0') } } }),
      /releases\/changelog\/1\.3\.json: holds version 1\.3\.0, so the file must be named 1\.3\.0\.json/,
    );
  }
});

test('the two changelog pages pair with each other', () => {
  const { page } = buildSite({ env: PROD });
  const expected = { de: `${SITE}${DE}`, en: `${SITE}${EN}`, 'x-default': `${SITE}${DE}` };
  for (const [route, other, lang] of [[DE, EN, 'en'], [EN, DE, 'de']]) {
    const doc = page(route);
    assert.deepEqual(alternates(doc), expected, route);
    assert.equal(doc.querySelector('link[rel="canonical"]').getAttribute('href'), `${SITE}${route}`);
    assert.equal(meta(doc, 'og:url'), `${SITE}${route}`);
    assert.equal(meta(doc, 'og:type'), 'website');
    const link = doc.querySelector('header nav.lang a');
    assert.deepEqual([link.getAttribute('href'), link.getAttribute('hreflang')], [other, lang]);
  }
});

test('every page with a footer links the changelog of its language', () => {
  for (const env of [{}, PROD]) {
    const { outDir, page } = buildSite({ env });
    const routes = htmlRoutes(outDir).filter((r) => r !== '/' && r !== '/404');
    for (const route of ['/de/anleitungen', '/en/guides', '/de/anleitungen/alexa', '/en/guides/alexa', '/impressum', '/en/imprint', '/datenschutz', '/en/privacy']) {
      assert.ok(routes.includes(route), route);
    }
    for (const route of routes) {
      const doc = page(route);
      const links = doc.querySelectorAll('footer nav a').map((a) => [a.text, a.getAttribute('href')]);
      const expected = doc.querySelector('html').getAttribute('lang') === 'de' ? ['Neuigkeiten', DE] : ["What's new", EN];
      assert.ok(links.some((l) => l.join() === expected.join()), route);
    }
    assert.ok(hrefs(page('/impressum'), 'footer a').includes(DE));
  }
});
