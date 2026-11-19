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

const onlyOB = process.argv.includes('--only=OB');
const measured = { OS: {}, SS: {} };
const scen = ['migrate', 'new', 'unlisted', 'twocountries', 'country'];
if (!onlyOB) {
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

}

// --- Round OB -------------------------------------------------------------------------------------------------------
const OB = await import(join(dir, 'ob.js'));
const obScen = OB.scenarios.map((x) => x.id);
const obTargets = () => page.evaluate(() => {
  const out = [];
  for (const host of document.querySelectorAll('.host')) {
    const ph = host.querySelector('.phone');
    const z = Number(ph.style.zoom || 1);
    for (const el of ph.querySelectorAll('.checks .check, [data-own], [data-other], [data-confirm], [data-keep], [data-app], .card .textbtn, .sheet .textbtn')) {
      const r = el.getBoundingClientRect();
      if (r.width && (r.height / z < 43.5 || r.width / z < 43.5)) out.push(`${host.dataset.frame}: target ${el.className} ${Math.round(r.width / z)}×${Math.round(r.height / z)}`);
    }
  }
  return out;
});
for (const s of settings) {
  for (const sc of obScen) {
    if ((s.theme === 'dark' || s.lang === 'de') && s.ts === 200) continue;
    const qs = q({ ...s, scenario: sc });
    await open(`ob/?${qs}`);
    for (const p of [...await layout(), ...await obTargets()]) check(false, `OB ${qs}: ${p}`);
    check(true, `OB ${qs} laid out`);
  }
}

// N-292 and the brief: no store-name disclaimer, no "official" or "partner" wording, no location, on any OB phone.
for (const lang of ['en', 'de']) {
  for (const sc of obScen) {
    await open(`ob/?lang=${lang}&scenario=${sc}`);
    const text = (await page.locator('.host').allInnerTexts()).join('\n');
    check(!/trade ?marks|Marken gehören|affiliated|in keiner Verbindung/i.test(text), `OB ${lang} ${sc}: no store-name disclaimer on a phone`);
    check(!/official|partner|offiziell/i.test(text), `OB ${lang} ${sc}: no “official” or “partner” wording`);
    check(await page.locator('.host [data-dialog="loc"], .host .map').count() === 0 && !/location|Standort/i.test(text), `OB ${lang} ${sc}: nothing asks for location`);
  }
}

// The live first phone of every walk: tap the path in drives[], count the taps, read where the phone ends.
const obState = (sel) => page.locator(sel).evaluate((el) => {
  const s = el.phone.s;
  return { screen: s.screen, card: Boolean(s.card), picked: s.picked.map((p) => ({ key: p.key, name: p.name, app: p.app ?? null })), stores: (s.stores ?? []).map((x) => x.link ?? x.name) };
});
for (const opt of OB.options) {
  for (const [sc, path] of Object.entries(OB.drives[opt.id])) {
    await open(`ob/?scenario=${sc}`);
    const sel = `[data-frame="${opt.id}:0"]`;
    const host = page.locator(sel);
    let taps = 0;
    for (const a of path) {
      if (a.fill !== undefined) await host.locator('[data-input="typed"]').last().fill(a.fill);
      else { await host.locator(a.click).first().click(); taps += 1; }
    }
    const st = await obState(sel);
    const [stepTaps, , , later] = OB.metrics[opt.id][sc];
    const claimed = opt.noStep ? later - (sc === 'twoapps' ? 4 : 0) : stepTaps;
    check(taps === claimed, `${opt.id} ${sc}: the live phone took ${taps} taps, the table says ${claimed}`);
    if (opt.noStep) {
      check(st.screen === 'list' && !st.card, `${opt.id} ${sc}: the card is answered and gone (${st.screen}, card ${st.card})`);
      const want = OB.expected.linked[sc];
      check(sc === 'skip' ? st.stores.join() === 'none' || st.stores.length === 1 : JSON.stringify(st.stores) === JSON.stringify(want), `${opt.id} ${sc}: the list ends with ${want} (${st.stores})`);
    } else {
      check(st.screen === 'need', `${opt.id} ${sc}: the step hands over to “What do you need right now?” (${st.screen})`);
      const got = st.picked.map((p) => (opt.id === 'today' ? p.name : p.key ?? p.name));
      const want = opt.id === 'today' ? OB.expected.today[sc] : OB.expected.linked[sc];
      check(JSON.stringify([...got].sort()) === JSON.stringify([...want].sort()), `${opt.id} ${sc}: picked ${got}, expected ${want}`);
      if (opt.id === 'today') check(st.picked.every((p) => p.key === null), `today ${sc}: every store stays a plain name`);
    }
    if (opt.id === 'OB5' && sc === 'twoapps') check(st.picked[0]?.app === 'jö Bonus Club', 'OB5 two apps: jö Bonus Club chosen in the step');
  }
}

