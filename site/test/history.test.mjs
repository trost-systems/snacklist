// The release timeline /history and /en/history (job 105): empty state, the fixture record's
// releases in both languages, the bot rule, the footer link on every page, and the copy list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildSite, alternates, htmlRoutes, meta, record, serve, SITE_DIR } from './helpers.mjs';
import { HISTORY_COPY, people, personLabel, t } from '../history.mjs';
import { RecordError, parseRecord } from '../releases.mjs';

const PROD = { VERCEL_ENV: 'production' };
const DE = '/history';
const EN = '/en/history';
const SITE = 'https://snacklist.app';
const FIXTURE = readFileSync(join(SITE_DIR, 'test/fixtures/history-record.json'), 'utf8');

// What a reader gets from one entry, in order.
const entries = (doc) =>
  doc.querySelectorAll('main ol.history > li').map((li) => ({
    id: li.id,
    heading: li.querySelector('h2').text,
    date: li.querySelector('.release-date').text,
    stats: li.querySelectorAll('dl > div').map((d) => [d.querySelector('dt').text, d.querySelector('dd').text]),
    top: li.querySelectorAll('.history-people li').map((x) => x.text),
    link: [li.querySelector('.history-link a').text, li.querySelector('.history-link a').getAttribute('href')],
  }));

test('with no public release both pages show the empty state, served like every page', async () => {
  const { outDir, page } = buildSite({ env: PROD });
  const de = page(DE);
  const en = page(EN);
  assert.equal(de.querySelector('h1').text, 'Chronik');
  assert.equal(en.querySelector('h1').text, 'History');
  assert.deepEqual(de.querySelectorAll('main p').map((p) => p.text), [HISTORY_COPY['history.empty'].de]);
  assert.deepEqual(en.querySelectorAll('main p').map((p) => p.text), [HISTORY_COPY['history.empty'].en]);
  assert.equal(de.querySelector('main ol'), null);
  assert.equal(de.querySelector('title').text, 'Chronik | Snacklist');
  assert.equal(en.querySelector('title').text, 'History | Snacklist');
  assert.equal(meta(de, 'description'), HISTORY_COPY['history.description'].de);
  assert.equal(meta(en, 'description'), HISTORY_COPY['history.description'].en);
  const res = await serve(outDir, [DE, EN, '/de/changelog']);
  for (const route of [DE, EN]) {
    assert.equal(res[route].status, 200, route);
    // noindex exactly like the rest of the site: the header, no page-level meta.
    assert.equal(res[route].headers['x-robots-tag'], res['/de/changelog'].headers['x-robots-tag'], route);
    assert.equal(res[route].headers['x-robots-tag'], 'noindex', route);
    assert.equal(meta(page(route), 'robots'), undefined, route);
  }
});

test('the fixture record: every public release, newest first, in German', () => {
  const { page } = buildSite({ env: PROD, repo: { record: FIXTURE } });
  const doc = page(DE);
  assert.equal(doc.querySelector('.history-intro').text, 'Jede öffentliche Version von Snacklist, die neueste zuerst, mit Zahlen aus dem Code. Tag 0 ist der 22. Oktober 2026, der Tag des ersten Commits.');
  const list = entries(doc);
  assert.deepEqual(list.map((e) => e.id), ['v1-1-0', 'v1-0-1', 'v1-0-0']);
  assert.deepEqual(list[0], {
    id: 'v1-1-0',
    heading: 'Version 1.1.0',
    date: '15. Januar 2027 · Tag 85',
    stats: [
      ['Commits seit Version 1.0.1', '96'],
      ['Mitwirkende', '3'],
      ['Codezeilen', '132.271'],
      ['Am meisten beigetragen', 'Peter Trost (@peter-trost): 90 CommitsMia Brandt (@mia-brandt): 9 CommitsNoah Brandt: 1 Commit'],
      ['Bots und KI-Assistenten', 'an 91 von 96 Commits beteiligt'],
      ['Codezeilen nach Sprache', 'Dart 55.020TypeScript 37.410SQL 17.890JavaScript 10.811Shell 5.010Swift 1.990CSS 1.902Kotlin 760HTML 640Python 596C/C++ 143Ruby 99'],
    ],
    top: ['Peter Trost (@peter-trost): 90 Commits', 'Mia Brandt (@mia-brandt): 9 Commits', 'Noah Brandt: 1 Commit'],
    link: ['Neuigkeiten in Version 1.1.0', '/de/changelog#v1-1-0'],
  });
  // 1.0.0 was recorded before job 105: no lines of code, no bot share, counted from the root.
  assert.deepEqual(list[2].stats, [
    ['Commits bis zu dieser Version', '412'],
    ['Mitwirkende', '1'],
    ['Am meisten beigetragen', 'Peter Trost (@peter-trost): 412 Commits'],
  ]);
  assert.equal(doc.querySelector('.history-note').text, HISTORY_COPY['history.note'].de);
});

