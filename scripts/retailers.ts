// The retailer registry (supabase/retailers/retailers.json, job 313) and the migration rows it
// becomes. The lint gate runs --check: the file's schema, and that the newest migration with a
// RETAILERS_BEGIN block holds the rows this file generates, and that the app's analytics allow-list
// (app/lib/analytics/events.dart) names exactly its chains and countries, and that the app's copy
// (app/lib/list/retailer_registry.g.dart, the onboarding chips before sign-in, job 321) is current.
// Usage:
//   deno run --allow-read scripts/retailers.ts --check
//   deno run --allow-read --allow-write scripts/retailers.ts --dart
//     the app's copy written again
//   deno run --allow-read --allow-write scripts/retailers.ts --migration [migration.sql]
//     a new timestamped migration, or the block replaced in a migration that is not on main yet
//   deno run --allow-read --allow-net scripts/retailers.ts --verify [--only DE,AT]
//     every app against the stores and the retailers' association files (online, not in CI)

export const REGISTRY = 'supabase/retailers/retailers.json';
export const MIGRATIONS = 'supabase/migrations';
export const EVENTS = 'app/lib/analytics/events.dart';
export const DART = 'app/lib/list/retailer_registry.g.dart';
export const COVERAGE = 'supabase/retailers/coverage.md';

