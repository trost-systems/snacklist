#!/usr/bin/env node
// The user-facing changelog (docs/CHANGELOG.md): every PR description carries a `## Changelog`
// section, push-pr.sh lands it in the one commit main takes, and this script reads it back from git.
// Plain node, no packages, no network.
//
//   node scripts/release/changelog.mjs check [--file F]
//     Checks the `## Changelog` section of a PR description or commit message (stdin without
//     --file). Exit 0: valid; 1: invalid (the reason on stderr); 3: no section.
//   node scripts/release/changelog.mjs draft --version X --sha S [--previous-sha P] [--out F]
//     [--skip SHA]... [--force] [--dry-run]
//     Collects the notes of main's commits in previous..sha into releases/changelog/<X>.json,
//     with the App Store and Play "What's new" texts.
//   node scripts/release/changelog.mjs store --version X [--file F]
//     Rewrites a draft's store texts from its (edited) title and items.
//   node scripts/release/changelog.mjs notes --lang de|en --sha S [--previous-sha P]
//     TestFlight's "What to Test" for the commits in previous..sha (testerNotes).
//   node scripts/release/changelog.mjs drafts [--dir D]
//     Checks releases/flags.json and releases/changelog/: every draft valid, named <version>.json,
//     store texts current; pending.json, rewords.json and the <version>.override.md files valid.
//
// Job 40: an item with a `flag:` or `hold:` line stays out of the draft until releases/flags.json
// opens its gate. The draft lists it under `held`; record.mjs keeps it in
// releases/changelog/pending.json, and a later draft takes it once the gate is open. An override
// releases/changelog/<version>.override.md replaces the draft's title and store texts.

import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import {
  CATEGORIES,
  DRAFT_STATUS,
  GATE_KEY,
  PENDING_FILE,
  REWORDS_FILE,
  RecordError,
  STORE_LIMITS,
  compareVersions,
  draftFileNames,
  isVersion,
  parseDraft,
  parseGates,
  parsePending,
  parseRecord,
  parseRewords,
  publicReleases,
} from '../../site/releases.mjs';

export class NoteError extends Error {}

const HEADING = /^##[ \t]+changelog[ \t]*$/i;
const CATEGORY_WORDS = { new: 'new', neu: 'new', improved: 'improved', verbessert: 'improved', fixed: 'fixed', behoben: 'fixed' };
const TEXT_LINE = /^(?:[-*][ \t]+)?(de|en)[ \t]*:[ \t]*(.*)$/i;
const GATE_LINE = /^(?:[-*][ \t]+)?(flag|hold)[ \t]*:[ \t]*(.*)$/i;

// The word a category or `none` line holds, without Markdown around it, a trailing colon or full
// stop, or a remark in brackets: "**New:**", "`none`", "None.", "none (docs only)".
const word = (line) =>
  line
    .trim()
    .replace(/^(?:[-*>][ \t]+)+/, '')
    .replace(/[*_`]/g, '')
    .replace(/[ \t]*\([^)]*\)$/, '')
    .replace(/[:.]$/, '')
    .trim()
    .toLowerCase();
const NEAR_HEADING = /^[ \t]*#{1,6}[ \t]*\**changelog\b/i;

// A description without HTML comments (the template's guidance) and code fences: it may quote the
// format, heading included.
const unquoted = (message) =>
  message
    .replace(/\r/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?^ {0,3}\1[`~]*[ \t]*$/gm, '');

