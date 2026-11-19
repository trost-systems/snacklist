// Drives round AS in Chromium and checks what the page claims.
// Usage: node verify.mjs [<root>] [--path /docs/design/after-add/] [--write]
// --write stores the measurements in measured.json; without it they must match the file.
import { createRequire } from 'node:module';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { serve } from './tools/serve.mjs';
import { storeCat, verdict } from './walk.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const write = args.includes('--write');
const pathArg = args.includes('--path') ? args[args.indexOf('--path') + 1] : '/docs/design/after-add/';
const root = resolve(args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--path') ?? join(here, '../../..'));
const pwDir = [join(root, 'e2e'), join(here, '../../../e2e'), join(process.env.HOME ?? '', 'family-groceries/e2e')].find((d) => existsSync(join(d, 'node_modules/playwright')));
const { chromium } = createRequire(join(pwDir, 'package.json'))('playwright');

let checks = 0;
const failures = [];
const check = (ok, what) => {
  checks += 1;
  if (!ok) failures.push(what);
};

const { server, url } = await serve(root);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2000, height: 1200 } });
page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
const ids = ['AS1', 'AS2', 'AS3', 'AS4', 'AS5'];
const devices = ['ios', 'android'];
// Each phone's text sizes up to its own largest: iOS 310 %, Android 200 %.
const sizesFor = (device) => (device === 'ios' ? [100, 200, 310] : [100, 200]);
const open = async (q) => {
  await page.goto(`${url}${pathArg}as/?${q}`);
  await page.waitForSelector('body[data-ready]');
};

// Per frame: rows behind the sheet, sheet height, fields in view, small targets, the gap above the field.
const inspect = () =>
  page.evaluate(() => {
    const out = {};
    for (const sec of document.querySelectorAll('section.option, section#today')) {
      const id = sec.id;
      out[id] = [...sec.querySelectorAll('figure.cell .phone:not([data-live])')].map((ph, i) => {
        const box = ph.getBoundingClientRect();
        const kb = ph.querySelector('.kbd')?.getBoundingClientRect();
        const sheet = ph.querySelector('[data-sheet]');
        const sr = sheet?.getBoundingClientRect();
        const status = ph.querySelector('.status').getBoundingClientRect();
        const bottom = kb ? kb.top : box.bottom;
        const fields = [...ph.querySelectorAll('[data-field]')].filter((f) => f.closest('[data-sheet], [data-card]'));
        const hidden = fields
          .filter((f) => {
            const r = f.getBoundingClientRect();
            return r.left < box.left - 0.5 || r.right > box.right + 0.5 || r.top < status.bottom - 0.5 || r.bottom > bottom + 0.5 || (sr && f.closest('[data-sheet]') && r.top < sr.top - 0.5);
          })
          .map((f) => f.dataset.field);
        const content = sheet ? [...sheet.children].reduce((h, c) => Math.max(h, c.getBoundingClientRect().bottom), 0) - sr.top : 0;
        const small = [...ph.querySelectorAll('[data-sheet] [data-act], [data-card] [data-act]')]
          .filter((b) => b.tagName === 'BUTTON' && !b.closest('.nowrap'))
          .filter((b) => {
            const r = b.getBoundingClientRect();
            return r.height < 43.5 || r.width < 43.5;
          })
          .map((b) => b.dataset.act);
        const inputEl = ph.querySelector('[data-sheet] [data-field="input"]');
        let gapAbove = null;
        if (inputEl) {
          const ir = inputEl.getBoundingClientRect();
          const above = [...ph.querySelectorAll('[data-sheet] *')]
            .filter((e) => e.matches('button, input, label, .grab i, .addednote, .flabel'))
            .map((e) => e.getBoundingClientRect())
            .filter((r) => r.height > 0 && r.bottom <= ir.top + 0.5)
            .reduce((m, r) => Math.max(m, r.bottom), sr ? sr.top : ir.top);
          gapAbove = Math.round(ir.top - above);
        }
        return {
          i,
          state: ph.dataset.state,
          rows: ph.querySelectorAll('.list.behind [data-row]').length,
          // The list left above the sheet: room to tap it closed, and rows not cut by the status bar or the sheet.
          freeList: sr ? Math.round(Math.max(0, Math.min(sr.top, ...[...ph.querySelectorAll('.list.behind [data-row], .list.behind [data-card]')].map((e) => e.getBoundingClientRect().top)) - status.bottom)) : null,
          rowsCut: [...ph.querySelectorAll('.list.behind [data-row]')].filter((e) => e.getBoundingClientRect().top < status.bottom - 0.5).length,
          sheetH: sr && kb ? Math.round(kb.top - sr.top) : null,
          // What editing takes from the screen: the sheet, and for AS4 the card above it too.
          editH: sr && kb ? Math.round(kb.top - Math.min(sr.top, ph.querySelector('[data-card]')?.getBoundingClientRect().top ?? sr.top)) : null,
          overflow: sheet ? Math.round(content - sr.height) : 0,
          hidden,
          small,
          gapAbove,
          x: ph.querySelectorAll('[data-x]').length,
          undo: ph.querySelectorAll('[data-undo]').length,
          justAdded: ph.querySelectorAll('[data-just-added]').length,
        };
      });
    }
    return out;
  });

