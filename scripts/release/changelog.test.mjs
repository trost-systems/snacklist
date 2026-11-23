// changelog.mjs: the PR note parser, the collector against a scratch git repository, the store
// texts and the draft and store commands. Run by scripts/release/test.sh.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { RecordError, STORE_LIMITS, parseDraft, parseRecord } from '../../site/releases.mjs';
import { NoteError, checkGates, gateOf, parseNote, parseOverride, sanitize, storeText, storeTexts } from './changelog.mjs';

const cli = fileURLToPath(new URL('changelog.mjs', import.meta.url));
const recordCli = fileURLToPath(new URL('record.mjs', import.meta.url));
const realRecord = readFileSync(fileURLToPath(new URL('../../releases/releases.json', import.meta.url)), 'utf8');
const realFlags = readFileSync(fileURLToPath(new URL('../../releases/flags.json', import.meta.url)), 'utf8');

const note = (...paragraphs) => `## What\n\nSomething.\n\n## Changelog\n${paragraphs.join('\n\n')}\n`;
const item = (category, de, en) => `${category}\nde: ${de}\nen: ${en}`;
const rejects = (message, pattern) => assert.throws(() => parseNote(message), (e) => e instanceof NoteError && pattern.test(e.message), `expected ${pattern}`);

describe('parseNote', () => {
  test('no section is null, none is none', () => {
    assert.equal(parseNote('## What\n\nA refactor.\n'), null);
    assert.equal(parseNote(note('none')), 'none');
    assert.equal(parseNote('## Changelog\r\nnone\r\n'), 'none', 'CRLF as the GitHub API returns it');
  });

  test('several items in order, with the text after the section ignored', () => {
    const message = `${note(item('new', 'Mit Alexa fügst du Artikel hinzu.', 'Add items with Alexa.'), 'Fixed:\n- en: The list no longer jumps.\n- de: Die Liste springt nicht mehr.', item('improved', 'Schneller.', 'Faster.'))}
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-authored-by: Peter Trost <peter@petertrost.com>`;
    assert.deepEqual(parseNote(message), [
      { category: 'new', de: 'Mit Alexa fügst du Artikel hinzu.', en: 'Add items with Alexa.' },
      { category: 'fixed', de: 'Die Liste springt nicht mehr.', en: 'The list no longer jumps.' },
      { category: 'improved', de: 'Schneller.', en: 'Faster.' },
    ]);
  });

  test('the section ends at the next heading; HTML comments (the template guidance) are no part of it', () => {
    assert.deepEqual(parseNote(`## Changelog\n<!--\nnew\nde: x\n-->\n${item('fixed', 'A.', 'B.')}\n\n## How verified\n\nfixd\nde: x\n`), [{ category: 'fixed', de: 'A.', en: 'B.' }]);
  });

  test('lenient about wording around the words', () => {
    for (const none of ['None.', '`none`', '> none', 'none (docs only)', '**none**', 'keine']) assert.equal(parseNote(note(none)), 'none', none);
    assert.deepEqual(parseNote(note('**New:**\nde: A.\nen: B.')), [{ category: 'new', de: 'A.', en: 'B.' }]);
  });

  test('a fenced example of the format is no section', () => {
    const quoted = '## What\n\nThe format:\n\n```\n## Changelog\nfixd\nde: x\n```\n';
    assert.equal(parseNote(quoted), null);
    assert.equal(parseNote(`${quoted}\n## Changelog\nnone\n`), 'none');
  });

  test('invalid sections are rejected with the reason', () => {
    rejects(note(item('fixd', 'A.', 'B.')), /unknown category "fixd"/);
    rejects('### Changelog\nnone\n', /"### Changelog" is not the section heading; write it as "## Changelog"/);
    rejects('## Changelog:\nnone\n', /"## Changelog:" is not the section heading/);
    rejects(note('new\nde: Nur Deutsch.'), /item "Nur Deutsch\." has no "en:" line/);
    rejects(note('new\nen: Only English.'), /has no "de:" line/);
    rejects(note('none', item('new', 'A.', 'B.')), /"none" and items in one section/);
    rejects(note('none\nde: x'), /"none" stands alone/);
    rejects(note(item('new', 'A.', 'B.') + '\nde: C.'), /two "de:" lines/);
    rejects(note('new\nde:\nen: B.'), /the "de:" line is empty/);
    rejects(note('new\nde: A.\nAnd more.\nen: B.'), /"And more\." is not a "de: \.\.\." or "en: \.\.\." line/);
    rejects('## Changelog\n<!-- the template, untouched -->\n', /section is empty/);
    rejects(`${note('none')}\n## Changelog\nnone\n`, /several "## Changelog" sections/);
    rejects(note('Thanks to Lea for the idea.', item('new', 'A.', 'B.')), /comes after "Thanks to Lea/);
  });

  test('job 40: an item may carry one flag: and one hold: line', () => {
    assert.deepEqual(parseNote(note(`${item('new', 'A.', 'B.')}\nflag: smart-lists\nhold: alexa-certification`, item('fixed', 'C.', 'D.'))), [
      { category: 'new', de: 'A.', en: 'B.', flag: 'smart-lists', hold: 'alexa-certification' },
      { category: 'fixed', de: 'C.', en: 'D.' },
    ]);
    assert.deepEqual(parseNote(note('new\n- Hold: `ios.widget_2`\n- de: A.\n- en: B.')), [{ category: 'new', de: 'A.', en: 'B.', hold: 'ios.widget_2' }], 'any order, list dashes, backticks');
    rejects(note(`${item('new', 'A.', 'B.')}\nflag: Smart Lists`), /new item: flag "Smart Lists" is not a key: lower-case letters/);
    rejects(note(`${item('new', 'A.', 'B.')}\nhold: -x`), /hold "-x" is not a key/);
    rejects(note(`${item('new', 'A.', 'B.')}\nflag:`), /flag "" is not a key/);
    rejects(note(`${item('new', 'A.', 'B.')}\nflag: a\nflag: b`), /two "flag:" lines; an item has at most one flag: and one hold: line/);
    rejects(note(`${item('new', 'A.', 'B.')}\nhold: a\nhold: a`), /two "hold:" lines/);
    rejects(note(`${item('new', 'A.', 'B.')}\nowner: lea`), /"owner: lea" is not a "de: \.\.\." or "en: \.\.\." line/);
    rejects(note('none\nflag: x'), /"none" stands alone/);
    rejects(note('flag: x'), /unknown category "flag: x"/);
  });
});

describe('store texts', () => {
  const sha = 'a'.repeat(40);
  const changelog = (counts, text = (c, i, lang) => `${lang} ${c} ${i}.`) => ({
    title: { de: '', en: '' },
    items: Object.fromEntries(Object.entries({ new: 0, improved: 0, fixed: 0, ...counts }).map(([c, n]) => [c, Array.from({ length: n }, (_, i) => ({ de: text(c, i, 'de'), en: text(c, i, 'en'), pr: i + 1, sha }))])),
  });

  test('title, then the categories with their items', () => {
    const c = changelog({ new: 2, improved: 1, fixed: 1 });
    c.title = { de: 'Alexa und schnellere Listen', en: 'Alexa and faster lists' };
    assert.equal(storeText(c, 'play', 'de', '1.0.0'), 'Alexa und schnellere Listen\n\nNeu:\n• de new 0.\n• de new 1.\n\nVerbessert:\n• de improved 0.\n\nBehoben:\n• de fixed 0.');
    assert.equal(storeText(c, 'app_store', 'en', '1.0.0'), 'Alexa and faster lists\n\nNew:\n• en new 0.\n• en new 1.\n\nImproved:\n• en improved 0.\n\nFixed:\n• en fixed 0.');
  });

  test('over the Play limit, whole items go from the end (fixed, then improved, then new) and a link line follows', () => {
    const long = (c, i, lang) => `${lang}: ${c} item ${i} ${'ä'.repeat(40)}.`;
    const c = changelog({ new: 4, improved: 4, fixed: 4 }, long);
    const text = storeText(c, 'play', 'de', '1.2.0');
    assert.ok([...text].length <= 500, `${[...text].length} characters`);
    assert.match(text, /\n\nAlle Änderungen: snacklist\.app\/de\/changelog#v1-2-0$/);
    for (let i = 0; i < 4; i++) assert.ok(text.includes(`new item ${i}`), `new ${i} kept`);
    assert.ok(!text.includes('Behoben:'), 'fixed went first');
    const kept = text.split('\n').filter((l) => l.startsWith('• '));
    for (const line of kept) assert.match(line, /^• de: \w+ item \d ä{40}\.$/, 'no sentence is cut');
    const appStore = storeText(c, 'app_store', 'de', '1.2.0');
    assert.ok(!appStore.includes('Alle Änderungen'), 'the same items fit the App Store');
    assert.equal(appStore.split('\n').filter((l) => l.startsWith('• ')).length, 12);
  });

  test('Play counts Unicode characters, the App Store UTF-8 bytes (umlauts count twice there)', () => {
    assert.equal(STORE_LIMITS.play.length('Grüße'), 5);
    assert.equal(STORE_LIMITS.play.length('Grüße'), 5, 'decomposed umlauts are composed first');
    assert.equal(STORE_LIMITS.app_store.length('Grüße'), 7);
    // 4000 bytes: 1999 "ü" plus the bullet and the heading do not fit, so the item goes.
    const c = changelog({ new: 1 }, (_, __, lang) => (lang === 'de' ? 'ü'.repeat(1999) : 'u'));
    assert.match(storeText(c, 'app_store', 'de', '1.0.0'), /^Alle Änderungen: snacklist\.app\/de\/changelog#v1-0-0$/);
    assert.match(storeText(c, 'play', 'de', '1.0.0'), /^Alle Änderungen/, 'over 500 characters on Play too');
    assert.equal(storeText(c, 'app_store', 'en', '1.0.0'), 'New:\n• u');
  });

  test('emoji and "<" are stripped, as Apple rejects them; text symbols stay', () => {
    assert.equal(sanitize('Neue Listen 🎉 für 👨‍👩‍👧 und 🇩🇪 <3'), 'Neue Listen für und 3');
    assert.equal(sanitize('Milch 🥛. Haken ✔️ und 1️⃣'), 'Milch. Haken und 1');
    assert.equal(sanitize('© 2026 Snacklist™ ↔ ✔'), '© 2026 Snacklist™ ↔ ✔');
    const c = changelog({ fixed: 1 }, () => 'Fixed ✅ the <b> tag 👍🏽.');
    assert.equal(storeText(c, 'play', 'en', '1.0.0'), 'Fixed:\n• Fixed the b> tag.');
    const onlyEmoji = changelog({ new: 2 }, (_, i) => (i === 0 ? '🎉' : 'Real.'));
    assert.equal(storeText(onlyEmoji, 'play', 'en', '1.0.0'), 'New:\n• Real.', 'an item that is only emoji leaves no empty bullet');
  });

  test('no items: the neutral sentence', () => {
    const c = changelog({ new: 0, improved: 0, fixed: 0 });
    assert.deepEqual(storeTexts(c, '1.0.0'), {
      app_store: { de: 'Fehlerbehebungen und Verbesserungen.', en: 'Bug fixes and improvements.' },
      play: { de: 'Fehlerbehebungen und Verbesserungen.', en: 'Bug fixes and improvements.' },
    });
  });
});

describe('draft and store commands', () => {
  let repo;
  const shas = {};
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' }).trim();
  const commit = (subject, body = '', path = 'app/lib/f.dart') => {
    mkdirSync(dirname(join(repo, path)), { recursive: true });
    writeFileSync(join(repo, path), subject);
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '-m', subject, ...(body ? ['-m', body] : []));
    shas[subject] = git('rev-parse', 'HEAD');
  };
  const run = (...args) => {
    const r = spawnSync('node', [cli, ...args], { cwd: repo, encoding: 'utf8' });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  };
  const draftFile = (version) => join(repo, 'releases/changelog', `${version}.json`);
  const readDraft = (version) => parseDraft(readFileSync(draftFile(version), 'utf8'), version);
  const withRelease = (version, sha) => {
    const data = JSON.parse(realRecord);
    data.releases = [{ version, channel: 'public', date: '2026-11-01', day: 10, build: 1, sha, previous_sha: null, stores: { app_store: true, play: true, web: true }, stats: { commits: 1, additions: 0, deletions: 0, files_changed: 0, contributors: [] }, notes: { de: '', en: '' } }];
    parseRecord(JSON.stringify(data));
    writeFileSync(join(repo, 'releases/releases.json'), `${JSON.stringify(data, null, 2)}\n`);
  };

  before(() => {
    repo = mkdtempSync(join(tmpdir(), 'changelog-test-'));
    git('init', '-q', '-b', 'main');
    mkdirSync(join(repo, 'releases'));
    writeFileSync(join(repo, 'releases/releases.json'), realRecord);
    writeFileSync(join(repo, 'releases/flags.json'), realFlags);
    commit('Job 1: foundation (#1)', 'Before job 39, no section.\n\nCo-authored-by: Peter Trost <peter@petertrost.com>');
    commit('Add voice (#2)', `${note(item('new', 'Per Sprache fügst du Artikel hinzu.', 'Add items by voice.'), item('fixed', 'Die Liste springt nicht mehr.', 'The list no longer jumps.'))}\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nCo-authored-by: Peter Trost <peter@petertrost.com>`);
    commit('CI: faster gates (#3)', note('none'));
    commit('Release 0.9.0: public release record');
    commit('Bump actions/checkout (#4)', 'Bumps actions/checkout.\n\nSigned-off-by: dependabot[bot] <support@github.com>');
    commit('Faster lists (#5)', note(item('improved', 'Listen laden schneller.', 'Lists load faster.'), item('fixed', 'Die Liste springt nicht mehr.', 'The list no longer jumps.')));
    commit('Merged without a PR number', note(item('fixed', 'Haken bleiben gesetzt.', 'Checks stay set.')));
  });
  after(() => rmSync(repo, { recursive: true, force: true }));

  test('from the root without a public release: none and section-less commits give nothing; grouped, merge order, deduped', () => {
    const r = run('draft', '--version', '1.0.0', '--sha', 'main');
    assert.equal(r.code, 0, r.stderr);
    const draft = readDraft('1.0.0');
    assert.deepEqual(draft.generated_from, { previous_sha: null, sha: shas['Merged without a PR number'] });
    assert.equal(draft.status, 'draft');
    assert.deepEqual(draft.title, { de: '', en: '' });
    assert.deepEqual(draft.items, {
      new: [{ de: 'Per Sprache fügst du Artikel hinzu.', en: 'Add items by voice.', pr: 2, sha: shas['Add voice (#2)'] }],
      improved: [{ de: 'Listen laden schneller.', en: 'Lists load faster.', pr: 5, sha: shas['Faster lists (#5)'] }],
      fixed: [
        { de: 'Die Liste springt nicht mehr.', en: 'The list no longer jumps.', pr: 2, sha: shas['Add voice (#2)'] },
        { de: 'Haken bleiben gesetzt.', en: 'Checks stay set.', pr: null, sha: shas['Merged without a PR number'] },
      ],
    });
    assert.equal(draft.store.play.en, 'New:\n• Add items by voice.\n\nImproved:\n• Lists load faster.\n\nFixed:\n• The list no longer jumps.\n• Checks stay set.');
    assert.match(r.stdout, /wrote releases\/changelog\/1\.0\.0\.json: 4 items from the root commit/);
  });

  test('a draft is never overwritten without --force', () => {
    const edited = readDraft('1.0.0');
    edited.title = { de: 'Sprache', en: 'Voice' };
    writeFileSync(draftFile('1.0.0'), `${JSON.stringify(edited, null, 2)}\n`);
    const r = run('draft', '--version', '1.0.0', '--sha', 'main');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /exists and may hold reviewed wording; .*--force/);
    assert.equal(readDraft('1.0.0').title.de, 'Sprache');
    assert.equal(run('draft', '--version', '1.0.0', '--sha', 'main', '--force').code, 0);
    assert.equal(readDraft('1.0.0').title.de, '');
  });

  test('the store command rewrites the store texts from edited wording', () => {
    const edited = readDraft('1.0.0');
    edited.title = { de: 'Sprache ist da', en: 'Voice is here' };
    edited.items.new[0].en = 'Add items by voice, in one sentence.';
    writeFileSync(draftFile('1.0.0'), `${JSON.stringify(edited, null, 2)}\n`);
    assert.equal(run('store', '--version', '1.0.0').code, 0);
    assert.match(readDraft('1.0.0').store.app_store.en, /^Voice is here\n\nNew:\n• Add items by voice, in one sentence\.\n/);
    assert.equal(readDraft('1.0.0').items.new[0].en, 'Add items by voice, in one sentence.', 'items are kept');
    rmSync(draftFile('1.0.0'));
  });

  test('after a public release the range starts at its sha; --previous-sha overrides it', () => {
    withRelease('0.9.0', shas['Release 0.9.0: public release record']);
    try {
      const r = run('draft', '--version', '1.0.0', '--sha', 'main', '--dry-run');
      assert.equal(r.code, 0, r.stderr);
      assert.match(r.stdout, /dry run: releases\/changelog\/1\.0\.0\.json not written/);
      assert.match(r.stdout, /--- play de \(\d+ of 500 Unicode characters\)/);
      assert.match(r.stdout, /--- app_store en \(\d+ of 4000 UTF-8 bytes\)/);
      assert.ok(!existsSync(draftFile('1.0.0')), 'a dry run writes nothing');
      const draft = JSON.parse(r.stdout.slice(0, r.stdout.indexOf('\n}\n') + 2));
      assert.equal(draft.generated_from.previous_sha, shas['Release 0.9.0: public release record']);
      assert.deepEqual(draft.items.new, [], 'voice shipped in 0.9.0');
      assert.deepEqual(draft.items.fixed.map((i) => i.pr), [5, null], 'the jump fix is listed again: it is a new PR');
      assert.equal(run('draft', '--version', '0.9.0', '--sha', 'main').code, 1, 'a recorded version');
      assert.match(run('draft', '--version', '0.8.0', '--sha', 'main').stderr, /must be above the newest public release 0\.9\.0/);
      const p = run('draft', '--version', '1.0.0', '--sha', 'main', '--previous-sha', shas['CI: faster gates (#3)'], '--dry-run');
      assert.equal(p.code, 0, p.stderr);
      assert.match(p.stdout, /"previous_sha": "[0-9a-f]{40}"/);
    } finally {
      writeFileSync(join(repo, 'releases/releases.json'), realRecord);
    }
  });

  test('an empty range warns loudly and uses the neutral sentence', () => {
    const r = run('draft', '--version', '1.0.0', '--sha', shas['CI: faster gates (#3)'], '--previous-sha', shas['Add voice (#2)'], '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    assert.match(r.stderr, /^WARNING: .*no user-visible change in this range.*suspicious/m);
    assert.match(r.stdout, /"de": "Fehlerbehebungen und Verbesserungen\."/);
  });

  test('an invalid section on main stops the draft and names the commit; --skip passes it', () => {
    commit('Broken note (#6)', note(item('fixd', 'A.', 'B.')));
    try {
      const r = run('draft', '--version', '1.0.0', '--sha', 'main', '--dry-run');
      assert.equal(r.code, 1);
      assert.match(r.stderr, new RegExp(`${shas['Broken note (#6)'].slice(0, 7)} "Broken note \\(#6\\)": unknown category "fixd"`));
      assert.equal(run('draft', '--version', '1.0.0', '--sha', 'main', '--dry-run', '--skip', shas['Broken note (#6)'].slice(0, 7)).code, 0);
    } finally {
      git('reset', '-q', '--hard', 'HEAD~1');
    }
  });

  test('drafts: stale store texts and misnamed drafts are refused', () => {
    assert.equal(run('draft', '--version', '1.0.0', '--sha', 'main').code, 0);
    assert.match(run('drafts').stdout, /changelog drafts: 1 checked/);
    const edited = readDraft('1.0.0');
    edited.items.new[0].en = 'Edited.';
    writeFileSync(draftFile('1.0.0'), `${JSON.stringify(edited, null, 2)}\n`);
    let r = run('drafts');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /store texts app_store\.en, play\.en are not what its title and items give; run: node scripts\/release\/changelog\.mjs store --version 1\.0\.0/);
    assert.equal(run('store', '--version', '1.0.0').code, 0);
    assert.equal(run('drafts').code, 0);
    writeFileSync(draftFile('1.1.0'), readFileSync(draftFile('1.0.0')));
    r = run('drafts');
    assert.match(r.stderr, /1\.1\.0\.json holds version 1\.0\.0/);
    rmSync(draftFile('1.1.0'));
    rmSync(draftFile('1.0.0'));
  });

  test('check: exit 0 valid, 1 invalid, 3 no section', () => {
    const check = (text) => spawnSync('node', [cli, 'check'], { input: text, encoding: 'utf8' });
    assert.equal(check(note('none')).status, 0);
    assert.match(check(note(item('new', 'A.', 'B.'))).stdout, /changelog: new: B\./);
    const bad = check(note('new\nde: A.'));
    assert.equal(bad.status, 1);
    assert.match(bad.stderr, /has no "en:" line/);
    assert.equal(check('## What\n').status, 3);
  });
});

// Job 40: items behind a flag or hold stay out of drafts, store texts and the site until
// releases/flags.json opens the gate; record.mjs keeps them in pending.json meanwhile.
describe('gated items, pending.json and the override', () => {
  let repo;
  const shas = {};
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' }).trim();
  const commit = (subject, body = '', path = 'app/lib/f.dart') => {
    mkdirSync(dirname(join(repo, path)), { recursive: true });
    writeFileSync(join(repo, path), subject);
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '-m', subject, ...(body ? ['-m', body] : []));
    shas[subject] = git('rev-parse', 'HEAD');
  };
  const run = (...args) => {
    const r = spawnSync('node', [cli, ...args], { cwd: repo, encoding: 'utf8' });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  };
  const record = (...args) => {
    const r = spawnSync('node', [recordCli, 'add', '--main', 'main', '--file', 'releases/releases.json', ...args], { cwd: repo, encoding: 'utf8' });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  };
  const path = (name) => join(repo, 'releases/changelog', name);
  const readDraft = (version) => parseDraft(readFileSync(path(`${version}.json`), 'utf8'), version);
  const pending = () => JSON.parse(readFileSync(path('pending.json'), 'utf8')).items;
  const dryDraft = (stdout) => JSON.parse(stdout.slice(0, stdout.indexOf('\n}\n') + 2));
  const flags = (patch = {}) => {
    const data = {
      flags: { 'smart-lists': { rollout: 'partial', note: 'half the households' }, 'dark-mode': { rollout: 'full', note: '' } },
      holds: {
        'alexa-certification': { released: false, note: 'an example hold that is not released yet', match: ['alexa'] },
        'ios-widget': { released: true, note: '' },
      },
    };
    for (const [k, v] of Object.entries(patch)) Object.assign(k in data.flags ? data.flags[k] : data.holds[k], v);
    writeFileSync(join(repo, 'releases/flags.json'), `${JSON.stringify(data, null, 2)}\n`);
  };
  const smart = 'Listen sortieren sich selbst.';
  const alexa = 'Mit Alexa fügst du Artikel hinzu.';

  before(() => {
    repo = mkdtempSync(join(tmpdir(), 'changelog-gates-'));
    git('init', '-q', '-b', 'main');
    mkdirSync(join(repo, 'releases/changelog'), { recursive: true });
    writeFileSync(join(repo, 'releases/releases.json'), realRecord);
    writeFileSync(path('pending.json'), '{\n  "items": []\n}\n');
    flags();
    commit('Base (#1)', note('none'));
    commit('Smart lists (#2)', note(`${item('new', smart, 'Lists sort themselves.')}\nflag: smart-lists`, item('fixed', 'Haken bleiben gesetzt.', 'Checks stay set.')));
    commit('Alexa skill (#3)', note(`${item('new', alexa, 'Add items with Alexa.')}\nhold: alexa-certification`));
    commit('Alexa fix (#4)', note(item('fixed', 'Alexa versteht dich besser.', 'Alexa understands you better.')));
    commit('Widget (#5)', note(`${item('new', 'Ein Widget zeigt die Liste.', 'A widget shows the list.')}\nhold: ios-widget`));
    commit('Dark mode (#6)', note(`${item('improved', 'Dunkles Design.', 'Dark theme.')}\nflag: dark-mode`));
  });
  after(() => rmSync(repo, { recursive: true, force: true }));

  test('a partial flag and an unreleased hold keep items out of the draft and the store texts; full and released let them in', () => {
    const r = run('draft', '--version', '1.0.0', '--sha', 'main', '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    const draft = dryDraft(r.stdout);
    assert.deepEqual(draft.items.new, [{ de: 'Ein Widget zeigt die Liste.', en: 'A widget shows the list.', pr: 5, sha: shas['Widget (#5)'], hold: 'ios-widget' }]);
    assert.deepEqual(draft.items.improved, [{ de: 'Dunkles Design.', en: 'Dark theme.', pr: 6, sha: shas['Dark mode (#6)'], flag: 'dark-mode' }]);
    assert.deepEqual(draft.items.fixed.map((i) => i.pr), [2]);
    assert.deepEqual(
      draft.held.map((i) => [i.category, i.flag, i.hold, i.pr]),
      [
        ['new', 'smart-lists', null, 2],
        ['new', null, 'alexa-certification', 3],
        ['fixed', null, 'alexa-certification', 4],
      ],
    );
    for (const text of Object.values(draft.store).flatMap(Object.values)) {
      assert.doesNotMatch(text, /alexa|sortieren|sort themselves/i, 'no held item in a store text');
    }
    assert.match(r.stderr, /WARNING: "Alexa understands you better\." \([0-9a-f]{7}\) mentions "alexa" but has no "hold: alexa-certification" line; held anyway/);
    assert.match(r.stdout, /--- held, not public \(3\): record\.mjs keeps them in releases\/changelog\/pending\.json/);
    assert.match(r.stdout, / {2}new \[flag: smart-lists\] Lists sort themselves\. \(#2 [0-9a-f]{7}\)/);
    assert.ok(!existsSync(path('1.0.0.json')), 'a dry run writes nothing');
    assert.deepEqual(pending(), [], 'the draft command never writes pending.json');
  });

  test('a flag or hold that releases/flags.json does not know is an error, not public', () => {
    for (const [line, pattern] of [
      ['flag: smart-list', /flag "smart-list" is not in releases\/flags\.json; add it under "flags"/],
      ['hold: alexa-cert', /hold "alexa-cert" is not in releases\/flags\.json; add it under "holds"/],
    ]) {
      commit('Typo (#9)', note(`${item('new', 'A.', 'B.')}\n${line}`));
      try {
        const r = run('draft', '--version', '1.0.0', '--sha', 'main', '--dry-run');
        assert.equal(r.code, 1, line);
        assert.match(r.stderr, pattern);
      } finally {
        git('reset', '-q', '--hard', 'HEAD~1');
      }
    }
  });

  test('check: unknown keys and an Alexa item without its hold fail; with the hold it passes', () => {
    const check = (text) => spawnSync('node', [cli, 'check'], { cwd: repo, input: text, encoding: 'utf8' });
    let r = check(note(`${item('new', 'A.', 'B.')}\nflag: nope`));
    assert.equal(r.status, 1);
    assert.match(r.stderr, /flag "nope" is not in releases\/flags\.json/);
    r = check(note(item('fixed', 'Der Alexa-Skill antwortet schneller.', 'The skill answers faster.')));
    assert.equal(r.status, 1, 'German text mentions Alexa');
    assert.match(r.stderr, /mentions "alexa": add the line "hold: alexa-certification" \(an example hold that is not released yet\)/);
    r = check(note(`${item('new', alexa, 'Add items with Alexa.')}\nhold: alexa-certification`));
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /changelog: new \(hold: alexa-certification\): Add items with Alexa\./);
    for (const de of ['Alexas Antworten sind schneller.', 'Der Alexaskill.', 'Ale\u00ADxa hört zu.', 'Siehe alexa.amazon.de.']) {
      assert.equal(check(note(item('fixed', de, 'Faster.'))).status, 1, `${de}: matched at a word start`);
    }
    assert.equal(check(note(item('new', 'Die Lexa-Liste.', 'The Lexa list.'))).status, 0, 'not inside a word');
  });

  test('check: once the hold is released an Alexa item needs no hold line', () => {
    flags({ 'alexa-certification': { released: true } });
    const r = spawnSync('node', [cli, 'check'], { cwd: repo, input: note(item('new', alexa, 'Add items with Alexa.')), encoding: 'utf8' });
    flags();
    assert.equal(r.status, 0, r.stderr);
  });

  test('record keeps the held items in pending.json; once the flag is full the next draft takes them and they leave pending.json', () => {
    assert.equal(run('draft', '--version', '1.0.0', '--sha', 'main').code, 0);
    let r = record('--version', '1.0.0', '--sha', 'main', '--build', '1', '--date', '2026-11-01');
    assert.equal(r.code, 0, r.stderr);
    assert.match(r.stdout, /pending\.json: 3 items held back after 1\.0\.0 \(was 0\)/);
    const entry = JSON.parse(readFileSync(join(repo, 'releases/releases.json'), 'utf8')).releases[0];
    assert.doesNotMatch(JSON.stringify(entry.changelog), /alexa|sort themselves/i, 'nothing held reaches the record');
    assert.deepEqual(pending().map((i) => [i.pr, i.flag, i.hold]), [[2, 'smart-lists', null], [3, null, 'alexa-certification'], [4, null, 'alexa-certification']]);
    assert.ok(!existsSync(path('1.0.0.json')));

    flags({ 'smart-lists': { rollout: 'full' } });
    commit('Later (#7)', note(item('fixed', 'Neu sortiert.', 'Sorted anew.')));
    r = run('draft', '--version', '1.1.0', '--sha', 'main');
    assert.equal(r.code, 0, r.stderr);
    assert.match(r.stdout, /--- from pending\.json, gate open now \(1\): in this draft/);
    const draft = readDraft('1.1.0');
    assert.deepEqual(draft.items.new, [{ de: smart, en: 'Lists sort themselves.', pr: 2, sha: shas['Smart lists (#2)'], flag: 'smart-lists' }], 'in its category, with its flag');
    assert.deepEqual(draft.items.fixed.map((i) => i.pr), [7]);
    assert.match(draft.store.play.en, /• Lists sort themselves\./);
    assert.deepEqual(draft.held.map((i) => i.pr), [3, 4]);
    assert.equal(pending().length, 3, 'pending.json changes only when the release is recorded');
    assert.match(run('drafts').stdout, /1 checked, 0 overrides, 3 pending items/);

    r = record('--version', '1.1.0', '--sha', 'main', '--build', '2', '--date', '2026-11-02');
    assert.equal(r.code, 0, r.stderr);
    assert.deepEqual(pending().map((i) => i.pr), [3, 4], 'the released item left pending.json; Alexa waits');
    const released = JSON.parse(readFileSync(join(repo, 'releases/releases.json'), 'utf8')).releases[1].changelog;
    assert.equal(released.items.new[0].flag, 'smart-lists');
    assert.doesNotMatch(JSON.stringify(released), /alexa/i);
  });

  test('the Alexa items reach a draft only after the hold is released', () => {
    commit('More (#8)', note(item('new', 'Mehr.', 'More.')));
    assert.equal(run('draft', '--version', '1.2.0', '--sha', 'main').code, 0);
    assert.deepEqual(readDraft('1.2.0').held.map((i) => i.pr), [3, 4]);
    assert.doesNotMatch(JSON.stringify({ items: readDraft('1.2.0').items, store: readDraft('1.2.0').store }), /alexa/i);
    flags({ 'alexa-certification': { released: true } });
    assert.equal(run('draft', '--version', '1.2.0', '--sha', 'main', '--force').code, 0);
    const draft = readDraft('1.2.0');
    assert.deepEqual(draft.items.new.map((i) => i.pr), [3, 8]);
    assert.deepEqual(draft.items.fixed.map((i) => [i.pr, i.hold]), [[4, 'alexa-certification']], 'the slipped Alexa fix carries the hold it was held by');
    assert.deepEqual(draft.held, []);
    rmSync(path('1.2.0.json'));
    flags({ 'smart-lists': { rollout: 'full' } });
  });

  test('record refuses a draft that would lose a pending item; without a draft pending.json keeps everything', () => {
    assert.equal(run('draft', '--version', '1.2.0', '--sha', 'main').code, 0);
    const draft = readDraft('1.2.0');
    draft.held = draft.held.slice(1);
    writeFileSync(path('1.2.0.json'), `${JSON.stringify(draft, null, 2)}\n`);
    let r = record('--version', '1.2.0', '--sha', 'main', '--build', '3', '--date', '2026-11-03', '--dry-run');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /neither publishes nor holds 1 item\(s\) of pending\.json, which would be lost: "Add items with Alexa\." /);
    rmSync(path('1.2.0.json'));
    commit('Gated late (#10)', note(`${item('new', 'Später.', 'Later.')}\nflag: smart-lists`, `${item('new', 'Halb.', 'Half.')}\nhold: alexa-certification`));
    r = record('--version', '1.2.0', '--sha', 'main', '--build', '3', '--date', '2026-11-03');
    assert.equal(r.code, 0, r.stderr);
    assert.match(r.stderr, /2 gated item\(s\) merged after the previous release wait in pending\.json for the next draft/);
    assert.deepEqual(pending().map((i) => i.pr), [3, 4, 10, 10], 'nothing published, nothing lost');
  });

  test('review: what a draft publishes is checked again against flags.json, and a draft must not reach past the release', () => {
    const head = git('rev-parse', 'HEAD');
    try {
      assert.equal(run('draft', '--version', '1.3.0', '--sha', 'main').code, 0);
      const good = readFileSync(path('1.3.0.json'), 'utf8');
      const collectedUpTo = (sha) => {
        const d = JSON.parse(good);
        d.generated_from.sha = sha;
        return `${JSON.stringify(d, null, 2)}\n`;
      };
      flags({ 'smart-lists': { rollout: 'partial' } });
      const flipped = readDraft('1.3.0');
      flipped.items.new.push({ de: smart, en: 'Lists sort themselves.', pr: 2, sha: shas['Smart lists (#2)'], flag: 'smart-lists' });
      writeFileSync(path('1.3.0.json'), `${JSON.stringify(flipped, null, 2)}\n`);
      assert.equal(run('store', '--version', '1.3.0').code, 0);
      let r = run('drafts');
      assert.equal(r.code, 1, 'a flag set back to partial after the draft');
      assert.match(r.stderr, /would publish what is held back; redraft with --force[^]*\n {2}"Lists sort themselves\." is public, but flag: smart-lists is not open/);
      r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04', '--dry-run');
      assert.equal(r.code, 1);
      assert.match(r.stderr, /would publish what is held back/);
      flags({ 'smart-lists': { rollout: 'full' } });

      const moved = JSON.parse(good);
      moved.title = { de: 'Alexa ist da', en: 'Alexa is here' };
      writeFileSync(path('1.3.0.json'), `${JSON.stringify(moved, null, 2)}\n`);
      assert.equal(run('store', '--version', '1.3.0').code, 0);
      r = run('drafts');
      assert.equal(r.code, 1, 'a title edited by hand to mention Alexa');
      assert.match(r.stderr, /title\.de mentions "alexa", held by alexa-certification/);
      writeFileSync(path('1.3.0.json'), good);

      writeFileSync(path('1.3.0.override.md'), '## de\ntitle: Neu\n\nJetzt mit Alexa.\n\n## en\ntitle: New\n\nNow with Alexa.\n');
      r = run('drafts');
      assert.equal(r.code, 1, 'an override that names Alexa');
      assert.match(r.stderr, /1\.3\.0\.override\.md would publish what is held back:\n {2}app_store\.de mentions "alexa", held by alexa-certification/);
      rmSync(path('1.3.0.override.md'));

      commit('After the draft (#11)', note(item('fixed', 'Danach.', 'After.')));
      writeFileSync(path('1.3.0.json'), collectedUpTo(git('rev-parse', 'HEAD')));
      r = record('--version', '1.3.0', '--sha', head, '--build', '4', '--date', '2026-11-04', '--dry-run');
      assert.equal(r.code, 1, 'a draft collected past the release would publish too much');
      assert.match(r.stderr, /was collected up to [0-9a-f]{7}, which is not [0-9a-f]{7} or before it; redraft with --sha/);
      const side = git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit-tree', `${head}^{tree}`, '-p', head, '-m', 'Side (#12)');
      writeFileSync(path('1.3.0.json'), collectedUpTo(side));
      r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04', '--dry-run');
      assert.equal(r.code, 1, 'a draft from another branch');
      assert.match(r.stderr, /which is not [0-9a-f]{7} or before it/);

      const old = JSON.parse(good);
      delete old.held;
      writeFileSync(path('1.3.0.json'), `${JSON.stringify(old, null, 2)}\n`);
      assert.match(run('drafts').stderr, /has no "held" \(a draft from before job 40\) while pending\.json has items; redraft it with --force/);
    } finally {
      git('reset', '-q', '--hard', head);
      rmSync(path('1.3.0.json'), { force: true });
      rmSync(path('1.3.0.override.md'), { force: true });
      flags({ 'smart-lists': { rollout: 'full' } });
    }
  });

  test('review: the same note pending twice (reverted and relanded) does not block the next release', () => {
    const before = readFileSync(path('pending.json'), 'utf8');
    const head = git('rev-parse', 'HEAD');
    const relanded = { category: 'new', de: 'Zweimal.', en: 'Twice.', flag: 'smart-lists', hold: null, pr: 13, sha: head };
    writeFileSync(path('pending.json'), `${JSON.stringify({ items: [...pending(), relanded, { ...relanded, pr: 14, sha: shas['Base (#1)'] }] }, null, 2)}\n`);
    flags({ 'smart-lists': { rollout: 'partial' } });
    const d = run('draft', '--version', '1.3.0', '--sha', 'main');
    assert.equal(d.code, 0, d.stderr);
    assert.equal(readDraft('1.3.0').held.filter((i) => i.en === 'Twice.').length, 1, 'the draft dedupes by sentence');
    const r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04', '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    rmSync(path('1.3.0.json'));
    writeFileSync(path('pending.json'), before);
    flags({ 'smart-lists': { rollout: 'full' } });
  });

  test('an override replaces title and store texts; status: draft blocks the public release until removed', () => {
    const text = (de, en) => `# Snacklist 1.3.0\nstatus: draft — pending Peter's review\n\n## de\ntitle: Willkommen\n\n${de}\n\n## en\ntitle: Welcome\n\n${en}\n`;
    writeFileSync(path('1.3.0.override.md'), text('Deine Liste, mit allen geteilt.\n\n• Sofort synchron', 'Your list, shared.\n\n• Syncs instantly'));
    let r = run('draft', '--version', '1.3.0', '--sha', 'main', '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    let draft = dryDraft(r.stdout);
    assert.deepEqual(draft.title, { de: 'Willkommen', en: 'Welcome' });
    assert.equal(draft.store.play.de, 'Deine Liste, mit allen geteilt.\n\n• Sofort synchron');
    assert.equal(draft.store.app_store.en, 'Your list, shared.\n\n• Syncs instantly', 'one text serves both stores');
    assert.match(r.stdout, /--- title and store texts from releases\/changelog\/1\.3\.0\.override\.md \(status: draft, so record\.mjs add refuses/);
    assert.match(r.stdout, /--- play de \(50 of 500 Unicode characters\)/);
    assert.doesNotMatch(r.stdout, /title is empty/);

    assert.equal(run('draft', '--version', '1.3.0', '--sha', 'main').code, 0);
    draft = readDraft('1.3.0');
    assert.ok(draft.items.new.length > 0, 'items stay as collected, for the site');
    assert.equal(run('drafts').code, 0);
    writeFileSync(path('1.3.0.override.md'), text('Anders.', 'Different.'));
    r = run('drafts');
    assert.equal(r.code, 1, 'the draft no longer matches its override');
    assert.match(r.stderr, /the title\.de|the app_store\.de|play\.de/);
    assert.match(r.stderr, /are not what releases\/changelog\/1\.3\.0\.override\.md gives; run: node scripts\/release\/changelog\.mjs store --version 1\.3\.0/);
    assert.equal(run('store', '--version', '1.3.0').code, 0);
    assert.equal(readDraft('1.3.0').store.play.en, 'Different.');

    r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /1\.3\.0\.override\.md says "status: draft": its launch text is not approved yet\. Peter approves it by removing that line; until then 1\.3\.0 can't be recorded/);
    r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04', '--dry-run');
    assert.equal(r.code, 0, 'a dry run shows the entry and warns');
    assert.match(r.stderr, /without --dry-run this refuses/);

    writeFileSync(path('1.3.0.override.md'), text('Anders.', 'Different.').replace(/^status:.*\n/m, ''));
    r = record('--version', '1.3.0', '--sha', 'main', '--build', '4', '--date', '2026-11-04');
    assert.equal(r.code, 0, r.stderr);
    assert.ok(!existsSync(path('1.3.0.override.md')) && !existsSync(path('1.3.0.json')), 'draft and override leave with the release');
    const entry = JSON.parse(readFileSync(join(repo, 'releases/releases.json'), 'utf8')).releases.at(-1);
    assert.deepEqual(entry.changelog.store.play, { de: 'Anders.', en: 'Different.' });
    assert.deepEqual(entry.changelog.title, { de: 'Willkommen', en: 'Welcome' });
  });

  test('an override without its draft cannot be recorded', () => {
    writeFileSync(path('1.4.0.override.md'), '## de\ntitle: A\n\nB\n\n## en\ntitle: C\n\nD\n');
    const r = record('--version', '1.4.0', '--sha', 'main', '--build', '5', '--date', '2026-11-05', '--dry-run');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /has the store texts of 1\.4\.0, but there is no .*1\.4\.0\.json; run: node scripts\/release\/changelog\.mjs draft/);
    rmSync(path('1.4.0.override.md'));
  });
});

describe('two holds on one item', () => {
  const gates = (released = {}) => ({
    flags: {},
    holds: {
      'premium-launch': { released: released.premium ?? false, note: 'not on sale yet', match: ['premium'] },
      'integration-lock': { released: released.lock ?? false, note: 'the lock is off' },
      'new-design': { released: true, note: '' },
    },
  });
  const lock = { category: 'new', de: 'Siri gehört zu Snacklist Premium.', en: 'Siri is part of Snacklist Premium.', hold: 'integration-lock' };

  test('an item whose own hold is closed may name another held word; a released or missing hold may not', () => {
    assert.doesNotThrow(() => checkGates([lock], gates()));
    for (const hold of ['new-design', undefined]) {
      assert.throws(() => checkGates([{ ...lock, hold }], gates()), /mentions "premium": add the line "hold: premium-launch"/, `hold ${hold}`);
    }
  });

  test('it is public only once both holds are released', () => {
    assert.equal(gateOf(lock, gates()).open, false);
    assert.equal(gateOf(lock, gates({ lock: true })).open, false, 'premium still held');
    assert.equal(gateOf(lock, gates({ premium: true })).open, false, 'its own hold still closed');
    assert.equal(gateOf(lock, gates({ lock: true, premium: true })).open, true);
  });
});

describe('parseOverride', () => {
  const parse = (text) => parseOverride(text, 'x.override.md');
  const fails = (text, pattern) => assert.throws(() => parse(text), (e) => e instanceof RecordError && pattern.test(e.message), String(pattern));
  const both = (de, en) => `## de\ntitle: T\n\n${de}\n\n## en\ntitle: T\n\n${en}\n`;

  test('separate play and app_store blocks; comments, emoji and "<" go', () => {
    const o = parse('<!-- guidance -->\n# Heading\n\n## de\ntitle: Hallo\n### play\nKurz 🎉.\n### app_store\nLänger <b>.\n\n\n\nMehr.\n## en\ntitle: Hi\n### app_store\nLonger.\n### play\nShort.\n');
    assert.equal(o.status, null);
    assert.deepEqual(o.store, { app_store: { de: 'Länger b>.\n\nMehr.', en: 'Longer.' }, play: { de: 'Kurz.', en: 'Short.' } });
  });

  test('limits: one text must fit Play, a play block 500, an app_store block 4000 bytes', () => {
    assert.doesNotThrow(() => parse(both('x'.repeat(500), 'y')));
    fails(both('x'.repeat(501), 'y'), /## de \(one text for both stores, so it must fit Play\): 501 Unicode characters, above play's limit of 500/);
    fails('## de\ntitle: T\n### play\nok\n### app_store\n' + 'ä'.repeat(2001) + '\n## en\ntitle: T\nok\n', /## de ### app_store: 4002 UTF-8 bytes, above app_store's limit of 4000/);
    fails('## de\ntitle: T\nok\n## en\ntitle: T\n### play\n' + 'ü'.repeat(501) + '\n### app_store\nok\n', /## en ### play: 501 Unicode characters/);
  });

  test('structure errors', () => {
    fails('## de\ntitle: T\n\nText\n', /no "## en" section; both languages are required/);
    fails('## de\nText\n## en\ntitle: T\nText\n', /## de: the first line is "title: <headline>"/);
    fails('## de\ntitle:\nText\n## en\ntitle: T\nText\n', /## de: the first line is "title: <headline>"/);
    fails(both('Text', '') , /## en: no text after the title/);
    fails('## fr\ntitle: T\n', /"## fr": a section is "## de" or "## en"/);
    fails(`${both('a', 'b')}## de\ntitle: T\nc\n`, /two "## de" sections/);
    fails('## de\ntitle: T\n### play\nok\n## en\ntitle: T\nok\n', /## de: "### app_store" is missing/);
    fails('## de\ntitle: T\nvorher\n### play\nok\n### app_store\nok\n## en\ntitle: T\nok\n', /## de: text outside the blocks/);
    fails('## de\ntitle: T\n### web\nok\n## en\ntitle: T\nok\n', /"### web": a block is "### play" or "### app_store"/);
    fails(`status: approved\n${both('a', 'b')}`, /the only status is "draft"/);
    fails(`Hallo\n${both('a', 'b')}`, /"Hallo" comes before "## de"/);
    assert.equal(parse(`status: draft — pending Peter's review\n${both('a', 'b')}`).status, 'draft');
  });

  test('the 1.0.0 launch text: both languages within the limits, no Alexa, no improved/fixed list, approved by Peter', () => {
    const file = fileURLToPath(new URL('../../releases/changelog/1.0.0.override.md', import.meta.url));
    const o = parse(readFileSync(file, 'utf8'));
    assert.equal(o.status, null, 'Peter approved the text on 2026-10-31');
    for (const [store, langs] of Object.entries(o.store)) {
      for (const [lang, text] of Object.entries(langs)) {
        assert.ok(STORE_LIMITS[store].length(text) <= STORE_LIMITS[store].limit, `${store} ${lang}`);
        assert.doesNotMatch(text, /alexa|humm\b|verbessert|behoben|improved|fixed|beta/i, `${store} ${lang}`);
      }
    }
  });
});

// Job 167: internal work (Nexus, CI, scripts, docs, tests, the site) never reaches the testers'
// "What to Test" or the public changelog; what users run does.
describe('internal commits stay out of the notes and the draft', () => {
  let repo;
  const shas = {};
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' }).trim();
  const commit = (subject, body, ...paths) => {
    for (const path of paths) {
      mkdirSync(dirname(join(repo, path)), { recursive: true });
      writeFileSync(join(repo, path), subject);
    }
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '--allow-empty', '-m', subject, ...(body ? ['-m', body] : []));
    shas[subject] = git('rev-parse', 'HEAD');
  };
  const run = (...args) => {
    const r = spawnSync('node', [cli, ...args], { cwd: repo, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    return { stdout: r.stdout.trimEnd(), stderr: r.stderr };
  };
  const notes = (lang, from, to = 'main') => run('notes', '--lang', lang, '--previous-sha', from, '--sha', to).stdout;

  before(() => {
    repo = mkdtempSync(join(tmpdir(), 'changelog-internal-'));
    git('init', '-q', '-b', 'main');
    mkdirSync(join(repo, 'releases'));
    writeFileSync(join(repo, 'releases/releases.json'), realRecord);
    writeFileSync(join(repo, 'releases/flags.json'), realFlags);
    commit('Job 20: rename the app to Snacklist (com.snacklist.app) (#46)', '', 'app/lib/main.dart');
    commit('Job 21: feedback button on the list (#60)', '', 'app/lib/feedback.dart');
    commit('nexus.snacklist.app: ops control room dashboard (#305)', note('none'), 'nexus/index.html', 'scripts/nexus/publish.sh');
    commit('Nexus status page (#306)', note(item('new', 'Ein Dashboard für den Betrieb.', 'An ops dashboard.')), 'nexus/status.html', '.github/workflows/nexus.yml');
    commit('privacy §14 last-member (#313)', note('none'), 'site/content/legal/privacy.md');
    commit('Store links wait for the server; the e2e proves the tap retries (#314)', note(item('fixed', 'Ein Link zu einem Laden öffnet ihn wieder.', 'A store link opens that store again.')), 'app/lib/router.dart', 'e2e/tests/deep-links.spec.ts');
    commit('Job 22 review 1: onboarding mail from peter@example.com no longer shows (#63)', '', 'app/lib/onboarding.dart');
    commit('ci: faster gates (#64)', '', 'app/lib/main.dart', 'scripts/gates/e2e.sh');
    commit('docs(done): job 21 summary (#61)', '', 'docs/done/21.md');
    commit('Sync indicator tests (#70)', note(item('fixed', 'Tests.', 'Tests.')), 'app/test/sync_test.dart', 'supabase/functions/voice/parse_test.ts', 'supabase/tests/rls.test.sql');
    commit('Debug overlay (#71)', `${note(item('new', 'Ein Overlay.', 'An overlay.'))}\nChangelog: skip\n`, 'app/lib/debug.dart');
    commit('Refactor the list cubit (#72)', note('none'), 'app/lib/list/list_cubit.dart');
    commit('Quoted skip line (#74)', `${note(item('new', 'Zitiert.', 'Quoted.'))}\n\`\`\`\nChangelog: skip\n\`\`\`\n<!--\nChangelog: skip\n-->\n`, 'app/lib/quoted.dart');
    commit('Grüne Häkchen (#75)', note(item('improved', 'Häkchen sind grün.', 'Ticks are green.')), 'app/assets/icons/häkchen.svg');
    commit('Classifier knows Baumarkt words (#73)', note(item('improved', 'Baumarkt-Wörter landen richtig.', 'DIY words land right.')), 'supabase/classifier/dictionary.tsv');
  });
  after(() => rmSync(repo, { recursive: true, force: true }));

  test('What to Test lists what users run, in their language, newest first', () => {
    const from = shas['Job 21: feedback button on the list (#60)'];
    assert.equal(notes('de', from), ['Neu in diesem Build von Snacklist:', '- Baumarkt-Wörter landen richtig.', '- Häkchen sind grün.', '- Zitiert.', '- onboarding mail from  no longer shows', '- Ein Link zu einem Laden öffnet ihn wieder.'].join('\n'));
    assert.equal(notes('en', from), ['New in this Snacklist build:', '- DIY words land right.', '- Ticks are green.', '- Quoted.', '- onboarding mail from  no longer shows', '- A store link opens that store again.'].join('\n'));
  });

  test('a range of internal commits only gives the nothing-new line', () => {
    const to = shas['Refactor the list cubit (#72)'];
    assert.equal(notes('de', shas['Job 21: feedback button on the list (#60)'], shas['privacy §14 last-member (#313)']), 'Kleine Verbesserungen und Fehlerbehebungen.');
    assert.equal(notes('en', shas['Job 22 review 1: onboarding mail from peter@example.com no longer shows (#63)'], to), 'Small improvements and fixes.');
  });

  test('an unknown previous commit (the first upload) takes the recent history, filtered the same way', () => {
    const out = notes('en', '0000000000000000000000000000000000000000');
    assert.match(out, /- rename the app to Snacklist \(com\.snacklist\.app\)$/);
    assert.doesNotMatch(out, /Nexus|nexus|dashboard|privacy|ci:|docs|Tests\.|overlay|@|#\d|Job \d/);
  });

  test('at most 12 lines, the rest counted', () => {
    const from = git('rev-parse', 'HEAD');
    for (let i = 1; i <= 15; i++) commit(`change ${i} (#${80 + i})`, '', `app/lib/change${i}.dart`);
    const out = notes('en', from).split('\n');
    assert.equal(out.filter((l) => l.startsWith('- change')).length, 12);
    assert.equal(out.at(-1), '- and 3 more changes');
  });

  test('the draft leaves out the items of internal commits and names them', () => {
    const r = run('draft', '--version', '1.0.0', '--sha', shas['Classifier knows Baumarkt words (#73)'], '--dry-run');
    const draft = JSON.parse(r.stdout.slice(0, r.stdout.indexOf('\n}\n') + 2));
    assert.deepEqual(['new', 'improved', 'fixed'].flatMap((c) => draft.items[c].map((i) => i.en)), ['Quoted.', 'Ticks are green.', 'DIY words land right.', 'A store link opens that store again.']);
    assert.match(r.stderr, /left out the items of [0-9a-f]{7} "Nexus status page \(#306\)": it changes nothing that reaches users/);
    assert.match(r.stderr, /"Sync indicator tests \(#70\)": it changes nothing that reaches users/);
    assert.match(r.stderr, /"Debug overlay \(#71\)": it is marked "Changelog: skip"/);
  });
});

// Job 213: rewords.json gives an item already on main new wording; the commit can't change.
describe('rewords.json', () => {
  let repo;
  let sha;
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' }).trim();
  const run = (...args) => {
    const r = spawnSync('node', [cli, ...args], { cwd: repo, encoding: 'utf8' });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  };
  const rewords = (items) => writeFileSync(join(repo, 'releases/changelog/rewords.json'), `${JSON.stringify({ items }, null, 2)}\n`);
  const reword = (patch = {}) => ({ sha, item: 2, why: 'Siri stays free', de: 'Der Zugang für KI-Assistenten gehört zu Premium.', en: 'Access for AI assistants is part of Premium.', ...patch });
  const dryDraft = (stdout) => JSON.parse(stdout.slice(0, stdout.indexOf('\n}\n') + 2));

  before(() => {
    repo = mkdtempSync(join(tmpdir(), 'changelog-rewords-'));
    git('init', '-q', '-b', 'main');
    mkdirSync(join(repo, 'releases/changelog'), { recursive: true });
    mkdirSync(join(repo, 'app/lib'), { recursive: true });
    writeFileSync(join(repo, 'releases/releases.json'), realRecord);
    writeFileSync(join(repo, 'releases/flags.json'), `${JSON.stringify({ flags: {}, holds: { 'integration-lock': { released: false, note: 'off' } } }, null, 2)}\n`);
    writeFileSync(join(repo, 'app/lib/f.dart'), 'x');
    git('add', '-A');
    const body = note(item('fixed', 'Haken bleiben gesetzt.', 'Checks stay set.'), `${item('new', 'Siri und KI-Assistenten gehören zu Premium.', 'Siri and AI assistants are part of Premium.')}\nhold: integration-lock`);
    git('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '-m', 'Premium (#7)', '-m', body);
    sha = git('rev-parse', 'HEAD');
  });
  after(() => rmSync(repo, { recursive: true, force: true }));

  test('the reworded item keeps its category and hold; the others stay as written', () => {
    rewords([reword()]);
    const r = run('draft', '--version', '9.0.0', '--sha', 'main', '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    const draft = dryDraft(r.stdout);
    assert.deepEqual(draft.held, [{ category: 'new', de: 'Der Zugang für KI-Assistenten gehört zu Premium.', en: 'Access for AI assistants is part of Premium.', flag: null, hold: 'integration-lock', pr: 7, sha }]);
    assert.deepEqual(draft.items.fixed.map((i) => i.en), ['Checks stay set.']);
    assert.doesNotMatch(r.stdout, /Siri and AI assistants/);
  });

  test('a dropped item leaves the draft; the others stay', () => {
    rewords([{ sha, item: 2, why: 'users saw no change', drop: true }]);
    const r = run('draft', '--version', '9.0.0', '--sha', 'main', '--dry-run');
    assert.equal(r.code, 0, r.stderr);
    const draft = dryDraft(r.stdout);
    assert.deepEqual(draft.held, []);
    assert.deepEqual(draft.items.fixed.map((i) => i.en), ['Checks stay set.']);
    assert.doesNotMatch(r.stdout, /Siri and AI assistants/);
  });

  test('a reword of an item the note does not have refuses the draft', () => {
    rewords([reword({ item: 3 })]);
    const r = run('draft', '--version', '9.0.0', '--sha', 'main', '--dry-run');
    assert.equal(r.code, 1);
    assert.match(r.stderr, /rewords\.json rewords item 3 of [0-9a-f]{7} "Premium \(#7\)", but its note has 2; fix the entry/);
  });

  test('drafts checks the file and does not take it for a draft', () => {
    rewords([reword()]);
    const ok = run('drafts');
    assert.equal(ok.code, 0, ok.stderr);
    assert.match(ok.stdout, /0 checked, 0 overrides, 0 pending items, 1 rewords/);
    for (const [patch, pattern] of [[{ why: '' }, /items\[0\]\.why: must not be empty/], [{ sha: 'abc' }, /items\[0\]\.sha: must be a full commit sha/], [{ item: 0 }, /items\[0\]\.item: must be the item's place/]]) {
      rewords([reword(patch)]);
      const r = run('drafts');
      assert.equal(r.code, 1, JSON.stringify(patch));
      assert.match(r.stderr, pattern);
    }
    rewords([reword(), reword()]);
    assert.match(run('drafts').stderr, /rewords item 2 of [0-9a-f]{7} a second time/);
  });
});