test('the fixture record in English', () => {
  const { page } = buildSite({ env: PROD, repo: { record: FIXTURE } });
  const list = entries(page(EN));
  assert.deepEqual(list[1], {
    id: 'v1-0-1',
    heading: 'Version 1.0.1',
    date: 'December 9, 2026 · Day 48',
    stats: [
      ['Commits since version 1.0.0', '18'],
      ['Contributors', '2'],
      ['Lines of code', '126,357'],
      ['Top contributors', 'Peter Trost (@peter-trost): 16 commitsMia Brandt (@mia-brandt): 2 commits'],
      ['Bots and AI assistants', 'took part in 17 of 18 commits'],
      ['Lines of code by language', 'Dart 52,110TypeScript 35,980SQL 17,005JavaScript 10,420Shell 4,902Swift 1,880CSS 1,850Kotlin 750HTML 622Python 596C/C++ 143Ruby 99'],
    ],
    top: ['Peter Trost (@peter-trost): 16 commits', 'Mia Brandt (@mia-brandt): 2 commits'],
    link: ["What's new in version 1.0.1", '/en/changelog#v1-0-1'],
  });
  assert.equal(list[2].stats[0][0], 'Commits up to this version');
});

test('bots are never named or counted; only GitHub logins and display names show', () => {
  const { page } = buildSite({ env: PROD, repo: { record: FIXTURE } });
  for (const route of [DE, EN]) {
    const main = page(route).querySelector('main').toString();
    assert.doesNotMatch(main, /Claude|petertrost-bot|dependabot|@users\.noreply|@petertrost\.com|aaaaaaaa/, route);
  }
  const fixture = parseRecord(FIXTURE);
  assert.deepEqual(people(fixture.releases[2].stats).map((p) => p.name), ['Peter Trost', 'Mia Brandt', 'Noah Brandt']);
  assert.equal(personLabel({ name: 'Peter Trost', github: 'peter-trost' }), 'Peter Trost (@peter-trost)');
  assert.equal(personLabel({ name: 'lea-x', github: 'Lea-X' }), '@Lea-X', 'a name that is the login shows once');
  assert.equal(personLabel({ name: 'Noah Brandt', github: null }), 'Noah Brandt');
});

test('at most three people under top contributors, ties by additions then name', () => {
  const four = record(['1.0.0'], (data) => {
    const person = (name, commits, additions) => ({ name, github: null, commits, additions, deletions: 0, bot: false });
    data.releases[0].stats = { ...data.releases[0].stats, commits: 5, contributors: [person('D', 1, 1), person('C', 2, 1), person('B', 2, 5), person('A', 2, 1)] };
    return data;
  });
  const list = entries(buildSite({ repo: { record: four } }).page(EN));
  assert.deepEqual(list[0].top, ['B: 2 commits', 'A: 2 commits', 'C: 2 commits']);
  assert.deepEqual(list[0].stats[1], ['Contributors', '4']);
});