/** The strings of the Dart set literal `const <name> = {...};` in [dart]. */
export function dartSet(dart: string, name: string): Set<string> | undefined {
  const body = new RegExp(`const ${name} = \\{([^}]*)\\};`).exec(dart)?.[1];
  return body === undefined ? undefined : new Set([...body.matchAll(/'([^']*)'/g)].map((m) => m[1] ?? ''));
}

function sameSet(a: ReadonlySet<string>, b: ReadonlySet<string>): boolean {
  return a.size === b.size && [...a].every((v) => b.has(v));
}
const BEGIN = '-- RETAILERS_BEGIN';
const END = '-- RETAILERS_END';

export type RetailerApp = {
  name: string;
  android: string;
  ios: string;
  universalLink: string | null;
  /** The URL scheme the app registers (`lidlplus`), with its source in the entry's note; iOS opens its bare root. */
  scheme: string | null;
};
export type Entry = {
  chain: string;
  country: string;
  name: string;
  /** What a chip and a store made from it are called, when shorter than [name] ("Netto"). */
  short?: string;
  aliases: string[];
  web: string | null;
  apps: RetailerApp[];
  status: 'verified' | 'no-app';
  verified: string;
  sources: string[];
  note: string;
};
export type Registry = { version: 2; updated: string; entries: Entry[] };

const CHAIN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const COUNTRY = /^[A-Z]{2}$/;
const ALIAS = /^[a-z0-9]+( [a-z0-9]+)*$/;
const HOST = /^[a-z0-9-]+(\.[a-z0-9-]+)+$/;
const PACKAGE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ENTRY_KEYS = ['chain', 'country', 'name', 'short', 'aliases', 'web', 'apps', 'status', 'verified', 'sources', 'note'];
const APP_KEYS = ['name', 'android', 'ios', 'universalLink', 'scheme'];
const SCHEME = /^[a-z][a-z0-9+.-]*$/;
/** Schemes that belong to the browser, the stores or the system, never to a chain's app. */
const NOT_AN_APP_SCHEME = new Set(['http', 'https', 'itms', 'itms-apps', 'itms-appss', 'market', 'mailto', 'tel', 'sms', 'file', 'data', 'javascript', 'about', 'intent']);

type Json = Record<string, unknown>;
const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const isString = (v: unknown): v is string => typeof v === 'string' && v !== '';
const strings = (v: unknown): v is string[] => Array.isArray(v) && v.every((s) => typeof s === 'string');

function parseApp(raw: unknown, at: string, problems: string[]): RetailerApp | undefined {
  if (!isObject(raw)) return void problems.push(`${at}: not an object`);
  const extra = Object.keys(raw).filter((k) => !APP_KEYS.includes(k));
  if (extra.length > 0) problems.push(`${at}: unknown keys ${extra.join(', ')}`);
  const { name, android, ios, universalLink, scheme } = raw;
  const before = problems.length;
  if (!isString(name)) problems.push(`${at}: name missing`);
  if (typeof android !== 'string' || !PACKAGE.test(android)) problems.push(`${at}: bad android package ${android}`);
  if (typeof ios !== 'string' || !/^\d+$/.test(ios)) problems.push(`${at}: bad ios id ${ios}`);
  if (universalLink !== null && (typeof universalLink !== 'string' || !/^https:\/\/[^/]+\//.test(universalLink))) {
    problems.push(`${at}: universalLink must be an https URL or null`);
  }
  if (scheme !== null && (typeof scheme !== 'string' || !SCHEME.test(scheme) || NOT_AN_APP_SCHEME.has(scheme))) {
    problems.push(`${at}: scheme must be the app's own lower-case URL scheme without "://", or null`);
  }
  if (problems.length > before || !isString(name) || typeof android !== 'string' || typeof ios !== 'string') {
    return undefined;
  }
  return {
    name,
    android,
    ios,
    universalLink: typeof universalLink === 'string' ? universalLink : null,
    scheme: typeof scheme === 'string' ? scheme : null,
  };
}

function parseEntry(raw: unknown, index: number, problems: string[]): Entry | undefined {
  if (!isObject(raw)) return void problems.push(`entries[${index}]: not an object`);
  const at = `entries[${index}] ${raw.country}/${raw.chain}`;
  const before = problems.length;
  const extra = Object.keys(raw).filter((k) => !ENTRY_KEYS.includes(k));
  if (extra.length > 0) problems.push(`${at}: unknown keys ${extra.join(', ')}`);
  const { chain, country, name, short, aliases, web, apps, status, verified, sources, note } = raw;
  if (typeof chain !== 'string' || !CHAIN.test(chain)) problems.push(`${at}: chain must be like "aldi-sued"`);
  if (typeof country !== 'string' || !COUNTRY.test(country)) problems.push(`${at}: country is not ISO alpha-2`);
  if (!isString(name)) problems.push(`${at}: name missing`);
  if (short !== undefined && (!isString(short) || short === name)) {
    problems.push(`${at}: short is a name shorter than name, or left out`);
  }
  if (!strings(aliases) || !aliases.every((a) => ALIAS.test(a) && a.length >= 3)) {
    problems.push(`${at}: aliases are lower-case words without accents, three characters or more`);
  }
  if (web !== null && (typeof web !== 'string' || !HOST.test(web))) problems.push(`${at}: web must be a host or null`);
  if (status !== 'verified' && status !== 'no-app') problems.push(`${at}: status is verified or no-app`);
  if (typeof verified !== 'string' || !DATE.test(verified)) problems.push(`${at}: verified is not a date`);
  if (!strings(sources) || sources.length === 0 || !sources.every((s) => s.startsWith('https://'))) {
    problems.push(`${at}: sources must be https URLs`);
  }
  if (!isString(note)) problems.push(`${at}: note with the evidence missing`);
  const parsed = Array.isArray(apps)
    ? apps.map((a, i) => parseApp(a, `${at} apps[${i}]`, problems))
    : (problems.push(`${at}: apps must be a list`), []);
  const list = parsed.filter((a): a is RetailerApp => a !== undefined);
  if (status === 'verified' && parsed.length === 0) problems.push(`${at}: a verified entry lists an app`);
  if (status === 'no-app' && parsed.length > 0) problems.push(`${at}: a no-app entry lists none`);
  if (new Set(list.map((a) => a.android)).size !== list.length) problems.push(`${at}: an android package twice`);
  if (
    problems.length > before || typeof chain !== 'string' || typeof country !== 'string' || !isString(name) ||
    !strings(aliases) || (web !== null && typeof web !== 'string') || (status !== 'verified' && status !== 'no-app') ||
    typeof verified !== 'string' || !strings(sources) || !isString(note)
  ) return undefined;
  return {
    chain,
    country,
    name,
    ...(isString(short) ? { short } : {}),
    aliases,
    web,
    apps: list,
    status,
    verified,
    sources,
    note,
  };
}

/** The registry, or an error naming every problem in it. */
export function parseRegistry(raw: unknown): Registry {
  const problems: string[] = [];
  if (!isObject(raw)) throw new Error(`${REGISTRY}: not a JSON object`);
  if (raw.version !== 2) problems.push('version must be 2');
  if (typeof raw.updated !== 'string' || !DATE.test(raw.updated)) problems.push('updated is not a date');
  const list = Array.isArray(raw.entries) ? raw.entries : (problems.push('entries must be a list'), []);
  const entries = list.map((e, i) => parseEntry(e, i, problems)).filter((e): e is Entry => e !== undefined);
  const seen = new Set<string>();
  for (const e of entries) {
    const key = `${e.country}/${e.chain}`;
    if (seen.has(key)) problems.push(`${key} twice`);
    seen.add(key);
  }
  if (problems.length > 0 || typeof raw.updated !== 'string') {
    throw new Error(`${REGISTRY}:\n  ${problems.join('\n  ')}`);
  }
  return { version: 2, updated: raw.updated, entries };
}

/** The migration block that makes public.retailers hold exactly the registry's rows. */
export async function dataBlock(registry: Registry): Promise<string> {
  const rows = registry.entries.map(({ chain, country, name, aliases, web, apps }) =>
    JSON.stringify({ chain, country, name, aliases, web, apps })
  );
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(rows.join('\n')));
  const sha = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return [
    `${BEGIN} sha256=${sha}`,
    `-- Generated by scripts/retailers.ts from ${REGISTRY}; edit the JSON, not this block.`,
    'with registry as (',
    '  select * from jsonb_to_recordset($retailers$[',
    rows.join(',\n'),
    ']$retailers$::jsonb) as r (chain text, country text, name text, aliases text[], web text, apps jsonb)',
    '), upserted as (',
    '  insert into public.retailers (chain, country, name, aliases, web, apps)',
    '  select chain, country, name, aliases, web, apps from registry',
    '  on conflict (chain, country) do update',
    '    set name = excluded.name, aliases = excluded.aliases, web = excluded.web, apps = excluded.apps',
    '  returning 1',
    ')',
    'delete from public.retailers r',
    'where not exists (select from registry g where g.chain = r.chain and g.country = r.country);',
    END,
  ].join('\n');
}

const dartString = (s: string): string => `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;

type DartValue = string | { call: string; args: [string, DartValue][] } | DartValue[];

/** [value] at [indent] after [prefix] and before [suffix], as dart format's tall style lays it out: on one line when it fits in 80. */
function dartLines(value: DartValue, indent: string, prefix: string, suffix: string): string[] {
  const flat = (v: DartValue): string =>
    typeof v === 'string'
      ? v
      : Array.isArray(v)
      ? `[${v.map(flat).join(', ')}]`
      : `${v.call}(${v.args.map(([k, a]) => `${k}: ${flat(a)}`).join(', ')})`;
  const line = `${indent}${prefix}${flat(value)}${suffix}`;
  if (typeof value === 'string' || line.length <= 80) return [line];
  const inner = `${indent}  `;
  if (Array.isArray(value)) {
    return [`${indent}${prefix}[`, ...value.flatMap((v) => dartLines(v, inner, '', ',')), `${indent}]${suffix}`];
  }
  return [
    `${indent}${prefix}${value.call}(`,
    ...value.args.flatMap(([k, a]) => dartLines(a, inner, `${k}: `, ',')),
    `${indent})${suffix}`,
  ];
}

/** How the iPhone app opens each app (job 335): a universal link, the URL scheme, both, or only the App Store. */
export function coverageFile(registry: Registry): string {
  const apps = registry.entries.flatMap((e) => e.apps.map((a) => ({ e, a })));
  const unique = new Map(apps.map(({ a }) => [a.android, a]));
  const direct = [...unique.values()].filter((a) => a.universalLink !== null || a.scheme !== null).length;
  const cell = (s: string) => s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
  return [
    '# How the iPhone app opens each chain app',
    '',
    `Generated by \`scripts/retailers.ts --coverage\` from \`${REGISTRY}\`; edit the JSON, not this file.`,
    'The iPhone app tries the universal link, then the bare root of the URL scheme, then opens the App Store',
    '(`app/lib/list/store_app.dart`, `storeAppPlan`). Android starts the package and needs neither.',
    '',
    `${direct} of ${unique.size} apps open directly on an iPhone when installed.`,
    '',
    '| Country | Chain | App | Universal link | Scheme | Source (the entry\'s note) |',
    '| --- | --- | --- | --- | --- | --- |',
    ...apps.map(({ e, a }) =>
      `| ${e.country} | ${e.chain} | ${cell(a.name)} | ${a.universalLink ?? ''} | ${a.scheme === null ? '' : `\`${a.scheme}://\``} | ${cell(e.note)} |`
    ),
    '',
  ].join('\n');
}

/** The app's copy of the registry: what the onboarding chips and their suggestions read before sign-in. */
export function dartFile(registry: Registry): string {
  const entries: DartValue = registry.entries.map((e) => ({
    call: 'Retailer',
    args: [
      ['chain', dartString(e.chain)],
      ['country', dartString(e.country)],
      ['name', dartString(e.name)],
      ...(e.short === undefined ? [] : [['short', dartString(e.short)] as [string, DartValue]]),
      ...(e.aliases.length === 0 ? [] : [['aliases', e.aliases.map(dartString)] as [string, DartValue]]),
      ...(e.apps.length === 0 ? [] : [[
        'apps',
        e.apps.map((a): DartValue => ({
          call: 'RetailerApp',
          args: [
            ['name', dartString(a.name)],
            ['android', dartString(a.android)],
            ['ios', dartString(a.ios)],
            ...(a.universalLink === null ? [] : [['universalLink', dartString(a.universalLink)] as [string, DartValue]]),
            ...(a.scheme === null ? [] : [['scheme', dartString(a.scheme)] as [string, DartValue]]),
          ],
        })),
      ] as [string, DartValue]]),
    ],
  }));
  const [, ...list] = dartLines(entries, '', '', ';');
  return [
    '// Generated by scripts/retailers.ts --dart from',
    `// ${REGISTRY}; edit the JSON, not this file.`,
    '',
    "import 'package:family_groceries/list/retailer.dart';",
    '',
    '/// The registry as the app was built with it, in its order: per country the',
    '/// order the onboarding chips show (most stores first).',
    'const retailerRegistry = <Retailer>[',
    ...list,
    '',
  ].join('\n');
}

