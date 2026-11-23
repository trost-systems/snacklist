// The public release record, releases/releases.json (releases/README.md): its format, checked here
// for the site build, the site tests and scripts/release/record.mjs, which writes it.
import { Buffer } from 'node:buffer';

export const CHANNELS = ['public'];
const STORES = ['app_store', 'play', 'web'];
const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const SHA = /^[0-9a-f]{40}$/;
const LANGUAGES = ['de', 'en'];
export const CATEGORIES = ['new', 'improved', 'fixed'];
// A feature flag or hold key in a `flag:` / `hold:` line and in releases/flags.json (job 40).
export const GATE_KEY = /^[a-z0-9][a-z0-9._-]*$/;
export const ROLLOUTS = ['full', 'partial', 'off'];
// Items held back from the public changelog until their gate opens (docs/CHANGELOG.md, "Gated items").
export const PENDING_FILE = 'pending.json';
export const REWORDS_FILE = 'rewords.json';

// "What's new" limits per language. Play: "up to 500 Unicode characters per language" (Play Console
// Help, answer 9859348). App Store: "Limited to 4000 characters" (App Store Connect Help, Platform
// version information); fastlane's pilot enforces it as 4000 UTF-8 bytes, the strictest reading, so
// that is what counts here.
export const STORE_LIMITS = {
  'app_store': { limit: 4000, unit: 'UTF-8 bytes', length: (text) => Buffer.byteLength(text.normalize('NFC'), 'utf8') },
  play: { limit: 500, unit: 'Unicode characters', length: (text) => [...text.normalize('NFC')].length },
};

export class RecordError extends Error {}

export const isVersion = (value) => typeof value === 'string' && SEMVER.test(value);

// Strict MAJOR.MINOR.PATCH only: store versions have no pre-release or build part.
export function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] - pb[i];
  return 0;
}

export const isDate = (value) =>
  typeof value === 'string' && DATE.test(value) && !Number.isNaN(Date.parse(value)) && new Date(`${value}T00:00:00Z`).toISOString().startsWith(value);

// Day 0 is project.day_zero, the date of the repository's first commit.
export const dayNumber = (dayZero, date) => Math.round((Date.parse(date) - Date.parse(dayZero)) / 86_400_000);

const sortReleases = (releases) => [...releases].sort((a, b) => compareVersions(a.version, b.version));

function checker(source) {
  const fail = (path, reason) => {
    throw new RecordError(`${source}: ${path}: ${reason}`);
  };
  const object = (value, path, keys) => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) fail(path, 'must be an object');
    for (const key of Object.keys(value)) if (!keys.includes(key)) fail(`${path}.${key}`, `unknown field (allowed: ${keys.join(', ')})`);
    for (const key of keys) if (!(key in value)) fail(`${path}.${key}`, 'missing');
    return value;
  };
  const array = (value, path) => (Array.isArray(value) ? value : fail(path, 'must be an array'));
  const string = (value, path) => (typeof value === 'string' ? value : fail(path, 'must be a string'));
  const nullableString = (value, path) => (value === null || typeof value === 'string' ? value : fail(path, 'must be a string or null'));
  const boolean = (value, path) => (typeof value === 'boolean' ? value : fail(path, 'must be true or false'));
  const count = (value, path) => (Number.isInteger(value) && value >= 0 ? value : fail(path, `must be a whole number >= 0, got ${JSON.stringify(value)}`));
  const matches = (ok, value, path, what) => (ok ? value : fail(path, `must be ${what}, got ${JSON.stringify(value)}`));
  return { fail, object, array, string, nullableString, boolean, count, matches };
}

const texts = (c, value, path, { nonEmpty, multiline = false }) => {
  c.object(value, path, LANGUAGES);
  for (const lang of LANGUAGES) {
    const text = c.string(value[lang], `${path}.${lang}`);
    if (nonEmpty && text.trim() === '') c.fail(`${path}.${lang}`, 'must not be empty');
    if (!multiline && /[\r\n]/.test(text)) c.fail(`${path}.${lang}`, 'must be one line');
  }
  return value;
};