test('accessible structure: one h1, an h2 per release in a list, the changelog anchors exist', () => {
  const { page } = buildSite({ env: PROD, repo: { record: FIXTURE } });
  for (const [route, changelog] of [[DE, '/de/changelog'], [EN, '/en/changelog']]) {
    const doc = page(route);
    assert.equal(doc.querySelectorAll('h1').length, 1);
    const list = doc.querySelector('main ol.history');
    assert.equal(list.getAttribute('role'), 'list', 'list semantics survive list-style: none in Safari');
    assert.equal(list.querySelectorAll(':scope > li > h2').length, 3);
    assert.equal(list.querySelectorAll('dl').length, 3);
    for (const a of doc.querySelectorAll('.history-link a')) {
      const [path, id] = a.getAttribute('href').split('#');
      assert.equal(path, changelog);
      assert.ok(page(changelog).querySelector(`#${id}`), `${route}: ${changelog}#${id}`);
    }
  }
});

test('the two pages pair with each other', () => {
  const { page } = buildSite({ env: PROD });
  const expected = { de: `${SITE}${DE}`, en: `${SITE}${EN}`, 'x-default': `${SITE}${DE}` };
  for (const [route, other] of [[DE, EN], [EN, DE]]) {
    const doc = page(route);
    assert.deepEqual(alternates(doc), expected, route);
    assert.equal(doc.querySelector('link[rel="canonical"]').getAttribute('href'), `${SITE}${route}`);
    assert.equal(doc.querySelector('header nav.lang a').getAttribute('href'), other);
  }
});

test('every page with a footer links the history of its language', () => {
  for (const env of [{}, PROD]) {
    const { outDir, page } = buildSite({ env });
    for (const route of htmlRoutes(outDir).filter((r) => r !== '/' && r !== '/404')) {
      const doc = page(route);
      const links = doc.querySelectorAll('footer nav.footer-site a').map((a) => [a.text, a.getAttribute('href')]);
      const expected = doc.querySelector('html').getAttribute('lang') === 'de' ? ['Chronik', DE] : ['History', EN];
      assert.deepEqual(links.at(-1), expected, route);
    }
  }
});

test('a release with malformed stats fails the build and names the field', () => {
  const bad = FIXTURE.replace('"total": 132271', '"total": 1');
  assert.throws(() => buildSite({ repo: { record: bad } }), (e) => e instanceof RecordError && /releases\[2\]\.stats\.loc\.total: is 1, but the languages add up to 132271/.test(e.message));
});

test('every history string has German and English, and the placeholders resolve', () => {
  for (const [id, entry] of Object.entries(HISTORY_COPY)) {
    for (const locale of ['de', 'en']) {
      assert.ok(entry[locale].trim(), `${id}.${locale}`);
      const vars = Object.fromEntries([...entry[locale].matchAll(/\{(\w+)\}/g)].map((m) => [m[1], 'X']));
      assert.doesNotMatch(t(id, locale, vars), /[{}]/, `${id}.${locale}`);
    }
    assert.deepEqual([...entry.de.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort(), [...entry.en.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort(), id);
    assert.ok(entry.status === 'draft' || entry.status === 'reused', `${id}.status`);
  }
  assert.throws(() => t('history.version', 'de'), /needs \{version\}/);
  const copyNeeded = readFileSync(join(SITE_DIR, 'COPY_NEEDED.md'), 'utf8');
  for (const [id, entry] of Object.entries(HISTORY_COPY)) {
    assert.match(copyNeeded, new RegExp(`\\| \`${id.replaceAll('.', '\\.')}\` \\|.*\\| ${entry.status} \\|`), `${id} in COPY_NEEDED.md as ${entry.status}`);
  }
});

test('a top contributor is a bold name and a separate count span, so the count stays whole (job 444)', () => {
  const { page } = buildSite({ env: PROD, repo: { record: FIXTURE } });
  const li = page(EN).querySelector('.history-people li');
  assert.equal(li.querySelector('b').text, 'Peter Trost (@peter-trost):');
  assert.equal(li.querySelector('span').text, '90 commits');
});