// The `## Changelog` section of a PR description or commit message: null when there is none,
// 'none', or the items in order. It runs to the next heading or `---` rule; a paragraph that is
// neither an item nor `none` ends it too, so text after it (a "Generated with" line, trailers)
// is no part of it. Strict about structure, lenient about case, a trailing colon and list dashes.
export function parseNote(message) {
  const lines = unquoted(message).split('\n');
  const starts = lines.flatMap((line, i) => (HEADING.test(line) ? [i] : []));
  const near = lines.find((line) => NEAR_HEADING.test(line) && !HEADING.test(line));
  if (near !== undefined) throw new NoteError(`"${near.trim()}" is not the section heading; write it as "## Changelog" on its own line`);
  if (starts.length === 0) return null;
  if (starts.length > 1) throw new NoteError('there are several "## Changelog" sections; keep one');
  const body = [];
  for (const line of lines.slice(starts[0] + 1)) {
    if (/^#{1,6}([ \t]|$)/.test(line) || /^-{3,}[ \t]*$/.test(line)) break;
    body.push(line);
  }
  const paragraphs = [];
  for (const line of body) {
    if (line.trim() === '') paragraphs.push([]);
    else (paragraphs.at(-1) ?? paragraphs[paragraphs.push([]) - 1]).push(line.trim());
  }
  const items = [];
  let none = false;
  let ended = null;
  for (const paragraph of paragraphs.filter((p) => p.length > 0)) {
    const [first, ...rest] = paragraph;
    const head = word(first);
    const looksLikeItem = paragraph.some((line) => TEXT_LINE.test(line) || GATE_LINE.test(line)) || /^[\p{L}-]+$/u.test(head);
    if (ended !== null) {
      if (looksLikeItem) throw new NoteError(`"${first}" comes after "${ended}", which is no item; put the items first, one after another`);
      continue;
    }
    if (head === 'none' || head === 'keine') {
      if (rest.length > 0) throw new NoteError(`"${first}" stands alone; found "${rest[0]}" after it`);
      none = true;
      continue;
    }
    const category = CATEGORY_WORDS[head];
    if (!category) {
      if (looksLikeItem) throw new NoteError(`unknown category "${first}"; an item starts with new, improved or fixed (or the section is just "none")`);
      ended = first;
      continue;
    }
    const texts = {};
    const gates = {};
    for (const line of rest) {
      const gate = GATE_LINE.exec(line);
      if (gate) {
        const kind = gate[1].toLowerCase();
        const key = gate[2].trim().replace(/^`(.*)`$/, '$1');
        if (kind in gates) throw new NoteError(`${category} item: two "${kind}:" lines; an item has at most one flag: and one hold: line`);
        if (!GATE_KEY.test(key)) throw new NoteError(`${category} item: ${kind} "${key}" is not a key: lower-case letters, digits, ".", "_" and "-", starting with a letter or digit`);
        gates[kind] = key;
        continue;
      }
      const match = TEXT_LINE.exec(line);
      if (!match) throw new NoteError(`${category} item: "${line}" is not a "de: ..." or "en: ..." line (or "flag: ..." / "hold: ...")`);
      const lang = match[1].toLowerCase();
      if (lang in texts) throw new NoteError(`${category} item: two "${lang}:" lines; one item has one de: and one en: line`);
      if (match[2].trim() === '') throw new NoteError(`${category} item: the "${lang}:" line is empty`);
      texts[lang] = match[2].trim();
    }
    for (const lang of ['de', 'en']) if (!(lang in texts)) throw new NoteError(`${category} item${texts.de || texts.en ? ` "${texts.de ?? texts.en}"` : ''} has no "${lang}:" line`);
    items.push({ category, de: texts.de, en: texts.en, ...gates });
  }
  if (none && items.length > 0) throw new NoteError('"none" and items in one section; write either items or just "none"');
  if (!none && items.length === 0) throw new NoteError('the "## Changelog" section is empty; add items (new, improved or fixed with a de: and an en: line) or "none"');
  return none ? 'none' : items;
}

// --- gates (job 40) -----------------------------------------------------------------------------

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// At a word start only, so "Alexas" and "Alexaskill" count too; a soft hyphen doesn't hide it.
const mentions = (word, text) => new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegExp(word)}`, 'iu').test(text.replace(/\u00AD/g, ''));

// The word of a hold not released yet that a public text mentions, as { key, word }, or null.
export function heldWordIn(text, gates) {
  for (const [key, hold] of Object.entries(gates.holds)) {
    if (hold.released) continue;
    const word = (hold.match ?? []).find((w) => mentions(w, text));
    if (word) return { key, word };
  }
  return null;
}

// What a draft or an override would publish while a gate is closed: an item whose flag or hold is
// closed now (flipped back since the draft, or moved there by hand), or a title or store text
// that mentions a held word. The changelog gate and record.mjs refuse it.
export function closedInPublic({ title, items = {}, store }, gates) {
  const problems = [];
  for (const category of CATEGORIES) {
    for (const item of items[category] ?? []) {
      let gate;
      try {
        gate = gateOf(item, gates);
      } catch (error) {
        if (!(error instanceof NoteError)) throw error;
        problems.push(`"${item.en}": ${error.message}`);
        continue;
      }
      if (!gate.open) problems.push(`"${item.en}" is public, but ${gate.matched ? `it mentions "${gate.matched.word}" (hold ${gate.matched.key})` : gateLabel(item)} is not open in releases/flags.json`);
    }
  }
  const texts = [...Object.entries(title ?? {}).map(([lang, t]) => [`title.${lang}`, t]), ...Object.entries(store ?? {}).flatMap(([name, langs]) => Object.entries(langs).map(([lang, t]) => [`${name}.${lang}`, t]))];
  for (const [path, text] of texts) {
    const hit = heldWordIn(text, gates);
    if (hit) problems.push(`${path} mentions "${hit.word}", held by ${hit.key} (${gates.holds[hit.key].note})`);
  }
  return problems;
}

// Whether an item may be public now. A flag must be `full` and a hold `released`; a key that
// releases/flags.json doesn't know is an error, so a typo never makes an item public. An item
// that mentions a word of a hold not released yet (`match`, the Alexa skill) stays back even
// without that hold's line: `matched` names the hold and the word.
export function gateOf(item, gates) {
  if (item.flag && !Object.hasOwn(gates.flags, item.flag)) throw new NoteError(`flag "${item.flag}" is not in releases/flags.json; add it under "flags" with its rollout (full, partial or off), or fix the key`);
  if (item.hold && !Object.hasOwn(gates.holds, item.hold)) throw new NoteError(`hold "${item.hold}" is not in releases/flags.json; add it under "holds" with "released": false, or fix the key`);
  let matched = null;
  for (const [key, hold] of Object.entries(gates.holds)) {
    if (hold.released || item.hold === key) continue;
    const word = (hold.match ?? []).find((w) => mentions(w, item.de) || mentions(w, item.en));
    if (word) {
      matched = { key, word };
      break;
    }
  }
  const flagOpen = !item.flag || gates.flags[item.flag].rollout === 'full';
  const holdOpen = !item.hold || gates.holds[item.hold].released;
  return { open: flagOpen && holdOpen && matched === null, matched };
}

// The check push-pr.sh and the gate run on a PR's items: keys known, and an item about something
// held back (Alexa) carries that hold's line, so its author sees it stays out of the changelog. An
// item with a hold of its own that is still closed may also name another held word (the
// integration lock's item names Premium): one hold line per item, and the draft keeps it back
// until both are released (gateOf).
export function checkGates(items, gates) {
  for (const item of items) {
    const { matched } = gateOf(item, gates);
    const ownHoldClosed = item.hold && !gates.holds[item.hold].released;
    if (matched && !ownHoldClosed) throw new NoteError(`${item.category} item "${item.en}" mentions "${matched.word}": add the line "hold: ${matched.key}" (${gates.holds[matched.key].note}); it stays out of the public changelog until releases/flags.json releases that hold`);
  }
}

// The draft's items and the held-back ones, from pending.json (older, first) and the collected
// items. Within a category, merge order; an item with the German and English sentences of an
// earlier one is dropped. Released items keep their flag or hold for tracing.
export function plan(collected, pending, gates) {
  const items = Object.fromEntries(CATEGORIES.map((c) => [c, []]));
  const held = [];
  const released = [];
  const matched = [];
  const seen = new Set();
  for (const [fromPending, item] of [...pending.map((i) => [true, i]), ...collected.map((i) => [false, i])]) {
    const key = `${item.de}\n${item.en}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const gate = gateOf(item, gates);
    const { category, de, en, pr, sha } = item;
    const flag = item.flag ?? null;
    const hold = item.hold ?? (gate.open ? null : gate.matched?.key) ?? null;
    if (gate.open) {
      items[category].push({ de, en, pr, sha, ...(flag ? { flag } : {}), ...(hold ? { hold } : {}) });
      if (fromPending) released.push({ category, de, en, flag, hold, pr, sha });
    } else {
      held.push({ category, de, en, flag, hold, pr, sha });
      if (gate.matched && (item.hold === null || item.hold === undefined)) matched.push({ item: held.at(-1), word: gate.matched.word });
    }
  }
  return { items, held, released, matched };
}

