// Usage: node stores.mjs [distDir] [--port 57650] [--shots dir]
// The landing page's stores card in Chromium (landing.mjs renders it, ../public/stores.js switches
// it): the supermarket's route without JavaScript, each store button's route by click and by
// keyboard, one pressed button at a time (also in forced colours), the list named by the chosen
// store, rows that slide with motion allowed and nothing animating with reduced motion, and no
// console error, and every row and button inside the card from 320 to 1440 px. --shots writes the
// PR screenshots. README.md lists what it proves.
import process from 'node:process';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { parseArgs, serve } from './lib.mjs';

const args = process.argv.slice(2);
const shotsAt = args.indexOf('--shots');
const shots = shotsAt < 0 ? null : args.splice(shotsAt, 2)[1];
process.argv = [process.argv[0], process.argv[1], ...args];
const { dist, port } = parseArgs({ port: 57650 });
if (shots) mkdirSync(shots, { recursive: true });

const ROUTES = {
  de: {
    Wochenmarkt: ['Wochenmarkt', 'Bäckerei', 'Supermarkt', 'Drogerie'],
    Bäckerei: ['Bäckerei', 'Wochenmarkt', 'Supermarkt', 'Drogerie'],
    Supermarkt: ['Supermarkt', 'Wochenmarkt', 'Bäckerei', 'Drogerie'],
    Drogerie: ['Drogerie', 'Wochenmarkt', 'Bäckerei', 'Supermarkt'],
  },
  en: {
    'Farmers’ market': ['Farmers’ market', 'Bakery', 'Supermarket', 'Drugstore'],
    Bakery: ['Bakery', 'Farmers’ market', 'Supermarket', 'Drugstore'],
    Supermarket: ['Supermarket', 'Farmers’ market', 'Bakery', 'Drugstore'],
    Drugstore: ['Drugstore', 'Farmers’ market', 'Bakery', 'Supermarket'],
  },
};

const { origin, close } = await serve(dist, port);
const browser = await chromium.launch();
const problems = [];
let steps = 0;
const expect = (ok, what) => {
  steps++;
  if (!ok) problems.push(what);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

async function open(locale, { width = 390, scheme = 'light', motion = 'reduce', js = true, forced = 'none' } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height: width === 390 ? 844 : 900 }, colorScheme: scheme, reducedMotion: motion, javaScriptEnabled: js, forcedColors: forced });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${origin}/${locale}`);
  const card = page.locator('[data-stores]');
  await card.scrollIntoViewIfNeeded();
  return { page, card, errors, close: () => ctx.close() };
}

// What a visitor gets: the visible rows' names in order, the pressed buttons and the list's
// accessible name. The step numbers are a CSS counter; the screenshots show them.
function state(card) {
  return card.evaluate((el) => {
    const rows = [...el.querySelectorAll('.store-route li')].filter((li) => li.checkVisibility());
    const list = el.querySelector('.store-route');
    return {
      rows: rows.map((li) => li.querySelector('[data-copy-id]').textContent),
      pressed: [...el.querySelectorAll('button[aria-pressed="true"]')].map((b) => b.textContent),
      buttons: el.querySelectorAll('button').length,
      name: document.getElementById(list.getAttribute('aria-labelledby'))?.textContent,
    };
  });
}

for (const locale of ['de', 'en']) {
  const routes = ROUTES[locale];
  const stores = Object.keys(routes);
  const home = stores[2];

  const off = await open(locale, { js: false });
  const first = await state(off.card);
  expect(same(first.rows, routes[home]), `${locale} without JS: rows ${first.rows}, want ${home}'s`);
  expect(same(first.pressed, [home]) && first.buttons === 4, `${locale} without JS: pressed ${first.pressed} of ${first.buttons} buttons`);
  expect(first.name === home, `${locale} without JS: list named ${first.name}`);
  if (shots) await off.card.screenshot({ path: join(shots, `${locale}-390-nojs.png`) });
  await off.close();

  for (const width of [390, 1440]) {
    for (const scheme of ['light', 'dark']) {
      const run = `${locale} ${width} ${scheme}`;
      const { card, errors, close: done } = await open(locale, { width, scheme });
      for (const store of [stores[1], stores[3], stores[0], home]) {
        await card.getByRole('button', { name: store }).click();
        const now = await state(card);
        expect(same(now.rows, routes[store]), `${run} ${store}: rows ${now.rows}`);
        expect(same(now.pressed, [store]), `${run} ${store}: pressed ${now.pressed}`);
        expect(now.name === store, `${run} ${store}: list named ${now.name}`);
        const moved = await card.evaluate((el) => [...el.querySelectorAll('.store-route li')].flatMap((li) => li.getAnimations()).length);
        expect(moved === 0, `${run} ${store}: ${moved} row animations with reduced motion`);
        if (shots) await card.screenshot({ path: join(shots, `${locale}-${width}-${scheme}-${stores.indexOf(store)}.png`) });
      }
      expect(errors.length === 0, `${run}: console ${errors.join(' | ')}`);
      await done();
    }
  }

  const keys = await open(locale);
  await keys.card.getByRole('button', { name: home }).focus();
  await keys.page.keyboard.press('Shift+Tab');
  await keys.page.keyboard.press('Enter');
  const byEnter = await state(keys.card);
  expect(same(byEnter.rows, routes[stores[1]]), `${locale} keyboard: Shift+Tab, Enter shows ${byEnter.rows}`);
  await keys.page.keyboard.press('Shift+Tab');
  await keys.page.keyboard.press('Space');
  const bySpace = await state(keys.card);
  expect(same(bySpace.rows, routes[stores[0]]), `${locale} keyboard: Shift+Tab, Space shows ${bySpace.rows}`);
  await keys.close();

  const forced = await open(locale, { forced: 'active' });
  const faces = await forced.card.evaluate((el) => [...el.querySelectorAll('button')].map((b) => getComputedStyle(b.querySelector('.face'), '::after').backgroundColor));
  expect(new Set(faces).size === 2 && faces.filter((f) => f === faces[2]).length === 1, `${locale} forced colours: faces ${faces}, want the pressed one apart`);
  if (shots) await forced.card.screenshot({ path: join(shots, `${locale}-390-forced.png`) });
  await forced.close();

  const moving = await open(locale, { width: 1440, motion: 'no-preference' });
  await moving.card.getByRole('button', { name: stores[1] }).click();
  const running = await moving.page.evaluate(() => document.querySelectorAll('.store-route li').values().map((li) => li.getAnimations().length).reduce((a, b) => a + b, 0));
  expect(running === 4, `${locale} motion: ${running} rows animate, want 4`);
  await moving.page.waitForFunction(() => document.getAnimations().length === 0, null, { timeout: 2000 }).catch(() => expect(false, `${locale} motion: still animating after 2 s`));
  const settled = await state(moving.card);
  expect(same(settled.rows, routes[stores[1]]), `${locale} motion: rows ${settled.rows}`);
  expect(moving.errors.length === 0, `${locale} motion: console ${moving.errors.join(' | ')}`);
  await moving.close();
}

