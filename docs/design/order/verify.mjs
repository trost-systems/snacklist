// Drives round IO in Chromium and checks what the page claims. Its last line is `all checks passed (N)`.
//   node docs/design/order/verify.mjs [<root>] [--path /docs/design/order/] [--write]
// --write stores the measured rows in io/measured.json (with the pick and runner-up read from RECOMMENDATION.md).
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './tools/serve.mjs';
import { generate } from './tools/strings.mjs';
import { catOf, fix, initial, orderOf, walk } from './model.js';
import { ids, options } from './options.js';
import { fixPath, ikeaCost } from './paths.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const pathArg = args.includes('--path') ? args[args.indexOf('--path') + 1] : '/docs/design/order/';
const rootArg = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--path');
const root = resolve(rootArg ?? join(here, '../../..'));
const dir = join(root, pathArg);
const write = args.includes('--write');
const pwDir = [join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');

let n = 0;
const fails = [];
const check = (ok, what) => {
  n += 1;
  if (!ok) {
    fails.push(what);
    console.log(`FAIL ${what}`);
  }
};

// The ARB words are the app's own.
const arbDir = [join(root, 'app/l10n'), join(here, '../../../app/l10n')].find((d) => existsSync(d));
check(readFileSync(join(dir, 'strings.js'), 'utf8') === generate(arbDir), 'strings.js equals the ARB files (node tools/strings.mjs)');

const { server, url } = await serve(root);
const browser = await chromium.launch();
const configs = [['ios', 100], ['ios', 200], ['ios', 310], ['android', 100], ['android', 200]];
const measured = { en: {}, de: {} };
const all = ['today', ...ids];

// Rows wholly visible between the top bar and the add field, in a frame; and the rows' offsets from the screen top.
const geometry = (page, sel) => page.locator(sel).evaluate((ph) => {
  const screen = ph.querySelector('.screen').getBoundingClientRect();
  const bar = ph.querySelector('[data-topbar] .switcher').getBoundingClientRect().bottom;
  const field = ph.querySelector('[data-addfield]').getBoundingClientRect().top;
  const rows = [...ph.querySelectorAll('.item')].map((r) => ({ id: r.dataset.row, top: r.getBoundingClientRect().top - screen.top, bottom: r.getBoundingClientRect().bottom - screen.top }));
  const whole = rows.filter((r) => r.top >= bar - screen.top - 1 && r.bottom <= field - screen.top + 1);
  const wide = [...ph.querySelectorAll('.screen *')].filter((e) => e.getBoundingClientRect().right > ph.getBoundingClientRect().right + 1 && !e.closest('.scroll') && !e.closest('.menu'));
  return { whole: whole.map((r) => r.id), rows, fieldTop: field - screen.top, barBottom: bar - screen.top, fieldFromBottom: screen.bottom - field, wide: wide.length, heads: ph.querySelectorAll('.cat').length, gaps: ph.querySelectorAll('[data-gap]').length };
});
const sectionOrder = (page, sel, store) => page.locator(sel).evaluate((ph, st) => [...ph.querySelectorAll(`[data-store="${st}"] .item`)].map((r) => r.dataset.row), store);

for (const lang of ['en', 'de']) {
  for (const [device, ts] of configs) {
    const page = await browser.newPage({ viewport: { width: 2400, height: 1400 } });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const q = new URLSearchParams({ ...(lang === 'de' ? { lang } : {}), ...(ts !== 100 ? { ts: String(ts) } : {}), ...(device === 'android' ? { device } : {}) });
    await page.goto(`${url}${pathArg}io/?${q}`);
    await page.waitForSelector('body[data-ready]');
    const tag = `${lang} ${device} ${ts} %`;
    measured[lang][device] ??= {};
    measured[lang][device][ts] = {};
    for (const id of all) {
      const sel = `#${id} [data-frame="top"] .phone`;
      const g = await geometry(page, sel);
      measured[lang][device][ts][id] = g.whole.length;
      check(g.wide === 0, `${tag} ${id}: nothing sticks out of the phone`);
      const s = initial(options[id].kind, lang);
      check(JSON.stringify(await sectionOrder(page, sel, 'edeka')) === JSON.stringify(orderOf(s, options[id].kind, 'edeka')), `${tag} ${id}: EDEKA rows in the model's order`);
      if (id === 'today') check(g.heads > 0, `${tag} Today shows category heads`);
      else if (id !== 'IO5') check(g.heads === 0 && g.gaps === 0, `${tag} ${id}: no category heads or gaps`);
      else check(g.heads === 0 && g.gaps > 0, `${tag} IO5 hidden: gaps, no heads`);
      if (ts === 100) check(g.whole.length >= 3, `${tag} ${id}: at least 3 whole rows on the first screen`);
      else check(g.whole.length >= 1, `${tag} ${id}: at least 1 whole row on the first screen`);
    }
    // Every frame, the sheets and the stores screen included: nothing wider than the phone.
    const frameCount = await page.locator('figure[data-frame] .phone').count();
    for (let k = 0; k < frameCount; k += 1) {
      const fr = page.locator('figure[data-frame] .phone').nth(k);
      const name = await fr.evaluate((ph) => `${ph.closest('section').id} ${ph.closest('figure').dataset.frame}`);
      const g = await fr.evaluate((ph) => [...ph.querySelectorAll('.screen *')].filter((e) => e.getBoundingClientRect().right > ph.getBoundingClientRect().right + 1 && !e.closest('.scroll') && !e.closest('[data-menu]')).length);
      check(g === 0, `${tag} ${name}: nothing sticks out of the phone`);
    }
    const cats = await geometry(page, '#IO5 [data-frame="cats"] .phone');
    check(cats.heads > 0 && cats.gaps === 0, `${tag} IO5 with the switch on shows heads`);
    measured[lang][device][ts].IO5cats = cats.whole.length;
    // Today against the release web build: the rows' offsets from the screen top (the web build has no status bar).
    const realFile = join(dir, `io/real/${lang}-light-${ts}${device === 'android' ? '-android' : ''}.json`);
    if (existsSync(realFile)) {
      const real = JSON.parse(readFileSync(realFile, 'utf8'));
      const g = await geometry(page, '#today [data-frame="top"] .phone');
      const realRows = real.top.filter((r) => r.role === 'checkbox');
      const tol = ts === 100 ? 3 : 0.05;
      let worst = 0;
      realRows.slice(0, g.rows.length).forEach((r, k) => {
        const mine = g.rows[k];
        if (!mine) return;
        const d = Math.abs(mine.top - r.top);
        worst = Math.max(worst, ts === 100 ? d : d / Math.max(r.top, 1));
      });
      check(worst <= tol, `${tag} Today's rows sit where the release build puts them (worst ${worst.toFixed(ts === 100 ? 1 : 3)}, allowed ${tol})`);
      // The window the rows are counted in is the release build's: the same top bar and add field, the same whole rows.
      check(Math.abs(g.fieldTop - real.fieldTop) <= 3, `${tag} the add field sits where the release build puts it (${Math.round(g.fieldTop)} vs ${Math.round(real.fieldTop)})`);
      check(Math.abs(g.barBottom - real.barBottom) <= 3, `${tag} the top bar ends where the release build's does (${Math.round(g.barBottom)} vs ${Math.round(real.barBottom)})`);
      check(g.whole.length === real.visibleRows.length, `${tag} Today shows as many whole rows as the release build (${g.whole.length} vs ${real.visibleRows.length})`);
      check(Math.abs(real.cats ? Object.keys(real.cats).length : 0) > 0, `${tag} the capture read the categories`);
      if (ts === 100 && device === 'ios') {
        for (const [id, cat] of Object.entries(real.cats)) {
          check(catOf(initial('categorical', lang), id) === cat, `${tag} ${id}: the model's category is the classifier's (${cat})`);
        }
      }
    }
    check(errors.length === 0, `${tag}: no page errors (${errors.join('; ')})`);
    await page.close();
  }
}

// The live phones at 100 % on the iPhone: every fix replayed by real clicks, counted.
for (const lang of ['en', 'de']) {
  const page = await browser.newPage({ viewport: { width: 2400, height: 1400 } });
  await page.goto(`${url}${pathArg}io/${lang === 'de' ? '?lang=de' : ''}`);
  await page.waitForSelector('body[data-ready]');
  for (const id of ids) {
    const o = options[id];
    const live = page.locator(`[data-live-phone="${id}"]`);
    const ph = live.locator('.phone');
    const reset = () => page.locator(`#${id} [data-scene="reset"]`).click();
    await reset();
    const path = fixPath(id, initial(o.kind, lang));
    let clicks = 0;
    for (const a of path) {
      const [verb, arg, arg2] = a.split(':');
      if (verb === 'hold') {
        const row = ph.locator(`[data-row="${arg}"] .nm`);
        await row.scrollIntoViewIfNeeded();
        await row.click({ button: 'right' });
      } else if (verb === 'drop') {
        // As a person would: the list scrolled so the row and its new place are both in view, above the add field.
        await ph.locator('[data-scroll]').evaluate((sc, rid) => { sc.scrollTop = sc.querySelector(`[data-row="${rid}"]`).offsetTop - 200; }, arg);
        const handle = ph.locator(`[data-handle="${arg}"]`);
        await handle.scrollIntoViewIfNeeded();
        const from = await handle.boundingBox();
        const target = await ph.locator(`[data-row="${arg2}"]`).boundingBox();
        await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
        await page.mouse.down();
        for (let k = 1; k <= 8; k += 1) await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2 + ((target.y + target.height / 2 - from.y - from.height / 2) * k) / 8);
        await page.mouse.up();
      } else {
        await ph.locator(a === 'done' ? '[data-sheet] .actions .hexbtn' : `[data-act="${a}"]`).first().click();
      }
      clicks += 1;
    }
    const order = await sectionOrder(page, `[data-live-phone="${id}"] .phone`, 'edeka');
    const before = order[order.indexOf(fix.item) - 1];
    if (o.fix === 'none') {
      check(clicks === 0, `${lang} ${id}: nothing to tap`);
      await page.locator(`#${id} [data-scene="trip"]`).click();
      const after = await sectionOrder(page, `[data-live-phone="${id}"] .phone`, 'edeka');
      check(after.join() === walk.edeka.join(), `${lang} ${id}: after one trip the EDEKA list is the walk`);
    } else if (o.fix === 'category') {
      check(before === 'passata', `${lang} ${id}: a category pick puts Eggs at the end of Pantry (after ${before})`);
    } else {
      check(before === fix.after, `${lang} ${id}: Eggs end right after Flour (after ${before})`);
    }
    check(clicks === path.length, `${lang} ${id}: ${clicks} clicks`);
    check(!(await ph.locator('[data-sheet]').count()), `${lang} ${id}: the sheet closed after the fix`);
    // A new item takes its place without a tap.
    await reset();
    await page.locator(`#${id} [data-scene="add"]`).click();
    const withKetchup = await sectionOrder(page, `[data-live-phone="${id}"] .phone`, 'edeka');
    const k = withKetchup[withKetchup.indexOf('ketchup') - 1];
    check(o.kind === 'learned' ? k === 'flour' : k === 'passata', `${lang} ${id}: Ketchup lands after ${k}`);
    // A tap ticks; in learning options the end of a trip teaches the order of the ticks.
    await reset();
    await ph.locator('[data-row="bananas"] .nm').click();
    check(!(await ph.locator('[data-row="bananas"]').count()), `${lang} ${id}: a tap ticks a row`);
    // Tick Pretzels before Bananas and end the trip: a learning option now starts EDEKA with Pretzels, the others keep their order.
    await reset();
    await ph.locator('[data-scroll]').evaluate((sc) => { sc.scrollTop = sc.querySelector('[data-row="pretzels"]').offsetTop - 200; });
    await ph.locator('[data-row="pretzels"] .nm').click();
    await ph.locator('[data-scroll]').evaluate((sc) => { sc.scrollTop = 0; });
    await ph.locator('[data-row="bananas"] .nm').click();
    await ph.locator('[data-act="endTrip"]').click();
    const afterTrip = await sectionOrder(page, `[data-live-phone="${id}"] .phone`, 'edeka');
    check(o.kind === 'learned' ? afterTrip[0] === 'pretzels' : afterTrip.join() === orderOf(initial(o.kind, lang), o.kind, 'edeka').join(), `${lang} ${id}: the trip's end ${o.kind === 'learned' ? 'teaches its order' : 'changes no order'} (${afterTrip.slice(0, 2).join(', ')})`);
  }
  // IO3: no ticking in sort mode; IO5: the switch.
  await page.locator('#IO3 [data-scene="reset"]').click();
  await page.locator('[data-live-phone="IO3"] [data-act="sortMode"]').click();
  await page.locator('[data-live-phone="IO3"] [data-row="bananas"] .nm').click();
  check(await page.locator('[data-live-phone="IO3"] [data-row="bananas"]').count() === 1, `${lang} IO3: sort mode does not tick`);
  await page.locator('#IO5 [data-scene="reset"]').click();
  await page.locator('[data-live-phone="IO5"] [data-act="screen:stores"]').click();
  await page.locator('[data-live-phone="IO5"] [data-act="showCats"]').click();
  await page.locator('[data-live-phone="IO5"] [data-act="screen:list"]').click();
  check(await page.locator('[data-live-phone="IO5"] .cat').count() > 0, `${lang} IO5: the switch brings the heads back`);
  // New words carry their marker; every other word on the phones comes from strings.js.
  check(await page.locator('#IO5 [data-frame="settings"] [data-proposed="showCategories"].new').count() === 1, `${lang} IO5: the new switch label is marked`);
  await page.close();
}

