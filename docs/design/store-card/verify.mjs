// Round SC's checks. Renders every phone in Chromium, compares Today with the release web build (sc/real/), checks each
// option's content rules and its layout at 100 % and 310 % in both languages, themes and phones, screenshots every
// option, recomputes the measurements against sc/measured.json and the tables in RECOMMENDATION(.de).md, and loads
// the page itself. Exits non-zero on any failure; the last line is "all checks passed (n)" when green.
//
//   node docs/design/store-card/verify.mjs [--shots <dir>] [--write] [--dir <built preview root> --path /store-card/]
import process from 'node:process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve } from './tools/serve.mjs';
import { chromium } from '../../../e2e/node_modules/@playwright/test/index.mjs';
import { optionIds, multi } from './phone.mjs';
import { copy } from './copy.mjs';
import { itemsOf, storeById } from './data.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const arg = (n, d) => (args.includes(n) ? args[args.indexOf(n) + 1] : d);
const shots = arg('--shots', '/tmp/p400/shots');
const write = args.includes('--write');
const builtDir = arg('--dir', null);
const base = arg('--path', '/store-card/');
mkdirSync(shots, { recursive: true });

let passed = 0;
const failures = [];
const check = (ok, what) => {
  if (ok) passed += 1;
  else failures.push(what);
};

const { server, url } = await serve(0, builtDir ?? undefined);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, deviceScaleFactor: 2 });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

async function open(qs) {
  await page.goto(`${url}${base}sc/?measure=1&${qs}`);
  await page.waitForFunction(() => document.body.dataset.ready === '1');
  await page.evaluate(() => document.fonts.ready);
}
const show = (o) => page.evaluate((o) => globalThis.show(o), o);
const text = () => page.evaluate(() => document.querySelector('#stage .phone').innerText);
const cardText = () => page.evaluate(() => [...document.querySelectorAll('#stage [data-card]')].map((c) => c.innerText).join('\n'));
const boxes = () => page.evaluate(() => {
  const s = document.querySelector('#stage .screen').getBoundingClientRect().top;
  const pick = (sel) => [...document.querySelectorAll(`#stage ${sel}`)].map((el) => ({ text: el.innerText.replace(/\n/g, ' ').trim(), top: el.getBoundingClientRect().top - s, h: el.getBoundingClientRect().height }));
  return { heads: pick('[data-head]'), rows: pick('[data-row]') };
});

// 1. Today against the release web build: every store header and row the capture has (it records nodes that start
// above 844 px), at the same offsets from the screen's top.
for (const [file, ts, tol, qs] of [['en-100', 1, 2, 'lang=en'], ['en-310', 3.1, 4, 'lang=en'], ['de-100-dark', 1, 2, 'lang=de&theme=dark']]) {
  const real = JSON.parse(readFileSync(join(here, 'sc/real', `${file}.json`), 'utf8'));
  await open(qs);
  for (const [frame, opt] of [['before', 'before'], ['after', 'today']]) {
    await show({ opt, state: 'a', ts });
    const mine = await boxes();
    const realHeads = real[frame].filter((n) => n.role === 'button' && /, \d+ (items?|Artikel)$/.test(n.label));
    const realRows = real[frame].filter((n) => n.role === 'checkbox');
    check(realHeads.length >= 1 && realRows.length >= 3, `calibration ${file} ${frame}: the capture has ${realHeads.length} headers, ${realRows.length} rows`);
    for (const h of realHeads) {
      const name = h.label.split(',')[0];
      const m = mine.heads.find((x) => x.text.startsWith(name));
      check(m && Math.abs(m.top - h.top) <= tol && Math.abs(m.h - h.height) <= tol, `calibration ${file} ${frame}: header ${name} at ${m?.top}/${m?.h}, real ${h.top}/${h.height}`);
    }
    for (const r of realRows) {
      const name = r.label.split('\n')[0];
      const m = mine.rows.find((x) => x.text.includes(name));
      // The web build clips a node's box at the 844 px viewport: a row cut there is at least that tall.
      const cut = r.bottom >= 844 - 0.5;
      check(m && Math.abs(m.top - r.top) <= tol && (cut ? m.h >= r.height - tol : Math.abs(m.h - r.height) <= tol), `calibration ${file} ${frame}: row ${name} at ${m?.top}/${m?.h}, real ${r.top}/${r.height}${cut ? ' (cut at 844)' : ''}`);
    }
  }
}