const itemFields = (c, item, at) => {
  texts(c, { de: item.de, en: item.en }, at, { nonEmpty: true });
  c.matches(item.pr === null || (Number.isInteger(item.pr) && item.pr > 0), item.pr, `${at}.pr`, 'a PR number or null');
  c.matches(SHA.test(c.string(item.sha, `${at}.sha`)), item.sha, `${at}.sha`, 'a full commit sha (40 hex)');
};
const gateKey = (c, value, path) => c.matches(typeof value === 'string' && GATE_KEY.test(value), value, path, 'a key ([a-z0-9][a-z0-9._-]*)');

// An item held back by its flag or hold: in a draft's `held` and in pending.json.
function checkHeld(c, items, path) {
  c.array(items, path).forEach((item, i) => {
    const at = `${path}[${i}]`;
    c.object(item, at, ['category', 'de', 'en', 'flag', 'hold', 'pr', 'sha']);
    c.matches(CATEGORIES.includes(item.category), item.category, `${at}.category`, `one of ${CATEGORIES.join(', ')}`);
    itemFields(c, item, at);
    for (const k of ['flag', 'hold']) if (item[k] !== null) gateKey(c, item[k], `${at}.${k}`);
    if (item.flag === null && item.hold === null) c.fail(at, 'has neither a flag nor a hold, so nothing holds it back');
  });
  return items;
}

// The user-facing changelog of one release (releases/README.md, "changelog"): in a release of the
// record, and in a draft file releases/changelog/<version>.json before the release.
function checkChangelog(c, changelog, path, keys = ['title', 'items', 'store']) {
  c.object(changelog, path, keys);
  texts(c, changelog.title, `${path}.title`, { nonEmpty: false });
  c.object(changelog.items, `${path}.items`, CATEGORIES);
  for (const category of CATEGORIES) {
    c.array(changelog.items[category], `${path}.items.${category}`).forEach((item, i) => {
      const at = `${path}.items.${category}[${i}]`;
      // Job 40: an item that waited for a flag or hold keeps it, for tracing; the site never shows it.
      c.object(item, at, ['de', 'en', 'pr', 'sha', ...['flag', 'hold'].filter((k) => k in item)]);
      itemFields(c, item, at);
      for (const k of ['flag', 'hold']) if (k in item) gateKey(c, item[k], `${at}.${k}`);
    });
  }
  c.object(changelog.store, `${path}.store`, Object.keys(STORE_LIMITS));
  for (const [store, { limit, unit, length }] of Object.entries(STORE_LIMITS)) {
    texts(c, changelog.store[store], `${path}.store.${store}`, { nonEmpty: true, multiline: true });
    for (const lang of LANGUAGES) {
      const n = length(changelog.store[store][lang]);
      if (n > limit) c.fail(`${path}.store.${store}.${lang}`, `is ${n} ${unit}, above the store's limit of ${limit}`);
    }
  }
  return changelog;
}

// Optional stats of a release (job 105): the commits a bot or AI assistant took part in, and the
// lines of code at the release commit (scripts/release/loc.mjs, releases/README.md).
export const STATS_OPTIONAL = ['automated_commits', 'loc'];

function checkLoc(c, loc, path) {
  c.object(loc, path, ['total', 'languages']);
  c.count(loc.total, `${path}.total`);
  let sum = 0;
  let previous = null;
  const seen = new Set();
  c.array(loc.languages, `${path}.languages`).forEach((entry, i) => {
    const at = `${path}.languages[${i}]`;
    c.object(entry, at, ['language', 'files', 'lines']);
    c.matches(typeof entry.language === 'string' && entry.language.trim() !== '', entry.language, `${at}.language`, 'a language name');
    if (seen.has(entry.language)) c.fail(`${at}.language`, `${entry.language} is listed twice`);
    seen.add(entry.language);
    c.count(entry.files, `${at}.files`);
    sum += c.count(entry.lines, `${at}.lines`);
    if (previous && entry.lines > previous.lines) c.fail(at, `languages are sorted by lines, most first; ${entry.language} has more than ${previous.language}`);
    previous = entry;
  });
  if (sum !== loc.total) c.fail(`${path}.total`, `is ${loc.total}, but the languages add up to ${sum}`);
  return loc;
}

