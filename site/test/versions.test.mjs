import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { buildSite, guide, legal, alternates, hrefs, htmlRoutes, meta, record, serve, tempDir, REAL_PUBSPEC, REAL_RECORD, SITE_DIR } from './helpers.mjs';
import { RecordError, parseRecord } from '../releases.mjs';

const PROD = { VERCEL_ENV: 'production' };
const NEU = '/de/anleitungen/neu';
const NEW = '/en/guides/new';
const BANNER_DE = 'Ab Version 1.4.0, noch nicht im Store';
const BANNER_EN = 'From version 1.4.0, not in the stores yet';
const STORES_1_4 = { record: record(['1.0.0', '1.4.0']) };
const html = (outDir, route) => readFileSync(join(outDir, `${route.slice(1)}.html`), 'utf8');
const main = (doc) => doc.querySelector('main').innerHTML;

// A de/en pair where only the German guide waits for 1.4.0.
const pair = (since = '1.4.0', extra = {}) => ({
  'guides/de/neu.md': guide({ locale: 'de', slug: 'neu', key: 'neu', title: 'Neu', since, ...extra }),
  'guides/en/new.md': guide({ locale: 'en', slug: 'new', key: 'neu', title: 'New' }),
});

test('the live version is the newest public release, else app/pubspec.yaml', () => {
  const pubspecVersion = /^version:\s*(\d+\.\d+\.\d+)\+/m.exec(REAL_PUBSPEC)[1];
  assert.deepEqual(buildSite().live, { live: pubspecVersion, firstPublic: null, source: 'app/pubspec.yaml, no public release yet' });
  assert.equal(pubspecVersion, '0.1.0', 'today no public release exists and the app is 0.1.0');
  assert.deepEqual(buildSite({ repo: { pubspec: 'name: x\nversion: 2.3.4+17\n' } }).live.live, '2.3.4');
  assert.deepEqual(buildSite({ repo: { record: record(['1.0.0', '1.2.0', '1.10.0']), pubspec: 'version: 9.9.9+1\n' } }).live, {
    live: '1.10.0',
    firstPublic: '1.0.0',
    source: 'public release record',
  });
});

test('the CLI logs the live version and reports a bad record as a build failure', () => {
  const root = tempDir();
  const site = join(root, 'site');
  mkdirSync(site);
  for (const f of ['build.mjs', 'releases.mjs', 'landing.mjs', 'config.json', 'package.json', 'public', 'content']) cpSync(join(SITE_DIR, f), join(site, f), { recursive: true });
  symlinkSync(join(SITE_DIR, 'node_modules'), join(site, 'node_modules'));
  mkdirSync(join(root, 'releases'));
  mkdirSync(join(root, 'app'));
  writeFileSync(join(root, 'app/pubspec.yaml'), REAL_PUBSPEC);
  const run = () => spawnSync(process.execPath, [join(site, 'build.mjs')], { encoding: 'utf8', env: { ...process.env, VERCEL_ENV: '' } });

  writeFileSync(join(root, 'releases/releases.json'), REAL_RECORD);
  let out = run();
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^live version: 0\.1\.0 \(from app\/pubspec\.yaml, no public release yet\)\nbuilt \d+ pages into dist\/\n$/);

  writeFileSync(join(root, 'releases/releases.json'), record(['1.0.0', '1.4.0']));
  assert.match(run().stdout, /^live version: 1\.4\.0 \(from public release record\)\n/);

  writeFileSync(join(root, 'releases/releases.json'), '{"project": {}}');
  out = run();
  assert.equal(out.status, 1);
  assert.equal(out.stderr, 'build failed: releases/releases.json: $.identities: missing\n', 'one line, no stack trace');
});

test('production leaves out a guide the stores do not have yet, like a draft', async () => {
  const { outDir, page, routes } = buildSite({ files: pair(), env: PROD });
  assert.ok(!htmlRoutes(outDir).includes(NEU) && !routes.includes(NEU), 'no page');
  assert.ok(!hrefs(page('/de/anleitungen')).includes(NEU), 'not on the index');
  const en = page(NEW);
  assert.deepEqual(alternates(en), { en: `https://hummlist.com${NEW}`, 'x-default': `https://hummlist.com${NEW}` });
  assert.equal(en.querySelector('header nav.lang a').getAttribute('href'), '/de/anleitungen', 'the switch falls back to the index');
  for (const route of htmlRoutes(outDir)) assert.doesNotMatch(readFileSync(join(outDir, route === '/' ? 'index.html' : `${route.slice(1)}.html`), 'utf8'), /noch nicht im Store|not in the stores yet/, route);
  const res = await serve(outDir, [NEU, NEW]);
  assert.equal(res[NEU].status, 404);
  assert.equal(res[NEW].status, 200);
});

