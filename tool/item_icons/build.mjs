#!/usr/bin/env node
// Writes the item icon table (job 147) from tool/item_icons/<domain>.tsv: the app's bundled copy and
// the remote copy snacklist.app serves, then runs tool/item_icons/samples/*.tsv through the same
// matcher the app runs (ItemIcons in app/lib/list/list_view/item_icon.dart), and records the icon of
// every name in supabase/classifier/*.tsv in classifier-sweep.tsv, so a table change shows what it
// does to real names in the diff ("Lorbeer" once got 🍺 from "beer"). Node only, no packages.
//   node tool/item_icons/build.mjs            writes the files
//   node tool/item_icons/build.mjs --check    writes nothing, exits 1 when a file differs, a sample
//                                             fails or the entries changed without a new REVISION;
//                                             fails when it cannot read origin/main (the lint gate
//                                             fetches it) unless ITEM_ICONS_NO_MAIN=1
//   node tool/item_icons/build.mjs --samples  validates the TSVs and the samples only
//   --src <dir> reads <dir>/*.tsv, <dir>/samples/*.tsv and <dir>/REVISION; --out <dir> writes under <dir>
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');

const DART = 'app/lib/list/list_view/item_icons.g.dart';
const JSON_FILE = 'site/public/data/item-icons.v1.json';
const SWEEP = 'tool/item_icons/classifier-sweep.tsv';
const CLASSIFIER = 'supabase/classifier';
const STOP = '-';
const FORM = /^=?[a-z]+( [a-z]+){0,2}$/;
// Three-letter words that are safe as the head of a compound ("Pfefferminztee", "Sonnenblumenöl");
// every other form of up to three letters must be whole-word only.
const SAFE_SHORT_HEADS = new Set(['eis', 'tee', 'oel', 'mus']);

const option = (name) => {
  const i = process.argv.indexOf(name);
  return i < 0 ? undefined : process.argv[i + 1];
};
const src = option('--src') ?? here;
const out = option('--out') ?? root;
const checkOnly = process.argv.includes('--check');
const samplesOnly = process.argv.includes('--samples');

export function foldName(name) {
  return name.trim().toLowerCase().replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss').replace(/\s+/g, ' ');
}

/** Data lines of a TSV file as [line number, columns]. */
function rows(file) {
  return readFileSync(file, 'utf8').split('\n').map((text, i) => [i + 1, text]).filter(([, text]) =>
    text.trim() !== '' && !text.startsWith('#')
  ).map(([line, text]) => [line, text.replace(/\r$/, '').split('\t')]);
}

const tsvs = (dir) =>
  existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.tsv') && f !== 'emoji.tsv' && f !== 'classifier-sweep.tsv').sort() : [];

function readEmoji() {
  return new Set(rows(join(here, 'emoji.tsv')).map(([, cols]) => cols[0]));
}

/**
 * Every form of every source TSV as one entries map (folded form, `=` kept, to an emoji or `''` for
 * a stop), or the list of errors with file:line.
 */
export function readSources(dir, emoji) {
  const errors = [];
  const entries = new Map();
  const seen = new Map();
  const stats = { rows: 0, forms: 0, stops: 0 };
  for (const name of tsvs(dir)) {
    for (const [line, cols] of rows(join(dir, name))) {
      const at = `${relative(process.cwd(), join(dir, name))}:${line}`;
      if (cols.length < 2 || cols.length > 3) {
        errors.push(`${at}: expected <forms><TAB><emoji>[<TAB><note>], got ${cols.length} column(s)`);
        continue;
      }
      const [forms = '', value = ''] = cols;
      if (value !== STOP && !emoji.has(value)) {
        errors.push(`${at}: "${value}" is not in tool/item_icons/emoji.tsv (or "-" for no icon)`);
      }
      stats.rows++;
      if (value === STOP) stats.stops++;
      for (const raw of forms.split('|')) {
        const form = foldName(raw);
        const bare = form.replace(/^=/, '');
        if (!FORM.test(form) || bare.replaceAll(' ', '').length < 2) {
          errors.push(`${at}: form "${raw}" folds to "${form}": want 2+ letters a-z, 1 to 3 words, optional leading =`);
          continue;
        }
        if (form.startsWith('=') && bare.includes(' ')) {
          errors.push(`${at}: "${raw}": a phrase always matches whole words, drop the =`);
          continue;
        }
        if (!form.startsWith('=') && !bare.includes(' ') && bare.length <= 3 && !SAFE_SHORT_HEADS.has(bare)) {
          errors.push(`${at}: "${raw}" is short: write "=${bare}" so it never matches inside a compound`);
          continue;
        }
        const first = seen.get(bare);
        if (first?.at === at) continue;
        if (first !== undefined) {
          errors.push(`${at}: "${raw}" duplicates "${first.raw}" at ${first.at}`);
          continue;
        }
        seen.set(bare, { raw, at });
        entries.set(form, value === STOP ? '' : value);
        stats.forms++;
      }
    }
  }
  return { errors, entries, stats };
}