// 2. Every option in every state, language, theme, text size and phone: content rules and layout.
const money = /€|\$|\d+[.,]\d{2}\b|total|summe|trip|einkauf starten|verlauf|history|price|preis/i;
const measured = { options: {} };
const optsAll = ['today', ...optionIds];
for (const o of optsAll) measured.options[o] = { rows: {}, extra100: 0, extra310: 0, extraC: 0, overflow310: [] };
for (const lang of ['en', 'de']) {
  const a = copy[lang].app;
  for (const theme of ['light', 'dark']) {
    for (const device of ['iphone', 'android']) {
      await open(`lang=${lang}&theme=${theme}&device=${device}`);
      for (const ts of [1, 3.1]) {
        for (const opt of optsAll) {
          for (const state of ['a', 'b', 'c', 'd']) {
            const tag = `${opt} ${state} ${lang} ${theme} ${device} ${ts * 100}%`;
            const m = await show({ opt, state, ts });
            const all = await text();
            const ct = await cardText();
            const done = { a: ['rewe'], b: ['dm'], c: ['rewe', 'lidl'], d: ['netto'] }[state];
            const last = storeById(done.at(-1));
            check(!money.test(all), `${tag}: no prices, totals, trips or log (${all.match(money)?.[0]})`);
            if (opt === 'today') {
              check(m.cards === 0, `${tag}: Today has no card`);
            } else {
              const hidden = 'primary action not in view at scroll top';
              check(m.problems.filter((p) => ts === 3.1 && p === hidden ? false : true).length === 0, `${tag}: layout (${m.problems.join('; ')})`);
              if (ts === 3.1 && m.problems.includes(hidden) && !measured.options[opt].overflow310.includes(`${state} ${lang} ${device}`)) measured.options[opt].overflow310.push(`${state} ${lang} ${device}`);
              check(ct.includes(a.storeAppOpen(last.app)), `${tag}: the card opens ${last.app}`);
              if (ts === 1) check(m.primaryInView === true, `${tag}: "${a.storeAppOpen(last.app)}" in view above the add field at scroll top`);
              const wantCards = state === 'c' && multi[opt] === 'stack' ? 2 : 1;
              check(m.cards === wantCards, `${tag}: ${wantCards} card(s), saw ${m.cards}`);
              if (lang === 'de') check(!/\b(Open|done|items|left|Next|Undo)\b/.test(ct), `${tag}: no English on the German card`);
            }
            if (opt === 'SC1') check(!ct.includes(a.card) && !ct.includes(a.undoTick) && !ct.includes(a.imDone) && !ct.includes(a.next('').trim()), `${tag}: SC1 has no secondary action`);
            if (opt === 'SC2') check(ct.includes(a.card), `${tag}: SC2 shows the customer card action (deep link assumed)`);
            if (opt === 'SC3') check(ct.includes(a.bought(itemsOf(last.id).length, last.name)) && ct.includes(a.undoTick), `${tag}: SC3 counts ${itemsOf(last.id).length} items and offers undo`);
            if (opt === 'SC4') {
              const nextId = { a: 'lidl', b: null, c: 'dm', d: 'lidl' }[state];
              if (nextId) check(ct.includes(a.next(storeById(nextId).name)) && ct.includes(a.left(itemsOf(nextId).length)), `${tag}: SC4 points to ${nextId}`);
              else check(!ct.includes(a.next('').trim()), `${tag}: SC4 has no next row after the last store`);
            }
            if (opt === 'SC5') check(state === 'c' ? ct.includes(a.storesDone(2)) : ct.includes(a.finished(last.name)), `${tag}: SC5 title`);
            if (lang === 'en' && theme === 'light' && device === 'iphone') {
              if (ts === 1 && ['a', 'b', 'c'].includes(state)) measured.options[opt].rows[state] = m.rows;
              if (state === 'a') measured.options[opt][ts === 1 ? 'extra100' : 'extra310'] = m.extra;
              if (state === 'c' && ts === 1) measured.options[opt].extraC = m.extra;
            }
            if (opt !== 'today' && ['a', 'b', 'c'].includes(state) && device === 'iphone' || (opt !== 'today' && state === 'd' && ts === 1 && device === 'iphone')) {
              await page.locator('#stage .phone').screenshot({ path: join(shots, `${opt}-${state}-${lang}-${theme}-${ts === 1 ? 100 : 310}.png`) });
            }
          }
        }
        if (theme === 'light' && device === 'iphone') {
          await show({ opt: 'today', state: 'a', ts });
          await page.locator('#stage .phone').screenshot({ path: join(shots, `today-a-${lang}-light-${ts === 1 ? 100 : 310}.png`) });
          await show({ opt: 'before', state: 'a', ts });
          await page.locator('#stage .phone').screenshot({ path: join(shots, `before-a-${lang}-light-${ts === 1 ? 100 : 310}.png`) });
        }
      }
      // SC2 without a verified deep link hides the action; SC3's undo brings REWE back; SC4's open leaves a snackbar.
      await page.goto(`${url}${base}sc/?measure=1&lang=${lang}&theme=${theme}&device=${device}&links=today`);
      await page.waitForFunction(() => document.body.dataset.ready === '1');
      const m2 = await show({ opt: 'SC2', state: 'a' });
      if (lang === 'en' && theme === 'light' && device === 'iphone') measured.sc2WithoutLink = m2.extra;
      check(!(await cardText()).includes(a.card) && m2.problems.length === 0, `SC2 links=today ${lang} ${theme} ${device}: no customer card action, no dead button`);
      await show({ opt: 'SC3', state: 'a', frame: 'undone' });
      const undone = await page.evaluate(() => [...document.querySelectorAll('#stage [data-sec]')].map((s) => s.dataset.sec));
      check(undone[0] === 'rewe' && (await cardText()) === '', `SC3 undo ${lang} ${theme} ${device}: REWE back first, card gone (${undone})`);
      const m4 = await show({ opt: 'SC4', state: 'a', frame: 'opened' });
      check(m4.cards === 0 && (await text()).includes(a.hidden('REWE')) && (await text()).includes(a.undo), `SC4 open ${lang} ${theme} ${device}: card gone, snackbar with undo`);
      await show({ opt: 'SC4', state: 'f' });
      const dmBelow = await page.evaluate(() => {
        const head = document.querySelector('#stage [data-sec="dm"] [data-head]').getBoundingClientRect();
        return head.top >= document.querySelector('#stage [data-add]').getBoundingClientRect().top;
      });
      const c4 = await cardText();
      check(c4.includes(a.next('dm')) && c4.includes(a.left(3)) && dmBelow, `SC4 below the fold ${lang} ${theme} ${device}: "Next: dm" while dm starts under the add field`);
    }
  }
}
check(errors.length === 0, `no page errors (${errors.join('; ')})`);