// Frame order in walk.js: open, added, picking, edited, details, typing, second, third, dismiss, closed.
const ADDED = 1;
const measured = { ios: { fits: {} }, android: { fits: {} }, pick: verdict.pick, runner: verdict.runner };
for (const device of devices) {
  const sizes = sizesFor(device);
  const largest = sizes.at(-1);
  for (const id of ids) measured[device].fits[id] = { max: largest, largest };
  for (const ts of sizes) {
    for (const lang of ['en', 'de']) {
      for (const theme of ['light', 'dark']) {
        await open(`device=${device}&ts=${ts}&lang=${lang}&theme=${theme}`);
        const r = await inspect();
        const tag = `${device} ${ts}% ${lang} ${theme}`;
        if (ts === 100 && lang === 'en' && theme === 'light') {
          measured[device].today = { sheetH: r.today[0].sheetH, editH: r.today[0].editH, gapAbove: r.today[0].gapAbove, hidden: r.today[0].hidden };
          check(r.today[0].gapAbove >= 40, `${tag} today: the replica keeps the gap above the field (${r.today[0].gapAbove} px)`);
          check(r.today[0].x === 1 && r.today[0].undo === 1 && r.today[0].justAdded === 1, `${tag} today: the replica shows X, Undo and Just added`);
          check(r.today[0].hidden.includes('brand') && r.today[0].hidden.includes('details'), `${tag} today: brand and details start off screen`);
        }
        for (const id of ids) {
          const fr = r[id];
          check(fr.length === 10, `${tag} ${id}: 10 frames`);
          for (const f of fr) {
            check(f.x === 0 && f.undo === 0 && f.justAdded === 0, `${tag} ${id} frame ${f.i + 1}: no close key, Undo or Just added`);
            if (f.state === 'open') {
              check(f.small.length === 0 || ts > 100, `${tag} ${id} frame ${f.i + 1}: targets under 44 px: ${f.small.join(', ')}`);
            }
          }
          check(fr[0].rows === 0, `${tag} ${id}: the list behind is empty before the first add`);
          check(fr[1].rows === 1 && fr[6].rows === 2 && fr[7].rows === 2, `${tag} ${id}: one row after the first add, then only the last two`);
          check(fr[9].state === 'closed', `${tag} ${id}: the last frame is closed`);
          const a = fr[ADDED];
          const fits = a.hidden.length === 0 && a.overflow <= 1 && fr[3].hidden.length === 0 && fr[3].overflow <= 1;
          if (!fits && measured[device].fits[id].max >= ts) measured[device].fits[id] = { max: sizes[sizes.indexOf(ts) - 1] ?? 0, largest, firstMiss: `${ts}% ${lang}: ${[...a.hidden, ...fr[3].hidden].join(', ') || `sheet overflows ${Math.max(a.overflow, fr[3].overflow)} px`}` };
          if (ts === 100) {
            check(fits, `${tag} ${id}: every field in view after an add (hidden: ${a.hidden.join(', ')}; overflow ${a.overflow})`);
            check(a.gapAbove !== null && a.gapAbove <= 16, `${tag} ${id}: no gap above the field (${a.gapAbove} px)`);
            if (lang === 'en' && theme === 'light') measured[device][id] = { ...measured[device][id], sheetH: a.sheetH, editH: a.editH, gapAbove: a.gapAbove, freeList: fr[6].freeList, rowsCut: fr[6].rowsCut };
            if (lang === 'de' && theme === 'light') measured[device][id] = { ...measured[device][id], editHde: a.editH };
          }
        }
      }
    }
  }
}