// Parses and checks the record; throws RecordError naming `source` and the bad field.
export function parseRecord(text, source = 'releases/releases.json') {
  const c = checker(source);
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new RecordError(`${source}: not valid JSON (${error.message})`);
  }
  c.object(data, '$', ['project', 'identities', 'releases']);
  const project = c.object(data.project, 'project', ['name', 'repo', 'day_zero']);
  c.matches(project.name === 'Snacklist', project.name, 'project.name', '"Snacklist"');
  c.matches(/^[\w.-]+\/[\w.-]+$/.test(c.string(project.repo, 'project.repo')), project.repo, 'project.repo', 'owner/name');
  c.matches(isDate(project.day_zero), project.day_zero, 'project.day_zero', 'a date (YYYY-MM-DD)');

  const emails = new Map();
  c.array(data.identities, 'identities').forEach((identity, i) => {
    const path = `identities[${i}]`;
    c.object(identity, path, ['name', 'github', 'bot', 'emails']);
    c.string(identity.name, `${path}.name`);
    c.nullableString(identity.github, `${path}.github`);
    c.boolean(identity.bot, `${path}.bot`);
    c.array(identity.emails, `${path}.emails`).forEach((email, j) => {
      c.matches(typeof email === 'string' && email === email.toLowerCase() && email.includes('@'), email, `${path}.emails[${j}]`, 'a lower-case e-mail address');
      if (emails.has(email)) c.fail(`${path}.emails[${j}]`, `${email} is also listed under ${emails.get(email)}`);
      emails.set(email, path);
    });
  });

  const releases = c.array(data.releases, 'releases');
  const previous = {};
  releases.forEach((release, i) => {
    const path = `releases[${i}]`;
    const fields = ['version', 'channel', 'date', 'day', 'build', 'sha', 'previous_sha', 'stores', 'stats', 'notes'];
    // Job 39: `changelog` is optional, so releases recorded before it stay valid.
    c.object(release, path, 'changelog' in release ? [...fields, 'changelog'] : fields);
    c.matches(isVersion(release.version), release.version, `${path}.version`, 'a version MAJOR.MINOR.PATCH');
    c.matches(CHANNELS.includes(release.channel), release.channel, `${path}.channel`, `one of ${CHANNELS.join(', ')}`);
    c.matches(isDate(release.date), release.date, `${path}.date`, 'a date (YYYY-MM-DD)');
    c.matches(release.day === dayNumber(project.day_zero, release.date), release.day, `${path}.day`, `${dayNumber(project.day_zero, release.date)} (days from project.day_zero to date)`);
    c.matches(release.day >= 0, release.date, `${path}.date`, `on or after project.day_zero ${project.day_zero}`);
    c.matches(Number.isInteger(release.build) && release.build > 0, release.build, `${path}.build`, 'a whole number > 0');
    c.matches(SHA.test(c.string(release.sha, `${path}.sha`)), release.sha, `${path}.sha`, 'a full commit sha (40 hex)');
    c.object(release.stores, `${path}.stores`, STORES);
    for (const store of STORES) c.boolean(release.stores[store], `${path}.stores.${store}`);
    // Job 105: `automated_commits` and `loc` are optional, so releases recorded before them stay valid.
    const statFields = ['commits', 'additions', 'deletions', 'files_changed', 'contributors'];
    const stats = c.object(release.stats, `${path}.stats`, [...statFields, ...STATS_OPTIONAL.filter((k) => Object.hasOwn(Object(release.stats), k))]);
    for (const key of ['commits', 'additions', 'deletions', 'files_changed']) c.count(stats[key], `${path}.stats.${key}`);
    if ('automated_commits' in stats && c.count(stats.automated_commits, `${path}.stats.automated_commits`) > stats.commits) {
      c.fail(`${path}.stats.automated_commits`, `${stats.automated_commits} is more than the release's ${stats.commits} commits`);
    }
    if ('loc' in stats) checkLoc(c, stats.loc, `${path}.stats.loc`);
    c.array(stats.contributors, `${path}.stats.contributors`).forEach((person, j) => {
      const at = `${path}.stats.contributors[${j}]`;
      c.object(person, at, ['name', 'github', 'commits', 'additions', 'deletions', 'bot']);
      c.string(person.name, `${at}.name`);
      c.nullableString(person.github, `${at}.github`);
      for (const key of ['commits', 'additions', 'deletions']) c.count(person[key], `${at}.${key}`);
      c.boolean(person.bot, `${at}.bot`);
    });
    const notes = c.object(release.notes, `${path}.notes`, ['de', 'en']);
    c.string(notes.de, `${path}.notes.de`);
    c.string(notes.en, `${path}.notes.en`);
    if ('changelog' in release) checkChangelog(c, release.changelog, `${path}.changelog`);

    const prev = previous[release.channel];
    if (prev) {
      if (compareVersions(release.version, prev.version) <= 0) c.fail(`${path}.version`, `${release.version} must be above ${prev.version}; releases are sorted by version, oldest first, and versions are unique`);
      if (release.date < prev.date) c.fail(`${path}.date`, `${release.date} is before ${prev.version}'s date ${prev.date}`);
      if (release.build <= prev.build) c.fail(`${path}.build`, `${release.build} must be above ${prev.version}'s build ${prev.build}`);
      c.matches(release.previous_sha === prev.sha, release.previous_sha, `${path}.previous_sha`, `${prev.version}'s sha ${prev.sha}`);
    } else {
      c.matches(release.previous_sha === null, release.previous_sha, `${path}.previous_sha`, `null (the first ${release.channel} release counts from the root commit)`);
    }
    previous[release.channel] = release;
  });
  return data;
}