// Every visible row and button inside the card (sideways: its content box), for every store, at widths around the layout
// switches (600 px viewport, 1000 px two cards a row, the card's own 34rem query) and down to
// 320 px (WCAG 1.4.10), and no horizontal scroll.
const WIDTHS = [320, 340, 360, 390, 480, 600, 601, 700, 800, 960, 1000, 1024, 1100, 1180, 1280, 1440];
for (const locale of ['de', 'en']) {
  for (const width of WIDTHS) {
    const { page, card, close: done } = await open(locale, { width });
    for (const store of Object.keys(ROUTES[locale])) {
      await card.getByRole('button', { name: store }).click();
      const out = await card.evaluate((el) => {
        const layout = el.querySelector('.stores-layout');
        const box = layout.getBoundingClientRect();
        const pad = getComputedStyle(layout);
        const left = box.left + parseFloat(pad.paddingLeft);
        const right = box.right - parseFloat(pad.paddingRight);
        const frame = el.getBoundingClientRect();
        return [...el.querySelectorAll('.store-route li, .store-chip')]
          .filter((e) => e.checkVisibility())
          .map((e) => [e.textContent.trim(), e.getBoundingClientRect()])
          .filter(([, r]) => r.left < left - 0.5 || r.right > right + 0.5 || r.top < frame.top || r.bottom > frame.bottom)
          .map(([name, r]) => `${name} x ${Math.round(r.left)}..${Math.round(r.right)} y ${Math.round(r.top)}..${Math.round(r.bottom)} outside x ${Math.round(left)}..${Math.round(right)} y ${Math.round(frame.top)}..${Math.round(frame.bottom)}`);
      });
      expect(out.length === 0, `${locale} ${width} ${store}: ${out.join('; ')}`);
    }
    const scroll = await page.evaluate(() => {
      const wide = [...document.querySelectorAll('body *')].filter((e) => e.getBoundingClientRect().right > innerWidth + 0.5 && e.checkVisibility());
      const outer = wide.filter((e) => !wide.includes(e.parentElement)).map((e) => `${e.tagName.toLowerCase()}.${[...e.classList].join('.')}`);
      return { px: document.documentElement.scrollWidth - innerWidth, outer };
    });
    expect(scroll.px <= 0, `${locale} ${width}: page scrolls ${scroll.px} px sideways (${scroll.outer.slice(0, 3).join(', ')})`);
    if (shots && [320, 1024].includes(width)) {
      for (const [i, store] of Object.keys(ROUTES[locale]).entries()) {
        await card.getByRole('button', { name: store }).click();
        await card.screenshot({ path: join(shots, `${locale}-${width}-light-${i}.png`) });
      }
    }
    await done();
  }
}

await browser.close();
await close();
if (problems.length > 0) {
  console.error(`stores: ${problems.length} of ${steps} checks failed`);
  for (const p of problems) console.error(`- ${p}`);
  process.exit(1);
}
console.log(`stores: ${steps} checks passed`);