// Each walk ends at the table's total, joiners never see a store step, and only OB4 can show the joiner a card.
for (const lang of ['en', 'de']) {
  for (const opt of OB.options) {
    for (const sc of obScen) {
      const fs = OB.walk(opt, sc, lang);
      check(fs[fs.length - 1].taps === OB.totalOf(opt.id, sc), `${opt.id} ${sc}: the walk ends at ${OB.totalOf(opt.id, sc)} taps (${fs[fs.length - 1].taps})`);
      const counted = fs.filter((f) => f.taps !== undefined).map((f) => f.taps);
      check(counted.every((t, i) => i === 0 || t >= counted[i - 1]), `${opt.id} ${sc}: taps never go down along the walk (${counted})`);
      if (sc === 'joiner') {
        check(fs.every((f) => f.state.screen !== 'ob'), `${opt.id} joiner: no store step`);
        check(fs.some((f) => f.state.stores?.every((x) => x.link === 'lidl:DE' || x.link === 'dm:DE' || x.link === 'rewe:DE')), `${opt.id} joiner: the household’s stores arrive linked, with Germany’s apps on an Austrian phone`);
        check(fs.some((f) => f.state.card) === (opt.id === 'OB4'), `${opt.id} joiner: a card only in OB4, and only when nobody answered`);
      }
    }
  }
}
await open('ob/?scenario=twoapps');
check(await page.locator('[data-option="OB5"] [data-app="jö Bonus Club"]').count() >= 1, 'OB5: the step offers BILLA’s second app');
check(await page.locator('[data-option="OB1"] [data-chaincard="billa:AT"] [data-app="jö Bonus Club"]').count() === 1, 'OB1: the store’s screen changes BILLA’s app later');
check(registry.entries.some((e) => e.chain === 'billa' && e.country === 'AT' && e.app.name === OB.appsOf['billa:AT'][0] && /jö Bonus Club/.test(e.note)), 'registry: BILLA’s default app and jö Bonus Club as its alternative');
await open('ob/?scenario=at');
check(await page.locator('[data-frame="OB1:0"] [data-pick="aldi-sued:AT"]').innerText() === 'Hofer', 'OB1 AT: the chip says Hofer, the registry’s name in Austria');
check(await page.locator('[data-frame="today:0"] [data-pick="Hofer"]').count() === 0, 'today AT: no Hofer chip (German chips on every phone)');
check(await page.locator('[data-option="OB1"] [data-suggest] [data-chain="aldi-sued:AT"]').count() === 1, 'OB1: “Hofer” typed on a German phone still finds Austria’s Hofer');
await open('ob/?scenario=unlisted');
check(await page.locator('[data-option="OB1"] .host').last().locator('[data-store="hofladensonnenwiese"] [data-open]').count() === 0, 'OB1: a store of one’s own gets no app key');
for (const sc of ['de', 'at']) {
  await open(`ob/?scenario=${sc}`);
  await page.screenshot({ path: join(shots, `OB-${sc}-en-light-100.png`), fullPage: true });
}