/** The matcher of ItemIcons.emojiFor: an emoji, or null for the fallback glyph. */
export function matcher(entries) {
  const phrases = new Map();
  const whole = new Map();
  const heads = new Map();
  for (const [key, value] of entries) {
    if (key.includes(' ')) phrases.set(key, value);
    else if (key.startsWith('=')) whole.set(key.slice(1), value);
    else {
      whole.set(key, value);
      heads.set(key, value);
    }
  }
  return (name) => {
    const words = foldName(name).split(/[^a-z]+/).filter((w) => w !== '');
    let i = 0;
    next: while (i < words.length) {
      for (const n of [3, 2]) {
        if (i + n > words.length) continue;
        const value = phrases.get(words.slice(i, i + n).join(' '));
        if (value === undefined) continue;
        if (value === '') {
          i += n;
          continue next;
        }
        return value;
      }
      const w = words[i] ?? '';
      i++;
      const value = whole.get(w);
      if (value === '') continue;
      if (value !== undefined) return value;
      for (let s = 3; s <= w.length - 3; s++) {
        const head = heads.get(w.slice(s));
        if (head === '') break;
        if (head !== undefined) return head;
      }
    }
    return null;
  };
}

/** Every sample that the matcher gets wrong, as "file:line: ..." lines, and the number checked. */
export function checkSamples(dir, match, emoji) {
  const failures = [];
  let count = 0;
  const samples = join(dir, 'samples');
  for (const name of tsvs(samples)) {
    for (const [line, cols] of rows(join(samples, name))) {
      const at = `${relative(process.cwd(), join(samples, name))}:${line}`;
      const [item = '', expected = ''] = cols;
      if (cols.length !== 2 || (expected !== STOP && !emoji.has(expected))) {
        failures.push(`${at}: expected <name><TAB><emoji from emoji.tsv or ->`);
        continue;
      }
      count++;
      const got = match(item) ?? STOP;
      if (got !== expected) failures.push(`${at}: "${item}" wants ${expected}, gets ${got}`);
    }
  }
  return { failures, count };
}

const sorted = (entries) => [...entries].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

function dart(entries, revision) {
  const body = entries.length === 0
    ? '{}'
    : `{\n${entries.map(([k, v]) => `  '${k}': '${v}',\n`).join('')}}`;
  return `// GENERATED from tool/item_icons/*.tsv by tool/item_icons/build.mjs. Do not edit.

/// The revision of [itemIconEntries]; a remote table applies only when newer.
const itemIconsRevision = ${revision};

/// Folded item forms to their emoji, \`''\` for none: \`=\` marks a whole word.
const itemIconEntries = <String, String>${body};
`;
}

/** Every item name in the classifier's data, by folded name: brands alone and with their product. */
export function classifierNames(dir) {
  const names = new Map();
  const files = { brands: [0, 'brand'], dictionary: [0], sweep: [0], synonyms: [0, 1], wordlist: [0] };
  // Every language's words and exam (job 470): dictionary.en.tsv, expected.en.tsv.
  for (const file of readdirSync(dir).sort()) {
    const language = /^((?:dictionary|expected)\.[a-z]{2})\.tsv$/.exec(file);
    if (language) files[language[1]] = [0];
  }
  for (const [file, columns] of Object.entries(files)) {
    for (const [, cols] of rows(join(dir, `${file}.tsv`))) {
      const found = columns.map((c) => c === 'brand' ? (cols[1] ? `${cols[0]} ${cols[1]}` : '') : cols[c] ?? '');
      for (const name of found.map((n) => n.trim()).filter((n) => n !== '')) names.set(foldName(name), name);
    }
  }
  return [...names].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([, name]) => name);
}

