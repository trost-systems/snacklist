import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, guide, hrefs, htmlRoutes, CONTENT_DIR, REPO_DIR } from './helpers.mjs';

const listed = (doc) => doc.querySelectorAll('main li').map((li) => ({ href: li.querySelector('a').getAttribute('href'), text: li.text }));

test('real content builds every route', () => {
  const { outDir } = buildSite();
  const routes = htmlRoutes(outDir);
  for (const route of ['/', '/de/anleitungen/siri-kurzbefehl', '/en/guides/siri-shortcut', '/de/anleitungen/alexa', '/en/guides/alexa', '/de/anleitungen', '/en/guides', '/impressum', '/en/imprint']) {
    assert.ok(routes.includes(route), `${route} is built`);
  }
});

test('each index lists only its own locale with title and description', () => {
  const { page } = buildSite();
  const de = listed(page('/de/anleitungen'));
  assert.deepEqual(de.map((g) => g.href), ['/de/anleitungen/widget', '/de/anleitungen/claude', '/de/anleitungen/alexa', '/de/anleitungen/siri-kurzbefehl']);
  assert.match(de[2].text, /Snacklist per Alexa: Skill einrichten/);
  assert.match(de[2].text, /Mit dem Snacklist-Skill für Alexa kannst du Sachen per Sprache auf deine Snacklist setzen/);
  assert.match(de[0].text, /Snacklist auf dem Home-Bildschirm: das Widget/);
  assert.match(de[1].text, /Snacklist mit Claude verbinden/);
  assert.match(de[3].text, /Snacklist per Siri: Kurzbefehl einrichten/);
  assert.match(de[3].text, /Mit einem Kurzbefehl setzt du per Siri Sachen auf deine Snacklist/);
  const en = listed(page('/en/guides'));
  assert.deepEqual(en.map((g) => g.href), ['/en/guides/claude', '/en/guides/widget', '/en/guides/alexa', '/en/guides/siri-shortcut']);
  assert.match(en[0].text, /Connect Snacklist to Claude/);
  assert.match(en[2].text, /Snacklist with Alexa: set up the skill/);
  assert.match(en[1].text, /Snacklist on your Home Screen: the widget/);
  assert.match(en[3].text, /Snacklist with Siri \(German only for now\)/);
  assert.match(en[3].text, /works in German only for now/);
});

test('an unlisted guide builds at its route but is not on the index, the sitemap or llms.txt (job 415)', () => {
  const { page, outDir } = buildSite({
    files: { 'guides/de/nur-per-link.md': guide({ locale: 'de', slug: 'nur-per-link', title: 'Nur per Link', description: 'Nur über einen Link erreichbar.' }).replace('\n---\n', '\nunlisted: true\n---\n') },
  });
  assert.equal(page('/de/anleitungen/nur-per-link').querySelector('h1').text, 'Nur per Link');
  assert.ok(!hrefs(page('/de/anleitungen')).includes('/de/anleitungen/nur-per-link'));
  assert.match(page('/de/anleitungen/nur-per-link').querySelector('head').innerHTML, /name="robots" content="noindex"/);
  for (const f of ['sitemap.xml', 'llms.txt']) assert.ok(!readFileSync(join(outDir, f), 'utf8').includes('nur-per-link'), f);
  const real = buildSite();
  assert.ok(!hrefs(real.page('/en/guides')).includes('/en/guides/ai-assistants-plan'));
  assert.equal(real.page('/en/guides/ai-assistants-plan').querySelector('h1').text, 'AI assistants and your Snacklist plan');
});

test('a new guide file appears at its route and on its index', () => {
  const { page } = buildSite({
    files: { 'guides/de/einkauf-teilen.md': guide({ locale: 'de', slug: 'einkauf-teilen', title: 'Einkauf teilen', description: 'So teilst du die Liste.' }) },
  });
  assert.equal(page('/de/anleitungen/einkauf-teilen').querySelector('h1').text, 'Einkauf teilen');
  const de = listed(page('/de/anleitungen'));
  assert.deepEqual(de.map((g) => g.href), ['/de/anleitungen/einkauf-teilen', '/de/anleitungen/widget', '/de/anleitungen/claude', '/de/anleitungen/alexa', '/de/anleitungen/siri-kurzbefehl'], 'sorted by title');
  assert.match(de[0].text, /So teilst du die Liste\./);
  assert.ok(!hrefs(page('/en/guides')).includes('/de/anleitungen/einkauf-teilen'));
});

for (const field of ['description', 'translation_key', 'updated', 'title']) {
  test(`a guide missing ${field} fails naming file and field`, () => {
    assert.throws(
      () => buildSite({ files: { 'guides/en/broken.md': guide({ locale: 'en', slug: 'broken', omit: [field] }) } }),
      (e) => e.message.includes('guides/en/broken.md') && e.message.includes(`"${field}"`),
    );
  });
}

test('a guide whose locale or slug disagrees with its location fails', () => {
  assert.throws(() => buildSite({ files: { 'guides/en/x.md': guide({ locale: 'de', slug: 'x' }) } }), /guides\/en\/x\.md.*"locale"/);
  assert.throws(() => buildSite({ files: { 'guides/en/x.md': guide({ locale: 'en', slug: 'y' }) } }), /guides\/en\/x\.md.*"slug"/);
});

test('an invalid updated date fails', () => {
  const text = guide({ locale: 'en', slug: 'x' }).replace('2026-10-01', 'yesterday');
  assert.throws(() => buildSite({ files: { 'guides/en/x.md': text } }), /guides\/en\/x\.md.*"updated"/);
});