/** The RETAILERS_BEGIN..END block of a migration, or undefined. */
export function blockOf(sql: string): string | undefined {
  const start = sql.indexOf(BEGIN);
  const end = sql.indexOf(END, start);
  return start < 0 || end < 0 ? undefined : sql.slice(start, end + END.length);
}

/** The newest migration with a block, by file name. */
export function newestWithBlock(migrations: ReadonlyMap<string, string>): [string, string] | undefined {
  const named = [...migrations].filter(([, sql]) => blockOf(sql) !== undefined).sort(([a], [b]) => (a < b ? -1 : 1));
  return named.at(-1);
}

/** The migrations by file name. */
export async function readMigrations(): Promise<Map<string, string>> {
  const files = new Map<string, string>();
  for await (const f of Deno.readDir(MIGRATIONS)) {
    if (f.isFile && f.name.endsWith('.sql')) files.set(f.name, await Deno.readTextFile(`${MIGRATIONS}/${f.name}`));
  }
  return files;
}

/** The repository's registry, parsed. */
export async function readRegistry(): Promise<Registry> {
  return parseRegistry(JSON.parse(await Deno.readTextFile(REGISTRY)));
}

async function check(): Promise<number> {
  const registry = await readRegistry();
  const newest = newestWithBlock(await readMigrations());
  const want = await dataBlock(registry);
  const fix = 'run "deno run --allow-read --allow-write scripts/retailers.ts --migration" ' +
    '(a new migration; one already on main is never edited)';
  if (newest === undefined) {
    console.error(`retailers: no migration in ${MIGRATIONS} has a ${BEGIN} block: ${fix}`);
    return 1;
  }
  const [file, sql] = newest;
  if (blockOf(sql) !== want) {
    console.error(`retailers: ${REGISTRY} differs from the rows in ${MIGRATIONS}/${file}: ${fix}`);
    return 1;
  }
  const events = await Deno.readTextFile(EVENTS);
  for (
    const [name, want] of [
      ['retailerChains', new Set(registry.entries.map((e) => e.chain))],
      ['retailerCountries', new Set(registry.entries.map((e) => e.country))],
    ] as const
  ) {
    const have = dartSet(events, name);
    if (have === undefined || !sameSet(have, want)) {
      console.error(
        `retailers: ${name} in ${EVENTS} must list exactly ${[...want].sort().join(', ')} ` +
          '(store_app_opened admits registry ids only)',
      );
      return 1;
    }
  }
  const dart = await Deno.readTextFile(DART).catch(() => '');
  if (dart !== dartFile(registry)) {
    console.error(
      `retailers: ${DART} differs from ${REGISTRY}: run "deno run --allow-read --allow-write scripts/retailers.ts --dart"`,
    );
    return 1;
  }
  const coverage = await Deno.readTextFile(COVERAGE).catch(() => '');
  if (coverage !== coverageFile(registry)) {
    console.error(
      `retailers: ${COVERAGE} differs from ${REGISTRY}: run "deno run --allow-read --allow-write scripts/retailers.ts --coverage"`,
    );
    return 1;
  }
  console.error(`retailers: ${registry.entries.length} entries, ${MIGRATIONS}/${file}, ${DART} and ${COVERAGE} current`);
  return 0;
}