export function loadGates(file) {
  if (!existsSync(file)) refuse(`${relative(process.cwd(), file) || file} is missing; it lists the feature flags and holds (docs/CHANGELOG.md, "Gated items")`);
  return parseGates(readFileSync(file, 'utf8'), relative(process.cwd(), file) || file);
}

export function loadPending(dir) {
  const file = join(dir, PENDING_FILE);
  return existsSync(file) ? parsePending(readFileSync(file, 'utf8'), relative(process.cwd(), file) || file) : { items: [] };
}

export function loadRewords(dir) {
  const file = join(dir, REWORDS_FILE);
  return existsSync(file) ? parseRewords(readFileSync(file, 'utf8'), relative(process.cwd(), file) || file) : { items: [] };
}

export const serializePending = (pending) => `${JSON.stringify(pending, null, 2)}\n`;

// --- override (job 40) -------------------------------------------------------------------------

export const overrideName = (version) => `${version}.override.md`;
const OVERRIDE_FILE = /^(.+)\.override\.md$/;

// releases/changelog/<version>.override.md: a hand-written title and "What's new" texts that
// replace the generated ones (docs/CHANGELOG.md, "Override"). `## de` and `## en`, each a
// `title:` line, then one text for both stores or a `### play` and an `### app_store` block.
// A `status: draft` line before them marks it as not approved: record.mjs refuses to publish it.
export function parseOverride(text, source) {
  const fail = (reason) => {
    throw new RecordError(`${source}: ${reason}`);
  };
  let status = null;
  let current = null;
  const sections = {};
  for (const line of text.replace(/\r/g, '').replace(/<!--[\s\S]*?-->/g, '').split('\n')) {
    const h2 = /^##[ \t]+(.*?)[ \t]*$/.exec(line);
    if (h2) {
      const lang = h2[1].toLowerCase();
      if (!['de', 'en'].includes(lang)) fail(`"${line}": a section is "## de" or "## en"`);
      if (lang in sections) fail(`two "## ${lang}" sections`);
      current = sections[lang] = [];
    } else if (current) {
      current.push(line);
    } else if (/^status[ \t]*:/i.test(line)) {
      if (!/^status[ \t]*:[ \t]*draft\b/i.test(line)) fail(`"${line}": the only status is "draft"; remove the line once the text is approved`);
      if (status) fail('two status lines');
      status = 'draft';
    } else if (line.trim() !== '' && !/^#[ \t]/.test(line)) {
      fail(`"${line}" comes before "## de"; only a "# " heading and a "status: draft" line may`);
    }
  }
  const block = (lines) => sanitize(lines.map((l) => l.trimEnd()).join('\n')).replace(/\n{3,}/g, '\n\n');
  const title = {};
  const store = { 'app_store': {}, play: {} };
  const where = {};
  for (const lang of ['de', 'en']) {
    const body = sections[lang] ?? fail(`no "## ${lang}" section; both languages are required`);
    const first = body.findIndex((l) => l.trim() !== '');
    const heading = first < 0 ? null : /^title[ \t]*:[ \t]*(.*)$/i.exec(body[first].trim());
    if (!heading || heading[1].trim() === '') fail(`## ${lang}: the first line is "title: <headline>"`);
    title[lang] = heading[1].trim();
    const blocks = {};
    const free = [];
    let target = free;
    for (const line of body.slice(first + 1)) {
      const h3 = /^###[ \t]+(.*?)[ \t]*$/.exec(line);
      if (h3) {
        const name = h3[1].toLowerCase();
        if (!(name in store)) fail(`## ${lang}: "${line}": a block is "### play" or "### app_store"`);
        if (name in blocks) fail(`## ${lang}: two "### ${name}" blocks`);
        target = blocks[name] = [];
      } else if (/^#/.test(line)) {
        fail(`## ${lang}: "${line}": only "### play" and "### app_store" headings go here`);
      } else {
        target.push(line);
      }
    }
    if (Object.keys(blocks).length === 0) {
      const one = block(free);
      if (one === '') fail(`## ${lang}: no text after the title`);
      store.play[lang] = store.app_store[lang] = one;
      where[lang] = { play: `## ${lang} (one text for both stores, so it must fit Play)`, app_store: `## ${lang}` };
    } else {
      if (block(free) !== '') fail(`## ${lang}: text outside the blocks; with blocks, all text goes into "### play" and "### app_store"`);
      for (const name of Object.keys(store)) {
        if (!(name in blocks)) fail(`## ${lang}: "### ${name}" is missing; write both blocks, or one text without blocks for both stores`);
        store[name][lang] = block(blocks[name]);
        if (store[name][lang] === '') fail(`## ${lang}: "### ${name}" is empty`);
      }
      where[lang] = { play: `## ${lang} ### play`, app_store: `## ${lang} ### app_store` };
    }
    for (const [name, { limit, unit, length }] of Object.entries(STORE_LIMITS)) {
      const n = length(store[name][lang]);
      if (n > limit) fail(`${where[lang][name]}: ${n} ${unit}, above ${name}'s limit of ${limit}`);
    }
  }
  return { status, title, store };
}

