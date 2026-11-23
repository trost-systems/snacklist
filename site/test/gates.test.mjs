import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, guide, legal, record, REAL_FLAGS } from './helpers.mjs';

const PROD = { VERCEL_ENV: 'production' };
// Every `since` is out, so only the hold decides what renders.
const ALL_VERSIONS_LIVE = record(['9.9.9']);
const flags = (released) => {
  const data = JSON.parse(REAL_FLAGS);
  data.holds['native-siri'].released = released;
  return JSON.stringify(data);
};

// Claims only native Siri (App Intents, no Shortcut) makes true (Legal N-80).
const NATIVE_SIRI_WORDING = [
  'ohne eigenen Kurzbefehl',
  'Siri kennt Snacklist',
  'brauchst du keinen Kurzbefehl mehr',
  'Siri-Sätze anzeigen',
  'Füge etwas zu Snacklist hinzu',
  'Etwas auf Snacklist setzen',
  'with no shortcut of your own',
  'Siri knows Snacklist',
  "you don't need a Shortcut",
  'Show Siri phrases',
  'Add to Snacklist',
];

// Everything a person or an agent can read: pages, Markdown twins, llms*.txt, sitemap, JSON-LD.
const siteText = (outDir) =>
  readdirSync(outDir, { recursive: true })
    .filter((f) => /\.(html|md|txt|xml|json)$/.test(f))
    .map((f) => [f, readFileSync(join(outDir, f), 'utf8')]);

const found = (outDir) =>
  siteText(outDir).flatMap(([file, text]) => NATIVE_SIRI_WORDING.filter((w) => text.includes(w)).map((w) => `${file}: ${w}`));

test('no native-Siri wording renders anywhere while the native-siri hold is not released', () => {
  const { outDir } = buildSite({ env: PROD, repo: { record: ALL_VERSIONS_LIVE, flags: flags(false) } });
  assert.deepEqual(found(outDir), []);
});

test('the same wording renders once native-siri is released, so the list above matches the real text', () => {
  const { outDir } = buildSite({ env: PROD, repo: { record: ALL_VERSIONS_LIVE, flags: flags(true) } });
  const files = new Set(found(outDir).map((hit) => hit.split(':')[0]));
  for (const file of ['support.html', 'en/support.html', 'de/anleitungen/siri-kurzbefehl.html', 'en/guides/siri-shortcut.html']) {
    assert.ok(files.has(file), `${file} shows native Siri once released`);
  }
});

test('the help pages answer the Siri question with the Shortcut until native-siri is released, then with native Siri', () => {
  const answer = (site, route) => site.page(route).querySelector('main').innerHTML;
  const held = buildSite({ env: PROD, repo: { flags: flags(false) } });
  const live = buildSite({ env: PROD, repo: { flags: flags(true) } });
  assert.match(answer(held, '/support'), /Kurzbefehl, den du einmal selbst/);
  assert.match(answer(held, '/en/support'), /Shortcut you set up once yourself/);
  assert.doesNotMatch(answer(live, '/support'), /Kurzbefehl, den du einmal selbst/);
  assert.match(answer(live, '/support'), /ohne eigenen Kurzbefehl/);
  assert.match(answer(live, '/en/support'), /with no shortcut of your own/);
  for (const out of [held, live]) assert.doesNotMatch(answer(out, '/support'), /since-block|draft-banner/);
});

const GATED = `# Seite\n\nImmer.\n\n::: once native-siri\nNachher.\n:::\n\n::: until native-siri\nVorher.\n:::\n\n## Abschnitt {#abschnitt once=native-siri}\n\nNachher-Abschnitt.\n\n## Weiter\n\nEnde.\n`;
const gatedPage = (repo, env) =>
  buildSite({ env, repo, files: { 'legal/gated.md': legal({ locale: 'de', path: '/gated', key: 'gated', body: GATED }) } }).page('/gated').querySelector('main').innerHTML;

test('production renders only the side of a hold gate that is current, without a trace', () => {
  const held = gatedPage({ flags: flags(false) }, PROD);
  assert.match(held, /Vorher/);
  assert.doesNotMatch(held, /Nachher|abschnitt|since-block|draft-banner/);
  assert.match(held, /Ende/);
  const live = gatedPage({ flags: flags(true) }, PROD);
  assert.match(live, /Nachher\./);
  assert.match(live, /Nachher-Abschnitt/);
  assert.doesNotMatch(live, /Vorher|since-block|draft-banner/);
});

test('preview shows both sides of a hold gate, the one not current with a banner', () => {
  const held = gatedPage({ flags: flags(false) }, {});
  assert.match(held, /Vorher/);
  assert.match(held, /<div class="since-block">\n<p class="draft-banner" role="note"><strong>Erst wenn native-siri freigegeben ist, noch nicht live<\/strong><\/p>\n<p>Nachher\./);
  assert.match(held, /id="abschnitt"[^]*Erst wenn native-siri freigegeben ist[^]*Nachher-Abschnitt/);
  const live = gatedPage({ flags: flags(true) }, {});
  assert.match(live, /<div class="since-block">\n<p class="draft-banner" role="note"><strong>Nur bis native-siri freigegeben ist<\/strong><\/p>\n<p>Vorher/);
});