test('preview shows a guide the stores do not have yet with banner, comment and noindex', async () => {
  for (const env of [{}, { VERCEL_ENV: 'preview' }]) {
    const { outDir, page } = buildSite({ files: pair(), env });
    const doc = page(NEU);
    assert.equal(doc.querySelector('.draft-banner').text, BANNER_DE);
    assert.equal(doc.querySelector('.draft-banner').getAttribute('role'), 'note');
    assert.ok(html(outDir, NEU).includes(`<!-- ${BANNER_DE} -->`), 'comment');
    assert.equal(meta(doc, 'robots'), 'noindex');
    assert.ok(hrefs(page('/de/anleitungen')).includes(NEU), 'on the index');
    assert.equal(page(NEW).querySelector('header nav.lang a').getAttribute('href'), NEU);
    assert.equal(doc.querySelector('.since-note'), null, 'no note before any public release');
    assert.equal(meta(page(NEW), 'robots'), undefined, 'the released translation is indexable');
    assert.equal((await serve(outDir, [NEU]))[NEU].status, 200);
  }
});

test('a draft that also waits for a version carries both notices and one noindex', () => {
  const files = pair();
  files['guides/de/neu.md'] = files['guides/de/neu.md'].replace('since:', 'draft: true\nsince:');
  const { outDir, page } = buildSite({ files });
  assert.deepEqual(page(NEU).querySelectorAll('.draft-banner').map((b) => b.text), ['ENTWURF: Freigabe durch Peter', BANNER_DE]);
  assert.ok(html(outDir, NEU).includes(`<!-- ENTWURF: Freigabe durch Peter -->\n<!-- ${BANNER_DE} -->\n<meta name="robots" content="noindex">\n`));
  assert.equal(html(outDir, NEU).match(/<meta name="robots"/g).length, 1);
});

test('a released guide shows without banner; the note only when newer than the first public release', () => {
  const newer = buildSite({ files: pair('1.4.0'), env: PROD, repo: STORES_1_4 }).page(NEU);
  assert.equal(newer.querySelector('.draft-banner'), null);
  assert.equal(meta(newer, 'robots'), undefined);
  const note = newer.querySelector('h1').nextElementSibling;
  assert.equal(note.classNames, 'since-note');
  assert.equal(note.text, 'Ab App-Version 1.4.0');

  const dayOne = buildSite({ files: pair('1.0.0'), env: PROD, repo: STORES_1_4 }).page(NEU);
  assert.equal(dayOne.querySelector('.since-note'), null, 'since the first public release: no note');

  const beforeLaunch = buildSite({ files: pair('0.1.0'), env: PROD }).page(NEU);
  assert.equal(beforeLaunch.querySelector('.since-note'), null, 'no public release yet: no note');
  assert.equal(beforeLaunch.querySelector('.draft-banner'), null);
});

const SECTIONS = `# Neu

Einleitung.

## Neue Funktion {#neue-funktion since=1.4.0}

Geheimer Abschnitt.

### Unterpunkt

Geheimer Unterpunkt.

## Ohne ID {since=1.4.0}

Auch geheim.

## Andersrum {since=1.4.0 #andersrum}

Ebenfalls geheim.

## Alt {Hinweis}

Alter Text.
`;

test('a section waiting for a version: production removes it, preview marks it', () => {
  const files = { 'guides/de/neu.md': guide({ locale: 'de', slug: 'neu', body: SECTIONS }) };
  const prod = main(buildSite({ files, env: PROD }).page(NEU));
  assert.doesNotMatch(prod, /geheim|Geheim|Neue Funktion|Ohne ID|Andersrum|Unterpunkt/);
  assert.match(prod, /<h2>Alt \{Hinweis\}<\/h2>\n<p>Alter Text\.<\/p>/, 'other braces stay text');

  const preview = buildSite({ files }).page(NEU);
  const h2 = preview.querySelector('#neue-funktion');
  assert.equal(h2.text, 'Neue Funktion');
  assert.equal(h2.nextElementSibling.toString(), `<p class="draft-banner" role="note"><strong>${BANNER_DE}</strong></p>`);
  assert.match(main(preview), /Geheimer Unterpunkt/);
  assert.equal(preview.querySelector('#andersrum').text, 'Andersrum');
  assert.equal(preview.querySelectorAll('.draft-banner').length, 3);
  assert.equal(meta(preview, 'robots'), undefined, 'a page with a versioned section stays indexable');

  const en = buildSite({ files: { 'guides/en/new.md': guide({ locale: 'en', slug: 'new', body: '# New\n\n## Later {since=1.4.0}\n\nText.\n' }) } }).page(NEW);
  assert.equal(en.querySelector('.draft-banner').text, BANNER_EN);

  const released = buildSite({ files, env: PROD, repo: STORES_1_4 }).page(NEU);
  assert.equal(released.querySelector('.draft-banner'), null);
  assert.equal(released.querySelector('#neue-funktion').nextElementSibling.toString(), '<p class="since-note">Ab App-Version 1.4.0</p>');
  assert.match(main(released), /Geheimer Unterpunkt/);
});

