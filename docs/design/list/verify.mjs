// Drives round RU in Chromium and checks it. Last line: `all checks passed (N)`, else the failures and exit 1.
// Usage: node docs/design/list/verify.mjs [--dir <built folder> --path /list/]
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import process from 'node:process';
import { measureAll } from './tools/measure.mjs';
import { chromium } from './tools/pw.mjs';
import { check as checkTable } from './tools/rec-table.mjs';
import { serve } from './tools/serve.mjs';
import { generate, proposed } from './tools/strings.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (k, d) => (args.includes(k) ? args[args.indexOf(k) + 1] : d);
const root = resolve(opt('--dir', join(here, '../../..')));
const path = opt('--path', '/docs/design/list/');
const dir = join(root, path);

let passed = 0;
const failed = [];
const ok = (cond, name, detail = '') => {
  if (cond) passed += 1;
  else failed.push(`${name}${detail ? ` -- ${detail}` : ''}`);
};

const arbDir = [join(root, 'app/l10n'), join(here, '../../../app/l10n')].find((d) => existsSync(join(d, 'app_en.arb')));
ok(readFileSync(join(dir, 'strings.js'), 'utf8') === generate(arbDir), 'strings.js equals the ARB files');
const strings = await import(join(dir, 'strings.js'));
for (const key of Object.keys(proposed.en)) {
  for (const lang of ['en', 'de']) ok(typeof strings.proposed[lang]?.[key] === 'string' && strings.proposed[lang][key].length > 0, `proposed string ${key} exists in ${lang}`);
}

const { server, url } = await serve(root);
const base = `${url}${path}`;
const browser = await chromium.launch();

const open = async (q = '', { width = 2400, reducedMotion = 'no-preference' } = {}) => {
  const ctx = await browser.newContext({ viewport: { width, height: 1100 }, reducedMotion });
  const page = await ctx.newPage();
  const errors = [];
  const off = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('request', (r) => { if (!r.url().startsWith(url) && !r.url().startsWith('data:')) off.push(r.url()); });
  page.on('response', (r) => { if (r.status() >= 400) errors.push(`${r.status()} ${r.url()}`); });
  await page.goto(`${base}ru/?${q}`);
  await page.waitForSelector('body[data-ready]', { timeout: 20000 });
  return { page, ctx, errors, off };
};

for (const lang of ['en', 'de']) for (const theme of ['light', 'dark']) for (const ts of [100, 200, 310]) for (const device of ['ios', 'android']) {
  const q = new URLSearchParams({ lang, theme, ts: String(ts), device });
  const { ctx, errors, off } = await open(q.toString());
  ok(errors.length === 0, `page loads without errors (${q})`, errors.join(' | '));
  ok(off.length === 0, `no off-origin requests (${q})`, off.join(' '));
  await ctx.close();
}
{
  const ov = await open('', { width: 2400 });
  const ovPage = await ov.ctx.newPage();
  await ovPage.goto(base);
  await ovPage.waitForSelector('body[data-ready]');
  ok(await ovPage.locator('a.ocard[href^="ru/"]').count() === 1, 'the overview links round RU');
  await ov.ctx.close();
}

for (const lang of ['en', 'de']) {
  const { page, ctx } = await open(`lang=${lang}`, { width: 390 });
  const sw = await page.evaluate(() => document.documentElement.scrollWidth);
  ok(sw <= 390, `page fits 390 px without sideways scroll (${lang})`, `scrollWidth ${sw}`);
  await ctx.close();
}

const ru = ['RU1', 'RU2', 'RU3', 'RU4'];
// A click a person could make; one that cannot happen fails the named check instead of the run.
const click = async (loc, name) => {
  try {
    await loc.click({ timeout: 3000 });
    return true;
  } catch (e) {
    ok(false, name, `cannot click: ${String(e.message).split('\n')[0]}`);
    return false;
  }
};
const rowsIn = (page, sel, attr) => page.locator(`${sel} .phone`).first().evaluate((ph, a) => [...ph.querySelectorAll(`[${a}]`)].filter((e) => e.getBoundingClientRect().height > 0).map((e) => e.getAttribute(a)), attr);

