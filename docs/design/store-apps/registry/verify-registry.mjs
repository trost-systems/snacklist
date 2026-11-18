#!/usr/bin/env node
// Checks retailers.json against the stores and the retailers' own association files.
// node verify-registry.mjs [--offline] [--only DE,AT]
import process from 'node:process';
import { readFileSync } from 'node:fs';

const file = new URL('./retailers.json', import.meta.url);
const registry = JSON.parse(readFileSync(file, 'utf8'));
const args = process.argv.slice(2);
const offline = args.includes('--offline');
const onlyArg = args[args.indexOf('--only') + 1];
const only = args.includes('--only') && onlyArg ? new Set(onlyArg.split(',')) : null;

const STATUSES = new Set(['verified', 'todo', 'no-app']);
const PKG = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const UA = 'Mozilla/5.0 (snacklist registry check; read-only)';

function schemaErrors(e, chains) {
  const err = [];
  const chain = chains.get(e.chain);
  if (!chain) err.push(`unknown chain ${e.chain}`);
  else if (!chain.countries.includes(e.country)) err.push(`${e.country} not in chain ${e.chain} countries`);
  if (!/^[A-Z]{2}$/.test(e.country ?? '')) err.push('country is not ISO alpha-2');
  if (typeof e.name !== 'string' || !e.name) err.push('name missing');
  if (!STATUSES.has(e.status)) err.push(`status ${e.status}`);
  if (!DATE.test(e.verified ?? '')) err.push('verified is not a date');
  if (!Array.isArray(e.sources) || e.sources.length === 0 || !e.sources.every((s) => s.startsWith('https://'))) err.push('sources must be https URLs');
  if (typeof e.web !== 'string' && e.web !== null) err.push('web must be a host or null');
  if (e.status === 'no-app') {
    if (e.app !== null) err.push('no-app entry has an app');
    if (!e.note) err.push('no-app needs a note with the evidence');
    return err;
  }
  const a = e.app;
  if (!a) return [...err, 'app missing'];
  if (typeof a.name !== 'string' || !a.name) err.push('app.name missing');
  if (a.android !== null && !PKG.test(a.android)) err.push(`bad android package ${a.android}`);
  if (a.ios !== null && !/^\d+$/.test(a.ios)) err.push(`bad ios id ${a.ios}`);
  if (a.universalLink !== null && !/^https:\/\/[^/]+\//.test(a.universalLink)) err.push('universalLink must be an https URL');
  const fb = a.storeFallback ?? {};
  const wantAndroid = a.android ? `market://details?id=${a.android}` : null;
  const wantIos = a.ios ? `itms-apps://apps.apple.com/app/id${a.ios}` : null;
  if ((fb.android ?? null) !== wantAndroid) err.push(`storeFallback.android should be ${wantAndroid}`);
  if ((fb.ios ?? null) !== wantIos) err.push(`storeFallback.ios should be ${wantIos}`);
  if (e.status === 'verified' && (!a.android || !a.ios)) err.push('verified needs both store ids');
  if (e.status === 'todo' && !e.note) err.push('todo needs a note with the reason');
  if (a.universalLink === null && !e.note) err.push('null universalLink needs a reason in note');
  return err;
}

const chains = new Map(registry.chains.map((c) => [c.chain, c]));
const entries = registry.entries.filter((e) => !only || only.has(e.country));
const schema = entries.map((e) => ({ e, errors: schemaErrors(e, chains) }));
const seen = new Set();
for (const { e, errors } of schema) {
  const k = `${e.chain}/${e.country}`;
  if (seen.has(k)) errors.push(`duplicate ${k}`);
  seen.add(k);
}

if (offline) {
  let bad = 0;
  for (const { e, errors } of schema) if (errors.length) { bad++; console.log(`${e.country} ${e.chain}: ${errors.join('; ')}`); }
  const by = (s) => entries.filter((e) => e.status === s).length;
  console.log(`offline schema check: ${entries.length} entries, ${bad} with errors (no-app ${by('no-app')})`);
  console.log(`verified ${by('verified')}, todo ${by('todo')}, failed ${bad}`);
  process.exit(bad ? 1 : 0);
}

const get = async (url) => {
  for (let i = 0; ; i++) {
    try {
      const r = await fetch(url, { headers: { 'user-agent': UA }, signal: AbortSignal.timeout(20000) });
      return { status: r.status, body: await r.text() };
    } catch (err) {
      if (i === 2) return { status: 0, body: String(err) };
    }
  }
};
const memo = (fn) => { const m = new Map(); return (k) => { if (!m.has(k)) m.set(k, fn(k)); return m.get(k); }; };

const lookupCountry = memo(async (cc) => {
  const ids = entries.filter((e) => e.country === cc && e.app?.ios).map((e) => e.app.ios);
  if (!ids.length) return new Map();
  const r = await get(`https://itunes.apple.com/lookup?id=${ids.join(',')}&country=${cc.toLowerCase()}`);
  if (r.status !== 200) return null;
  return new Map(JSON.parse(r.body).results.map((x) => [String(x.trackId), x]));
});

const aasa = memo(async (host) => {
  const r = await get(`https://app-site-association.cdn-apple.com/a/v1/${host}`);
  if (r.status !== 200) return { error: `HTTP ${r.status}` };
  try { return { details: JSON.parse(r.body).applinks?.details ?? [] }; } catch { return { error: 'unparseable JSON' }; }
});

const assetLinks = memo(async (host) => {
  const r = await get(`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://${host}&relation=delegate_permission/common.handle_all_urls`);
  if (r.status !== 200) return { error: `HTTP ${r.status}` };
  return { packages: new Set((JSON.parse(r.body).statements ?? []).map((s) => s.target?.androidApp?.packageName).filter(Boolean)) };
});

const glob = (p) => new RegExp(`^${p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`);

function claims(detail, url) {
  if (detail.components) {
    for (const c of detail.components) {
      if (!glob(c['/'] ?? '*').test(url.pathname)) continue;
      const q = c['?'];
      if (typeof q === 'string' && !glob(q).test(url.search.slice(1))) continue;
      if (q && typeof q === 'object' && !Object.entries(q).every(([k, v]) => url.searchParams.has(k) && glob(v).test(url.searchParams.get(k)))) continue;
      if (!glob(c['#'] ?? '*').test(url.hash.slice(1))) continue;
      return !c.exclude;
    }
    return false;
  }
  for (const p of detail.paths ?? []) {
    if (p.startsWith('NOT ')) { if (glob(p.slice(4)).test(url.pathname)) return false; }
    else if (glob(p).test(url.pathname + url.search)) return true;
  }
  return false;
}

const appDetails = (details, bundleId) => details.filter((d) => (d.appIDs ?? [d.appID]).some((id) => id?.slice(id.indexOf('.') + 1) === bundleId));
const pathCount = (ds) => ds.reduce((n, d) => n + (d.components ?? d.paths ?? []).length, 0);
const decode = (s) => s.replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
const has = (title, name) => title.toLowerCase().includes(name.toLowerCase());

async function check(e, errors) {
  const r = { e, fails: [...errors], todo: [], cells: {} };
  if (e.status === 'no-app' || !e.app) return r;
  const a = e.app;
  let bundleId = null;
  if (a.ios) {
    const m = await lookupCountry(e.country);
    const x = m?.get(a.ios);
    if (!m) r.todo.push('itunes lookup failed');
    else if (!x) r.fails.push(`ios ${a.ios} not in the ${e.country} storefront`);
    else {
      bundleId = x.bundleId;
      r.cells.ios = `"${x.trackName}" ${x.bundleId}${has(x.trackName, a.name) ? '' : ' (name differs)'}`;
    }
  } else r.todo.push('ios null');
  if (a.android) {
    const p = await get(`https://play.google.com/store/apps/details?id=${a.android}&hl=en&gl=${e.country}`);
    if (p.status === 404) r.fails.push(`play 404 for ${a.android}`);
    else if (p.status !== 200) { r.todo.push(`play: blocked (HTTP ${p.status})`); r.cells.play = 'blocked'; }
    else {
      const title = decode(p.body.match(/<title[^>]*>([^<]*)<\/title>/)?.[1] ?? '').replace(/ - Apps on Google Play$/, '');
      // Reviews and other apps' descriptions sit in <script> data and quote this phrase too.
      const gone = /(isn['’]t|not) available in your country/i.test(p.body.replace(/<script[\s\S]*?<\/script>/g, ''));
      if (!has(title, a.name)) r.fails.push(`play title "${title}" lacks "${a.name}"`);
      if (gone) r.fails.push(`play says not available in ${e.country}`);
      r.cells.play = `"${title}" ${gone ? 'unavailable' : 'listed (country availability unverified)'}`;
    }
  } else r.todo.push('android null');

  const ul = a.universalLink ? new URL(a.universalLink) : null;
  const host = ul?.host ?? e.web;
  if (host) {
    const [ap, dal] = await Promise.all([aasa(host), assetLinks(host)]);
    if (ap.error) r.cells.aasa = `${host} aasa ${ap.error}`;
    else if (bundleId) {
      const ds = appDetails(ap.details, bundleId);
      r.cells.aasa = ds.length ? `${host} aasa lists ${bundleId} (${pathCount(ds)} patterns)` : `${host} aasa lacks ${bundleId}`;
      if (ul) {
        const ok = ds.some((d) => claims(d, ul));
        r.cells.aasa += ok ? `, claims ${ul.pathname}${ul.search}` : `, does NOT claim ${ul.pathname}${ul.search}`;
        if (!ok) r.fails.push(`universalLink ${a.universalLink} not claimed for ${bundleId}`);
      }
    }
    if (ul && ap.error) r.fails.push(`universalLink host ${host}: aasa ${ap.error}`);
    r.cells.dal = dal.error ? `assetlinks ${dal.error}` : a.android && dal.packages.has(a.android) ? `assetlinks lists ${a.android}` : 'assetlinks: package not listed';
  }
  return r;
}

const results = [];
const queue = [...schema];
await Promise.all(Array.from({ length: 4 }, async () => {
  for (let job = queue.shift(); job; job = queue.shift()) results.push(await check(job.e, job.errors));
}));
results.sort((x, y) => entries.indexOf(x.e) - entries.indexOf(y.e));

let verified = 0, todo = 0, failed = 0, noApp = 0;
for (const r of results) {
  const { e } = r;
  let verdict;
  if (r.fails.length) { verdict = 'FAIL'; failed++; }
  else if (e.status === 'no-app') { verdict = 'NO-APP'; noApp++; }
  else if (e.status === 'verified' && !r.todo.length) { verdict = 'OK'; verified++; }
  else { verdict = 'TODO'; todo++; }
  console.log(`${e.country} ${e.chain.padEnd(12)} ${verdict.padEnd(6)} ${e.app?.name ?? '-'}`);
  for (const k of ['ios', 'play', 'aasa', 'dal']) if (r.cells[k]) console.log(`     ${k.padEnd(4)} ${r.cells[k]}`);
  if (e.app) console.log(`     link ${e.app.universalLink ?? 'none'}`);
  for (const f of r.fails) console.log(`     FAIL ${f}`);
  for (const t of r.todo) console.log(`     todo ${t}`);
}
console.log(`no-app ${noApp} (counted apart)`);
console.log(`verified ${verified}, todo ${todo}, failed ${failed}`);
process.exit(failed ? 1 : 0);