export const DRAFT_STATUS = 'draft';

// A changelog draft, releases/changelog/<version>.json, written by scripts/release/changelog.mjs.
export function parseDraft(text, source) {
  const c = checker(source);
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new RecordError(`${source}: not valid JSON (${error.message})`);
  }
  // Job 40: `held` lists the items whose gate is closed; drafts from before it have none.
  checkChangelog(c, data, '$', ['version', 'status', 'generated_from', 'title', 'items', 'store', ...('held' in data ? ['held'] : [])]);
  if ('held' in data) checkHeld(c, data.held, '$.held');
  c.matches(isVersion(data.version), data.version, '$.version', 'a version MAJOR.MINOR.PATCH');
  c.matches(data.status === DRAFT_STATUS, data.status, '$.status', `"${DRAFT_STATUS}"`);
  c.object(data.generated_from, '$.generated_from', ['previous_sha', 'sha']);
  c.matches(data.generated_from.previous_sha === null || SHA.test(data.generated_from.previous_sha), data.generated_from.previous_sha, '$.generated_from.previous_sha', 'a full commit sha or null');
  c.matches(SHA.test(data.generated_from.sha), data.generated_from.sha, '$.generated_from.sha', 'a full commit sha (40 hex)');
  return data;
}

const parseJson = (text, source) => {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new RecordError(`${source}: not valid JSON (${error.message})`);
  }
};

// A flag's lowest app version, which scripts/posthog/sync-flags.ts turns into PostHog conditions
// (job 332, docs/ANALYTICS.md): "1.4.0" or "1.4.0+1420" for every platform, or an object with
// `default` and a version per platform. plan.ts parses the same shape.
const REQUIREMENT = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(\+[1-9]\d*)?$/;
const MIN_VERSION_PLATFORMS = ['android', 'ios', 'linux', 'macos', 'web', 'windows'];
const checkMinVersion = (c, value, path) => {
  const requirement = (v, at) => c.matches(typeof v === 'string' && REQUIREMENT.test(v), v, at, 'a version "MAJOR.MINOR.PATCH" or "MAJOR.MINOR.PATCH+BUILD"');
  if (typeof value === 'string') return requirement(value, path);
  if (typeof value !== 'object' || value === null || Array.isArray(value)) c.fail(path, 'must be a version or an object with "default"');
  if (!('default' in value)) c.fail(`${path}.default`, 'missing (the version for every other platform)');
  for (const [platform, v] of Object.entries(value)) {
    if (platform !== 'default' && !MIN_VERSION_PLATFORMS.includes(platform)) c.fail(`${path}.${platform}`, `unknown platform (allowed: default, ${MIN_VERSION_PLATFORMS.join(', ')})`);
    requirement(v, `${path}.${platform}`);
  }
  return value;
};