{
  const { page, ctx } = await open();
  for (const id of ru) {
    const vis = await page.locator(`#${id} [data-frame="short-3"] .phone`).evaluate((ph) => [...ph.querySelectorAll('[data-recent]')].map((e) => getComputedStyle(e).display !== 'none' && e.getBoundingClientRect().height > 0));
    ok(vis.length === 3 && vis.every(Boolean), `${id}: the section is expanded by default (short-3 frame)`, `${vis.length} recent rows`);
    const live = await rowsIn(page, `#${id} [data-live-phone]`, 'data-recent');
    ok(live.length === 3, `${id}: the live phone starts expanded`, `${live.length} recent rows`);
    const hex = await page.locator(`#${id}`).evaluate((sec) => [...sec.querySelectorAll('[data-recent-section] *, [data-recent-section], [data-peek] *')].filter((e) => [...e.classList].some((c) => c.includes('hex'))).length);
    ok(hex === 0, `${id}: no hex element in the recent section or peek`, `${hex} found`);
  }
  await ctx.close();
}

// Tick an active item, then one tap on it in the section: it lands first there, then back at its place.
const acceptance = async (reducedMotion) => {
  const { page, ctx } = await open('', { reducedMotion });
  for (const id of ru) {
    const sel = `#${id} [data-live-phone]`;
    const before = await rowsIn(page, sel, 'data-row');
    if (!await click(page.locator(`${sel} [data-row="mince"]`), `${id}: a tick on an active row (${reducedMotion})`)) continue;
    await page.waitForFunction((s) => !document.querySelector(s).dataset.busy && !document.querySelector(`${s} [data-row="mince"]`), sel, { timeout: 3000 }).catch(() => {});
    const afterRows = await rowsIn(page, sel, 'data-row');
    const afterRecent = await rowsIn(page, sel, 'data-recent');
    ok(!afterRows.includes('mince'), `${id}: a tick takes the item off the active rows (${reducedMotion})`);
    ok(afterRecent[0] === 'mince', `${id}: the ticked item is first in the section (${reducedMotion})`, `first is ${afterRecent[0]}`);
    if (!await click(page.locator(`${sel} [data-recent="mince"]`), `${id}: one tap on the ticked item in the section (${reducedMotion})`)) continue;
    const backRows = await rowsIn(page, sel, 'data-row');
    const backRecent = await rowsIn(page, sel, 'data-recent');
    ok(isDeepStrictEqual(backRows, before), `${id}: one tap puts it back at its place (${reducedMotion})`, `${backRows.join(',')} vs ${before.join(',')}`);
    ok(!backRecent.includes('mince'), `${id}: the returned item leaves the section (${reducedMotion})`);
    const hi = await page.locator(`${sel} [data-row="mince"]`).evaluate((e) => e.classList.contains('hi'));
    ok(hi, `${id}: the returned item is highlighted (${reducedMotion})`);
  }
  await ctx.close();
};
await acceptance('no-preference');
await acceptance('reduce');

{
  const { page, ctx } = await open('', { reducedMotion: 'reduce' });
  const sel = '#RU2 [data-live-phone]';
  await page.locator('#RU2 [data-scene="long-15"]').click();
  const pill = page.locator(`${sel} [data-peek]:not([hidden]) [data-peek-pill]`);
  ok(await pill.count() === 1, 'RU2: the peek shows on the long list at the top');
  const pid = await pill.getAttribute('data-peek-pill');
  ok(pid === 'milk', 'RU2: the peek holds the newest item', pid);
  await click(pill, 'RU2: one click on the peek pill');
  const rows = await rowsIn(page, sel, 'data-row');
  const rec = await rowsIn(page, sel, 'data-recent');
  ok(rows.includes('milk') && !rec.includes('milk') && rec.length === 14, 'RU2: one click on the peek pill returns the newest item', `rows ${rows.length}, recent ${rec.length}`);

  await page.locator('#RU4 [data-scene="short-15"]').click();
  ok((await rowsIn(page, '#RU4 [data-live-phone]', 'data-recent')).length === 5, 'RU4: shows the newest 5 before Show all');
  await click(page.locator('#RU4 [data-live-phone] [data-show-all]'), 'RU4: Show all is there to click');
  ok((await rowsIn(page, '#RU4 [data-live-phone]', 'data-recent')).length === 15, 'RU4: Show all reveals all 15');

  await click(page.locator('#RU1 [data-live-phone] [data-head]'), 'RU1: the header is there to click');
  ok((await rowsIn(page, '#RU1 [data-live-phone]', 'data-recent')).length === 0, 'RU1: the header folds the section');
  await page.reload();
  await page.waitForSelector('body[data-ready]');
  ok((await rowsIn(page, '#RU1 [data-live-phone]', 'data-recent')).length === 0, 'RU1: the fold is remembered on this device');
  ok((await page.locator('#RU1 [data-frame="short-3"] [data-recent]').count()) === 3, 'RU1: frames stay open whatever the device remembers');
  await ctx.close();
}