async function migration(target: string | undefined): Promise<number> {
  const block = await dataBlock(await readRegistry());
  if (target !== undefined) {
    const sql = await Deno.readTextFile(target);
    const old = blockOf(sql);
    if (old === undefined) throw new Error(`${target} has no ${BEGIN} ... ${END} block`);
    await Deno.writeTextFile(target, sql.replace(old, () => block));
    console.error(`retailers: block replaced in ${target}`);
    return 0;
  }
  const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
  const file = `${MIGRATIONS}/${stamp}_retailers_data.sql`;
  await Deno.writeTextFile(
    file,
    `-- The retailer registry's rows as ${REGISTRY} has them on ${stamp.slice(0, 8)}.\n${block}\n`,
  );
  console.error(`retailers: wrote ${file}`);
  return 0;
}

// The online check, ported from job 314's verify-registry.mjs (docs/design/store-apps/registry).

const UA = 'Mozilla/5.0 (snacklist registry check; read-only)';

async function get(url: string): Promise<{ status: number; body: string }> {
  for (let attempt = 0;; attempt++) {
    try {
      const r = await fetch(url, { headers: { 'user-agent': UA }, signal: AbortSignal.timeout(20000) });
      return { status: r.status, body: await r.text() };
    } catch (error) {
      if (attempt === 2) return { status: 0, body: String(error) };
    }
  }
}

