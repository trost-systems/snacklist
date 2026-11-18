// Drives both rounds in Chromium and checks what the pages claim. Last line: "all checks passed (N)", else exit 1.
// Usage: node verify.mjs [<repo root or build dir>] [<screenshot dir>] [<playwright dir>] [--write]
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import process from 'node:process';
import { tmpdir } from 'node:os';
import { serve } from './tools/serve.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const write = process.argv.includes('--write');
const root = resolve(args[0] ?? join(here, '../../..'));
const shots = resolve(args[1] ?? join(tmpdir(), 'store-apps-shots'));
const pwDir = args[2] || [join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');
const base = existsSync(join(root, 'store-apps/index.html')) ? '/store-apps/' : '/docs/design/store-apps/';
const dir = join(root, base);
mkdirSync(shots, { recursive: true });

let n = 0;
const fails = [];
const check = (ok, what) => { n += 1; if (!ok) { fails.push(what); console.log(`FAIL ${what}`); } };

// The registry first: schema offline, and every chain the scenes use is a verified entry with the same app and link.
execFileSync('node', [join(dir, 'registry/verify-registry.mjs'), '--offline'], { stdio: 'pipe' });
check(true, 'registry schema');
const registry = JSON.parse(readFileSync(join(dir, 'registry/retailers.json'), 'utf8'));
const { chains } = await import(join(dir, 'data.js'));
for (const [key, c] of Object.entries(chains)) {
  const e = registry.entries.find((x) => `${x.chain}:${x.country}` === key);
  check(e && e.status === 'verified', `${key} is a verified registry entry`);
  check(e?.app?.name === c.app, `${key}: app name "${c.app}" matches the registry ("${e?.app?.name}")`);
  check(Boolean(e?.app?.universalLink) === c.ul, `${key}: has-link ${c.ul} matches the registry`);
}
check(!registry.entries.some((e) => /deutschlandcard|payback/i.test(e.chain)), 'no DeutschlandCard or PAYBACK in the registry');

const { server, url } = await serve(root);
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1700, height: 1000 } });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const open = async (path) => {
  await page.goto(`${url}${base}${path}`);
  await page.waitForSelector('body[data-ready]', { timeout: 15000 });
};

// Every phone on the page: nothing past its edges, no text spilling out of a row, targets of 44 px.
const layout = () => page.evaluate(() => {
  const out = [];
  for (const host of document.querySelectorAll('.host')) {
    const ph = host.querySelector('.phone');
    const z = Number(ph.style.zoom || 1);
    const pr = ph.getBoundingClientRect();
    const id = host.dataset.frame;
    for (const el of ph.querySelectorAll('*')) {
      const r = el.getBoundingClientRect();
      if (!r.width || el.closest('.outside, .map')) continue;
      if (r.right > pr.right + 1 || r.left < pr.left - 1) { out.push(`${id}: ${el.className.baseVal ?? el.className} past the phone's edge`); break; }
    }
    for (const el of ph.querySelectorAll('.iname, .sname, .cnt, .donetext, .strip-app > span, .pickrow b, .crow b, .ssub, .apptag, .card.asks b, .sp-app b')) {
      if (el.scrollWidth > el.clientWidth + 2 && getComputedStyle(el).textOverflow !== 'ellipsis' && !el.matches('.cnt')) out.push(`${id}: "${el.textContent.trim().slice(0, 30)}" spills`);
    }
    for (const el of ph.querySelectorAll('[data-open], [data-menu], .stripopen, .sheet .lrow, .pickrow, .chip, .tact, .caret, .sysalert button')) {
      const r = el.getBoundingClientRect();
      if (r.width && (r.height / z < 43.5 || r.width / z < 43.5)) out.push(`${id}: target ${el.className} ${Math.round(r.width / z)}×${Math.round(r.height / z)}`);
    }
  }
  return out;
});

const settings = [];
for (const lang of ['en', 'de']) for (const theme of ['light', 'dark']) for (const ts of [100, 200, 310]) settings.push({ lang, theme, ts });
const q = (o) => Object.entries(o).filter(([k, v]) => !(k === 'lang' && v === 'en') && !(k === 'theme' && v === 'light') && !(k === 'ts' && v === 100)).map(([k, v]) => `${k}=${v}`).join('&');

// --- Round OS -------------------------------------------------------------------------------------------------------
for (const s of settings) {
  for (const platform of ['ios', 'android']) {
    if (platform === 'android' && (s.theme === 'dark' || s.ts === 200)) continue;
    const qs = q({ ...s, platform });
    await open(`os/?${qs}`);
    for (const p of await layout()) check(false, `OS ${qs}: ${p}`);
    check(true, `OS ${qs} laid out`);
  }
}
await open('os/');
await page.screenshot({ path: join(shots, 'OS-en-light-100.png'), fullPage: true });