test('a gate on a hold that releases/flags.json does not have fails the build', () => {
  for (const body of ['# T\n\n::: once native-sirri\nX.\n:::\n', '# T\n\n## A {once=nope}\n\nX.\n', '# T\n\n::: until\nX.\n:::\n']) {
    assert.throws(
      () => buildSite({ files: { 'guides/de/g.md': guide({ locale: 'de', slug: 'g', body }) } }),
      /names the hold "[^"]*", but releases\/flags\.json has only/,
    );
  }
});

test('the Claude guides say AI access needs Premium only once integration-lock is released', () => {
  const lock = (released) => {
    const data = JSON.parse(REAL_FLAGS);
    data.holds['integration-lock'].released = released;
    return JSON.stringify(data);
  };
  const guides = [['/de/anleitungen/claude', /braucht Snacklist Premium/], ['/en/guides/claude', /needs Snacklist Premium/]];
  const off = buildSite({ env: PROD, repo: { flags: lock(false) } });
  const on = buildSite({ env: PROD, repo: { flags: lock(true) } });
  for (const [route, premium] of guides) {
    assert.doesNotMatch(off.page(route).querySelector('main').innerHTML, premium);
    assert.match(on.page(route).querySelector('main').innerHTML, premium);
  }
});

test('the privacy policies describe push notifications and Firebase Cloud Messaging only once push-notifications is released', () => {
  const push = (released) => {
    const data = JSON.parse(REAL_FLAGS);
    data.holds['push-notifications'].released = released;
    return JSON.stringify(data);
  };
  const pages = [['/datenschutz', 'mitteilungen'], ['/en/privacy', 'notifications']];
  const off = buildSite({ env: PROD, repo: { flags: push(false) } });
  const on = buildSite({ env: PROD, repo: { flags: push(true) } });
  for (const [route, anchor] of pages) {
    assert.doesNotMatch(off.page(route).querySelector('main').innerHTML, /Firebase Cloud Messaging/);
    assert.equal(off.page(route).querySelector(`#${anchor}`), null);
    const main = on.page(route).querySelector('main').innerHTML;
    assert.equal((main.match(/Firebase Cloud Messaging/g) ?? []).length, 4);
    assert.notEqual(on.page(route).querySelector(`#${anchor}`), null);
  }
});

test("the privacy policies' 24 hours are the push function's longest ttl_seconds", () => {
  const repo = new URL('../../', import.meta.url);
  const handler = readFileSync(new URL('supabase/functions/push/handler.ts', repo), 'utf8');
  assert.match(handler, /ttl_seconds: z\.int\(\)\.min\(60\)\.max\(86400\)/);
  const de = readFileSync(new URL('site/content/legal/datenschutz.md', repo), 'utf8');
  const en = readFileSync(new URL('site/content/legal/privacy.md', repo), 'utf8');
  assert.match(de, /verfällt sie nach höchstens 24 Stunden/);
  assert.match(en, /it expires after at most 24 hours/);
});

test('job 397: the privacy text follows unified-keys, the guides follow unified-keys-guides alone', () => {
  const holds = (privacy, guides) => {
    const data = JSON.parse(REAL_FLAGS);
    data.holds['unified-keys'].released = privacy;
    data.holds['unified-keys-guides'].released = guides;
    return JSON.stringify(data);
  };
  const main = (site, route) => site.page(route).querySelector('main').innerHTML;
  const before = buildSite({ env: PROD, repo: { flags: holds(false, false) } });
  const text = buildSite({ env: PROD, repo: { flags: holds(true, false) } });
  const all = buildSite({ env: PROD, repo: { flags: holds(true, true) } });

  assert.match(main(before, '/datenschutz'), /Ein Zugriffstoken gilt nur für den Haushalt/);
  assert.doesNotMatch(main(before, '/datenschutz'), /Zugriffsschlüssel/);
  assert.doesNotMatch(main(before, '/en/privacy'), /access key/);
  for (const site of [text, all]) {
    assert.match(main(site, '/datenschutz'), /Ein Zugriffsschlüssel gilt nur für den Haushalt/);
    // Section 9's analytics event keeps its name „API-Schlüssel genutzt“ (consent text, unchanged).
    assert.doesNotMatch(main(site, '/datenschutz'), /mit einem API-Schlüssel|Rechtsgrundlage für API-Schlüssel|Ein Zugriffstoken gilt/);
    assert.match(main(site, '/en/privacy'), /An access key works only for the household/);
    assert.doesNotMatch(main(site, '/en/privacy'), /with an API key|Legal basis for API keys|An access token works/);
  }

  // Most apps still show „Zugriffstoken“ until the flag reaches everyone.
  for (const site of [before, text]) {
    assert.match(main(site, '/de/anleitungen/siri-kurzbefehl'), /Token erstellen/);
    assert.doesNotMatch(main(site, '/de/anleitungen/siri-kurzbefehl'), /Schlüssel erstellen/);
    assert.match(main(site, '/de/anleitungen/claude'), /Token erstellen/);
    assert.match(main(site, '/en/guides/claude'), /Create token/);
  }
  assert.match(main(all, '/de/anleitungen/siri-kurzbefehl'), /Schlüssel erstellen/);
  assert.doesNotMatch(main(all, '/de/anleitungen/siri-kurzbefehl'), /Token erstellen/);
  assert.match(main(all, '/de/anleitungen/claude'), /Schlüssel erstellen/);
  assert.match(main(all, '/en/guides/claude'), /Create key/);
});