function memo<T>(fn: (key: string) => Promise<T>): (key: string) => Promise<T> {
  const cache = new Map<string, Promise<T>>();
  return (key) => {
    const hit = cache.get(key);
    if (hit !== undefined) return hit;
    const made = fn(key);
    cache.set(key, made);
    return made;
  };
}

type Detail = { appIDs?: unknown; appID?: unknown; components?: unknown; paths?: unknown };
type Aasa = { error: string } | { details: Detail[] };
type AssetLinks = { error: string } | { packages: Set<string> };

const glob = (p: string) =>
  new RegExp(`^${p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`);
const text = (v: unknown, fallback: string) => (typeof v === 'string' ? v : fallback);

function claims(detail: Detail, url: URL): boolean {
  if (Array.isArray(detail.components)) {
    for (const c of detail.components) {
      if (!isObject(c)) continue;
      if (!glob(text(c['/'], '*')).test(url.pathname)) continue;
      const q = c['?'];
      if (typeof q === 'string' && !glob(q).test(url.search.slice(1))) continue;
      if (
        isObject(q) &&
        !Object.entries(q).every(([k, v]) => url.searchParams.has(k) && glob(text(v, '*')).test(url.searchParams.get(k) ?? ''))
      ) continue;
      if (!glob(text(c['#'], '*')).test(url.hash.slice(1))) continue;
      return !c.exclude;
    }
    return false;
  }
  for (const p of strings(detail.paths) ? detail.paths : []) {
    if (p.startsWith('NOT ')) {
      if (glob(p.slice(4)).test(url.pathname)) return false;
    } else if (glob(p).test(url.pathname + url.search)) return true;
  }
  return false;
}