// Measured at 390 × 844: UI words on the screen (chain and app names not counted), and whether Continue (OB4: Done)
// shows without scrolling, on the screen where the user picks for a new user in Germany.
const obMeasured = {};
for (const ts of [100, 200, 310]) {
  for (const lang of ['en', 'de']) {
    obMeasured[`${ts}-${lang}`] = await page.evaluate(async ({ ts, base, lang }) => {
      const P = await import(`${base}phone.js`);
      const O = await import(`${base}ob.js`);
      const out = {};
      for (const opt of [...O.options, O.lean]) {
        const fs = O.walk(opt.id === 'OB1-lean' ? O.options[1] : opt, 'de', lang);
        const f = opt.noStep ? fs[0] : fs.filter((x) => x.state.screen === 'ob').pop();
        const host = document.createElement('div');
        host.style.cssText = 'position:absolute;left:-2000px;top:0';
        document.body.append(host);
        host.innerHTML = P.view(P.initial(opt, { ts, lang, ...structuredClone(f.state) }));
        const ph = host.querySelector('.phone');
        const sc = ph.querySelector('[data-scroll]');
        const zone = opt.noStep ? ph.querySelector('[data-card]') : sc;
        const go = ph.querySelector(opt.noStep ? '[data-done]' : '[data-next]');
        const bottom = opt.noStep ? ph.querySelector('[data-bottom]').getBoundingClientRect().top : sc.getBoundingClientRect().bottom;
        const scroll = go.getBoundingClientRect().bottom > bottom + 0.5;
        zone.querySelectorAll('[data-pick], .sbadge, .appkey').forEach((e) => e.remove());
        const words = zone.innerText.split(/\s+/).filter((x) => /\p{L}/u.test(x)).length;
        host.remove();
        // The first list the user lands on (today: job 313's first question; OB4: its card): items in view above the band.
        const lf = fs.find((x) => x.state.screen === 'list');
        host.innerHTML = P.view(P.initial(opt, { ts, lang, ...structuredClone(lf.state) }));
        document.body.append(host);
        const lp = host.querySelector('.phone');
        const top = lp.querySelector('[data-scroll]').getBoundingClientRect().top;
        const band = lp.querySelector('[data-bottom]').getBoundingClientRect().top;
        const rows = [...lp.querySelectorAll('.item')].filter((r) => { const b = r.getBoundingClientRect(); return b.top >= top - 0.5 && b.bottom <= band + 0.5; }).length;
        host.remove();
        out[opt.id] = { words, scroll, rows };
      }
      return out;
    }, { ts, base, lang });
  }
}
for (const [id, v] of Object.entries(obMeasured['100-en'])) console.log(`OB ${id}: ${v.words} words (de ${obMeasured['100-de'][id].words}), scroll to Continue at 100/200/310 %: ${[100, 200, 310].map((t) => obMeasured[`${t}-en`][id].scroll).join('/')}, first list items in view ${[100, 200, 310].map((t) => obMeasured[`${t}-en`][id].rows).join('/')} (de ${[100, 200, 310].map((t) => obMeasured[`${t}-de`][id].rows).join('/')})`);
const obFile = join(dir, 'ob/measured.json');
const obFresh = JSON.stringify(obMeasured, null, 1);
if (write) writeFileSync(obFile, `${obFresh}\n`);
check(existsSync(obFile) && JSON.stringify(JSON.parse(readFileSync(obFile, 'utf8')), null, 1) === obFresh, 'ob/measured.json matches this run (rerun with --write after a change)');
const yn = (b, de) => (b ? (de ? 'ja' : 'yes') : (de ? 'nein' : 'no'));
for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
  const src = readFileSync(join(dir, 'ob', f), 'utf8');
  const de = f.includes('.de.');
  for (const opt of [...OB.options, OB.lean]) {
    const row = src.split('\n').find((l) => l.startsWith(`| **${opt.id}**`) || l.startsWith(`| ${opt.id} `) || (opt.id === 'today' && /^\| (Today|Heute)/.test(l)));
    const tot = opt.id === 'OB1-lean' ? [] : obScen.map((sc) => OB.totalOf(opt.id, sc));
    if (opt.id !== 'OB1-lean') check(row && obScen.every((sc, i) => row.includes(`| ${tot[i]} |`) || row.includes(`| ${tot[i]} (`)), `ob/${f}: ${opt.id} row has the totals ${tot.join('/')}`);
    const m = obMeasured[`100-${de ? 'de' : 'en'}`][opt.id];
    const sc = [100, 200, 310].map((t) => yn(obMeasured[`${t}-${de ? 'de' : 'en'}`][opt.id].scroll, de)).join(' / ');
    const mrow = src.split('\n').filter((l) => l.startsWith(`| **${opt.id}**`) || l.startsWith(`| ${opt.id} `) || (opt.id === 'today' && /^\| (Today|Heute)/.test(l)))[opt.id === 'OB1-lean' ? 0 : 1];
    const rows = [100, 200].map((t) => obMeasured[`${t}-${de ? 'de' : 'en'}`][opt.id].rows).join(' / ');
    check(mrow && mrow.includes(`| ${m.words} |`) && mrow.includes(sc) && mrow.includes(`| ${rows} |`), `ob/${f}: ${opt.id} measured row says ${m.words} words, scroll ${sc} and ${rows} items in view`);
  }
}

// --- Overview, recommendations, a phone-sized screen ----------------------------------------------------------------
for (const lang of ['en', 'de']) {
  await open(lang === 'de' ? '?lang=de' : '');
  check(await page.locator('[data-round-link]').count() === 3, `overview ${lang}: three round links`);
  for (const r of ['OB', 'OS', 'SS']) {
    const href = await page.locator(`[data-round-link="${r}"]`).getAttribute('href');
    check(href.startsWith(`${r.toLowerCase()}/`), `overview ${lang}: ${r} links to its page`);
    check(!/<!-- pick: \w+ -->/.test(await page.locator(`[data-round-link="${r}"]`).innerText()), `overview ${lang}: ${r} card renders`);
  }
  if (lang === 'en') await page.screenshot({ path: join(shots, 'overview.png') });
}
for (const r of ['ob', 'os', 'ss']) {
  const en = readFileSync(join(dir, r, 'RECOMMENDATION.md'), 'utf8');
  const de = readFileSync(join(dir, r, 'RECOMMENDATION.de.md'), 'utf8');
  const pick = (s) => [s.match(/<!-- pick: (\w+) -->/)?.[1], s.match(/<!-- runner-up: (\w+) -->/)?.[1]];
  check(pick(en)[0] && pick(en).join() === pick(de).join(), `${r}: the same pick and runner-up in both RECOMMENDATION files`);
  check(new RegExp(`^${r.toUpperCase()}`).test(pick(en)[0] ?? ''), `${r}: the pick is one of the round’s options`);
}
const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
const pp = await phone.newPage();
for (const path of ['', 'os/', 'ss/', 'os/?ts=310', 'ss/?lang=de&theme=dark', 'ob/', 'ob/?ts=310&scenario=twoapps', 'ob/?lang=de&theme=dark&scenario=joiner']) {
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
if (!onlyOB) {
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

}

check(errors.length === 0, `no page errors (${errors.slice(0, 3).join(' | ')})`);
await browser.close();
server.close();
if (fails.length) {
  console.log(`${fails.length} of ${n} checks failed`);
  process.exit(1);
}
console.log(`all checks passed (${n})`);