// 3. The numbers: sc/measured.json and both RECOMMENDATION tables.
const measuredFile = join(here, 'sc/measured.json');
if (write) writeFileSync(measuredFile, `${JSON.stringify(measured, null, 1)}\n`);
const saved = existsSync(measuredFile) ? JSON.parse(readFileSync(measuredFile, 'utf8')) : null;
check(JSON.stringify(saved) === JSON.stringify(measured), `sc/measured.json matches this run (rerun with --write after a change): ${JSON.stringify(measured.options)}`);
for (const file of ['RECOMMENDATION.md', 'RECOMMENDATION.de.md']) {
  const path = join(here, 'sc', file);
  check(existsSync(path), `${file} exists`);
  const doc = existsSync(path) ? readFileSync(path, 'utf8') : '';
  for (const o of optsAll) {
    const line = doc.split('\n').find((l) => l.startsWith(`| ${o === 'today' ? (file.endsWith('de.md') ? 'Heute' : 'Today') : o} `));
    const cells = line?.split('|').slice(1, -1).map((c) => c.trim()) ?? [];
    const m = measured.options[o];
    const want = [String(m.rows.a), String(m.rows.b), String(m.rows.c), `${m.extra100} px`, `${m.extra310} px`, `${m.extraC} px`];
    check(line && want.every((w, k) => cells[k + 1] === w), `${file}: row ${o} is ${want.join(' | ')}, doc has ${cells.slice(1, 7).join(' | ')}`);
  }
  const o = measured.options;
  for (const [claim, n] of [['SC2 without a link, more than SC1', measured.sc2WithoutLink - o.SC1.extra100], ['SC1 stack per store', o.SC1.extraC - o.SC1.extra100], ['smallest gap to SC1', Math.min(...['SC2', 'SC3', 'SC4', 'SC5'].map((k) => o[k].extra100)) - o.SC1.extra100], ['largest gap to SC1', Math.max(...['SC2', 'SC3', 'SC4', 'SC5'].map((k) => o[k].extra100)) - o.SC1.extra100]]) {
    check(doc.includes(`${n} px`), `${file}: states ${claim} as ${n} px`);
  }
  const qs = doc.match(/^\d+\. \*\*SC-(Q|F)\d+/gm) ?? [];
  check(qs.length >= 7, `${file}: at least 7 numbered open questions SC-Q1.. (${qs.length})`);
  for (const topic of file.endsWith('de.md') ? ['schließt', 'wieder', 'gestapelt', 'Deep Link', 'Anzahl', 'automatisch', 'open-store-app'] : ['dismiss', 'return', 'stack', 'deep link', 'count', 'auto', 'open-store-app']) {
    check(doc.toLowerCase().includes(topic.toLowerCase()), `${file}: covers "${topic}"`);
  }
}

