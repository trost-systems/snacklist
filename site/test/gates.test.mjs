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

// Per-user Premium's sale terms (job 329), live only with the sale itself: one row per
// `premium-launch` gate in the four pages, with a phrase only that side of the gate renders.
const PREMIUM_LAUNCH_GATES = [
  ['datenschutz', 'once', '5a. Snacklist Premium: Jahresabo und Einmalkauf'],
  ['datenschutz', 'once', 'Snacklist Premium, das du gekauft hast, endet mit deinem Konto, auch ein Einmalkauf'],
  ['datenschutz', 'until', 'Snacklist Lifetime endet mit dem Haushalt'],
  ['datenschutz', 'once', 'Snacklist Premium, das du gekauft hast, behältst du'],
  ['privacy', 'once', '5a. Snacklist Premium: yearly plan and one-time purchase'],
  ['privacy', 'once', 'Snacklist Premium you bought ends with your account, a one-time purchase included'],
  ['privacy', 'until', 'Snacklist Lifetime ends with the household'],
  ['privacy', 'once', 'you keep Snacklist Premium you bought'],
  ['support', 'until', 'auch mit Snacklist Lifetime; der Kauf lässt sich nicht auf einen anderen Haushalt übertragen'],
  ['support', 'once', 'endet mit deinem Konto, auch der Einmalkauf; es lässt sich nicht auf ein anderes Konto übertragen'],
  ['support', 'until', 'Was passiert mit Snacklist Lifetime, wenn ich als letztes Mitglied einen Haushalt verlasse?'],
  ['support', 'until', 'Kann ich Snacklist Lifetime zurückgeben?'],
  ['support', 'once', 'Was passiert mit Snacklist Premium, wenn ich einen Haushalt verlasse?'],
  ['support', 'once', 'Wie kündige ich das Jahresabo?'],
  ['support', 'once', 'Was passiert, wenn mein Premium endet?'],
  ['support', 'once', 'Kann ich Snacklist Premium zurückgeben?'],
  ['support-en', 'until', "Snacklist Lifetime included; the purchase can't be moved to another household"],
  ['support-en', 'once', "the one-time purchase included; it can't be moved to another account"],
  ['support-en', 'until', 'What happens to Snacklist Lifetime if I leave a household as its last member?'],
  ['support-en', 'until', 'Can I get a refund for Snacklist Lifetime?'],
  ['support-en', 'once', 'What happens to Snacklist Premium if I leave a household?'],
  ['support-en', 'once', 'How do I cancel the yearly plan?'],
  ['support-en', 'once', 'What happens when my Premium ends?'],
  ['support-en', 'once', 'Can I get a refund for Snacklist Premium?'],
];
const ROUTE = { datenschutz: '/datenschutz', privacy: '/en/privacy', support: '/support', 'support-en': '/en/support' };

test('every premium-launch gate of the privacy and help pages is listed, so a dropped gate fails the test below', () => {
  for (const page of Object.keys(ROUTE)) {
    const source = readFileSync(join(import.meta.dirname, '..', 'content', 'legal', `${page}.md`), 'utf8');
    const gates = source.match(/premium-launch/g)?.length ?? 0;
    assert.equal(gates, PREMIUM_LAUNCH_GATES.filter(([p]) => p === page).length, `${page}.md: gates in the file vs rows in PREMIUM_LAUNCH_GATES`);
  }
});

test('the privacy and help pages describe the Premium sale only once premium-launch is released', () => {
  const launch = (released) => {
    const data = JSON.parse(REAL_FLAGS);
    data.holds['premium-launch'].released = released;
    return JSON.stringify(data);
  };
  const held = buildSite({ env: PROD, repo: { record: ALL_VERSIONS_LIVE, flags: launch(false) } });
  const live = buildSite({ env: PROD, repo: { record: ALL_VERSIONS_LIVE, flags: launch(true) } });
  const text = (site, page) => site.page(ROUTE[page]).querySelector('main').text;
  for (const [page, mode, phrase] of PREMIUM_LAUNCH_GATES) {
    assert.equal(text(held, page).includes(phrase), mode === 'until', `held ${page}: ${phrase}`);
    assert.equal(text(live, page).includes(phrase), mode === 'once', `released ${page}: ${phrase}`);
  }
  for (const out of [held, live]) for (const page of Object.keys(ROUTE)) {
    assert.doesNotMatch(out.page(ROUTE[page]).querySelector('main').innerHTML, /since-block|draft-banner/, page);
  }
});