// Large text: rows and chips do not overlap, and no text overflows its row.
for (const q of ['ts=310', 'ts=310&lang=de', 'device=android&ts=200', 'device=android&ts=200&lang=de']) {
  const { page, ctx } = await open(q);
  const bad = await page.evaluate(() => {
    const out = [];
    for (const ph of document.querySelectorAll('.option .phone')) {
      const where = `${ph.closest('.option').id}/${ph.closest('[data-frame]')?.dataset.frame ?? 'live'}`;
      const els = [...ph.querySelectorAll('[data-row], [data-recent]')].filter((e) => e.getBoundingClientRect().height > 0 && !e.classList.contains('checking'));
      for (let i = 1; i < els.length; i += 1) {
        const a = els[i - 1].getBoundingClientRect();
        const b = els[i].getBoundingClientRect();
        const overlap = a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;
        if (overlap) out.push(`${where}: ${els[i - 1].dataset.row ?? els[i - 1].dataset.recent} overlaps ${els[i].dataset.row ?? els[i].dataset.recent}`);
      }
      for (const e of [...els, ...ph.querySelectorAll('[data-recent] .nm, [data-recent] > span:not(.emo), .ruhint, [data-head], .peek, .ppill, .showall')]) {
        if (e.getBoundingClientRect().height === 0) continue;
        if (e.scrollWidth > e.clientWidth + 1 || e.scrollHeight > e.clientHeight + 1) out.push(`${where}: ${e.className || e.tagName} overflows (${e.scrollWidth}x${e.scrollHeight} in ${e.clientWidth}x${e.clientHeight})`);
        const r = e.getBoundingClientRect();
        const s = ph.querySelector('.screen').getBoundingClientRect();
        if (r.left < s.left - 0.5 || r.right > s.right + 0.5) out.push(`${where}: ${e.className || e.tagName} sticks out of the phone`);
      }
    }
    return out;
  });
  ok(bad.length === 0, `no overlapping rows or overflowing text (${q})`, bad.slice(0, 6).join(' | '));
  await ctx.close();
}

// Today's replica against the release build (ru/real/*.json, tools/capture-today.mjs): 3 px.
for (const [lang, ts] of [['en', 100], ['de', 100], ['en', 310], ['de', 310]]) {
  const file = join(dir, `ru/real/${lang}-${ts}.json`);
  if (!existsSync(file)) continue;
  const real = JSON.parse(readFileSync(file, 'utf8'));
  const pick = (k) => real.expanded[k] ?? real.collapsed[k];
  const { page, ctx } = await open(`lang=${lang}&ts=${ts}`);
  const mine = await page.locator('#today [data-frame="scrolled"] .phone').evaluate((ph) => {
    const r = (e) => e.getBoundingClientRect();
    const used = ph.querySelector('.used');
    const rows = [...ph.querySelectorAll('[data-recent]')];
    return { tileHeight: r(used).height, gapAboveTile: r(used).top - r(ph.querySelector('[data-total]')).bottom, usedRowHeight: r(rows[0]).height, tileBottomToFirstUsed: r(rows[0]).top - r(used).bottom };
  });
  for (const k of Object.keys(mine)) {
    const want = pick(k);
    if (typeof want !== 'number') continue;
    ok(Math.abs(mine[k] - want) <= 3, `Today ${k} matches the release build within 3 px (${lang} ${ts} %)`, `replica ${mine[k].toFixed(1)}, real ${want}`);
  }
  await ctx.close();
}

const fresh = await measureAll(browser, base);
const stored = JSON.parse(readFileSync(join(dir, 'ru/measured.json'), 'utf8'));
const { pick: _p, runner: _r, ...storedM } = stored;
ok(isDeepStrictEqual(storedM, fresh), 'ru/measured.json equals a fresh measure', isDeepStrictEqual(storedM, fresh) ? '' : 'run node tools/measure.mjs --write');
for (const f of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
  const bad = checkTable(readFileSync(join(dir, 'ru', f), 'utf8'), fresh);
  ok(bad.length === 0, `${f}'s measured table matches the measure`, bad.slice(0, 4).join(' | '));
}