const BLOCKS = `# Neu

1. Schritt eins
2. Schritt zwei

   ::: since 1.4.0
   Geheim im Listenpunkt.
   :::

3. Schritt drei

::: since 1.4.0
> Geheimes Zitat

- geheime Liste
:::

Danach.

~~~text
::: since 1.4.0
Tilde
:::
~~~

\`\`\`text
::: since 1.4.0
Backtick
:::
\`\`\`
`;

test('a block waiting for a version: production removes it, preview wraps it with the banner', () => {
  const files = { 'guides/de/neu.md': guide({ locale: 'de', slug: 'neu', body: BLOCKS }) };
  const prod = main(buildSite({ files, env: PROD }).page(NEU));
  assert.doesNotMatch(prod, /Geheim|geheim|since-block/);
  assert.match(prod, /Schritt drei/);
  assert.match(prod, /Danach\./);
  for (const word of ['Tilde', 'Backtick']) assert.ok(prod.includes(`<pre tabindex="0"><code class="language-text">::: since 1.4.0\n${word}\n:::\n</code></pre>`), `${word} fence stays literal`);

  const preview = buildSite({ files }).page(NEU);
  const blocks = preview.querySelectorAll('.since-block');
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].parentNode.tagName, 'LI', 'the block inside the list item stays there');
  for (const block of blocks) assert.equal(block.firstElementChild.toString(), `<p class="draft-banner" role="note"><strong>${BANNER_DE}</strong></p>`);
  assert.match(blocks[0].text, /Geheim im Listenpunkt/);
  assert.ok(blocks[1].querySelector('blockquote') && blocks[1].querySelector('ul'));
  assert.equal(preview.querySelectorAll('pre').length, 2);
});

test('a released block leaves no markup but the note', () => {
  const body = (since) =>
    since === undefined
      ? '# Neu\n\n1. Eins\n\n   Im Listenpunkt.\n\n> Zitat\n\nDanach.\n'
      : `# Neu\n\n1. Eins\n\n   ::: since ${since}\n   Im Listenpunkt.\n   :::\n\n::: since ${since}\n> Zitat\n:::\n\nDanach.\n`;
  const render = (text) => main(buildSite({ files: { 'guides/de/neu.md': guide({ locale: 'de', slug: 'neu', body: text }) }, env: PROD, repo: STORES_1_4 }).page(NEU));
  assert.equal(render(body('1.0.0')), render(body()), 'since the first public release: same as without markers');

  const released = buildSite({ files: { 'guides/de/neu.md': guide({ locale: 'de', slug: 'neu', body: BLOCKS }) }, env: PROD, repo: STORES_1_4 }).page(NEU);
  assert.equal(released.querySelector('.since-block'), null);
  const notes = released.querySelectorAll('.since-note');
  assert.equal(notes.length, 2);
  assert.equal(notes[0].parentNode.tagName, 'LI');
  assert.equal(notes[0].text, 'Ab App-Version 1.4.0');
  assert.match(main(released), /Geheim im Listenpunkt/);
});