export function loadOverride(dir, version) {
  const file = join(dir, overrideName(version));
  if (!existsSync(file)) return null;
  const label = relative(process.cwd(), file) || file;
  return { ...parseOverride(readFileSync(file, 'utf8'), label), file, label };
}

// --- store texts -------------------------------------------------------------------------------

const STORE_WORDS = {
  de: { new: 'Neu:', improved: 'Verbessert:', fixed: 'Behoben:', nothing: 'Fehlerbehebungen und Verbesserungen.', more: (anchor) => `Alle Änderungen: snacklist.app/de/changelog${anchor}` },
  en: { new: 'New:', improved: 'Improved:', fixed: 'Fixed:', nothing: 'Bug fixes and improvements.', more: (anchor) => `All changes: snacklist.app/en/changelog${anchor}` },
};
// What pilot's sanitize_changelog takes out because Apple rejects it: emoji and "<" (it then cuts at
// 4000 bytes; storeText never lets it get there).
// Emoji are what shows as emoji: emoji presentation, or text symbols with the emoji selector. ©, ™,
// arrows and ✔ without the selector are text and stay.
const EMOJI = /\p{Extended_Pictographic}\u{FE0F}|[\p{Emoji_Presentation}\p{Emoji_Modifier}\p{Regional_Indicator}\u{FE0F}\u{20E3}\u{200D}]/gu;
export const sanitize = (text) =>
  text.normalize('NFC').replace(EMOJI, '').replace(/</g, '').replace(/[ \t]{2,}/g, ' ').replace(/[ \t]+([.,:;!?])/g, '$1').trim();

export const anchorOf = (version) => `#v${version.replaceAll('.', '-')}`;

// One store's "What's new" in one language: the title, then the items under Neu/Verbessert/Behoben.
// When it doesn't fit, whole items go from the end (fixed first, then improved, then new) and a
// last line points to the full list; a sentence is never cut.
export function storeText(changelog, store, lang, version) {
  const { limit, length } = STORE_LIMITS[store];
  const words = STORE_WORDS[lang];
  const title = sanitize(changelog.title[lang]);
  const items = CATEGORIES.flatMap((category) => changelog.items[category].map((item) => ({ category, text: sanitize(item[lang]) }))).filter((i) => i.text !== '');
  const render = (kept, more) => {
    const blocks = title ? [title] : [];
    for (const category of CATEGORIES) {
      const lines = kept.filter((i) => i.category === category).map((i) => `• ${i.text}`);
      if (lines.length) blocks.push([words[category], ...lines].join('\n'));
    }
    if (kept.length === 0 && !more) blocks.push(words.nothing);
    if (more) blocks.push(words.more(anchorOf(version)));
    return blocks.join('\n\n');
  };
  let text = render(items, false);
  // Items are in category order, so dropping from the end drops fixed first, then improved, then new.
  for (let kept = items.length - 1; length(text) > limit; kept--) {
    if (kept < 0) throw new NoteError(`${store} ${lang}: the title alone does not fit the store's ${limit} ${STORE_LIMITS[store].unit}; shorten it`);
    text = render(items.slice(0, kept), true);
  }
  return text;
}