// The live phones: what a tap does, per platform and installed state, and which stores have no button.
const expectKind = { ios: { yes: { lidl: 'storeOpen', aldi: 'app' }, no: { lidl: 'store', aldi: 'store' } }, android: { yes: { lidl: 'app', aldi: 'app' }, no: { lidl: 'store', aldi: 'store' } } };
for (const platform of ['ios', 'android']) {
  for (const inst of ['yes', 'no']) {
    for (const opt of ['OS1', 'OS3', 'OS4']) {
      for (const store of ['lidl', 'aldi']) {
        await open(`os/?platform=${platform}&installed=${inst}`);
        const host = page.locator(`[data-frame="${opt}:0"]`);
        let taps = 0;
        const path = opt === 'OS3' ? ['[data-act="go"][data-arg="stores"]', `[data-row="${store}"]`] : opt === 'OS4' ? [`[data-menu="${store}"]`] : [];
        for (const sel of path) { await host.locator(sel).first().click(); taps += 1; }
        await host.locator(`[data-open="${store}"]`).first().click();
        taps += 1;
        const kind = await host.locator('[data-outcome]').getAttribute('data-outcome');
        check(kind === expectKind[platform][inst][store], `${opt} ${platform} installed=${inst}: ${store} opens "${kind}", expected ${expectKind[platform][inst][store]}`);
        const claimed = { OS1: 1, OS3: 3, OS4: 2 }[opt];
        check(taps === claimed, `${opt}: ${taps} taps from the list to the app, page says ${claimed}`);
      }
    }
  }
}
await open('os/');
for (const opt of ['OS1', 'OS2', 'OS4', 'OS5']) {
  const host = page.locator(`[data-option="${opt}"]`);
  check(await host.locator('[data-open="markt"]').count() === 0, `${opt}: the market (no app) never shows an open button`);
}
check(await page.locator('[data-frame="OS3:3"] .appcard').count() === 0, 'OS3: no app card on the market’s screen');
check(await page.locator('[data-frame="OS4:2"] [data-open]').count() === 0, 'OS4: the market’s menu has no open row');
check(await page.locator('[data-frame="OS2:3"] .strip-app').count() === 0, 'OS2: at the market the strip has no app line');
check(await page.locator('[data-frame="OS2:0"] .strip-app').innerText().then((x) => /Lidl Plus/.test(x)), 'OS2: the strip names Lidl Plus at Lidl');
check(await page.locator('[data-frame="OS5:0"] [data-done="dm"]').count() === 1, 'OS5: dm done shows its line');
check(await page.locator('[data-frame="OS5:0"] [data-done="lidl"]').count() === 0, 'OS5: Lidl still in progress, no line');
check(await page.locator('[data-frame="OS5:3"] [data-done="markt"]').count() === 0, 'OS5: the market done keeps a plain header');
// OS5 live: ticking the last two Lidl items turns Lidl into its line.
{
  const host = page.locator('[data-frame="OS5:0"]');
  await host.locator('[data-item="lidl:0"]').click();
  await host.locator('[data-item="lidl:2"]').click();
  check(await host.locator('[data-done="lidl"]').count() === 1, 'OS5 live: the last Lidl tick shows “Lidl done · Open Lidl Plus”');
}
// OS1 live: the header key opens the app, the header itself still folds.
{
  const host = page.locator('[data-frame="OS1:0"]');
  await host.locator('[data-store="lidl"] .shead-hit').click();
  check(await host.locator('[data-item^="lidl:"]').count() === 0, 'OS1 live: a tap on the header folds it');
  check(await host.locator('[data-open="lidl"]').count() === 1, 'OS1 live: the folded header keeps its key');
}