test('a version that is not MAJOR.MINOR.PATCH fails, naming the file and the value', () => {
  const at = (body, since) => ({ 'guides/de/x.md': guide({ locale: 'de', slug: 'x', body, since }) });
  assert.throws(() => buildSite({ files: at('# X\n', '1.4') }), /guides\/de\/x\.md: frontmatter field "since" must be a version MAJOR\.MINOR\.PATCH, got 1\.4$/);
  assert.throws(() => buildSite({ files: at('# X\n', 'v1.4.0') }), /guides\/de\/x\.md: frontmatter field "since" must be a version MAJOR\.MINOR\.PATCH, got "v1\.4\.0"/);
  assert.throws(() => buildSite({ files: at('# X\n\n## Y {since=1.4}\n') }), /guides\/de\/x\.md: heading attribute "since" must be a version MAJOR\.MINOR\.PATCH, got "1\.4"/);
  assert.throws(() => buildSite({ files: at('# X\n\n::: since 1.4.0-beta\nY\n:::\n') }), /guides\/de\/x\.md: block "since" must be a version MAJOR\.MINOR\.PATCH, got "1\.4\.0-beta"/);
});

test('since is for guides only: legal texts and indexes are not versioned', () => {
  const page = legal({ locale: 'de', path: '/x', key: 'x' });
  const reason = /legal\/x\.md: .*"since" is only allowed on guides \(legal texts and indexes are not versioned\)/;
  assert.throws(() => buildSite({ files: { 'legal/x.md': page.replace('updated:', 'since: 1.4.0\nupdated:') } }), reason);
  assert.throws(() => buildSite({ files: { 'legal/x.md': page.replace('Text.', '## Neu {since=1.4.0}\n\nText.') } }), reason);
  assert.throws(() => buildSite({ files: { 'legal/x.md': page.replace('Text.', '::: since 1.4.0\nText.\n:::') } }), reason);
  const index = readFileSync(join(SITE_DIR, 'content/indexes/de.md'), 'utf8');
  assert.throws(() => buildSite({ files: { 'indexes/de.md': index.replace('locale:', 'since: 1.4.0\nlocale:') } }), /indexes\/de\.md: frontmatter field "since" is only allowed on guides/);
});

test('an unclosed or misspelled block fails', () => {
  const at = (body) => ({ 'guides/de/x.md': guide({ locale: 'de', slug: 'x', body }) });
  assert.throws(() => buildSite({ files: at('# X\n\n::: since 1.4.0\nY\n') }), /guides\/de\/x\.md: "::: since 1\.4\.0" is not closed; end it with a line ":::"/);
  assert.throws(() => buildSite({ files: at('# X\n\n1. Eins\n\n   ::: since 1.4.0\n   Y\n\nZ\n') }), /is not closed/);
  assert.throws(() => buildSite({ files: at('# X\n\n::: sinse 1.4.0\nY\n:::\n') }), /guides\/de\/x\.md: "::: sinse 1\.4\.0" is not a block this site knows; a versioned block is "::: since 1\.4\.0" up to a line ":::"/);
});

test('a ":::" line in a fence inside a block fails instead of ending the block; more colons work', () => {
  const at = (marker) => ({
    'guides/de/x.md': guide({ locale: 'de', slug: 'x', body: `# X\n\n${marker} since 9.0.0\n\nGeheim.\n\n~~~text\n:::\n~~~\n\nAuch geheim.\n\n${marker}\n\nEnde.\n` }),
  });
  assert.throws(() => buildSite({ files: at(':::'), env: PROD }), /guides\/de\/x\.md: a code fence inside "::: since 9\.0\.0" holds a ":::" line, which ends the block; open and close the block with more colons/);
  const prod = main(buildSite({ files: at('::::'), env: PROD }).page('/de/anleitungen/x'));
  assert.doesNotMatch(prod, /geheim|Geheim|<pre>/);
  assert.match(prod, /Ende\./);
});

test('the build needs the record and, before a public release, app/pubspec.yaml', () => {
  const outside = /: the site build needs releases\/releases\.json and app\/pubspec\.yaml from outside site\/ \(on Vercel the project setting "Include files outside the root directory in the Build Step" must stay on\)/;
  assert.throws(() => buildSite({ repo: { record: null } }), (e) => /cannot read \S+\/releases\/releases\.json \(ENOENT\)/.test(e.message) && outside.test(e.message));
  assert.throws(() => buildSite({ repo: { pubspec: null } }), (e) => /cannot read \S+\/app\/pubspec\.yaml \(ENOENT\)/.test(e.message) && outside.test(e.message));
  assert.throws(() => buildSite({ repo: { pubspec: 'name: x\n' } }), /app\/pubspec\.yaml: needs a line "version: MAJOR\.MINOR\.PATCH\+BUILD", got null/);
  assert.equal(buildSite({ repo: { record: record(['1.0.0']), pubspec: null } }).live.live, '1.0.0', 'no pubspec needed after a public release');
  assert.throws(() => buildSite({ repo: { record: REAL_RECORD.replace('"releases": []', '"releases": {}') } }), (e) => e instanceof RecordError && e.message === 'releases/releases.json: releases: must be an array');
});