// Store texts that are not what title and items give (or, with an override, the title and store
// texts that are not the override's), as "store.lang" paths: a draft edited without running the
// store command afterwards.
export const staleStoreTexts = (changelog, version, override = null) => {
  const fresh = override ? override.store : storeTexts(changelog, version);
  const titles = override ? ['de', 'en'].filter((lang) => changelog.title[lang] !== override.title[lang]).map((lang) => `title.${lang}`) : [];
  return [...titles, ...Object.entries(fresh).flatMap(([store, langs]) => Object.keys(langs).filter((lang) => changelog.store[store][lang] !== langs[lang]).map((lang) => `${store}.${lang}`))];
};

export const staleMessage = (label, stale, version, override) =>
  `${label}: ${override ? `the ${stale.join(', ')} are not what ${override.label} gives` : `the store texts ${stale.join(', ')} are not what its title and items give`}; run: node scripts/release/changelog.mjs store --version ${version}`;

export const storeTexts = (changelog, version) =>
  Object.fromEntries(Object.keys(STORE_LIMITS).map((store) => [store, { de: storeText(changelog, store, 'de', version), en: storeText(changelog, store, 'en', version) }]));

// --- collecting from git ------------------------------------------------------------------------

export class Refusal extends Error {}
const refuse = (message) => {
  throw new Refusal(message);
};

function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 28 });
  } catch (error) {
    return refuse(`git ${args.join(' ')} failed: ${String(error.stderr || error.message).trim()}`);
  }
}