// Measurements at 390 × 844 (the phone), each option against Today in the same state, at 100 %, 200 % and 310 %.
const measured = { OS: {}, SS: {} };
for (const ts of [100, 200, 310]) {
  for (const lang of ['en', 'de']) {
  const m = await page.evaluate(async ({ ts, base, lang }) => {
    const P = await import(`${base}phone.js`);
    const O = await import(`${base}os.js`);
    const today = O.options[0];
    const measure = (opt, over) => {
      const host = document.createElement('div');
      host.style.cssText = 'position:absolute;left:-2000px;top:0';
      document.body.append(host);
      host.innerHTML = P.view(P.initial(opt, { ts, lang, ...over }));
      const ph = host.querySelector('.phone');
      const sc = ph.querySelector('[data-scroll]');
      const band = ph.querySelector('[data-bottom]');
      const top = sc.getBoundingClientRect().top;
      const bottom = band.getBoundingClientRect().top;
      const rows = [...ph.querySelectorAll('.item')].filter((r) => { const b = r.getBoundingClientRect(); return b.top >= top - 0.5 && b.bottom <= bottom + 0.5; }).length;
      const aldi = ph.querySelector('[data-store="aldi"] .sbadge');
      const cut = [...ph.querySelectorAll('.sbadge > span')].filter((e) => e.scrollWidth > e.clientWidth + 1).length;
      const res = { content: Math.round(sc.scrollHeight), band: Math.round(band.getBoundingClientRect().height), rows, cut, aldiBadge: aldi ? Math.round(aldi.getBoundingClientRect().width) : null };
      host.remove();
      return res;
    };
    const out = {};
    for (const opt of O.options.slice(1)) {
      const st = O.measureState(opt);
      const a = measure(opt, st);
      const b = measure(today, st);
      out[opt.id] = { extra: a.content - b.content + (a.band - b.band), rows: a.rows, todayRows: b.rows, cut: a.cut, todayCut: b.cut, aldiBadge: a.aldiBadge, todayAldiBadge: b.aldiBadge, state: Object.keys(st).length ? 'trip' : 'list' };
    }
    return out;
  }, { ts, base, lang });
  measured.OS[lang === 'en' ? ts : `${ts}-de`] = m;
  }
}
for (const [id, v] of Object.entries(measured.OS[100])) console.log(`OS ${id} 100 %: +${v.extra} px, rows ${v.rows} (today ${v.todayRows}), names cut ${v.cut} (today ${v.todayCut}); 310 % de: names cut ${measured.OS['310-de'][id].cut} (today ${measured.OS['310-de'][id].todayCut}), ALDI badge ${measured.OS['310-de'][id].aldiBadge} (today ${measured.OS['310-de'][id].todayAldiBadge})`);

// --- Round SS -------------------------------------------------------------------------------------------------------
const scen = ['migrate', 'new', 'unlisted', 'twocountries', 'country'];
for (const s of settings) {
  for (const sc of scen) {
    if ((s.theme === 'dark' || s.lang === 'de') && s.ts === 200) continue;
    const qs = q({ ...s, scenario: sc });
    await open(`ss/?${qs}`);
    for (const p of await layout()) check(false, `SS ${qs}: ${p}`);
    check(true, `SS ${qs} laid out`);
  }
}
const last = (opt) => page.locator(`[data-option="${opt}"] .host`).last();
for (const sc of scen) {
  await open(`ss/?scenario=${sc}`);
  await page.screenshot({ path: join(shots, `SS-${sc}-en-light-100.png`), fullPage: true });
  for (const opt of ['SS1', 'SS2', 'SS3', 'SS4', 'SS5']) {
    const total = Number(await page.locator(`[data-total="${opt}"]`).innerText());
    measured.SS[opt] = { ...measured.SS[opt], [sc]: total };
    const end = last(opt);
    const linked = await end.locator('[data-linked]').evaluateAll((els) => els.map((e) => e.dataset.linked));
    const own = await end.locator('[data-own]').count();
    if (sc === 'migrate') {
      if (opt === 'SS2' || opt === 'SS5') check(await end.locator('[data-open]').count() === 3, `${opt} migrate: the list ends with 3 app keys (dm, Lidl, Aldi), never the market`);
      else check(['dm:DE', 'lidl:DE', 'aldi-sued:DE'].every((k) => linked.includes(k)), `${opt} migrate: dm, Lidl and Aldi linked (${linked})`);
    }
    if (sc === 'new') check(opt === 'SS5' ? (await end.locator('[data-card="suggest"]').count()) === 1 : linked.includes('rewe:DE') || (await end.locator('[data-chaincard="rewe:DE"]').count()) === 1, `${opt} new: REWE ends linked or offered`);
    if (sc === 'unlisted') check(own > 0 || (await end.locator('[data-row="hof"]').count()) === 1 || (await end.locator('.fieldtext').first().innerText()) === 'Hofladen Sonnenwiese', `${opt} unlisted: the farm shop ends as an own store`);
    if (sc === 'twocountries') check(linked.includes('aldi-sued:AT') && linked.includes('lidl:DE'), `${opt} two countries: Hofer (AT) next to Lidl (DE) (${linked})`);
    if (sc === 'country') check(linked.includes('carrefour:FR') && linked.includes('dm:DE'), `${opt} country: Carrefour (FR) added, dm keeps Germany (${linked})`);
  }
}
await open('ss/?scenario=twocountries');
check(await page.locator('[data-option="SS2"] [data-suggest] [data-chain="aldi-sued:AT"]').count() === 1, 'SS2: “Hof” suggests Austria’s Hofer without a setting');
check(await page.locator('[data-option="SS1"] [data-chain="aldi-sued:AT"]').count() >= 1, 'SS1: Austria’s list has Hofer');
await open('ss/?scenario=country');
check(await page.locator('[data-option="SS1"] [data-chain="aldi-nord:FR"]').count() === 1, 'SS1: in France, ALDI is ALDI Nord’s');
await open('ss/?scenario=unlisted');
check(await page.locator('[data-option="SS5"] .card.asks').count() === 0, 'SS5: a store without an app is never asked about');
check(await page.locator('[data-option="SS3"] .privacy').count() >= 1, 'SS3: the nearby page says where the location goes');
for (const sc of scen) {
  await open(`ss/?scenario=${sc}`);
  const chainLists = page.locator('.host [data-dir], .host .picklist, .host [data-card="which"], .host [data-card="suggest"]');
  check(await page.locator('.host .disclaimer').count() > 0 || await chainLists.count() === 0, `SS ${sc}: the store-name disclaimer stands under the chain lists`);
}
const reg = await page.locator('#registry').getAttribute('data-registry');
check(Number(reg) === registry.entries.length, `SS: the registry table shows all ${registry.entries.length} entries`);