test('a visible page linking to a guide production leaves out fails production, not preview', () => {
  const files = {
    ...pair(),
    'guides/de/alt.md': guide({ locale: 'de', slug: 'alt', body: `# Alt\n\n[Neu](${NEU})\n` }),
  };
  assert.throws(() => buildSite({ files, env: PROD }), /de\/anleitungen\/alt\.html: broken internal link \/de\/anleitungen\/neu/);
  assert.ok(htmlRoutes(buildSite({ files }).outDir).includes('/de/anleitungen/alt'));
  assert.ok(htmlRoutes(buildSite({ files, env: PROD, repo: STORES_1_4 }).outDir).includes(NEU), 'released: link works');
});

test('the real release record is valid and the validator rejects bad ones', () => {
  assert.deepEqual(parseRecord(REAL_RECORD).releases, []);
  assert.equal(parseRecord(record(['1.0.0', '1.4.0'])).releases.length, 2, 'the fixture records are valid');
  const rejects = (patch, message) => assert.throws(() => parseRecord(record(['1.0.0', '1.4.0'], patch)), (e) => e instanceof RecordError && message.test(e.message));
  rejects((d) => ({ ...d, extra: 1 }), /\$\.extra: unknown field/);
  rejects((d) => (d.releases[1].day += 1, d), /releases\[1\]\.day: must be \d+ \(days from project\.day_zero to date\)/);
  rejects((d) => (d.releases[1].version = '1.0.0', d), /releases\[1\]\.version: 1\.0\.0 must be above 1\.0\.0/);
  rejects((d) => (d.releases.reverse(), d), /releases\[0\]\.previous_sha|releases\[1\]\.version: 1\.0\.0 must be above 1\.4\.0/);
  rejects((d) => (d.releases[1].previous_sha = 'f'.repeat(40), d), /releases\[1\]\.previous_sha: must be 1\.0\.0's sha/);
  rejects((d) => (d.identities[2].emails.push(d.identities[0].emails[0]), d), /identities\[2\]\.emails\[1\]: peter@petertrost\.com is also listed under identities\[0\]/);
});

test('a note is not repeated: none under a section or block no newer than its guide, none on unreleased content', () => {
  const body = `# Uhr\n\nText.\n\n## Einrichten {since=1.2.0}\n\nSchritt.\n\n::: since 1.2.0\nGleich alt.\n:::\n\n## Später {since=1.3.0}\n\nNeuer.\n\n## Bald {since=1.4.0}\n\nGeheim.\n`;
  const files = { 'guides/de/uhr.md': guide({ locale: 'de', slug: 'uhr', since: '1.2.0', body }) };
  const repo = { record: record(['1.0.0', '1.3.0']) };
  const notes = (doc) => doc.querySelectorAll('.since-note').map((p) => p.text);
  const prod = buildSite({ files, env: PROD, repo }).page('/de/anleitungen/uhr');
  assert.deepEqual(notes(prod), ['Ab App-Version 1.2.0', 'Ab App-Version 1.3.0'], 'the guide note, then only the newer section');
  const preview = buildSite({ files, repo }).page('/de/anleitungen/uhr');
  assert.deepEqual(notes(preview), ['Ab App-Version 1.2.0', 'Ab App-Version 1.3.0'], 'the unreleased section has the banner, no note');
  assert.deepEqual(preview.querySelectorAll('.draft-banner').map((p) => p.text), [BANNER_DE]);
});

test('a quote or list whose only content production leaves out disappears with it', () => {
  const body = `# X\n\nText.\n\n> ::: since 9.0.0\n> Geheim.\n> :::\n\n- ::: since 9.0.0\n  Auch geheim.\n  :::\n\nEnde.\n`;
  const files = { 'guides/de/x.md': guide({ locale: 'de', slug: 'x', body }) };
  const prod = main(buildSite({ files, env: PROD }).page('/de/anleitungen/x'));
  assert.doesNotMatch(prod, /blockquote|<ul|<li|geheim|Geheim/);
  assert.match(prod, /Ende\./);
  const preview = main(buildSite({ files }).page('/de/anleitungen/x'));
  assert.match(preview, /<blockquote>[\s\S]*Geheim[\s\S]*<\/blockquote>/);
  assert.match(preview, /<li>[\s\S]*Auch geheim[\s\S]*<\/li>/);
});