// The live phones: the store and category taps as clicks, the options in view without a swipe, both ways to close.
for (const device of devices) {
  for (const id of ids) {
    await open(`device=${device}`);
    const live = page.locator(`[data-live-phone="${id}"]`);
    const field = live.locator('[data-input="text"]');
    await field.fill('Oat');
    await field.press('Enter');
    check((await live.locator('.list.behind [data-row]').count()) === 1, `${device} ${id} live: the add shows one row`);
    let swipes = 0;
    for (const a of storeCat[id]) {
      const target = live.locator(`[data-act="${a}"]`).first();
      const inView = await target.evaluate((el) => {
        const ph = el.closest('.phone').getBoundingClientRect();
        const r = el.getBoundingClientRect();
        return r.left >= ph.left && r.right <= ph.right;
      });
      if (!inView) {
        swipes += 1;
        await target.scrollIntoViewIfNeeded();
      }
      await target.click();
    }
    check(Number(await live.getAttribute('data-taps')) === storeCat[id].length, `${device} ${id} live: store + category took ${storeCat[id].length} taps`);
    const fieldsText = await live.locator('[data-sheet], [data-card]').first().innerText();
    const cardText = id === 'AS4' ? await live.locator('[data-card]').innerText() : fieldsText;
    check(/Lidl/.test(cardText) && /Chilled/.test(cardText), `${device} ${id} live: the fields show Lidl and Chilled`);
    await field.fill('Br');
    await field.press('Enter');
    await live.locator('.list.behind [data-row]').first().click();
    const cur = await live.locator('.list.behind [data-row].cur, [data-card] [data-row]').first().innerText();
    check(/Oat milk/.test(cur), `${device} ${id} live: a tap on the earlier row edits it`);
    measured[device][id].swipes = swipes;
    const free = measured[device][id].freeList;
    if (free >= 44) {
      const listBox = await live.locator('.list.behind').boundingBox();
      await page.mouse.click(listBox.x + listBox.width / 2, listBox.y + 22);
      check((await live.locator('.phone').getAttribute('data-state')) === 'closed', `${device} ${id} live: a tap on the list above closes`);
    }
    await page.locator(`[data-reset="${id}"]`).click();
    await live.locator('[data-input="text"]').fill('E');
    await live.locator('[data-input="text"]').press('Enter');
    const g = await live.locator('[data-grab]').boundingBox();
    await page.mouse.move(g.x + g.width / 2, g.y + g.height / 2);
    await page.mouse.down();
    await page.mouse.move(g.x + g.width / 2, g.y + 120, { steps: 5 });
    await page.mouse.up();
    check((await live.locator('.phone').getAttribute('data-state')) === 'closed', `${device} ${id} live: a swipe down on the grabber closes`);
  }
}

// The overview on a phone.
const small = await browser.newPage({ viewport: { width: 390, height: 844 } });
await small.goto(`${url}${pathArg}`);
await small.waitForSelector('body[data-ready]');
check(await small.evaluate(() => document.documentElement.scrollWidth <= 391), 'overview: no sideways scroll at 390 px');
check((await small.locator('a.ocard').count()) === 1, 'overview: links round AS');

const file = join(here, 'measured.json');
if (write) writeFileSync(file, `${JSON.stringify(measured, null, 1)}\n`);
else check(existsSync(file) && JSON.stringify(JSON.parse(readFileSync(file, 'utf8'))) === JSON.stringify(measured), 'measured.json matches this run (rerun with --write)');

// RECOMMENDATION.md quotes the same numbers.
const recFile = join(here, 'RECOMMENDATION.md');
if (existsSync(recFile)) {
  const rec = readFileSync(recFile, 'utf8');
  for (const id of ['today', ...ids]) {
    const cells = rec.split('\n').find((l) => l.startsWith(`| ${id === 'today' ? 'Today' : id} `))?.split('|').map((c) => c.trim()) ?? [];
    const h = (m) => (m.editHde === undefined || m.editHde === m.editH ? `${m.editH} px` : `${m.editH} px (German ${m.editHde} px)`);
    check(cells[2] === h(measured.ios[id]) && cells[3] === h(measured.android[id]), `RECOMMENDATION.md: ${id}'s heights (${h(measured.ios[id])}, ${h(measured.android[id])})`);
    check(cells[4] === String(storeCat[id].length), `RECOMMENDATION.md: ${id}'s taps`);
  }
} else check(false, 'RECOMMENDATION.md exists');

await browser.close();
server.close();
console.log(JSON.stringify(measured, null, 1));
for (const f of failures) console.log(`FAIL ${f}`);
console.log(failures.length ? `${failures.length} of ${checks} checks failed` : `all checks passed (${checks})`);
process.exit(failures.length ? 1 : 0);