const commitOrNull = (ref) => {
  try {
    return execFileSync('git', ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
};

const commitOf = (ref, flag) => commitOrNull(ref) ?? refuse(`${flag} ${ref} is not a commit in this repository`);
const isAncestor = (ancestor, descendant) => {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', ancestor, descendant], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
};

// main's commits in a range (git log arguments), with subject, message and changed paths.
function commits(...range) {
  const log = git('-c', 'core.quotePath=false', 'log', '--first-parent', '--format=%x1e%H%x00%s%x00%B%x00', '--name-only', ...range);
  return log.split('\x1e').slice(1).map((chunk) => {
    const [hash, subject, message, names] = chunk.split('\x00');
    return { hash, subject, message, paths: names.split('\n').filter(Boolean) };
  });
}

// --- who a commit is for (job 167) --------------------------------------------------------------

// What reaches users: the app builds, the server they talk to, the Alexa skill.
const USER_PATHS = [/^app\/(lib|l10n|assets|android|ios|web)\//, /^app\/pubspec\.(yaml|lock)$/, /^supabase\/(migrations|functions|classifier)\//, /^alexa\//];
// Inside those, what users never run: tests and their fixtures, docs, store tooling.
const INTERNAL_PATHS = [/(^|\/)(tests?|test_driver|integration_test|fastlane)\//, /[._]test\.(dart|ts|mjs)$/, /\.md$/];
export const reachesUsers = (path) => USER_PATHS.some((p) => p.test(path)) && !INTERNAL_PATHS.some((p) => p.test(path));
// A paragraph of the PR description, for what the paths get wrong.
const SKIP_LINE = /^changelog[ \t]*:[ \t]*(?:skip|internal)[ \t]*$/im;
// Section-less commits (before job 39) that say what they are in a conventional prefix.
const INTERNAL_SUBJECT = /^(?:docs|ci|chore|test|build|style)(?:\(.*\))?!?:|^revert "/i;

// Why a commit is no news for users (the testers' notes, the changelog), or null when it may be:
// a "Changelog: skip" line, no changed path that reaches users (Nexus, CI, scripts, docs, e2e,
// mcp-proxy, the site, tests), or, without a ## Changelog section, a docs/ci/test-style subject.
export function internalReason({ subject, message, paths }, note) {
  if (SKIP_LINE.test(unquoted(message))) return 'is marked "Changelog: skip"';
  if (!paths.some(reachesUsers)) return 'changes nothing that reaches users';
  if (note === null && INTERNAL_SUBJECT.test(subject)) return 'is a docs, CI, chore, test, build or style commit';
  return null;
}

// The items of the notes of main's commits in previous..sha (from the root without previous),
// oldest first, each with its category, flag or hold, PR and commit. Commits without a section
// (before job 39, release records, Dependabot) and `none` give no items; nor do internal commits,
// whose items come back as `excluded` for the report. An item in releases/changelog/rewords.json
// takes the wording there (job 213); its category and gate stay the note's.
export function collect({ previous, sha, skip = [], rewords = loadRewords(changelogDir()).items }) {
  const items = [];
  const excluded = [];
  const problems = [];
  for (const commit of commits('--reverse', ...(previous ? [`${previous}..${sha}`] : [sha]))) {
    const { hash, subject, message } = commit;
    if (skip.some((s) => hash.startsWith(s))) continue;
    let note;
    try {
      note = parseNote(message);
    } catch (error) {
      if (!(error instanceof NoteError)) throw error;
      problems.push(`${hash.slice(0, 7)} "${subject}": ${error.message}`);
      continue;
    }
    if (note === null || note === 'none') continue;
    const reason = internalReason(commit, note);
    if (reason) {
      excluded.push({ hash, subject, reason });
      continue;
    }
    const pr = Number(/\(#(\d+)\)$/.exec(subject)?.[1]) || null;
    const stray = rewords.find((r) => r.sha === hash && r.item > note.length);
    if (stray) refuse(`releases/changelog/${REWORDS_FILE} rewords item ${stray.item} of ${hash.slice(0, 7)} "${subject}", but its note has ${note.length}; fix the entry's "item"`);
    note.forEach((item, i) => {
      const reword = rewords.find((r) => r.sha === hash && r.item === i + 1);
      if (reword?.drop) return;
      items.push({ ...item, ...(reword ? { de: reword.de, en: reword.en } : {}), pr, sha: hash });
    });
  }
  if (problems.length) {
    refuse(`invalid ## Changelog sections on main (fix the wording in the draft by hand and rerun with --skip <sha> for each):\n  ${problems.join('\n  ')}`);
  }
  return { items, excluded };
}

// TestFlight's "What to Test" (docs/RELEASE.md): what users see from main's commits in
// previous..sha, newest first. A commit's ## Changelog items in the note's language, or its title
// (no job prefix, PR number or e-mail address) when it has no section; `none` and internal commits
// give nothing. An unknown or missing previous commit (the first upload) takes the last 20.
const NOTES_WORDS = {
  de: { head: 'Neu in diesem Build von Snacklist:', none: 'Kleine Verbesserungen und Fehlerbehebungen.', more: (n) => `und ${n} weitere Änderungen` },
  en: { head: 'New in this Snacklist build:', none: 'Small improvements and fixes.', more: (n) => `and ${n} more changes` },
};
const NOTES_MAX = 12;
const noteTitle = (subject) =>
  subject
    .replace(/ \(#\d+\)$/, '')
    .replace(/^Job \d+[a-z]*[^:]*: /i, '')
    .replace(/[\w.%+-]+@[\w.-]+/g, '')
    .trim();

export function testerNotes({ lang, previous, sha }) {
  const known = previous && commitOrNull(previous);
  const lines = [];
  for (const commit of commits(...(known ? [`${known}..${sha}`] : ['-n', '20', sha]))) {
    let note;
    try {
      note = parseNote(commit.message);
    } catch (error) {
      if (!(error instanceof NoteError)) throw error;
      note = null;
    }
    if (note === 'none' || internalReason(commit, note)) continue;
    if (note === null) lines.push(noteTitle(commit.subject));
    else lines.push(...note.map((item) => item[lang]));
  }
  const words = NOTES_WORDS[lang];
  const shown = lines.filter((line) => line !== '');
  if (shown.length === 0) return words.none;
  const more = shown.length > NOTES_MAX ? [words.more(shown.length - NOTES_MAX)] : [];
  return [words.head, ...[...shown.slice(0, NOTES_MAX), ...more].map((line) => `- ${line}`)].join('\n');
}

const repoRoot = () => git('rev-parse', '--show-toplevel').trim();
const changelogDir = () => resolve(repoRoot(), 'releases/changelog');
const draftPath = (version) => join(changelogDir(), `${version}.json`);
const gateLabel = (item) => [item.flag && `flag: ${item.flag}`, item.hold && `hold: ${item.hold}`].filter(Boolean).join(', ');
const itemLine = (item) => `  ${item.category} [${gateLabel(item)}] ${item.en} (${item.pr ? `#${item.pr} ` : ''}${item.sha.slice(0, 7)})`;
export const serializeDraft = (draft) => `${JSON.stringify(draft, null, 2)}\n`;

function report(draft, file, { released = [], override = null } = {}) {
  const lines = [];
  if (override) lines.push(`--- title and store texts from ${override.label}${override.status ? ' (status: draft, so record.mjs add refuses to publish it until that line is removed)' : ''}`);
  for (const [store, langs] of Object.entries(draft.store)) {
    for (const [lang, text] of Object.entries(langs)) {
      const { limit, unit, length } = STORE_LIMITS[store];
      lines.push(`--- ${store} ${lang} (${length(text)} of ${limit} ${unit})`, text);
    }
  }
  const count = CATEGORIES.reduce((n, c) => n + draft.items[c].length, 0);
  const held = draft.held ?? [];
  if (held.length) lines.push(`--- held, not public (${held.length}): record.mjs keeps them in releases/changelog/${PENDING_FILE} until releases/flags.json opens their gate`, ...held.map(itemLine));
  if (released.length) lines.push(`--- from ${PENDING_FILE}, gate open now (${released.length}): in this draft; record.mjs removes them from ${PENDING_FILE}`, ...released.map(itemLine));
  if (count === 0 && !override) {
    console.error(`WARNING: ${file}: no user-visible change in this range, so the store texts say only "${STORE_WORDS.en.nothing}". A release without anything users notice is suspicious: check the range and the PRs' ## Changelog sections.`);
  }
  if (!override && (!draft.title.de || !draft.title.en)) lines.push(`--- title is empty: add a headline naming the 2-3 biggest things (title.de, title.en), then run: node scripts/release/changelog.mjs store --version ${draft.version}`);
  return lines.join('\n');
}

function draftCommand(argv) {
  const { values: opts } = parseArgs({
    args: argv,
    strict: true,
    options: {
      version: { type: 'string' },
      sha: { type: 'string' },
      'previous-sha': { type: 'string' },
      out: { type: 'string' },
      skip: { type: 'string', multiple: true, default: [] },
      record: { type: 'string' },
      force: { type: 'boolean', default: false },
      'dry-run': { type: 'boolean', default: false },
    },
  });
  for (const required of ['version', 'sha']) if (opts[required] === undefined) refuse(`--${required} is required`);
  if (!isVersion(opts.version)) refuse(`--version ${opts.version} is not MAJOR.MINOR.PATCH`);
  const recordFile = opts.record ? resolve(opts.record) : resolve(repoRoot(), 'releases/releases.json');
  const releases = publicReleases(parseRecord(readFileSync(recordFile, 'utf8'), relative(process.cwd(), recordFile) || recordFile));
  const recorded = releases.find((r) => r.version === opts.version);
  if (recorded) refuse(`--version ${opts.version} is already a public release (${recorded.date}); its changelog is in the record`);
  const newest = releases.at(-1);
  if (newest && compareVersions(opts.version, newest.version) <= 0) refuse(`--version ${opts.version} must be above the newest public release ${newest.version}`);

  const sha = commitOf(opts.sha, '--sha');
  const previous = opts['previous-sha'] !== undefined ? commitOf(opts['previous-sha'], '--previous-sha') : (newest?.sha ?? null);
  if (previous && !isAncestor(previous, sha)) refuse(`${previous} (${opts['previous-sha'] ? '--previous-sha' : `release ${newest.version}`}) is not an ancestor of ${sha}`);

  const root = repoRoot();
  const dir = changelogDir();
  const gates = loadGates(resolve(root, 'releases/flags.json'));
  const collected = collect({ previous, sha, skip: opts.skip });
  const { items, held, released, matched } = plan(collected.items, loadPending(dir).items, gates);
  for (const { hash, subject, reason } of collected.excluded) {
    console.error(`WARNING: left out the items of ${hash.slice(0, 7)} "${subject}": it ${reason}. If users do see it, add its items to the draft by hand.`);
  }
  for (const { item, word } of matched) {
    console.error(`WARNING: "${item.en}" (${item.sha.slice(0, 7)}) mentions "${word}" but has no "hold: ${item.hold}" line; held anyway until releases/flags.json releases that hold`);
  }
  const override = loadOverride(dir, opts.version);
  const changelog = { title: override?.title ?? { de: '', en: '' }, items };
  const draft = {
    version: opts.version,
    status: DRAFT_STATUS,
    'generated_from': { previous_sha: previous, sha },
    ...changelog,
    held,
    store: override?.store ?? storeTexts(changelog, opts.version),
  };
  const text = serializeDraft(draft);
  const file = opts.out ? resolve(opts.out) : draftPath(opts.version);
  const label = relative(process.cwd(), file) || file;
  parseDraft(text, label);
  if (opts['dry-run']) {
    console.log(text.trimEnd());
    console.log(report(draft, label, { released, override }));
    console.log(`dry run: ${label} not written`);
    return;
  }
  if (existsSync(file) && !opts.force) {
    refuse(`${label} exists and may hold reviewed wording; edit it by hand (then run the store command), or rerun with --force to replace it`);
  }
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, text);
  console.log(report(draft, label, { released, override }));
  const count = CATEGORIES.reduce((n, c) => n + items[c].length, 0);
  console.log(`wrote ${label}: ${count} items${held.length ? ` (${held.length} held)` : ''} from ${previous ? previous.slice(0, 7) : 'the root commit'}..${sha.slice(0, 7)}`);
}

function storeCommand(argv) {
  const { values: opts } = parseArgs({ args: argv, strict: true, options: { version: { type: 'string' }, file: { type: 'string' } } });
  if (opts.version === undefined) refuse('--version is required');
  const file = opts.file ? resolve(opts.file) : draftPath(opts.version);
  const label = relative(process.cwd(), file) || file;
  if (!existsSync(file)) refuse(`${label} does not exist; run the draft command first`);
  const draft = parseDraft(readFileSync(file, 'utf8'), label);
  if (draft.version !== opts.version) refuse(`${label} is the draft of ${draft.version}, not ${opts.version}`);
  const override = loadOverride(changelogDir(), draft.version);
  if (override) draft.title = override.title;
  draft.store = override?.store ?? storeTexts(draft, draft.version);
  const text = serializeDraft(draft);
  parseDraft(text, label);
  writeFileSync(file, text);
  console.log(report(draft, label, { override }));
  console.log(`updated the store texts in ${label}`);
}

// releases/flags.json and everything in releases/changelog/: every draft parses, is named after
// its version and has current store texts; pending.json and the overrides parse, and every flag
// and hold they name is in flags.json. The changelog gate runs it, so a draft PR can't land with
// stale "What's new" texts, and a flag can't leave flags.json while an item still waits for it.
function draftsCommand(argv) {
  const { values: opts } = parseArgs({ args: argv, strict: true, options: { dir: { type: 'string' } } });
  const dir = opts.dir ? resolve(opts.dir) : changelogDir();
  const gates = loadGates(resolve(dir, '../flags.json'));
  const names = existsSync(dir) ? readdirSync(dir) : [];
  const keysKnown = (items, label) => {
    for (const item of items) {
      try {
        gateOf(item, gates);
      } catch (error) {
        if (error instanceof NoteError) refuse(`${label}: "${item.en}": ${error.message}`);
        throw error;
      }
    }
  };
  const overrides = names.filter((f) => f.endsWith('.override.md'));
  for (const f of overrides) {
    const version = OVERRIDE_FILE.exec(f)[1];
    if (!isVersion(version)) refuse(`${relative(process.cwd(), join(dir, f)) || f}: name it <version>.override.md (MAJOR.MINOR.PATCH)`);
    const override = loadOverride(dir, version);
    const closed = closedInPublic(override, gates);
    if (closed.length) refuse(`${override.label} would publish what is held back:\n  ${closed.join('\n  ')}`);
  }
  const pending = loadPending(dir);
  const drafts = draftFileNames(names);
  for (const f of drafts) {
    const label = relative(process.cwd(), join(dir, f)) || f;
    const draft = parseDraft(readFileSync(join(dir, f), 'utf8'), label);
    if (f !== `${draft.version}.json`) refuse(`${label} holds version ${draft.version}; name it ${draft.version}.json`);
    keysKnown(draft.held ?? [], label);
    if (!draft.held && pending.items.length) refuse(`${label} has no "held" (a draft from before job 40) while ${PENDING_FILE} has items; redraft it with --force`);
    const closed = closedInPublic(draft, gates);
    if (closed.length) refuse(`${label} would publish what is held back; redraft with --force (or fix releases/flags.json):\n  ${closed.join('\n  ')}`);
    const override = loadOverride(dir, draft.version);
    const stale = staleStoreTexts(draft, draft.version, override);
    if (stale.length) refuse(staleMessage(label, stale, draft.version, override));
  }
  keysKnown(pending.items, relative(process.cwd(), join(dir, PENDING_FILE)) || PENDING_FILE);
  const rewords = loadRewords(dir);
  console.log(`changelog drafts: ${drafts.length} checked, ${overrides.length} overrides, ${pending.items.length} pending items, ${rewords.items.length} rewords`);
}

function checkCommand(argv) {
  const { values: opts } = parseArgs({ args: argv, strict: true, options: { file: { type: 'string' } } });
  const message = readFileSync(opts.file ?? 0, 'utf8');
  const note = parseNote(message);
  if (note === null) {
    console.error('no "## Changelog" section');
    process.exit(3);
  }
  if (note !== 'none') checkGates(note, loadGates(resolve(repoRoot(), 'releases/flags.json')));
  const gated = (i) => (i.flag || i.hold ? ` (${gateLabel(i)})` : '');
  console.log(note === 'none' ? 'changelog: none (nothing users see)' : `changelog: ${note.map((i) => `${i.category}${gated(i)}: ${i.en}`).join(' | ')}`);
}

function notesCommand(argv) {
  const { values: opts } = parseArgs({ args: argv, strict: true, options: { lang: { type: 'string' }, sha: { type: 'string' }, 'previous-sha': { type: 'string', default: '' } } });
  if (!Object.hasOwn(NOTES_WORDS, opts.lang ?? '')) refuse('--lang is de or en');
  if (opts.sha === undefined) refuse('--sha is required');
  console.log(testerNotes({ lang: opts.lang, previous: opts['previous-sha'], sha: commitOf(opts.sha, '--sha') }));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, ...rest] = process.argv.slice(2);
  const commands = { check: checkCommand, draft: draftCommand, store: storeCommand, drafts: draftsCommand, notes: notesCommand };
  try {
    if (!commands[command]) refuse(`unknown command ${command ?? '(none)'}; usage: changelog.mjs check|draft|store|drafts|notes (see the comment at the top)`);
    commands[command](rest);
  } catch (error) {
    if (!(error instanceof Refusal || error instanceof NoteError || error instanceof RecordError || error.code?.startsWith('ERR_PARSE_ARGS'))) throw error;
    console.error(`changelog: ${error.message}`);
    process.exit(1);
  }
}