function appDetails(details: Detail[], bundleId: string): Detail[] {
  return details.filter((d) => {
    const ids = Array.isArray(d.appIDs) ? d.appIDs : [d.appID];
    return ids.some((id) => typeof id === 'string' && id.slice(id.indexOf('.') + 1) === bundleId);
  });
}

const decode = (s: string) => s.replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
const has = (title: string, name: string) => title.toLowerCase().includes(name.toLowerCase());

async function verify(only: Set<string> | undefined): Promise<number> {
  const entries = (await readRegistry()).entries.filter((e) => only === undefined || only.has(e.country));
  const lookup = memo(async (cc: string) => {
    const ids = entries.filter((e) => e.country === cc).flatMap((e) => e.apps.map((a) => a.ios));
    if (ids.length === 0) return new Map<string, Json>();
    const r = await get(`https://itunes.apple.com/lookup?id=${ids.join(',')}&country=${cc.toLowerCase()}`);
    if (r.status !== 200) return undefined;
    const body: unknown = JSON.parse(r.body);
    const results = isObject(body) && Array.isArray(body.results) ? body.results.filter(isObject) : [];
    return new Map(results.map((x) => [String(x.trackId), x]));
  });
  const aasa = memo(async (host: string): Promise<Aasa> => {
    const r = await get(`https://app-site-association.cdn-apple.com/a/v1/${host}`);
    if (r.status !== 200) return { error: `HTTP ${r.status}` };
    try {
      const body: unknown = JSON.parse(r.body);
      const applinks = isObject(body) && isObject(body.applinks) ? body.applinks : {};
      return { details: Array.isArray(applinks.details) ? applinks.details.filter(isObject) : [] };
    } catch {
      return { error: 'unparseable JSON' };
    }
  });
  const assetLinks = memo(async (host: string): Promise<AssetLinks> => {
    const r = await get(
      `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://${host}` +
        '&relation=delegate_permission/common.handle_all_urls',
    );
    if (r.status !== 200) return { error: `HTTP ${r.status}` };
    const body: unknown = JSON.parse(r.body);
    const statements = isObject(body) && Array.isArray(body.statements) ? body.statements.filter(isObject) : [];
    const packages = statements.map((s) => isObject(s.target) && isObject(s.target.androidApp) ? s.target.androidApp.packageName : undefined);
    return { packages: new Set(packages.filter((p): p is string => typeof p === 'string')) };
  });

  async function checkApp(e: Entry, a: RetailerApp): Promise<{ lines: string[]; fails: string[]; todo: string[] }> {
    const lines: string[] = [];
    const fails: string[] = [];
    const todo: string[] = [];
    let bundleId: string | undefined;
    const found = await lookup(e.country);
    const x = found?.get(a.ios);
    if (found === undefined) todo.push('itunes lookup failed');
    else if (x === undefined) fails.push(`ios ${a.ios} not in the ${e.country} storefront`);
    else {
      bundleId = text(x.bundleId, '');
      const track = text(x.trackName, '');
      lines.push(`ios  "${track}" ${bundleId}${has(track, a.name) ? '' : ' (name differs)'}`);
    }
    const p = await get(`https://play.google.com/store/apps/details?id=${a.android}&hl=en&gl=${e.country}`);
    if (p.status === 404) fails.push(`play 404 for ${a.android}`);
    else if (p.status !== 200) todo.push(`play: blocked (HTTP ${p.status})`);
    else {
      const title = decode(p.body.match(/<title[^>]*>([^<]*)<\/title>/)?.[1] ?? '').replace(/ - Apps on Google Play$/, '');
      // Reviews and other apps' descriptions sit in <script> data and quote this phrase too.
      const gone = /(isn['’]t|not) available in your country/i.test(p.body.replace(/<script[\s\S]*?<\/script>/g, ''));
      if (!has(title, a.name)) fails.push(`play title "${title}" lacks "${a.name}"`);
      if (gone) fails.push(`play says not available in ${e.country}`);
      lines.push(`play "${title}" ${gone ? 'unavailable' : 'listed (country availability unverified)'}`);
    }
    const link = a.universalLink === null ? undefined : new URL(a.universalLink);
    const host = link?.host ?? e.web;
    if (host !== null && host !== undefined) {
      const [apple, google] = await Promise.all([aasa(host), assetLinks(host)]);
      if ('error' in apple) {
        lines.push(`aasa ${host} ${apple.error}`);
        if (link !== undefined) fails.push(`universalLink host ${host}: aasa ${apple.error}`);
      } else if (bundleId !== undefined) {
        const ds = appDetails(apple.details, bundleId);
        let line = ds.length > 0 ? `aasa ${host} lists ${bundleId}` : `aasa ${host} lacks ${bundleId}`;
        if (link !== undefined) {
          const ok = ds.some((d) => claims(d, link));
          line += ok ? `, claims ${link.pathname}${link.search}` : `, does NOT claim ${link.pathname}${link.search}`;
          if (!ok) fails.push(`universalLink ${a.universalLink} not claimed for ${bundleId}`);
        }
        lines.push(line);
      }
      lines.push(
        'error' in google
          ? `dal  assetlinks ${google.error}`
          : google.packages.has(a.android)
          ? `dal  assetlinks lists ${a.android}`
          : 'dal  assetlinks: package not listed',
      );
    }
    lines.push(`link ${a.universalLink ?? 'none'}`, `scheme ${a.scheme ?? 'none'}`);
    return { lines, fails, todo };
  }

  let ok = 0;
  let todo = 0;
  let failed = 0;
  let noApp = 0;
  for (const e of entries) {
    if (e.status === 'no-app') {
      noApp++;
      console.log(`${e.country} ${e.chain.padEnd(12)} NO-APP`);
      continue;
    }
    for (const a of e.apps) {
      const r = await checkApp(e, a);
      const verdict = r.fails.length > 0 ? 'FAIL' : r.todo.length > 0 ? 'TODO' : 'OK';
      if (verdict === 'FAIL') failed++;
      else if (verdict === 'TODO') todo++;
      else ok++;
      console.log(`${e.country} ${e.chain.padEnd(12)} ${verdict.padEnd(6)} ${a.name}`);
      for (const line of r.lines) console.log(`     ${line}`);
      for (const f of r.fails) console.log(`     FAIL ${f}`);
      for (const t of r.todo) console.log(`     todo ${t}`);
    }
  }
  console.log(`apps verified ${ok}, todo ${todo}, failed ${failed}; entries without an app ${noApp}`);
  return failed > 0 ? 1 : 0;
}

if (import.meta.main) {
  const [mode, ...rest] = Deno.args;
  const usage = 'usage: scripts/retailers.ts --check | --migration [file.sql] | --dart | --coverage | --verify [--only DE,AT]';
  let code: number;
  if (mode === '--check') code = await check();
  else if (mode === '--migration') code = await migration(rest[0]);
  else if (mode === '--dart') {
    await Deno.writeTextFile(DART, dartFile(await readRegistry()));
    console.error(`retailers: wrote ${DART}`);
    code = 0;
  } else if (mode === '--coverage') {
    await Deno.writeTextFile(COVERAGE, coverageFile(await readRegistry()));
    console.error(`retailers: wrote ${COVERAGE}`);
    code = 0;
  } else if (mode === '--verify') {
    const only = rest[0] === '--only' && rest[1] !== undefined ? new Set(rest[1].split(',')) : undefined;
    code = await verify(only);
  } else {
    console.error(usage);
    code = 64;
  }
  Deno.exit(code);
}
