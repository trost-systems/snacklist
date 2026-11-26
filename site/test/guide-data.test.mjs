// The guides as JSON for the app (job 462, README.md "Data for the app"): the blocks the guide's
// page shows in the same build, under dist/data/guides/<locale>/.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, guide, htmlRoutes, record } from './helpers.mjs';
import { LOCALES, readConfig } from '../build.mjs';
import { ALEXA_SKILL_URLS } from '../config/stores.mjs';

const PROD = { VERCEL_ENV: 'production' };
const { siteUrl } = readConfig();
const json = (site, locale, name) => JSON.parse(readFileSync(join(site.outDir, 'data/guides', locale, `${name}.json`), 'utf8'));
const has = (site, locale, name) => existsSync(join(site.outDir, 'data/guides', locale, `${name}.json`));

const blocksOf = (blocks) => blocks.flatMap((b) => [b, ...blocksOf(b.blocks ?? []), ...(b.items ?? []).flatMap(blocksOf)]);
const spansOf = (blocks) =>
  blocksOf(blocks).flatMap((b) => [...(b.text && typeof b.text !== 'string' ? b.text : []), ...(b.header ?? []).flat(), ...(b.rows ?? []).flat(2)]);
const plain = (spans) => spans.map((s) => s.text).join('');

const real = buildSite({ env: PROD });

test('every guide production renders has its JSON; each index lists what its page lists', () => {
  for (const [locale, { guidesBase }] of Object.entries(LOCALES)) {
    const routes = htmlRoutes(real.outDir).filter((r) => r.startsWith(`${guidesBase}/`));
    const files = readdirSync(join(real.outDir, 'data/guides', locale)).filter((f) => f !== 'index.json');
    assert.ok(routes.length > 0, locale);
    assert.deepEqual(files.sort(), routes.map((r) => `${r.slice(guidesBase.length + 1)}.json`).sort(), `${locale}: one JSON per guide page`);
    for (const route of routes) {
      const slug = route.slice(guidesBase.length + 1);
      const data = json(real, locale, slug);
      const page = real.page(route);
      assert.deepEqual(
        { schema: data.schema, locale: data.locale, slug: data.slug, title: data.title, url: data.url },
        { schema: 1, locale, slug, title: page.querySelector('meta[property="og:title"]').getAttribute('content'), url: siteUrl + route },
      );
      assert.match(data.updated, /^\d{4}-\d{2}-\d{2}$/);
      assert.ok(data.description.length > 0);
      assert.ok(!blocksOf(data.blocks).some((b) => b.type === 'heading' && b.level === 1), `${route}: the h1 is the title, not a block`);
    }
    const index = json(real, locale, 'index');
    const indexPage = real.page(guidesBase);
    assert.equal(index.schema, 1);
    assert.equal(index.locale, locale);
    assert.equal(index.title, indexPage.querySelector('h1').text);
    assert.deepEqual(index.guides.map((g) => g.url), indexPage.querySelectorAll('.guide-list a').map((a) => siteUrl + a.getAttribute('href')));
    for (const g of index.guides) assert.deepEqual(Object.keys(g), ['slug', 'title', 'description', 'url']);
  }
});

test('the real guides use every block type, with ids, and links the app can open', () => {
  const all = Object.entries(LOCALES).flatMap(([locale]) => json(real, locale, 'index').guides.map((g) => json(real, locale, g.slug)));
  const blocks = all.flatMap((g) => blocksOf(g.blocks));
  for (const type of ['heading', 'paragraph', 'list', 'quote', 'code', 'table']) assert.ok(blocks.some((b) => b.type === type), type);
  assert.ok(blocks.some((b) => b.type === 'list' && b.ordered) && blocks.some((b) => b.type === 'list' && !b.ordered), 'ordered and bullet lists');
  for (const b of blocks.filter((b) => b.type === 'heading')) assert.ok(b.level >= 2 && b.level <= 4 && (b.id === null || /^[a-z0-9-]+$/.test(b.id)), JSON.stringify(b));
  for (const guide of all) {
    const ids = new Set(blocksOf(guide.blocks).filter((b) => b.type === 'heading' && b.id).map((b) => b.id));
    for (const { href } of spansOf(guide.blocks).filter((s) => s.href)) {
      if (href.startsWith('#')) assert.ok(ids.has(href.slice(1)), `${guide.url}: ${href} names a heading`);
      else assert.match(href, /^(https:\/\/|mailto:)/, `${guide.url}: ${href}`);
    }
  }
  const hrefs = all.flatMap((g) => spansOf(g.blocks)).map((s) => s.href);
  assert.ok(hrefs.includes(`${siteUrl}/datenschutz`), 'a site-relative link is made absolute');
  assert.ok(hrefs.includes(ALEXA_SKILL_URLS.de) && hrefs.includes(ALEXA_SKILL_URLS.en), 'alexa-skill links go to the skill pages');
  assert.ok(!hrefs.some((h) => h?.startsWith('alexa-skill:')));
});