const sweep = (names, match) =>
  '# Generated by tool/item_icons/build.mjs: every name in supabase/classifier/*.tsv and its icon (- = the\n' +
  '# fallback). Review the diff whenever the tables change; a wrong icon here is a wrong icon on a list.\n' +
  names.map((name) => `${name}\t${match(name) ?? STOP}\n`).join('');

const json = (entries, revision) =>
  `${JSON.stringify({ schema: 1, revision, entries: Object.fromEntries(entries) }, null, 2)}\n`;

/**
 * The entries and revision of origin/main's JSON, null when origin/main has no table yet, or
 * 'no-ref' when git cannot read origin/main at all (a shallow CI checkout).
 */
function mainTable() {
  try {
    execFileSync('git', ['rev-parse', '--verify', '--quiet', 'origin/main^{commit}'], { cwd: root, stdio: 'ignore' });
  } catch {
    return 'no-ref';
  }
  try {
    const text = execFileSync('git', ['show', `origin/main:${JSON_FILE}`], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const parsed = JSON.parse(text);
    return { revision: parsed.revision, entries: JSON.stringify(parsed.entries) };
  } catch {
    return null;
  }
}

function main() {
  const emoji = readEmoji();
  const { errors, entries, stats } = readSources(src, emoji);
  if (errors.length > 0) {
    for (const e of errors) console.error(e);
    console.error(`item icons: ${errors.length} error(s) in the source TSVs`);
    return 1;
  }
  const { failures, count } = checkSamples(src, matcher(entries), emoji);
  const distinct = new Set([...entries.values()].filter((v) => v !== '')).size;
  console.log(
    `item icons: ${stats.rows} rows, ${stats.forms} forms, ${distinct} distinct emoji, ${stats.stops} stops; ` +
      `${count - failures.length}/${count} samples pass`,
  );
  for (const f of failures) console.error(f);
  if (samplesOnly) return failures.length > 0 ? 1 : 0;

  const revisionText = readFileSync(join(src, 'REVISION'), 'utf8').trim();
  const revision = Number(revisionText);
  if (!/^[1-9][0-9]*$/.test(revisionText)) {
    console.error(`${join(src, 'REVISION')}: want a positive integer, got "${revisionText}"`);
    return 1;
  }
  const table = sorted(entries);
  const outputs = [[DART, dart(table, revision)], [JSON_FILE, json(table, revision)]];
  if (src === here) outputs.push([SWEEP, sweep(classifierNames(join(root, CLASSIFIER)), matcher(entries))]);
  let stale = failures.length;
  for (const [path, content] of outputs) {
    const file = join(out, path);
    if (existsSync(file) && readFileSync(file, 'utf8') === content) continue;
    if (checkOnly) {
      console.error(
        path === SWEEP
          ? `${path} is stale: the icons of classifier names changed; run node tool/item_icons/build.mjs and review git diff ${path}`
          : `${path} is stale: run node tool/item_icons/build.mjs`,
      );
      stale++;
    } else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, content);
      console.log(`wrote ${path}`);
    }
  }
  const onMain = checkOnly && out === root ? mainTable() : null;
  if (onMain === 'no-ref' && process.env.ITEM_ICONS_NO_MAIN !== '1') {
    console.error(
      'cannot read origin/main, so REVISION is unchecked: git fetch origin main (or ITEM_ICONS_NO_MAIN=1 to skip)',
    );
    stale++;
  } else if (onMain && onMain !== 'no-ref' && onMain.entries !== JSON.stringify(Object.fromEntries(table)) && !(revision > onMain.revision)) {
    console.error(
      `tool/item_icons/REVISION is ${revision}, as on origin/main, but the entries changed: raise it to ${
        onMain.revision + 1
      } so apps pick the new table up`,
    );
    stale++;
  }
  return stale > 0 ? 1 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