// The prose quotes measured numbers; each sentence is rebuilt from the fresh measure and must appear verbatim.
const g = (lang, dev, ts, sc, id, f) => fresh[lang][dev][ts][sc][id][f];
const span = (lang, sc, f) => ['RU1', 'RU2', 'RU3', 'RU4'].map((id) => g(lang, 'ios', 100, sc, id, f));
const claims = {
  'RECOMMENDATION.md': [
    `1 open row on the iPhone (${g('en', 'ios', 100, 'long-15', 'RU2', 'active')} instead of ${g('en', 'ios', 100, 'long-15', 'RU1', 'active')})`,
    `2 on Android (${g('en', 'android', 100, 'long-15', 'RU2', 'active')} instead of ${g('en', 'android', 100, 'long-15', 'RU1', 'active')})`,
    `it costs 1 (${g('en', 'ios', 310, 'short-3', 'RU2', 'active')} instead of ${g('en', 'ios', 310, 'short-3', 'RU1', 'active')})`,
    `scroll ${Math.min(...span('en', 'short-3', 'toFirstRecent'))} to ${Math.max(...span('en', 'short-3', 'toFirstRecent'))} px`,
    `${Math.min(...span('en', 'long-15', 'toFirstRecent'))} to ${Math.max(...span('en', 'long-15', 'toFirstRecent'))} px with 11`,
    `(${g('en', 'ios', 100, 'short-15', 'RU4', 'sectionPx')} px against RU1's ${g('en', 'ios', 100, 'short-15', 'RU1', 'sectionPx')} px)`,
    `(${g('en', 'ios', 100, 'short-15', 'RU1', 'sectionPx')} px with 15)`,
    `(${g('en', 'ios', 100, 'short-3', 'RU3', 'sectionPx')} px with 3)`,
    `**Pick: ${stored.pick}`,
    `Runner-up: ${stored.runner}`,
  ],
  'RECOMMENDATION.de.md': [
    `1 offene Zeile (${g('de', 'ios', 100, 'long-15', 'RU2', 'active')} statt ${g('de', 'ios', 100, 'long-15', 'RU1', 'active')})`,
    `auf Android 2 (${g('de', 'android', 100, 'long-15', 'RU2', 'active')} statt ${g('de', 'android', 100, 'long-15', 'RU1', 'active')})`,
    ...(g('de', 'ios', 310, 'short-3', 'RU2', 'active') === g('de', 'ios', 310, 'short-3', 'RU1', 'active') ? [`keine Zeile (RU1 und RU2 zeigen je ${g('de', 'ios', 310, 'short-3', 'RU2', 'active')})`] : ['(RU2 kostet bei 310 % auf Deutsch eine Zeile: Text anpassen)']),
    `${Math.min(...span('de', 'short-3', 'toFirstRecent'))} bis ${Math.max(...span('de', 'short-3', 'toFirstRecent'))} px scrollen`,
    `${Math.min(...span('de', 'long-15', 'toFirstRecent'))} bis ${Math.max(...span('de', 'long-15', 'toFirstRecent'))} px`,
    `(${g('de', 'ios', 100, 'short-15', 'RU4', 'sectionPx')} px statt ${g('de', 'ios', 100, 'short-15', 'RU1', 'sectionPx')} px bei RU1)`,
    `(${g('de', 'ios', 100, 'short-3', 'RU3', 'sectionPx')} px mit 3)`,
    `(${g('de', 'ios', 100, 'short-15', 'RU1', 'sectionPx')} px mit 15)`,
    `**Wahl: ${stored.pick}`,
    `Zweite Wahl: ${stored.runner}`,
  ],
};
for (const [f, want] of Object.entries(claims)) {
  const src = readFileSync(join(dir, 'ru', f), 'utf8');
  for (const c of want) ok(src.includes(c), `${f} quotes the measure: ${c}`);
}
const zeroSame = ['en', 'de'].every((lang) => ['ios', 'android'].every((dev) => ['short-0', 'long-0'].every((sc) => {
  const row = fresh[lang][dev][100][sc];
  return ['RU1', 'RU2', 'RU3', 'RU4'].every((id) => row[id].active === row.today.active && row[id].sectionPx === 0);
})));
ok(zeroSame, 'with 0 recent items every option shows the same open rows as Today and no section');
const neverAtTop = Object.values(fresh).every((d) => Object.values(d).every((t) => Object.values(t).every((sc) => Object.values(sc).every((opts) => Object.values(opts).every((o) => o.recent === 0)))));
ok(neverAtTop, 'no option shows a whole recent row at scroll top (the premise of the pick)');

await browser.close();
server.close();
if (failed.length) {
  for (const f of failed) console.log(`FAIL ${f}`);
  console.log(`${failed.length} checks failed, ${passed} passed`);
  process.exit(1);
}
console.log(`all checks passed (${passed})`);