// Opened on a 390 px phone, the page is no wider than the phone, in both languages.
for (const lang of ['en', 'de']) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(`${url}${pathArg}io/${lang === 'de' ? '?lang=de' : ''}`);
  await page.waitForSelector('body[data-ready]');
  const wide = await page.evaluate(() => document.documentElement.scrollWidth);
  check(wide <= 390, `${lang}: on a 390 px phone the page is ${wide} px wide`);
  await page.close();
}

// The numbers the documents quote.
const doc = (f) => (existsSync(join(dir, f)) ? readFileSync(join(dir, f), 'utf8') : '');
const rec = doc('io/RECOMMENDATION.md');
const recDe = doc('io/RECOMMENDATION.de.md');
const tableRows = (src) => Object.fromEntries(src.split('\n').filter((l) => /^\| \*{0,2}(Today|Heute|IO\d)/.test(l)).map((l) => {
  const c = l.split('|').slice(1, -1).map((x) => x.trim().replace(/\*\*/g, ''));
  return [c[0].split(' ')[0].replace('Heute', 'Today'), c];
}));
for (const [name, src] of [['RECOMMENDATION.md', rec], ['RECOMMENDATION.de.md', recDe]]) {
  const t = tableRows(src);
  for (const id of all) {
    const key = id === 'today' ? 'Today' : id;
    const c = t[key];
    check(Boolean(c), `${name}: a row for ${key}`);
    if (!c) continue;
    const r = measured.en.ios[100][id];
    const rDe = measured.de.ios[100][id];
    check(c[1] === (r === rDe ? String(r) : `${r} (de ${rDe})`), `${name} ${key}: rows on the iPhone at 100 % (${c[1]} vs ${r}/${rDe})`);
    const r310 = measured.en.ios[310][id];
    const r310de = measured.de.ios[310][id];
    check(c[2] === (r310 === r310de ? String(r310) : `${r310} (de ${r310de})`), `${name} ${key}: rows at 310 % (${c[2]})`);
    const ra = measured.en.android[100][id];
    const raDe = measured.de.android[100][id];
    check(c[3] === (ra === raDe ? String(ra) : `${ra} (de ${raDe})`), `${name} ${key}: rows on Android (${c[3]})`);
    const taps = options[id].fix === 'none' ? 0 : fixPath(id, initial(options[id].kind, 'en')).length;
    check(c[4] === String(taps), `${name} ${key}: taps to fix Eggs (${c[4]} vs ${taps})`);
    const ik = ikeaCost(id, 'en');
    const ikDe = ikeaCost(id, 'de');
    const want = ik.taps === null ? '–' : ik.trips ? (name.includes('.de.') ? '0, ein Einkauf' : '0, one trip') : ik.taps === ikDe.taps ? String(ik.taps) : `${ik.taps} (de ${ikDe.taps})`;
    check(c[5] === want, `${name} ${key}: whole IKEA list (${c[5]} vs ${want})`);
  }
}
const pick = /\*\*Pick: (IO\d)/.exec(rec)?.[1];
const runner = /Runner-up: (IO\d)/.exec(rec)?.[1];
check(Boolean(pick && runner), 'RECOMMENDATION.md names a pick and a runner-up');

if (write) {
  writeFileSync(join(dir, 'io/measured.json'), `${JSON.stringify({ pick, runner, ...measured }, null, 1)}\n`);
  console.log('wrote io/measured.json');
} else {
  const saved = JSON.parse(readFileSync(join(dir, 'io/measured.json'), 'utf8'));
  check(JSON.stringify({ en: saved.en, de: saved.de }) === JSON.stringify(measured), 'io/measured.json equals this run (else run with --write)');
  check(saved.pick === pick && saved.runner === runner, 'io/measured.json names the same pick and runner-up');
}

await browser.close();
server.close();
console.log(fails.length ? `${fails.length} of ${n} checks failed` : `all checks passed (${n})`);
process.exit(fails.length ? 1 : 0);