// --- Overview, recommendations, a phone-sized screen ----------------------------------------------------------------
for (const lang of ['en', 'de']) {
  await open(lang === 'de' ? '?lang=de' : '');
  check(await page.locator('[data-round-link]').count() === 2, `overview ${lang}: two round links`);
  for (const r of ['OS', 'SS']) {
    const href = await page.locator(`[data-round-link="${r}"]`).getAttribute('href');
    check(href.startsWith(`${r.toLowerCase()}/`), `overview ${lang}: ${r} links to its page`);
    check(!/<!-- pick: \w+ -->/.test(await page.locator(`[data-round-link="${r}"]`).innerText()), `overview ${lang}: ${r} card renders`);
  }
  if (lang === 'en') await page.screenshot({ path: join(shots, 'overview.png') });
}
for (const r of ['os', 'ss']) {
  const en = readFileSync(join(dir, r, 'RECOMMENDATION.md'), 'utf8');
  const de = readFileSync(join(dir, r, 'RECOMMENDATION.de.md'), 'utf8');
  const pick = (s) => [s.match(/<!-- pick: (\w+) -->/)?.[1], s.match(/<!-- runner-up: (\w+) -->/)?.[1]];
  check(pick(en)[0] && pick(en).join() === pick(de).join(), `${r}: the same pick and runner-up in both RECOMMENDATION files`);
  check(new RegExp(`^${r.toUpperCase()}`).test(pick(en)[0] ?? ''), `${r}: the pick is one of the round’s options`);
}
const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
const pp = await phone.newPage();
for (const path of ['', 'os/', 'ss/', 'os/?ts=310', 'ss/?lang=de&theme=dark']) {
  await pp.goto(`${url}${base}${path}`);
  await pp.waitForSelector('body[data-ready]');
  const sideways = await pp.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  check(!sideways, `390 px phone: ${path || 'overview'} does not scroll sideways`);
}
await pp.goto(`${url}${base}os/`);
await pp.waitForSelector('body[data-ready]');
await pp.screenshot({ path: join(shots, 'OS-phone-390x844.png') });
await phone.close();

// The measured numbers must match measured.json and the tables in both RECOMMENDATION files.
const mfile = join(dir, 'measured.json');
const fresh = JSON.stringify(measured, null, 1);
if (write) writeFileSync(mfile, `${fresh}\n`);
check(existsSync(mfile) && JSON.stringify(JSON.parse(readFileSync(mfile, 'utf8')), null, 1) === fresh, 'measured.json matches this run (rerun with --write after a change)');
for (const r of ['os', 'ss']) {
  for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
    const src = readFileSync(join(dir, r, f), 'utf8');
    if (r === 'os') {
      for (const [id, v] of Object.entries(measured.OS[100])) {
        const row = src.split('\n').find((l) => l.startsWith(`| **${id}**`) || l.startsWith(`| ${id} `));
        const cut = measured.OS[310][id].cut;
        check(row && row.includes(`+${v.extra} px`) && row.includes(`${v.rows} (${v.todayRows})`) && row.includes(`px | ${cut} |`), `${r}/${f}: ${id} row says +${v.extra} px, ${v.rows} (${v.todayRows}) rows and ${cut} names cut at 310 %`);
      }
    } else {
      for (const [id, v] of Object.entries(measured.SS)) {
        const row = src.split('\n').find((l) => l.startsWith(`| **${id}**`) || l.startsWith(`| ${id} `));
        check(row && scen.every((sc) => row.includes(`| ${v[sc]} |`) || row.includes(`| ${v[sc]} `)), `${r}/${f}: ${id} row has the taps ${scen.map((sc) => v[sc]).join('/')}`);
      }
    }
  }
}

check(errors.length === 0, `no page errors (${errors.slice(0, 3).join(' | ')})`);
await browser.close();
server.close();
if (fails.length) {
  console.log(`${fails.length} of ${n} checks failed`);
  process.exit(1);
}
console.log(`all checks passed (${n})`);