test('two files with the same route fail', () => {
  const clash = '---\ntitle: X\ndescription: Y\nlocale: de\npath: /de/anleitungen/siri-kurzbefehl\ntranslation_key: clash\nupdated: 2026-10-01\n---\n\n# X\n';
  assert.throws(() => buildSite({ files: { 'legal/clash.md': clash } }), /route \/de\/anleitungen\/siri-kurzbefehl/);
});

test('the EN stub says German only and links to the German guide', () => {
  const doc = buildSite().page('/en/guides/siri-shortcut');
  assert.match(doc.querySelector('main').text, /only works in German/);
  assert.ok(hrefs(doc, 'main a').includes('/de/anleitungen/siri-kurzbefehl'));
});

test('the EN Alexa guide is a full English guide that links the German one', () => {
  const doc = buildSite().page('/en/guides/alexa');
  assert.match(doc.querySelector('main').text, /Alexa, ask Snacklist to add milk and eggs/);
  assert.ok(hrefs(doc, 'main a').includes('/de/anleitungen/alexa'));
  assert.ok(hrefs(doc, 'main a').includes('#reach-snacklist'));
});

test('the dialogue renders as separate lines and other paragraphs get no line break', () => {
  const doc = buildSite().page('/de/anleitungen/siri-kurzbefehl');
  const dialogues = doc.querySelectorAll('main blockquote p').filter((p) => /^Du:/.test(p.text));
  assert.equal(dialogues.length, 2, 'the Shortcut and the native Siri dialogue');
  for (const dialogue of dialogues) assert.equal(dialogue.querySelectorAll('br').length, 3);
  const others = doc.querySelectorAll('main p').filter((p) => !dialogues.includes(p) && p.querySelector('br'));
  assert.deepEqual(others.map((p) => p.text), []);
});

const TOKEN = /fgp_[A-Za-z0-9_-]{43}/;
const filesUnder = (dir) => readdirSync(dir, { recursive: true, withFileTypes: true }).filter((d) => d.isFile()).map((d) => join(d.parentPath ?? d.path, d.name));

test('no real access token in content or build output', () => {
  const { outDir } = buildSite();
  for (const file of [...filesUnder(CONTENT_DIR), ...filesUnder(outDir)]) {
    assert.doesNotMatch(readFileSync(file, 'latin1'), TOKEN, file);
  }
  assert.match(`fgp_${'a'.repeat(43)}`, TOKEN, 'the pattern detects a token-shaped value');
});

test('the imprint pair shows the VAT ID (§ 5 Abs. 1 Nr. 6 DDG) under the personal name, no IAKUVO', () => {
  const { page } = buildSite();
  const de = page('/impressum').querySelector('main').text;
  assert.match(de, /Umsatzsteuer-Identifikationsnummer gemäß § 27a UStG: DE369514299/);
  assert.match(de, /Peter Trost/);
  const en = page('/en/imprint').querySelector('main').text;
  assert.match(en, /VAT ID pursuant to § 27a UStG: DE369514299/);
  for (const text of [de, en]) assert.doesNotMatch(text, /IAKUVO/);
});

test('every invocation phrase in the Alexa guides matches a sample of that language\'s skill model', () => {
  const words = (s) => s.toLowerCase().replace(/[,.!?]/g, '').split(/\s+/).filter(Boolean).join(' ');
  const samplesOf = (locale) =>
    JSON.parse(readFileSync(join(REPO_DIR, `alexa/skill-package/interactionModels/custom/${locale}.json`), 'utf8'))
      .interactionModel.languageModel.intents.flatMap((i) => i.samples)
      .map((sample) => new RegExp(`^${words(sample).split(' ').map((w) => (w.startsWith('{') ? '.+' : w)).join(' ')}$`));
  const guides = [
    ['de', 'de-DE', /Alexa, (?:sag|frag) Snacklist, ([a-zäöüß][^“”"|\n]*)/gi],
    ['en', 'en-US', /Alexa, (?:ask|tell) Snacklist (?:to )?([a-z][^“”"|\n]*)/gi],
  ];
  for (const [locale, model, pattern] of guides) {
    const samples = samplesOf(model);
    const phrases = [...readFileSync(join(CONTENT_DIR, 'guides', locale, 'alexa.md'), 'utf8').matchAll(pattern)].map((m) => m[1].trim());
    assert.ok(phrases.length >= 5, `${locale}: found ${phrases.length} phrases`);
    for (const phrase of phrases) assert.ok(samples.some((s) => s.test(words(phrase))), `${locale}: no sample matches „${phrase}“`);
  }
});

test('the Bring comparison says free only with LK1\'s Premium qualifier; the other free claims are Bring!\'s own, quoted (job 495)', () => {
  const doc = buildSite().page('/de/einkaufsliste-vergleich-bring');
  for (const el of doc.querySelectorAll('script:not([type="application/ld+json"])')) el.remove();
  const html = doc.toString();
  assert.match(html, /Kostenlos nutzbar, ohne Werbung\. Premium ist optional\./);
  const rest = html
    .replace('Kostenlos nutzbar, ohne Werbung. Premium ist optional.', '')
    .replace(/„[^“]*“/g, '');
  const claim = /.{0,60}(kostenlos|gratis|umsonst|\bfree\b).{0,40}/i.exec(rest);
  assert.equal(claim, null, `a free claim without LK1's qualifier: ${claim?.[0]}`);
});