// releases/flags.json: the rollout of each feature flag and the state of each hold. An item is
// public only when its flag is `full` and its hold `released`. `match` lists words that, while
// the hold is not released, hold back every item mentioning them (the Alexa skill).
export function parseGates(text, source = 'releases/flags.json') {
  const c = checker(source);
  const data = parseJson(text, source);
  c.object(data, '$', ['flags', 'holds']);
  c.object(data.flags, 'flags', Object.keys(data.flags ?? {}));
  for (const [key, flag] of Object.entries(data.flags)) {
    gateKey(c, key, `flags.${key}`);
    c.object(flag, `flags.${key}`, ['rollout', 'note', ...['min_version', 'tester_group'].filter((k) => typeof flag === 'object' && flag !== null && k in flag)]);
    c.matches(ROLLOUTS.includes(flag.rollout), flag.rollout, `flags.${key}.rollout`, `one of ${ROLLOUTS.join(', ')}`);
    c.string(flag.note, `flags.${key}.note`);
    if ('tester_group' in flag) c.matches(typeof flag.tester_group === 'string' && /^[a-z0-9][a-z0-9-]*$/.test(flag.tester_group), flag.tester_group, `flags.${key}.tester_group`, 'a tester group name (lowercase, digits, hyphens)');
    if ('min_version' in flag) checkMinVersion(c, flag.min_version, `flags.${key}.min_version`);
  }
  c.object(data.holds, 'holds', Object.keys(data.holds ?? {}));
  for (const [key, hold] of Object.entries(data.holds)) {
    gateKey(c, key, `holds.${key}`);
    c.object(hold, `holds.${key}`, ['released', 'note', ...('match' in hold ? ['match'] : [])]);
    c.boolean(hold.released, `holds.${key}.released`);
    c.string(hold.note, `holds.${key}.note`);
    if ('match' in hold) c.array(hold.match, `holds.${key}.match`).forEach((w, i) => c.matches(typeof w === 'string' && /^[\p{L}\p{N}][\p{L}\p{N} -]*$/u.test(w), w, `holds.${key}.match[${i}]`, 'a word'));
  }
  return data;
}

// releases/changelog/pending.json: the items held back so far, oldest first.
export function parsePending(text, source = `releases/changelog/${PENDING_FILE}`) {
  const c = checker(source);
  const data = parseJson(text, source);
  c.object(data, '$', ['items']);
  checkHeld(c, data.items, 'items');
  return data;
}

// releases/changelog/rewords.json (job 213): new wording for an item already on main, whose commit
// message can't change, or `drop: true` to take an item out that users never saw. `item` counts the note's items from 1; `why` is for the reviewer.
export function parseRewords(text, source = `releases/changelog/${REWORDS_FILE}`) {
  const c = checker(source);
  const data = parseJson(text, source);
  c.object(data, '$', ['items']);
  const seen = new Set();
  c.array(data.items, 'items').forEach((reword, i) => {
    const at = `items[${i}]`;
    // `drop: true` takes the item out instead of rewording it: no `de` and `en` then.
    c.object(reword, at, ['sha', 'item', 'why', ...(reword?.drop === true ? ['drop'] : ['de', 'en'])]);
    c.matches(SHA.test(c.string(reword.sha, `${at}.sha`)), reword.sha, `${at}.sha`, 'a full commit sha (40 hex)');
    c.matches(Number.isInteger(reword.item) && reword.item > 0, reword.item, `${at}.item`, 'the item\'s place in the note, from 1');
    if (c.string(reword.why, `${at}.why`).trim() === '') c.fail(`${at}.why`, 'must not be empty');
    if (reword.drop !== true) texts(c, { de: reword.de, en: reword.en }, at, { nonEmpty: true });
    const key = `${reword.sha}#${reword.item}`;
    if (seen.has(key)) c.fail(at, `rewords item ${reword.item} of ${reword.sha.slice(0, 7)} a second time`);
    seen.add(key);
  });
  return data;
}

// The draft files in releases/changelog/: every .json but pending.json and rewords.json.
export const draftFileNames = (files) => files.filter((f) => f.endsWith('.json') && f !== PENDING_FILE && f !== REWORDS_FILE);

export function serializeRecord(record) {
  return `${JSON.stringify({ ...record, releases: sortReleases(record.releases) }, null, 2)}\n`;
}

// Public releases, oldest first.
export const publicReleases = (record) => sortReleases(record.releases.filter((r) => r.channel === 'public'));