test('with alexaPublished off, the skill links are plain text in the JSON as on the page', () => {
  const off = buildSite({ env: PROD, config: { alexaPublished: false } });
  for (const locale of Object.keys(LOCALES)) {
    const spans = spansOf(json(off, locale, 'alexa').blocks);
    assert.ok(!spans.some((s) => Object.values(ALEXA_SKILL_URLS).includes(s.href)), locale);
    assert.ok(!spans.some((s) => s.href?.startsWith('alexa-skill:')), locale);
  }
});

const BODY = `# Alles drin

Ein **fetter** und *schräger* Satz mit \`code\`, [Datenschutz](/datenschutz), [oben](#oben) und [Web](https://example.com).
Zweite Zeile.

## Oben {#oben}

1. Erstens
2. Zweitens
   - innen

> Zitat mit **Wort**

\`\`\`text
Zeile 1
Zeile 2
\`\`\`

| Du sagst | Passiert |
| --- | --- |
| Milch | **steht** drauf |

## Später {#spaeter since=9.0.0}

Kommt erst mit 9.0.0.

::: since 9.0.0
Block für 9.0.0.
:::

---

## Neu {since=1.1.0}

Seit 1.1.0.
`;

const fixture = (env) =>
  buildSite({ env, repo: { record: record(['1.0.0', '1.1.0']) }, files: { 'guides/de/alles.md': guide({ locale: 'de', slug: 'alles', title: 'Alles drin', body: BODY }) } });

test('a guide\'s blocks follow the contract; production leaves out what its page leaves out', () => {
  const prod = json(fixture(PROD), 'de', 'alles');
  assert.deepEqual(prod.blocks, [
    {
      type: 'paragraph',
      text: [
        { text: 'Ein ' },
        { text: 'fetter', strong: true },
        { text: ' und ' },
        { text: 'schräger', em: true },
        { text: ' Satz mit ' },
        { text: 'code', code: true },
        { text: ', ' },
        { text: 'Datenschutz', href: `${siteUrl}/datenschutz` },
        { text: ', ' },
        { text: 'oben', href: '#oben' },
        { text: ' und ' },
        { text: 'Web', href: 'https://example.com' },
        { text: '.\nZweite Zeile.' },
      ],
    },
    { type: 'heading', level: 2, id: 'oben', text: [{ text: 'Oben' }] },
    {
      type: 'list',
      ordered: true,
      items: [
        [{ type: 'paragraph', text: [{ text: 'Erstens' }] }],
        [{ type: 'paragraph', text: [{ text: 'Zweitens' }] }, { type: 'list', ordered: false, items: [[{ type: 'paragraph', text: [{ text: 'innen' }] }]] }],
      ],
    },
    { type: 'quote', blocks: [{ type: 'paragraph', text: [{ text: 'Zitat mit ' }, { text: 'Wort', strong: true }] }] },
    { type: 'code', text: 'Zeile 1\nZeile 2' },
    { type: 'table', header: [[{ text: 'Du sagst' }], [{ text: 'Passiert' }]], rows: [[[{ text: 'Milch' }], [{ text: 'steht', strong: true }, { text: ' drauf' }]]] },
    { type: 'heading', level: 2, id: null, text: [{ text: 'Neu' }] },
    { type: 'paragraph', text: [{ text: 'Ab App-Version 1.1.0', em: true }] },
    { type: 'paragraph', text: [{ text: 'Seit 1.1.0.' }] },
  ]);
});

test('a preview build shows unreleased content in the JSON as on its page, without the banners', () => {
  const preview = json(fixture({}), 'de', 'alles');
  const text = spansOf(preview.blocks).map((s) => s.text);
  assert.ok(text.includes('Später') && text.includes('Kommt erst mit 9.0.0.') && text.includes('Block für 9.0.0.'));
  assert.ok(!plain(spansOf(preview.blocks)).includes('noch nicht im Store'), 'no banner');
});

test('a draft guide has JSON in previews only; an unlisted one has JSON but no index entry', () => {
  const files = {
    'guides/de/entwurf.md': guide({ locale: 'de', slug: 'entwurf' }).replace('---\n\n', 'draft: true\n---\n\n'),
    'guides/de/versteckt.md': guide({ locale: 'de', slug: 'versteckt' }).replace('---\n\n', 'unlisted: true\n---\n\n'),
  };
  const prod = buildSite({ env: PROD, files });
  const preview = buildSite({ files });
  assert.ok(!has(prod, 'de', 'entwurf'));
  assert.ok(has(preview, 'de', 'entwurf'));
  assert.ok(has(prod, 'de', 'versteckt'));
  assert.ok(!json(prod, 'de', 'index').guides.some((g) => g.slug === 'versteckt'));
});

test('a guide slug the apps cannot open fails the build', () => {
  for (const slug of ['Siri', 'siri_shortcut', 'siri.v2']) {
    assert.throws(
      () => buildSite({ files: { [`guides/de/${slug}.md`]: guide({ locale: 'de', slug }) } }),
      new RegExp(`frontmatter field "slug" must be lowercase words joined by hyphens .*got "${slug.replace('.', '\\.')}"`),
    );
  }
});

test('a guide named index fails the build: its JSON would be the index', () => {
  assert.throws(() => buildSite({ files: { 'guides/de/index.md': guide({ locale: 'de', slug: 'index' }) } }), /must not be "index"/);
});