// 4. The page itself, both languages.
for (const lang of ['en', 'de']) {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${url}${base}sc/?lang=${lang}`);
  await page.waitForFunction(() => document.body.dataset.ready === '1');
  const info = await page.evaluate(() => ({ phones: document.querySelectorAll('.frame .phone').length, table: document.querySelectorAll('#measured table.m tbody tr').length, rec: document.querySelector('#rec')?.innerText.length ?? 0, sections: [...document.querySelectorAll('section.opt h2')].map((h) => h.textContent) }));
  check(info.phones === 6 + 5 * 5 + 4, `page ${lang}: ${info.phones} phones`);
  check(info.table === 6, `page ${lang}: measurement table has Today and SC1-SC5`);
  check(info.rec > 1500, `page ${lang}: recommendation rendered`);
  check(optionIds.every((o) => info.sections.some((s) => s.startsWith(o))), `page ${lang}: a section per option`);
  await page.screenshot({ path: join(shots, `page-${lang}.png`) });
}
if (builtDir) {
  const rounds = readFileSync(join(builtDir, 'rounds.js'), 'utf8');
  const at = rounds.indexOf('export const linked = [');
  check(at >= 0 && rounds.indexOf("href: '../store-card/sc/'", at) === rounds.indexOf('href:', at) + 0, 'overview links round SC first (newest)');
}
check(errors.length === 0, `no page errors after the page loads (${errors.join('; ')})`);

await browser.close();
server.close();
for (const f of failures.slice(0, 40)) console.log(`FAIL ${f}`);
if (failures.length) {
  console.log(`${failures.length} of ${failures.length + passed} checks failed`);
  process.exit(1);
}
console.log(`all checks passed (${passed})`);
